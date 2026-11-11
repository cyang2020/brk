import AppKit
import XCTest
@testable import BrkCEF

/// Chromium's save bubbles recognized by their structure (SavePrompts.swift). The tree below is what Chromium
/// 156's bubble showed through accessibility on 2026-11-12 (frames in screen points), trimmed to the elements that count.
final class SaveBubbleTests: XCTestCase {
    private func node(_ role: NSAccessibility.Role, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ children: [AXNode] = []) -> AXNode {
        AXNode(role: role.rawValue, frame: CGRect(x: x, y: y, width: w, height: h), children: children)
    }

    private func bubble(actions: [Double]) -> AXNode {
        node(.window, 1142, 132, 448, 374, [
            node(NSAccessibility.Role(rawValue: SaveBubble.heading), 1198, 272, 372, 24),
            node(.button, 1546, 152, 24, 22),
            node(.group, 1162, 304, 408, 84, [
                node(.comboBox, 1236, 304, 334, 36, [node(.textField, 1236, 304, 334, 36)]),
                node(.comboBox, 1236, 352, 334, 36, [node(.textField, 1236, 352, 334, 36), node(.checkBox, 1540, 358, 24, 24)]),
            ]),
            node(.group, 1142, 404, 448, 56, actions.map { node(.button, $0, 404, 99, 36) }),
            node(.link, 1299, 471, 107, 20),
        ])
    }

    func testThePasswordBubbleIsFoundWithItsButtonsLeftToRight() throws {
        let buttons = try XCTUnwrap(SaveBubble.passwordButtons(in: bubble(actions: [1471, 1162, 1364])))
        XCTAssertEqual([buttons.never.frame.minX, buttons.notNow.frame.minX, buttons.save.frame.minX], [1162, 1364, 1471])
    }

    func testRightToLeftReadsTheRowTheOtherWay() throws {
        let buttons = try XCTUnwrap(SaveBubble.passwordButtons(in: bubble(actions: [1162, 1364, 1471]), rightToLeft: true))
        XCTAssertEqual(buttons.save.frame.minX, 1162)
        XCTAssertEqual(buttons.never.frame.minX, 1471)
    }

    /// Save address? (an Edit button beside the close button) and Save card? (the card network's image), as Chromium 156
    /// showed them for the fixture forms.
    func testAddressAndCardBubblesAreFound() throws {
        let heading = node(NSAccessibility.Role(rawValue: SaveBubble.heading), 1290, 272, 280, 24)
        let close = node(.button, 1546, 152, 24, 22)
        let row = [node(.button, 1474, 475, 96, 36), node(.button, 1370, 475, 96, 36)]
        let address = node(.window, 1270, 132, 320, 399, [heading, close, node(.staticText, 1322, 305, 119, 80), node(.button, 1546, 304, 24, 24)] + row)
        let card = node(.window, 1270, 132, 320, 338, [heading, close, node(.staticText, 1290, 304, 280, 40), node(.image, 1290, 360, 48, 30)] + row)
        let a = try XCTUnwrap(SaveBubble.classify(address))
        XCTAssertEqual(a.kind, .address)
        XCTAssertEqual([a.buttons.notNow.frame.minX, a.buttons.save.frame.minX], [1370, 1474])
        XCTAssertNil(a.buttons.never)
        XCTAssertEqual(try XCTUnwrap(SaveBubble.classify(card)).kind, .card)
    }

    /// The password update state (two buttons beside the fields) and Chromium's other widgets (the autofill list) stay Chromium's.
    func testOtherBubblesAreLeftAlone() {
        XCTAssertNil(SaveBubble.classify(bubble(actions: [1364, 1471])))
        let autofill = node(.window, 655, 197, 200, 48, [node(.group, 655, 197, 200, 48, [node(.cell, 663, 205, 184, 32), node(.button, 820, 211, 20, 20)])])
        XCTAssertNil(SaveBubble.classify(autofill))
    }
}
