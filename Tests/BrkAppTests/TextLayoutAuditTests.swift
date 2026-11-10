import AppKit
import BrkControl
import XCTest
@testable import BrkApp

/// `TextLayoutAudit` against views cut on purpose, in a real window: each rule reports the case it is for and stays
/// quiet on the same text given the room it needs.
@MainActor final class TextLayoutAuditTests: XCTestCase {
    private func audit(_ build: (NSView) -> Void) -> TextLayoutReport {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = root
        build(root)
        DrawnTextRecorder.install()
        var walk = TextLayoutAudit.Walk()
        walk.visit(window)
        return walk.report
    }

    private func label(_ text: String, font: NSFont = .systemFont(ofSize: 11, weight: .semibold)) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.isSelectable = false
        return label
    }

    private func problems(_ report: TextLayoutReport, _ text: String) -> [TextLayoutFinding.Problem] {
        report.findings.filter { $0.text == text }.map(\.problem)
    }

    /// The bug the check was written for: a frame of `intrinsicContentSize` leaves out the cell's inset.
    func testAFrameOfTheIntrinsicWidthIsCut() {
        let report = audit { root in
            let clear = label("Clear")
            clear.frame = CGRect(origin: CGPoint(x: 20, y: 20), size: clear.intrinsicContentSize)
            root.addSubview(clear)
        }
        XCTAssertEqual(problems(report, "Clear"), [.overflowsFrame])
        XCTAssertEqual(report.measured.count, 1)
        XCTAssertTrue(report.measured[0].hasPrefix("Clear | frame "))
    }

    func testAFrameOfTheCellSizeFits() {
        let report = audit { root in
            let clear = label("Clear")
            clear.frame = CGRect(origin: CGPoint(x: 20, y: 20), size: clear.fittingSize)
            root.addSubview(clear)
        }
        XCTAssertEqual(report.findings, [])
        XCTAssertEqual(report.truncated, [])
    }

    func testATruncatingLabelTooNarrowIsListedNotCut() {
        let report = audit { root in
            let long = label("A long title that cannot fit its row")
            long.lineBreakMode = .byTruncatingTail
            long.frame = CGRect(x: 20, y: 20, width: 80, height: 16)
            root.addSubview(long)
        }
        XCTAssertEqual(report.findings, [])
        XCTAssertEqual(report.truncated.map(\.problem), [.ellipsis])
    }
}
