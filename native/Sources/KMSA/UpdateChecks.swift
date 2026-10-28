import Foundation
import KMSACore

extension UpdateModel {
    static func sampleOffer() -> AvailableUpdate {
        // Used only by explicit preview/check commands. Never downloaded or installed.
        let release = try! JSONDecoder().decode(UpdateRelease.self, from: Data(#"{"tag_name":"v9.9.9","draft":false,"prerelease":false,"assets":[]}"#.utf8))
        let manifest = try! JSONDecoder().decode(UpdateManifest.self, from: JSONSerialization.data(withJSONObject: [
            "version": "9.9.9", "build": 999, "minimumMacOS": "14.2", "architecture": "arm64",
            "asset": UpdateRelease.assetName, "sourceRevision": String(repeating: "a", count: 40),
            "sha256": String(repeating: "b", count: 64),
        ]))
        return AvailableUpdate(release: release, manifest: manifest)
    }

    static func runChecks() async {
        let suite = "fr.franckdupont.kmsa.update-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var count = 0
        func expect(_ condition: @autoclosure () -> Bool) {
            count += 1
            precondition(condition(), "Update model check failed")
        }
        let offer = sampleOffer()
        var now = Date(timeIntervalSince1970: 1_000_000)
        var calls = 0
        var responses: [Result<AvailableUpdate?, Error>] = [.success(nil), .success(offer), .failure(URLError(.notConnectedToInternet)), .success(nil), .success(nil)]
        let model = UpdateModel(defaults: defaults, clock: { now }, fetchLatest: {
            calls += 1
            return try responses.removeFirst().get()
        })
        expect(calls == 0 && model.status == nil && !model.hasUpdate)
        await model.checkAutomatically()
        expect(calls == 1 && model.status == .appUpToDate && !model.hasUpdate && !model.busy)
        await model.checkAutomatically() // Duplicate startup/wake/session notifications coalesce.
        expect(calls == 1)
        now.addTimeInterval(UpdateCheckSchedule.dailyInterval - 1)
        await model.checkAutomatically()
        expect(calls == 1)
        now.addTimeInterval(1)
        await model.checkAutomatically()
        expect(calls == 2 && model.hasUpdate && model.status == .updateAvailable)
        now.addTimeInterval(UpdateCheckSchedule.dailyInterval)
        await model.checkAutomatically()
        expect(calls == 3 && model.hasUpdate && model.status == .updateCheckFailed && !model.busy)
        now.addTimeInterval(UpdateCheckSchedule.retryInterval - 1)
        await model.checkAutomatically()
        expect(calls == 3 && model.hasUpdate)
        now.addTimeInterval(1)
        await model.checkAutomatically()
        expect(calls == 4 && !model.hasUpdate && model.status == .appUpToDate)
        now.addTimeInterval(-3600) // Recover if the system clock moves backwards.
        await model.checkAutomatically()
        expect(calls == 5 && model.status == .appUpToDate)

        var concurrentCalls = 0
        var reentrant: UpdateModel?
        reentrant = UpdateModel(defaults: defaults, fetchLatest: {
            concurrentCalls += 1
            await reentrant?.checkAutomatically()
            return nil
        })
        await reentrant?.checkAutomatically()
        expect(concurrentCalls == 1 && reentrant?.busy == false)
        reentrant = nil

        let offline = UpdateModel(defaults: defaults, fetchLatest: { throw URLError(.notConnectedToInternet) })
        await offline.checkAutomatically()
        expect(offline.status == .updateCheckFailed && !offline.hasUpdate)
        let manual = UpdateModel(defaults: defaults, fetchLatest: { nil })
        await manual.check { preconditionFailure("An up-to-date check must never restart the app") }
        expect(manual.status == .appUpToDate && !manual.busy)
        expect(manual.isUpToDate && !manual.showsProgress)

        var manualRechecks = 0
        let recheck = UpdateModel(defaults: defaults, fetchLatest: {
            manualRechecks += 1
            return manualRechecks == 1 ? nil : offer
        })
        await recheck.check { preconditionFailure("A current-version check must not restart") }
        expect(recheck.isUpToDate && manualRechecks == 1)
        await recheck.check { preconditionFailure("Searching again must not install") }
        expect(recheck.hasUpdate && !recheck.isUpToDate && manualRechecks == 2)

        let search = UpdateModel(defaults: defaults, fetchLatest: { offer })
        expect(search.buttonTitle == L10n.text(.checkUpdates))
        await search.check { preconditionFailure("Searching must not install or restart") }
        expect(search.hasUpdate && search.buttonTitle == "\(L10n.text(.updateToVersion)) 9.9.9")
        expect(!search.showsProgress && !search.isUpToDate)

        var late: (@Sendable (UpdateFetchProgress) -> Void)?
        await search.install(offer: offer) { progress in
            expect(search.showsProgress && search.downloadProgress == 0)
            late = progress
            progress(.downloading(0.4))
            try await Task.sleep(nanoseconds: 1_000_000)
            expect(search.downloadProgress == 0.4)
            progress(.downloading(0.2))
            progress(.downloading(.nan))
            try await Task.sleep(nanoseconds: 1_000_000)
            expect(search.downloadProgress == 0.4)
            progress(.downloading(2))
            try await Task.sleep(nanoseconds: 1_000_000)
            expect(search.downloadProgress == 1)
            progress(.verifying)
            try await Task.sleep(nanoseconds: 1_000_000)
            expect(search.status == .verifyingUpdate && search.downloadProgress == nil && search.showsProgress)
        }
        expect(search.isUpToDate && !search.hasUpdate && !search.showsProgress && search.downloadProgress == nil)
        late?(.downloading(0.1))
        try! await Task.sleep(nanoseconds: 1_000_000)
        expect(search.isUpToDate && search.downloadProgress == nil)

        let retry = UpdateModel(defaults: defaults)
        await retry.install(offer: offer) { _ in throw URLError(.notConnectedToInternet) }
        expect(retry.hasUpdate && !retry.isUpToDate && !retry.showsProgress && retry.errorMessage == .updateCheckFailed)

        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        defaults.set(current, forKey: "updateInstalledVersion")
        defaults.set(now, forKey: "updateInstalledAt")
        var receiptCalls = 0
        let receipt = UpdateModel(defaults: defaults, clock: { now }, fetchLatest: { receiptCalls += 1; return nil })
        expect(receipt.isUpToDate && !receipt.hasUpdate)
        await receipt.checkAutomatically()
        expect(receiptCalls == 0 && receipt.isUpToDate)
        defaults.set(current, forKey: "updateInstalledVersion")
        defaults.set(now.addingTimeInterval(-301), forKey: "updateInstalledAt")
        let expired = UpdateModel(defaults: defaults, clock: { now }, fetchLatest: { nil })
        expect(!expired.isUpToDate)
        print("Passed \(count) update-model checks: daily checks, offline retry, badge, search/update/progress/completion, late callbacks, failed install retry and relaunch receipt. No network, user preferences or audio used.")
    }
}
