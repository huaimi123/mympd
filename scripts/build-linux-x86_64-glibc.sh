#!/usr/bin/env bash
# MPD x86_64 glibc 平台构建脚本
set -e

echo "===================================="
echo "构建 MPD linux-x86_64-glibc"
echo "===================================="

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export TARGET_PLATFORM=linux-x86_64-glibc
export TARGET_ARCH=x86_64
export TARGET_LIBC=glibc

# 构建参数
export MPD_VERSION="0.23.15"
export MPC_VERSION="0.45"
export NPROC="${NPROC:-$(nproc)}"

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

# 解压源代码
echo "解压源代码..."
tar -xzf "${DOWNLOAD_DIR}/mpd-${MPD_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xzf "${DOWNLOAD_DIR}/mpc-${MPC_VERSION}.tar.gz" -C "${SRC_DIR}"

# 构建 MPD
echo "构建 MPD..."
cd "${SRC_DIR}/MPD-${MPD_VERSION}"
meson setup "${BUILD_DIR}/mpd" \
    --prefix=/usr \
    --buildtype=release \
    -Dalsa=enabled \
    -Dpulse=enabled \
    -Dpipewire=enabled \
    -Dexpat=enabled \
    -Dcurl=enabled \
    -Dflac=enabled \
    -Dmad=enabled \
    -Dmpg123=enabled \
    -Dvorbis=enabled \
    -Dopus=enabled \
    -Dsndfile=enabled \
    -Dsqlite=enabled \
    -Did3tag=enabled \
    -Dfifo=true \
    -Ddbus=disabled \
    -Dsystemd=disabled \
    -Dipv6=disabled

ninja -C "${BUILD_DIR}/mpd" -j${NPROC}
DESTDIR="${STAGE_DIR}" ninja -C "${BUILD_DIR}/mpd" install

# 构建 MPC
echo "构建 MPC..."
cd "${SRC_DIR}/mpc-${MPC_VERSION}"
meson setup "${BUILD_DIR}/mpc" \
    --prefix=/usr \
    --buildtype=release

ninja -C "${BUILD_DIR}/mpc" -j${NPROC}
DESTDIR="${STAGE_DIR}" ninja -C "${BUILD_DIR}/mpc" install

# 收集构建产物
echo "收集构建产物..."
mkdir -p "${TARGET_DIR}/lib"

# 复制二进制文件
cp "${STAGE_DIR}/usr/bin/mpd" "${TARGET_DIR}/mpd.real"
cp "${STAGE_DIR}/usr/bin/mpc" "${TARGET_DIR}/mpc.real"

# 复制依赖库
ALL_LIBS=$(ldd "${TARGET_DIR}/mpd.real" "${TARGET_DIR}/mpc.real" | grep -o '/[^ ]*\.so[^ ]*' | sort -u)

for lib in $ALL_LIBS; do
    lib_dir=$(dirname "${lib}")
    lib_name=$(basename "${lib}")
    mkdir -p "${TARGET_DIR}${lib_dir}"
    
    if [ -L "${lib}" ]; then
        real_path=$(readlink "${lib}")
        real_lib_dir=$(dirname "${lib}")
        cp "${real_lib_dir}/${real_path}" "${TARGET_DIR}${lib_dir}/${lib_name}"
    elif [ -f "${lib}" ]; then
        cp "${lib}" "${TARGET_DIR}${lib_dir}/${lib_name}"
    fi
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