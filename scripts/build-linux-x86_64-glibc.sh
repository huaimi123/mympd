#!/usr/bin/env bash
# MPD linux-x86_64-glibc 构建脚本
# 运行方式（在 debian:11 容器内）：bash scripts/build-linux-x86_64-glibc.sh
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export BUILD_ROOT="${SCRIPT_DIR}"
export TARGET_PLATFORM="linux-x86_64-glibc"
export TARGET_ARCH="x86_64"
export TARGET_LIBC="glibc"

# shellcheck source=build-linux-glibc-common.sh
source "${SCRIPT_DIR}/build-linux-glibc-common.sh"
run_glibc_build