import BrkBase
import BrkDomain
import BrkLayout
import CoreGraphics
import XCTest
@testable import BrkControl

/// The wire format is Codable on both sides; these pin that every request the runner builds decodes on the server
/// side unchanged, and every reply the server builds decodes on the runner side.
final class ProtocolTests: XCTestCase {
    /// One tag per `ControlOp` case. `tag(of:)` is an exhaustive switch over the op and `sample(_:)` one over the tags,
    /// so a new op does not compile until it has a tag and a sample here.
    enum Tag: String, CaseIterable {
        case chooseOutputFixture, cancelCurrentOutput, selectLinkExportFixture, configureSavePanel, answerSavePanel, cancelPrintPanel, menuAction, pasteboard, readPasteboard, screenshotSheet
        case mediaWindowScreenshot, mediaSounds, captureProbe, sidebarData, sidebarPanel
        case hello, view, activate, native, dispatch, load, press, hold, type, click, captureContextMenu, hover, screenshot, pixel, advanceClock, evaluate, crash
        case nativeDialogKey, setAppAppearance, siteControlsScreenshot, siteControls, siteControlInput, siteControlTexts
        case pointerDrag, scrollGesture, sheetButton, selectSheetDirectory
        case setWindowFrame, pageLog, pageObservations, flush, settle, quit, settings, openSettings, externalURL, pointer
    }

    static func tag(of op: ControlOp) -> Tag {
        switch op {
        case .mediaWindowScreenshot: .mediaWindowScreenshot
        case .mediaSounds: .mediaSounds
        case .captureProbe: .captureProbe
        case .sidebarData: .sidebarData
        case .sidebarPanel: .sidebarPanel
        case .chooseOutputFixture: .chooseOutputFixture
        case .cancelCurrentOutput: .cancelCurrentOutput
        case .selectLinkExportFixture: .selectLinkExportFixture
        case .configureSavePanel: .configureSavePanel
        case .answerSavePanel: .answerSavePanel
        case .cancelPrintPanel: .cancelPrintPanel
        case .menuAction: .menuAction
        case .pasteboard: .pasteboard
        case .readPasteboard: .readPasteboard
        case .screenshotSheet: .screenshotSheet
        case .nativeDialogKey: .nativeDialogKey
        case .setAppAppearance: .setAppAppearance
        case .siteControlsScreenshot: .siteControlsScreenshot
        case .siteControls: .siteControls
        case .siteControlInput: .siteControlInput
        case .siteControlTexts: .siteControlTexts
        case .hello: .hello
        case .view: .view
        case .activate: .activate
        case .native: .native
        case .dispatch: .dispatch
        case .load: .load
        case .press: .press
        case .hold: .hold
        case .type: .type
        case .click: .click
        case .captureContextMenu: .captureContextMenu
        case .pointerDrag: .pointerDrag
        case .scrollGesture: .scrollGesture
        case .sheetButton: .sheetButton
        case .selectSheetDirectory: .selectSheetDirectory
        case .hover: .hover
        case .pointer: .pointer
        case .screenshot: .screenshot
        case .pixel: .pixel
        case .advanceClock: .advanceClock
        case .evaluate: .evaluate
        case .crash: .crash
        case .setWindowFrame: .setWindowFrame
        case .pageLog: .pageLog
        case .pageObservations: .pageObservations
        case .flush: .flush
        case .settle: .settle
        case .quit: .quit
        case .settings: .settings
        case .openSettings: .openSettings
        case .externalURL: .externalURL
        }
    }

    static func samples(_ tag: Tag) -> [ControlOp] {
        let page = PageID(window: WindowID("w"), item: ItemID("t3"))
        switch tag {
        case .mediaWindowScreenshot: return [.mediaWindowScreenshot(number:1,path:"/tmp/owned-pip.png")]
        case .mediaSounds: return [.mediaSounds]
        case .captureProbe: return [.captureProbe(page: page, directory: URL(fileURLWithPath: "/tmp/owned"))]
        case .sidebarData: return [.sidebarData]
        case .sidebarPanel: return [.sidebarPanel(window: nil, action: .inspect), .sidebarPanel(window: WindowID("w"), action: .save(directory: "/tmp/owned", filename: "tabs.html")), .sidebarPanel(window: nil, action: .open(path: "/tmp/selected.html"))]
        case .chooseOutputFixture: return [.chooseOutputFixture(window: nil, path: "/tmp/fixture.pdf")]
        case .cancelCurrentOutput: return [.cancelCurrentOutput(window: nil)]
        case .selectLinkExportFixture: return [.selectLinkExportFixture(window: WindowID("w"), path: "/tmp/owned/link.json")]
        case .configureSavePanel: return [.configureSavePanel(window: nil, path: "/tmp/fixture.pdf")]
        case .answerSavePanel: return [.answerSavePanel(window: nil, path: "/tmp/fixture.pdf"), .answerSavePanel(window: nil, path: nil)]
        case .cancelPrintPanel: return [.cancelPrintPanel(window: nil)]
        case .menuAction: return [.menuAction("Copy")]
        case .pasteboard: return [.pasteboard("fixture"), .pasteboard(nil)]
        case .readPasteboard: return [.readPasteboard]
        case .screenshotSheet: return [.screenshotSheet(window: nil, path: "/tmp/sheet.png")]
        case .nativeDialogKey: return [.nativeDialogKey(number: 7, chord: "return")]
        case .setAppAppearance: return [.setAppAppearance(.dark), .setAppAppearance(nil)]
        case .siteControlsScreenshot: return [.siteControlsScreenshot(window: WindowID("w"), path: "/tmp/panel.png")]
        case .siteControls: return [.siteControls]
        case .siteControlTexts: return [.siteControlTexts(window: WindowID("w"))]
        case .siteControlInput: return [.siteControlInput(window: WindowID("w"), field: "extension-shortcut-fixture-run", action: .focus), .siteControlInput(window: WindowID("w"), field: "siteExportLink", action: .press)]
        case .hello: return [.hello]
        case .view: return [.view(window: nil), .view(window: WindowID("w1"))]
        case .activate: return [.activate(window: WindowID("w"))]
        case .native: return [.native(window: WindowID("w1"))]
        case .captureContextMenu: return [.captureContextMenu(window: WindowID("w1"), point: CGPoint(x: 40, y: 60))]
        case .dispatch:
            return [.dispatch(window: nil, command: .space(.focus(SpaceID("s2")))),
                    .dispatch(window: WindowID("w1"), command: .space(.create(title: "Work", icon: .none, theme: .default))),
                    .dispatch(window: nil, command: .item(.move(ItemID("t1"), to: .into(parent: ItemID("r1"), index: 2))))]
        case .load: return [.load(window: nil, url: URL(string: "http://127.0.0.1:8000/page2.html")!)]
        case .press: return [.press(chord: "cmd+t"), .press(chord: "ctrl+shift+=")]
        case .hold: return [.hold(modifiers: "ctrl", chord: "tab", times: 2)]
        case .type: return [.type(text: "http://127.0.0.1:8000/page2.html"), .type(text: "x \"quoted\" ü")]
        case .click:
            return [.click(view: .dockSpace(SpaceID("s1")), point: nil, modifiers: nil, count: 1),
                    .click(view: nil, point: CGPoint(x: 400, y: 120), modifiers: "cmd", count: 2)]
        case .pointerDrag: return [.pointerDrag(from: .zero, to: CGPoint(x: 80, y: 50), cancel: false)]
        case .scrollGesture: return [.scrollGesture(at: .zero, horizontal: -120, vertical: 0, cancel: true)]
        case .sheetButton: return [.sheetButton(title: "Cancel")]
        case .selectSheetDirectory: return [.selectSheetDirectory(path: "/tmp/owned-fixture")]
        case .hover: return [.hover(point: CGPoint(x: 5, y: 388))]
        case .pointer: return [.pointer(window: nil, phase: .down, point: CGPoint(x: 50, y: 60)),
                              .pointer(window: WindowID("w"), phase: .dragged, point: CGPoint(x: 600, y: 300)),
                              .pointer(window: WindowID("w"), phase: .up, point: CGPoint(x: 600, y: 300))]
        case .screenshot: return [.screenshot(window: nil, path: "/tmp/shots/0-launch.png")]
        case .pixel: return [.pixel(window: nil, point: CGPoint(x: 4, y: 200))]
        case .advanceClock: return [.advanceClock(seconds: 46_800), .advanceClock(seconds: -1)]
        case .evaluate: return [.evaluate(page: page, script: "document.title = 'x'")]
        case .crash: return [.crash(page: page, process: .renderer), .crash(page: page, process: .gpu)]
        case .setWindowFrame: return [.setWindowFrame(window: nil, frame: CGRect(x: 5000, y: 4000, width: 1000, height: 700))]
        case .pageLog: return [.pageLog]
        case .pageObservations: return [.pageObservations]
        case .flush: return [.flush]
        case .settle: return [.settle(timeout: 5)]
        case .quit: return [.quit]
        case .settings: return [.settings]
        case .openSettings: return [.openSettings(pane: .links)]
        case .externalURL: return [.externalURL(url: URL(string: "https://example.com/from-another-app")!)]
        }
    }

    func testEveryOpRoundTripsThroughTheWire() throws {
        for tag in Tag.allCases {
            let ops = Self.samples(tag)
            XCTAssertFalse(ops.isEmpty, "\(tag) has no sample")
            for (i, op) in ops.enumerated() {
                XCTAssertEqual(Self.tag(of: op), tag)
                let line = try ControlWire.encode(ControlRequest(id: i, op: op))
                XCTAssertEqual(line.last, 0x0A, "\(tag): one line")
                XCTAssertFalse(line.dropLast().contains(0x0A), "\(tag): no newline inside the line")
                // The op's wire name is its case name: what scripts/ctl.sh users type.
                let object = try JSONSerialization.jsonObject(with: line.dropLast()) as? [String: Any]
                XCTAssertEqual((object?["op"] as? [String: Any])?.keys.first, tag.rawValue)
                XCTAssertEqual(try ControlWire.parseRequest(line.dropLast()).get(), ControlRequest(id: i, op: op))
            }
        }
    }

    func testRepliesRoundTrip() throws {
        let results: [ControlResult] = [
            .text("fixture"), .menuItems(["Back", "Reload"]),
            .siteControls([:]),
            .ok, .hello(Hello(pid: 42, engine: "stub", windows: [WindowID("w1")], dataDirectory: "/tmp/brk")), .dispatched(rev: 3),
            .loaded(tab: ItemID("t9")), .pixel(red: 255, green: 0, blue: 0, alpha: 255),
            .screenshot(path: "/tmp/a.png", pixelWidth: 2560, pixelHeight: 1552), .clock(now: Instant(milliseconds: 1_700_000_000_000)),
            .pageLog([PageLogEntry(page: PageID(window: WindowID("w"), item: ItemID("t1")), generation: 2, kind: .closed, browserID: 7, uptime: 12.5)]),
            .failed("no window"),
            .native(NativeFacts(window: WindowID("w1"), windowFrame: CGRect(x: 0, y: 0, width: 1280, height: 776),
                                contentSize: CGSize(width: 1280, height: 776), backingScale: 2, isKey: true,
                                computed: WindowFrames(contentSize: CGSize(width: 1280, height: 776), sidebar: nil, sidebarFloats: false,
                                                       resizeHandle: nil, revealStrip: CGRect(x: -20, y: 0, width: 35, height: 776),
                                                       contentArea: CGRect(x: 10, y: 10, width: 1260, height: 756), cards: [],
                                                       dividers: [], commandBar: nil, library: nil, peek: nil),
                                actual: ["card-0": ActualView(frame: CGRect(x: 10, y: 10, width: 1260, height: 756), hidden: false, cornerRadius: 6)],
                                pages: [PageID(window: WindowID("w"), item: ItemID("t1")): PageFacts(surfaceFrame: nil, embeddedViews: [], browserID: nil,
                                                                        hostWindowNumber: nil, hasKeyboardFocus: false)],
                                firstResponder: "NSTextView:command-bar-input", focusedPage: nil,
                                appWindows: [AppWindowFact(number: 9, className: "BrkApp.BrowserWindow", isKey: true, isVisible: true)])),
        ]
        for (i, result) in results.enumerated() {
            let line = try ControlWire.encode(ControlReply(id: i, result: result))
            XCTAssertEqual(try ControlWire.decode(ControlReply.self, line: line.dropLast()), ControlReply(id: i, result: result))
        }
    }

    func testLineBufferSplitsLinesAcrossReads() {
        var buffer = ControlLineBuffer()
        buffer.append(Data("{\"a\":1}\n\n{\"b\"".utf8))
        XCTAssertEqual(buffer.nextLine(), Data("{\"a\":1}".utf8))
        XCTAssertNil(buffer.nextLine())
        buffer.append(Data(":2}\n".utf8))
        XCTAssertEqual(buffer.nextLine(), Data("{\"b\":2}".utf8))
        XCTAssertNil(buffer.nextLine())
    }

    func testViewIdentifiersAreStableStrings() {
        XCTAssertEqual(ViewID.dockSpace(SpaceID("s1")).identifier, "dock-space-s1")
        XCTAssertEqual(ViewID.row(ItemID("t1")).identifier, "row-t1")
        XCTAssertEqual(ViewID.archiveGroup(.today).identifier, "archive-group-today")
    }
}
