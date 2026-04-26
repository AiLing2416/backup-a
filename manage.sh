#!/bin/bash
# set -e removed to prevent silent exits during manual management

# 获取调用时的脚本名称
INVOKED_NAME=$(basename "$0")

# 如果是通过 manage.sh 调用，则第一个参数是命令
# 如果是通过软链接（如 list, backup）直接调用，则命令就是文件名本身
if [[ "$INVOKED_NAME" == "manage.sh" ]]; then
    COMMAND=$1
    shift || true
else
    COMMAND="$INVOKED_NAME"
fi

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
            rclone delete "remote:${BUCKET}/.manage_ping.txt" || true
        else
            echo "FAILURE: Cannot connect or write to bucket. Check your credentials and endpoint."
            exit 1
        fi
        ;;
    prune)
        DAYS=$1
        FORCE=$2
        if [ -z "$DAYS" ]; then
            echo "Usage: prune <days> [-y]"
            echo "Example: prune 7 (Deletes files older than 7 days)"
            exit 1
        fi
        
        echo "[Manage] Scanning for files older than $DAYS days in remote:${BUCKET}..."
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
            # 交互式确认
            read -p "Are you sure you want to delete these files? (y/N): " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo "Aborted."
                exit 0
            fi
        fi
        
        echo "[Manage] Deleting files..."
        rclone delete "remote:${BUCKET}" --min-age "${DAYS}d" -v
        rclone rmdirs "remote:${BUCKET}" --leave-root 2>/dev/null || true
        echo "[Manage] Prune completed successfully."
        ;;
    *)
        if [[ "$INVOKED_NAME" == "manage.sh" ]]; then
            echo "Usage: manage.sh {backup|list|check|prune}"
        else
            echo "Unknown command: $INVOKED_NAME"
        fi
        exit 1
        ;;
esac
