#!/bin/bash
# ============================================================
# LocalSend 银河麒麟 V10 (aarch64) 一键构建脚本
# 在麒麟桌面版 V10 SP1 (飞腾/鲲鹏) 上直接编译
# 产物: app/build/linux/arm64/release/bundle/
# ============================================================
set -e

# --- 1. 架构检查 ---
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
    echo "错误: 本脚本仅支持 aarch64 架构, 当前: $ARCH"
    exit 1
fi
echo "[1/6] 架构检查通过: $ARCH"

# --- 2. 安装系统依赖 ---
echo "[2/6] 安装系统依赖 (需要 sudo 密码)..."
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    git curl unzip xz-utils zip ca-certificates \
    gcc g++ clang cmake ninja-build pkg-config patchelf \
    libgtk-3-dev liblzma-dev libglu1-mesa \
    libayatana-appindicator3-dev libsecret-1-dev libjsoncpp-dev \
    libglib2.0-dev libgraphite2-dev \
    libxdamage-dev libxcomposite-dev libxcursor-dev libxinerama-dev libxrandr-dev \
    libxi-dev libxtst-dev libxfixes-dev libxrender-dev libxext-dev libx11-dev \
    libgbm-dev libdrm-dev libegl-dev libgl-dev libgles-dev \
    libnss3-dev libnspr4-dev \
    libatk1.0-dev libatk-bridge2.0-dev \
    libcups2-dev libdbus-1-dev \
    libpango1.0-dev libcairo2-dev \
    libfribidi-dev libthai-dev \
    libfontconfig1-dev libfreetype6-dev \
    libgdk-pixbuf2.0-dev \
    libwayland-dev libxkbcommon-dev \
    fonts-noto-cjk fonts-wqy-microhei fonts-wqy-zenhei

# --- 3. 安装 Rust ---
echo "[3/6] 安装 Rust..."
if ! command -v cargo >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
export PATH="$HOME/.cargo/bin:$PATH"
rustup default 1.93.1 || rustup default stable

# --- 4. 安装 Flutter (aarch64) ---
echo "[4/6] 安装 Flutter aarch64..."
export PATH="$HOME/flutter/bin:$PATH"
if [ ! -d "$HOME/flutter" ]; then
    FLUTTER_VERSION="3.41.9"
    FLUTTER_URL="https://mirrors.tuna.tsinghua.edu.cn/flutter/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-arm64.tar.xz"
    echo "下载 $FLUTTER_URL"
    wget -q "$FLUTTER_URL" -O /tmp/flutter.tar.xz || {
        echo "指定版本下载失败, 尝试 latest stable..."
        FLUTTER_URL="https://mirrors.tuna.tsinghua.edu.cn/flutter/flutter_infra_release/releases/releases_linux.json"
        LATEST=$(curl -s "$FLUTTER_URL" | python3 -c "import sys,json; d=json.load(sys.stdin); print([r['archive'] for r in d['releases'] if r.get('dart_sdk_arch')=='arm64' and r['channel']=='stable'][0])" 2>/dev/null || echo "")
        if [ -z "$LATEST" ]; then
            echo "错误: 无法定位 Flutter aarch64 下载地址, 请手动下载到 ~/flutter"
            exit 1
        fi
        wget -q "https://mirrors.tuna.tsinghua.edu.cn/flutter/flutter_infra_release/releases/${LATEST}" -O /tmp/flutter.tar.xz
    }
    tar xf /tmp/flutter.tar.xz -C "$HOME"
fi
flutter config --no-analytics
flutter config --enable-linux-desktop
flutter precache --linux

# --- 5. 获取代码 (从 Gitee 国内加速) ---
echo "[5/6] 获取项目代码..."
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"
if [ ! -f "app/pubspec.yaml" ]; then
    echo "当前目录不是项目根, 尝试克隆..."
    cd "$HOME"
    [ -d localsend-improved ] || git clone https://gitee.com/zhuhuidcm/localsend-improved.git
    cd localsend-improved
fi

# --- 6. 构建 ---
echo "[6/6] 构建 Linux ARM64 (请耐心等待, 首次约 20-40 分钟)..."
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs || true
dart run slang || true
flutter build linux --release

echo ""
echo "============================================"
echo "构建完成!"
echo "安装包目录: $(pwd)/build/linux/arm64/release/bundle/"
echo "运行: cd build/linux/arm64/release/bundle && ./localsend_app"
echo "============================================"
