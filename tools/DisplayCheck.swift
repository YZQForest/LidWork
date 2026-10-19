import CoreGraphics
import Foundation
var displays = [CGDirectDisplayID](repeating: 0, count: 16)
var count: UInt32 = 0
guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { exit(1) }
let snapshot = displays.prefix(Int(count)).map { id -> [String: Any] in
    ["id": id, "builtin": CGDisplayIsBuiltin(id) != 0, "active": CGDisplayIsActive(id) != 0,
     "asleep": CGDisplayIsAsleep(id) != 0, "mirror_of": CGDisplayMirrorsDisplay(id),
     "width": CGDisplayPixelsWide(id), "height": CGDisplayPixelsHigh(id),
     "vendor": CGDisplayVendorNumber(id), "model": CGDisplayModelNumber(id)]
}
let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
