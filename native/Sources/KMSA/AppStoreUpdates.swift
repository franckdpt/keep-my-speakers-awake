#if APP_STORE
import Foundation
import Combine

/// App Store builds contain no GitHub updater or replacement helper.
@MainActor
final class UpdateModel: ObservableObject {
    var hasUpdate: Bool { false }
    init(automaticChecks: Bool = false) {}
    static func preview(available: Bool, searching: Bool = false, downloading: Bool = false) -> UpdateModel {
        UpdateModel()
    }
    static func runChecks() async {
        precondition(!UpdateModel(automaticChecks: true).hasUpdate)
        precondition(!FileManager.default.fileExists(atPath: Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/KMSAUpdateInstaller").path))
        print("Mac App Store channel: no independent updater or installer helper. No audio played.")
    }
}
#endif
