#!/usr/bin/env bash
# 共享构建逻辑：MPD glibc 平台构建（在目标发行版容器内运行）
#
# 设计要点（相对旧脚本的关键修复）：
#   1) 基线锁定：在 Debian 11 (glibc 2.31) 容器内构建，整包 glibc 要求 <= 2.31。
#   2) 不打包 glibc 家族：libc/libm/libpthread 等全部交给宿主，避免"包内旧 glibc
#      + 宿主新库"互相冲突（issue #472 的根因）。
#   3) 依赖库扁平化到 lib/，并用 patchelf 重写 RUNPATH 为 $ORIGIN，杜绝漏到宿主。
#   4) wrapper 仍用 LD_LIBRARY_PATH=lib 启动，宿主 glibc >= 2.31 即可运行。
#   5) 产物内附 buildinfo.txt，记录基线、版本、构建日期，便于排查。
set -euo pipefail

# ============ 版本与基线（可被平台脚本覆盖） ============
export MPD_VERSION="${MPD_VERSION:-0.23.15}"
export MPC_VERSION="${MPC_VERSION:-0.35}"
export FFMPEG_VERSION="${FFMPEG_VERSION:-6.1.2}"
export GLIBC_BASELINE="${GLIBC_BASELINE:-2.31}"
export NPROC="${NPROC:-$(nproc)}"

# ============ 目录 ============
setup_dirs() {
    WORKSPACE="${BUILD_ROOT}/workspace/${TARGET_PLATFORM}"
    DOWNLOAD_DIR="${WORKSPACE}/downloads"
    SRC_DIR="${WORKSPACE}/src"
    BUILD_DIR="${WORKSPACE}/build"
    STAGE_DIR="${WORKSPACE}/stage"
    TARGET_DIR="${WORKSPACE}/target"
    ARCHIVE_DIR="${WORKSPACE}/archive"
    rm -rf "${WORKSPACE}"
    mkdir -p "${DOWNLOAD_DIR}" "${SRC_DIR}" "${BUILD_DIR}" "${STAGE_DIR}" \
        "${TARGET_DIR}/lib" "${ARCHIVE_DIR}"
}

# ============ 安装构建依赖 ============
install_build_deps() {
    echo "==> 安装构建依赖...."
    export DEBIAN_FRONTEND=noninteractive
    export PIP_BREAK_SYSTEM_PACKAGES=1
    apt-get update
    apt-get install -y --no-install-recommends \
        build-essential pkg-config binutils ca-certificates curl file tar xz-utils \
        patchelf nasm yasm zlib1g-dev python3-pip libssl-dev libboost-dev libfmt-dev \
        libasound2-dev libcurl4-openssl-dev libexpat1-dev libflac-dev \
        libmad0-dev libmpg123-dev libogg-dev libopus-dev \
        libpipewire-0.3-dev libpulse-dev libsndfile1-dev libsqlite3-dev \
        libid3tag0-dev libvorbis-dev libmpdclient-dev libsoxr-dev
    apt-get clean
    pip3 install --no-cache-dir "meson==1.2.3" \
        || { echo "pip 安装 meson 失败，回退 apt meson" >&2; \
             apt-get install -y --no-install-recommends meson; }
    pip3 install --no-cache-dir "ninja==1.11.1.1" \
        || { echo "pip 安装 ninja 失败，回退 apt ninja-build" >&2; \
             apt-get install -y --no-install-recommends ninja-build; }
    command -v ninja >/dev/null || { echo "错误：ninja 不可用" >&2; exit 1; }
    command -v meson >/dev/null || { echo "错误：meson 不可用" >&2; exit 1; }
}

# ============ 下载 / 解压源码 ============
download_sources() {
    local mpd_url="https://github.com/MusicPlayerDaemon/MPD/archive/refs/tags/v${MPD_VERSION}.tar.gz"
    local mpc_url="https://github.com/MusicPlayerDaemon/mpc/archive/refs/tags/v${MPC_VERSION}.tar.gz"
    local ffmpeg_url="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"

    [ -f "${DOWNLOAD_DIR}/mpd-${MPD_VERSION}.tar.gz" ] || \
        curl -fsSL -o "${DOWNLOAD_DIR}/mpd-${MPD_VERSION}.tar.gz" "${mpd_url}"
    [ -f "${DOWNLOAD_DIR}/mpc-${MPC_VERSION}.tar.gz" ] || \
        curl -fsSL -o "${DOWNLOAD_DIR}/mpc-${MPC_VERSION}.tar.gz" "${mpc_url}"
    [ -f "${DOWNLOAD_DIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz" ] || \
        curl -fsSL -o "${DOWNLOAD_DIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz" "${ffmpeg_url}"

    tar -xzf "${DOWNLOAD_DIR}/mpd-${MPD_VERSION}.tar.gz" -C "${SRC_DIR}"
    tar -xzf "${DOWNLOAD_DIR}/mpc-${MPC_VERSION}.tar.gz" -C "${SRC_DIR}"
    tar -xJf "${DOWNLOAD_DIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz" -C "${SRC_DIR}"
}

# ============ 编译瘦身版 ffmpeg（仅音频 + HLS + openssl） ============
build_ffmpeg() {
    local ffdir="${SRC_DIR}/ffmpeg-${FFMPEG_VERSION}"
    if [ -f /usr/local/lib/libavcodec.so ]; then
        echo "==> ffmpeg 已安装，跳过"
        return 0
    fi
    echo "==> 编译 ffmpeg v${FFMPEG_VERSION}（仅音频解码器 + HLS + openssl）...."
    cd "${ffdir}"
    ./configure --prefix=/usr/local \
        --disable-everything \
        --enable-decoder='mp3*,aac*,vorbis,opus,flac,alac,wmav*,wmapro*,wmalossless,wmavoice' \
        --enable-decoder='ac3,eac3,dts,truehd,mlp' \
        --enable-decoder='ape,wavpack*,tta,pcm*,adpcm*' \
        --enable-decoder='cook,amrnb,amrwb,gsm*,qcelp,atrac*' \
        --enable-demuxer='mp3,aac,ogg,flac,wav,aiff,matroska,asf,ac3,eac3,dts,hls' \
        --enable-demuxer='ape,wv,tta,mp4,mov,au,pcm*,w64' \
        --enable-parser='mpegaudio,aac,vorbis,opus,flac,ac3' \
        --enable-protocol='file,pipe,data,http,https,tls,crypto' \
        --enable-filter=aresample \
        --enable-openssl \
        --enable-shared --disable-static --disable-doc --disable-programs
    make -j"${NPROC}"
    make install
    echo "/usr/local/lib" > /etc/ld.so.conf.d/ffmpeg.conf
    ldconfig
}

# ============ 构建 MPD ============
build_mpd() {
    echo "==> 构建 MPD v${MPD_VERSION}...."
    export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
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
        -Dipv6=disabled \
        -Dicu=disabled \
        -Dffmpeg=enabled \
        -Dsoxr=enabled
    ninja -C "${BUILD_DIR}/mpd" -j"${NPROC}"
    DESTDIR="${STAGE_DIR}" ninja -C "${BUILD_DIR}/mpd" install
}

# ============ 构建 MPC ============
build_mpc() {
    echo "==> 构建 MPC v${MPC_VERSION}...."
    cd "${SRC_DIR}/mpc-${MPC_VERSION}"
    meson setup "${BUILD_DIR}/mpc" \
        --prefix=/usr \
        --buildtype=release
    ninja -C "${BUILD_DIR}/mpc" -j"${NPROC}"
    DESTDIR="${STAGE_DIR}" ninja -C "${BUILD_DIR}/mpc" install
}

# ============ 排除 glibc 家族（含 loader） ============
# 命中即从 bundle 剔除，运行期交给宿主提供
is_glibc_family() {
    local n="$1"
    case "${n}" in
        ld-*.so.* | ld-linux*.so.*)                     return 0 ;;
        libc.so.6 | libc-*.so)                          return 0 ;;
        libm.so.6 | libm-*.so)                          return 0 ;;
        libmvec.so.1 | libmvec-*.so)                    return 0 ;;
        libpthread.so.0* | libpthread-*.so)             return 0 ;;
        libdl.so.2 | libdl-*.so)                        return 0 ;;
        librt.so.1* | librt-*.so)                       return 0 ;;
        libresolv.so.2 | libresolv-*.so)                return 0 ;;
        libnsl.so.1 | libnsl-*.so)                      return 0 ;;
        libutil.so.1 | libutil-*.so)                    return 0 ;;
        libanl.so.1 | libanl-*.so)                      return 0 ;;
        libnss_*.so.2)                                  return 0 ;;
        libthread_db.so.1 | libthread_db-*.so)          return 0 ;;
        libBrokenLocale.so.1 | libBrokenLocale-*.so)    return 0 ;;
        libSegFault.so | libmemusage.so | libpcprofile.so) return 0 ;;
        *) return 1 ;;
    esac
}

# ============ 收集依赖 + 打包 ============
collect_and_package() {
    echo "==> 收集构建产物...." >&2
    local lib lib_name
    cp "${STAGE_DIR}/usr/bin/mpd"  "${TARGET_DIR}/mpd.real"
    cp "${STAGE_DIR}/usr/bin/mpc"  "${TARGET_DIR}/mpc.real"
    chmod 755 "${TARGET_DIR}/mpd.real" "${TARGET_DIR}/mpc.real"

    # 依赖列表（lsof 输出已经包含完整路径；扁平化到 lib/）
    local all_libs
    all_libs=$(ldd "${TARGET_DIR}/mpd.real" "${TARGET_DIR}/mpc.real" \
        | grep -o '/[^ ]*\.so[^ ]*' | sort -u || true)

    for lib in ${all_libs}; do
        lib_name=$(basename "${lib}")
        cp -L "${lib}" "${TARGET_DIR}/lib/${lib_name}" 2>/dev/null || true
    done

    # 剔除 glibc 家族
    local excluded=0
    for lib in "${TARGET_DIR}/lib/"*; do
        [ -e "${lib}" ] || continue
        if is_glibc_family "$(basename "${lib}")"; then
            echo "   剔除 glibc 家族: $(basename "${lib}")" >&2
            rm -f "${lib}"
            excluded=$((excluded + 1))
        fi
    done
    echo "  已剔除 ${excluded} 个 glibc 家族文件" >&2

    # 校验：lib/ 中不应残留 glibc 家族
    local leftover
    leftover=$(for lib in "${TARGET_DIR}/lib/"*; do
        [ -e "${lib}" ] || continue
        is_glibc_family "$(basename "${lib}")" && echo "$(basename "${lib}")"
    done || true)
    if [ -n "${leftover}" ]; then
        echo "错误：lib/ 仍残留 glibc 家族文件: ${leftover}" >&2
        exit 1
    fi

    # patchelf：所有第三方库 RUNPATH 改为 $ORIGIN
    echo "==> patchelf 重写 RUNPATH 为 \$ORIGIN...." >&2
    for lib in "${TARGET_DIR}/lib/"*.so*; do
        [ -e "${lib}" ] || continue
        patchelf --set-rpath '$ORIGIN' "${lib}" 2>/dev/null || true
    done

    # 创建包装脚本
    echo "==> 创建包装脚本...." >&2
    cat > "${TARGET_DIR}/mpd" << 'EOF'
#!/bin/sh
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="${SELF_DIR}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec "${SELF_DIR}/mpd.real" "$@"
EOF
    chmod 755 "${TARGET_DIR}/mpd"

    cat > "${TARGET_DIR}/mpc" << 'EOF'
#!/bin/sh
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="${SELF_DIR}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec "${SELF_DIR}/mpc.real" "$@"
EOF
    chmod 755 "${TARGET_DIR}/mpc"

    # buildinfo.txt
    cat > "${TARGET_DIR}/buildinfo.txt" << EOF
platform=${TARGET_PLATFORM}
arch=${TARGET_ARCH}
libc=glibc
baseline=${GLIBC_BASELINE}
mpd=${MPD_VERSION}
mpc=${MPC_VERSION}
ffmpeg=${FFMPEG_VERSION}
build_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

    # 打压缩包（保持插件原有命名）
    echo "==> 创建压缩包...." >&2
    local archive
    archive="${ARCHIVE_DIR}/mpd-player-${TARGET_PLATFORM}.tgz"
    tar -czf "${archive}" -C "${TARGET_DIR}" mpd mpc mpd.real mpc.real lib buildinfo.txt
    echo "${archive}"
}

# ============ 校验 ============
verify_artifact() {
    echo "==> 校验产物...."
    local bad=0

    # 1) 依赖必须全部可解析（与 wrapper 相同环境：LD_LIBRARY_PATH=lib）
    if env LD_LIBRARY_PATH="${TARGET_DIR}/lib" ldd "${TARGET_DIR}/mpd.real" | grep -q "not found"; then
        echo "错误：存在无法解析的依赖:"
        env LD_LIBRARY_PATH="${TARGET_DIR}/lib" ldd "${TARGET_DIR}/mpd.real" | grep "not found"
        bad=1
    fi

    # 2) 整包最高 GLIBC 要求不得高于基线
    local max_req max_req_num highest
    max_req=$(for f in "${TARGET_DIR}/mpd.real" "${TARGET_DIR}/mpc.real" "${TARGET_DIR}/lib/"*; do
        [ -e "${f}" ] || continue
        readelf -V "${f}" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' || true
    done | sort -uV | tail -1 || true)
    max_req_num="${max_req/#GLIBC_}"   # 去掉前缀，转数值版本号参与比较
    highest=$(printf '%s\n%s\n' "${max_req_num:-0}" "${GLIBC_BASELINE}" | sort -uV | tail -1)
    echo "  整包最高 GLIBC 要求: ${max_req:-(无)}，基线: ${GLIBC_BASELINE}"
    if [ -n "${max_req_num}" ] && [ "${highest}" != "${GLIBC_BASELINE}" ]; then
        echo "错误：产物要求 ${max_req}，超过基线 ${GLIBC_BASELINE}" >&2
        bad=1
    fi

    # 3) 运行验证（干净环境下，借助 wrapper 自带 LD_LIBRARY_PATH）
    cd "${TARGET_DIR}"
    if ! env -i HOME=/tmp PATH="/usr/bin:/bin" ./mpd --version > /dev/null 2>&1; then
        echo "错误：./mpd --version 运行失败" >&2
        bad=1
    else
        echo "  ./mpd --version 运行正常"
    fi
    # MPC 0.35 没有 --version，返回 "invalid option --version"(退出码1)，属正常，与插件探测逻辑一致
    local mpc_out
    mpc_out=$(env -i HOME=/tmp PATH="/usr/bin:/bin" ./mpc --version 2>&1 || true)
    if [ "${?}" -ne 0 ] && ! echo "${mpc_out}" | grep -qi "invalid option"; then
        echo "错误：./mpc --version 运行失败: ${mpc_out}" >&2
        bad=1
    else
        echo "  ./mpc 运行正常"
    fi
    cd "${BUILD_ROOT}"

    if [ "${bad}" -ne 0 ]; then
        echo "校验未通过，参见上方错误" >&2
        exit 1
    fi
    echo "  校验全部通过"
}

# ============ 主流程 ============
run_glibc_build() {
    echo "============================================"
    echo "构建 MPD ${TARGET_PLATFORM}"
    echo "  glibc 基线: ${GLIBC_BASELINE} (Debian 11)"
    echo "============================================"
    setup_dirs
    install_build_deps
    download_sources
    build_ffmpeg
    build_mpd
    build_mpc
    local archive
    archive=$(collect_and_package)
    verify_artifact

    echo ""
    echo "============================================"
    echo "构建完成: ${TARGET_PLATFORM}"
    echo "产物: ${archive}"
    echo "大小: $(ls -lh "${archive}" | awk '{print $5}')"
    echo "文件数: $(tar -tzf "${archive}" | wc -l)"
    echo "============================================"
}