import AppKit
import Foundation

func sidecarIsConnected() -> Bool {
    var displays = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return false }
    return displays.prefix(Int(count)).contains { CGDisplayVendorNumber($0) == 0x6161706c && CGDisplayModelNumber($0) == 0x69506164 }
}

final class SidecarController {
    private var manager: NSObject?
    private var operation: AnyObject?

    func devices() throws -> [NSObject] {
        if manager == nil {
            guard dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY) != nil,
                  let type = NSClassFromString("SidecarDisplayManager") as? NSObject.Type,
                  let instance = type.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue() as? NSObject else {
                throw failure("系统随航接口不可用，请通过控制中心连接 iPad。")
            }
            manager = instance
        }
        guard let manager, manager.responds(to: NSSelectorFromString("devices")),
              let list = manager.perform(NSSelectorFromString("devices"))?.takeUnretainedValue() as? [NSObject] else {
            throw failure("无法查找 iPad，请确认 iPad 已解锁，并开启无线局域网和蓝牙。")
        }
        return list
    }

    func name(of device: NSObject) -> String {
        guard device.responds(to: NSSelectorFromString("name")),
              let name = device.perform(NSSelectorFromString("name"))?.takeUnretainedValue() as? String else { return "iPad" }
        return name
    }

    func connectedDevices() throws -> [NSObject] {
        _ = try devices()
        guard let manager, manager.responds(to: NSSelectorFromString("connectedDevices")) else { return [] }
        return manager.perform(NSSelectorFromString("connectedDevices"))?.takeUnretainedValue() as? [NSObject] ?? []
    }

    func perform(device: NSObject, connect: Bool, completion: @escaping (Error?) -> Void) {
        guard let manager else { completion(failure("随航尚未就绪。")); return }
        let selector = NSSelectorFromString(connect ? "connectToDevice:completion:" : "disconnectFromDevice:completion:")
        guard manager.responds(to: selector) else { completion(failure("当前系统不支持直接连接，请使用控制中心。")); return }
        var finished = false
        let finish: (Error?) -> Void = { [weak self] error in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                self?.operation = nil
                completion(error)
            }
        }
        let block: @convention(block) (NSError?) -> Void = { error in finish(error) }
        operation = block as AnyObject
        manager.perform(selector, with: device, with: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            if connect && sidecarIsConnected() { finish(nil) }
            else { finish(failure("连接超时。请保持 iPad 解锁，并确认两台设备使用同一 Apple 账户。")) }
        }
    }
}

func ensureSidecarMirror() throws {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { throw failure("无法读取显示器状态。") }
    let online = Array(ids.prefix(Int(count)))
    guard let ipad = online.first(where: { CGDisplayVendorNumber($0) == 0x6161706c && CGDisplayModelNumber($0) == 0x69506164 }) else { throw failure("iPad 显示器尚未就绪。") }
    if CGDisplayIsInMirrorSet(ipad) != 0 { return }
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let config else { throw failure("无法准备屏幕镜像。") }
    let main = CGMainDisplayID()
    var result: CGError
    if main != ipad {
        result = CGConfigureDisplayMirrorOfDisplay(config, ipad, main)
    } else if let target = online.first(where: { CGDisplayIsBuiltin($0) != 0 }) {
        result = CGConfigureDisplayMirrorOfDisplay(config, target, ipad)
    } else {
        CGCancelDisplayConfiguration(config)
        return
    }
    if result == .success { result = CGCompleteDisplayConfiguration(config, .forSession) }
    else { CGCancelDisplayConfiguration(config) }
    guard result == .success else { throw failure("iPad 已连接，但自动切换镜像未完成；可在控制中心选择镜像。") }
}
