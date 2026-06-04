FROM debian:bookworm-slim

# 设置环境变量，防止交互式安装询问
ENV DEBIAN_FRONTEND=noninteractive

# 更新源并安装编译基础依赖
# 注意：移除了 libffmpeg-dev (如果后续编译报错缺少它，我们将换用 libavcodec-dev)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    meson \
    pkg-config \
    git \
    ca-certificates \
    libmpdclient-dev \
    libflac-dev \
    libvorbis-dev \
    libopus-dev \
    libsqlite3-dev \
    libao-dev \
    libpulse-dev \
    libicu-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 创建输出目录
RUN mkdir -p /output

# 编译 MPD
RUN git clone https://github.com/MusicPlayerDaemon/MPD.git /mpd-src && \
    cd /mpd-src && \
    meson setup build --buildtype=release && \
    ninja -C build && \
    cp build/mpd /output/mpd

# 编译 MPC
RUN git clone https://github.com/MusicPlayerDaemon/mpc.git /mpc-src && \
    cd /mpc-src && \
    meson setup build --buildtype=release && \
    ninja -C build && \
    cp build/mpc /output/mpc
