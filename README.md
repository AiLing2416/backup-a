# backup-a

`backup-a` 是一个面向个人和小型自托管场景的容器化备份方案。它基于 Alpine 构建，使用 Ofelia 负责定时调度，使用 `tar + pigz` 完成分目录压缩，并通过 Rclone 上传到兼容 S3 的对象存储。

## 功能特性

- 基于容器运行，部署简单，适合放在现有 Docker / Compose 环境中长期运行。
- 使用 Ofelia 进行定时调度，支持独立配置备份任务与清理任务的执行时间。
- 自动遍历 `/backup/` 下的一级子目录，并分别生成独立归档文件，便于恢复和管理。
- 使用 `pigz` 进行多线程压缩，默认按 CPU 核数自动计算线程数，上限为 4。
- 备份前执行远端写入自检，提前发现存储桶不可达、凭据错误或无写权限等问题。
- 启动时检查 `/backup/` 下的挂载是否为只读，避免误操作影响源数据。
- 支持通过 `WEBHOOK_URL` 发送成功或失败通知。
- 支持基于 `RETENTION_DAYS` 的远端过期清理。
- 提供 `backup`、`list`、`check`、`prune`、`prune-auto` 等管理命令，便于手动触发和排查。

## 示例配置

默认使用本地构建方式运行：

```yaml
services:
  backup-a:
    build: .
    container_name: backup-a
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - TZ=Asia/Shanghai
      - CRON_SCHEDULE=0 0 2 * * *
      - PRUNE_SCHEDULE=0 30 2 * * *
      - RETENTION_DAYS=30
      - TYPE=s3
      - PROVIDER=Other
      - ENDPOINT=https://s3.us-west-004.backblazeb2.com
      - ACCESS_KEY=${ACCESS_KEY}
      - SECRET_KEY=${SECRET_KEY}
      - BUCKET=${BUCKET}
      - RCLONE_BUFFER_SIZE=16M
      # - PIGZ_THREADS=2
      # - WEBHOOK_URL=https://your-webhook.example.com/notify
    volumes:
      - /opt/data/nextcloud:/backup/nextcloud:ro
      - /opt/data/mysql_dumps:/backup/mysql:ro
```

`.env.example` 可作为变量模板使用：

```dotenv
ACCESS_KEY=your-access-key
SECRET_KEY=your-secret-key
BUCKET=your-bucket-name
```

常用手动命令：

```bash
docker exec backup-a check
docker exec backup-a backup
docker exec backup-a list
docker exec backup-a prune-auto
docker exec -it backup-a prune 7
docker exec backup-a prune 30 -y
```

## 变量说明

| 变量名 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `TZ` | `Asia/Shanghai` | 容器时区。 |
| `CRON_SCHEDULE` | `0 0 2 * * *` | 备份任务的 Ofelia 六段式 cron 表达式。 |
| `PRUNE_SCHEDULE` | `0 30 2 * * *` | 清理任务的 Ofelia 六段式 cron 表达式。 |
| `RETENTION_DAYS` | `30` | 远端保留天数，`0` 表示关闭自动清理。 |
| `TYPE` | `s3` | Rclone 远端类型，常见为 `s3` 或 `b2`。 |
| `PROVIDER` | `Other` | S3 提供商类型，兼容存储通常使用 `Other`。 |
| `ENDPOINT` | 无 | 对象存储接入地址，例如 R2、B2 S3、MinIO。 |
| `ACCESS_KEY` | 无 | 对象存储访问密钥 ID。 |
| `SECRET_KEY` | 无 | 对象存储访问密钥 Secret。 |
| `BUCKET` | 无 | 目标存储桶名称。 |
| `RCLONE_BUFFER_SIZE` | `16M` | Rclone 上传缓冲区大小，低内存环境可适当调小。 |
| `PIGZ_THREADS` | 自动计算 | 压缩线程数；未设置时按 CPU 核心数的 80% 自动计算，上限为 4。 |
| `WEBHOOK_URL` | 空 | 任务完成后发送通知的 Webhook 地址。 |

补充说明：

- `/backup/` 下每个一级子目录会单独生成一个归档文件，命名格式为 `目录名_YYYYMMDD_HHMMSS.tar.gz`。
- `volumes` 挂载到 `/backup/` 的目录必须带 `:ro`，否则容器会在启动时直接退出。
- 当 `TYPE=b2` 时，脚本会按 Backblaze B2 原生方式生成 Rclone 配置。

## 标签说明

当前仓库默认使用 `build: .` 本地构建，因此即使不依赖远程镜像标签，也可以直接部署。

如果你发布预构建镜像，推荐按下面的方式理解和使用标签：

- `latest`：最新可用版本，适合个人项目直接跟随更新。
- `1`：主版本标签，表示同一主版本线上的最新构建。
- `1.0`、`1.1`：固定次版本标签，适合希望在一个较稳定范围内更新的场景。
- `1.0.3`：固定完整版本标签，适合需要精确复现环境的场景。

如果你的目标是省心维护，直接使用 `latest` 或保持本地 `build: .` 都是合理选择；如果你的目标是更强的可重复性，再切换到明确版本标签即可。
