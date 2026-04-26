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
# 针对变量尽量简化的需求，直接映射用户传入的 ACCESS_KEY 等变量
mkdir -p /etc/rclone
cat <<EOF > /etc/rclone/rclone.conf
[remote]
type = ${TYPE:-s3}
provider = ${PROVIDER:-}
env_auth = false
access_key_id = ${ACCESS_KEY}
secret_access_key = ${SECRET_KEY}
endpoint = ${ENDPOINT}
EOF
echo "[Init] Generated rclone.conf"

echo "[Init] Pre-flight check: Verifying remote bucket connectivity and write access..."
if ! echo "ping" | rclone rcat "remote:${BUCKET}/.backup_ping.txt"; then
    echo "ERROR: Failed to write to remote:${BUCKET}. Please check your credentials, endpoint, and bucket permissions."
    exit 1
fi
rclone deletefile "remote:${BUCKET}/.backup_ping.txt" || true
echo "[Init] Pre-flight check passed. Remote bucket is accessible and writable."

# 生成 ofelia 配置
# 默认使用 0 0 2 * * * (每日凌晨2点) 如果没有提供 CRON_SCHEDULE 变量的话
CRON_SCHEDULE=${CRON_SCHEDULE:-"0 0 2 * * *"}
cat <<EOF > /etc/ofelia.conf
[job-local "backup-job"]
schedule = ${CRON_SCHEDULE}
command = /backup.sh
EOF
echo "[Init] Generated ofelia.conf with schedule: $CRON_SCHEDULE"

# 启动 ofelia 调度器
echo "[Init] Starting Ofelia scheduler..."
exec ofelia daemon --config /etc/ofelia.conf
