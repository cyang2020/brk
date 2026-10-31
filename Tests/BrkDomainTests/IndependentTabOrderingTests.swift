import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class IndependentTabOrderingTests: XCTestCase {
    func testMixedSelectionFollowsVisibleSidebarOrderNotRootIDOrder() throws {
        let setup = Driver()
        let pinned = setup.todayIDs[0]
        setup.user(.tab(.togglePin(.item(pinned))))
        let today = setup.open("https://example.com/today")
        let p = setup.view.space.pinned.root.rawValue, t = setup.view.space.today.root.rawValue
        // IDs are opaque. A byte-equivalent rename of the two section IDs changes no hierarchy.
        let text = String(decoding: setup.savedFile, as: UTF8.self)
        let swapped = text.replacingOccurrences(of: "\"\(p)\"", with: "\"TEMP_ROOT\"")
            .replacingOccurrences(of: "\"\(t)\"", with: "\"\(p)\"")
            .replacingOccurrences(of: "\"TEMP_ROOT\"", with: "\"\(t)\"")
        let d = Driver(file: Data(swapped.utf8))
        XCTAssertEqual(d.pinnedIDs, [pinned]); XCTAssertEqual(d.todayIDs, [today])
        d.user(.tabTools(.select(pinned, .replace)))
        d.user(.tabTools(.select(today, .range)))
        XCTAssertEqual(d.view.tabTools.selected, [pinned, today])
        d.user(.tabTools(.bulk(.selected, .newFolder(group: true))))
        guard case .folder(let group)? = d.view.space.pinned.rows.first else { return XCTFail("group missing") }
        print("REVIEW sidebar order=\([pinned,today]) grouped order=\(group.children.map(\.id))")
        XCTAssertEqual(group.children.map(\.id), [pinned, today], "mixed selection was sorted by opaque section IDs")
    }
}
