import SwiftUI
import WidgetKit
import OSLog

struct ControlProvider: TimelineProvider {
    private let logger = Logger(subsystem: "local.yzq.lidwork", category: "WidgetSync")
    func placeholder(in context: Context) -> ControlEntry { ControlEntry(date: Date(), snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (ControlEntry) -> Void) {
        completion(ControlEntry(date: Date(), snapshot: context.isPreview ? .preview : .current()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ControlEntry>) -> Void) {
        let snapshot = DeviceSnapshot.current()
        logger.notice("Widget snapshot version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?", privacy: .public) state=\(snapshot.fingerprint, privacy: .public)")
        let now = Date()
        // A stale entry stops presenting an old on/off picture as a fresh reading.
        let expiry = now.addingTimeInterval(300)
        completion(Timeline(entries: [ControlEntry(date: now, snapshot: snapshot), ControlEntry(date: expiry, snapshot: snapshot, expired: true)], policy: .after(expiry)))
    }
}

struct LidWorkNativeWidget: Widget {
    let kind = "LidWorkNativeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ControlProvider()) { entry in
            NativeControlView(entry: entry)
                .containerBackground(for: .widget) { WidgetNeutralBackground() }
        }
        .configurationDisplayName("合盖控制")
        .description("控制中心磁贴：合盖工作、镜像保活与 iPad 连接。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
@main struct LidWorkNativeBundle: WidgetBundle {
    var body: some Widget { LidWorkNativeWidget() }
}
