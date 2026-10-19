import AppKit
import IOKit
import CoreGraphics
import WidgetKit

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
    guard let pid = try displayJob().pid else { return false }
    let assertions = try runCommand("/usr/bin/pmset", ["-g", "assertions"])
    guard assertions.code == 0 else { throw failure("无法读取显示器唤醒状态。") }
    return displayCanvasOnline() && assertions.output.components(separatedBy: .newlines).contains {
        $0.contains("pid \(pid)(LidWorkDisplay):") && $0.contains("PreventUserIdleDisplaySleep")
    }
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
    let sleepSwitch = NSSwitch()
    let displaySwitch = NSSwitch()
    let displayStatusLabel = NSTextField(labelWithString: "正在读取状态…")
    let displayDetailLabel = NSTextField(wrappingLabelWithString: "")
    let statusLabel = NSTextField(labelWithString: "正在读取状态…")
    let detailLabel = NSTextField(wrappingLabelWithString: "")
    let powerLabel = NSTextField(labelWithString: "")
    let feedbackLabel = NSTextField(wrappingLabelWithString: "")
    let symbol = NSImageView()
    var timer: Timer?
    var busy = false
    var widget: ControlMenu?
    var lastNativeWidgetState = ""
    var pendingNativeURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出\(appTitle)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        NSApp.mainMenu = menu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 540), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = appTitle
        window.isReleasedWhenClosed = false
        window.center()
        let root = NSView()
        window.contentView = root

        symbol.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Mac 合盖工作")
        symbol.symbolConfiguration = .init(pointSize: 36, weight: .medium)
        symbol.contentTintColor = .controlAccentColor
        symbol.frame = NSRect(x: 28, y: 445, width: 50, height: 56)
        root.addSubview(symbol)

        let heading = NSTextField(labelWithString: "合盖与画面")
        heading.font = .systemFont(ofSize: 25, weight: .semibold)
        heading.frame = NSRect(x: 93, y: 472, width: 370, height: 34)
        root.addSubview(heading)
        let subtitle = NSTextField(labelWithString: "接电源和使用电池时均生效")
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 95, y: 448, width: 370, height: 22)
        root.addSubview(subtitle)

        let card = NSBox(frame: NSRect(x: 28, y: 316, width: 444, height: 110))
        card.boxType = .custom
        card.fillColor = .controlBackgroundColor
        card.borderColor = .separatorColor
        card.cornerRadius = 14
        root.addSubview(card)

        statusLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        statusLabel.frame = NSRect(x: 45, y: 382, width: 330, height: 29)
        root.addSubview(statusLabel)
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.frame = NSRect(x: 45, y: 334, width: 340, height: 40)
        root.addSubview(detailLabel)
        sleepSwitch.frame = NSRect(x: 400, y: 375, width: 50, height: 28)
        sleepSwitch.target = self
        sleepSwitch.action = #selector(toggleSleep(_:))
        sleepSwitch.setAccessibilityLabel("合盖继续工作")
        root.addSubview(sleepSwitch)

        let displayCard = NSBox(frame: NSRect(x: 28, y: 186, width: 444, height: 116))
        displayCard.boxType = .custom
        displayCard.fillColor = .controlBackgroundColor
        displayCard.borderColor = .separatorColor
        displayCard.cornerRadius = 14
        root.addSubview(displayCard)
        displayStatusLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        displayStatusLabel.frame = NSRect(x: 45, y: 258, width: 340, height: 29)
        root.addSubview(displayStatusLabel)
        displayDetailLabel.font = .systemFont(ofSize: 13)
        displayDetailLabel.textColor = .secondaryLabelColor
        displayDetailLabel.frame = NSRect(x: 45, y: 204, width: 344, height: 44)
        root.addSubview(displayDetailLabel)
        displaySwitch.frame = NSRect(x: 400, y: 251, width: 50, height: 28)
        displaySwitch.target = self
        displaySwitch.action = #selector(toggleDisplay(_:))
        displaySwitch.setAccessibilityLabel("保持画面与 iPad 镜像")
        root.addSubview(displaySwitch)

        powerLabel.font = .systemFont(ofSize: 13, weight: .medium)
        powerLabel.frame = NSRect(x: 32, y: 151, width: 440, height: 22)
        root.addSubview(powerLabel)
        let notes = NSTextField(wrappingLabelWithString: "关闭窗口后继续生效；合盖使用 iPad 请开启两个开关。\n放进包里前，请关闭两个开关。")
        notes.font = .systemFont(ofSize: 12)
        notes.textColor = .secondaryLabelColor
        notes.frame = NSRect(x: 32, y: 65, width: 438, height: 44)
        root.addSubview(notes)
        feedbackLabel.font = .systemFont(ofSize: 12)
        feedbackLabel.textColor = .secondaryLabelColor
        feedbackLabel.frame = NSRect(x: 32, y: 20, width: 438, height: 42)
        root.addSubview(feedbackLabel)

        widget = ControlMenu(owner: self)
        if let mirrorButton = widget?.mirrorButton {
            mirrorButton.frame = NSRect(x: 32, y: 113, width: 255, height: 30)
            root.addSubview(mirrorButton)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(fullWindowClosed), name: NSWindow.willCloseNotification, object: window)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showFullPanel()
        return true
    }

    func showFullPanel() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func fullWindowClosed() { NSApp.setActivationPolicy(.accessory) }
    func application(_ application: NSApplication, open urls: [URL]) {
        let wasEmpty = pendingNativeURLs.isEmpty
        pendingNativeURLs.append(contentsOf: urls.filter { $0.scheme == "lidwork" })
        if wasEmpty { processNextNativeURL() }
    }
    func processNextNativeURL() {
        guard !pendingNativeURLs.isEmpty else { return }
        guard !busy else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.processNextNativeURL() }
            return
        }
        let url = pendingNativeURLs.removeFirst()
        let requested = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "enabled" })?.value
        switch url.host {
        case "sleep":
            let desired = requested.map { $0 == "1" } ?? !((try? readEnabled()) ?? false)
            sleepSwitch.state = desired ? .on : .off
            toggleSleep(sleepSwitch)
        case "display":
            let desired = requested.map { $0 == "1" } ?? !((try? readDisplayAwake()) ?? false)
            displaySwitch.state = desired ? .on : .off
            toggleDisplay(displaySwitch)
        case "mirror": widget?.connectFromNativeWidget()
        case "show": showFullPanel()
        default: break
        }
        if !pendingNativeURLs.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.processNextNativeURL() }
        }
    }
    func updateFeedback(_ message: String) {
        feedbackLabel.stringValue = message
        widget?.feedback(message)
    }

    func refresh() {
        guard !busy else { return }
        do {
            let enabled = try readEnabled()
            sleepSwitch.state = enabled ? .on : .off
            sleepSwitch.isEnabled = true
            statusLabel.stringValue = enabled ? "合盖工作 · 已开启" : "合盖工作 · 已关闭"
            statusLabel.textColor = enabled ? .systemGreen : .labelColor
            detailLabel.stringValue = enabled ? "合盖后保持运行，方便继续连接和工作。" : "使用系统原有的睡眠设置。"
            symbol.contentTintColor = enabled ? .systemGreen : .secondaryLabelColor
        } catch {
            statusLabel.stringValue = "无法读取状态"
            statusLabel.textColor = .systemOrange
            detailLabel.stringValue = error.localizedDescription
            sleepSwitch.isEnabled = false
        }
        do {
            let enabled = try readDisplayAwake()
            displaySwitch.state = enabled ? .on : .off
            displaySwitch.isEnabled = true
            displayStatusLabel.stringValue = enabled ? "镜像保活 · 已开启" : "镜像保活 · 已关闭"
            displayStatusLabel.textColor = enabled ? .systemGreen : .labelColor
            displayDetailLabel.stringValue = "保持画面常亮，并提供 iPad 随航显示画布。\n先开启两个开关，再连接 iPad 屏幕镜像。"
        } catch {
            displayStatusLabel.stringValue = "镜像保活 · 状态未知"
            displayStatusLabel.textColor = .systemOrange
            displayDetailLabel.stringValue = error.localizedDescription
            displaySwitch.isEnabled = false
        }
        powerLabel.stringValue = batterySummary()
        widget?.update(sleep: sleepSwitch.state == .on, display: displaySwitch.state == .on, sleepValid: sleepSwitch.isEnabled, displayValid: displaySwitch.isEnabled, powerText: powerLabel.stringValue)
        let nativeState = "\(sleepSwitch.state.rawValue):\(displaySwitch.state.rawValue):\(sidecarIsConnected())"
        if nativeState != lastNativeWidgetState {
            lastNativeWidgetState = nativeState
            WidgetCenter.shared.reloadTimelines(ofKind: "LidWorkNativeWidget")
        }
    }

    @objc func toggleSleep(_ sender: NSSwitch) {
        guard !busy else { return }
        let desired = sender.state == .on
        busy = true
        sender.isEnabled = false
        displaySwitch.isEnabled = false
        widget?.setBusy(true, message: "正在更改合盖工作设置…")
        updateFeedback("正在更改设置；如系统要求，请验证管理员身份。")
        DispatchQueue.global(qos: .userInitiated).async {
            var issue: String?
            do { try setEnabled(desired) } catch { issue = error.localizedDescription }
            DispatchQueue.main.async {
                self.busy = false
                self.widget?.setBusy(false, message: "")
                self.refresh()
                if let issue = issue {
                    self.updateFeedback(issue)
                    let alert = NSAlert()
                    alert.messageText = "设置未完成"
                    alert.informativeText = issue
                    alert.addButton(withTitle: "好")
                    self.showFullPanel()
                    alert.beginSheetModal(for: self.window)
                } else {
                    self.updateFeedback(desired ? "合盖工作已开启" : "已恢复系统睡眠行为")
                }
            }
        }
    }

    @objc func toggleDisplay(_ sender: NSSwitch) {
        guard !busy else { return }
        let desired = sender.state == .on
        busy = true
        sender.isEnabled = false
        sleepSwitch.isEnabled = false
        widget?.setBusy(true, message: "正在更改镜像保活…")
        updateFeedback("正在\(desired ? "开启" : "关闭")镜像保活…")
        DispatchQueue.global(qos: .userInitiated).async {
            var issue: String?
            do { try setDisplayAwake(desired) } catch { issue = error.localizedDescription }
            DispatchQueue.main.async {
                self.busy = false
                self.widget?.setBusy(false, message: "")
                self.refresh()
                if let issue = issue {
                    self.updateFeedback(issue)
                    let alert = NSAlert()
                    alert.messageText = "设置未完成"
                    alert.informativeText = issue
                    alert.addButton(withTitle: "好")
                    self.showFullPanel()
                    alert.beginSheetModal(for: self.window)
                } else {
                    self.updateFeedback(desired ? "镜像保活已开启，可连接 iPad" : "镜像保活已关闭，显示画布已移除")
                }
            }
        }
    }
}

if let argument = CommandLine.arguments.dropFirst().first {
    do {
        switch argument {
        case "--status": break
        case "--enable": try setEnabled(true)
        case "--disable": try setEnabled(false)
        case "--display-status": print(try readDisplayAwake() ? "enabled" : "disabled"); exit(0)
        case "--display-enable": try setDisplayAwake(true); print(try readDisplayAwake() ? "enabled" : "disabled"); exit(0)
        case "--display-disable": try setDisplayAwake(false); print(try readDisplayAwake() ? "enabled" : "disabled"); exit(0)
        default: throw failure("未知参数。")
        }
        print(try readEnabled() ? "enabled" : "disabled")
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
