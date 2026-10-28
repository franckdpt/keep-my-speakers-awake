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
        var suites: [String] = []
        func isolatedDefaults() -> UserDefaults {
            let suite = "fr.franckdupont.kmsa.update-check.\(UUID().uuidString)"
            suites.append(suite)
            return UserDefaults(suiteName: suite)!
        }
        let defaults = isolatedDefaults()
        defer { for suite in suites { UserDefaults().removePersistentDomain(forName: suite) } }
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
        let receiptDefaults = isolatedDefaults()
        receiptDefaults.set(current, forKey: "updateInstalledVersion")
        receiptDefaults.set(now, forKey: "updateInstalledAt")
        var receiptCalls = 0
        let receipt = UpdateModel(defaults: receiptDefaults, clock: { now }, fetchLatest: { receiptCalls += 1; return nil })
        expect(receipt.isUpToDate && !receipt.hasUpdate)
        await receipt.checkAutomatically()
        expect(receiptCalls == 0 && receipt.isUpToDate)
        let expiredDefaults = isolatedDefaults()
        expiredDefaults.set(current, forKey: "updateInstalledVersion")
        expiredDefaults.set(now.addingTimeInterval(-86_400), forKey: "updateInstalledAt")
        let expired = UpdateModel(defaults: expiredDefaults, clock: { now }, fetchLatest: { nil })
        expect(!expired.isUpToDate)

        // A real confirmation lasts 24 hours, including across process restarts.
        let freshnessDefaults = isolatedDefaults()
        let checkedAt = Date(timeIntervalSince1970: 10_000_000)
        var freshnessNow = checkedAt
        let fresh = UpdateModel(defaults: freshnessDefaults, clock: { freshnessNow }, fetchLatest: { nil })
        expect(!fresh.isUpToDate && fresh.confirmedCurrentAt == nil)
        await fresh.check { preconditionFailure("A successful check must not restart") }
        expect(fresh.isUpToDate && fresh.confirmedCurrentAt == checkedAt)
        freshnessNow.addTimeInterval(86_399)
        expect(fresh.isUpToDate)
        let reopened = UpdateModel(defaults: freshnessDefaults, clock: { freshnessNow }, fetchLatest: { nil })
        expect(reopened.isUpToDate && reopened.confirmedCurrentAt == checkedAt)
        freshnessNow.addTimeInterval(1)
        expect(!fresh.isUpToDate && !reopened.isUpToDate)
        let stale = UpdateModel(defaults: freshnessDefaults, clock: { freshnessNow }, fetchLatest: { nil })
        expect(!stale.isUpToDate)
        freshnessNow = checkedAt.addingTimeInterval(-1)
        expect(!fresh.isUpToDate) // A clock rollback must not extend the message.

        let mismatch = isolatedDefaults()
        mismatch.set("0.0.0", forKey: "updateConfirmedVersion")
        mismatch.set(checkedAt, forKey: "updateConfirmedAt")
        let anotherVersion = UpdateModel(defaults: mismatch, clock: { checkedAt }, fetchLatest: { nil })
        expect(!anotherVersion.isUpToDate)

        let failedDefaults = isolatedDefaults()
        var failNext = false
        let failedCheck = UpdateModel(defaults: failedDefaults, clock: { checkedAt }, fetchLatest: {
            if failNext { throw URLError(.notConnectedToInternet) }
            return nil
        })
        await failedCheck.check { preconditionFailure("Checking must not restart") }
        expect(failedCheck.isUpToDate)
        failNext = true
        await failedCheck.check { preconditionFailure("An error must not restart") }
        expect(!failedCheck.isUpToDate && failedCheck.confirmedCurrentAt == nil)
        expect(failedDefaults.object(forKey: "updateConfirmedAt") == nil)
        let reopenedAfterError = UpdateModel(defaults: failedDefaults, clock: { checkedAt }, fetchLatest: { nil })
        expect(!reopenedAfterError.isUpToDate)
        expect(recheck.confirmedCurrentAt == nil) // A detected update suppresses the current message.

        let dayOldInstall = isolatedDefaults()
        dayOldInstall.set(current, forKey: "updateInstalledVersion")
        dayOldInstall.set(checkedAt.addingTimeInterval(-86_399), forKey: "updateInstalledAt")
        let delayedRelaunch = UpdateModel(defaults: dayOldInstall, clock: { checkedAt }, fetchLatest: { nil })
        expect(delayedRelaunch.isUpToDate)
        expect(delayedRelaunch.confirmedCurrentAt == checkedAt.addingTimeInterval(-86_399))
        print("Passed \(count) update-model checks: daily checks, offline retry, badge, UI flow, relaunch receipt and version-bound 24-hour confirmations. No network, user preferences or audio used.")
    }
}
