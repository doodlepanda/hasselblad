#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DISPLAY_NAME="FionaFFF"
EXECUTABLE_NAME="ImgSlicer"
APP_VERSION="0.35.2"
APP_BUILD="41"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_BASE_NAME="$APP_DISPLAY_NAME-$APP_VERSION-$APP_BUILD"
RELEASE_NAME="$RELEASE_BASE_NAME"
RELEASE_DIR="$DIST_DIR/$RELEASE_NAME"
APP_DIR="$RELEASE_DIR/$APP_DISPLAY_NAME.app"
LATEST_APP_DIR="$DIST_DIR/$APP_DISPLAY_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
ZIP_PATH="$DIST_DIR/$RELEASE_NAME.zip"
DMG_PATH="$DIST_DIR/$RELEASE_NAME.dmg"
README_PATH="$RELEASE_DIR/其他Mac打开说明.txt"
CHANGELOG_PATH="$RELEASE_DIR/版本更新说明.txt"
INSTALLER_PATH="$RELEASE_DIR/安装.command"

cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
swift build --disable-sandbox -c debug --triple arm64-apple-macosx14.0 --cache-path "$ROOT_DIR/.build/cache-arm64"
swift build --disable-sandbox -c debug --triple x86_64-apple-macosx14.0 --cache-path "$ROOT_DIR/.build/cache-x86_64"

mkdir -p "$DIST_DIR"
if [ -e "$RELEASE_DIR" ] || [ -e "$ZIP_PATH" ] || [ -e "$DMG_PATH" ]; then
  suffix=2
  while [ -e "$DIST_DIR/$RELEASE_BASE_NAME $suffix" ] || [ -e "$DIST_DIR/$RELEASE_BASE_NAME $suffix.zip" ] || [ -e "$DIST_DIR/$RELEASE_BASE_NAME $suffix.dmg" ]; do
    suffix=$((suffix + 1))
  done
  RELEASE_NAME="$RELEASE_BASE_NAME $suffix"
  RELEASE_DIR="$DIST_DIR/$RELEASE_NAME"
  APP_DIR="$RELEASE_DIR/$APP_DISPLAY_NAME.app"
  CONTENTS="$APP_DIR/Contents"
  MACOS="$CONTENTS/MacOS"
  RESOURCES="$CONTENTS/Resources"
  FRAMEWORKS="$CONTENTS/Frameworks"
  ZIP_PATH="$DIST_DIR/$RELEASE_NAME.zip"
  DMG_PATH="$DIST_DIR/$RELEASE_NAME.dmg"
  README_PATH="$RELEASE_DIR/其他Mac打开说明.txt"
  CHANGELOG_PATH="$RELEASE_DIR/版本更新说明.txt"
  INSTALLER_PATH="$RELEASE_DIR/安装.command"
fi

rm -rf "$LATEST_APP_DIR"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"
lipo -create \
  ".build/arm64-apple-macosx/debug/$EXECUTABLE_NAME" \
  ".build/x86_64-apple-macosx/debug/$EXECUTABLE_NAME" \
  -output "$MACOS/$EXECUTABLE_NAME"
install_name_tool -delete_rpath /usr/lib/swift "$MACOS/$EXECUTABLE_NAME" 2>/dev/null || true
install_name_tool -delete_rpath "@loader_path" "$MACOS/$EXECUTABLE_NAME" 2>/dev/null || true
install_name_tool -delete_rpath "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx" "$MACOS/$EXECUTABLE_NAME" 2>/dev/null || true
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$EXECUTABLE_NAME"
xcrun swift-stdlib-tool \
  --copy \
  --scan-executable "$MACOS/$EXECUTABLE_NAME" \
  --destination "$FRAMEWORKS" \
  --platform macosx \
  --sign -
find "$FRAMEWORKS" -name "*.original" -delete
cp "Sources/ImgSlicer/Resources/AppIconSource.png" "$RESOURCES/AppIconSource.png"
cp "Sources/ImgSlicer/Resources/icon.svg" "$RESOURCES/icon.svg"
ditto ".build/arm64-apple-macosx/debug/ImgSlicer_ImgSlicer.bundle" "$RESOURCES/ImgSlicer_ImgSlicer.bundle"
if ! swift scripts/generate-icon.swift "$RESOURCES/AppIcon.icns" "$ROOT_DIR/Sources/ImgSlicer/Resources/AppIconSource.png"; then
  FALLBACK_ICON="$ROOT_DIR/Sources/ImgSlicer/Resources/AppIcon.icns"
  if [ -f "$FALLBACK_ICON" ]; then
    cp "$FALLBACK_ICON" "$RESOURCES/AppIcon.icns"
  else
    echo "无法生成 AppIcon.icns，且没有找到可复用的旧图标。" >&2
    exit 1
  fi
fi

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>ImgSlicer</string>
  <key>CFBundleIdentifier</key>
  <string>local.fiona.fff</string>
  <key>CFBundleName</key>
  <string>FionaFFF</string>
  <key>CFBundleDisplayName</key>
  <string>FionaFFF</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>__APP_VERSION__</string>
  <key>CFBundleVersion</key>
  <string>__APP_BUILD__</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>FionaFFF __APP_VERSION__</string>
</dict>
</plist>
PLIST

sed -i '' \
  -e "s/__APP_VERSION__/$APP_VERSION/g" \
  -e "s/__APP_BUILD__/$APP_BUILD/g" \
  "$CONTENTS/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
xattr -cr "$APP_DIR"

cat > "$README_PATH" <<'TXT'
FionaFFF 其他 Mac 打开说明

如果双击提示“FionaFFF 已损坏，无法打开”，不是文件真的损坏，而是 macOS Gatekeeper 对微信/浏览器收到的未公证应用加了隔离标记。

推荐打开方式：

1. 解压 zip。
2. 双击“安装.command”。
3. 如果系统提示不能打开脚本，请右键“安装.command”选择“打开”。
4. 安装脚本会复制 FionaFFF.app 到“应用程序”，重新本机签名，并清除隔离属性。

手动方式：

1. 把 FionaFFF.app 拖到“应用程序”。
2. 打开“终端”，执行：

   xattr -dr com.apple.quarantine "/Applications/FionaFFF.app"

如果仍然打不开，可执行：

   codesign --force --deep --sign - "/Applications/FionaFFF.app"
   xattr -dr com.apple.quarantine "/Applications/FionaFFF.app"

说明：
当前版本是本地测试包，没有 Apple Developer ID 公证签名。正式商用分发需要使用 Apple Developer ID 证书签名并提交 notarization，才能像普通软件一样直接打开。
TXT

cat > "$CHANGELOG_PATH" <<TXT
$APP_DISPLAY_NAME $APP_VERSION-$APP_BUILD 版本更新说明

打包文件：
- 文件夹：$RELEASE_NAME
- 应用：$APP_DISPLAY_NAME.app
- 压缩包：$RELEASE_NAME.zip
- DMG：$RELEASE_NAME.dmg

本次更新：
- 新增 FFF 测试分支支持：可直接导入哈苏 FlexColor/Flextight 扫描生成的 .fff 文件。
- FFF 文件不再依赖系统 ImageIO 缩略图，软件会读取 TIFF 容器内的 16bit RGB 主图用于预览、自动识别和导出。
- FFF 导出 TIF 时保持 16bit 输出，避免只导出 199px 预览图或低位深图片。
- 文件夹扫描与拖入导入已加入 .fff 扩展名，可与 tif/jpg 文件一起进入任务列表。
- 红框保存/恢复增加 FFF 主图真实尺寸校验，避免系统只识别缩略图尺寸导致历史红框误套用。
- 优化红色裁切框拖动响应，点中后立即进入拖动，减少拖动开始时的卡顿。
- 优化裁切框调整大小时的稳定性，减少拖动边缘时其他边异常抖动。
- 红色裁切框颜色调整为更深、更亮、更明显的红色。
- 右侧参数区新增“只保留当前选框”按钮，可清除当前画面其他红框，只保留当前选中的 1 个。
- 修复旋转或替换同名图片后，旧红框记录被错误恢复，导致导出变成长条形的问题。
- 保存红框记录时新增图片尺寸、文件大小和修改时间校验；旧格式记录或文件已变化时不再自动恢复。
- 重新导入图片时会检查上一次标准框对应的图片长宽比，旋转前后方向不一致时不会自动套用旧模板。
- 修复超高竖向 TIFF 在旋转视图坐标下导出时，窄高红框被直接按原图坐标裁切，导致输出长条形的问题。
- 对超高原图中的窄高旋转视图红框，导出前自动转换为原图宽短裁切区域。
- 收窄红色裁切框的透明拖拽热区，避免鼠标离红线较远时仍触发边缘缩放。
- 角点热区从 64px 收窄到 30px，边缘厚度从 44px 收窄到 18px。
- 打包脚本改为每次生成独立版本文件夹；同版本重复打包会自动追加序号，不覆盖旧测试包。
- 每个版本文件夹内自动生成本文件，方便记录本次客户端变化。

测试重点：
- 直接拖入单个 .fff 文件或包含 .fff 的文件夹，任务列表是否正常出现。
- .fff 文件预览是否显示真实胶片画面，而不是系统缩略图或模糊色块。
- .fff 自动识别后红框是否能正常编辑、套用和导出。
- .fff 导出 TIF 后用 sips/Photoshop 查看是否仍为 16bit。
- 放大预览后拖动红框是否立即跟手。
- 拖动红框边缘或四角调整大小时，固定边是否保持稳定。
- “只保留当前选框”按钮是否只删除当前画面的其他红框，不影响其他图片。
- 导出结果是否仍按当前红框位置裁切。
TXT

cat > "$INSTALLER_PATH" <<'SCRIPT'
#!/bin/bash
set -e

APP_NAME="FionaFFF.app"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SOURCE_DIR/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"

if [ ! -d "$SOURCE_APP" ]; then
  echo "没有找到 $SOURCE_APP"
  read -n 1 -s -r -p "按任意键退出..."
  exit 1
fi

echo "正在安装 FionaFFF 到 /Applications..."
rm -rf "$TARGET_APP" 2>/dev/null || true

if ! ditto "$SOURCE_APP" "$TARGET_APP" 2>/dev/null; then
  echo "需要管理员权限复制到应用程序目录。"
  sudo rm -rf "$TARGET_APP"
  sudo ditto "$SOURCE_APP" "$TARGET_APP"
fi

echo "正在修复其他 Mac 上的 Gatekeeper 隔离标记..."
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
xattr -cr "$TARGET_APP" 2>/dev/null || true

echo "正在进行本机 ad-hoc 签名..."
codesign --force --deep --sign - "$TARGET_APP"

echo "正在启动 FionaFFF..."
open "$TARGET_APP"

echo ""
echo "安装完成。"
read -n 1 -s -r -p "按任意键关闭窗口..."
SCRIPT

chmod +x "$INSTALLER_PATH"

ditto "$APP_DIR" "$LATEST_APP_DIR"
ditto -c -k --keepParent "$RELEASE_DIR" "$ZIP_PATH"
hdiutil create -volname "$RELEASE_NAME" -srcfolder "$RELEASE_DIR" -ov -format UDZO "$DMG_PATH"

echo "$APP_DIR"
echo "$ZIP_PATH"
echo "$DMG_PATH"
