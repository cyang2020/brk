import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class DataLifecycleTests: XCTestCase {

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
