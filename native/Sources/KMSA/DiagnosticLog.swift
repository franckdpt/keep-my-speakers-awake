import Foundation
import os

/// Local, bounded JSON-lines history. All disk work runs off the UI/audio polling thread.
final class DiagnosticLog {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Keep My Speakers Awake", isDirectory: true)
    static let shared = DiagnosticLog(directory: directory)
    static let disabled = DiagnosticLog(directory: nil)

    private let directory: URL?
    private let queue = DispatchQueue(label: "fr.franckdupont.kmsa.diagnostics", qos: .utility)
    private let runID = UUID().uuidString
    private let maxBytes: Int
    private let archives: Int
    private let fallback = Logger(subsystem: "fr.franckdupont.kmma.native", category: "diagnostics")

    init(directory: URL?, maxBytes: Int = 2 * 1024 * 1024, archives: Int = 3) {
        self.directory = directory
        self.maxBytes = maxBytes
        self.archives = archives
    }

    func record(_ event: String, fields: [String: Any] = [:]) {
        guard let directory else { return }
        var record = fields
        record["event"] = event
        record["timestamp"] = ISO8601DateFormatter().string(from: Date())
        record["runID"] = runID
        record["pid"] = ProcessInfo.processInfo.processIdentifier
        record["version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        guard var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        data.append(0x0a)
        let line = data
        queue.async { [self] in
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                let file = directory.appendingPathComponent("diagnostics.jsonl")
                let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
                if size + line.count > maxBytes {
                    for index in stride(from: archives, through: 1, by: -1) {
                        let target = directory.appendingPathComponent("diagnostics.\(index).jsonl")
                        let source = index == 1 ? file : directory.appendingPathComponent("diagnostics.\(index - 1).jsonl")
                        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                        if fm.fileExists(atPath: source.path) { try fm.moveItem(at: source, to: target) }
                    }
                }
                if !fm.fileExists(atPath: file.path) {
                    guard fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } catch {
                fallback.error("Could not write diagnostics: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func flush() { queue.sync {} }
}
