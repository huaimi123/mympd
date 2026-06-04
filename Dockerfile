FROM debian:bookworm-slim

# 设置环境变量，防止安装时出现交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 安装所有必要的编译依赖
# 包含了 MPD 编译所必需的库：Boost、FFmpeg、systemd、yajl 等
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
    libsystemd-dev \
    libboost-dev \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    zlib1g-dev \
    libyajl-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 创建输出目录
RUN mkdir -p /output

# 编译 MPD
# 使用 --wrap-mode=nofallback 确保它使用系统库而不是尝试下载外部依赖
RUN git clone https://github.com/MusicPlayerDaemon/MPD.git /mpd-src && \
    cd /mpd-src && \
    meson setup build --buildtype=release --wrap-mode=nofallback && \
    ninja -C build && \
    cp build/mpd /output/mpd

# 编译 MPC
RUN git clone https://github.com/MusicPlayerDaemon/mpc.git /mpc-src && \
    cd /mpc-src && \
    meson setup build --buildtype=release --wrap-mode=nofallback && \
    ninja -C build && \
    cp build/mpc /output/mpc

# 保持容器运行
CMD ["tail", "-f", "/dev/null"]
