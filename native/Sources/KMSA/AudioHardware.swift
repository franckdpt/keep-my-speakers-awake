import Foundation
import CoreAudio
import KMSACore

enum HardwareError: Error { case unavailable(OSStatus) }

enum HAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func scalar(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                       element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> UInt32 {
        var property = address(selector, scope, element)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value)
        guard status == noErr, size == 4 else { throw HardwareError.unavailable(status) }
        return value
    }

    static func list(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [UInt32] {
        var property = address(selector, scope)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size)
        guard status == noErr, size % 4 == 0 else { throw HardwareError.unavailable(status) }
        if size == 0 { return [] }
        var values = [UInt32](repeating: 0, count: Int(size) / 4)
        status = values.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { throw HardwareError.unavailable(status) }
        return Array(values.prefix(Int(size) / 4))
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var property = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, UnsafeMutableRawPointer($0))
        }
        guard status == noErr, let value else { throw HardwareError.unavailable(status) }
        return value.takeRetainedValue() as String
    }

    struct Route: Codable, Equatable {
        var device: UInt32 = 0
        var uid = ""
        var name = L10n.text(.unknownOutput)
        var isJack = false
        var alive = false
        var transport: UInt32?
        var terminals: [UInt32] = []
        var jackControl: UInt32?
        var sources: [UInt32] = []
        var error: String?
        var jackUID: String? { isJack && alive && !uid.isEmpty ? uid : nil }
    }

    static func route() -> Route {
        do {
            let device = try scalar(system, kAudioHardwarePropertyDefaultOutputDevice)
            let uid = try string(device, kAudioDevicePropertyDeviceUID)
            let name = try string(device, kAudioObjectPropertyName)
            let alive = try scalar(device, kAudioDevicePropertyDeviceIsAlive) == 1
            let transport = try scalar(device, kAudioDevicePropertyTransportType)
            let streams = try list(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            let terminals = try streams.map { try scalar($0, kAudioStreamPropertyTerminalType) }
            // A missing jack control is supported only when the output stream itself identifies a built-in analog port.
            let jackControl = try? scalar(device, kAudioDevicePropertyJackIsConnected, scope: kAudioObjectPropertyScopeOutput)
            let sources = (try? list(device, kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput)) ?? []
            let isJack = OutputClassifier.isBuiltInJack(transport: transport, terminals: terminals, sources: sources,
                                                       jackControl: jackControl, alive: alive)
            return Route(device: device, uid: uid, name: name, isJack: isJack, alive: alive,
                         transport: transport, terminals: terminals, jackControl: jackControl, sources: sources)
        } catch {
            return Route(error: String(describing: error))
        }
    }

    /// Read only: the Mac's output setting, never the signal's own gain or an audio meter.
    static func outputVolume(_ device: UInt32) -> Double? {
        if (try? scalar(device, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)) == 1 { return 0 }
        func read(_ element: UInt32) -> Double? {
            if (try? scalar(device, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: element)) == 1 { return 0 }
            var property = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr,
                  size == MemoryLayout<Float32>.size, value.isFinite, (0...1).contains(value) else { return nil }
            return Double(value)
        }
        if let main = read(kAudioObjectPropertyElementMain) { return main }
        guard let channels = try? list(device, kAudioDevicePropertyPreferredChannelsForStereo,
                                       scope: kAudioObjectPropertyScopeOutput), channels.count == 2 else { return nil }
        let levels = channels.compactMap { read($0) }
        // Both speakers should be loud enough before suppressing their keep-awake signal.
        return levels.count == channels.count ? levels.min() : nil
    }

    struct Activity: Codable {
        var known: Bool
        var microphoneBusy: Bool
        var outputBusy: Bool
        var busy: Bool { microphoneBusy || outputBusy }
        var reason: String {
            if microphoneBusy { return L10n.text(.inputBusy) }
            if outputBusy { return L10n.text(.outputBusy) }
            return known ? L10n.text(.audioAvailable) : L10n.text(.unknownAudio)
        }
    }

    static func activity(output: UInt32, excludingPID: Int32 = ProcessInfo.processInfo.processIdentifier) -> Activity {
        var inputBusy = false
        var outputBusy = false
        do {
            let processes = try list(system, kAudioHardwarePropertyProcessObjectList)
            for process in processes {
                let pid = try scalar(process, kAudioProcessPropertyPID)
                if pid == UInt32(bitPattern: excludingPID) { continue }
                if try scalar(process, kAudioProcessPropertyIsRunningInput) != 0 {
                    inputBusy = true
                }
                if try scalar(process, kAudioProcessPropertyIsRunningOutput) != 0 {
                    let devices = try list(process, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)
                    if devices.contains(output) {
                        outputBusy = true
                    }
                }
            }
            return Activity(known: true, microphoneBusy: inputBusy, outputBusy: outputBusy)
        } catch {
            return Activity(known: false, microphoneBusy: inputBusy, outputBusy: outputBusy)
        }
    }
}

/// Notifications cover routing changes; periodic fresh reads also catch missed events and audio activity.
final class HardwareObserver {
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init(onChange: @escaping () -> Void) {
        add(HAL.system, HAL.address(kAudioHardwarePropertyDefaultOutputDevice), onChange)
        add(HAL.system, HAL.address(kAudioHardwarePropertyDevices), onChange)
        if let devices = try? HAL.list(HAL.system, kAudioHardwarePropertyDevices) {
            for device in devices {
                for selector in [kAudioDevicePropertyJackIsConnected, kAudioDevicePropertyDataSource, kAudioDevicePropertyDeviceIsAlive] {
                    add(device, HAL.address(selector, kAudioObjectPropertyScopeOutput), onChange)
                }
            }
        }
    }

    private func add(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ action: @escaping () -> Void) {
        var property = address
        guard AudioObjectHasProperty(object, &property) else { return }
        let callback: AudioObjectPropertyListenerBlock = { _, _ in action() }
        if AudioObjectAddPropertyListenerBlock(object, &property, .main, callback) == noErr {
            listeners.append((object, address, callback))
        }
    }

    deinit {
        for (object, address, callback) in listeners {
            var property = address
            AudioObjectRemovePropertyListenerBlock(object, &property, .main, callback)
        }
    }
}
