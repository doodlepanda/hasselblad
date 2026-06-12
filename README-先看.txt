ImgSlicer 完整交付包

目录说明：

1. 可运行安装包/ImgSlicer-0.35.2-37
   给其他 Mac 直接运行使用。进入这个目录后双击“安装.command”。

2. 项目源码
   当前项目源码、需求/设计文件、图标、测试图片和打包脚本。没有包含 .build、.venv、输出图片等本机缓存。

其他 Mac 打开方式：

1. 解压本 zip。
2. 打开“可运行安装包/ImgSlicer-0.35.2-37”。
3. 双击“安装.command”。
4. 如果系统提示无法打开脚本，请右键“安装.command”选择“打开”。

如果仍提示“应用已损坏”，原因通常是 macOS Gatekeeper 对微信/浏览器传来的未公证应用加了隔离标记。
安装脚本已经会自动执行清除隔离和本机 ad-hoc 签名。

正式无提示分发说明：

当前包是本地测试签名。若要让任何 Mac 都像普通软件一样双击打开，需要使用 Apple Developer ID 证书签名并提交 Apple notarization 公证。

源码编译：

需要 macOS 14 或更高版本，以及 Xcode/Swift 工具链。
在项目源码目录执行：

swift build

重新打包：

bash scripts/package-mac.sh
