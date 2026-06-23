#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE_NAME="fiona-spotter-tool"
APP_VERSION="0.35.3"
APP_BUILD="74"
APP_DISPLAY_NAME="FionaFFF Test Mojave $APP_VERSION-$APP_BUILD"
APP_BUNDLE_ID="local.fiona.fff.test.mojave.v0353.b74"
RELEASE_BASE_NAME="FionaFFF-Test-Mojave-Intel-$APP_VERSION-$APP_BUILD"
RELEASE_NAME="$RELEASE_BASE_NAME"
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
CHANGELOG_PATH="$RELEASE_DIR/版本更新说明.txt"
INSTALLER_PATH="$RELEASE_DIR/安装.command"
DIAGNOSTIC_PATH="$RELEASE_DIR/启动诊断.command"

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"
if [ -e "$RELEASE_DIR" ] || [ -e "$DMG_PATH" ]; then
  suffix=2
  while [ -e "$DIST_DIR/$RELEASE_BASE_NAME $suffix" ] || [ -e "$DIST_DIR/$RELEASE_BASE_NAME $suffix.dmg" ]; do
    suffix=$((suffix + 1))
  done
  RELEASE_NAME="$RELEASE_BASE_NAME $suffix"
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
  CHANGELOG_PATH="$RELEASE_DIR/版本更新说明.txt"
  INSTALLER_PATH="$RELEASE_DIR/安装.command"
  DIAGNOSTIC_PATH="$RELEASE_DIR/启动诊断.command"
fi
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

swiftc \
  -target x86_64-apple-macosx10.14 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -O \
  -framework AppKit \
  -framework ImageIO \
  -framework CoreGraphics \
  Sources/ImgSlicerLegacy/main.swift \
  Sources/ImgSlicer/Processing/HasselbladFFFDecoder.swift \
  -o "$REAL_EXECUTABLE"

cat > "$EXECUTABLE" <<'SCRIPT'
#!/bin/bash

LOG="$HOME/Desktop/fionafff-mojave-launcher.log"
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
  <string>fiona-spotter-tool</string>
  <key>CFBundleIdentifier</key>
  <string>__APP_BUNDLE_ID__</string>
  <key>CFBundleName</key>
  <string>__APP_DISPLAY_NAME__</string>
  <key>CFBundleDisplayName</key>
  <string>__APP_DISPLAY_NAME__</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>__APP_VERSION__</string>
  <key>CFBundleVersion</key>
  <string>__APP_BUILD__</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.14</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

sed -i '' \
  -e "s/__APP_DISPLAY_NAME__/$APP_DISPLAY_NAME/g" \
  -e "s/__APP_BUNDLE_ID__/$APP_BUNDLE_ID/g" \
  -e "s/__APP_VERSION__/$APP_VERSION/g" \
  -e "s/__APP_BUILD__/$APP_BUILD/g" \
  "$CONTENTS/Info.plist"

install_name_tool -delete_rpath "@executable_path/../Frameworks" "$REAL_EXECUTABLE" 2>/dev/null || true
install_name_tool -add_rpath /usr/lib/swift "$REAL_EXECUTABLE" 2>/dev/null || true

cat > "$README_PATH" <<'TXT'
__APP_DISPLAY_NAME__ Intel 打开说明

这个包用于 macOS 10.14.6 Mojave Intel 电脑。

推荐打开方式：

1. 打开 DMG。
2. 双击“安装.command”。
3. 如果系统提示不能打开脚本，请右键“安装.command”选择“打开”。
4. 脚本会复制 __APP_DISPLAY_NAME__.app 到“应用程序”，重新本机签名，并清除 Gatekeeper 隔离标记。

如果双击 app 提示“已损坏”或“无法验证开发者”，通常不是文件损坏，而是未公证测试包被 macOS 加了隔离标记。

手动修复：

   xattr -dr com.apple.quarantine "/Applications/__APP_DISPLAY_NAME__.app"
   codesign --force --deep --sign - "/Applications/__APP_DISPLAY_NAME__.app"

说明：
当前是本地测试包，没有 Apple Developer ID 公证签名。正式分发需要 Apple Developer ID 签名并 notarize。
TXT

sed -i '' -e "s/__APP_DISPLAY_NAME__/$APP_DISPLAY_NAME/g" "$README_PATH"

cat > "$CHANGELOG_PATH" <<TXT
$APP_DISPLAY_NAME Mojave Intel $APP_VERSION-$APP_BUILD 版本更新说明

打包文件：
- 文件夹：$RELEASE_NAME
- 应用：$APP_DISPLAY_NAME.app
- DMG：$RELEASE_NAME.dmg

本次更新：
- 底部文件栏取消图片缩略图，只显示系统文件图标、文件名和删除按钮，不再为每个文件解码预览图。
- 删除非当前文件时不再重新加载当前大图，减少删除和列表刷新的等待；底栏高度同步缩小，扩大中央画布。
- 左侧任务列表固定按导入顺序从上到下排列。
- 左侧工具栏按文件操作、自动识别、旋转、缩放、应用与查看工具重新排列，移除当前图片下拉菜单，任务列表使用剩余纵向空间。
- 右侧第一排只保留新增和删除当前选框，第二排统一微调；算法候选改为直接可点击列表，显示算法名称、识别张数和可信度。
- 键盘方向键绑定为移动当前图片全部红框，支持按住连续微调。
- FFF/3F 解析默认关闭，需要时可在右侧手动开启。
- 重做左侧任务区：取消任务下拉菜单，改为按文件夹名称显示的竖向任务列表；每个任务可直接选择、单独终止或删除。
- 左侧工具重新分区为任务列表、文件操作、当前图片与画面工具，减少按钮混杂并扩大任务列表可视面积。
- 优化画布交互性能：拖动画布、拖动红框和滚轮缩放期间统一使用约 1800px 的轻量预览缓存，并将重绘限制在约 60fps，操作结束后恢复高清显示。
- JPG 导出质量提升至 ImageIO 最高等级 1.0，显著增大文件体积并减少胶片颗粒、天空、树叶和建筑细节的压缩损失；完全无损仍建议使用 TIF 16-bit。
- 2x6 固定胶片识别后，全部 12 个红框统一沿用第一个手工调整红框的宽高，算法只负责确定各画面中心位置。
- 改进除尘算法：支持草地等有色背景上的半透明白色小尘点，并通过小面积和纹理保护减少误伤树叶与画面细节。
- 增加天空低反差白点、断续细线、弯曲划痕和跨越建筑区域划痕检测，保留窗格、栏杆和建筑纹理。
- 优化除尘算法：增加白色/低色彩瑕疵判断和局部纹理保护，避免树叶、屋顶纹理、雕花高光被误判后出现涂抹变形。
- 取消色阶、曲线、白平衡工具入口。
- 左侧放大镜支持快捷键 D；默认关闭，避免拖动红框时额外绘制造成卡顿。
- 优化拖动性能：拖动过程中不再持续保存和刷新统计，松手后再提交红框变化。
- 进一步优化拖动性能：拖动红框时只局部刷新旧/新红框和放大镜区域，避免整张画布重绘。
- 放大镜开启后，显示完整红框和外侧边缘区域，并保持原比例不拉伸，便于检查是否裁到黑边。
- 同步 14 版负片检测分支：自动识别优先使用浅色片距、画面纹理密度和规律间距一致性查找 FFF/负片画面。
- 针对横向两排胶片扫描增加分割分支：先识别上下胶片条，再按竖向黑/浅色片距拆成单张画面；测试图可识别 12 张。
- 横向胶片扫描增加规律片距补偿：当竖向分隔线被画面内容遮挡或不完整时，按胶片条整体比例补齐 6 格，修复只能识别 4 张的问题。
- 胶片识别按“照片-固定片距-照片”的规律生成等尺寸候选框，并根据片距和上下边缘安全内缩，减少选框碰到黑片距、上黑边和下白边。
- 针对 2 行 x 6 张、3:2 横向胶片扫描改为强约束模型：先锁定每条胶片的左右边界，再每行强制生成 6 个不重叠框；黑片距只用于安全内缩，不再决定张数。
- 修复 2x6 强约束结果又被内容裁边和长宽比过滤破坏的问题：标准两行胶片现在直接返回 12 个不重叠网格框，不再被人物/高光/暗部误裁成局部小框。
- 移植 14 版候选思路：Mojave 自动识别现在会同时比较 2x6 固定胶片、片距识别、模板定位、中心投影，并在右侧栏显示每套算法识别张数与可信度。
- 右侧栏增加“算法结果”下拉菜单，可手动切换不同算法候选；应用候选时只使用算法给出的中心位置，红框宽高固定沿用第一红框，避免同一卷画面忽大忽小。
- 改进 2x6 固定胶片与浅色/黑色片距算法：先在每行内部重新寻找真实画面内容范围，再生成等距中心点；增加上沿和左右片距安全避让，减少裁到黑边或片距。
- 改进模板定位算法：保留较准确的横向定位，只对纵向中心做轻微下移补偿，减少选框偏上。
- 底部图片预览区加高，缩略图放宽放大，减少显示不全。
- 缩略图增加内存缓存，移除底部单张文件时不再重新解码所有缩略图，降低删除卡顿。
- Command+Q 退出时如果仍有未终止任务，会弹出确认框，防止误退出。
- 底部预览栏再次加高，缩略图保持原始比例缩放，不再压扁或裁切显示。
- 右侧“统一微调”方向按钮支持按住连续移动，松开停止，便于快速整体校准红框位置。
- 自动识别默认采用“中心投影”候选，其他 2x6 固定胶片、浅色/黑色片距、模板定位仍保留在算法结果下拉中作为备选。
- 底部胶片栏改为深色缩略图卡片，去掉按钮自带大白边，缩略图按原始比例完整显示在底部边栏内。
- 增加“解析 FFF/3F 文件”开关；关闭后导入会跳过 .fff/.3f 文件，预览、识别和导出也不会读取 Hasselblad FFF/3F 解码器。
- 放大镜针对 27 寸显示器增大显示区域，并减少外侧取样留白，让红框边缘检查的实际放大效果更明显。
- 调整底部胶片栏单张文件删除按钮：按钮放大并内移，选择点击区域避开右上角，避免删除按钮被遮挡或点不到。
- 修复胶片专用识别结果又被当前红框模板尺寸覆盖的问题；负片/胶片分支现在直接使用算法计算出的真实照片边界，避免 12 张被重叠去重成少数几张。
- 导出文件名序号按红框行列顺序生成：先按第一行从左到右，再第二行从左到右；同一行轻微上下偏差不会打乱编号。
- 优化鼠标滚轮缩放：合并高频滚轮事件，缩放过程中使用低插值快速预览，停止滚轮后恢复高质量重绘，减少卡顿。
- 进一步优化滚轮缩放：为预览图建立约 2200px 的滚轮专用缓存，滚动时不再反复绘制 6200px 大图，停止滚轮后再切回完整预览。
- 增加快捷键 S，功能与 Delete 一样删除当前选框；右侧栏底部显示快捷键说明。
- 放大镜调大并贴近当前拖动位置；红框线条改细，减少遮挡边缘判断。
- 底部图片文件区每张缩略图增加单独移除按钮，只从当前任务列表移除，不删除磁盘原图。
- 导入、打开当前图片所在文件夹、选择导出文件夹改用不同图标，减少功能混淆。
- 顶部栏支持双击最大化，再次双击恢复。
- 顶部副标题显示 Mojave build 号，方便确认打开的是最新 Mojave 包。

说明：
- Mojave 版没有 14 版的 .imgslicer-edits.json 持久化恢复逻辑，所以不存在跨重启恢复旧隐藏红框记录的问题。
- Mojave 版原本存在内存模板跨导入复用的相似风险，本版本已加长宽比校验。
TXT

cat > "$INSTALLER_PATH" <<'SCRIPT'
#!/bin/bash
set -e

APP_NAME="__APP_DISPLAY_NAME__.app"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SOURCE_DIR/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"

if [ ! -d "$SOURCE_APP" ]; then
  echo "没有找到 $SOURCE_APP"
  read -n 1 -s -r -p "按任意键退出..."
  exit 1
fi

echo "正在安装 __APP_DISPLAY_NAME__ 到 /Applications..."
echo "正在关闭可能仍在运行的旧版 FionaFFF..."
killall "fiona-spotter-tool-bin" 2>/dev/null || true
killall "fiona-spotter-tool" 2>/dev/null || true
sleep 1

for OLD_APP in \
  "/Applications/FionaFFF Test Mojave 0.35.2.app" \
  "/Applications/FionaFFF Test Mojave 0.35.3-74.app"; do
  if [ -e "$OLD_APP" ] && [ "$OLD_APP" != "$TARGET_APP" ]; then
    echo "正在移除旧测试版：$OLD_APP"
    if ! rm -rf "$OLD_APP" 2>/dev/null; then
      sudo rm -rf "$OLD_APP"
    fi
  fi
done

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

echo "正在启动 __APP_DISPLAY_NAME__..."
open "$TARGET_APP"

echo ""
echo "安装完成。"
read -n 1 -s -r -p "按任意键关闭窗口..."
SCRIPT

sed -i '' -e "s/__APP_DISPLAY_NAME__/$APP_DISPLAY_NAME/g" "$INSTALLER_PATH"

chmod +x "$INSTALLER_PATH"

cat > "$DIAGNOSTIC_PATH" <<'SCRIPT'
#!/bin/bash
set -e

APP_NAME="__APP_DISPLAY_NAME__.app"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SOURCE_DIR/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"
LOG="$HOME/Desktop/fionafff-diagnostic.log"

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

echo "诊断已启动，日志在桌面：fionafff-diagnostic.log"
echo "应用自己的启动日志在桌面：fionafff-mojave.log"
echo "启动器日志在桌面：fionafff-mojave-launcher.log"
read -n 1 -s -r -p "按任意键关闭窗口..."
SCRIPT

sed -i '' -e "s/__APP_DISPLAY_NAME__/$APP_DISPLAY_NAME/g" "$DIAGNOSTIC_PATH"

chmod +x "$DIAGNOSTIC_PATH"

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
hdiutil create -volname "$RELEASE_NAME" -srcfolder "$RELEASE_DIR" -ov -format UDZO "$DMG_PATH"

SMB_COPY_DIR="/Volumes/照片临时/fionafff客户端"
if [ "${COPY_TO_SMB:-0}" = "1" ] && [ -d "$(dirname "$SMB_COPY_DIR")" ]; then
  mkdir -p "$SMB_COPY_DIR" 2>/dev/null || true
  if [ -d "$SMB_COPY_DIR" ] && cp -f "$DMG_PATH" "$SMB_COPY_DIR/"; then
    echo "已复制 DMG 到 SMB：$SMB_COPY_DIR/$(basename "$DMG_PATH")"
  else
    echo "未能复制 DMG 到 SMB：$SMB_COPY_DIR"
  fi
else
  echo "未启用 SMB 复制，跳过：$SMB_COPY_DIR"
fi

echo "$APP_DIR"
echo "$DMG_PATH"
