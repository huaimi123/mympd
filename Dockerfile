FROM debian:bookworm-slim

# 安装工具用于解压 deb 包
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget binutils \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /output

# 下载并提取 mpd 和 mpc 的 deb 包 (Debian Bookworm 源)
# 注意：这会根据容器架构自动下载对应平台的包
RUN apt-get update && \
    apt-get download mpd mpc && \
    ar x mpd_*.deb data.tar.xz && tar -xf data.tar.xz ./usr/bin/mpd && mv usr/bin/mpd /output/mpd && \
    ar x mpc_*.deb data.tar.xz && tar -xf data.tar.xz ./usr/bin/mpc && mv usr/bin/mpc /output/mpc

# 删除临时文件
RUN rm -rf *.deb *.tar.xz usr
