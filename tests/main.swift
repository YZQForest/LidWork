import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
// A missing observation must not masquerade as a disabled switch.
expect(DeviceSnapshot.displayValue(displaysReadable: false, canvas: false, powerReadable: false, keeper: false) == nil, "display query failure is unknown")
expect(DeviceSnapshot.displayValue(displaysReadable: true, canvas: false, powerReadable: false, keeper: false) == false, "no canvas is definitively off")
expect(DeviceSnapshot.displayValue(displaysReadable: true, canvas: true, powerReadable: false, keeper: false) == nil, "unreadable assertion is unknown")
expect(DeviceSnapshot.displayValue(displaysReadable: true, canvas: true, powerReadable: true, keeper: false) == false, "canvas without live keeper is off")
expect(DeviceSnapshot.displayValue(displaysReadable: true, canvas: true, powerReadable: true, keeper: true) == true, "live canvas and keeper are on")
// A stale widget picture must not dictate the next switch state.
for action in [ControlAction.sleep, .display] {
    expect(ControlAction.desired(for: action.url, current: true) == false, "toggle live on state off")
    expect(ControlAction.desired(for: action.url, current: false) == true, "toggle live off state on")
    expect(URLComponents(url: action.url, resolvingAgainstBaseURL: false)?.queryItems == nil, "widget URL contains no cached enabled value")
}
expect(ControlAction.desired(for: URL(string: "lidwork://sleep?enabled=1")!, current: true), "legacy explicit enable remains idempotent")
let one = DeviceSnapshot(sleep: nil, display: false, ipad: true, sampledAt: Date(timeIntervalSince1970: 1))
let two = DeviceSnapshot(sleep: nil, display: false, ipad: true, sampledAt: Date(timeIntervalSince1970: 9))
let off = DeviceSnapshot(sleep: false, display: false, ipad: true, sampledAt: one.sampledAt)
expect(one.fingerprint == two.fingerprint, "sampling time must not cause a widget reload storm")
expect(one.fingerprint != off.fingerprint, "unknown and off are different")
let decoded = try JSONDecoder().decode(DeviceSnapshot.self, from: JSONEncoder().encode(one))
expect(decoded == one, "unknown states survive serialization")
let ownedPath = "/example/with spaces/合盖工作开关.app/Contents/PlugIns/LidWorkNativeWidget.appex/Contents/MacOS/LidWorkNativeWidget"
let rows = "  81 \(ownedPath)\n 82 /System/NotificationCenter\n 83 \(ownedPath)Extra\n 84 /different/LidWorkNativeWidget\n"
expect(OwnedWidgetProcess.identifiers(in: rows, executablePath: ownedPath) == [81], "update repair stops only the exact owned widget executable")
print("PASS: missing observations, live toggles, compatibility, reload coalescing and serialization")
