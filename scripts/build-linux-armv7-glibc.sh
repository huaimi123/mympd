#!/usr/bin/env bash
# MPD linux-armv7-glibc 构建脚本（armhf 硬浮点）
# 运行方式（在 arm32v7/debian:11 容器内，x86_64 主机需先注册 qemu-arm binfmt）：
#   git clone 后执行 bash scripts/build-linux-armv7-glibc.sh
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export BUILD_ROOT="${SCRIPT_DIR}"
export TARGET_PLATFORM="linux-armv7-glibc"
export TARGET_ARCH="armv7"
export TARGET_LIBC="glibc"

# shellcheck source=build-linux-glibc-common.sh
source "${SCRIPT_DIR}/build-linux-glibc-common.sh"
run_glibc_build