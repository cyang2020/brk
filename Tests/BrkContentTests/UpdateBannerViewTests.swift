import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
@testable import BrkSidebar
import BrkUIKit
import XCTest

@MainActor
final class UpdateBannerViewTests: XCTestCase {
    private let size = CGSize(width: 1280, height: 776)
    private let now = Instant(milliseconds: 1_790_000_000_000)
    private let release = UpdateRelease(version: "0.0.1", build: 44)

    private func snapshot() -> WindowSnapshot {
        let ids = IDs()
        let state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: size),
                                       ctx: Context(now: now, newID: ids.next)).state
        return project(state, ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))).windows.values.first!
    }

    func testCardOpensBeforeInstallAndAnExplicitInstallIsConsumedOnce() throws {
        _ = NSApplication.shared
        var commands: [Command] = []
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = WindowRootView(dispatch: { commands.append($0) })
        window.contentView = root
        var view = snapshot()
        view.sidebar.update = .available(release)
        func render() {
            root.render(view, frames: WindowLayout.compute(view, contentSize: size), surface: { _ in nil })
        }
        render()
        let button = root.sidebar.updateBanner
        func primary(_ title: String) throws -> NSButton {
            try XCTUnwrap(button.subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }.first { $0.title == title })
        }
        func click(inside: Bool = true) throws {
            let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: inside ? point : CGPoint(x: size.width, y: size.height), modifierFlags: [], timestamp: 0,
                                                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
            button.mouseDown(with: down)
            button.mouseUp(with: up)
        }
        try click(inside: false)
        XCTAssertTrue(commands.isEmpty)
        try click()
        XCTAssertTrue(button.expanded)
        XCTAssertTrue(commands.isEmpty, "opening the card must not start an update")
        try primary("Restart and Update").performClick(nil)
        render()
        try primary("Restart and Update").performClick(nil)
        XCTAssertEqual(commands, [.app(.help(.installUpdate))])
        view.sidebar.update = .failed(message: "Signature verification failed")
        render()
        XCTAssertEqual(button.accessibilityHelp(), "Signature verification failed")
        try primary("Try Again").performClick(nil)
        XCTAssertEqual(commands.count, 2)
        view.sidebar.update = .ready(release)
        render()
        XCTAssertTrue(button.accessibilityPerformPress())
        try primary("Restart and Update").performClick(nil)
        XCTAssertEqual(commands, Array(repeating: .app(.help(.installUpdate)), count: 3))
        view.sidebar.update = .updated(release)
        render()
        try primary("See What’s New").performClick(nil)
        XCTAssertEqual(commands.last, .app(.help(.updateReleaseNotes)))
    }

    /// Arc: a pointer resting 0.3 s on the pill opens the card upward from the pill; the list then ends at the card's top
    /// (rows stay put); leaving closes it at once and gives the list its height back. A pointer passing over opens nothing.
    /// About 2.3 s: a real window (1.2 s, as the other tests here) and Arc's 0.3 s hover delay waited out twice.
    func testRestingPointerOpensTheCardOverTheListAndLeavingClosesIt() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = WindowRootView(dispatch: { _ in })
        window.contentView = root
        var view = snapshot()
        view.sidebar.update = .available(release)
        root.render(view, frames: WindowLayout.compute(view, contentSize: size), surface: { _ in nil })
        let banner = root.sidebar.updateBanner, list = root.sidebar.tablist
        banner.reduceMotion = { true }
        let pill = banner.frame, restList = list.convert(list.bounds, to: root.sidebar)
        // The banner does not clip (the card's shadow reaches past it), so a visible-rect area would be the whole window.
        func trackedRegions() -> [CGRect] {
            banner.updateTrackingAreas()
            return banner.trackingAreas.filter { $0.owner === banner }.map { $0.options.contains(.inVisibleRect) ? banner.visibleRect : $0.rect }
        }
        XCTAssertEqual(trackedRegions(), [banner.bounds], "the pointer is on the pill only inside it")
        XCTAssertEqual(restList.maxY, pill.minY, accuracy: 0.5, "at rest the list ends at the pill's top (Arc pads the pill only on the sides and below)")
        func pointer(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: banner.convert(CGPoint(x: banner.bounds.midX, y: banner.bounds.midY), to: nil),
                                                 modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                 eventNumber: 0, trackingNumber: 0, userData: nil))
        }
        // XCTest's wait keeps the run loop turning for the whole time (a bare run(until:) returns at once when nothing
        // is scheduled), so the hover delay's task and the sidebar's deferred layout get to run.
        func spin(_ seconds: Double) {
            let elapsed = expectation(description: "\(seconds) s")
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { elapsed.fulfill() }
            wait(for: [elapsed], timeout: seconds + 2)
        }
        /// Turns the run loop until `done` holds (the hover delay's task and the sidebar's deferred layout run late on a busy Mac).
        func spin(until done: () -> Bool) {
            for _ in 0..<60 where !done() { spin(0.05) }
        }
        banner.mouseEntered(with: try pointer(.mouseEntered))
        spin(0.1)
        banner.mouseExited(with: try pointer(.mouseExited))
        spin(0.25)
        XCTAssertFalse(banner.expanded, "a pointer passing over the pill does not open it")
        banner.mouseEntered(with: try pointer(.mouseEntered))
        XCTAssertFalse(banner.expanded)
        spin { banner.expanded && list.convert(list.bounds, to: root.sidebar).maxY < pill.minY }
        XCTAssertTrue(banner.expanded)
        let card = banner.frame, openList = list.convert(list.bounds, to: root.sidebar)
        XCTAssertEqual(card.height, UpdateBannerView.openHeight(for: .available(release)))
        XCTAssertEqual(card.maxY, pill.maxY)
        XCTAssertEqual(openList.maxY, card.minY, accuracy: 0.5, "the open card takes its height from the list")
        XCTAssertEqual(openList.minY, restList.minY, accuracy: 0.5, "rows stay where they were")
        XCTAssertEqual(trackedRegions(), [banner.bounds], "the open card is hovered over its whole height, not beyond")
        banner.mouseExited(with: try pointer(.mouseExited))
        XCTAssertFalse(banner.expanded, "leaving closes the card at once")
        spin { list.convert(list.bounds, to: root.sidebar).maxY >= pill.minY - 0.5 }
        XCTAssertEqual(banner.frame, pill)
        XCTAssertEqual(list.convert(list.bounds, to: root.sidebar).maxY, restList.maxY, accuracy: 0.5)
    }

    func testProgressInvalidatesTheSidebarAndBusyStatesCannotStartAnotherInstall() {
        _ = NSApplication.shared
        var commands: [Command] = []
        let root = WindowRootView(dispatch: { commands.append($0) })
        root.frame = CGRect(origin: .zero, size: size)
        var view = snapshot()
        let states: [UpdatePresentation] = [.checking, .downloading(release, fraction: 0.2), .downloading(release, fraction: 0.75),
                                            .preparing(release), .installing(release)]
        var progressLabels: [String] = []
        for state in states {
            view.sidebar.update = state
            root.render(view, frames: WindowLayout.compute(view, contentSize: size), surface: { _ in nil })
            let button = root.sidebar.updateBanner
            XCTAssertFalse(button.isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(button.accessibilityPerformPress(), "progress remains inspectable")
            let action = button.subviews.flatMap(\.subviews).compactMap { $0 as? UpdateActionButton }.first
            XCTAssertEqual(action?.isEnabled, false)
            if case .downloading = state { progressLabels.append(button.accessibilityLabel() ?? "") }
        }
        XCTAssertTrue(progressLabels[0].contains("20%"))
        XCTAssertTrue(progressLabels[1].contains("75%"))
        XCTAssertTrue(commands.isEmpty)
        view.sidebar.update = nil
        root.render(view, frames: WindowLayout.compute(view, contentSize: size), surface: { _ in nil })
        XCTAssertTrue(root.sidebar.updateBanner.isHidden)
        XCTAssertFalse(root.sidebar.updateBanner.accessibilityPerformPress())
    }

    func testLastTabScrollsFullyAboveThePillAndNeighborUsesTheSameReservation() throws {
        _ = NSApplication.shared
        let ids = IDs()
        let ctx = Context(now: now, newID: ids.next)
        let projection = ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian), softwareUpdate: .available(release))
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: size), ctx: ctx).state
        let id = try XCTUnwrap(project(state, projection).windows.keys.first)
        for index in 0..<24 {
            state = reduce(state, .user(id, .commandBar(.open(.newTab))), ctx).state
            state = reduce(state, .user(id, .commandBar(.submit("http://127.0.0.1:9/\(index)"))), ctx).state
        }
        var view = try XCTUnwrap(project(state, projection).windows[id])
        view.sidebar.width = 164
        view.sidebar.visible = false
        view.sidebar.peek = true
        let frames = WindowLayout.compute(view, contentSize: size)
        let sidebar = try XCTUnwrap(frames.sidebar)
        let banner = try XCTUnwrap(sidebar.updateBanner)
        let root = WindowRootView(dispatch: { _ in })
        root.frame = CGRect(origin: .zero, size: size)
        root.render(view, frames: frames, surface: { _ in nil })
        let list = root.sidebar.tablist
        let document = try XCTUnwrap(list.documentView)
        list.contentView.scroll(to: CGPoint(x: 0, y: document.bounds.height - list.contentView.bounds.height))
        list.reflectScrolledClipView(list.contentView)
        let last = try XCTUnwrap(sidebar.rows.last { if case .item = $0.kind { true } else { false } })
        XCTAssertTrue(list.documentVisibleRect.contains(last.rect), "the last tab must remain fully scrollable into view")
        let visibleLast = document.convert(last.rect, to: root)
        XCTAssertLessThanOrEqual(visibleLast.maxY, banner.minY)
        let neighbor = SpaceSidePageView(frame: CGRect(origin: .zero, size: sidebar.frame.size))
        neighbor.render(SpacePage(space: view.space, favorites: view.favorites, theme: view.theme), sharesFavorites: false,
                        column: sidebar.frame, snapshot: view, now: now)
        let neighborList = try XCTUnwrap(neighbor.subviews.compactMap { $0 as? TablistView }.first)
        XCTAssertEqual(neighborList.frame, list.frame)
    }
}
