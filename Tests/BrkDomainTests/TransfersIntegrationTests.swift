import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class TransfersIntegrationTests: XCTestCase {
    func testPrivateEpochRevokesBeforeDrainAndNextWindowGetsFreshIdentity() throws {
        let d = Driver()
        d.user(.window(.newIncognito))
        let first = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        let old = try XCTUnwrap(d.state.session.privateSession)
        d.user(.window(.newIncognito))
        let second = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito && $0.id != first }?.id)
        XCTAssertFalse(d.user(.window(.close), in: first).effects.contains { if case .disposeContext = $0 { return true }; return false })
        let effects = d.system(.window(second, .closed)).effects
        guard case .disposeContext(let request)? = effects.first else { return XCTFail("no revocation") }
        XCTAssertEqual(request.context, .incognito(old)); XCTAssertNil(d.state.session.privateSession)
        d.user(.window(.newIncognito))
        let fresh = try XCTUnwrap(d.state.session.privateSession)
        XCTAssertNotEqual(old, fresh)
        d.system(.contextDisposed(.completed(request.id, request.context, .memoryReleased)))
        XCTAssertEqual(d.state.session.privateSession, fresh)
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains(fresh.rawValue))
    }

    func testFrozenTransferOriginSurvivesWindowRemovalAndProfileReassignment() throws {
        let d = Driver(); let tab = d.todayIDs[0]
        let page = PageID(window: d.window, item: tab)
        let owner = DownloadOwner(browser: d.state.session.live[page]!.browser!, context: ContextEpoch(context: .profile(.default), generation: 1), policy: .default)
        let id = DownloadID("owned")
        let details = DownloadDetails(url: url("https://example.com/original"), suggestedName: "original")
        d.system(.download(DownloadUpdate(id: id, owner: owner, details: details, revision: 1, stage: .receiving(TransferProgress(received: 4, total: 10)))))
        d.user(.profile(.create(name: "Other", icon: nil)))
        let other = try XCTUnwrap(d.snapshot.settings.profiles.first { $0.profile.id != .default }?.profile.id)
        d.user(.profile(.assign(.current, to: other)))
        d.user(.tab(.close(.item(tab))))
        d.system(.download(DownloadUpdate(id: id, owner: owner, details: details, revision: 2, stage: .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/original"), bytes: 10))))))
        XCTAssertEqual(d.state.doc.downloads.first?.profile, .default)
        XCTAssertEqual(d.state.doc.downloads.first?.state, .finished)
        let stale = d.system(.download(DownloadUpdate(id: id, owner: owner, details: details, revision: 1, stage: .receiving(TransferProgress(received: 1, total: 10)))))
        XCTAssertFalse(stale.changed)
        XCTAssertEqual(Driver(file: d.savedFile).state.doc.downloads.first?.end, d.state.doc.downloads.first?.end)
    }

    func testFailedDisposalPersistsAndRetryWaitsForCorrelatedFinalResult() throws {
        let d = Driver()
        d.user(.profile(.create(name: "Delete", icon: nil)))
        let profile = try XCTUnwrap(d.snapshot.settings.profiles.first { $0.profile.id != .default }?.profile.id)
        guard case .disposeContext(let first)? = d.user(.profile(.delete(profile))).effects.first else { return XCTFail() }
        XCTAssertNotNil(d.state.doc.deletingProfiles[profile])
        d.system(.contextDisposed(.failed(first.id, first.context, reason: "host did not close")))
        XCTAssertEqual(d.state.doc.deletingProfiles[profile]?.failure, "host did not close")
        let restored = Driver(file: d.savedFile)
        XCTAssertNotNil(restored.state.doc.deletingProfiles[profile]?.failure)
        guard case .disposeContext(let retry)? = d.user(.profile(.delete(profile))).effects.first else { return XCTFail() }
        XCTAssertNotEqual(first.id, retry.id)
        d.system(.contextDisposed(.completed(first.id, first.context, .deletionScheduledForNextLaunch)))
        XCTAssertNotNil(d.state.doc.deletingProfiles[profile])
        d.system(.contextDisposed(.completed(retry.id, retry.context, .deletionScheduledForNextLaunch)))
        XCTAssertNil(d.state.doc.deletingProfiles[profile])
    }
}
