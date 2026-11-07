# ffmpeg_build 交叉编译脚本

在 **Linux** 上为 Android / Windows 交叉编译 FFmpeg，供 `gdextension_build`（SCons）链接。

## 特性

- **自动探测依赖**：自动查找 Android NDK（环境变量 → 常见安装位置），自动检查 make / mingw-w64 / tar / xz / curl 等工具；加 `--install-deps` 可用 apt 自动安装缺失的系统依赖（Debian/Ubuntu）。
- **自动下载源码**：找不到 FFmpeg 源码时自动从 ffmpeg.org 下载指定版本（默认 7.1.1）并解压到 `sources/ffmpeg`。
- **路径全部可输入**：所有路径通过命令行参数或环境变量传入，脚本内不再有硬编码路径。
- **一键合并**：`build_simple.sh --merge` 或单独运行 `build_and_merge.sh` / `merge_windows.sh`，把静态库合并成单个 `libffmpeg.so` / `ffmpeg.dll`。

## 脚本一览

| 脚本 | 用途 |
| --- | --- |
| `build_simple.sh` | 交叉编译 Android 各 ABI 的 FFmpeg 静态库 |
| `build_and_merge.sh` | 把 Android 静态库合并为单个 `libffmpeg.so` |
| `build_windows.sh` | MinGW-w64 交叉编译 Windows 64 位 FFmpeg 静态库 |
| `merge_windows.sh` | 把 Windows 静态库合并为 `ffmpeg.dll`（+ 导入库） |
| `_common.sh` | 公共库（被上面几个脚本 source，不直接执行） |

## 快速开始

```bash
# Android：自动探测 NDK、自动下载源码、只编 arm64-v8a，编完自动合并
./build_simple.sh --merge

# Android：多 ABI + 显式指定 NDK
./build_simple.sh --merge --ndk /opt/android-ndk-r26d --abi arm64-v8a,x86_64

# Windows：需要先装 mingw-w64（或加 --install-deps 自动装）
./build_windows.sh
./merge_windows.sh
```

## 路径输入方式

优先级：**命令行参数 > 环境变量 > 自动探测/默认值**。

| 选项 | 环境变量 | 说明 |
| --- | --- | --- |
| `--ffmpeg-src <路径>` | `FFMPEG_SRC` | FFmpeg 源码目录（缺省自动下载） |
| `--output <路径>` | `FFMPEG_OUTPUT_DIR` | 输出根目录 |
| `--ndk <路径>` | `NDK_ROOT` / `ANDROID_NDK_ROOT` / `ANDROID_HOME` | NDK 探测顺序，先到先用 |
| `--ffmpeg-version <V>` | `FFMPEG_VERSION` | 自动下载的 FFmpeg 版本（默认 7.1.1） |
| `--jobs <N>` | `JOBS` | 并行编译线程数（默认 `nproc`） |
| `--api-level <N>` | `API_LEVEL` | Android API 级别（默认 30） |
| `--abi <列表>` | `FFMPEG_ABIS` | Android ABI，逗号分隔（默认 `arm64-v8a`） |
| `--install-deps` | — | 缺依赖时用 apt 自动安装 |
| `--no-download` | — | 缺源码时不自动下载，直接报错 |

每个脚本都支持 `-h/--help` 查看完整用法。

## 输出目录结构

默认输出到 `<脚本目录>/output/`（可用 `--output` 覆盖）：

```
output/
├── android/
│   └── arm64-v8a/          # 每个 ABI 一个目录
│       ├── include/        # 头文件
│       └── lib/
│           ├── libavcodec.a ...
│           └── libffmpeg.so    # 合并后的库
└── windows/
    ├── include/
    ├── lib/
    │   ├── libavcodec.a ...
    │   ├── ffmpeg.dll          # 合并后的库（同步副本）
    │   └── libffmpeg.dll.a     # 导入库
    └── bin/
        └── ffmpeg.dll
```

## 与 SCons 集成

`gdextension_build/SConstruct` 通过 `ffmpeg_path`（要求目录下有 `include/` 和 `lib/`，库名 `ffmpeg`）定位：

```bash
# Android (arm64-v8a)
scons platform=android arch=arm64 ffmpeg_path=../ffmpeg_build/output/android/arm64-v8a

# Windows
scons platform=windows ffmpeg_path=../ffmpeg_build/output/windows
```

## 环境要求

- Linux 主机（脚本依赖 GNU 工具链：bash、make、tar、xz、curl/wget）
- Android 构建：Android NDK r19+（含 `toolchains/llvm/prebuilt/linux-x86_64`）
- Windows 构建：`mingw-w64`（`sudo apt install mingw-w64`）
