import SwiftUI
import WidgetKit

struct ControlEntry: TimelineEntry {
    let date: Date
    let snapshot: DeviceSnapshot
    var expired = false
}

/// Full-color fallback. In the system's clear/tinted appearance WidgetKit
/// removes this layer and supplies the actual desktop Liquid Glass material.
struct WidgetNeutralBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        (scheme == .dark ? Color(white: 0.13) : Color(white: 0.98)).opacity(0.94)
    }
}

struct NativeControlView: View {
    let entry: ControlEntry
    var previewFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isSmall: Bool { (previewFamily ?? family) == .systemSmall }
    private var sleep: Bool? { entry.expired ? nil : entry.snapshot.sleep }
    private var display: Bool? { entry.expired ? nil : entry.snapshot.display }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 6)
            if isSmall {
                overviewRow("合盖工作", symbol: "moon", value: sleep)
                overviewRow("镜像保活", symbol: "rectangle.on.rectangle", value: display)
            } else {
                controlRow("合盖工作", symbol: "moon", value: sleep, action: .sleep)
                controlRow("镜像保活", symbol: "rectangle.on.rectangle", value: display, action: .display)
            }
            Spacer(minLength: 6)
            Divider().opacity(0.55)
            Spacer(minLength: 7)
            if isSmall { ipadLabel }
            else {
                Link(destination: ControlAction.mirror.url) { ipadLabel }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.snapshot.ipad ? "iPad 镜像已连接" : "连接 iPad 镜像")
            }
        }
        .padding(.horizontal, isSmall ? 15 : 17)
        .padding(.vertical, 14)
        .widgetURL(ControlAction.show.url)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("合盖控制").font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
            if entry.expired && !isSmall {
                Text("待同步").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if !isSmall {
                Link(destination: ControlAction.refresh.url) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("刷新小组件状态")
            }
        }.frame(height: 22)
    }

    private func controlRow(_ title: String, symbol: String, value: Bool?, action: ControlAction) -> some View {
        Link(destination: action.url) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14, weight: .regular)).foregroundStyle(.secondary).frame(width: 19)
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                Spacer(minLength: 8)
                switchIndicator(value)
            }.frame(height: 30).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(title)，\(stateLabel(value))，点击切换")
    }

    @ViewBuilder private func switchIndicator(_ value: Bool?) -> some View {
        if let value {
            let fill: Color = renderingMode == .accented
                ? .primary.opacity(value ? 0.24 : 0.08)
                : (value ? .green : .primary.opacity(0.12))
            ZStack(alignment: value ? .trailing : .leading) {
                Capsule().fill(fill)
                Circle().fill(.white).frame(width: 16, height: 16).padding(2)
                    .shadow(color: .black.opacity(0.14), radius: 0.8, y: 0.5)
            }.frame(width: 34, height: 20)
        } else {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 34, height: 20)
                .background(.primary.opacity(0.045), in: Capsule())
        }
    }

    private var ipadLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "ipad.landscape").font(.system(size: 14, weight: .regular)).foregroundStyle(.secondary).frame(width: 19)
            Text("iPad 镜像").font(.system(size: isSmall ? 10.5 : 12, weight: .medium)).foregroundStyle(.primary)
            Spacer(minLength: 1)
            if !isSmall {
                Text(entry.snapshot.ipad ? "已连接" : "连接").font(.system(size: 11)).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
            } else {
                Image(systemName: entry.snapshot.ipad ? "checkmark" : "arrow.up.right")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
        }.frame(height: 26).contentShape(Rectangle())
    }

    private func overviewRow(_ title: String, symbol: String, value: Bool?) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 16)
            Text(title).font(.system(size: 11, weight: .medium))
            Spacer(minLength: 0)
            Text(value.map { $0 ? "开" : "关" } ?? "—").font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(height: 30)
    }
    private func stateLabel(_ value: Bool?) -> String { value.map { $0 ? "已开启" : "已关闭" } ?? "待同步" }
}
