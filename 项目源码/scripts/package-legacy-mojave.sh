#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DISPLAY_NAME="FionaSpotterTool"
EXECUTABLE_NAME="fiona-spotter-tool"
RELEASE_NAME="FionaSpotterTool-Mojave-Intel"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/$RELEASE_NAME"
APP_DIR="$RELEASE_DIR/$APP_DISPLAY_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
EXECUTABLE="$MACOS/$EXECUTABLE_NAME"
REAL_EXECUTABLE="$MACOS/$EXECUTABLE_NAME-bin"
DMG_PATH="$DIST_DIR/$RELEASE_NAME.dmg"
README_PATH="$RELEASE_DIR/其他Mac打开说明.txt"
INSTALLER_PATH="$RELEASE_DIR/安装.command"
DIAGNOSTIC_PATH="$RELEASE_DIR/启动诊断.command"

cd "$ROOT_DIR"
rm -rf "$RELEASE_DIR" "$DMG_PATH"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

swiftc \
  -target x86_64-apple-macosx10.14 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -O \
  -framework AppKit \
  -framework ImageIO \
  -framework CoreGraphics \
  Sources/ImgSlicerLegacy/main.swift \
  -o "$REAL_EXECUTABLE"

cat > "$EXECUTABLE" <<'SCRIPT'
#!/bin/bash

LOG="$HOME/Desktop/fiona-spotter-tool-mojave-launcher.log"
APP_MACOS_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_CONTENTS_DIR="$(cd "$APP_MACOS_DIR/.." && pwd)"
REAL_EXECUTABLE="$APP_MACOS_DIR/fiona-spotter-tool-bin"
FRAMEWORKS_DIR="$APP_CONTENTS_DIR/Frameworks"

if [ -d "$FRAMEWORKS_DIR" ]; then
  rm -f "$FRAMEWORKS_DIR"/libswift*.dylib 2>/dev/null || true
fi

{
  echo "Launcher started: $(date)"
  echo "macOS: $(sw_vers -productVersion 2>/dev/null || true)"
  echo "Executable: $REAL_EXECUTABLE"
  echo "Contents: $APP_CONTENTS_DIR"
  echo "Frameworks:"
  ls -la "$APP_CONTENTS_DIR/Frameworks" 2>&1 || true
  echo "Running app binary..."
} >> "$LOG" 2>&1

exec "$REAL_EXECUTABLE" >> "$LOG" 2>&1
SCRIPT

chmod +x "$EXECUTABLE"

cp "Sources/ImgSlicer/Resources/AppIconSource.png" "$RESOURCES/AppIconSource.png"
swift scripts/generate-icon.swift "$RESOURCES/AppIcon.icns" "$ROOT_DIR/Sources/ImgSlicer/Resources/AppIconSource.png"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>fiona-spotter-tool</string>
  <key>CFBundleIdentifier</key>
  <string>local.fiona.spotter.tool.legacy</string>
  <key>CFBundleName</key>
  <string>FionaSpotterTool</string>
  <key>CFBundleDisplayName</key>
  <string>FionaSpotterTool</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>0.35.2-legacy</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.14</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

install_name_tool -delete_rpath "@executable_path/../Frameworks" "$REAL_EXECUTABLE" 2>/dev/null || true
install_name_tool -add_rpath /usr/lib/swift "$REAL_EXECUTABLE" 2>/dev/null || true

cat > "$README_PATH" <<'TXT'
FionaSpotterTool Mojave Intel 打开说明

这个包用于 macOS 10.14.6 Mojave Intel 电脑。

推荐打开方式：

1. 打开 DMG。
2. 双击“安装.command”。
3. 如果系统提示不能打开脚本，请右键“安装.command”选择“打开”。
4. 脚本会复制 FionaSpotterTool.app 到“应用程序”，重新本机签名，并清除 Gatekeeper 隔离标记。

如果双击 app 提示“已损坏”或“无法验证开发者”，通常不是文件损坏，而是未公证测试包被 macOS 加了隔离标记。

手动修复：

   xattr -dr com.apple.quarantine "/Applications/FionaSpotterTool.app"
   codesign --force --deep --sign - "/Applications/FionaSpotterTool.app"

说明：
当前是本地测试包，没有 Apple Developer ID 公证签名。正式分发需要 Apple Developer ID 签名并 notarize。
TXT

cat > "$INSTALLER_PATH" <<'SCRIPT'
#!/bin/bash
set -e

APP_NAME="FionaSpotterTool.app"
OLD_APP_NAME="fiona spotter tool.app"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SOURCE_DIR/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"
OLD_TARGET_APP="/Applications/$OLD_APP_NAME"

if [ ! -d "$SOURCE_APP" ]; then
  echo "没有找到 $SOURCE_APP"
  read -n 1 -s -r -p "按任意键退出..."
  exit 1
fi

echo "正在安装 FionaSpotterTool 到 /Applications..."
if [ -e "$OLD_TARGET_APP" ]; then
  echo "正在删除旧版本 $OLD_TARGET_APP..."
  if ! rm -rf "$OLD_TARGET_APP" 2>/dev/null; then
    sudo rm -rf "$OLD_TARGET_APP"
  fi
fi

if [ -e "$TARGET_APP" ]; then
  echo "正在删除旧版本..."
  if ! rm -rf "$TARGET_APP" 2>/dev/null; then
    sudo rm -rf "$TARGET_APP"
  fi
fi

if ! ditto "$SOURCE_APP" "$TARGET_APP" 2>/dev/null; then
  echo "需要管理员权限复制到应用程序目录。"
  sudo rm -rf "$TARGET_APP"
  sudo ditto "$SOURCE_APP" "$TARGET_APP"
fi

rm -f "$TARGET_APP/Contents/Frameworks"/libswift*.dylib 2>/dev/null || true

echo "正在修复 Gatekeeper 隔离标记..."
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
xattr -cr "$TARGET_APP" 2>/dev/null || true

echo "正在进行本机 ad-hoc 签名..."
codesign --force --deep --sign - "$TARGET_APP"

echo "正在启动 FionaSpotterTool..."
open "$TARGET_APP"

echo ""
echo "安装完成。"
read -n 1 -s -r -p "按任意键关闭窗口..."
SCRIPT

chmod +x "$INSTALLER_PATH"

cat > "$DIAGNOSTIC_PATH" <<'SCRIPT'
#!/bin/bash
set -e

APP_NAME="FionaSpotterTool.app"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SOURCE_DIR/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"
LOG="$HOME/Desktop/fiona-spotter-tool-diagnostic.log"

echo "Diagnostic started: $(date)" > "$LOG"
echo "macOS: $(sw_vers -productVersion)" >> "$LOG"
echo "Source app: $SOURCE_APP" >> "$LOG"
echo "Target app: $TARGET_APP" >> "$LOG"

if [ -d "$TARGET_APP" ]; then
  APP="$TARGET_APP"
else
  APP="$SOURCE_APP"
fi

echo "Using app: $APP" >> "$LOG"
xattr -dr com.apple.quarantine "$APP" 2>>"$LOG" || true
xattr -cr "$APP" 2>>"$LOG" || true
codesign --force --deep --sign - "$APP" >> "$LOG" 2>&1 || true

echo "Executable file:" >> "$LOG"
file "$APP/Contents/MacOS/fiona-spotter-tool" >> "$LOG" 2>&1 || true
file "$APP/Contents/MacOS/fiona-spotter-tool-bin" >> "$LOG" 2>&1 || true
echo "Linked libraries:" >> "$LOG"
otool -L "$APP/Contents/MacOS/fiona-spotter-tool-bin" >> "$LOG" 2>&1 || true
echo "Launching via app launcher..." >> "$LOG"
"$APP/Contents/MacOS/fiona-spotter-tool" >> "$LOG" 2>&1 &

echo "诊断已启动，日志在桌面：fiona-spotter-tool-diagnostic.log"
echo "应用自己的启动日志在桌面：fiona-spotter-tool-mojave.log"
echo "启动器日志在桌面：fiona-spotter-tool-mojave-launcher.log"
read -n 1 -s -r -p "按任意键关闭窗口..."
SCRIPT

chmod +x "$DIAGNOSTIC_PATH"

codesign --force --deep --sign - "$APP_DIR"
xattr -cr "$APP_DIR"
hdiutil create -volname "$RELEASE_NAME" -srcfolder "$RELEASE_DIR" -ov -format UDZO "$DMG_PATH"

echo "$APP_DIR"
echo "$DMG_PATH"
