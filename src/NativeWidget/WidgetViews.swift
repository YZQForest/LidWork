import SwiftUI
import WidgetKit

struct ControlEntry: TimelineEntry {
    let date: Date
    let snapshot: DeviceSnapshot
    var expired = false
}

/// WidgetKit replaces this removable layer with system glass in clear/tinted mode.
struct WidgetNeutralBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        (scheme == .dark ? Color(white: 0.105) : Color(white: 0.91))
    }
}

struct NativeControlView: View {
    let entry: ControlEntry
    var previewFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var scheme

    private var isSmall: Bool { (previewFamily ?? family) == .systemSmall }
    private var sleep: Bool? { entry.expired ? nil : entry.snapshot.sleep }
    private var display: Bool? { entry.expired ? nil : entry.snapshot.display }
    private var accented: Bool { renderingMode == .accented }
    private var ink: Color { accented ? .primary : Color.accentColor }

    var body: some View {
        Group {
            if isSmall { compactOverview }
            else { controlCenter }
        }
        .widgetURL(ControlAction.show.url)
    }

    private var controlCenter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                tile("合盖工作", symbol: "moon.fill", value: sleep, action: .sleep)
                tile("镜像保活", symbol: "rectangle.on.rectangle", value: display, action: .display)
            }
            HStack(spacing: 8) {
                Link(destination: ControlAction.mirror.url) {
                    HStack(spacing: 9) {
                        Image(systemName: "ipad.landscape").font(.system(size: 16, weight: .medium))
                            .foregroundStyle(!entry.expired && entry.snapshot.ipad ? ink : .secondary)
                        Text("iPad 镜像").font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                        Text(entry.expired ? "待同步" : (entry.snapshot.ipad ? "已连接" : "连接")).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 13).frame(height: 36)
                    .contentShape(Capsule())
                    .background(surface(radius: 18, active: false))
                }.buttonStyle(.plain).accessibilityLabel(mirrorDescription)
                refresh.frame(width: 36, height: 36)
                    .background(surface(radius: 18, active: false))
            }
        }.padding(12)
    }

    private func tile(_ title: String, symbol: String, value: Bool?, action: ControlAction) -> some View {
        Link(destination: action.url) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                        .foregroundStyle(value == true ? ink : .secondary)
                        .frame(width: 26, height: 26)
                    Spacer(minLength: 5)
                    switchIndicator(value)
                }
                Spacer(minLength: 5)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                Text(stateLabel(value)).font(.system(size: 10.5)).foregroundStyle(.secondary).padding(.top, 2)
            }
            .padding(13).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 21))
            .background(surface(radius: 21, active: value == true))
        }.buttonStyle(.plain).accessibilityLabel("\(title)，\(stateLabel(value))，点击切换")
    }

    /// Subtle functional surfaces; no simulated wallpaper or decorative blur.
    private func surface(radius: CGFloat, active: Bool) -> some View {
        let fill: Color = accented
            ? .primary.opacity(active ? 0.16 : 0.065)
            : .white.opacity(scheme == .dark ? (active ? 0.11 : 0.055) : (active ? 0.92 : 0.55))
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(scheme == .dark ? 0.10 : 0.65), lineWidth: 0.5)
            }
    }

    @ViewBuilder private func switchIndicator(_ value: Bool?) -> some View {
        if let value {
            ZStack(alignment: value ? .trailing : .leading) {
                Capsule().fill(value ? (accented ? .primary.opacity(0.28) : ink) : .primary.opacity(0.13))
                Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                    .shadow(color: .black.opacity(0.13), radius: 1, y: 0.5)
            }.frame(width: 30, height: 18)
        } else {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 30, height: 18)
        }
    }

    private var compactOverview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "laptopcomputer").font(.system(size: 11))
                Text("LidWork").font(.system(size: 11, weight: .semibold))
            }.foregroundStyle(.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                compactItem("合盖工作", symbol: "moon.fill", value: sleep)
                Spacer(minLength: 6)
                compactItem("镜像保活", symbol: "rectangle.on.rectangle", value: display)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Image(systemName: "ipad.landscape").font(.system(size: 12))
                Text("iPad 镜像").font(.system(size: 10.5, weight: .medium))
                Spacer(minLength: 1)
                Image(systemName: entry.expired ? "ellipsis" : (entry.snapshot.ipad ? "checkmark" : "arrow.up.right")).font(.system(size: 9, weight: .medium))
            }.foregroundStyle(.secondary)
        }.padding(16)
    }

    private func compactItem(_ title: String, symbol: String, value: Bool?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(value == true ? ink : .secondary)
                .frame(height: 24)
            Text(title).font(.system(size: 10.5, weight: .medium))
            Text(stateLabel(value)).font(.system(size: 9.5)).foregroundStyle(.secondary)
        }
    }

    private var refresh: some View {
        Link(destination: ControlAction.refresh.url) {
            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel("刷新小组件状态")
    }
    private var mirrorDescription: String { entry.expired ? "iPad 镜像状态待同步，点击连接" : (entry.snapshot.ipad ? "iPad 镜像已连接" : "连接 iPad 镜像") }
    private func stateLabel(_ value: Bool?) -> String { value.map { $0 ? "已开启" : "已关闭" } ?? "待同步" }
}
