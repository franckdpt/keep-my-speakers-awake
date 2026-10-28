import Foundation
import Darwin
import KMSACore

private final class TransferCheck: @unchecked Sendable {
    private let lock = NSLock()
    private var downloaded = false
    private var verified = false
    func record(_ progress: UpdateFetchProgress) {
        lock.lock()
        defer { lock.unlock() }
        switch progress {
        case .downloading(let fraction):
            precondition(fraction.isFinite && (0...1).contains(fraction))
            if fraction > 0 { downloaded = true }
        case .verifying: verified = true
        }
    }
    func validate() {
        lock.lock()
        defer { lock.unlock() }
        precondition(downloaded && verified, "Expected real byte progress and verification phase")
    }
}

@main
enum UpdateInstallerMain {
    static func main() async {
        do {
            // Read-only integration check against a real public release. No app is launched.
            if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--verify-latest" {
                guard let offer = try await UpdateClient.latest(currentVersion: "0.0.0", currentBuild: 0) else {
                    throw UpdateError.invalidRelease
                }
                let hash = try UpdateFiles.hash(URL(fileURLWithPath: CommandLine.arguments[2]))
                let transfer = TransferCheck()
                let workspace = try await UpdateClient.fetch(offer, signalHash: hash, progress: { transfer.record($0) })
                defer { try? FileManager.default.removeItem(at: workspace) }
                transfer.validate()
                print("Verified official release \(offer.manifest.version) (\(offer.manifest.build)): real byte progress, GitHub digests, manifest, DMG, bundle identity, signature, arm64 and unchanged signal. No installation or audio.")
                return
            }
            guard CommandLine.arguments.count == 2 else { throw UpdateError.invalidRelease }
            let jobFile = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
            let job = try JSONDecoder().decode(UpdateInstallJob.self, from: Data(contentsOf: jobFile))
            try job.validateLocation()
            guard jobFile.path == job.staging.appendingPathComponent("job.json").path else { throw UpdateError.installLocation }
            try UpdateFiles.verifyBundle(job.candidate, manifest: job.manifest, signalHash: job.signalHash)
            try Data("ready".utf8).write(to: job.staging.appendingPathComponent("ready"), options: .atomic)
            // Do not touch the app until its process has really exited.
            let deadline = Date().addingTimeInterval(120)
            while kill(job.parentPID, 0) == 0 || errno == EPERM {
                guard Date() < deadline else { throw UpdateError.changedInstallation }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard errno == ESRCH else { throw UpdateError.changedInstallation }
            do {
                try UpdateFiles.verifyUpgrade(from: job.target, to: job.manifest)
                try job.apply { try UpdateFiles.verifyBundle($0, manifest: job.manifest, signalHash: job.signalHash) }
                let preferences = UserDefaults(suiteName: UpdateFiles.bundleID)
                preferences?.set(job.manifest.version, forKey: "updateInstalledVersion")
                preferences?.set(Date(), forKey: "updateInstalledAt")
                preferences?.synchronize()
                try UpdateFiles.run("/usr/bin/open", ["-n", job.target.path])
                // Keep Previous.app as a recoverable backup, outside the public repo.
                try? FileManager.default.removeItem(at: job.staging.appendingPathComponent("job.json"))
                try? FileManager.default.removeItem(at: job.staging.appendingPathComponent("ready"))
            } catch {
                // apply() restores the original if installation fails. Also roll back if relaunch fails.
                if FileManager.default.fileExists(atPath: job.backup.path),
                   (try? UpdateFiles.hash(job.target.appendingPathComponent("Contents/MacOS/KMSA"))) == job.candidateHash {
                    try FileManager.default.moveItem(at: job.target, to: job.staging.appendingPathComponent("Relaunch-failed.app"))
                    try FileManager.default.moveItem(at: job.backup, to: job.target)
                }
                let preferences = UserDefaults(suiteName: UpdateFiles.bundleID)
                preferences?.removeObject(forKey: "updateInstalledVersion")
                preferences?.removeObject(forKey: "updateInstalledAt")
                preferences?.set(true, forKey: "updateInstallFailed")
                preferences?.synchronize()
                _ = try? UpdateFiles.run("/usr/bin/open", ["-n", job.target.path])
                throw error
            }
        } catch {
            fputs("KMSA update could not be completed.\n", stderr)
            exit(1)
        }
    }
}
