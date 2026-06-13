#!/usr/bin/env bash
# MPD 全平台构建脚本
set -e

echo "===================================="
echo "MPD 全平台构建"
echo "===================================="

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "${SCRIPT_DIR}"

# 构建平台列表
PLATFORMS=(
    "linux-arm64-glibc"
    "linux-arm64-musl"
    "linux-armv7-glibc"
    "linux-x86_64-glibc"
    "linux-x86_64-musl"
)

# 检查构建脚本
for platform in "${PLATFORMS[@]}"; do
    script="build-${platform}.sh"
    if [ ! -f "${script}" ]; then
        echo "错误: 找不到构建脚本 ${script}"
        exit 1
    fi
    chmod +x "${script}"
done

echo "找到 ${#PLATFORMS[@]} 个构建脚本"
echo ""

# 构建每个平台
SUCCESS_COUNT=0
FAIL_COUNT=0

for platform in "${PLATFORMS[@]}"; do
    echo "===================================="
    echo "构建平台: ${platform}"
    echo "===================================="
    
    if ./build-${platform}.sh; then
        echo "✓ ${platform} 构建成功"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "✗ ${platform} 构建失败"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    echo ""
done

# 汇总结果
echo "===================================="
echo "构建完成汇总"
echo "===================================="
echo "总平台数: ${#PLATFORMS[@]}"
echo "成功: ${SUCCESS_COUNT}"
echo "失败: ${FAIL_COUNT}"
echo ""

if [ ${FAIL_COUNT} -gt 0 ]; then
    echo "部分平台构建失败，请检查错误信息"
    exit 1
else
    echo "所有平台构建成功！"
    echo ""
    echo "构建产物位置:"
    for platform in "${PLATFORMS[@]}"; do
        artifact="workspace/${platform}/archive/mpd-player-${platform}.tgz"
        if [ -f "${artifact}" ]; then
            size=$(ls -lh "${artifact}" | awk '{print $5}')
            files=$(tar -tzf "${artifact}" | wc -l)
            echo "  ${platform}: ${size} (${files} 个文件)"
        fi
    done
fi

echo ""
echo "===================================="