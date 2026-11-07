#!/bin/bash
# =============================================================================
# 把 build_windows.sh 编出的静态库合并为单个 ffmpeg.dll（含导入库）
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# ---------- 默认值（环境变量 < 命令行参数）----------
USER_OUTPUT=""
OUTPUT_BASE="${FFMPEG_OUTPUT_DIR:-$FFMPEG_BUILD_ROOT/output}"

show_usage() {
cat <<EOF
用法: $0 [选项]

把 Windows 静态库合并为单个 ffmpeg.dll + 导入库，并同时放入 lib/ 供 SCons 直接 -lffmpeg 链接。

$(common_options_text)
示例:
  $0
  $0 --output /path/to/output_windows
EOF
}

# ---------- 参数解析 ----------
while [ $# -gt 0 ]; do
    common_flag "$@"
    if [ "$CONSUMED" -gt 0 ]; then shift "$CONSUMED"; continue; fi
    die "未知选项: $1（-h 查看用法）"
done

OUTPUT_DIR="${USER_OUTPUT:-$OUTPUT_BASE/windows}"

info "输出目录: $OUTPUT_DIR"
merge_windows_dll "$OUTPUT_DIR"

echo
ok "SCons 构建时使用: scons platform=windows ffmpeg_path=$OUTPUT_DIR"
