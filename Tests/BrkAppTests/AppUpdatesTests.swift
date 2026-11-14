import BrkBase
import Foundation
import Sparkle
import XCTest
@testable import BrkApp

@MainActor
final class AppUpdatesTests: XCTestCase {
    private let release = UpdateRelease(version: "0.0.1", build: 44)

    private func item(build: String = "44", informationOnly: Bool = false, notes: URL? = nil) throws -> SUAppcastItem {
        var dictionary: [String: Any] = informationOnly
            ? ["sparkle:version": build, "sparkle:shortVersionString": "0.0.1", "link": "https://example.invalid/notes"]
            : ["enclosure": ["url": "https://example.invalid/Brk.dmg", "sparkle:version": build,
                               "sparkle:shortVersionString": "0.0.1", "length": "100"]]
        if let notes { dictionary["sparkle:releaseNotesLink"] = ["content": notes.absoluteString] }
        return try XCTUnwrap(SUAppcastItem(dictionary: dictionary))
    }

    private func state(_ stage: SPUUserUpdateStage = .notDownloaded) throws -> SPUUserUpdateState {
        try XCTUnwrap(SPUUserUpdateState(coder: StateDecoder(stage: stage)))
    }

    private func pump() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    func testOneClickDownloadsPreparesAndInstallsExactlyOnceOnTheRunLoop() throws {
        let updates = AppUpdates()
        let driver: any SPUUserDriver = updates.driver
        var choices: [SPUUserUpdateChoice] = []
        var readyChoices: [SPUUserUpdateChoice] = []
        var snapshots: [UpdatePresentation?] = []
        updates.changed = { [weak updates] in snapshots.append(updates?.presentation) }
        driver.showUpdateFound(with: try item(), state: try state()) { choices.append($0) }
        XCTAssertEqual(updates.presentation, .available(release))
        updates.install()
        updates.install()
        XCTAssertEqual(choices, [.install])
        driver.showDownloadInitiated(cancellation: { XCTFail("download was unexpectedly cancelled") })
        driver.showDownloadDidReceiveExpectedContentLength(100)
        driver.showDownloadDidReceiveData(ofLength: 50)
        XCTAssertEqual(updates.presentation, .downloading(release, fraction: 0.5))
        driver.showDownloadDidStartExtractingUpdate()
        XCTAssertEqual(updates.presentation, .preparing(release))
        driver.showReady(toInstallAndRelaunch: { readyChoices.append($0) })
        updates.install()
        XCTAssertEqual(readyChoices, [], "the final continuation must leave the dispatch drain")
        let confirmed = Quit.confirmed
        let relaunch = Quit.relaunch
        defer { Quit.confirmed = confirmed; Quit.relaunch = relaunch }
        Quit.confirmed = false
        Quit.relaunch = true
        pump()
        updates.install()
        XCTAssertEqual(readyChoices, [.install])
        XCTAssertTrue(Quit.confirmed)
        XCTAssertFalse(Quit.relaunch, "only Sparkle may relaunch the replacement")
        XCTAssertTrue(snapshots.contains(.ready(release)))
        XCTAssertEqual(updates.presentation, .installing(release))
    }

    func testStagedReadyUpdateAcceptsAnExplicitInstallAction() throws {
        let updates = AppUpdates()
        let driver: any SPUUserDriver = updates.driver
        var ready: [SPUUserUpdateChoice] = []
        driver.showUpdateFound(with: try item(), state: try state(.installing)) { ready.append($0) }
        XCTAssertEqual(updates.presentation, .ready(release))
        updates.install()
        updates.install()
        let confirmed = Quit.confirmed
        let relaunch = Quit.relaunch
        defer { Quit.confirmed = confirmed; Quit.relaunch = relaunch }
        pump()
        XCTAssertEqual(ready, [.install])
    }

    func testDismissalInvalidatesPendingInstallationAndRejectsLateCallbacks() throws {
        let updates = AppUpdates()
        let driver: any SPUUserDriver = updates.driver
        var installed: [SPUUserUpdateChoice] = []
        driver.showUpdateFound(with: try item(), state: try state()) { _ in }
        updates.install()
        driver.showDownloadDidStartExtractingUpdate()
        driver.showReady(toInstallAndRelaunch: { installed.append($0) })
        driver.dismissUpdateInstallation()
        pump()
        XCTAssertEqual(installed, [])
        XCTAssertNil(updates.presentation)
        var cancellations = 0
        driver.showDownloadInitiated { cancellations += 1 }
        driver.showDownloadDidReceiveData(ofLength: 100)
        driver.showReady(toInstallAndRelaunch: { installed.append($0) })
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(installed, [.skip])
        XCTAssertNil(updates.presentation)
    }

    func testManualResultsAcknowledgeOnceAndErrorsCanRetry() throws {
        let updates = AppUpdates()
        let driver: any SPUUserDriver = updates.driver
        var messages: [String] = []
        var acknowledgements = 0
        updates.message = { messages.append($0 + " " + $1) }
        let current = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue),
                              userInfo: [NSLocalizedDescriptionKey: "Already up to date"])
        driver.showUpdateNotFoundWithError(current) { acknowledgements += 1 }
        XCTAssertEqual(messages, [], "background checks remain silent")
        driver.showUserInitiatedUpdateCheck(cancellation: {})
        driver.showUpdateNotFoundWithError(current) { acknowledgements += 1 }
        XCTAssertEqual(messages.count, 1)
        XCTAssertNil(updates.presentation)
        driver.showUserInitiatedUpdateCheck(cancellation: {})
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        driver.showUpdaterError(offline) { acknowledgements += 1 }
        driver.dismissUpdateInstallation()
        XCTAssertEqual(updates.presentation, .failed(message: offline.localizedDescription))
        XCTAssertEqual(messages.count, 2)
        driver.showUserInitiatedUpdateCheck(cancellation: {})
        XCTAssertEqual(updates.presentation, .checking)
        driver.showUpdateFound(with: try item(), state: try state()) { _ in }
        XCTAssertEqual(updates.presentation, .available(release))
        XCTAssertEqual(acknowledgements, 3)
    }

    func testProgressHandlesUnknownAndIncorrectLengthsWithoutFloodingRenders() throws {
        let updates = AppUpdates()
        let driver: any SPUUserDriver = updates.driver
        driver.showUpdateFound(with: try item(), state: try state()) { _ in }
        updates.install()
        driver.showDownloadDidReceiveData(ofLength: 10)
        XCTAssertEqual(updates.presentation, .downloading(release, fraction: nil))
        driver.showDownloadDidReceiveExpectedContentLength(1_000)
        var renders = 0
        updates.changed = { renders += 1 }
        for _ in 0..<5 { driver.showDownloadDidReceiveData(ofLength: 1) }
        XCTAssertEqual(renders, 0)
        driver.showDownloadDidReceiveData(ofLength: UInt64.max)
        XCTAssertEqual(updates.presentation, .downloading(release, fraction: 1))
        XCTAssertEqual(renders, 1)
        driver.showDownloadDidReceiveExpectedContentLength(0)
        XCTAssertEqual(updates.presentation, .downloading(release, fraction: nil))
    }

    func testInvalidOrInformationalOffersNeverStartInstallation() throws {
        for appcast in [try item(build: "invalid"), try item(informationOnly: true)] {
            let updates = AppUpdates()
            let driver: any SPUUserDriver = updates.driver
            var replies: [SPUUserUpdateChoice] = []
            driver.showUpdateFound(with: appcast, state: try state()) { replies.append($0) }
            updates.driver.install()
            XCTAssertEqual(replies, [.dismiss])
            guard case .failed = updates.presentation else { return XCTFail("an unusable offer must be visible") }
        }
    }

    func testBundleConfigurationPreservesCustomFeedsAndUsesNativeArchitecture() {
        let production = ["SUFeedURL": "https://example.invalid/appcast-x86_64.xml"]
        XCTAssertEqual(UpdateFeed.url(info: production, arm64: true)?.lastPathComponent, "appcast-arm64.xml")
        XCTAssertEqual(UpdateFeed.url(info: production, arm64: false)?.lastPathComponent, "appcast-x86_64.xml")
        let fixture = "http://127.0.0.1:8765/fixture.xml?token=local"
        XCTAssertEqual(UpdateFeed.url(info: ["SUFeedURL": fixture], arm64: true)?.absoluteString, fixture)
        let updates = AppUpdates(bundle: Bundle(for: Self.self))
        var messages = 0
        updates.message = { _, _ in messages += 1 }
        updates.start()
        updates.start()
        updates.check()
        XCTAssertNil(updates.presentation)
        XCTAssertEqual(messages, 1)
    }

    func testSummarySurvivesRelaunchAndAcknowledgementIncludingLegacyUpgrades() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let receipt = directory.appendingPathComponent("history.json")
        let old = UpdateRelease(version: "0.0.1", build: 44)
        let new = UpdateRelease(version: "0.0.2", build: 45)
        XCTAssertNil(AppUpdateHistory(url: receipt).summary(for: old), "first install is not an update")
        XCTAssertNil(AppUpdateHistory(url: receipt).summary(for: old, previouslyLaunched: true))
        XCTAssertEqual(AppUpdateHistory(url: receipt).summary(for: new), new)
        let relaunched = AppUpdateHistory(url: receipt)
        XCTAssertEqual(relaunched.summary(for: new), new, "an unread summary survives another launch")
        relaunched.dismiss(new)
        XCTAssertNil(AppUpdateHistory(url: receipt).summary(for: new))
        XCTAssertNil(AppUpdateHistory(url: receipt).summary(for: old), "downgrades must not celebrate an update")

        let legacyReceipt = directory.appendingPathComponent("legacy.json")
        let legacy = AppUpdateHistory(url: legacyReceipt)
        XCTAssertEqual(legacy.summary(for: new, previouslyLaunched: true), new,
                       "released Sparkle builds already wrote SUHasLaunchedBefore before this history existed")
        legacy.dismiss(new)
        XCTAssertNil(AppUpdateHistory(url: legacyReceipt).summary(for: new, previouslyLaunched: true))
    }

    func testAutomaticPreferencePersistsAndBackgroundPreparationDoesNotRestart() throws {
        let suite = "brk-updates-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let updates = AppUpdates(defaults: defaults, directory: directory)
        var choices: [SPUUserUpdateChoice] = []
        var installs: [SPUUserUpdateChoice] = []
        updates.driver.showUpdateFound(with: try item(), state: try state()) { choices.append($0) }
        updates.setAutomaticUpdates(true)
        updates.setAutomaticUpdates(true)
        XCTAssertEqual(choices, [.install], "enabling automatic updates may prepare the offered update only once")
        XCTAssertTrue(AppUpdates(defaults: defaults, directory: directory).automaticUpdates)
        updates.driver.showDownloadDidStartExtractingUpdate()
        updates.driver.showReady(toInstallAndRelaunch: { installs.append($0) })
        pump()
        XCTAssertEqual(updates.presentation, .ready(release))
        XCTAssertTrue(installs.isEmpty, "preparation alone must not restart an active browsing session")
        updates.setAutomaticUpdates(false)
        XCTAssertFalse(AppUpdates(defaults: defaults, directory: directory).automaticUpdates)
    }

    func testAutomaticInstallRequiresScreenAwayAndNoActivityAndRechecksBeforeQuit() throws {
        let suite = "brk-updates-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let confirmed = Quit.confirmed, relaunch = Quit.relaunch
        defer {
            Quit.confirmed = confirmed; Quit.relaunch = relaunch
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let updates = AppUpdates(defaults: defaults, directory: directory)
        var inactive = false
        updates.canAutomaticallyRestart = { inactive }
        updates.setAutomaticUpdates(true)
        var installations = 0
        XCTAssertTrue(updates.driver.showAutomaticUpdateReady(try item()) { installations += 1 })
        updates.screenState.set(.locked, active: true)
        pump()
        XCTAssertEqual(installations, 0, "media, downloads or a modal dialog still prevent automatic restart")
        inactive = true
        updates.screenState.set(.locked, active: false)
        updates.installAutomaticallyIfAllowed()
        pump()
        XCTAssertEqual(installations, 0, "a quiet but visible screen is not enough")
        updates.screenState.set(.locked, active: true)
        updates.screenState.set(.locked, active: false)
        pump()
        XCTAssertEqual(installations, 0, "unlocking before the queued quit cancels automatic restart")
        XCTAssertEqual(updates.presentation, .ready(release))
        Quit.confirmed = false
        Quit.relaunch = true
        updates.screenState.set(.screensaver, active: true)
        pump()
        updates.installAutomaticallyIfAllowed()
        XCTAssertEqual(installations, 1)
        XCTAssertTrue(Quit.confirmed)
        XCTAssertFalse(Quit.relaunch)

        let feed = UpdateFeed(url: try XCTUnwrap(URL(string: "https://example.invalid/appcast.xml")), driver: updates.driver)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: updates.driver, delegate: feed)
        let failure = NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInvalid)
        feed.updater(updater, didAbortWithError: failure)
        XCTAssertTrue(updates.driver.canCheck, "a failed background installer releases its dead continuation")
        guard case .failed(let failureMessage) = updates.presentation else { return XCTFail("background installation must report failure") }
        XCTAssertTrue(failureMessage.contains(failure.localizedDescription))
        XCTAssertFalse(Quit.confirmed, "failed installation must not bypass the next ordinary quit confirmation")
        XCTAssertTrue(Quit.relaunch)
        feed.updater(updater, didFinishUpdateCycleFor: .updatesInBackground, error: failure)
        XCTAssertEqual(updates.presentation, .failed(message: failureMessage))

        XCTAssertTrue(updates.driver.showAutomaticUpdateReady(try item()) { installations += 1 })
        updates.installAutomaticallyIfAllowed()
        feed.updater(updater, didFinishUpdateCycleFor: .updatesInBackground, error: nil)
        pump()
        XCTAssertEqual(installations, 1, "a finished background cycle invalidates its queued installation")
        XCTAssertNil(updates.presentation)
        updates.setAutomaticUpdates(false)
        updates.driver.showUpdateFound(with: try item(), state: try state()) { _ in }
        let noUpdate = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue))
        feed.updater(updater, didAbortWithError: noUpdate)
        XCTAssertEqual(updates.presentation, .available(release), "unowned background callbacks do not dismiss a foreground offer")
    }

    func testMissingCandidateNotesStayOnTheCandidateVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let updates = AppUpdates(directory: directory)
        let notes = try XCTUnwrap(URL(string: "https://example.invalid/releases/0.0.1.html"))
        updates.driver.showUpdateFound(with: try item(notes: notes), state: try state()) { _ in }
        XCTAssertEqual(updates.releaseNotesURL, notes)
        updates.driver.showUpdateReleaseNotesFailedToDownloadWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        let fallback = try XCTUnwrap(updates.releaseNotesURL)
        XCTAssertTrue(fallback.isFileURL)
        let content = try String(contentsOf: fallback, encoding: .utf8)
        XCTAssertTrue(content.contains("Release notes for 0.0.1"))
        XCTAssertTrue(content.contains(notes.absoluteString))
        updates.driver.dismissUpdateInstallation()
        XCTAssertNil(updates.releaseNotesURL, "a late notes failure must not substitute the current installed notes")
    }

    func testDownloadedNotesAreCachedAndAvailableOnTheNextOffer() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = try XCTUnwrap(URL(string: "https://example.invalid/releases/0.0.1.html"))
        let updates = AppUpdates(directory: directory)
        updates.driver.showUpdateFound(with: try item(notes: notes), state: try state()) { _ in }
        let archive = NSKeyedArchiver(requiringSecureCoding: true)
        archive.encode(Data("<h1>Saved tab restoration is fixed</h1>".utf8), forKey: "SPUDownloadData")
        archive.encode(notes, forKey: "SPUDownloadURL")
        archive.encode("utf-8", forKey: "SPUDownloadTextEncoding")
        archive.encode("text/html", forKey: "SPUDownloadMIMEType")
        archive.finishEncoding()
        let decoder = try NSKeyedUnarchiver(forReadingFrom: archive.encodedData)
        let download = try XCTUnwrap(SPUDownloadData(coder: decoder))
        decoder.finishDecoding()
        updates.driver.showUpdateReleaseNotes(with: download)
        let cached = try XCTUnwrap(updates.releaseNotesURL)
        XCTAssertTrue(cached.isFileURL)
        XCTAssertTrue(try String(contentsOf: cached, encoding: .utf8).contains("Saved tab restoration is fixed"))
        let next = AppUpdates(directory: directory)
        next.driver.showUpdateFound(with: try item(notes: notes), state: try state()) { _ in }
        next.driver.showUpdateReleaseNotesFailedToDownloadWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        XCTAssertEqual(next.releaseNotesURL, cached, "an offline check retains notes already cached for this build")
    }
}

private final class StateDecoder: NSCoder {
    let stage: SPUUserUpdateStage
    init(stage: SPUUserUpdateStage) { self.stage = stage }
    override var allowsKeyedCoding: Bool { true }
    override func decodeInteger(forKey key: String) -> Int { stage.rawValue }
    override func decodeBool(forKey key: String) -> Bool { true }
}
