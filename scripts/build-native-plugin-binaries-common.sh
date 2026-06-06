#!/usr/bin/env bash
set -euo pipefail

# Native bundle build for one target platform.
# Expected output:
#   bin/<platform>/
#     mpd
#     mpc
#     mpd.real
#     mpc.real
#     lib/

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

TARGET_PLATFORM=${TARGET_PLATFORM:-}
TARGET_ARCH=${TARGET_ARCH:-}
TARGET_LIBC=${TARGET_LIBC:-}
MPD_VERSION=${MPD_VERSION:-0.24.12}
MPC_VERSION=${MPC_VERSION:-0.35}
TARGET_DIR=${TARGET_DIR:-}
WORK_DIR=${WORK_DIR:-"${PROJECT_ROOT}/.build/plugin-binaries"}
ARCHIVE_DIR=${ARCHIVE_DIR:-"${PROJECT_ROOT}/dist/plugin-binaries"}
ARCHIVE_PATH=

APT_PACKAGES=(
  build-essential
  ca-certificates
  curl
  file
  git
  meson
  ninja-build
  patchelf
  pkgconf
  python3
  tar
  xz-utils
  libasound2-dev
  libcurl4-gnutls-dev
  libexpat1-dev
  libflac-dev
  libfmt-dev
  libicu-dev
  libid3tag0-dev
  libmad0-dev
  libmpg123-dev
  libogg-dev
  libopus-dev
  libpipewire-0.3-dev
  libpulse-dev
  libsndfile1-dev
  libsqlite3-dev
  libvorbis-dev
)

APK_PACKAGES=(
  bash
  build-base
  ca-certificates
  curl
  file
  git
  linux-headers
  meson
  ninja
  patchelf
  pkgconf
  python3
  tar
  xz
  alsa-lib-dev
  curl-dev
  expat-dev
  flac-dev
  fmt-dev
  icu-dev
  libid3tag-dev
  libmad-dev
  mpg123-dev
  libogg-dev
  opus-dev
  pipewire-dev
  pulseaudio-dev
  libsndfile-dev
  sqlite-dev
  libvorbis-dev
)

log() {
  printf '[build-native-plugin-binaries] %s\n' "$*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

normalize_legacy_target_platform() {
  case "$1" in
    linux-amd64)
      printf '%s\n' 'linux-x86_64-glibc'
      ;;
    linux-arm64)
      printf '%s\n' 'linux-arm64-glibc'
      ;;
    linux-armv7)
      printf '%s\n' 'linux-armv7-glibc'
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

normalize_arch() {
  case "$1" in
    x86_64|amd64)
      printf '%s\n' 'x86_64'
      ;;
    aarch64|arm64)
      printf '%s\n' 'arm64'
      ;;
    armv7l|armv7|armhf|armv6l)
      printf '%s\n' 'armv7'
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

normalize_libc() {
  local value
  value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "${value}" in
    *musl*)
      printf '%s\n' 'musl'
      ;;
    *glibc*|*gnu\ libc*|*gnu\ c\ library*|*gnu_get_libc_version*)
      printf '%s\n' 'glibc'
      ;;
    *)
      printf '%s\n' "${value:-unknown}"
      ;;
  esac
}

build_platform_key() {
  printf 'linux-%s-%s\n' "$1" "$2"
}

parse_target_platform() {
  TARGET_PLATFORM=$(normalize_legacy_target_platform "${TARGET_PLATFORM}")

  if [[ -z "${TARGET_PLATFORM}" ]]; then
    if [[ -z "${TARGET_ARCH}" || -z "${TARGET_LIBC}" ]]; then
      printf 'TARGET_PLATFORM or both TARGET_ARCH and TARGET_LIBC are required\n' >&2
      exit 1
    fi
    TARGET_ARCH=$(normalize_arch "${TARGET_ARCH}")
    TARGET_LIBC=$(normalize_libc "${TARGET_LIBC}")
    TARGET_PLATFORM=$(build_platform_key "${TARGET_ARCH}" "${TARGET_LIBC}")
    return
  fi

  case "${TARGET_PLATFORM}" in
    linux-x86_64-glibc)
      TARGET_ARCH='x86_64'
      TARGET_LIBC='glibc'
      ;;
    linux-x86_64-musl)
      TARGET_ARCH='x86_64'
      TARGET_LIBC='musl'
      ;;
    linux-arm64-glibc)
      TARGET_ARCH='arm64'
      TARGET_LIBC='glibc'
      ;;
    linux-arm64-musl)
      TARGET_ARCH='arm64'
      TARGET_LIBC='musl'
      ;;
    linux-armv7-glibc)
      TARGET_ARCH='armv7'
      TARGET_LIBC='glibc'
      ;;
    *)
      printf 'Unsupported TARGET_PLATFORM: %s\n' "${TARGET_PLATFORM}" >&2
      exit 1
      ;;
  esac
}

detect_host_arch() {
  local machine
  machine=$(uname -m)
  machine=$(normalize_arch "${machine}")
  case "${machine}" in
    x86_64|arm64|armv7)
      printf '%s\n' "${machine}"
      ;;
    *)
      printf 'Unsupported host architecture: %s\n' "${machine}" >&2
      exit 1
      ;;
  esac
}

detect_host_libc() {
  local raw=''
  if command -v ldd >/dev/null 2>&1; then
    raw=$(ldd --version 2>&1 | head -n 1 || true)
  fi
  if [[ -z "${raw}" ]] && command -v getconf >/dev/null 2>&1; then
    raw=$(getconf GNU_LIBC_VERSION 2>/dev/null | head -n 1 || true)
  fi
  if [[ -z "${raw}" ]] && ls /lib/libc.musl-* >/dev/null 2>&1; then
    raw='musl'
  fi
  if [[ -z "${raw}" ]] && { ls /lib64/libc.so.6 >/dev/null 2>&1 || ls /lib/x86_64-linux-gnu/libc.so.6 >/dev/null 2>&1 || ls /lib/aarch64-linux-gnu/libc.so.6 >/dev/null 2>&1; }; then
    raw='glibc'
  fi

  local libc
  libc=$(normalize_libc "${raw}")
  case "${libc}" in
    glibc|musl)
      printf '%s\n' "${libc}"
      ;;
    *)
      printf 'Unable to detect host libc from: %s\n' "${raw:-<empty>}" >&2
      exit 1
      ;;
  esac
}

install_build_deps_apt() {
  if [[ "${SKIP_APT:-0}" == "1" || "${SKIP_SYS_PKG_INSTALL:-0}" == "1" ]]; then
    log "Skip apt dependency installation"
    return
  fi

  local -a apt_cmd=()
  if command -v sudo >/dev/null 2>&1; then
    apt_cmd=(sudo)
  elif [[ "$(id -u)" != "0" ]]; then
    printf 'sudo is required unless SKIP_APT=1 or you run as root\n' >&2
    exit 1
  fi

  log "Installing glibc/Debian build dependencies"
  "${apt_cmd[@]}" apt-get update
  "${apt_cmd[@]}" apt-get install -y "${APT_PACKAGES[@]}"
}

install_build_deps_apk() {
  if [[ "${SKIP_APK:-0}" == "1" || "${SKIP_SYS_PKG_INSTALL:-0}" == "1" ]]; then
    log "Skip apk dependency installation"
    return
  fi

  local -a apk_cmd=()
  if command -v sudo >/dev/null 2>&1; then
    apk_cmd=(sudo)
  elif [[ "$(id -u)" != "0" ]]; then
    printf 'sudo is required unless SKIP_APK=1 or you run as root\n' >&2
    exit 1
  fi

  log "Installing musl/Alpine build dependencies"
  "${apk_cmd[@]}" apk add --no-cache "${APK_PACKAGES[@]}"
}

install_build_deps() {
  if [[ "${TARGET_LIBC}" == "glibc" ]]; then
    require_command apt-get
    install_build_deps_apt
  elif [[ "${TARGET_LIBC}" == "musl" ]]; then
    require_command apk
    install_build_deps_apk
  else
    printf 'Unsupported TARGET_LIBC: %s\n' "${TARGET_LIBC}" >&2
    exit 1
  fi
}

prepare_target() {
  parse_target_platform

  local host_arch host_libc host_platform
  host_arch=$(detect_host_arch)
  host_libc=$(detect_host_libc)
  host_platform=$(build_platform_key "${host_arch}" "${host_libc}")
  if [[ "${host_platform}" != "${TARGET_PLATFORM}" ]]; then
    printf 'Host platform is %s but TARGET_PLATFORM is %s\n' "${host_platform}" "${TARGET_PLATFORM}" >&2
    printf 'Run the matching script on the matching native host/rootfs with the same libc family.\n' >&2
    exit 1
  fi

  if [[ -z "${TARGET_DIR}" ]]; then
    TARGET_DIR="${PROJECT_ROOT}/bin/${TARGET_PLATFORM}"
  fi

  TARGET_WORK_DIR="${WORK_DIR}/${TARGET_PLATFORM}"
  DOWNLOAD_DIR="${TARGET_WORK_DIR}/downloads"
  SRC_DIR="${TARGET_WORK_DIR}/src"
  BUILD_DIR="${TARGET_WORK_DIR}/build"
  STAGE_DIR="${TARGET_WORK_DIR}/stage"
}

prepare_dirs() {
  rm -rf "${TARGET_WORK_DIR}"
  mkdir -p "${DOWNLOAD_DIR}" "${SRC_DIR}" "${BUILD_DIR}" "${STAGE_DIR}" "${TARGET_DIR}/lib"
}

download_source() {
  local url="$1"
  local out="$2"
  if [[ ! -f "${out}" ]]; then
    log "Downloading $(basename "${out}")"
    curl -L --fail --retry 3 -o "${out}" "${url}"
  fi
}

extract_tarball() {
  local archive="$1"
  local dest="$2"
  rm -rf "${dest}"
  mkdir -p "${dest}"
  tar -xf "${archive}" -C "${dest}" --strip-components=1
}

build_mpd() {
  local src="${SRC_DIR}/mpd"
  local build="${BUILD_DIR}/mpd"

  mkdir -p "${build}"

  meson setup "${build}" "${src}" \
    --buildtype release \
    --prefix /usr \
    -Ddocumentation=disabled \
    -Dhtml_manual=false \
    -Dmanpages=false \
    -Dtest=false \
    -Dfuzzer=false \
    -Dsyslog=disabled \
    -Dinotify=false \
    -Dio_uring=disabled \
    -Dsystemd=disabled \
    -Ddatabase=false \
    -Dupnp=disabled \
    -Dlibmpdclient=disabled \
    -Dneighbor=false \
    -Dudisks=disabled \
    -Dwebdav=disabled \
    -Dcue=false \
    -Dcdio_paranoia=disabled \
    -Dmms=disabled \
    -Dnfs=disabled \
    -Dsmbclient=disabled \
    -Dqobuz=disabled \
    -Dbzip2=disabled \
    -Diso9660=disabled \
    -Dzzip=disabled \
    -Dchromaprint=disabled \
    -Dadplug=disabled \
    -Daudiofile=disabled \
    -Dfaad=disabled \
    -Dffmpeg=disabled \
    -Dfluidsynth=disabled \
    -Dgme=disabled \
    -Dmikmod=disabled \
    -Dmodplug=disabled \
    -Dopenmpt=disabled \
    -Dmpcdec=disabled \
    -Dsidplay=disabled \
    -Dtremor=disabled \
    -Dwavpack=disabled \
    -Dwildmidi=disabled \
    -Dvorbisenc=disabled \
    -Dlame=disabled \
    -Dtwolame=disabled \
    -Dshine=disabled \
    -Dlibsamplerate=disabled \
    -Dsoxr=disabled \
    -Dao=disabled \
    -Dfifo=false \
    -Dhttpd=false \
    -Djack=disabled \
    -Dopenal=disabled \
    -Doss=disabled \
    -Dpipe=false \
    -Dpipewire=enabled \
    -Dpulse=enabled \
    -Drecorder=false \
    -Dshout=disabled \
    -Dsnapcast=false \
    -Dsndio=disabled \
    -Dsolaris_output=disabled \
    -Ddbus=disabled \
    -Dnlohmann_json=disabled \
    -Dzeroconf=disabled

  ninja -C "${build}"
  DESTDIR="${STAGE_DIR}/mpd" ninja -C "${build}" install
}

build_mpc() {
  local src="${SRC_DIR}/mpc"
  local build="${BUILD_DIR}/mpc"

  mkdir -p "${build}"

  meson setup "${build}" "${src}" \
    --buildtype release \
    --prefix /usr \
    --wrap-mode=forcefallback \
    -Ddocumentation=disabled \
    -Dtest=false

  ninja -C "${build}"
  DESTDIR="${STAGE_DIR}/mpc" ninja -C "${build}" install
}

copy_binary() {
  local from="$1"
  local to="$2"
  install -Dm755 "${from}" "${to}"
  if command -v strip >/dev/null 2>&1; then
    strip --strip-unneeded "${to}" || true
  fi
  patchelf --set-rpath '$ORIGIN/lib' "${to}" || true
}

should_skip_runtime_lib() {
  case "$1" in
    */ld-linux-*|*/ld-musl-*|*/libc.so.*|*/libm.so.*|*/libpthread.so.*|*/libdl.so.*|*/librt.so.*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

copy_runtime_libs() {
  local target_lib_dir="$1"
  shift

  mkdir -p "${target_lib_dir}"
  local queue=("$@")
  declare -A seen=()

  while [[ ${#queue[@]} -gt 0 ]]; do
    local current="${queue[0]}"
    queue=("${queue[@]:1}")

    if [[ -n "${seen[${current}]:-}" ]]; then
      continue
    fi
    seen["${current}"]=1

    while IFS= read -r line; do
      local dep=""
      if [[ "${line}" == *"=>"* ]]; then
        dep=$(printf '%s\n' "${line}" | awk '{for (i = 1; i <= NF; i++) if ($i == "=>") { print $(i + 1); exit }}')
      elif [[ "${line}" == /* ]]; then
        dep=$(printf '%s\n' "${line}" | awk '{print $1}')
      fi

      if [[ -z "${dep}" || ! -f "${dep}" ]]; then
        continue
      fi
      if should_skip_runtime_lib "${dep}"; then
        continue
      fi

      local base
      base=$(basename "${dep}")
      if [[ ! -f "${target_lib_dir}/${base}" ]]; then
        install -Dm755 "${dep}" "${target_lib_dir}/${base}"
        queue+=("${dep}")
      fi
    done < <(ldd "${current}" 2>/dev/null || true)
  done
}

write_wrapper() {
  local output="$1"
  local real_name="$2"
  cat > "${output}" <<EOF
#!/bin/sh
set -eu
SELF_DIR=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
export LD_LIBRARY_PATH="\${SELF_DIR}/lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
exec "\${SELF_DIR}/${real_name}" "\$@"
EOF
  chmod 0755 "${output}"
}

main() {
  prepare_target

  log "Target platform: ${TARGET_PLATFORM}"
  log "Target arch/libc: ${TARGET_ARCH}/${TARGET_LIBC}"
  log "Output directory: ${TARGET_DIR}"

  install_build_deps
  require_command tar
  require_command curl
  require_command meson
  require_command ninja
  require_command patchelf
  require_command ldd

  prepare_dirs

  download_source "https://github.com/MusicPlayerDaemon/MPD/archive/refs/tags/v${MPD_VERSION}.tar.gz" "${DOWNLOAD_DIR}/mpd-${MPD_VERSION}.tar.gz"
  download_source "https://github.com/MusicPlayerDaemon/mpc/archive/refs/tags/v${MPC_VERSION}.tar.gz" "${DOWNLOAD_DIR}/mpc-${MPC_VERSION}.tar.gz"

  extract_tarball "${DOWNLOAD_DIR}/mpd-${MPD_VERSION}.tar.gz" "${SRC_DIR}/mpd"
  extract_tarball "${DOWNLOAD_DIR}/mpc-${MPC_VERSION}.tar.gz" "${SRC_DIR}/mpc"

  build_mpd
  build_mpc

  rm -rf "${TARGET_DIR}"
  mkdir -p "${TARGET_DIR}/lib"

  copy_binary "${STAGE_DIR}/mpd/usr/bin/mpd" "${TARGET_DIR}/mpd.real"
  copy_binary "${STAGE_DIR}/mpc/usr/bin/mpc" "${TARGET_DIR}/mpc.real"

  copy_runtime_libs "${TARGET_DIR}/lib" "${TARGET_DIR}/mpd.real" "${TARGET_DIR}/mpc.real"

  write_wrapper "${TARGET_DIR}/mpd" "mpd.real"
  write_wrapper "${TARGET_DIR}/mpc" "mpc.real"

  mkdir -p "${ARCHIVE_DIR}"
  ARCHIVE_PATH="${ARCHIVE_DIR}/mpd-player-${TARGET_PLATFORM}.tgz"
  tar -czf "${ARCHIVE_PATH}" -C "${TARGET_DIR}" mpd mpc mpd.real mpc.real lib

  log "Build finished"
  log "Plugin bundle directory: ${TARGET_DIR}"
  log "GitHub upload archive: ${ARCHIVE_PATH}"
}

main "$@"
