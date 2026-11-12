import BrkBase
import XCTest
@testable import BrkDomain

/// A group dropped onto a group nested inside it (group A > folder F > group B, A dropped onto B): the merge moved what
/// it could into B and then removed A with everything still under it, B and its tabs included, without archiving them.
final class TabGroupMergeTests: XCTestCase {
    func testDroppingAGroupOntoAGroupInsideItLosesNoTab() throws {
        let d = Driver()
        let one = d.open("https://one.example/"), two = d.open("https://two.example/"), three = d.open("https://three.example/")
        d.user(.tabTools(.bulk(.items([one]), .newFolder(group: true))))
        let a = try XCTUnwrap(d.state.doc.tree[one]?.parent)
        d.user(.tabTools(.bulk(.items([two]), .newFolder(group: false))))
        let f = try XCTUnwrap(d.state.doc.tree[two]?.parent)
        d.user(.tabTools(.bulk(.items([three]), .newFolder(group: true))))
        let b = try XCTUnwrap(d.state.doc.tree[three]?.parent)
        d.user(.item(.move(f, to: .into(parent: a, index: 1))))
        d.user(.item(.move(b, to: .into(parent: f, index: 1))))
        XCTAssertTrue(d.state.doc.tree.isDescendant(b, of: a), "a group can sit in a folder inside a group")
        d.user(.item(.move(a, to: .into(parent: b, index: 0))))
        for tab in [one, two, three] { XCTAssertNotNil(d.state.doc.tree[tab], "\(tab) is still in the sidebar") }
        XCTAssertTrue(d.state.doc.tree.isDescendant(b, of: a), "the drop is refused")
    }
}
