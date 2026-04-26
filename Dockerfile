FROM mcuadros/ofelia:latest AS ofelia

FROM alpine:latest

# 安装必要的基础依赖包
RUN apk add --no-cache \
    bash \
    rclone \
    pigz \
    tar \
    curl \
    tzdata \
    jq \
    coreutils

# 从 ofelia 官方镜像中复制二进制文件
COPY --from=ofelia /usr/bin/ofelia /usr/bin/ofelia

# 创建所需目录
RUN mkdir -p /backup /etc/rclone

# 复制脚本
COPY entrypoint.sh /entrypoint.sh
COPY backup.sh /backup.sh

# 赋予执行权限
RUN chmod +x /entrypoint.sh /backup.sh

# 设定 rclone 配置路径
ENV RCLONE_CONFIG=/etc/rclone/rclone.conf

ENTRYPOINT ["/entrypoint.sh"]