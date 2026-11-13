import AppKit
@testable import BrkApp
import BrkBase
@testable import BrkDomain
import BrkEngine
import BrkLayout
@testable import BrkSettings
import XCTest

/// The pointer sweep and the readability check (PointerSweepTests) over the surfaces the app hosts in windows of their own:
/// a Little Arc window, every Settings pane, the site control center and the permission prompt. Each draws its surface in
/// every look (`SurfaceChecks.looks`), hence more than 2 s for some.
@MainActor
final class AppSurfaceSweepTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    /// A Little Arc window with its header, its first-run tip, the Space picker open and two download pills.
    func testALittleArcWindowTakesThePointerAndReads() throws {
        var problems: [String] = []
        for look in SurfaceChecks.macLooks {
            try SurfaceChecks.appearing(look.mac) {
                let rig = try SweepRig(look)
                defer { rig.close() }
                _ = try rig.buildSidebar()
                let before = Set(rig.state.doc.windows.keys)
                rig.run(.window(.newLittle(URL(string: "https://example.com/little"))))
                let little = try XCTUnwrap(rig.state.doc.windows.keys.first { !before.contains($0) })
                var value = try XCTUnwrap(project(rig.state, rig.projection).windows[little])
                value.tabTools.littleTip = true
                value.littleDownloads = rig.libraryItems().compactMap { item -> DownloadRow? in if case .download(let row) = item.content { row } else { nil } }
                let controller = LittleWindowController(id: little, engine: SurfaceEngine(), send: { _ in })
                defer { controller.window.close() }
                controller.render(value)
                SurfaceChecks.conceal(controller.window)
                controller.header.onChooseSpace?()
                controller.render(value)
                let content = try XCTUnwrap(controller.window.contentView)
                let c = value.theme.windowColor
                problems += SurfaceChecks.unreadable(in: content, base: NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1), "\(look) Little Arc")
                XCTAssertGreaterThanOrEqual(SurfaceChecks.sweep(content, in: controller.window), 3, "\(look) Little Arc")
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// Every Settings pane's AppKit controls in Dark. SwiftUI text and gestures are checked by Settings-Real in both
    /// appearances; this pass reaches native tracking areas SwiftUI does not expose to that scenario.
    func testEverySettingsPaneTakesThePointerAndReads() throws {
        var problems: [String] = []
        for look in SurfaceChecks.macLooks.suffix(1) {
            try SurfaceChecks.appearing(look.mac) {
                let rig = try SweepRig(look)
                defer { rig.close() }
                let host = SettingsHost(dispatch: { _ in })
                host.defaultBrowserCheck = { false }
                let window = SurfaceChecks.window(Metrics.settings.windowSize.value, style: [.titled, .closable])
                defer { window.close() }
                window.contentView = host
                var reached = 0
                for pane in SettingsPane.allCases {
                    var settings = project(rig.state, rig.projection).settings
                    settings.pane = pane
                    host.render(settings)
                    host.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.01))   // SwiftUI lays the pane out on the next turn
                    problems += SurfaceChecks.unreadable(in: host, base: window.backgroundColor, "\(look) Settings \(pane)")
                    reached += SurfaceChecks.sweep(host, in: window)
                }
                XCTAssertGreaterThan(reached, 0, "\(look) Settings")
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// The site control center on a web page, its details page, and the permission prompt, as the window's popovers. The
    /// site controls take the window theme's appearance, as the app gives it.
    func testTheSiteControlsAndThePermissionPromptTakeThePointerAndRead() throws {
        var problems: [String] = []
        for look in SurfaceChecks.macLooks {
            try SurfaceChecks.appearing(look.mac) {
                let rig = try SweepRig(look)
                defer { rig.close() }
                rig.render()
                let page = PageID(window: rig.id, item: try XCTUnwrap(rig.snapshot().content.panes.first?.tab))
                let document = DocumentToken(browser: BrowserToken(page: page, generation: 1), sequence: 1)
                let target = SiteTarget(document: document, context: .profile(.default), origin: try XCTUnwrap(SiteOrigin(URL(string: "https://example.com/")!)))
                var value = SiteControlSnapshot(context: .profile(.default), applied: nil, rulesVersion: 1, rulesError: nil, extensionsLoaded: true,
                                                extensions: [], pinnedExtensions: [], extensionError: nil, target: target, profileName: "Default",
                                                rule: SiteRule(), appearance: .automatic, clearing: false, result: nil, secure: true)
                value.ready = true
                let scheme = rig.snapshot().theme.scheme
                let panels = SitePanels()
                panels.render([rig.id: value], owner: { _ in rig.window }, scheme: { _ in scheme })
                let popover = try XCTUnwrap(panels.window(for: rig.id), "\(look): the site controls opened")
                SurfaceChecks.conceal(popover)
                let content = try XCTUnwrap(popover.contentView)
                problems += SurfaceChecks.unreadable(in: content, base: .windowBackgroundColor, "\(look) site controls")
                SurfaceChecks.sweep(content, in: popover)
                @MainActor func host(_ view: NSView) -> SiteControlsHost? { (view as? SiteControlsHost) ?? view.subviews.lazy.compactMap(host).first }
                try XCTUnwrap(host(content)).show(details: true)
                problems += SurfaceChecks.unreadable(in: content, base: .windowBackgroundColor, "\(look) site details")
                SurfaceChecks.sweep(content, in: popover)
                panels.render([:], owner: { _ in rig.window }, scheme: { _ in scheme })

                let dialogs = SiteDialogs()
                let prompt = SitePermissionPrompt(id: "prompt", target: target, requestingOrigin: target.origin, capabilities: [.camera, .microphone],
                                                  frame: nil, mask: 0)
                dialogs.permission(prompt, in: rig.window, scheme: scheme) { _, _ in }
                let shown = try XCTUnwrap(dialogs.permissionWindow(for: rig.id), "\(look): the prompt opened")
                SurfaceChecks.conceal(shown)
                let promptContent = try XCTUnwrap(shown.contentView)
                problems += SurfaceChecks.unreadable(in: promptContent, base: .windowBackgroundColor, "\(look) permission prompt")
                SurfaceChecks.sweep(promptContent, in: shown)
                dialogs.dismiss("prompt")
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }
}

/// This sweep renders window controls without loading web pages.
@MainActor
private final class SurfaceEngine: WebEngine {
    weak var delegate: (any WebEngineDelegate)?
    var pageLog: [PageLogEntry] { [] }
    func reconcile(_ pages: [PageSpec]) {}
    func surface(for page: PageID) -> PageSurfaceView? { nil }
    func perform(_ action: PageAction, on page: PageID) {}
    func focus(_ page: PageID?, in window: NSWindow) {}
    func evaluate(_ script: String, in page: PageID) {}
    func facts(for page: PageID) -> PageFacts? { nil }
    func output(_ request: OutputRequest) {}
    func cancelOutput(_ id: OutputID) {}
    func cancelDownload(_ id: DownloadID) {}
    func disposeContext(_ request: ContextDisposal) {}
    func shutdown() async -> ShutdownOutcome { .clean }
}
