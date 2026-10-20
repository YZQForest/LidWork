import AppKit
import SwiftUI

final class ControlModel: ObservableObject {
    @Published var snapshot = DeviceSnapshot(sleep: nil, display: nil, ipad: false, sampledAt: Date())
    @Published var busy = false
    @Published var connecting = false
    @Published var feedback = ""
    @Published var power = "读取电源状态…"

    static var preview: ControlModel {
        let model = ControlModel()
        model.snapshot = .preview
        model.power = "电池供电 · 82%"
        return model
    }
}

private struct WindowFrost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct ControlDashboard: View {
    @ObservedObject var model: ControlModel
    var setSleep: (Bool) -> Void
    var setDisplay: (Bool) -> Void
    var mirror: () -> Void
    var refresh: () -> Void
    var preview = false

    var body: some View {
        ZStack {
            if !preview { WindowFrost().ignoresSafeArea() }
            AuroraBackground().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 17) {
                header
                deviceStage
                VStack(spacing: 11) {
                    controlRow(title: "合盖工作", subtitle: "关闭上盖，Mac 继续运行", icon: "moon.stars.fill", value: model.snapshot.sleep, color: LidPalette.mint, action: setSleep)
                    controlRow(title: "镜像保活", subtitle: "让 iPad 画面保持连接", icon: "rectangle.on.rectangle", value: model.snapshot.display, color: LidPalette.blue, action: setDisplay)
                }
                mirrorRow
                footer
            }
            .padding(.horizontal, 29).padding(.top, 40).padding(.bottom, 25)
        }
        .frame(width: 600, height: 666)
        .animation(.easeInOut(duration: 0.22), value: model.snapshot.fingerprint)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(LidPalette.mint)
                .frame(width: 55, height: 55)
                .background(LinearGradient(colors: [LidPalette.mint.opacity(0.23), LidPalette.blue.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.28), lineWidth: 0.7))
            VStack(alignment: .leading, spacing: 4) {
                Text("LIDWORK").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(3).foregroundStyle(.secondary)
                Text("合盖控制").font(.system(size: 28, weight: .semibold)).tracking(-0.7)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text("MAC + IPAD").font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(1.5).foregroundStyle(.secondary)
                Button(action: refresh) { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium)).frame(width: 31, height: 31).lidGlass(12) }
                    .buttonStyle(.plain).help("重新读取系统状态并更新小组件")
                    .accessibilityLabel("同步 App 与桌面小组件")
            }
        }
    }

    private var deviceStage: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("合上盖子，继续工作。").font(.system(size: 17, weight: .semibold))
                    Text(model.snapshot.ready ? "运行与画面保活已就绪" : "接电源与使用电池时均可开启")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    StatusDot(color: model.snapshot.ready ? LidPalette.mint : .secondary)
                    Text(model.snapshot.ready ? "已就绪" : "待开启").font(.system(size: 10, weight: .medium))
                }.padding(.horizontal, 9).padding(.vertical, 6).background(.primary.opacity(0.045), in: Capsule())
            }
            HStack(spacing: 16) {
                deviceIcon("laptopcomputer", name: "Mac", active: true)
                VStack(spacing: 7) {
                    HStack(spacing: 5) {
                        Capsule().fill(LidPalette.mint.opacity(0.45)).frame(height: 1)
                        Image(systemName: model.snapshot.ipad ? "link" : "ellipsis").font(.system(size: 13, weight: .medium)).foregroundStyle(model.snapshot.ipad ? LidPalette.mint : .secondary)
                        Capsule().fill(LidPalette.blue.opacity(0.45)).frame(height: 1)
                    }
                    Text(model.snapshot.ipad ? "镜像已连接" : "等待 iPad 连接").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                }
                deviceIcon("ipad.landscape", name: "iPad", active: model.snapshot.ipad)
            }.padding(.horizontal, 20)
        }.padding(19).lidGlass(25)
    }

    private func deviceIcon(_ symbol: String, name: String, active: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(active ? .primary : .secondary)
            Text(name).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
        }.frame(width: 58)
    }

    private func controlRow(title: String, subtitle: String, icon: String, value: Bool?, color: Color, action: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 20, weight: .medium)).foregroundStyle(color)
                .frame(width: 46, height: 46).background(color.opacity(value == true ? 0.16 : 0.075), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(color.opacity(0.15), lineWidth: 0.7))
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(model.busy ? "更新中" : value.map { $0 ? "已开启" : "已关闭" } ?? "状态未知")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(value == true ? color : .secondary)
                }
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if preview {
                // ImageRenderer cannot draw AppKit-backed native switches.
                // This glyph is only for explicitly labelled design previews.
                ZStack(alignment: value == true ? .trailing : .leading) {
                    Capsule().fill(value == true ? color : .secondary.opacity(0.25))
                    Circle().fill(.white).frame(width: 19, height: 19).padding(3)
                }.frame(width: 44, height: 25)
            } else {
                Toggle(title, isOn: Binding(get: { value ?? false }, set: action))
                    .labelsHidden().toggleStyle(.switch).tint(color).controlSize(.regular)
                    .disabled(model.busy || model.connecting || value == nil)
                    .accessibilityLabel(title)
            }
        }.padding(17).lidGlass(22)
    }

    private var mirrorRow: some View {
        Button(action: mirror) {
            HStack(spacing: 13) {
                Image(systemName: "ipad.landscape").font(.system(size: 23, weight: .light)).foregroundStyle(LidPalette.blue)
                    .frame(width: 46, height: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text("iPad 镜像").font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    Text(model.connecting ? "正在建立连接…" : model.snapshot.ipad ? "已连接 · 点击管理镜像" : "解锁 iPad，轻点即可连接")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.connecting { ProgressView().controlSize(.small) }
                else {
                    HStack(spacing: 6) {
                        Text(model.snapshot.ipad ? "管理" : "连接").font(.system(size: 11, weight: .semibold))
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                    }.foregroundStyle(LidPalette.blue).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(LidPalette.blue.opacity(0.12), in: Capsule())
                }
            }.padding(17).lidGlass(22)
        }.buttonStyle(.plain).disabled(model.busy || model.connecting).accessibilityLabel("连接或管理 iPad 镜像")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                Image(systemName: "battery.75percent").font(.system(size: 12)).foregroundStyle(.secondary)
                Text(model.power).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                StatusDot(color: LidPalette.mint, size: 4)
                Text("已同步").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(model.snapshot.sampledAt, style: .time).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
            Rectangle().fill(.primary.opacity(0.07)).frame(height: 0.5)
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: model.feedback.isEmpty ? "info.circle" : "checkmark.circle").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(model.feedback.isEmpty ? "关闭窗口后继续运行。放入包中前，请关闭两个开关。" : model.feedback)
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 28, alignment: .top)
        }.padding(.horizontal, 3)
    }
}
