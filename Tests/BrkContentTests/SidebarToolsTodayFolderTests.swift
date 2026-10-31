import AppKit
import BrkBase
import BrkContent
import BrkDomain
import BrkLayout
import QuartzCore
import XCTest

extension WindowRootViewTests {
    /// Tidy Tabs admits folders in Today after integration. Exercise that projection without changing Placement here.
    func testTodayFolderRendersItsChildIconHoverMetadataGlowAndSadTab() throws {
        let ids = IDs()
        let ctx = Context(now: now, newID: ids.next)
        let projection = ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "https://fixture.invalid/child"), contentSize: Self.size), ctx: ctx).state
        var view = try XCTUnwrap(project(state, projection).windows.values.first)
        let window = view.id, child = try XCTUnwrap(view.space.today.rows.first?.id)
        state = reduce(state, .user(window, .item(.newFolder)), ctx).state
        let folderID = try XCTUnwrap(project(state, projection).windows[window]?.space.pinned.rows.first?.id)
        state = reduce(state, .user(window, .item(.rename(folderID, title: "Topic"))), ctx).state
        state = reduce(state, .user(window, .item(.move(child, to: .into(parent: folderID, index: 0)))), ctx).state
        state = reduce(state, .user(window, .item(.setIcon(folderID, .emoji("📚")))), ctx).state
        view = try XCTUnwrap(project(state, projection).windows[window])
        guard case .folder(var folder)? = view.space.pinned.rows.first,
              case .tab(var tab)? = folder.children.first else { return XCTFail("missing folder child") }
        folder.section = .today
        tab.section = .today
        tab.loading = true
        folder.children = [.tab(tab)]
        view.space.pinned.rows = []
        view.space.today.rows = [.folder(folder)]
        view.renaming = nil
        view.urlPill.loading = true
        view.urlPill.loadProgress = 0.4
        let page = PageID(window: window, item: child)
        XCTAssertFalse(view.content.panes.isEmpty)
        let (_, root, frames) = render(view)
        root.layoutSubtreeIfNeeded()
        var identified: [String: NSView] = [:]
        var labels: [String] = []
        func walk(_ node: NSView) {
            let id = node.accessibilityIdentifier()
            if !id.isEmpty, identified[id] == nil || (identified[id]!.isHiddenOrHasHiddenAncestor && !node.isHiddenOrHasHiddenAncestor) { identified[id] = node }
            if let field = node as? NSTextField { labels.append(field.stringValue) }
            node.subviews.forEach(walk)
        }
        walk(root)
        XCTAssertFalse(try XCTUnwrap(identified[ViewID.row(folderID).identifier]).isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(try XCTUnwrap(identified[ViewID.row(child).identifier]).isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(labels.contains("Topic"))
        XCTAssertTrue(labels.contains("📚"), "Today folder must render its custom icon")
        XCTAssertEqual(Row.folder(folder).hoverPreviewText, "Topic\n1 items")
        XCTAssertTrue(frames.sidebar?.rows.contains { $0.kind == .item(folderID) } == true)
        XCTAssertTrue(frames.sidebar?.rows.contains { $0.kind == .item(child) } == true)
        let glow = try XCTUnwrap(identified[ViewID.urlPill.identifier]?.layer?.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
        XCTAssertFalse(glow.isHidden)
        XCTAssertGreaterThan(glow.bounds.width, 0)
        view.urlPill.loading = false
        view.urlPill.loadProgress = 0
        view.content.panes[0].content = .crashed(page)
        root.render(view, frames: WindowLayout.compute(view, contentSize: Self.size), surface: { _ in nil })
        XCTAssertTrue(glow.isHidden)
        walk(root)
        XCTAssertFalse(try XCTUnwrap(identified["sad-tab"]).isHiddenOrHasHiddenAncestor)
        XCTAssertNotNil(identified["sad-tab-reload"])
    }
}
