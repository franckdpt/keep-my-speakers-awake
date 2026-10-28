import Foundation

public struct AvailableUpdate {
    public let release: UpdateRelease
    public let manifest: UpdateManifest
    public init(release: UpdateRelease, manifest: UpdateManifest) {
        self.release = release; self.manifest = manifest
    }
}

public enum UpdateFetchProgress: Sendable {
    case downloading(Double)
    case verifying
}

private final class UpdateTransferGuard: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let limit: Int64
    let progress: (@Sendable (UpdateFetchProgress) -> Void)?
    let destination: URL?
    // Written before resume(), then consumed only on the session's serial delegate queue.
    var completion: ((Result<(URL, URLResponse), Error>) -> Void)?
    init(limit: Int, progress: (@Sendable (UpdateFetchProgress) -> Void)? = nil, destination: URL? = nil) {
        self.limit = Int64(limit); self.progress = progress; self.destination = destination
    }

    static func allows(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return ["github.com", "api.github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(Self.allows(request.url) ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel() }
        else { progress?(.downloading(min(1, max(0, Double(totalBytesWritten) / Double(limit))))) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destination else { return }
        do {
            guard let response = downloadTask.response else { throw UpdateError.invalidDownload }
            // URLSession removes its temporary file when this delegate method returns.
            try FileManager.default.moveItem(at: location, to: destination)
            resolve(.success((destination, response)))
        } catch { resolve(.failure(error)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { resolve(.failure(error)) }
    }
    private func resolve(_ result: Result<(URL, URLResponse), Error>) {
        let callback = completion
        completion = nil
        callback?(result)
    }
}

public enum UpdateClient {
    private static func session(delegate: URLSessionDelegate? = nil) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.httpAdditionalHeaders = ["User-Agent": "KMSA-Updater", "Accept": "application/vnd.github+json"]
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    public static func latest(currentVersion: String, currentBuild: Int) async throws -> AvailableUpdate? {
        let session = session()
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(UpdateRelease.repository)/releases/latest")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request, delegate: UpdateTransferGuard(limit: 512 * 1024))
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 512 * 1024,
              UpdateTransferGuard.allows(response.url) else { throw UpdateError.invalidRelease }
        let release = try JSONDecoder().decode(UpdateRelease.self, from: data)
        guard try release.isNewer(than: currentVersion) else { return nil }
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("kmsa-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let asset = try release.asset(named: "release-manifest.json")
        let file = try await download(asset, into: workspace)
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(contentsOf: file))
        try manifest.validate(release: release, currentVersion: currentVersion, currentBuild: currentBuild)
        return AvailableUpdate(release: release, manifest: manifest)
    }

    private static func download(_ asset: UpdateAsset, into workspace: URL,
                                 progress: (@Sendable (UpdateFetchProgress) -> Void)? = nil) async throws -> URL {
        let destination = workspace.appendingPathComponent(asset.name)
        let transfer = UpdateTransferGuard(limit: asset.size, progress: progress, destination: destination)
        let session = session(delegate: transfer)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: asset.browser_download_url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        // A delegate-backed task delivers didWriteData; download(for:delegate:)
        // only accepts a task delegate and doesn't deliver download progress here.
        let (file, response): (URL, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            transfer.completion = { continuation.resume(with: $0) }
            session.downloadTask(with: request).resume()
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200, UpdateTransferGuard.allows(response.url),
              (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize == asset.size else { throw UpdateError.invalidDownload }
        progress?(.verifying)
        guard try "sha256:\(UpdateFiles.hash(file))" == asset.digest else { throw UpdateError.invalidDownload }
        return file
    }

    /// Returns a verified app in a private temporary directory. Never executes it.
    /// The caller owns and removes the workspace after copying the app to staging.
    public static func fetch(_ update: AvailableUpdate, signalHash: String,
                             progress: (@Sendable (UpdateFetchProgress) -> Void)? = nil) async throws -> URL {
        let fm = FileManager.default
        let workspace = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("kmsa-download-\(UUID().uuidString)")
        try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let mount = workspace.appendingPathComponent("mount")
        var mounted = false
        do {
            progress?(.downloading(0))
            let dmg = try await download(update.release.asset(named: UpdateRelease.assetName), into: workspace, progress: progress)
            guard try UpdateFiles.hash(dmg) == update.manifest.sha256 else { throw UpdateError.invalidDownload }
            try fm.createDirectory(at: mount, withIntermediateDirectories: false)
            try UpdateFiles.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, dmg.path])
            mounted = true
            let source = mount.appendingPathComponent(UpdateFiles.appName)
            try UpdateFiles.verifyBundle(source, manifest: update.manifest, signalHash: signalHash)
            let destination = workspace.appendingPathComponent(UpdateFiles.appName)
            try UpdateFiles.run("/usr/bin/ditto", [source.path, destination.path])
            try UpdateFiles.verifyBundle(destination, manifest: update.manifest, signalHash: signalHash)
            try UpdateFiles.run("/usr/bin/hdiutil", ["detach", mount.path])
            mounted = false
            return workspace
        } catch {
            if mounted {
                mounted = (try? UpdateFiles.run("/usr/bin/hdiutil", ["detach", mount.path])) == nil
            }
            // Never recurse into a mounted image during cleanup.
            if !mounted { try? fm.removeItem(at: workspace) }
            throw error
        }
    }
}
