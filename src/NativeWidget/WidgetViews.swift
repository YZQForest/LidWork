import SwiftUI
import WidgetKit

struct ControlEntry: TimelineEntry {
    let date: Date
    let snapshot: DeviceSnapshot
    var expired = false
}

struct NativeControlView: View {
    let entry: ControlEntry
    var previewFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var scheme

    private var sleep: Bool? { entry.expired ? nil : entry.snapshot.sleep }
    private var display: Bool? { entry.expired ? nil : entry.snapshot.display }
    private var isSmall: Bool { (previewFamily ?? family) == .systemSmall }

    var body: some View {
        VStack(spacing: isSmall ? 9 : 7) {
            header
            if isSmall {
                compactStatus("合盖工作", symbol: "moon.stars.fill", value: sleep, color: LidPalette.mint)
                compactStatus("镜像保活", symbol: "rectangle.on.rectangle", value: display, color: LidPalette.blue)
                HStack(spacing: 5) {
                    Image(systemName: "ipad.landscape")
                    Text(entry.snapshot.ipad ? "iPad 已连接" : "打开控制台").font(.system(size: 9, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 7, weight: .semibold))
                }.foregroundStyle(.secondary).padding(.horizontal, 3)
            } else {
                HStack(spacing: 8) {
                    control("合盖工作", detail: "合盖继续运行", symbol: "moon.stars.fill", value: sleep, action: .sleep, color: LidPalette.mint)
                    control("镜像保活", detail: "保持画面连接", symbol: "rectangle.on.rectangle", value: display, action: .display, color: LidPalette.blue)
                }
                Link(destination: ControlAction.mirror.url) {
                    HStack(spacing: 7) {
                        Image(systemName: "ipad.landscape").font(.system(size: 12, weight: .medium))
                        Text(entry.snapshot.ipad ? "iPad 镜像已连接" : "连接 iPad 镜像").font(.system(size: 10, weight: .semibold))
                        Spacer(minLength: 0)
                        StatusDot(color: entry.snapshot.ipad ? tint(LidPalette.mint) : .secondary, size: 4)
                        Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .medium)).opacity(0.65)
                    }.foregroundStyle(.primary).padding(.horizontal, 11).frame(height: 28)
                        .background(LidPalette.blue.opacity(scheme == .dark ? 0.14 : 0.085), in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.13), lineWidth: 0.5))
                }.buttonStyle(.plain)
            }
            footer
        }
        .padding(isSmall ? 13 : 12)
        .widgetURL(ControlAction.show.url)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "laptopcomputer").font(.system(size: 13, weight: .medium)).foregroundStyle(tint(LidPalette.mint))
            Text("合盖控制").font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            if !isSmall {
                Text("LIDWORK").font(.system(size: 6.5, weight: .bold, design: .rounded)).tracking(1.5).foregroundStyle(.secondary)
                Link(destination: ControlAction.refresh.url) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 23, height: 22)
                        .background(.primary.opacity(0.045), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("刷新小组件状态")
            }
        }.frame(height: 22)
    }
    private var footer: some View {
        HStack(spacing: 4) {
            StatusDot(color: entry.expired ? .orange : tint(LidPalette.mint), size: 3)
            if entry.expired { Text("待同步 · 点刷新").font(.system(size: 7.5)) }
            else {
                Text("同步").font(.system(size: 7.5))
                Text(entry.snapshot.sampledAt, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                    .font(.system(size: 7.5, design: .monospaced))
            }
            Spacer(minLength: 0)
            if !isSmall { Text("MAC + IPAD").font(.system(size: 6, weight: .medium, design: .rounded)).tracking(1) }
        }.foregroundStyle(.secondary).padding(.horizontal, 2).frame(height: 9)
    }

    private func tint(_ color: Color) -> Color { renderingMode == .accented ? .primary : color }
    private func label(_ value: Bool?) -> String { value.map { $0 ? "已开启" : "已关闭" } ?? (entry.expired ? "待同步" : "未获取") }
    private func control(_ title: String, detail: String, symbol: String, value: Bool?, action: ControlAction, color: Color) -> some View {
        Link(destination: action.url) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(tint(color))
                    Text(title).font(.system(size: 10.5, weight: .semibold))
                    Spacer(minLength: 1)
                    ZStack(alignment: value == true ? .trailing : .leading) {
                        Capsule().fill(value == true ? tint(color).opacity(0.8) : .primary.opacity(0.13))
                        Circle().fill(.white.opacity(value == nil ? 0.4 : 0.95)).frame(width: 8, height: 8).padding(2)
                    }.frame(width: 22, height: 12)
                }
                HStack {
                    Text(detail).font(.system(size: 8)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(label(value)).font(.system(size: 8, weight: .medium)).foregroundStyle(value == true ? tint(color) : .secondary)
                }
            }.foregroundStyle(.primary).padding(.horizontal, 9).frame(maxWidth: .infinity).frame(height: 51)
                .background(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.075 : 0.55), .white.opacity(scheme == .dark ? 0.025 : 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(scheme == .dark ? 0.12 : 0.5), lineWidth: 0.6))
        }.buttonStyle(.plain).accessibilityLabel("\(title)，\(label(value))，点击切换")
    }

    private func compactStatus(_ title: String, symbol: String, value: Bool?, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(tint(color)).frame(width: 14)
            Text(title).font(.system(size: 10, weight: .medium))
            Spacer(minLength: 1)
            StatusDot(color: value == true ? tint(color) : .secondary.opacity(0.5), size: 5)
        }.padding(.horizontal, 8).frame(height: 27)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }
}
