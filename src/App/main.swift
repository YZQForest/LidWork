import AppKit
import IOKit
import CoreGraphics
import WidgetKit
import SwiftUI
import OSLog

let appTitle = "合盖工作开关"

struct CommandResult {
    let code: Int32
    let output: String
}

func runCommand(_ path: String, _ arguments: [String]) throws -> CommandResult {
    let task = Process()
    let pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    task.standardOutput = pipe
    task.standardError = pipe
    try task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return CommandResult(code: task.terminationStatus, output: String(decoding: data, as: UTF8.self))
}

func readEnabled() throws -> Bool {
    let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard entry != 0 else { throw failure("无法读取系统睡眠状态。") }
    defer { IOObjectRelease(entry) }
    guard let value = IORegistryEntryCreateCFProperty(entry, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else {
        throw failure("系统未提供睡眠开关状态。")
    }
    return value.boolValue
}

func failure(_ message: String) -> NSError {
    NSError(domain: "local.lidwork", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

func setEnabled(_ desired: Bool) throws {
    let value = desired ? "1" : "0"
    let result = try runCommand("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", value])
    if result.code != 0 {
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
        let auth = try runCommand("/usr/bin/osascript", ["-e", script])
        guard auth.code == 0 else {
            if auth.output.contains("-128") { throw failure("已取消授权，设置未更改。") }
            throw failure("无法更改睡眠设置：\n" + auth.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    // Verify the actual kernel flag, rather than trusting pmset's exit code.
    for _ in 0..<30 {
        if try readEnabled() == desired { return }
        Thread.sleep(forTimeInterval: 0.1)
    }
    throw failure("设置尚未生效。请稍后重新打开开关查看状态。")
}

func batterySummary() -> String {
    guard let result = try? runCommand("/usr/bin/pmset", ["-g", "batt"]), result.code == 0 else { return "接电源与使用电池时均生效" }
    let power = result.output.contains("'AC Power'") ? "电源供电" : "电池供电"
    if let range = result.output.range(of: #"\d+%"#, options: .regularExpression) {
        return "\(power) · 电量 \(result.output[range])"
    }
    return power
}

let displayJobLabel = "local.yzq.lidwork.display"
let displayJobDomain = "gui/\(getuid())"
let displayJobURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(displayJobLabel).plist")
let displayHelperURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LidWork/LidWorkDisplay")

func installDisplayHelper() throws {
    let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/LidWorkDisplay")
    guard FileManager.default.fileExists(atPath: bundled.path) else { throw failure("镜像保活组件缺失，请重新打开桌面上的完整应用。") }
    let data = try Data(contentsOf: bundled)
    try FileManager.default.createDirectory(at: displayHelperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if (try? Data(contentsOf: displayHelperURL)) != data {
        try data.write(to: displayHelperURL, options: .atomic)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: displayHelperURL.path)
}

func displayCanvasOnline() -> Bool {
    var displays = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return false }
    return displays.prefix(Int(count)).contains { CGDisplayVendorNumber($0) == 0x4c57 && CGDisplayModelNumber($0) == 1 }
}

func displayJob() throws -> (loaded: Bool, pid: Int32?) {
    let result = try runCommand("/bin/launchctl", ["print", "\(displayJobDomain)/\(displayJobLabel)"])
    guard result.code == 0 else {
        if result.output.contains("Could not find service") || result.output.contains("could not find service") { return (false, nil) }
        throw failure("无法读取画面唤醒状态：\n" + result.output)
    }
    guard let range = result.output.range(of: #"(?m)^\s*pid = (\d+)\s*$"#, options: .regularExpression) else { return (true, nil) }
    let line = String(result.output[range])
    return (true, Int32(line.components(separatedBy: "=").last!.trimmingCharacters(in: .whitespacesAndNewlines)))
}

func readDisplayAwake() throws -> Bool {
    guard let value = DeviceSnapshot.current().display else { throw failure("暂时无法读取镜像保活状态，请刷新后重试。") }
    return value
}

func setDisplayAwake(_ desired: Bool) throws {
    let job = try displayJob()
    if desired {
        if try readDisplayAwake() { return }
        try installDisplayHelper()
        if job.loaded {
            let stop = try runCommand("/bin/launchctl", ["bootout", "\(displayJobDomain)/\(displayJobLabel)"])
            guard stop.code == 0 else { throw failure("无法重启画面唤醒功能：\n" + stop.output) }
        }
        let settings: [String: Any] = [
            "Label": displayJobLabel,
            "ProgramArguments": [displayHelperURL.path],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
            "ThrottleInterval": 10,
            "AssociatedBundleIdentifiers": ["local.yzq.lidwork"]
        ]
        try FileManager.default.createDirectory(at: displayJobURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
        try data.write(to: displayJobURL, options: .atomic)
        let start = try runCommand("/bin/launchctl", ["bootstrap", displayJobDomain, displayJobURL.path])
        guard start.code == 0 else {
            try? FileManager.default.removeItem(at: displayJobURL)
            throw failure("无法开启画面唤醒：\n" + start.output)
        }
    } else {
        if job.loaded {
            let stop = try runCommand("/bin/launchctl", ["bootout", "\(displayJobDomain)/\(displayJobLabel)"])
            guard stop.code == 0 else { throw failure("无法关闭画面唤醒：\n" + stop.output) }
        }
        if FileManager.default.fileExists(atPath: displayJobURL.path) {
            try FileManager.default.removeItem(at: displayJobURL)
        }
    }
    for _ in 0..<30 {
        if try readDisplayAwake() == desired { return }
        Thread.sleep(forTimeInterval: 0.1)
    }
    throw failure("画面唤醒设置尚未生效，请稍后重试。")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let model = ControlModel()
    let sleepSwitch = NSSwitch()
    let displaySwitch = NSSwitch()
    var widget: ControlMenu?
    private var timer: Timer?
    private var busy = false
    private var pendingNativeURLs: [URL] = []
    private var lastNativeWidgetState = ""
    private var lastPowerRead = Date.distantPast
    private var trailingReload: DispatchWorkItem?
    private let logger = Logger(subsystem: "local.yzq.lidwork", category: "AppSync")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        repairWidgetAfterUpdate()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 666), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = appTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.center()
        window.contentView = NSHostingView(rootView: ControlDashboard(model: model,
            setSleep: { [weak self] desired in self?.applySleep(desired) },
            setDisplay: { [weak self] desired in self?.applyDisplay(desired) },
            mirror: { [weak self] in guard let self, let controls = self.widget else { return }; controls.connectIPad(controls.mirrorButton) },
            refresh: { [weak self] in self?.manualRefresh() }))

        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出\(appTitle)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        let close = fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.target = window
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)
        NSApp.mainMenu = menu

        widget = ControlMenu(owner: self)
        NotificationCenter.default.addObserver(self, selector: #selector(fullWindowClosed), name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey), name: NSWindow.didBecomeKeyNotification, object: window)
        refresh(forceWidget: true)
        let poll = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        poll.tolerance = 0.3
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showFullPanel(); return true }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); trailingReload?.cancel() }
    func showFullPanel() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh(forceWidget: true)
    }
    @objc func fullWindowClosed() { NSApp.setActivationPolicy(.accessory) }
    @objc func windowBecameKey() { refresh(forceWidget: true) }
    func manualRefresh() {
        refresh(forceWidget: true)
        updateFeedback("已读取系统状态，正在更新桌面小组件。")
    }
    func updateFeedback(_ message: String) { model.feedback = message }

    private func repairWidgetAfterUpdate() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let key = "widgetRegisteredBuild"
        guard UserDefaults.standard.string(forKey: key) != build else { return }
        let extensionURL = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/LidWorkNativeWidget.appex")
        let executable = extensionURL.appendingPathComponent("Contents/MacOS/LidWorkNativeWidget").path
        do {
            let processes = try runCommand("/bin/ps", ["-axo", "pid=,comm="])
            guard processes.code == 0 else { return }
            // A suspended old widget retains its old Bundle version after a drag
            // update. It has no unsaved user data; only this exact executable is reset.
            for pid in OwnedWidgetProcess.identifiers(in: processes.output, executablePath: executable) {
                _ = try runCommand("/bin/kill", ["-KILL", String(pid)])
            }
            let registration = try runCommand("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f", Bundle.main.bundlePath])
            let plugin = try runCommand("/usr/bin/pluginkit", ["-a", extensionURL.path])
            if registration.code == 0 && plugin.code == 0 {
                UserDefaults.standard.set(build, forKey: key)
                logger.notice("Widget registration repaired for build=\(build, privacy: .public)")
            }
        } catch { logger.error("Widget update repair could not complete") }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingNativeURLs.append(contentsOf: urls.filter { $0.scheme == "lidwork" })
        processNextNativeURL()
    }
    func processNextNativeURL() {
        guard !busy && !model.connecting, !pendingNativeURLs.isEmpty else { return }
        let url = pendingNativeURLs.removeFirst()
        do {
            switch ControlAction(rawValue: url.host ?? "") {
            case .sleep: applySleep(ControlAction.desired(for: url, current: try readEnabled()))
            case .display: applyDisplay(ControlAction.desired(for: url, current: try readDisplayAwake()))
            case .mirror: widget?.connectFromNativeWidget()
            case .refresh: manualRefresh()
            case .show: showFullPanel()
            case nil: break
            }
        } catch { presentError(error.localizedDescription) }
        if !busy && !model.connecting { DispatchQueue.main.async { [weak self] in self?.processNextNativeURL() } }
    }

    func refresh(forceWidget: Bool = false) {
        guard !busy else { return }
        let snapshot = DeviceSnapshot.current()
        model.snapshot = snapshot
        sleepSwitch.state = snapshot.sleep == true ? .on : .off
        displaySwitch.state = snapshot.display == true ? .on : .off
        if forceWidget || Date().timeIntervalSince(lastPowerRead) > 30 {
            model.power = batterySummary()
            lastPowerRead = Date()
        }
        widget?.update(sleep: snapshot.sleep == true, display: snapshot.display == true, sleepValid: snapshot.sleep != nil, displayValid: snapshot.display != nil, powerText: model.power)
        if forceWidget || snapshot.fingerprint != lastNativeWidgetState {
            lastNativeWidgetState = snapshot.fingerprint
            requestWidgetReload()
        }
    }
    private func requestWidgetReload() {
        trailingReload?.cancel()
        logger.notice("Request widget state=\(self.lastNativeWidgetState, privacy: .public)")
        WidgetCenter.shared.reloadTimelines(ofKind: "LidWorkNativeWidget")
        // WidgetKit coalesces rapid requests. One trailing request carries the
        // final state after its visible-widget throttle window, without polling.
        let work = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: "LidWorkNativeWidget")
        }
        trailingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5, execute: work)
    }

    func applySleep(_ desired: Bool) {
        sleepSwitch.state = desired ? .on : .off
        toggleSleep(sleepSwitch)
    }
    func applyDisplay(_ desired: Bool) {
        displaySwitch.state = desired ? .on : .off
        toggleDisplay(displaySwitch)
    }
    @objc func toggleSleep(_ sender: NSSwitch) {
        let desired = sender.state == .on
        performSetting(message: "正在更改合盖工作…", success: desired ? "合盖工作已开启。" : "已恢复系统睡眠行为。") { try setEnabled(desired) }
    }
    @objc func toggleDisplay(_ sender: NSSwitch) {
        let desired = sender.state == .on
        performSetting(message: "正在更改镜像保活…", success: desired ? "镜像保活已开启，可以连接 iPad。" : "镜像保活已关闭，显示画布已移除。") { try setDisplayAwake(desired) }
    }
    private func performSetting(message: String, success: String, operation: @escaping () throws -> Void) {
        guard !busy && !model.connecting else { return }
        busy = true
        model.busy = true
        widget?.setBusy(true, message: message)
        updateFeedback(message)
        DispatchQueue.global(qos: .userInitiated).async {
            var issue: String?
            do { try operation() } catch { issue = error.localizedDescription }
            DispatchQueue.main.async {
                self.busy = false
                self.model.busy = false
                self.widget?.setBusy(false, message: "")
                self.refresh(forceWidget: true)
                if let issue { self.presentError(issue) } else { self.updateFeedback(success) }
                self.processNextNativeURL()
            }
        }
    }
    private func presentError(_ message: String) {
        updateFeedback(message)
        showFullPanel()
        let alert = NSAlert()
        alert.messageText = "设置未完成"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window)
    }
}

if let argument = CommandLine.arguments.dropFirst().first {
    do {
        switch argument {
        case "--status": print(try readEnabled() ? "enabled" : "disabled")
        case "--enable": try setEnabled(true); print(try readEnabled() ? "enabled" : "disabled")
        case "--disable": try setEnabled(false); print(try readEnabled() ? "enabled" : "disabled")
        case "--display-status": print(try readDisplayAwake() ? "enabled" : "disabled")
        case "--display-enable": try setDisplayAwake(true); print(try readDisplayAwake() ? "enabled" : "disabled")
        case "--display-disable": try setDisplayAwake(false); print(try readDisplayAwake() ? "enabled" : "disabled")
        case "--snapshot-json":
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
            print(String(decoding: try encoder.encode(DeviceSnapshot.current()), as: UTF8.self))
        case "--refresh-widgets":
            WidgetCenter.shared.reloadTimelines(ofKind: "LidWorkNativeWidget")
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            print("requested")
        case "--render-previews":
            guard CommandLine.arguments.count > 2 else { throw failure("需要指定预览输出目录。") }
            try MainActor.assumeIsolated { try renderPreviews(to: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)) }
        default: throw failure("未知参数。")
        }
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
