#!/bin/bash
# =============================================================================
# 在 Linux 上用 MinGW-w64 为 Windows 交叉编译 FFmpeg 静态库
#
# 自动：检查 mingw-w64 工具链、缺失时下载 FFmpeg 源码；
# 所有路径均可通过命令行参数或环境变量输入，无需修改本文件。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

CROSS_PREFIX="x86_64-w64-mingw32-"

# ---------- 默认值（环境变量 < 命令行参数）----------
FFMPEG_SRC="${FFMPEG_SRC:-}"
USER_OUTPUT=""
OUTPUT_BASE="${FFMPEG_OUTPUT_DIR:-$FFMPEG_BUILD_ROOT/output}"
JOBS=""

show_usage() {
cat <<EOF
用法: $0 [选项]

在 Linux 主机上用 MinGW-w64 为 Windows 64 位交叉编译 FFmpeg 静态库。
编译完成后运行 ./merge_windows.sh 可合并为 ffmpeg.dll。

$(common_options_text)
示例:
  $0                                        # 自动下载源码、检查依赖
  $0 --ffmpeg-src /path/to/ffmpeg --output /tmp/out
EOF
}

# ---------- 参数解析 ----------
while [ $# -gt 0 ]; do
    common_flag "$@"
    if [ "$CONSUMED" -gt 0 ]; then shift "$CONSUMED"; continue; fi
    die "未知选项: $1（-h 查看用法）"
done

# ---------- 前置检查 ----------
info "检查依赖 ..."
ensure_cmd make make
ensure_cmd "${CROSS_PREFIX}gcc" mingw-w64
ensure_cmd "${CROSS_PREFIX}strip" mingw-w64
ensure_cmd tar tar
ensure_cmd xz xz-utils
ensure_download_tool
resolve_ffmpeg_source

JOBS="${JOBS:-$(nproc)}"
assert_number "$JOBS" "--jobs"

OUTPUT_DIR="${USER_OUTPUT:-$OUTPUT_BASE/windows}"

info "FFmpeg 源码: $FFMPEG_SRC"
info "输出目录:    $OUTPUT_DIR"
info "线程数:      $JOBS"

# ---------- 配置、编译、安装 ----------
BUILD_DIR="$FFMPEG_SRC/build_windows"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

(
    cd "$BUILD_DIR"
    "$FFMPEG_SRC/configure" \
        --prefix="$OUTPUT_DIR" \
        --arch=x86_64 \
        --target-os=mingw32 \
        --cross-prefix="$CROSS_PREFIX" \
        --enable-static \
        --enable-cross-compile \
        --disable-zlib \
        --disable-bzlib \
        --disable-iconv \
        --disable-lzma \
        --disable-everything \
        --enable-small \
        \
        --enable-avutil \
        --enable-avcodec \
        --enable-avformat \
        --enable-swresample \
        --enable-swscale \
        \
        --enable-protocol=file \
        \
        --enable-demuxer=mp4,mov,avi,mkv,flv,wmv,asf,mp3,wav,aac,ogg,webm,mpegts,mpegps \
        --enable-muxer=mp4,mkv,mp3,wav \
        --enable-decoder=h264,h265,hevc,vp8,vp9,mpeg4,mpeg2video,mpeg1video,wmv1,wmv2,flv,msmpeg4v2,msmpeg4v3,aac,mp3float,mp3,opus,vorbis,pcm_s16le,pcm_s24le,pcm_f32le,ac3,eac3,dts \
        --enable-parser=h264,hevc,mpeg4video,mpegvideo,vp8,vp9,aac,mpegaudio,opus,vorbis \
        --enable-filter=aresample,scale,crop,overlay,pad,rotate,format \
        --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc

    make -j"$JOBS"
    make install
)

ok "Windows 64 位 FFmpeg 编译完成！"
echo "  静态库: $OUTPUT_DIR/lib/*.a"
info "下一步: 运行 ./merge_windows.sh 合并为 ffmpeg.dll"
