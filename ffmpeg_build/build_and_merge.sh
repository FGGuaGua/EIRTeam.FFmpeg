#!/bin/bash
# =============================================================================
# 把已编译好的 Android 静态库（build_simple.sh 的产物）合并为单个 libffmpeg.so
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# ---------- 默认值（环境变量 < 命令行参数）----------
USER_OUTPUT=""
OUTPUT_BASE="${FFMPEG_OUTPUT_DIR:-$FFMPEG_BUILD_ROOT/output}"
NDK_ROOT="${NDK_ROOT:-${ANDROID_NDK_ROOT:-}}"
API_LEVEL="${API_LEVEL:-30}"
ABIS="${FFMPEG_ABIS:-arm64-v8a}"

show_usage() {
cat <<EOF
用法: $0 [选项]

把 build_simple.sh 编出的各 ABI 静态库合并为 libffmpeg.so（输出到对应目录的 lib/ 下）。

Android 选项:
  --abi <列表>        要合并的 ABI，逗号分隔（默认: arm64-v8a）
  --ndk <路径>        Android NDK 根目录（默认自动探测）
  --api-level <N>     Android API 级别（默认: 30）

$(common_options_text)
示例:
  $0
  $0 --abi arm64-v8a,x86_64 --ndk /opt/ndk
EOF
}

# ---------- 参数解析 ----------
while [ $# -gt 0 ]; do
    common_flag "$@"
    if [ "$CONSUMED" -gt 0 ]; then shift "$CONSUMED"; continue; fi
    case "$1" in
        --abi)       ABIS="$(opt_val "$@")"; shift 2 ;;
        --ndk)       NDK_ROOT="$(abs_path "$(opt_val "$@")")"; shift 2 ;;
        --api-level) API_LEVEL="$(opt_val "$@")"; shift 2 ;;
        *) die "未知选项: $1（-h 查看用法）" ;;
    esac
done

assert_number "$API_LEVEL" "--api-level"

OUTPUT_DIR="${USER_OUTPUT:-$OUTPUT_BASE/android}"

detect_ndk

IFS=',' read -r -a abi_list <<< "$ABIS"
for abi in "${abi_list[@]}"; do
    abi="$(trim "$abi")"
    [ -n "$abi" ] || continue
    merge_android_abi "$abi" "$OUTPUT_DIR/$abi"
done

echo
ok "合并完成！SCons 构建时使用: scons platform=android ffmpeg_path=$OUTPUT_DIR/<abi>"
