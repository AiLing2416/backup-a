#!/bin/bash
set -e

echo "[Init] Initializing backup-a container..."

# 检查 /backup/ 下的挂载点是否全部为只读 (ro)
echo "[Init] Checking mount permissions for /backup/..."
# 使用 awk 过滤 /proc/mounts 中的 /backup/ 挂载，检查选项是否包含 ro
non_ro=$(awk '$2 ~ /^\/backup\// {if ($4 !~ /(^|,)ro(,|$)/) print $2}' /proc/mounts)
if [ -n "$non_ro" ]; then
    echo "ERROR: The following mounts are NOT read-only:"
    echo "$non_ro"
    echo "CRITICAL: Please use ':ro' in your volume mounts (e.g., -v /host:/backup/target:ro). Exiting for safety."
    exit 1
fi
echo "[Init] All /backup/ mounts are read-only."

# 生成 rclone 配置
mkdir -p /etc/rclone
if [ "${TYPE}" = "b2" ]; then
    cat <<EOF > /etc/rclone/rclone.conf
[remote]
type = b2
account = ${ACCESS_KEY}
key = ${SECRET_KEY}
hard_delete = true
EOF
else
    # 自动尝试从 Endpoint 提取 Region (针对 B2 S3 特别有用)
    REGION=""
    if [[ "$ENDPOINT" =~ s3\.([a-z0-9-]+)\.backblazeb2\.com ]]; then
        REGION="${BASH_REMATCH[1]}"
    fi

    # 默认为 S3 兼容模式
    cat <<EOF > /etc/rclone/rclone.conf
[remote]
type = ${TYPE:-s3}
provider = ${PROVIDER:-}
env_auth = false
access_key_id = ${ACCESS_KEY}
secret_access_key = ${SECRET_KEY}
endpoint = ${ENDPOINT}
region = ${REGION}
no_check_bucket = true
EOF
fi
echo "[Init] Generated rclone.conf (Type: ${TYPE:-s3}, Region: ${REGION:-auto})"

echo "[Init] Pre-flight check: Verifying remote bucket connectivity and write access..."
if ! echo "ping" | rclone rcat "remote:${BUCKET}/.backup_ping.txt"; then
    echo "ERROR: Failed to write to remote:${BUCKET}. Please check your credentials, endpoint, and bucket permissions."
    exit 1
fi
rclone delete "remote:${BUCKET}/.backup_ping.txt" || true
echo "[Init] Pre-flight check passed. Remote bucket is accessible and writable."

# 生成 ofelia 配置
# 默认使用 0 0 2 * * * (每日凌晨2点) 如果没有提供 CRON_SCHEDULE 变量的话
CRON_SCHEDULE=${CRON_SCHEDULE:-"0 0 2 * * *"}
# 预设清理任务在备份开始后 30 分钟执行 (假设是 0 30 2 * * *)
PRUNE_SCHEDULE=${PRUNE_SCHEDULE:-"0 30 2 * * *"}

cat <<EOF > /etc/ofelia.conf
[job-local "backup-job"]
schedule = ${CRON_SCHEDULE}
command = /backup.sh

[job-local "prune-job"]
schedule = ${PRUNE_SCHEDULE}
command = /prune.sh
EOF
echo "[Init] Generated ofelia.conf with backup: $CRON_SCHEDULE and prune: $PRUNE_SCHEDULE"

# 启动 ofelia 调度器
echo "[Init] Starting Ofelia scheduler..."
exec ofelia daemon --config /etc/ofelia.conf
