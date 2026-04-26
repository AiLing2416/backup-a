#!/bin/bash
set -eo pipefail

echo "========================================"
echo "Starting retention policy check at $(date)"
echo "========================================"

# Webhook 通知函数
notify() {
    local status="$1"
    local message="$2"
    if [ -n "$WEBHOOK_URL" ]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"status\": \"$status\", \"message\": \"$message\", \"container\": \"backup-a\", \"task\": \"prune\"}" || true
    fi
}

# 捕获异常退出
trap 'notify "FAILED" "Retention task failed on line $LINENO"; exit 1' ERR

# 应用远程保留策略
RETENTION=${RETENTION_DAYS:-30}

if [ "$RETENTION" -gt 0 ]; then
    echo "Applying Retention Policy: ${RETENTION} days"
    # 遍历 /backup/ 下的目录，因为 rclone 也是按目录存放的
    for dir in /backup/*; do
        if [ -d "$dir" ]; then
            dirname=$(basename "$dir")
            echo "  -> Checking retention for ${dirname}..."
            # 自动删除超过指定天数的文件
            rclone delete "remote:${BUCKET}/${dirname}/" --min-age "${RETENTION}d" -v
            # 清理可能的空目录（忽略错误）
            rclone rmdirs "remote:${BUCKET}/${dirname}/" --leave-root 2>/dev/null || true
        fi
    done
    echo "Retention policy check completed."
    notify "SUCCESS" "Retention policy applied: deleted files older than $RETENTION days."
else
    echo "Retention policy disabled (RETENTION_DAYS=0)."
fi

echo "========================================"
