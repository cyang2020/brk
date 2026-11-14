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

    func testInstallClickIsConsumedOnceAndFailureOrReadyCanBeActedOnAgain() throws {
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
        render()
        try click()
        XCTAssertEqual(commands, [.app(.help(.installUpdate))])
        view.sidebar.update = .failed(message: "Signature verification failed")
        render()
        XCTAssertEqual(button.accessibilityHelp(), "Signature verification failed")
        try click()
        XCTAssertEqual(commands.count, 2)
        view.sidebar.update = .ready(release)
        render()
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(commands, Array(repeating: .app(.help(.installUpdate)), count: 3))
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
            XCTAssertFalse(button.isAccessibilityEnabled())
            XCTAssertFalse(button.accessibilityPerformPress())
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
