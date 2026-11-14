import BrkBase
import Foundation
import Sparkle
import XCTest
@testable import BrkApp

@MainActor
final class AppUpdatesTests: XCTestCase {
    private let release = UpdateRelease(version: "0.0.1", build: 44)

    private func item(build: String = "44", informationOnly: Bool = false) throws -> SUAppcastItem {
        let dictionary: [String: Any] = informationOnly
            ? ["sparkle:version": build, "sparkle:shortVersionString": "0.0.1", "link": "https://example.invalid/notes"]
            : ["enclosure": ["url": "https://example.invalid/Brk.dmg", "sparkle:version": build,
                               "sparkle:shortVersionString": "0.0.1", "length": "100"]]
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
}

private final class StateDecoder: NSCoder {
    let stage: SPUUserUpdateStage
    init(stage: SPUUserUpdateStage) { self.stage = stage }
    override var allowsKeyedCoding: Bool { true }
    override func decodeInteger(forKey key: String) -> Int { stage.rawValue }
    override func decodeBool(forKey key: String) -> Bool { true }
}
