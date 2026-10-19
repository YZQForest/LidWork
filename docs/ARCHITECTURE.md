# 开发说明

## 进程与状态

宿主应用 `local.yzq.lidwork` 使用 AppKit，默认以 accessory 模式在后台运行。完整控制窗口按需打开；菜单栏由 `ControlMenu` 管理，没有常驻悬浮面板。

睡眠开关读取 `IOPMrootDomain.SleepDisabled`，写入时先尝试 `sudo -n pmset`，无法使用现有权限时才弹出 macOS 管理员授权。命令返回后再次读取内核状态核对。不会保存管理员密码或安装自定义 sudoers 规则。

镜像保活通过用户 LaunchAgent `local.yzq.lidwork.display` 运行 `LidWorkDisplay`。应用从自身 bundle 将后台组件安装到 `~/Library/Application Support/LidWork/`；LaunchAgent 位于 `~/Library/LaunchAgents/`。组件保留一个 `CGVirtualDisplay` 和显示器唤醒断言，每两秒维护画布的镜像关系。完整控制窗口同时检查任务 PID、画布与对应断言，避免仅相信任务已加载。

`local.yzq.lidwork.widget` 是可选的登录后台运行任务，仅使用 `open -g` 打开宿主。它不显示悬浮面板，且与镜像保活任务分开管理。

## 原生小组件

`local.yzq.lidwork.nativewidget` 是沙盒化 WidgetKit 扩展，支持小号、中号，kind 为 `LidWorkNativeWidget`。小组件通过 IOKit 和 CoreGraphics 读取状态；其中镜像保活状态检测虚拟画布是否在线，完整控制窗口另有任务与断言核对。

扩展不执行管理员命令，而是用 `lidwork://sleep`、`lidwork://display`、`lidwork://mirror` 链接把动作交给宿主。开关链接携带当前画面所对应的目标状态；WidgetKit 刷新较慢时应以宿主实际状态为准。空白区域链接为 `lidwork://show`。

宿主将收到的动作加入主线程队列；上一次设置未完成时等待再执行，防止连续点击时丢弃后续请求。宿主检测到两个功能或随航连接状态改变时，请求 `WidgetCenter` 更新；最终刷新时机仍由系统决定。

命令行构建 WidgetBundle 时，需要显式把 Mach-O 入口设为 `_NSExtensionMain`。不加此链接参数时，本机扩展会在 `EXRunningExtension` 初始化阶段崩溃。构建脚本已固定该入口，并先签后台可执行文件、再签沙盒扩展、最后签宿主。

## 随航与兼容性

`SidecarController` 动态加载 `SidecarCore.framework`，查询设备、连接及断开。连接完成后使用 CoreGraphics 设置本次会话的镜像关系。虚拟显示器声明使用私有 `CGVirtualDisplay` 类；系统更新可能更改这些接口。

设备名只用于本机设备选择界面，不会写入仓库，也不会上传到服务端。仓库无遥测、后端、API 密钥或运行时网络依赖；建立随航连接仍使用系统自己的连接机制。

## 本地诊断

宿主支持以下只读命令：

```sh
"/path/to/合盖工作开关.app/Contents/MacOS/LidWork" --status
"/path/to/合盖工作开关.app/Contents/MacOS/LidWork" --display-status
```

写入命令是 `--enable`、`--disable`、`--display-enable`、`--display-disable`，应在理解设置影响后使用。

`tools/DisplayCheck.swift` 仅列出显示器状态和镜像关系；`tools/GenerateIcon.swift` 是图标绘制源码。它们不参与运行时，不需要保留在安装设备上。

## 发布规则

- 修改版本时同步 `VERSION` 和 `BUILD_NUMBER`；构建脚本会更新两个 bundle 的 Info.plist。
- 源码与资源提交到 Git，`build/`、`dist/`、签名证书、日志和实验文件忽略。
- 执行 `build.sh`、`verify.sh`、`package.sh`，把 `dist/` 文件上传到 Release。
- 需要面向陌生设备正常分发时，另行配置自己的 Developer ID 与公证流程；当前脚本只产生本地 ad hoc 签名。
- CI 只验证构建和包结构；真实合盖、电池运行、随航显示与输入必须在实体设备上验证。
