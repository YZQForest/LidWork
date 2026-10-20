import Foundation
import CoreGraphics
import IOKit
import IOKit.pwr_mgt

/// The app and the sandboxed widget compile this same reader. Unknown is never off.
struct DeviceSnapshot: Codable, Equatable {
    let sleep: Bool?
    let display: Bool?
    let ipad: Bool
    let sampledAt: Date

    var fingerprint: String { "\(sleep.map(String.init) ?? "unknown"):\(display.map(String.init) ?? "unknown"):\(ipad)" }
    var ready: Bool { sleep == true && display == true }

    static func current() -> DeviceSnapshot {
        var sleep: Bool?
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        if root != 0 {
            if let value = IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                sleep = value.boolValue
            }
            IOObjectRelease(root)
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        let displaysReadable = CGGetOnlineDisplayList(32, &ids, &count) == .success
        let online = ids.prefix(Int(count))
        let canvas = online.contains { CGDisplayVendorNumber($0) == 0x4c57 && CGDisplayModelNumber($0) == 1 }
        let ipad = online.contains { CGDisplayVendorNumber($0) == 0x6161706c && CGDisplayModelNumber($0) == 0x69506164 }

        var assertions: Unmanaged<CFDictionary>?
        let powerReadable = IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess
        let processes = assertions?.takeRetainedValue() as? [AnyHashable: Any] ?? [:]
        let keeper = processes.values.contains { value in
            (value as? [[String: Any]] ?? []).contains {
                ($0["AssertName"] as? String) == "LidWork display and Sidecar keeper" &&
                ($0["AssertType"] as? String) == "PreventUserIdleDisplaySleep" &&
                (($0["AssertLevel"] as? NSNumber)?.intValue ?? 0) > 0
            }
        }
        return DeviceSnapshot(sleep: sleep,
                              display: displayValue(displaysReadable: displaysReadable, canvas: canvas, powerReadable: powerReadable, keeper: keeper),
                              ipad: displaysReadable && ipad,
                              sampledAt: Date())
    }

    static func displayValue(displaysReadable: Bool, canvas: Bool, powerReadable: Bool, keeper: Bool) -> Bool? {
        guard displaysReadable else { return nil }
        guard canvas else { return false }
        guard powerReadable else { return nil }
        return keeper
    }

    static let preview = DeviceSnapshot(sleep: true, display: true, ipad: true, sampledAt: Date())
}

enum ControlAction: String, CaseIterable {
    case sleep, display, mirror, refresh, show
    var url: URL { URL(string: "lidwork://\(rawValue)")! }
    /// Widgets request a toggle against live state, never invert a cached picture.
    static func desired(for url: URL, current: Bool) -> Bool {
        let explicit = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "enabled" }?.value
        return explicit.map { $0 == "1" } ?? !current
    }
}
