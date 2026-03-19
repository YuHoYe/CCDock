#!/bin/bash
# 将 SPM 构建产物打包为 macOS .app bundle
set -e

APP_NAME="CCDock"
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$BUILD_DIR"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# 先构建
cd "$PROJECT_DIR"
swift build

# 清理旧 bundle
rm -rf "$APP_BUNDLE"

# 创建 .app 结构
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制可执行文件
cp ".build/debug/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 复制 resource bundle（包含 AppIcon.icns）
cp -R ".build/debug/${APP_NAME}_${APP_NAME}.bundle" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true

# 复制图标到 Resources 根目录（macOS 标准位置）
cp ".build/debug/${APP_NAME}_${APP_NAME}.bundle/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true

# 生成 Info.plist（带 bundle identifier）
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.yuho.CCDock</string>
    <key>CFBundleName</key>
    <string>CCDock</string>
    <key>CFBundleDisplayName</key>
    <string>CCDock</string>
    <key>CFBundleExecutable</key>
    <string>CCDock</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "✅ Built $APP_BUNDLE"
