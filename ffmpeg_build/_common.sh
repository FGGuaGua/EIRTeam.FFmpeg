#!/bin/bash
# =============================================================================
# ffmpeg_build 公共库 —— 供 build_*.sh / merge_*.sh 通过 source 引入，请勿直接执行。
#
# 提供：
#   1. 通用命令行选项（路径输入）：--ffmpeg-src / --output / --jobs ...
#   2. 依赖检查与可选 apt 自动安装（--install-deps）
#   3. FFmpeg 源码自动下载（缺省下载到 <脚本目录>/sources/ffmpeg）
#   4. Android NDK 自动探测
#   5. 静态库合并函数（Android -> libffmpeg.so，Windows -> ffmpeg.dll）
# =============================================================================

FFMPEG_BUILD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFMPEG_VERSION_DEFAULT="7.1.1"

# ---------- 日志输出 ----------
if [ -t 1 ]; then
    C_INFO=$'\033[1;34m'; C_OK=$'\033[1;32m'; C_ERR=$'\033[1;31m'; C_END=$'\033[0m'
else
    C_INFO=""; C_OK=""; C_ERR=""; C_END=""
fi
info() { printf '%s[INFO]%s %s\n' "$C_INFO" "$C_END" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_OK"   "$C_END" "$*"; }
die()  { printf '%s[FAIL]%s %s\n' "$C_ERR"  "$C_END" "$*" >&2; exit 1; }

# 相对路径转绝对路径（不做符号链接解析；兼容 Linux 与 Windows 盘符路径）
abs_path() {
    case "$1" in
        /*|[A-Za-z]:[\\/]*|[A-Za-z]:) printf '%s' "$1" ;;
        *)  printf '%s' "$(pwd)/$1" ;;
    esac
}

# 去除首尾空白
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# 校验数字（用于 --jobs / --api-level 等）
assert_number() {
    case "${1:-}" in
        ''|*[!0-9]*) die "$2 不是有效数字: ${1:-<空>}" ;;
    esac
}

# 取选项的参数值：opt_val --foo value；缺失时报错
opt_val() {
    if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
        die "选项 $1 需要一个参数值，例如: $1 <路径>"
    fi
    printf '%s' "$2"
}

# =============================================================================
# 依赖检查 / 自动安装
# =============================================================================
APT_UPDATED=0

apt_install() {
    local pkg="$1"
    command -v apt-get >/dev/null 2>&1 \
        || die "无法自动安装 $pkg：仅支持 apt（Debian/Ubuntu），请手动安装后重试"
    local sudo=""
    if [ "$(id -u)" != "0" ]; then
        command -v sudo >/dev/null 2>&1 \
            || die "缺少 $pkg，且当前非 root 也无 sudo，无法自动安装；请手动安装后重试"
        sudo="sudo"
    fi
    if [ "$APT_UPDATED" = "0" ]; then
        info "执行 apt-get update ..."
        $sudo apt-get update -y
        APT_UPDATED=1
    fi
    info "通过 apt 安装依赖: $pkg"
    $sudo apt-get install -y "$pkg"
}

# ensure_cmd <命令> <对应 apt 包名>
ensure_cmd() {
    local cmd="$1" pkg="$2"
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi
    if [ "${AUTO_INSTALL:-0}" = "1" ]; then
        apt_install "$pkg" || die "自动安装 $pkg 失败，请手动安装后重试"
        command -v "$cmd" >/dev/null 2>&1 || die "已安装 $pkg 但仍找不到命令 $cmd"
        return 0
    fi
    die "缺少依赖命令: $cmd（Debian/Ubuntu: sudo apt install $pkg；或加 --install-deps 让脚本自动安装）"
}

ensure_download_tool() {
    if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
        return 0
    fi
    if [ "${AUTO_INSTALL:-0}" = "1" ]; then
        ensure_cmd curl curl
        return 0
    fi
    die "缺少 curl 或 wget，无法下载 FFmpeg 源码（sudo apt install curl；或加 --install-deps）"
}

download_file() {
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 15 -o "$out" "$url"
    else
        wget -q --tries=3 --timeout=30 -O "$out" "$url"
    fi
}

# =============================================================================
# FFmpeg 源码解析与自动下载
# =============================================================================
# 优先级: --ffmpeg-src > $FFMPEG_SRC > <脚本目录>/sources/ffmpeg > 自动下载
resolve_ffmpeg_source() {
    if [ -n "${FFMPEG_SRC:-}" ]; then
        [ -f "$FFMPEG_SRC/configure" ] || die "--ffmpeg-src 指定的目录不是 FFmpeg 源码（缺少 configure）: $FFMPEG_SRC"
        return 0
    fi

    local local_src="$FFMPEG_BUILD_ROOT/sources/ffmpeg"
    if [ -f "$local_src/configure" ]; then
        FFMPEG_SRC="$local_src"
        return 0
    fi

    if [ "${AUTO_DOWNLOAD:-1}" != "1" ]; then
        die "未找到 FFmpeg 源码。请用 --ffmpeg-src 指定源码目录，或去掉 --no-download 允许自动下载"
    fi

    ensure_cmd tar tar
    ensure_cmd xz xz-utils
    ensure_download_tool

    local ver="${FFMPEG_VERSION:-$FFMPEG_VERSION_DEFAULT}"
    local url="https://ffmpeg.org/releases/ffmpeg-${ver}.tar.xz"
    local archive="$FFMPEG_BUILD_ROOT/sources/ffmpeg-${ver}.tar.xz"

    mkdir -p "$FFMPEG_BUILD_ROOT/sources"
    info "未找到 FFmpeg 源码，开始下载: $url"
    download_file "$url" "$archive" || die "下载失败，请检查网络，或用 --ffmpeg-src 指定本地源码"
    [ -s "$archive" ] || die "下载的压缩包为空: $archive"

    info "解压源码 ..."
    rm -rf "$local_src"
    tar -xJf "$archive" -C "$FFMPEG_BUILD_ROOT/sources"
    mv "$FFMPEG_BUILD_ROOT/sources/ffmpeg-${ver}" "$local_src"

    FFMPEG_SRC="$local_src"
    ok "FFmpeg ${ver} 源码就绪: $FFMPEG_SRC"
}

# =============================================================================
# Android NDK 探测
# =============================================================================
# 优先级: --ndk > $NDK_ROOT > $ANDROID_NDK_ROOT / $ANDROID_NDK_HOME >
#         $ANDROID_HOME(-ndk、ndk-bundle)、~/Android/Sdk/ndk、/opt/android-ndk*
# 选择其中版本号最大的有效 NDK（需含 toolchains/llvm/prebuilt/linux-x86_64）
ndk_is_valid() {
    [ -d "$1/toolchains/llvm/prebuilt/linux-x86_64" ]
}

detect_ndk() {
    local base d latest cand found=""

    if [ -z "${NDK_ROOT:-}" ] && [ -n "${ANDROID_NDK_ROOT:-}" ]; then NDK_ROOT="$ANDROID_NDK_ROOT"; fi
    if [ -z "${NDK_ROOT:-}" ] && [ -n "${ANDROID_NDK_HOME:-}" ]; then NDK_ROOT="$ANDROID_NDK_HOME"; fi

    if [ -z "${NDK_ROOT:-}" ]; then
        # ndk-bundle 目录本身就是 NDK
        for cand in "${ANDROID_HOME:-/nonexistent}/ndk-bundle" "${ANDROID_SDK_ROOT:-/nonexistent}/ndk-bundle"; do
            if ndk_is_valid "$cand"; then NDK_ROOT="$cand"; found=1; break; fi
        done
        # 在各常见 SDK 目录下搜索版本号最大的 NDK
        if [ -z "$found" ]; then
            for base in \
                "${ANDROID_HOME:-/nonexistent}/ndk" \
                "${ANDROID_SDK_ROOT:-/nonexistent}/ndk" \
                "$HOME/Android/Sdk/ndk" \
                "$HOME/Library/Android/sdk/ndk" \
                "/opt/android-ndk"
            do
                [ -d "$base" ] || continue
                latest=""
                while IFS= read -r d; do
                    if ndk_is_valid "$d"; then latest="$d"; fi   # sort -V 升序，最后一次赋值即最新
                done < <(find "$base" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -V)
                if [ -n "$latest" ]; then
                    NDK_ROOT="$latest"
                    found=1
                    break
                fi
            done
        fi
    fi

    [ -n "${NDK_ROOT:-}" ] || die "未找到 Android NDK。请用 --ndk 指定路径，或设置环境变量 ANDROID_NDK_ROOT / ANDROID_HOME"
    NDK_ROOT="$(abs_path "$NDK_ROOT")"
    ndk_is_valid "$NDK_ROOT" \
        || die "NDK 路径无效（缺少 toolchains/llvm/prebuilt/linux-x86_64）: $NDK_ROOT"
    ok "NDK: $NDK_ROOT"
}

# =============================================================================
# 静态库合并
# =============================================================================
# 合并某个 ABI 的 FFmpeg 静态库为单个 libffmpeg.so
# 用法: merge_android_abi <abi> <该 abi 的输出目录（含 lib/）>
merge_android_abi() {
    local abi="$1" out="$2"
    local prefix
    case "$abi" in
        armeabi-v7a) prefix="armv7a-linux-androideabi" ;;
        arm64-v8a)   prefix="aarch64-linux-android" ;;
        x86)         prefix="i686-linux-android" ;;
        x86_64)      prefix="x86_64-linux-android" ;;
        *) die "未知 ABI: $abi（可选: armeabi-v7a, arm64-v8a, x86, x86_64）" ;;
    esac
    assert_number "${API_LEVEL:-}" "API_LEVEL"

    local tool_bin="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
    local lib_dir="$out/lib"
    [ -d "$lib_dir" ] || die "找不到 $lib_dir，请先编译 $abi"

    (
        cd "$lib_dir"
        # shellcheck disable=SC2012  # 有意按文件名排序取 lib*.a
        local static_libs
        static_libs="$(ls lib*.a 2>/dev/null | grep -v libavresample | tr '\n' ' ' || true)"
        [ -n "$static_libs" ] || die "$lib_dir 下没有静态库 (.a)"
        "$tool_bin/${prefix}${API_LEVEL}-clang" -shared \
            -Wl,--whole-archive $static_libs -Wl,--no-whole-archive \
            -o libffmpeg.so \
            -lz -lm -lc++_shared -ldl -llog \
            -Wl,--no-undefined -Wl,--as-needed
        "$tool_bin/llvm-strip" --strip-unneeded libffmpeg.so
    ) || die "$abi 合并为 libffmpeg.so 失败"

    ok "$abi 合并完成: $lib_dir/libffmpeg.so"
}

# 合并 Windows 静态库为单个 ffmpeg.dll（+ 导入库）
# 用法: merge_windows_dll <Windows 输出目录（含 lib/）>
merge_windows_dll() {
    local out="$1"
    local cross="x86_64-w64-mingw32-"

    ensure_cmd "${cross}gcc" mingw-w64
    ensure_cmd "${cross}strip" mingw-w64

    local lib_dir="$out/lib"
    [ -d "$lib_dir" ] || die "找不到 $lib_dir，请先运行 build_windows.sh"
    mkdir -p "$out/bin"

    (
        cd "$lib_dir"
        # shellcheck disable=SC2012  # 有意按文件名排序取 lib*.a
        local static_libs
        static_libs="$(ls lib*.a 2>/dev/null | grep -v libavresample | tr '\n' ' ' || true)"
        [ -n "$static_libs" ] || die "$lib_dir 下没有静态库 (.a)"
        "${cross}gcc" -shared \
            -o "$out/bin/ffmpeg.dll" \
            -Wl,--whole-archive $static_libs -Wl,--no-whole-archive \
            -Wl,--enable-auto-import \
            -Wl,--export-all-symbols \
            -Wl,--out-implib,"$out/bin/ffmpeg.lib" \
            -Wl,--gc-sections \
            -Wl,--as-needed \
            -lwinpthread -lmingw32 -luser32 -lgdi32 -lole32 -lws2_32 \
            -ladvapi32 -lshell32 -lm -lbcrypt -lcrypt32 -lncrypt -lsecur32
    ) || die "链接 ffmpeg.dll 失败"

    "${cross}strip" --strip-unneeded "$out/bin/ffmpeg.dll"

    # 同步一份到 lib/，SCons 可直接 -lffmpeg 链接（MinGW ld 能识别 ffmpeg.dll / 导入库）
    cp -f "$out/bin/ffmpeg.dll" "$lib_dir/ffmpeg.dll"
    if [ -s "$out/bin/ffmpeg.lib" ]; then
        cp -f "$out/bin/ffmpeg.lib" "$lib_dir/libffmpeg.dll.a"
    else
        echo "警告：导入库 ffmpeg.lib 为空，可能没有导出符号，请检查。" >&2
    fi

    ok "已生成: $out/bin/ffmpeg.dll"
    ok "导入库: $lib_dir/libffmpeg.dll.a"
}

# =============================================================================
# 通用命令行选项
# =============================================================================
# 各脚本在自己的 case 里先处理专属选项，其余交给 common_flag。
# 注意：必须在当前 shell 中调用（不能放进 $( )），通过全局变量 CONSUMED
# 返回消耗的参数个数；0 表示不是通用选项。
common_flag() {
    CONSUMED=0
    case "$1" in
        -h|--help)        show_usage; exit 0 ;;
        --ffmpeg-src)     FFMPEG_SRC="$(abs_path "$(opt_val "$@")")";   CONSUMED=2 ;;
        --output)         USER_OUTPUT="$(abs_path "$(opt_val "$@")")";  CONSUMED=2 ;;
        --jobs)           JOBS="$(opt_val "$@")";                       CONSUMED=2 ;;
        --ffmpeg-version) FFMPEG_VERSION="$(opt_val "$@")";             CONSUMED=2 ;;
        --install-deps)   AUTO_INSTALL=1;                               CONSUMED=1 ;;
        --no-download)    AUTO_DOWNLOAD=0;                              CONSUMED=1 ;;
    esac
}

common_options_text() {
    cat <<'EOF'
通用选项:
  --ffmpeg-src <路径>   FFmpeg 源码目录（环境变量 FFMPEG_SRC）
                        缺省时自动查找 <脚本目录>/sources/ffmpeg，没有则自动下载
  --ffmpeg-version <V>  自动下载的 FFmpeg 版本（默认 7.1.1，环境变量 FFMPEG_VERSION）
  --output <路径>       输出根目录（环境变量 FFMPEG_OUTPUT_DIR）
  --jobs <N>            并行编译线程数（默认 nproc，环境变量 JOBS）
  --install-deps        缺少系统依赖时用 apt 自动安装（Debian/Ubuntu）
  --no-download         缺少 FFmpeg 源码时不自动下载，直接报错
EOF
}
