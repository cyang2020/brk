import BrkBase
import BrkDomain
import BrkLayout
import CoreGraphics
import XCTest
@testable import BrkControl

let pendingW6 = "W6: not implemented yet"

/// The wire format is Codable on both sides; these run now and pin that every request the runner builds decodes on
/// the server side unchanged.
final class ProtocolTests: XCTestCase {
    func testRequestsRoundTrip() throws {
        let ops: [ControlOp] = [
            .hello, .view(window: nil), .native(window: WindowID("w1")),
            .dispatch(window: nil, command: .space(.focus(SpaceID("s2")))),
            .load(window: nil, url: URL(string: "http://127.0.0.1:8000/page2.html")!), .press(chord: "cmd+t"), .hold(modifiers: "ctrl", chord: "tab", times: 2), .type(text: "http://127.0.0.1:8000/page2.html"),
            .click(view: .dockSpace(SpaceID("s1")), point: nil, modifiers: nil, count: 1),
            .click(view: nil, point: CGPoint(x: 400, y: 120), modifiers: "cmd", count: 1),
            .pixel(window: nil, point: CGPoint(x: 4, y: 200)), .advanceClock(seconds: 46_800),
            .crash(page: PageID(ItemID("t3")), process: .renderer), .pageLog, .settle(timeout: 5), .quit,
        ]
        for (i, op) in ops.enumerated() {
            let line = try ControlWire.encode(ControlRequest(id: i, op: op))
            XCTAssertEqual(line.last, 0x0A)
            XCTAssertEqual(try ControlWire.decode(ControlRequest.self, line: line.dropLast()), ControlRequest(id: i, op: op))
        }
    }

    func testViewIdentifiersAreStableStrings() {
        XCTAssertEqual(ViewID.dockSpace(SpaceID("s1")).identifier, "dock-space-s1")
        XCTAssertEqual(ViewID.row(ItemID("t1")).identifier, "row-t1")
        XCTAssertEqual(ViewID.archiveGroup(.today).identifier, "archive-group-today")
    }
}
