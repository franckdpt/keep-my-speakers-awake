import Foundation
import CryptoKit

public enum UpdateError: Error {
    case invalidRelease, invalidDownload, incompatibleSystem, invalidBundle, installLocation, changedInstallation
}

public struct StableVersion: Comparable, Equatable {
    private let parts: [Int]
    public init?(_ value: String) {
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }),
                  piece == "0" || piece.first != "0", let number = Int(piece) else { return nil }
            numbers.append(number)
        }
        parts = numbers
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

public struct UpdateAsset: Decodable {
    public let name: String
    public let size: Int
    public let digest: String?
    public let state: String
    public let browser_download_url: URL
}

public struct UpdateRelease: Decodable {
    public let tag_name: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [UpdateAsset]

    public static let repository = "franckdpt/keep-my-speakers-awake"
    public static let assetName = "Keep-My-Speakers-Awake-Apple-Silicon.dmg"
    public var version: String { String(tag_name.dropFirst()) }

    public func isNewer(than current: String) throws -> Bool {
        guard !draft, !prerelease, tag_name.first == "v",
              let offered = StableVersion(version), let installed = StableVersion(current) else {
            throw UpdateError.invalidRelease
        }
        return offered > installed
    }

    public func asset(named name: String) throws -> UpdateAsset {
        let matches = assets.filter { $0.name == name }
        guard matches.count == 1, let asset = matches.first, asset.state == "uploaded",
              asset.size > 0, asset.size <= (name == Self.assetName ? 128 * 1024 * 1024 : 65_536),
              let digest = asset.digest, digest.hasPrefix("sha256:"), Self.validHash(String(digest.dropFirst(7))),
              asset.browser_download_url.absoluteString == "https://github.com/\(Self.repository)/releases/download/\(tag_name)/\(name)"
        else { throw UpdateError.invalidRelease }
        return asset
    }

    public static func validHash(_ hash: String) -> Bool {
        hash.count == 64 && hash.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
}

public struct UpdateManifest: Codable {
    public let version: String
    public let build: Int
    public let minimumMacOS: String
    public let architecture: String
    public let asset: String
    public let sourceRevision: String
    public let sha256: String

    public func validate(release: UpdateRelease, currentVersion: String, currentBuild: Int,
                         system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) throws {
        let minimum = minimumMacOS.split(separator: ".").compactMap { Int($0) }
        guard try release.isNewer(than: currentVersion), version == release.version, build > currentBuild,
              architecture == "arm64", asset == UpdateRelease.assetName,
              UpdateRelease.validHash(sha256), sourceRevision.count == 40,
              sourceRevision.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }),
              minimumMacOS.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression) != nil,
              minimum.count >= 2, minimum.count == minimumMacOS.split(separator: ".").count,
              try release.asset(named: asset).digest == "sha256:\(sha256)" else { throw UpdateError.invalidRelease }
        let required = minimum + Array(repeating: 0, count: 3 - minimum.count)
        let actual = [system.majorVersion, system.minorVersion, system.patchVersion]
        guard !actual.lexicographicallyPrecedes(required) else { throw UpdateError.incompatibleSystem }
    }
}

public enum UpdateFiles {
    public static let appName = "Keep My Speakers Awake.app"
    public static let bundleID = "fr.franckdupont.kmma.native"

    public static func verifyUpgrade(from target: URL, to manifest: UpdateManifest) throws {
        guard let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: target.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleID,
              let version = info["CFBundleShortVersionString"] as? String,
              let installed = StableVersion(version), let offered = StableVersion(manifest.version), offered > installed,
              let buildString = info["CFBundleVersion"] as? String, let build = Int(buildString),
              build > 0, manifest.build > build else { throw UpdateError.changedInstallation }
    }

    public static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult public static func run(_ command: String, _ arguments: [String]) throws -> Data {
        let task = Process(), output = Pipe()
        task.executableURL = URL(fileURLWithPath: command)
        task.arguments = arguments
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        try task.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw UpdateError.invalidBundle }
        return data
    }

    public static func verifyBundle(_ app: URL, manifest: UpdateManifest, signalHash: String) throws {
        let resolved = app.resolvingSymlinksInPath()
        guard resolved.path == app.standardizedFileURL.path,
              let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleID,
              info["CFBundleExecutable"] as? String == "KMSA",
              info["CFBundleShortVersionString"] as? String == manifest.version,
              info["CFBundleVersion"] as? String == String(manifest.build),
              info["LSMinimumSystemVersion"] as? String == manifest.minimumMacOS else { throw UpdateError.invalidBundle }
        let executable = app.appendingPathComponent("Contents/MacOS/KMSA")
        let signal = app.appendingPathComponent("Contents/Resources/Signals/sub2.wav")
        for file in [executable, signal] {
            guard file.resolvingSymlinksInPath().path.hasPrefix(app.path + "/") else { throw UpdateError.invalidBundle }
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let architecture = String(decoding: try run("/usr/bin/lipo", [executable.path, "-archs"]), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard architecture == "arm64", try hash(signal) == signalHash else { throw UpdateError.invalidBundle }
    }
}

/// Every path is derived from a private staging directory beside the installed app.
/// Keeping both moves on the same volume makes replacement atomic and rollback possible.
public struct UpdateInstallJob: Codable {
    public let target: URL
    public let staging: URL
    public let parentPID: Int32
    public let previousHash: String
    public let candidateHash: String
    public let signalHash: String
    public let manifest: UpdateManifest
    public var candidate: URL { staging.appendingPathComponent(UpdateFiles.appName) }
    public var backup: URL { staging.appendingPathComponent("Previous.app") }

    public init(target: URL, staging: URL, parentPID: Int32, previousHash: String, candidateHash: String,
                signalHash: String, manifest: UpdateManifest) {
        self.target = target; self.staging = staging; self.parentPID = parentPID
        self.previousHash = previousHash; self.candidateHash = candidateHash
        self.signalHash = signalHash; self.manifest = manifest
    }

    public func validateLocation(allowedParents: [URL] = [URL(fileURLWithPath: "/Applications"),
                               FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]) throws {
        let parent = target.deletingLastPathComponent()
        let attributes = try FileManager.default.attributesOfItem(atPath: staging.path)
        guard target.lastPathComponent == UpdateFiles.appName,
              allowedParents.contains(where: { $0.path == parent.path }), target.path == target.resolvingSymlinksInPath().path,
              staging.path == staging.resolvingSymlinksInPath().path, staging.deletingLastPathComponent().path == parent.path,
              staging.lastPathComponent.hasPrefix(".kmsa-update-"),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              parentPID > 1, UpdateRelease.validHash(previousHash), UpdateRelease.validHash(candidateHash)
        else { throw UpdateError.installLocation }
    }

    /// Revalidate immediately before the swap; refuse a concurrent update or changed files.
    public func apply(verify: (URL) throws -> Void) throws {
        let fm = FileManager.default
        guard try UpdateFiles.hash(target.appendingPathComponent("Contents/MacOS/KMSA")) == previousHash,
              try UpdateFiles.hash(candidate.appendingPathComponent("Contents/MacOS/KMSA")) == candidateHash,
              !fm.fileExists(atPath: backup.path) else { throw UpdateError.changedInstallation }
        try verify(candidate)
        try fm.moveItem(at: target, to: backup)
        do {
            try fm.moveItem(at: candidate, to: target)
            try verify(target)
        } catch {
            // Move the failed candidate out of the way before restoring the original.
            if fm.fileExists(atPath: target.path) { try fm.moveItem(at: target, to: staging.appendingPathComponent("Failed.app")) }
            try fm.moveItem(at: backup, to: target)
            throw error
        }
    }
}
