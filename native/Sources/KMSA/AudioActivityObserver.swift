import CoreAudio
import Foundation

/// Activity notifications restart observation promptly if music starts while the
/// menu-bar app is eligible for App Nap. They never record audio or change devices.
@MainActor
final class AudioActivityObserver {
    private typealias Listener = (AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)
    private var systemListener: Listener?
    private var processListeners: [AudioObjectID: [Listener]] = [:]
    private var processPIDs: [AudioObjectID: UInt32] = [:]
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        systemListener = listen(HAL.system, HAL.address(kAudioHardwarePropertyProcessObjectList)) { [weak self] in
            self?.updateProcesses()
            self?.onChange()
        }
        updateProcesses()
    }

    private func updateProcesses() {
        guard let ids = try? HAL.list(HAL.system, kAudioHardwarePropertyProcessObjectList) else { return }
        let currentIDs = Set(ids)
        for id in Array(processListeners.keys) where !currentIDs.contains(id) {
            removeProcess(id)
        }
        for id in ids {
            guard let pid = try? HAL.scalar(id, kAudioProcessPropertyPID),
                  pid != UInt32(bitPattern: ProcessInfo.processInfo.processIdentifier) else { continue }
            guard processPIDs[id] != pid else { continue }
            removeProcess(id)
            processPIDs[id] = pid
            let addresses = [HAL.address(kAudioProcessPropertyIsRunningInput),
                             HAL.address(kAudioProcessPropertyIsRunningOutput),
                             HAL.address(kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput)]
            processListeners[id] = addresses.compactMap { address in
                listen(id, address) { [weak self] in self?.onChange() }
            }
        }
    }

    private func listen(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress,
                        action: @escaping @MainActor () -> Void) -> Listener? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        let callback: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in action() }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, callback) == noErr else { return nil }
        return (object, address, callback)
    }

    private func removeProcess(_ id: AudioObjectID) {
        for (object, original, callback) in processListeners.removeValue(forKey: id) ?? [] {
            var address = original
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, callback)
        }
        processPIDs.removeValue(forKey: id)
    }

    deinit {
        for (object, original, callback) in processListeners.values.flatMap({ $0 }) + [systemListener].compactMap({ $0 }) {
            var address = original
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, callback)
        }
    }
}
