#!/bin/bash
set -euo pipefail

# DesktopPet macOS App 打包脚本
# 用法: bash build.sh

APP_NAME="DesktopPet"       # 可执行文件名，须与 Package.swift target 一致
DISPLAY_NAME="BubblePet"    # 用户可见的应用名
BUNDLE_ID="com.desktoppet.app"
VERSION="1.0.0"
MIN_MACOS="12.0"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/.build"
APP_DIR="${PROJECT_DIR}/${DISPLAY_NAME}.app"
DMG_NAME="${DISPLAY_NAME}.dmg"
DMG_PATH="${PROJECT_DIR}/${DMG_NAME}"
RESOURCES_SRC="${PROJECT_DIR}/Sources/DesktopPet/Resources"

echo "=== ${DISPLAY_NAME} 打包脚本 ==="
echo ""

# ---- 1. 编译 Release (arm64) ----
echo "[1/5] 编译 Release 版本 (arm64)..."
cd "${PROJECT_DIR}"
swift build -c release --arch arm64
echo "  ✓ 编译完成"

EXECUTABLE="${BUILD_DIR}/arm64-apple-macosx/release/${APP_NAME}"
if [ ! -f "${EXECUTABLE}" ]; then
    echo "  ✗ 找不到编译产物: ${EXECUTABLE}"
    exit 1
fi

# ---- 2. 创建 .app Bundle ----
echo "[2/5] 创建 ${APP_NAME}.app..."

# 清理旧的
rm -rf "${APP_DIR}"

# 创建目录结构
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# 复制可执行文件
cp "${EXECUTABLE}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# 复制 SPM 资源 bundle（如果存在）
SPM_BUNDLE="${BUILD_DIR}/arm64-apple-macosx/release/DesktopPet_DesktopPet.bundle"
if [ -d "${SPM_BUNDLE}" ]; then
    cp -R "${SPM_BUNDLE}" "${APP_DIR}/Contents/Resources/"
    # 清理不需要的文件（mp4 源视频、DS_Store）
    find "${APP_DIR}/Contents/Resources/DesktopPet_DesktopPet.bundle" \
        \( -name "*.mp4" -o -name ".DS_Store" -o -name "*.icns" \) -delete
    echo "  ✓ 已复制 SPM 资源 bundle（已清理 mp4/DS_Store）"
fi

# 直接复制资源文件到 Resources（排除 mp4、DS_Store、临时文件）
if [ -d "${RESOURCES_SRC}" ]; then
    find "${RESOURCES_SRC}" -maxdepth 1 -name "*.icns" -exec cp {} "${APP_DIR}/Contents/Resources/" \;
    echo "  ✓ 已复制图标资源 (ICNS)"
fi

# 创建 PkgInfo
echo -n "APPL????" > "${APP_DIR}/Contents/PkgInfo"

# ---- 3. 生成 Info.plist ----
echo "[3/5] 生成 Info.plist..."

cat > "${APP_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>BubblePet</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>BubblePet 需要访问终端来执行命令。</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
echo "  ✓ Info.plist 已生成"

# ---- 4. 代码签名 ----
echo "[4/5] Ad-hoc 代码签名..."
codesign --force --deep -s - "${APP_DIR}"
echo "  ✓ 签名完成"

# ---- 5. 创建 DMG ----
echo "[5/5] 创建 DMG..."

# 清理旧的（先卸载可能挂载的旧 DMG）
hdiutil detach "/Volumes/${DISPLAY_NAME}" 2>/dev/null || true
rm -f "${DMG_PATH}"

# 创建临时目录
DMG_TEMP="${BUILD_DIR}/dmg_temp"
rm -rf "${DMG_TEMP}"
mkdir -p "${DMG_TEMP}"

# 复制 app 到临时目录
cp -R "${APP_DIR}" "${DMG_TEMP}/"

# 创建 Applications 快捷方式
ln -s /Applications "${DMG_TEMP}/Applications"

# 创建 DMG
hdiutil create -volname "${DISPLAY_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${DMG_PATH}"

# 清理临时目录
rm -rf "${DMG_TEMP}"

echo "  ✓ DMG 已创建"

# ---- 完成 ----
echo ""
echo "=== 打包完成！==="
echo "  App: ${APP_DIR}"
echo "  DMG: ${DMG_PATH}"
echo ""
echo "你可以："
echo "  1. 直接运行: open ${APP_DIR}"
echo "  2. 打开 DMG 拖拽安装: open ${DMG_PATH}"
