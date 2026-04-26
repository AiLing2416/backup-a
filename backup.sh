#!/bin/bash
set -eo pipefail

echo "========================================"
echo "Starting backup job at $(date)"
echo "========================================"

# Webhook 通知函数
notify() {
    local status="$1"
    local message="$2"
    if [ -n "$WEBHOOK_URL" ]; then
        echo "Sending webhook notification (Status: $status)..."
        # 发送简单的 JSON 到 Webhook
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"status\": \"$status\", \"message\": \"$message\", \"container\": \"backup-a\"}" || true
    fi
}

# 捕获异常退出，发送失败通知
trap 'notify "FAILED" "Backup job failed on line $LINENO"; exit 1' ERR

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DETAILS=""

# 计算 PIGZ_THREADS
if [ -z "$PIGZ_THREADS" ]; then
    threads=$(nproc)
    calc=$(( threads * 80 / 100 ))
    if [ "$calc" -gt 4 ]; then
        calc=4
    elif [ "$calc" -lt 1 ]; then
        calc=1
    fi
    PIGZ_THREADS=$calc
    echo "[Backup] Calculated PIGZ_THREADS: $PIGZ_THREADS (80% of $threads, max 4)"
else
    echo "[Backup] Using provided PIGZ_THREADS: $PIGZ_THREADS"
fi

echo "[Backup] Pre-flight check: Verifying remote bucket connectivity and write access before compression..."
if ! echo "ping" | rclone rcat "remote:${BUCKET}/.backup_ping.txt"; then
    echo "ERROR: Pre-flight check failed. Cannot write to remote:${BUCKET}."
    exit 1
fi
rclone delete "remote:${BUCKET}/.backup_ping.txt" || true
echo "[Backup] Pre-flight check passed."

# 遍历 /backup/ 目录下的所有子目录并进行分别打包
for dir in /backup/*; do
    # 确保是目录
    if [ -d "$dir" ]; then
        dirname=$(basename "$dir")
        archive_name="${dirname}_${TIMESTAMP}.tar.gz"
        tmp_archive="/tmp/$archive_name"
        
        echo "[Backup] Directory: $dirname"
        echo "  -> Compressing to $tmp_archive using $PIGZ_THREADS threads..."
        
        # 使用 tar 和 pigz 进行多线程压缩
        tar -cf - -C /backup "$dirname" | pigz -p "$PIGZ_THREADS" > "$tmp_archive"
        
        echo "  -> Uploading to remote:${BUCKET}/${dirname}/..."
        # 使用 rclone 复制到远程桶，存放在各自的子目录下
        rclone copy "$tmp_archive" "remote:${BUCKET}/${dirname}/" -v
        
        echo "  -> Cleaning up local temporary archive..."
        rm -f "$tmp_archive"
        
        DETAILS="${DETAILS} ${dirname} (success);"
        echo "[Backup] $dirname completed."
    fi
done

echo "========================================"
echo "Backup job completed successfully at $(date)"
notify "SUCCESS" "Backup completed. Details: $DETAILS"
