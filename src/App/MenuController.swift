import AppKit

private let widgetLoginURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/local.yzq.lidwork.widget.plist")

func setWidgetLogin(_ enabled: Bool) throws {
    if enabled {
        let settings: [String: Any] = [
            "Label": "local.yzq.lidwork.widget",
            "ProgramArguments": ["/usr/bin/open", "-g", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "AssociatedBundleIdentifiers": ["local.yzq.lidwork"]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: widgetLoginURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: widgetLoginURL, options: .atomic)
    } else {
        _ = try? runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())/local.yzq.lidwork.widget"])
        if FileManager.default.fileExists(atPath: widgetLoginURL.path) { try FileManager.default.removeItem(at: widgetLoginURL) }
    }
}

final class ControlMenu: NSObject {
    weak var owner: AppDelegate?
    let mirrorButton = NSButton()
    private var statusItem: NSStatusItem!
    private let sidecar = SidecarController()
    private var connecting = false
    private var configurationBusy = false

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        mirrorButton.bezelStyle = .rounded
        mirrorButton.target = self
        mirrorButton.action = #selector(connectIPad(_:))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "合盖控制")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusMenu(_:))
        if !UserDefaults.standard.bool(forKey: "widgetLoginConfigured") {
            do {
                try setWidgetLogin(true)
                UserDefaults.standard.set(true, forKey: "widgetLoginConfigured")
            } catch { feedback(error.localizedDescription) }
        } else if FileManager.default.fileExists(atPath: widgetLoginURL.path) {
            try? setWidgetLogin(true)
        }
    }
    func update(sleep: Bool, display: Bool, sleepValid: Bool, displayValid: Bool, powerText: String) {
        statusItem.button?.toolTip = "合盖工作：\(sleep ? "开启" : "关闭") · 镜像保活：\(display ? "开启" : "关闭")"
        if !connecting { mirrorButton.title = sidecarIsConnected() ? "iPad 镜像已连接 · 管理…" : "连接 iPad 镜像" }
        mirrorButton.isEnabled = !connecting && !configurationBusy
    }
    func setBusy(_ value: Bool, message: String) {
        configurationBusy = value
        mirrorButton.isEnabled = !value && !connecting
        if !message.isEmpty { feedback(message) }
    }
    func feedback(_ message: String) {
        owner?.updateFeedback(message)
    }
    private func report(_ message: String) { feedback(message); owner?.showFullPanel() }
    @objc func statusMenu(_ sender: NSButton) {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }
        _ = add("打开控制窗口…", #selector(showFullPanel))
        _ = add(sidecarIsConnected() ? "管理 iPad 镜像…" : "连接 iPad 镜像", #selector(mirrorMenu))
        menu.addItem(.separator())
        add("登录时在后台运行", #selector(toggleLogin)).state = FileManager.default.fileExists(atPath: widgetLoginURL.path) ? .on : .off
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "退出（保留开关状态）", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
    }
    @objc func showFullPanel() { owner?.showFullPanel() }
    @objc func toggleLogin() {
        do { try setWidgetLogin(!FileManager.default.fileExists(atPath: widgetLoginURL.path)) }
        catch { report(error.localizedDescription) }
    }
    @objc func mirrorMenu() { owner?.showFullPanel(); connectIPad(mirrorButton) }
    func connectFromNativeWidget() {
        guard !sidecarIsConnected() else { feedback("iPad 镜像已连接"); return }
        connectIPad(mirrorButton)
    }
    @objc func connectIPad(_ sender: NSButton) {
        guard !connecting && !configurationBusy else { return }
        do {
            let devices = try sidecar.devices()
            guard !devices.isEmpty else { throw failure("未找到 iPad，请先解锁 iPad 并开启蓝牙和无线局域网。") }
            if devices.count == 1 && !sidecarIsConnected() { connect(device: devices[0], desired: true); return }
            owner?.showFullPanel()
            let menu = NSMenu()
            for device in devices {
                let item = menu.addItem(withTitle: "连接 \(sidecar.name(of: device))", action: #selector(selectConnect(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = device
            }
            if sidecarIsConnected(), let device = try sidecar.connectedDevices().first ?? devices.first {
                menu.addItem(.separator())
                let item = menu.addItem(withTitle: "断开 iPad 镜像", action: #selector(selectDisconnect(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = device
            }
            if let content = owner?.window.contentView {
                menu.popUp(positioning: nil, at: NSPoint(x: content.bounds.midX, y: content.bounds.midY - 110), in: content)
            }
        } catch { report(error.localizedDescription) }
    }
    @objc func selectConnect(_ sender: NSMenuItem) { if let device = sender.representedObject as? NSObject { connect(device: device, desired: true) } }
    @objc func selectDisconnect(_ sender: NSMenuItem) { if let device = sender.representedObject as? NSObject { connect(device: device, desired: false) } }
    private func connect(device: NSObject, desired: Bool) {
        connecting = true
        owner?.model.connecting = true
        mirrorButton.title = desired ? "正在连接 iPad…" : "正在断开…"
        mirrorButton.isEnabled = false
        feedback(desired ? "请保持 iPad 解锁，正在建立镜像" : "正在断开 iPad 镜像")
        sidecar.perform(device: device, connect: desired) { [weak self] error in
            guard let self else { return }
            if let error, !(desired && sidecarIsConnected()) { self.finishConnection(error.localizedDescription, failed: true) }
            else { self.verifyConnection(desired: desired, deadline: Date().addingTimeInterval(10)) }
        }
    }
    private func verifyConnection(desired: Bool, deadline: Date) {
        if sidecarIsConnected() == desired {
            do { if desired { try ensureSidecarMirror() } }
            catch { finishConnection(error.localizedDescription, failed: true); return }
            finishConnection(desired ? "iPad 镜像已连接，可以合盖使用" : "已断开 iPad 镜像")
        } else if Date() < deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.verifyConnection(desired: desired, deadline: deadline) }
        } else { finishConnection("连接状态尚未确认，请在控制中心查看", failed: true) }
    }
    private func finishConnection(_ message: String, failed: Bool = false) {
        connecting = false
        owner?.model.connecting = false
        owner?.refresh(forceWidget: true)
        feedback(message)
        if failed { owner?.showFullPanel() }
        owner?.processNextNativeURL()
    }
}
