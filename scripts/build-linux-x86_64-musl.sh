#!/usr/bin/env bash
# MPD x86_64 musl 平台构建脚本（Alpine chroot）
# 修改记录：v2 - 新增 ffmpeg + soxr 支持
#   2026-06-26: 添加 -Dffmpeg=enabled (HLS m3u8 电台 + AAC/APE/WMA/AC3)
#                添加 -Dsoxr=enabled  (高质量重采样)
set -e

echo "===================================="
echo "构建 MPD linux-x86_64-musl"
echo "===================================="

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export TARGET_PLATFORM=linux-x86_64-musl
export TARGET_ARCH=x86_64
export TARGET_LIBC=musl

# 构建参数
export MPD_VERSION="0.23.15"
export MPC_VERSION="0.35"
export NPROC="${NPROC:-4}"

# 源代码下载地址
MPD_URL="https://github.com/MusicPlayerDaemon/MPD/archive/refs/tags/v${MPD_VERSION}.tar.gz"
MPC_URL="https://github.com/MusicPlayerDaemon/mpc/archive/refs/tags/v${MPC_VERSION}.tar.gz"

# 目录设置
WORKSPACE="${SCRIPT_DIR}/workspace/${TARGET_PLATFORM}"
DOWNLOAD_DIR="${WORKSPACE}/downloads"
SRC_DIR="${WORKSPACE}/src"
BUILD_DIR="${WORKSPACE}/build"
STAGE_DIR="${WORKSPACE}/stage"
TARGET_DIR="${WORKSPACE}/target"
ARCHIVE_DIR="${WORKSPACE}/archive"

# 清理并创建目录
rm -rf "${WORKSPACE}"
mkdir -p "${DOWNLOAD_DIR}" "${SRC_DIR}" "${BUILD_DIR}" "${STAGE_DIR}" "${TARGET_DIR}" "${ARCHIVE_DIR}"

# 下载源代码
echo "下载源代码..."
if [ ! -f "${DOWNLOAD_DIR}/mpd-${MPD_VERSION}.tar.gz" ]; then
    curl -L -o "${DOWNLOAD_DIR}/mpd-${MPD_VERSION}.tar.gz" "${MPD_URL}"
fi
if [ ! -f "${DOWNLOAD_DIR}/mpc-${MPC_VERSION}.tar.gz" ]; then
    curl -L -o "${DOWNLOAD_DIR}/mpc-${MPC_VERSION}.tar.gz" "${MPC_URL}"
fi

# 下载瘦身版 ffmpeg 源码（仅音频，无视频/GPU）
FFMPEG_VERSION="6.1.2"
if [ ! -f "${DOWNLOAD_DIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz" ]; then
    curl -L -o "${DOWNLOAD_DIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz" \
      "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
fi

# 解压源代码
echo "解压源代码..."
tar -xzf "${DOWNLOAD_DIR}/mpd-${MPD_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xzf "${DOWNLOAD_DIR}/mpc-${MPC_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xJf "${DOWNLOAD_DIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz" -C "${SRC_DIR}"

# 设置 Alpine x86_64 chroot 环境
CHROOT_DIR="/workspace/chroots/x86_64-musl"
if [ ! -d "${CHROOT_DIR}" ]; then
    echo "错误: chroot 目录不存在，请先创建 chroot 环境"
    exit 1
fi

# ============================================================
# 在 chroot 环境中安装构建依赖 + 编译瘦身版 ffmpeg
# soxr = 高质量重采样器
# ============================================================
echo "检查并安装 chroot 环境中的构建依赖..."
chroot "${CHROOT_DIR}" bash -c "
set -e
apk add --no-cache \
    soxr-dev \
    nasm
"

# 在 chroot 环境中构建
echo "在 chroot 环境中构建 MPD..."
mkdir -p "${CHROOT_DIR}/workspace"
cp "${DOWNLOAD_DIR}"/* "${CHROOT_DIR}/workspace/"
cp -r "${SRC_DIR}"/* "${CHROOT_DIR}/workspace/"

# 在 chroot 中构建 MPD
chroot "${CHROOT_DIR}" bash -c "
set -e
cd /workspace

# 设置构建参数
export MPD_VERSION=\"${MPD_VERSION}\"
export MPC_VERSION=\"${MPC_VERSION}\"
export BUILD_DIR=\"/workspace/build\"
export STAGE_DIR=\"/workspace/stage\"
export NPROC=${NPROC}

mkdir -p \"\${BUILD_DIR}\" \"\${STAGE_DIR}\"

# 编译瘦身版 ffmpeg（仅音频，无视频/GPU）
FFMPEG_DIR=\"/workspace/ffmpeg-${FFMPEG_VERSION}\"
if [ ! -f /usr/local/lib/libavcodec.so ]; then
    echo \"配置 ffmpeg（仅音频解码器 + HLS 流协议）...\"
    cd \"\${FFMPEG_DIR}\"
    ./configure --prefix=/usr/local \\
        --disable-everything \\
        --enable-decoder='mp3*,aac*,vorbis,opus,flac,alac,wmav*,wmapro*,wmalossless,wmavoice' \\
        --enable-decoder='ac3,eac3,dts,truehd,mlp' \\
        --enable-decoder='ape,wavpack*,tta,pcm*,adpcm*' \\
        --enable-decoder='cook,amrnb,amrwb,gsm*,qcelp,atrac*' \\
        --enable-demuxer='mp3,aac,ogg,flac,wav,aiff,matroska,asf,ac3,eac3,dts,hls' \\
        --enable-demuxer='ape,wv,tta,mp4,mov,au,pcm*,w64' \\
        --enable-parser='mpegaudio,aac,vorbis,opus,flac,ac3' \\
        --enable-protocol='file,pipe,data,http,https,tls,crypto' \\
        --enable-filter=aresample \\
        --enable-shared --disable-static --disable-doc --disable-programs
    make -j\${NPROC}
    make install
fi

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:\${PKG_CONFIG_PATH}

# 构建 MPD
echo \"构建 MPD...\"
cd /workspace
cd MPD-\${MPD_VERSION}
meson setup \"\${BUILD_DIR}/mpd\" \\
    --prefix=/usr \\
    --buildtype=release \\
    -Dalsa=enabled \\
    -Dpulse=enabled \\
    -Dpipewire=enabled \\
    -Dexpat=enabled \\
    -Dcurl=enabled \\
    -Dflac=enabled \\
    -Dmad=enabled \\
    -Dmpg123=enabled \\
    -Dvorbis=enabled \\
    -Dopus=enabled \\
    -Dsndfile=enabled \\
    -Dsqlite=enabled \\
    -Did3tag=enabled \\
    -Dfifo=true \\
    -Ddbus=disabled \\
    -Dsystemd=disabled \\
    -Dipv6=disabled \\
    -Dicu=disabled \\
    -Dffmpeg=enabled \\
    -Dsoxr=enabled

ninja -C \"\${BUILD_DIR}/mpd\" -j\${NPROC}
DESTDIR=\"\${STAGE_DIR}\" ninja -C \"\${BUILD_DIR}/mpd\" install

# 构建 MPC
echo \"构建 MPC...\"
cd ../mpc-\${MPC_VERSION}
meson setup \"\${BUILD_DIR}/mpc\" \\
    --prefix=/usr \\
    --buildtype=release

ninja -C \"\${BUILD_DIR}/mpc\" -j\${NPROC}
DESTDIR=\"\${STAGE_DIR}\" ninja -C \"\${BUILD_DIR}/mpc\" install
"

# 收集构建产物
echo "收集构建产物..."
mkdir -p "${TARGET_DIR}/lib"

# 复制 musl libc
cp "${CHROOT_DIR}/lib/ld-musl-x86_64.so.1" "${TARGET_DIR}/lib/"
cp "${CHROOT_DIR}/lib/libc.musl-x86_64.so.1" "${TARGET_DIR}/lib/"

# 复制二进制文件
cp "${CHROOT_DIR}/workspace/stage/usr/bin/mpd" "${TARGET_DIR}/mpd.real"
cp "${CHROOT_DIR}/workspace/stage/usr/bin/mpc" "${TARGET_DIR}/mpc.real"

# 复制依赖库
ALL_LIBS=$(chroot "${CHROOT_DIR}" bash -c "ldd /workspace/stage/usr/bin/mpd /workspace/stage/usr/bin/mpc" | grep -o '/[^ ]*\.so[^ ]*' | sort -u)

for lib in $ALL_LIBS; do
    lib_name=$(basename "${lib}")
    cp -L "${CHROOT_DIR}${lib}" "${TARGET_DIR}/lib/${lib_name}" 2>/dev/null || true
done

# 创建包装脚本
echo "创建包装脚本..."
cat > "${TARGET_DIR}/mpd" << 'EOF'
#!/bin/sh
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="${SELF_DIR}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec "${SELF_DIR}/mpd.real" "$@"
EOF
chmod +x "${TARGET_DIR}/mpd"

cat > "${TARGET_DIR}/mpc" << 'EOF'
#!/bin/sh
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="${SELF_DIR}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec "${SELF_DIR}/mpc.real" "$@"
EOF
chmod +x "${TARGET_DIR}/mpc"

# 创建压缩包
echo "创建压缩包..."
ARCHIVE_PATH="${ARCHIVE_DIR}/mpd-player-${TARGET_PLATFORM}.tgz"
tar -czf "${ARCHIVE_PATH}" -C "${TARGET_DIR}" mpd mpc mpd.real mpc.real lib

echo ""
echo "===================================="
echo "构建完成！"
echo "===================================="
echo "平台: ${TARGET_PLATFORM}"
echo "产物: ${ARCHIVE_PATH}"
echo "大小: $(ls -lh "${ARCHIVE_PATH}" | awk '{print $5}')"
echo "文件数: $(tar -tzf "${ARCHIVE_PATH}" | wc -l)"
echo "===================================="
