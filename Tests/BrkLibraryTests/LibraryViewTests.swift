import AppKit
import BrkBase
@testable import BrkDomain
import BrkLayout
import BrkUIKit
import XCTest
@testable import BrkLibrary

extension NSView {
    var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) }
}

/// Owner: F5. The Library as the window shows it (P32): the panel in place of the sidebar, a navigation column and
/// the open page's column, the content area left to the page; and what each control dispatches. Frames come from
/// the real layout of a real snapshot.
@MainActor
final class LibraryViewTests: XCTestCase {
    private var sent: [Command] = []
    /// Fri 30 Oct 2026 15:05 UTC.
    private let now = Instant(milliseconds: 1_793_372_700_000)
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// The frames of a fresh window (1280 x 776, sidebar 228) with the Library open on `page`.
    private func frames(_ page: LibraryPage) -> WindowFrames {
        let size = CGSize(width: 1280, height: 776)
        let ctx = { Context(now: self.now, newID: { UUID().uuidString }) }
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: size), ctx: ctx()).state
        let projection = ProjectionContext(now: now, calendar: utc)
        let window = project(state, projection).windows.keys.sorted()[0]
        state = reduce(state, .user(window, .library(.open(page))), ctx()).state
        return WindowLayout.compute(project(state, projection).windows[window]!, contentSize: size)
    }

    private func makeView() -> LibraryView {
        let view = LibraryView(dispatch: { [unowned self] in self.sent.append($0) })
        view.downloads.calendar = utc
        return view
    }

    private func render(_ view: LibraryView, _ snapshot: LibrarySnapshot) -> WindowFrames {
        let f = frames(snapshot.page)
        view.render(snapshot, now: now, frames: f, palette: Palette(resolveTheme(.default)))
        return f
    }

    private func shown(_ root: NSView) -> [NSView] { root.descendants.filter { !$0.isHiddenOrHasHiddenAncestor } }
    private func view(_ id: ViewID, in root: NSView) -> NSView? { shown(root).first { $0.accessibilityIdentifier() == id.identifier } }
    private func texts(_ root: NSView?) -> [String] {
        guard let root else { return [] }
        return shown(root).compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty }
    }

    private func library(_ page: LibraryPage, downloads: [DownloadRow] = [], openID: Int = 1) -> LibrarySnapshot {
        LibrarySnapshot(openID: openID, page: page, archive: page == .archive ? ArchiveSnapshot(openID: openID, groups: [], threshold: .twelveHours) : nil,
                        downloads: downloads)
    }

    // MARK: Downloads

    private func download(_ id: String, _ name: String, _ state: DownloadState, received: Int64, total: Int64?, path: String?) -> DownloadRow {
        DownloadRow(id: DownloadID(id), filename: name, url: URL(string: "https://files.example.com/\(name)")!, path: path,
                    received: received, total: total, state: state, startedAt: now)
    }

    private func row(_ id: String, in view: NSView) -> LibraryRowView? { self.view(.downloadEntry(DownloadID(id)), in: view) as? LibraryRowView }

    /// a row per download with its name, size or progress and state; a finished file opens on click and shows in the
    /// Finder, a running one cancels, the others leave the list; Clear Downloads and the search
    func testTheDownloadsPageListsRowsWithProgressAndActions() throws {
        let view = makeView()
        var opened: [URL] = []
        view.downloads.openFile = { opened.append($0) }
        view.downloads.fileExists = { $0 == "/tmp/d/report.pdf" }
        let size = { (n: Int64) in ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
        _ = render(view, library(.downloads, downloads: [
            download("1", "report.pdf", .finished, received: 2048, total: 2048, path: "/tmp/d/report.pdf"),
            download("2", "moved.zip", .finished, received: 10, total: 10, path: "/tmp/d/moved.zip"),
            download("3", "big.iso", .inProgress, received: 250, total: 1000, path: "/tmp/d/big.iso"),
            download("4", "stream.bin", .inProgress, received: 300, total: nil, path: "/tmp/d/stream.bin"),
            download("5", "broken.dmg", .failed, received: 0, total: nil, path: nil),
        ]))
        XCTAssertEqual(shown(view).compactMap { ($0 as? LibraryRowView)?.accessibilityIdentifier() }, (1...5).map { "download-\($0)" })
        XCTAssertTrue(texts(view.downloads).contains("Today"))
        let report = try XCTUnwrap(row("1", in: view)), moved = try XCTUnwrap(row("2", in: view))
        let big = try XCTUnwrap(row("3", in: view)), stream = try XCTUnwrap(row("4", in: view)), broken = try XCTUnwrap(row("5", in: view))
        XCTAssertEqual(report.texts, ["report.pdf", "\(size(2048)) · files.example.com"])
        XCTAssertEqual(moved.texts, ["moved.zip", "File deleted or moved"])
        XCTAssertEqual(big.texts, ["big.iso", "\(size(250)) of \(size(1000))"])
        XCTAssertEqual(stream.texts, ["stream.bin", size(300)])
        XCTAssertEqual(broken.texts, ["broken.dmg", "Failed · files.example.com"])
        XCTAssertEqual([report, big, stream].map(\.shownProgress), [.none, .fraction(0.25), .indeterminate])
        XCTAssertEqual(report.accessoryTooltips, ["Show in Finder", "Remove from List"])
        XCTAssertEqual(big.accessoryTooltips, ["Show in Finder", "Cancel Download"])
        XCTAssertEqual(broken.accessoryTooltips, ["Remove from List"])
        XCTAssertEqual(report.contextMenu()?.items.map(\.title), ["Open", "Tidy Name with Max", "Show in Finder", "Remove from List"])
        let tidy = try XCTUnwrap(report.contextMenu()?.items.first { $0.title == "Tidy Name with Max" })
        _ = (tidy.target as? NSObject)?.perform(tidy.action!, with: tidy)
        report.click()
        moved.click()
        XCTAssertEqual(opened, [URL(fileURLWithPath: "/tmp/d/report.pdf")], "only a file still on disk opens")
        report.pressAccessory("Show in Finder")
        big.pressAccessory("Cancel Download")
        broken.pressAccessory("Remove from List")
        view.downloads.clearDownloads()
        XCTAssertEqual(sent, [.assist(.renameDownload(DownloadID("1"))), .library(.revealDownload(DownloadID("1"))), .library(.cancelDownload(DownloadID("3"))),
                              .library(.removeDownload(DownloadID("5"))), .library(.clearDownloads)])
        view.downloads.searchField.stringValue = "ISO"
        view.downloads.searchChanged()
        XCTAssertEqual(shown(view).compactMap { ($0 as? LibraryRowView)?.accessibilityIdentifier() }, ["download-3"])
        view.downloads.searchField.stringValue = "zzz"
        view.downloads.searchChanged()
        XCTAssertTrue(texts(view.downloads).contains("No results found for “zzz”"))
    }

    /// day headers: today, yesterday, a date this year, a date with its year
    func testDaysAreTodayYesterdayThenTheDate() {
        let day: Int64 = 86_400_000
        let instants = [0, 1, 4, 400].map { Instant(milliseconds: now.milliseconds - $0 * day) }
        XCTAssertEqual(LibraryDays.group(instants, at: { $0 }, now: now, calendar: utc).map(\.title),
                       ["Today", "Yesterday", "Monday, October 26", "Thursday, September 25, 2025"])
    }

    private func spacesSnapshot(_ ids: [SpaceID]) -> LibrarySnapshot {
        var snapshot = library(.spaces)
        snapshot.spaces = ids.map {
            SpaceManagerRow(id: $0, title: $0.rawValue, icon: .none, profileName: "Default", theme: resolveTheme(.default), tabCount: 0, active: $0 == ids[0])
        }
        return snapshot
    }

    private func spacesPage(_ ids: [SpaceID]) -> SpacesPageView {
        let view = SpacesPageView(dispatch: { [unowned self] in self.sent.append($0) })
        view.show(spacesSnapshot(ids), in: CGRect(x: 0, y: 0, width: 900, height: 700), scheme: .light, accent: .white)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func control(_ name: String, in root: NSView) throws -> NSView {
        try XCTUnwrap(root.descendants.first { $0.accessibilityIdentifier() == ViewID.spaceToolsControl(name).identifier }, name)
    }

    private func mouse(_ type: NSEvent.EventType, x: Double) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 100), modifierFlags: [], timestamp: 0, windowNumber: 0,
                                         context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    /// a Space card's pencil opens Arc's theme panel for that space (P32-d), not a form; its … and a right-click on
    /// the card ask the reducer for the space's card menu (P30-c: Arc's four groups) instead of building one here
    func testASpaceCardsPencilAndMenu() throws {
        let space = SpaceID("s2")
        let view = spacesPage([space])
        let edit = try XCTUnwrap(try control("manager-edit-s2", in: view) as? NSButton)
        edit.performClick(nil)
        XCTAssertEqual(sent.last, .sidebar(.openDialog(.theme(.space(space)))))
        sent = []
        let more = try XCTUnwrap(try control("manager-more-s2", in: view) as? NSButton)
        more.performClick(nil)
        guard case .sidebar(.popupMenu(.spaceCard(space), _))? = sent.last else { return XCTFail("… sent \(sent)") }
        let card = try XCTUnwrap(edit.superview)
        XCTAssertNil(card.menu(for: try mouse(.rightMouseDown, x: 0)), "no menu of the view's own")
        card.rightMouseDown(with: try mouse(.rightMouseDown, x: 40))
        XCTAssertEqual(sent.count, 2)
        guard case .sidebar(.popupMenu(.spaceCard(space), _))? = sent.last else { return XCTFail("right-click sent \(sent)") }
        XCTAssertNil(view.descendants.first { $0.accessibilityIdentifier().hasPrefix("space-tools-manager-search") }, "no search field")
        XCTAssertNotNil(view.cardHeader(space), "the icon popover's anchor")
        let shadow = try XCTUnwrap(view.descendants.first { $0 is SpaceCardShadow })
        XCTAssertEqual(shadow.frame, card.frame.insetBy(dx: -SpaceCardShadow.reach, dy: -SpaceCardShadow.reach), "the shadow reaches past the card")
        XCTAssertTrue(shadow.superview === card.superview)
        XCTAssertLessThan(try XCTUnwrap(shadow.superview?.subviews.firstIndex(of: shadow)), try XCTUnwrap(card.superview?.subviews.firstIndex(of: card)), "under the card")
        XCTAssertNil(shadow.hitTest(CGPoint(x: shadow.frame.midX, y: shadow.frame.midY)))
    }

    /// the move handle at a card's lower left reorders: the card follows the pointer while the others close up, and
    /// letting go over another slot moves the space there; a short drag leaves the order alone
    func testTheMoveHandleDragsACardToAnotherSlot() throws {
        let a = SpaceID("a"), b = SpaceID("b"), c = SpaceID("c")
        let view = spacesPage([a, b, c])
        let handle = try control("manager-move-a", in: view)
        let card = { (id: String) in try XCTUnwrap(try self.control("manager-edit-\(id)", in: view).superview) }
        let pitch = Metrics.library.spacesCardWidth.value + Metrics.library.spacesCardGap.value
        let start = try card("a").frame.minX
        XCTAssertEqual(try card("b").frame.minX, start + pitch)
        handle.mouseDown(with: try mouse(.leftMouseDown, x: 100))
        handle.mouseDragged(with: try mouse(.leftMouseDragged, x: 100 + 0.3 * pitch))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(try card("a").frame.minX, (start + 0.3 * pitch).rounded(), "the dragged card follows the pointer")
        handle.mouseUp(with: try mouse(.leftMouseUp, x: 100 + 0.3 * pitch))
        XCTAssertEqual(sent, [], "a short drag keeps the order")
        handle.mouseDown(with: try mouse(.leftMouseDown, x: 100))
        handle.mouseDragged(with: try mouse(.leftMouseDragged, x: 100 + 1.7 * pitch))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(try card("b").frame.minX, start, "b closes up into a's slot")
        XCTAssertEqual(try card("c").frame.minX, start + pitch, "c closes up into b's slot")
        handle.mouseUp(with: try mouse(.leftMouseUp, x: 100 + 1.7 * pitch))
        XCTAssertEqual(sent, [.space(.move(a, index: 2))])
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(try card("a").frame.minX, start, "until the order changes the card goes back")
    }

    /// Escape mid-drag closes the Library: the drag ends there, so a late release moves nothing, the card is back in
    /// its slot when the page shows again, and the next card's drag starts from its own slot
    func testClosingTheLibraryMidDragEndsTheDrag() throws {
        let a = SpaceID("a"), b = SpaceID("b"), c = SpaceID("c")
        let view = spacesPage([a, b, c])
        let card = { (id: String) in try XCTUnwrap(try self.control("manager-edit-\(id)", in: view).superview) }
        let pitch = Metrics.library.spacesCardWidth.value + Metrics.library.spacesCardGap.value
        let start = try card("a").frame.minX
        let dragged = try control("manager-move-a", in: view)
        dragged.mouseDown(with: try mouse(.leftMouseDown, x: 100))
        dragged.mouseDragged(with: try mouse(.leftMouseDragged, x: 100 + 0.3 * pitch))
        view.hide()
        dragged.mouseUp(with: try mouse(.leftMouseUp, x: 100 + 1.7 * pitch))
        XCTAssertEqual(sent, [])
        view.show(spacesSnapshot([a, b, c]), in: CGRect(x: 0, y: 0, width: 900, height: 700), scheme: .light, accent: .white)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(try card("a").frame.minX, start)
        let next = try control("manager-move-b", in: view)
        next.mouseDown(with: try mouse(.leftMouseDown, x: 100))
        next.mouseDragged(with: try mouse(.leftMouseDragged, x: 100 + pitch))
        next.mouseUp(with: try mouse(.leftMouseUp, x: 100 + pitch))
        XCTAssertEqual(sent, [.space(.move(b, index: 2))])
    }

    // MARK: Boosts

    /// leaving Boosts with a search typed empties the field, and coming back lists every Boost again, not the ones the
    /// old text matched
    func testBoostsComeBackUnfilteredAfterLeavingThePage() {
        let view = BoostsPageView(dispatch: { [unowned self] in self.sent.append($0) })
        var snapshot = library(.boosts)
        snapshot.boosts = [Boost(id: "a", name: "Alpha", scope: .host("alpha.example")), Boost(id: "b", name: "Beta", scope: .host("beta.example"))]
        let listed = { ["a", "b"].filter { id in view.descendants.contains { $0.accessibilityIdentifier() == ViewID.boostControl("edit-" + id).identifier } } }
        let rect = CGRect(x: 0, y: 0, width: 400, height: 700)
        view.show(snapshot, in: rect, scheme: .light)
        view.searchField.stringValue = "alpha"
        view.searchField.onChange()
        XCTAssertEqual(listed(), ["a"])
        view.hide()
        view.show(snapshot, in: rect, scheme: .light)
        XCTAssertEqual(view.searchField.stringValue, "")
        XCTAssertEqual(listed(), ["a", "b"])
    }

    // MARK: Media

    private func capture(_ id: String) -> CaptureRecord {
        let document = DocumentToken(browser: BrowserToken(page: PageID(window: WindowID("w"), item: ItemID("t")), generation: 1), sequence: 1)
        let request = CaptureRequest(id: id, document: document, context: .profile(.default), mode: .area, title: "Fixture capture",
                                     url: URL(string: "http://127.0.0.1:9/a")!, createdAt: now)
        return CaptureRecord(request: request, profile: .default, image: CaptureImage(png: Data(), width: 1200, height: 900, scale: 1))
    }

    /// The longer side in pixels of the picture a row's tile shows.
    private func tilePixels(_ row: LibraryRowView) -> Int? {
        let tile = row.descendants.compactMap { $0 as? LibraryTileView }.first
        guard let image = tile?.layer?.sublayers?.compactMap({ $0.contents as? NSImage }).first,
              let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return max(picture.width, picture.height)
    }

    /// a capture's tile is a small picture read once, off the main thread: a search keystroke, which rebuilds every row,
    /// reads no capture file again (each rebuild read every whole picture on the main thread)
    func testMediaThumbnailsAreSmallAndReadOnce() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("brk-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("c1.png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 900, bitsPerSample: 8, samplesPerPixel: 4,
                                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
        let view = MediaPageView(dispatch: { [unowned self] in self.sent.append($0) })
        var snapshot = library(.media)
        snapshot.captures = [capture("c1")]
        snapshot.captureFiles = ["c1": file]
        view.show(snapshot, in: CGRect(x: 0, y: 0, width: 400, height: 700), scheme: .light, now: now)
        var waited = 0
        while view.rows.first?.showsThumbnail != true, waited < 250 {
            try await Task.sleep(for: .milliseconds(20))
            waited += 1
        }
        let row = try XCTUnwrap(view.rows.first)
        XCTAssertLessThanOrEqual(try XCTUnwrap(tilePixels(row)), 200, "a tile-sized picture, not the 1200 x 900 capture")
        try FileManager.default.removeItem(at: file)
        view.searchField.stringValue = "fixture"
        view.searchField.onChange()
        XCTAssertEqual(view.rows.count, 1)
        XCTAssertEqual(view.rows.first?.showsThumbnail, true, "the search read no file")
    }

    /// × puts the preview away and a click on the same capture shows it again (the click changed nothing in the state,
    /// and the view kept the × to itself, so the preview stayed hidden)
    func testAClosedPreviewOpensAgainOnTheSameCapture() throws {
        let size = CGSize(width: 1280, height: 776)
        let ctx = { Context(now: self.now, newID: { UUID().uuidString }) }
        let projection = ProjectionContext(now: now, calendar: utc)
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: size), ctx: ctx()).state
        let window = project(state, projection).windows.keys.sorted()[0]
        state = reduce(state, .user(window, .library(.open(.media))), ctx()).state
        state = reduce(state, .system(.capture(.loaded(.default, [capture("c1")], [:], error: nil))), ctx()).state
        var view: LibraryView?
        func render() {
            let snapshot = project(state, projection).windows[window]!
            guard case .library(let library)? = snapshot.overlay else { return XCTFail("the Library closed") }
            view?.render(library, now: now, frames: WindowLayout.compute(snapshot, contentSize: size), palette: Palette(resolveTheme(.default)))
        }
        view = LibraryView(dispatch: { state = reduce(state, .user(window, $0), ctx()).state; render() })
        render()
        let library = try XCTUnwrap(view)
        try XCTUnwrap(library.media.rows.first).click()
        XCTAssertFalse(library.preview.isHidden)
        try XCTUnwrap(library.preview.descendants.compactMap { $0 as? NSButton }.first).performClick(nil)
        XCTAssertTrue(library.preview.isHidden)
        try XCTUnwrap(library.media.rows.first).click()
        XCTAssertFalse(library.preview.isHidden, "the same capture shows again")
    }
}
