import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class DataLifecycleTests: XCTestCase {
    func testProfileClearIsIndependentOfLoadedPagesAndDeletionAndOnlyAcknowledgesRequestedHistory() throws {
        let d = Driver()
        d.user(.profile(.create(name: "Unused", icon: nil)))
        let id = try XCTUnwrap(d.snapshot.settings.profiles.first { $0.profile.name == "Unused" }?.profile.id)
        let profiles = d.state.doc.profiles, settings = d.state.doc.settings.profiles, favorites = d.state.doc.favorites
        let transition = d.user(.site(.clearProfile(id, [.cookies, .history])))
        guard case .clearProfileData(let request)? = transition.effects.first else { return XCTFail("missing clear request") }
        XCTAssertEqual(request.profile, id)
        XCTAssertEqual(d.snapshot.settings.profiles.first { $0.profile.id == id }?.clearingData, true)
        XCTAssertTrue(d.user(.site(.clearProfile(id, [.cache]))).effects.isEmpty, "concurrent clear is not submitted")
        let result = ClearProfileDataResult(request: request, completed: [.cookies], error: "fixture interruption")
        d.system(.profileDataCleared(result))
        XCTAssertEqual(d.snapshot.settings.profiles.first { $0.profile.id == id }?.clearDataResult, result)
        XCTAssertEqual(d.state.doc.profiles, profiles)
        XCTAssertEqual(d.state.doc.settings.profiles, settings)
        XCTAssertEqual(d.state.doc.favorites, favorites)
        XCTAssertTrue(d.state.doc.deletingProfiles.isEmpty)
        XCTAssertTrue(d.system(.profileDataCleared(result)).effects.isEmpty)
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("fixture interruption"), "operation results stay transient")
    }

    func testClearHistoryCompletionIsScopedAndCannotRecreateDeletedProfile() throws {
        let d = Driver()
        let oldHistory = d.state.doc.history
        let transition = d.user(.site(.clearProfile(.default, [.cookies])))
        guard case .clearProfileData(let request)? = transition.effects.first else { return XCTFail("missing request") }
        d.system(.profileDataCleared(.init(request: request, completed: [.cookies], error: nil)))
        XCTAssertEqual(d.state.doc.history, oldHistory)
        d.user(.profile(.create(name: "Remove", icon: nil)))
        let id = try XCTUnwrap(d.snapshot.settings.profiles.first { $0.profile.name == "Remove" }?.profile.id)
        let clearing = d.user(.site(.clearProfile(id, [.history])))
        guard case .clearProfileData(let pending)? = clearing.effects.first else { return XCTFail("missing request") }
        d.user(.profile(.delete(id)))
        d.system(.profileDataCleared(.init(request: pending, completed: [.history], error: nil)))
        XCTAssertNil(d.state.doc.profiles[id])
        XCTAssertNil(d.snapshot.settings.profiles.first { $0.profile.id == id })
        XCTAssertTrue(d.user(.site(.clearProfile(id, [.cookies]))).effects.isEmpty)
    }
}
