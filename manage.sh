#!/bin/bash
set -eo pipefail

COMMAND=$1
shift || true

# 确保环境变量存在
if [ -z "$BUCKET" ]; then
    echo "ERROR: BUCKET environment variable is not set."
    exit 1
fi

case "$COMMAND" in
    backup)
        echo "[Manage] Starting manual backup task..."
        /backup.sh
        ;;
    list)
        echo "[Manage] Listing all backups in remote:${BUCKET}..."
        rclone lsf "remote:${BUCKET}" --recursive --format "pt"
        ;;
    check)
        echo "[Manage] Running connectivity and write test to remote:${BUCKET}..."
        if echo "ping" | rclone rcat "remote:${BUCKET}/.manage_ping.txt"; then
            echo "SUCCESS: Remote bucket is accessible and writable."
            rclone deletefile "remote:${BUCKET}/.manage_ping.txt" || true
        else
            echo "FAILURE: Cannot connect or write to bucket. Check your credentials and endpoint."
            exit 1
        fi
        ;;
    prune)
        DAYS=$1
        FORCE=$2
        if [ -z "$DAYS" ]; then
            echo "Usage: manage.sh prune <days> [-y]"
            echo "Example: manage.sh prune 7 (Deletes files older than 7 days)"
            exit 1
        fi
        
        echo "[Manage] Scanning for files older than $DAYS days in remote:${BUCKET}..."
        # 预览即将删除的文件
        FILES_TO_DELETE=$(rclone lsf "remote:${BUCKET}" --min-age "${DAYS}d" --recursive)
        
        if [ -z "$FILES_TO_DELETE" ]; then
            echo "No files found older than $DAYS days."
            exit 0
        fi
        
        echo "The following files will be DELETED:"
        echo "--------------------------------"
        echo "$FILES_TO_DELETE"
        echo "--------------------------------"
        
        if [[ "$FORCE" != "-y" && "$FORCE" != "--yes" ]]; then
            # 如果不是 -y 模式，尝试交互式确认
            # 注意：docker exec 需要配合 -it 才能交互
            read -p "Are you sure you want to delete these files? (y/N): " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo "Aborted."
                exit 0
            fi
        fi
        
        echo "[Manage] Deleting files..."
        rclone delete "remote:${BUCKET}" --min-age "${DAYS}d" -v
        # 清理空目录
        rclone rmdirs "remote:${BUCKET}" --leave-root 2>/dev/null || true
        echo "[Manage] Prune completed successfully."
        ;;
    *)
        echo "backup-a Management Tool"
        echo "Usage: manage.sh {backup|list|check|prune}"
        echo ""
        echo "Commands:"
        echo "  backup             Run the full backup process immediately"
        echo "  list               List all files stored in the remote bucket"
        echo "  check              Test connectivity and write permissions to S3"
        echo "  prune <days> [-y]  Delete files older than specified days"
        echo ""
        echo "Example usage via docker exec:"
        echo "  docker exec backup-a /manage.sh list"
        echo "  docker exec -it backup-a /manage.sh prune 30"
        echo "  docker exec backup-a /manage.sh prune 30 -y"
        exit 1
        ;;
esac
