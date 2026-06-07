#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export TARGET_PLATFORM=linux-armv7-glibc

exec "${SCRIPT_DIR}/build-native-plugin-binaries-common.sh" "$@"
