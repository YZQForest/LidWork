# 合盖工作开关

桌面已放置「合盖工作开关.app」1.5.1版，适用于这台 M4 MacBook Air。右下角悬浮面板已移除；平时使用原生 macOS 桌面小组件操作，应用在后台运行。

## 原生桌面小组件

中号「合盖控制」已添加到桌面。以后需要重新添加时：在桌面空白处右键 →「编辑小组件」，搜索「合盖」，将「合盖控制」拖到桌面。提供小号和中号；推荐中号，可直接操作两个开关和 iPad 连接。

小组件包含三个操作：

- **合盖工作**：开启后，接电源或使用电池时都禁止系统睡眠；关闭后恢复系统原有睡眠行为。
- **镜像保活**：保持画面常亮，并创建虚拟显示画布，用于在合盖后继续使用 iPad 随航。关闭后移除虚拟画布，并恢复原有屏幕定时。
- **连接 iPad 镜像**：连接找到的 iPad，并切换为镜像显示。已连接时显示「iPad 镜像已连接」。多个设备时会打开设备选择，请保持 iPad 解锁。

点击操作由本机应用执行，连续操作会依次处理。若 macOS 要求管理员身份验证，请在系统对话框内完成。原生小组件由系统调度刷新，显示状态通常会有数秒调度延迟。App 与小组件共用状态检测；中号右上角的刷新按钮会重新读取并请求更新。状态未能获取时显示省略号，过期显示「待同步」，不会误显示为关闭。小号为概览，中号提供三个操作。

小组件采用两行开关和一行 iPad 镜像入口，配合留白和中性背景。系统透明/着色样式由 WidgetKit 提供原生 Liquid Glass；全彩样式为深浅色中性背景，外观跟随 macOS 的小组件设置。点击标题或空白区域可以打开完整控制窗口。菜单栏的笔记本图标也保留了控制窗口、iPad 镜像管理和登录后台运行入口。只有主动打开控制窗口或操作需要处理时才显示窗口，不再自动显示悬浮面板。

## 使用 iPad

先打开两个开关，再点击「连接 iPad 镜像」，等连接成功后合盖。也可以继续使用 Mac「控制中心 → 屏幕镜像」。开关不会让合上的 Mac 内置屏幕继续发光。

需要断开 iPad 时，从菜单栏打开「管理 iPad 镜像…」，或在完整控制窗口点击 iPad 管理按钮，再选择断开。

关闭控制窗口或退出应用，都不会关闭已启用的两个功能。合盖工作设置在重启后保留，镜像保活通过用户后台任务在重新登录后启动。菜单栏「登录时在后台运行」控制本应用是否随登录运行，不会弹出右下角面板。

开启合盖工作期间，常规自动睡眠和手动睡眠也会暂停。两个功能都会增加耗电；放进包里或长期不用前，请关闭。关闭镜像保活会移除虚拟显示器，请先打开 Mac 上盖，以免中断 iPad 画面。

## 卸载和恢复

先打开 Mac 上盖，关闭两个开关，在菜单栏关闭「登录时在后台运行」，然后退出应用、移除桌面小组件并删除应用。若应用无法打开，可在终端执行以下命令恢复正常睡眠，并移除本应用的后台任务：

```sh
sudo /usr/bin/pmset -a disablesleep 0
/bin/launchctl bootout "gui/$(id -u)/local.yzq.lidwork.display"
/bin/launchctl bootout "gui/$(id -u)/local.yzq.lidwork.widget"
/bin/rm -f "$HOME/Library/LaunchAgents/local.yzq.lidwork.display.plist"
/bin/rm -f "$HOME/Library/LaunchAgents/local.yzq.lidwork.widget.plist"
```

应用不修改原有电池/电源的睡眠定时、屏幕定时、休眠模式或网络权限。

## 1.5.1 更新

小组件重做为简约原生布局，去掉渐变、光晕和嵌套卡片，保留两个开关、iPad 入口与右上角刷新。状态读取、操作队列和同步机制沿用 1.5.0。

## 1.5.0 更新

App 与小组件采用统一的玻璃、青蓝渐变和模糊光晕，适配深浅色。macOS 26+ 的 App 卡片使用原生 Liquid Glass，窗口背景使用实时模糊；原生小组件的透明玻璃由系统样式决定。首次启动新版本自动释放本项目的旧扩展进程并重注册，避免版本不匹配导致系统拒绝刷新。

2026年10月20日，用户已确认修复后状态一致，并确认新版切换开关后小组件正常跟随、界面卡片和开关显示完整。

## 本机验证记录

2026年10月19日已实测电池供电下两次合盖，最长连续观测约52秒，运行采样连续、互联网连接检查通过。你已确认虚拟画布方案解决了本机 iPad 合盖镜像断开，正式版在电池供电下也能正常显示和操作。

镜像保活的开启、关闭、虚拟显示器创建与移除均已验证，原有屏幕定时设置保持不变。此前已验证通过应用断开、重新连接 iPad 并恢复镜像。

1.4版原生 WidgetKit 扩展已在系统小组件库成功渲染小号和中号预览，你已将中号放到桌面并点击三个操作。1.4.1版移除了悬浮面板，加入连续操作队列；已验证两个功能的开启状态、显示器保活断言，以及 Mac 与虚拟画布跟随 iPad 的镜像关系；原生小组件的镜像保活操作也已实际切换系统状态。安装包签名和压缩包完整性检查通过。

上述结果针对当前设备和系统版本，macOS 大版本更新后请重新检查。

技术参考：[Apple 的 pmset 源码](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m)、[Apple 显示器唤醒文档](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridledisplaysleep)、[Apple WidgetKit](https://developer.apple.com/documentation/widgetkit)、[Chromium 的虚拟显示器接口示例](https://chromium.googlesource.com/chromium/src/+/cca923fbde2d338f3730885e0dbe734eee8465a2/ui/display/mac/test/virtual_display_mac_util.mm)、[SidecarLauncher](https://github.com/Ocasio-J/SidecarLauncher)。
