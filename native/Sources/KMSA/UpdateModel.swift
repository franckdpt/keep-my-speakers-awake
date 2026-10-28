import AppKit
import KMSACore

@MainActor
final class UpdateModel: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var status: AppText?
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var foregroundAction = false
    var hasUpdate: Bool { availableUpdate != nil }
    var showsProgress: Bool { busy && foregroundAction }
    var isUpToDate: Bool { status == .appUpToDate && !hasUpdate }
    var buttonTitle: String {
        availableUpdate.map { "\(L10n.text(.updateToVersion)) \($0.manifest.version)" } ?? L10n.text(.checkUpdates)
    }
    var errorMessage: AppText? {
        guard let status, [.updateFailed, .updateInstallLocation, .updateNeedsNewerMacOS,
                           .updateVerificationFailed, .updateCheckFailed].contains(status) else { return nil }
        return status
    }
    private var transferID: UUID?
    private var schedule = UpdateCheckSchedule()
    private let clock: () -> Date
    private let fetchLatest: () async throws -> AvailableUpdate?
    private var timer: Timer?
    private var observations: [(NotificationCenter, NSObjectProtocol)] = []

    init(automaticChecks: Bool = false, defaults: UserDefaults = .standard,
         clock: @escaping () -> Date = Date.init,
         fetchLatest: (() async throws -> AvailableUpdate?)? = nil) {
        self.clock = clock
        self.fetchLatest = fetchLatest ?? {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
            return try await UpdateClient.latest(currentVersion: version, currentBuild: build)
        }
        // Preview renders neither read nor change the user's update status.
        guard !CommandLine.arguments.contains("--preview") else { return }
        if defaults.bool(forKey: "updateInstallFailed") {
            status = .updateFailed
            defaults.removeObject(forKey: "updateInstallFailed")
        }
        let installed = defaults.string(forKey: "updateInstalledVersion")
        let installedAt = defaults.object(forKey: "updateInstalledAt") as? Date
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        if let installed, installed == current, let installedAt,
           (0...300).contains(clock().timeIntervalSince(installedAt)) {
            status = .appUpToDate
            schedule.finished(success: true, at: clock())
        }
        defaults.removeObject(forKey: "updateInstalledVersion")
        defaults.removeObject(forKey: "updateInstalledAt")
        if automaticChecks { startAutomaticChecks() }
    }

    deinit {
        timer?.invalidate()
        for (center, observer) in observations { center.removeObserver(observer) }
    }

    static func preview(available: Bool, searching: Bool = false, downloading: Bool = false) -> UpdateModel {
        let model = UpdateModel()
        model.availableUpdate = available ? sampleOffer() : nil
        model.status = available ? .updateAvailable : .appUpToDate
        if searching { model.status = nil }
        if downloading {
            model.busy = true
            model.foregroundAction = true
            model.status = .downloadingUpdate
            model.downloadProgress = 0.42
        }
        return model
    }

    private func startAutomaticChecks() {
        // The application owns this model, so opening the menu is not required.
        Task { [weak self] in await self?.checkAutomatically() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkAutomatically() }
        }
        timer?.tolerance = 15
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.checkAutomatically() }
            }
            observations.append((center, observer))
        }
    }

    /// Silent background checks never download or install the app.
    func checkAutomatically() async {
        guard !busy, schedule.isDue(at: clock()) else { return }
        await refresh()
    }

    private func refresh(visible: Bool = false) async {
        guard !busy else { return }
        busy = true
        foregroundAction = visible
        if visible { status = .checkingUpdates }
        schedule.started(at: clock())
        defer { busy = false; foregroundAction = false }
        do {
            availableUpdate = try await fetchLatest()
            status = hasUpdate ? .updateAvailable : .appUpToDate
            schedule.finished(success: true, at: clock())
        } catch {
            // A failed request cannot dismiss an update that was already detected,
            // and cannot claim the app is up to date.
            status = Self.errorText(error)
            schedule.finished(success: false, at: clock())
        }
    }

    func check(stopForRestart: () -> Void) async {
        guard !busy else { return }
        if availableUpdate == nil { await refresh(visible: true); return }
        guard let offer = availableUpdate else { return }
        await install(offer: offer) { progress in
            try await self.performInstallation(offer, progress: progress, stopForRestart: stopForRestart)
        }
    }

    /// Separate state handling from filesystem/relaunch work so checks can exercise
    /// the complete UI flow without touching the installed app or playing audio.
    func install(offer: AvailableUpdate,
                 perform: (_ progress: @escaping @Sendable (UpdateFetchProgress) -> Void) async throws -> Void) async {
        guard !busy else { return }
        availableUpdate = offer
        busy = true
        foregroundAction = true
        status = .downloadingUpdate
        downloadProgress = 0
        let id = UUID()
        transferID = id
        defer { busy = false; foregroundAction = false; downloadProgress = nil; transferID = nil }
        do {
            try await perform { [weak self] progress in
                Task { @MainActor in self?.receive(progress, id: id) }
            }
            availableUpdate = nil
            status = .appUpToDate
        } catch { status = Self.errorText(error) }
    }

    private func receive(_ progress: UpdateFetchProgress, id: UUID) {
        guard transferID == id, busy else { return }
        switch progress {
        case .downloading(let fraction):
            guard status == .downloadingUpdate, fraction.isFinite else { return }
            downloadProgress = max(downloadProgress ?? 0, min(1, max(0, fraction)))
        case .verifying:
            guard status == .downloadingUpdate else { return }
            status = .verifyingUpdate
            downloadProgress = nil
        }
    }

    private func performInstallation(_ offer: AvailableUpdate,
                                     progress: @escaping @Sendable (UpdateFetchProgress) -> Void,
                                     stopForRestart: () -> Void) async throws {
        // The supported locations avoid read-only DMGs, app translocation and privilege prompts.
        let target = Bundle.main.bundleURL.standardizedFileURL
        let parent = target.deletingLastPathComponent()
        let allowed = ["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        guard allowed.contains(parent.path), target.lastPathComponent == UpdateFiles.appName,
              target.path == target.resolvingSymlinksInPath().path,
              FileManager.default.isWritableFile(atPath: parent.path) else { throw UpdateError.installLocation }
        status = .downloadingUpdate
        guard let signal = AppModel.resource("sub2", ext: "wav") else { throw UpdateError.invalidBundle }
        let signalHash = try UpdateFiles.hash(signal)
        let workspace = try await UpdateClient.fetch(offer, signalHash: signalHash, progress: progress)
        defer { try? FileManager.default.removeItem(at: workspace) }
        status = .installingUpdate
        downloadProgress = nil
        let job = try await Task.detached {
            try Self.stage(workspace: workspace, target: target, manifest: offer.manifest, signalHash: signalHash)
        }.value
        var handedOff = false
        defer { if !handedOff { try? FileManager.default.removeItem(at: job.staging) } }
        let helper = Process()
        helper.executableURL = target.appendingPathComponent("Contents/Helpers/KMSAUpdateInstaller")
        helper.arguments = [job.staging.appendingPathComponent("job.json").path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: job.staging.appendingPathComponent("ready").path) {
            guard helper.isRunning, Date() < deadline else {
                if helper.isRunning { helper.terminate() }
                throw UpdateError.invalidBundle
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        handedOff = true
        stopForRestart() // Stop audio without changing the user's saved Auto setting.
        NSApplication.shared.terminate(nil)
    }

    private static func errorText(_ error: Error) -> AppText {
        switch error {
        case UpdateError.installLocation: return .updateInstallLocation
        case UpdateError.incompatibleSystem: return .updateNeedsNewerMacOS
        case UpdateError.invalidBundle, UpdateError.invalidDownload,
             UpdateError.invalidRelease, UpdateError.changedInstallation, is DecodingError: return .updateVerificationFailed
        default: return .updateCheckFailed
        }
    }

    nonisolated private static func stage(workspace: URL, target: URL, manifest: UpdateManifest, signalHash: String) throws -> UpdateInstallJob {
        let fm = FileManager.default
        let staging = target.deletingLastPathComponent().appendingPathComponent(".kmsa-update-\(UUID().uuidString)")
        try UpdateFiles.verifyUpgrade(from: target, to: manifest)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let candidate = staging.appendingPathComponent(UpdateFiles.appName)
            try UpdateFiles.run("/usr/bin/ditto", [workspace.appendingPathComponent(UpdateFiles.appName).path, candidate.path])
            try UpdateFiles.verifyBundle(candidate, manifest: manifest, signalHash: signalHash)
            let job = UpdateInstallJob(target: target, staging: staging, parentPID: ProcessInfo.processInfo.processIdentifier,
                                      previousHash: try UpdateFiles.hash(target.appendingPathComponent("Contents/MacOS/KMSA")),
                                      candidateHash: try UpdateFiles.hash(candidate.appendingPathComponent("Contents/MacOS/KMSA")),
                                      signalHash: signalHash, manifest: manifest)
            try job.validateLocation()
            try JSONEncoder().encode(job).write(to: staging.appendingPathComponent("job.json"), options: [.atomic])
            return job
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }
}
