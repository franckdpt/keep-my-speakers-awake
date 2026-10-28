import Foundation
import KMSACore

func runUpdateChecks() -> Int {
    var count = 0
    func expect(_ condition: @autoclosure () throws -> Bool, _ context: String = #function) {
        count += 1
        guard (try? condition()) == true else { fatalError("Update check failed: \(context)") }
    }
    func rejects(_ action: () throws -> Void) {
        count += 1
        do { try action(); fatalError("Unsafe update accepted") } catch {}
    }
    func decode<T: Decodable>(_ value: Any, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
    }
    let digest = String(repeating: "b", count: 64)
    let asset: [String: Any] = ["name": UpdateRelease.assetName, "size": 1234, "state": "uploaded", "digest": "sha256:\(digest)",
                               "browser_download_url": "https://github.com/\(UpdateRelease.repository)/releases/download/v1.7.0/\(UpdateRelease.assetName)"]
    let releaseJSON: [String: Any] = ["tag_name": "v1.7.0", "draft": false, "prerelease": false, "assets": [asset]]
    let release = try! decode(releaseJSON, as: UpdateRelease.self)
    let manifestJSON: [String: Any] = ["version": "1.7.0", "build": 35, "minimumMacOS": "14.2", "architecture": "arm64",
                                     "asset": UpdateRelease.assetName, "sourceRevision": String(repeating: "a", count: 40), "sha256": digest]
    let manifest = try! decode(manifestJSON, as: UpdateManifest.self)
    let system = OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 0)
    var schedule = UpdateCheckSchedule()
    let start = Date(timeIntervalSince1970: 10_000)
    expect(schedule.isDue(at: start))
    schedule.started(at: start)
    expect(!schedule.isDue(at: start))
    schedule.finished(success: true, at: start)
    expect(!schedule.isDue(at: start.addingTimeInterval(43_199)))
    expect(schedule.isDue(at: start.addingTimeInterval(43_200)))
    expect(schedule.isDue(at: start.addingTimeInterval(86_400 * 7)))
    expect(schedule.isDue(at: start.addingTimeInterval(-1)))
    schedule.started(at: start.addingTimeInterval(43_200))
    schedule.finished(success: false, at: start.addingTimeInterval(43_200))
    expect(!schedule.isDue(at: start.addingTimeInterval(43_200 + 3_599)))
    expect(schedule.isDue(at: start.addingTimeInterval(43_200 + 3_600)))
    for invalid in ["1.7", "1.7.0-beta", "v1.7.0", "1.7.0;touch /tmp/oops", "1.-1.0", "01.7.0", "١.7.0", "99999999999999999999999999.0.0"] {
        expect(StableVersion(invalid) == nil)
    }
    expect(StableVersion("1.6.9")! < StableVersion("1.6.10")!)
    expect(StableVersion("2.0.0")! > StableVersion("1.99.99")!)
    expect(try release.isNewer(than: "1.6.8"))
    expect(try !release.isNewer(than: "1.7.0"))
    expect(try !release.isNewer(than: "1.8.0"))
    for change in [["draft": true], ["prerelease": true], ["tag_name": "v1.7.0-beta"], ["tag_name": "1.7.0"]] as [[String: Any]] {
        rejects { _ = try decode(releaseJSON.merging(change, uniquingKeysWith: { _, new in new }), as: UpdateRelease.self).isNewer(than: "1.0.0") }
    }
    expect(try release.asset(named: UpdateRelease.assetName).size == 1234)
    for change in [["size": 0], ["size": 129 * 1024 * 1024], ["state": "new"], ["digest": "sha256:bad"],
                   ["browser_download_url": "https://example.com/\(UpdateRelease.assetName)"],
                   ["browser_download_url": "https://github.com/another/repo/releases/download/v1.7.0/\(UpdateRelease.assetName)"],
                   ["browser_download_url": "http://github.com/\(UpdateRelease.repository)/releases/download/v1.7.0/\(UpdateRelease.assetName)"]] as [[String: Any]] {
        rejects {
            let modified = asset.merging(change, uniquingKeysWith: { _, new in new })
            let unsafe = try decode(releaseJSON.merging(["assets": [modified]], uniquingKeysWith: { _, new in new }), as: UpdateRelease.self)
            _ = try unsafe.asset(named: UpdateRelease.assetName)
        }
    }
    rejects {
        let duplicate = try decode(releaseJSON.merging(["assets": [asset, asset]], uniquingKeysWith: { _, new in new }), as: UpdateRelease.self)
        _ = try duplicate.asset(named: UpdateRelease.assetName)
    }
    expect((try? manifest.validate(release: release, currentVersion: "1.6.8", currentBuild: 34, system: system)) != nil)
    rejects { try manifest.validate(release: release, currentVersion: "1.6.8", currentBuild: 35, system: system) }
    rejects { try manifest.validate(release: release, currentVersion: "1.8.0", currentBuild: 34, system: system) }
    rejects { try manifest.validate(release: release, currentVersion: "1.6.8", currentBuild: 34,
                                   system: OperatingSystemVersion(majorVersion: 14, minorVersion: 1, patchVersion: 9)) }
    for change in [["version": "1.7.1"], ["architecture": "x86_64"], ["build": 0], ["asset": "other.dmg"],
                   ["sha256": String(repeating: "c", count: 64)], ["sourceRevision": "bad"], ["minimumMacOS": "latest"],
                   ["minimumMacOS": "14.99999999999999999999999.0"]] as [[String: Any]] {
        rejects {
            let unsafe = try decode(manifestJSON.merging(change, uniquingKeysWith: { _, new in new }), as: UpdateManifest.self)
            try unsafe.validate(release: release, currentVersion: "1.6.8", currentBuild: 34, system: system)
        }
    }

    // Real filesystem transactions with harmless text stand-ins. Never launch an app or play audio.
    let fm = FileManager.default
    let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("kmsa-update-check-\(UUID().uuidString)")
    try! fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: root) }
    func executable(_ app: URL) -> URL { app.appendingPathComponent("Contents/MacOS/KMSA") }
    func fixture() -> UpdateInstallJob {
        let parent = root.appendingPathComponent(UUID().uuidString)
        let target = parent.appendingPathComponent(UpdateFiles.appName)
        let staging = parent.appendingPathComponent(".kmsa-update-\(UUID().uuidString)")
        let candidate = staging.appendingPathComponent(UpdateFiles.appName)
        try! fm.createDirectory(at: executable(target).deletingLastPathComponent(), withIntermediateDirectories: true)
        try! fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try! fm.createDirectory(at: executable(candidate).deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data("previous".utf8).write(to: executable(target))
        try! Data("candidate".utf8).write(to: executable(candidate))
        return UpdateInstallJob(target: target, staging: staging, parentPID: getpid(), previousHash: try! UpdateFiles.hash(executable(target)),
                                candidateHash: try! UpdateFiles.hash(executable(candidate)), signalHash: digest, manifest: manifest)
    }
    let success = fixture()
    let plist = success.target.appendingPathComponent("Contents/Info.plist")
    var installedInfo = ["CFBundleIdentifier": UpdateFiles.bundleID, "CFBundleShortVersionString": "1.6.8", "CFBundleVersion": "34"]
    try! PropertyListSerialization.data(fromPropertyList: installedInfo, format: .xml, options: 0).write(to: plist)
    expect((try? UpdateFiles.verifyUpgrade(from: success.target, to: manifest)) != nil)
    installedInfo["CFBundleShortVersionString"] = "1.8.0"
    installedInfo["CFBundleVersion"] = "36"
    try! PropertyListSerialization.data(fromPropertyList: installedInfo, format: .xml, options: 0).write(to: plist)
    rejects { try UpdateFiles.verifyUpgrade(from: success.target, to: manifest) }
    installedInfo["CFBundleShortVersionString"] = "1.6.8"
    try! PropertyListSerialization.data(fromPropertyList: installedInfo, format: .xml, options: 0).write(to: plist)
    rejects { try UpdateFiles.verifyUpgrade(from: success.target, to: manifest) }
    expect((try? success.validateLocation(allowedParents: [success.target.deletingLastPathComponent()])) != nil)
    rejects { try success.validateLocation() }
    try! success.apply { app in
        guard try String(contentsOf: executable(app), encoding: .utf8) == "candidate" else { throw UpdateError.invalidBundle }
    }
    expect(try String(contentsOf: executable(success.target), encoding: .utf8) == "candidate")
    expect(try String(contentsOf: executable(success.backup), encoding: .utf8) == "previous")
    let failed = fixture()
    rejects { try failed.apply { if $0.path == failed.target.path { throw UpdateError.invalidBundle } } }
    expect(try String(contentsOf: executable(failed.target), encoding: .utf8) == "previous")
    expect(!fm.fileExists(atPath: failed.backup.path))
    let unverified = fixture()
    rejects { try unverified.apply { _ in throw UpdateError.invalidBundle } }
    expect(try String(contentsOf: executable(unverified.target), encoding: .utf8) == "previous")
    let concurrent = fixture()
    try! Data("changed by another update".utf8).write(to: executable(concurrent.target))
    rejects { try concurrent.apply { _ in } }
    expect(try String(contentsOf: executable(concurrent.target), encoding: .utf8) == "changed by another update")
    let corrupted = fixture()
    try! Data("corrupted".utf8).write(to: executable(corrupted.candidate))
    rejects { try corrupted.apply { _ in } }
    expect(try String(contentsOf: executable(corrupted.target), encoding: .utf8) == "previous")
    let publicStaging = fixture()
    try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: publicStaging.staging.path)
    rejects { try publicStaging.validateLocation(allowedParents: [publicStaging.target.deletingLastPathComponent()]) }
    return count
}
