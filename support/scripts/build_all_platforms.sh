#!/bin/bash
# LocalSend 改进版编译脚本
# 支持编译 Windows EXE 安装包、绿色免安装版和 Android APK
# 适配 Win7 以上系统
#
# 使用方法:
#   chmod +x build_all_platforms.sh
#   ./build_all_platforms.sh
#
# 前置要求:
#   - Flutter SDK (>=3.41.0) 安装并加入 PATH
#   - Rust 工具链 (rustup, cargo) 安装
#   - Android SDK 和 NDK 安装 (ANDROID_HOME 环境变量)
#   - Windows 交叉编译: rustup target add x86_64-pc-windows-gnu
#   - Inno Setup (用于 Windows EXE 安装包)
#
# 作者: LocalSend 改进版
# 日期: 2026-08-06

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP_DIR="$PROJECT_ROOT/app"
OUTPUT_DIR="$PROJECT_ROOT/build_output"

mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo "LocalSend 改进版编译脚本"
echo "========================================"
echo ""

# 检查 Flutter
if ! command -v flutter &> /dev/null; then
    echo "[错误] 未找到 Flutter SDK，请先安装 Flutter >= 3.41.0"
    echo "  下载地址: https://docs.flutter.dev/get-started/install"
    exit 1
fi

# 检查 Rust
if ! command -v cargo &> /dev/null; then
    echo "[错误] 未找到 Rust 工具链，请先安装 rustup"
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi

echo "[1/5] 安装 Flutter 依赖..."
cd "$APP_DIR"
flutter pub get

echo "[2/5] 运行代码生成器..."
dart run build_runner build --delete-conflicting-outputs
dart run slang

echo ""
echo "========================================"
echo "编译 Windows 版本 (Win7+)"
echo "========================================"

# 添加 Windows 交叉编译目标
rustup target add x86_64-pc-windows-gnu || true

echo "[3/5] 编译 Windows 绿色免安装版..."
flutter build windows --release

# 复制绿色版到输出目录
WINDOWS_BUILD="$APP_DIR/build/windows/x64/runner/Release"
if [ -d "$WINDOWS_BUILD" ]; then
    cp -r "$WINDOWS_BUILD" "$OUTPUT_DIR/LocalSend_Windows_Portable"
    echo "  ✓ Windows 绿色版已生成: $OUTPUT_DIR/LocalSend_Windows_Portable"
else
    echo "  ✗ Windows 编译失败，请检查 Flutter 和 Rust 环境"
fi

echo ""
echo "[4/5] 编译 Windows EXE 安装包..."
# 使用 Inno Setup 编译安装包
INNO_SCRIPT="$PROJECT_ROOT/support/scripts/compile_windows_exe-inno.iss"
if command -v iscc &> /dev/null && [ -f "$INNO_SCRIPT" ]; then
    iscc "$INNO_SCRIPT"
    echo "  ✓ Windows EXE 安装包已生成"
else
    echo "  ⚠ 未找到 Inno Setup (iscc)，跳过安装包编译"
    echo "    请安装 Inno Setup 后运行: iscc $INNO_SCRIPT"
fi

echo ""
echo "========================================"
echo "编译 Android APK"
echo "========================================"

echo "[5/5] 编译 Android APK..."
# 添加 Android 交叉编译目标
rustup target add aarch64-linux-android || true
rustup target add armv7-linux-androideabi || true
rustup target add x86_64-linux-android || true

flutter build apk --release

APK_FILE="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK_FILE" ]; then
    cp "$APK_FILE" "$OUTPUT_DIR/LocalSend_Android.apk"
    echo "  ✓ Android APK 已生成: $OUTPUT_DIR/LocalSend_Android.apk"
else
    echo "  ✗ Android 编译失败，请检查 Android SDK 配置"
    echo "    确保设置 ANDROID_HOME 环境变量"
    echo "    确保安装了 Android NDK"
fi

echo ""
echo "========================================"
echo "编译完成！"
echo "========================================"
echo ""
echo "输出文件位置: $OUTPUT_DIR/"
ls -la "$OUTPUT_DIR/" 2>/dev/null || true
echo ""
echo "注意:"
echo "  - Windows 绿色版: 直接解压运行 LocalSend.exe"
echo "  - Windows 安装包: 运行 .exe 安装程序"
echo "  - Android APK: 安装到 Android 设备"
echo "  - 适配 Win7 以上系统（已移除 permission_handler_windows 依赖）"
