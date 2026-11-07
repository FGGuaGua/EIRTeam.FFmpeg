#!/bin/bash
# =============================================================================
# 在 Linux 上为 Android 交叉编译 FFmpeg 静态库
#
# 自动：探测 Android NDK、检查依赖、缺失时下载 FFmpeg 源码；
# 所有路径均可通过命令行参数或环境变量输入，无需修改本文件。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# ---------- 默认值（环境变量 < 命令行参数）----------
FFMPEG_SRC="${FFMPEG_SRC:-}"
USER_OUTPUT=""
OUTPUT_BASE="${FFMPEG_OUTPUT_DIR:-$FFMPEG_BUILD_ROOT/output}"
NDK_ROOT="${NDK_ROOT:-${ANDROID_NDK_ROOT:-}}"
API_LEVEL="${API_LEVEL:-30}"
ABIS="${FFMPEG_ABIS:-arm64-v8a}"
JOBS=""
DO_MERGE=0

show_usage() {
cat <<EOF
用法: $0 [选项]

在 Linux 主机上为 Android 交叉编译 FFmpeg 静态库（--disable-everything 精简构建）。

Android 选项:
  --abi <列表>        要编译的 ABI，逗号分隔（默认: arm64-v8a）
                      可选: armeabi-v7a, arm64-v8a, x86, x86_64
  --ndk <路径>        Android NDK 根目录（默认按 ANDROID_NDK_ROOT / ANDROID_HOME
                      / ~/Android/Sdk 等常见位置自动探测）
  --api-level <N>     Android API 级别（默认: 30）
  --merge             编译完成后自动把各 ABI 静态库合并为 libffmpeg.so
                      （等价于再运行一次 build_and_merge.sh）

$(common_options_text)
示例:
  $0                                   # 自动探测一切，只编 arm64-v8a
  $0 --ndk /opt/ndk --abi arm64-v8a,x86_64 --merge
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
        --merge)     DO_MERGE=1; shift ;;
        --no-merge)  DO_MERGE=0; shift ;;
        *) die "未知选项: $1（-h 查看用法）" ;;
    esac
done

assert_number "$API_LEVEL" "--api-level"

# ---------- ABI 名称映射 ----------
abi_clang_prefix() {
    case "$1" in
        armeabi-v7a) printf 'armv7a-linux-androideabi' ;;
        arm64-v8a)   printf 'aarch64-linux-android' ;;
        x86)         printf 'i686-linux-android' ;;
        x86_64)      printf 'x86_64-linux-android' ;;
        *) die "未知 ABI: $1（可选: armeabi-v7a, arm64-v8a, x86, x86_64）" ;;
    esac
}

abi_arch() {
    case "$1" in
        armeabi-v7a) printf 'arm' ;;
        arm64-v8a)   printf 'aarch64' ;;
        x86)         printf 'x86' ;;
        x86_64)      printf 'x86_64' ;;
    esac
}

abi_cpu_flags() {
    case "$1" in
        armeabi-v7a) printf '%s' "-march=armv7-a -mfloat-abi=softfp -mfpu=neon" ;;
        arm64-v8a)   printf '%s' "-march=armv8-a" ;;
        x86)         printf '%s' "-march=i686 -mtune=intel -mssse3 -mfpmath=sse -m32" ;;
        x86_64)      printf '%s' "-march=x86-64 -msse4.2 -mpopcnt -m64 -mtune=intel" ;;
    esac
}

build_ffmpeg() {
    local abi="$1"
    local prefix arch cflags build_dir
    prefix="$(abi_clang_prefix "$abi")"
    arch="$(abi_arch "$abi")"
    cflags="$(abi_cpu_flags "$abi")"

    echo "========================================="
    echo "开始编译 $abi"
    echo "========================================="

    # 构建目录放在源码树内（FFmpeg 支持源外构建，配置产物互不干扰）
    build_dir="$FFMPEG_SRC/build_$abi"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    (
        cd "$build_dir"
        "$FFMPEG_SRC/configure" \
            --prefix="$OUTPUT_DIR/$abi" \
            --enable-cross-compile \
            --enable-static \
            --target-os=android \
            --arch="$arch" \
            --cc="$TOOLCHAIN/bin/${prefix}${API_LEVEL}-clang" \
            --cxx="$TOOLCHAIN/bin/${prefix}${API_LEVEL}-clang++" \
            --ar="$TOOLCHAIN/bin/llvm-ar" \
            --nm="$TOOLCHAIN/bin/llvm-nm" \
            --strip="$TOOLCHAIN/bin/llvm-strip" \
            --ranlib="$TOOLCHAIN/bin/llvm-ranlib" \
            --sysroot="$SYSROOT" \
            --extra-cflags="-fPIC -DANDROID $cflags" \
            --extra-ldflags="" \
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
            --enable-decoder=aac,mp3float,mp3,opus,vorbis,pcm_s16le,pcm_s24le,pcm_f32le,ac3,eac3,dts \
            --enable-decoder=h264,h265,hevc,vp8,vp9,mpeg4,mpeg2video,mpeg1video,wmv1,wmv2,flv,msmpeg4v2,msmpeg4v3 \
            --enable-parser=h264,hevc,mpeg4video,mpegvideo,vp8,vp9,aac,mpegaudio,opus,vorbis \
            --enable-filter=aresample,scale,crop,overlay,pad,rotate,format \
            --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc

        make -j"$JOBS"
        make install
    )
    ok "$abi 编译完成"
}

# ---------- 前置检查 ----------
info "检查依赖 ..."
ensure_cmd make make
ensure_cmd tar tar
ensure_cmd xz xz-utils
ensure_download_tool
detect_ndk
resolve_ffmpeg_source

JOBS="${JOBS:-$(nproc)}"
assert_number "$JOBS" "--jobs"

TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64"
SYSROOT="$TOOLCHAIN/sysroot"
OUTPUT_DIR="${USER_OUTPUT:-$OUTPUT_BASE/android}"

info "FFmpeg 源码: $FFMPEG_SRC"
info "输出目录:    $OUTPUT_DIR/<abi>"
info "API 级别:    $API_LEVEL    并行线程: $JOBS"

# ---------- 编译各 ABI ----------
BUILT=""
IFS=',' read -r -a abi_list <<< "$ABIS"
for abi in "${abi_list[@]}"; do
    abi="$(trim "$abi")"
    [ -n "$abi" ] || continue
    build_ffmpeg "$abi"
    BUILT="$BUILT $abi"
done

# ---------- 可选：合并为 libffmpeg.so ----------
if [ "$DO_MERGE" = "1" ]; then
    for abi in $BUILT; do
        merge_android_abi "$abi" "$OUTPUT_DIR/$abi"
    done
fi

echo
ok "全部完成！输出目录: $OUTPUT_DIR"
for abi in $BUILT; do
    echo "  $abi: include/ lib/  →  ffmpeg_path=$OUTPUT_DIR/$abi"
done
if [ "$DO_MERGE" != "1" ]; then
    info "提示: 加 --merge 可在编译后自动合并为 libffmpeg.so（或运行 ./build_and_merge.sh）"
fi
