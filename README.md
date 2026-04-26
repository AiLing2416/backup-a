# backup-a 容器化备份方案

基于 Alpine 制作的自动化备份容器，使用 Ofelia 作为任务调度器，并通过 Rclone 同步到支持 S3 协议的存储桶（如 Cloudflare R2）。利用 `pigz` 进行多线程压缩，极大地提升压缩效率。

## 核心特性
- **高度精简**: 基于 Alpine 基础镜像。
- **自动检测并发**: 自动读取宿主机的 CPU 核心数，`pigz` 默认占用 80% 算力（上限为 4 核心），也支持使用 `PIGZ_THREADS` 变量强制指定。
- **强制只读挂载**: 入口脚本会在运行前检查所有挂载到 `/backup/` 下的目录权限，如果发现不是 `:ro` (read-only) 只读挂载，容器将自动退出，保护原数据不受破坏。
- **启动前置自检 (Pre-flight Check)**: 容器在启动时及每次执行备份前，均会向目标存储桶自动发送写入测试。如果配置错误导致连接失败或无写入权限，任务将立即中止，避免空耗 CPU 算力进行无意义的压缩。
- **分目录归档**: 会将 `/backup/` 下的每一个子目录，单独压缩成 `dirname_YYYYMMDD_HHMMSS.tar.gz` 然后推送到目标存储桶对应的目录内。
- **Webhook 状态推送**: 通过 `WEBHOOK_URL` 支持发送 JSON 格式的成功/失败提醒。
- **内置远程留存清理**: 备份完成后会自动使用 Rclone 检查并删除超出 `RETENTION_DAYS` 的旧备份。

## 使用指引

详细变量和配置参考 `docker-compose.yml` 中的内容。

### 手动管理工具 (Manual Management)

容器已将常用管理功能注册为全局命令，您可以直接通过 `docker exec` 调用，无需记忆脚本路径：

| 功能 | 直接执行命令 | 说明 |
| :--- | :--- | :--- |
| **列表查询** | `docker exec backup-a list` | 列出远程存储桶中的所有备份文件 |
| **连通自检** | `docker exec backup-a check` | 手动执行 S3 写入和连通性测试 |
| **立即备份** | `docker exec backup-a backup` | 立即手动触发全量归档备份流程 |
| **手动清理** | `docker exec -it backup-a prune 7` | 交互式确认后删除 7 天前的备份 |
| **静默清理** | `docker exec backup-a prune 30 -y` | 强制删除 30 天前的备份 (无确认) |

### Webhook 负载格式 (JSON)

若配置了 `WEBHOOK_URL`，备份任务成功或失败时都会发送 POST 请求：

\`\`\`json
{
  "status": "SUCCESS", 
  "message": "Backup completed. Details:  nextcloud (success); mysql (success);", 
  "container": "backup-a"
}
\`\`\`
*(如果是失败，status 则为 "FAILED")*
