import SwiftUI

private struct PreviewRenderingKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var lidPreviewRendering: Bool {
        get { self[PreviewRenderingKey.self] }
        set { self[PreviewRenderingKey.self] = newValue }
    }
}

enum LidPalette {
    static let mint = Color(red: 0.24, green: 0.83, blue: 0.69)
    static let blue = Color(red: 0.35, green: 0.60, blue: 0.99)
    static let lilac = Color(red: 0.64, green: 0.50, blue: 0.95)
}

struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme
    var compact = false
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: scheme == .dark
                               ? [Color(red: 0.055, green: 0.08, blue: 0.14).opacity(0.75), Color(red: 0.10, green: 0.13, blue: 0.20).opacity(0.55)]
                               : [Color.white.opacity(0.64), Color(red: 0.87, green: 0.94, blue: 0.97).opacity(0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse().fill(LidPalette.mint.opacity(scheme == .dark ? 0.24 : 0.22))
                    .frame(width: proxy.size.width * 0.85, height: proxy.size.height * 0.58)
                    .blur(radius: compact ? 32 : 70)
                    .offset(x: -proxy.size.width * 0.29, y: -proxy.size.height * 0.28)
                Ellipse().fill(LidPalette.blue.opacity(scheme == .dark ? 0.27 : 0.16))
                    .frame(width: proxy.size.width * 0.83, height: proxy.size.height * 0.60)
                    .blur(radius: compact ? 36 : 78)
                    .offset(x: proxy.size.width * 0.35, y: proxy.size.height * 0.03)
                Ellipse().fill(LidPalette.lilac.opacity(scheme == .dark ? 0.19 : 0.12))
                    .frame(width: proxy.size.width * 0.85, height: proxy.size.height * 0.48)
                    .blur(radius: compact ? 35 : 70)
                    .offset(x: -proxy.size.width * 0.04, y: proxy.size.height * 0.47)
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GlassSurface: ViewModifier {
    let radius: CGFloat
    @Environment(\.lidPreviewRendering) private var preview
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        if preview {
            content.background(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.09 : 0.62), .white.opacity(scheme == .dark ? 0.035 : 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(scheme == .dark ? 0.17 : 0.48), lineWidth: 0.7))
                .shadow(color: .black.opacity(scheme == .dark ? 0.10 : 0.045), radius: 15, y: 7)
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 0.7))
        }
    }
}

extension View {
    func lidGlass(_ radius: CGFloat = 24) -> some View { modifier(GlassSurface(radius: radius)) }
}

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 6
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .shadow(color: color.opacity(0.45), radius: 5)
    }
}
