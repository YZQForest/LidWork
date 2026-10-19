import SwiftUI
import WidgetKit
import IOKit
import CoreGraphics

struct ControlEntry: TimelineEntry {
    let date: Date
    let sleep: Bool?
    let display: Bool?
    let ipad: Bool
    static func current() -> ControlEntry {
        var sleep: Bool?
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        if root != 0 {
            if let value = IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber { sleep = value.boolValue }
            IOObjectRelease(root)
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        let valid = CGGetOnlineDisplayList(16, &ids, &count) == .success
        let online = ids.prefix(Int(count))
        let display = valid ? online.contains { CGDisplayVendorNumber($0) == 0x4c57 && CGDisplayModelNumber($0) == 1 } : nil
        let ipad = valid && online.contains { CGDisplayVendorNumber($0) == 0x6161706c && CGDisplayModelNumber($0) == 0x69506164 }
        return ControlEntry(date: Date(), sleep: sleep, display: display, ipad: ipad)
    }
}

struct ControlProvider: TimelineProvider {
    func placeholder(in context: Context) -> ControlEntry { ControlEntry(date: Date(), sleep: true, display: true, ipad: false) }
    func getSnapshot(in context: Context, completion: @escaping (ControlEntry) -> Void) { completion(.current()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ControlEntry>) -> Void) {
        completion(Timeline(entries: [.current()], policy: .after(Date().addingTimeInterval(60))))
    }
}

struct NativeControlView: View {
    let entry: ControlEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        VStack(spacing: family == .systemSmall ? 7 : 10) {
            HStack(spacing: 7) {
                Image(systemName: "laptopcomputer").foregroundStyle(.teal)
                Text("合盖控制").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 2)
                if family != .systemSmall {
                    Text("Mac + iPad").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            if family == .systemSmall {
                compactControl(title: "合盖工作", symbol: "moon.stars.fill", value: entry.sleep, action: "sleep", color: .teal)
                compactControl(title: "镜像保活", symbol: "rectangle.on.rectangle", value: entry.display, action: "display", color: .blue)
            } else {
                HStack(spacing: 9) {
                    control(title: "合盖工作", symbol: "moon.stars.fill", value: entry.sleep, action: "sleep", color: .teal)
                    control(title: "镜像保活", symbol: "rectangle.on.rectangle", value: entry.display, action: "display", color: .blue)
                }
            }
            Link(destination: URL(string: "lidwork://mirror")!) {
                HStack(spacing: 6) {
                    Image(systemName: entry.ipad ? "checkmark.circle.fill" : "ipad.landscape")
                    Text(entry.ipad ? "iPad 镜像已连接" : "连接 iPad 镜像")
                        .font(.system(size: family == .systemSmall ? 10 : 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.forward").font(.system(size: 8, weight: .semibold)).opacity(0.6)
                }
                .foregroundStyle(.teal)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.teal.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
        }
        .padding(family == .systemSmall ? 12 : 14)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), .teal.opacity(0.10), .blue.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "lidwork://show")!)
    }
    func target(_ action: String, _ value: Bool?) -> URL {
        if let value { return URL(string: "lidwork://\(action)?enabled=\(value ? "0" : "1")")! }
        return URL(string: "lidwork://\(action)")!
    }
    func valueText(_ value: Bool?) -> String { value.map { $0 ? "已开启" : "已关闭" } ?? "点击切换" }
    func control(title: String, symbol: String, value: Bool?, action: String, color: Color) -> some View {
        Link(destination: target(action, value)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol).foregroundStyle(color)
                    Spacer(minLength: 0)
                    Image(systemName: value == true ? "switch.2" : "power").foregroundStyle(value == true ? color : .secondary)
                }.font(.system(size: 14, weight: .medium))
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(valueText(value)).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }.foregroundStyle(.primary).padding(10).frame(maxWidth: .infinity)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
    func compactControl(title: String, symbol: String, value: Bool?, action: String, color: Color) -> some View {
        Link(destination: target(action, value)) {
            HStack(spacing: 7) {
                Image(systemName: symbol).foregroundStyle(color).frame(width: 16)
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                Circle().fill(value == true ? color : .secondary.opacity(0.4)).frame(width: 6, height: 6)
            }.foregroundStyle(.primary).padding(.horizontal, 8).padding(.vertical, 7)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
}

struct LidWorkNativeWidget: Widget {
    let kind = "LidWorkNativeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ControlProvider()) { entry in NativeControlView(entry: entry) }
            .configurationDisplayName("合盖控制")
            .description("控制合盖运行、镜像保活，并连接 iPad 随航。")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}
@main struct LidWorkNativeBundle: WidgetBundle {
    var body: some Widget { LidWorkNativeWidget() }
}
