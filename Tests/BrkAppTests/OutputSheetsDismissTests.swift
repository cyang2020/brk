import AppKit
import BrkBase
import XCTest
@testable import BrkApp

/// Save Page As or Export PDF asked while the window already shows a sheet (a page's dialog, a download prompt) waits
/// for its turn. Taking it away then (the page went, the window was minimized or the app hidden) dropped its answer:
/// with only the rendering timed, the save stayed at "Choose a destination" until the person cancelled it.
@MainActor
final class OutputSheetsDismissTests: XCTestCase {
    func testDismissingASaveThatWaitsBehindAnotherSheetAnswersIt() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView()
        window.orderFront(nil)
        defer { window.close() }
        let other = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        window.beginSheet(other)
        defer { window.endSheet(other); other.close() }
        for _ in 0..<20 where window.attachedSheet == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        _ = try XCTUnwrap(window.attachedSheet, "the other sheet is up")

        let sheets = OutputSheets()
        let page = PageID(window: WindowID("w"), item: ItemID("t"))
        let request = OutputRequest(id: OutputID("save"), document: DocumentToken(browser: BrowserToken(page: page, generation: 1), sequence: 1),
                                    intent: .mhtml, suggestedName: "Page")
        var answers: [String] = []
        sheets.destination(OutputDestinationPrompt(request: request), in: window) { answer in
            switch answer {
            case .accepted(let url): answers.append("accepted \(url.path)")
            case .cancelled: answers.append("cancelled")
            case .ownerGone: answers.append("ownerGone")
            }
        }
        XCTAssertEqual(answers, [], "it waits behind the other sheet")
        sheets.dismiss(request.id)
        XCTAssertEqual(answers, ["ownerGone"], "the waiting save was never answered")
        sheets.dismiss(request.id)
        XCTAssertEqual(answers, ["ownerGone"], "answered once")
    }
}
