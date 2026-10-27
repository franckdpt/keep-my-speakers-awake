import Foundation
import CoreMediaIO

/// Read device-running metadata only. Never create a capture session, open a stream, or request camera access.
enum CameraHardware {
    struct Snapshot: Codable {
        var known: Bool
        var busy: Bool
        var deviceCount: Int
        var errorCode: Int32?
    }

    private static func address(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector, mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
                                  mElement: UInt32(kCMIOObjectPropertyElementMain))
    }

    static func snapshot() -> Snapshot {
        var property = address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        var status = CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil, &size)
        guard status == noErr, size % 4 == 0 else {
            return Snapshot(known: false, busy: false, deviceCount: 0, errorCode: status)
        }
        if size == 0 { return Snapshot(known: true, busy: false, deviceCount: 0) }
        var devices = [UInt32](repeating: 0, count: Int(size) / 4)
        var used: UInt32 = 0
        status = devices.withUnsafeMutableBytes {
            CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil, size, &used, $0.baseAddress!)
        }
        guard status == noErr, used <= size, used % 4 == 0 else {
            return Snapshot(known: false, busy: false, deviceCount: 0, errorCode: status)
        }
        devices = Array(devices.prefix(Int(used) / 4))
        var unknown: Int32?
        for device in devices {
            var runningProperty = address(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            var value: UInt32 = 0
            var count: UInt32 = 0
            let result = CMIOObjectGetPropertyData(device, &runningProperty, 0, nil, 4, &count, &value)
            if result == noErr && count == 4 {
                if value != 0 { return Snapshot(known: true, busy: true, deviceCount: devices.count) }
            } else { unknown = result == noErr ? -1 : result }
        }
        return Snapshot(known: unknown == nil, busy: false, deviceCount: devices.count, errorCode: unknown)
    }
}
