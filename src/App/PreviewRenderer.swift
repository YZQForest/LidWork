import AppKit
import SwiftUI
import WidgetKit

@MainActor
func renderPreviews(to directory: URL) throws {
    _ = NSApplication.shared
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    func save<V: View>(_ view: V, width: CGFloat, height: CGFloat, scheme: ColorScheme, name: String) throws {
        let content = view.environment(\.colorScheme, scheme).environment(\.lidPreviewRendering, true).frame(width: width, height: height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else {
            throw failure("无法生成界面预览。")
        }
        try data.write(to: directory.appendingPathComponent(name))
    }
    for (label, scheme) in [("dark", ColorScheme.dark), ("light", ColorScheme.light)] {
        let model = ControlModel.preview
        let app = ControlDashboard(model: model, setSleep: { _ in }, setDisplay: { _ in }, mirror: {}, refresh: {}, preview: true)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        try save(app, width: 600, height: 666, scheme: scheme, name: "app-\(label).png")
        for (size, family, width, height) in [("medium", WidgetFamily.systemMedium, CGFloat(344), CGFloat(164)), ("small", WidgetFamily.systemSmall, CGFloat(164), CGFloat(164))] {
            let view = NativeControlView(entry: ControlEntry(date: Date(), snapshot: .preview), previewFamily: family)
                .background(WidgetNeutralBackground())
                .clipShape(RoundedRectangle(cornerRadius: 27.88))
            try save(view, width: width, height: height, scheme: scheme, name: "widget-\(size)-\(label).png")
        }
    }
    print("已生成深浅色 App 与小组件的内容预览；实时背景模糊由 macOS 在实际窗口中渲染。")
}
