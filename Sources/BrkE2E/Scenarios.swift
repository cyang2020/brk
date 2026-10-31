import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// The scenario list: the Electron plan's done predicate (1 to 9, plus the launch smoke 0), the regression scenarios
/// of electron-v1:e2e/regression.spec.ts (R2 to R10) translated to the socket, and native-only checks (N1 to N4).
/// Each body follows the steps and assertions listed for its id in docs/design/swift/module-map.md, with expected
/// values from `Metrics`.
///
/// Engines: `cefOnly` scenarios have nothing the stub can judge and are SKIPPED on it without a launch. Others run on
/// the stub; checks only Chromium can make either end the scenario as SKIPPED (`requireCEF`) or are noted next to a
/// PASS (`onCEF`), as the module map's honesty rule says.
struct Scenario: Sendable {
    let id: String
    let title: String
    let cefOnly: String?
    /// The wave-2 worker whose feature this scenario proves; while set, the scenario is SKIPPED without a launch
    /// (its body is the contract the worker makes pass, then removes the tag).
    let pending: String?
    let run: @Sendable (AppUnderTest) throws -> Void

    init(_ id: String, _ title: String, cefOnly: String? = nil, pending: String? = nil, _ run: @escaping @Sendable (AppUnderTest) throws -> Void) {
        self.id = id
        self.title = title
        self.cefOnly = cefOnly
        self.pending = pending
        self.run = run
    }
}

enum Scenarios {
    static let all: [Scenario] = [
        Scenario("F12", "repeated native Find reclaims the query after a page click", cefOnly: "native find", FindScenarios.repeatedFindFocus),
        Scenario("F11", "narrow split find controls, replacement and native clicks", cefOnly: "native find", FindScenarios.narrowPaneControls),
        Scenario("F1", "find native keys, remaps, counts and queued steps", cefOnly: "native find", FindScenarios.keysAndCounts),
        Scenario("F2", "actual selection and Jump scroll", cefOnly: "renderer selection", FindScenarios.selectionAndJump),
        Scenario("F3", "input and textarea Unicode replacements, input events and undo", cefOnly: "renderer editing", FindScenarios.controlsAndUndo),
        Scenario("F4", "contenteditable replacements preserve markup and undo", cefOnly: "renderer editing", FindScenarios.contentEditable),
        Scenario("F5", "protected, stale, cross-origin and IME refusal", cefOnly: "renderer editing", FindScenarios.refusals),
        Scenario("F6", "later find updates, DOM, subframes and main navigation", cefOnly: "native find", FindScenarios.dynamicDocuments),
        Scenario("F7", "partial edits, cancellation and timeout ambiguity", cefOnly: "renderer editing", FindScenarios.partialAndAmbiguous),
        Scenario("F10", "frame document invalidation and renderer mutation idempotence", cefOnly: "renderer editing", FindScenarios.frameLifetimeAndIdempotence),
        Scenario("F9", "stale editable elements, protected changes, persistence and native focus", cefOnly: "native find", FindScenarios.staleScopesAndFocus),
        Scenario("F8", "independent windows, Peek, split and private find", cefOnly: "native find", FindScenarios.windowsPeekAndPrivate),
        Scenario("0", "launch smoke: socket answers, one window, sidebar and one card", PlanScenarios.launchSmoke),
        Scenario("1", "launch: one page in one card, inset 10 and radius 6; corner shows the background", PlanScenarios.oneCard),
        Scenario("2", "Cmd+T opens the centered command bar; Enter on a URL adds a Today tab that loads it", PlanScenarios.newTab),
        Scenario("3", "Cmd+D moves the tab from Today to Pinned, and again back", PlanScenarios.pinToggle),
        Scenario("4", "clicking a dock space switches space: its rows show and the background changes", PlanScenarios.dockSwitch),
        Scenario("5", "Cmd+S hides the sidebar: the card fills the window with inset and radius; again restores", PlanScenarios.sidebarToggle),
        Scenario("6", "Ctrl+Shift+= makes a split: two cards side by side, gap 10, both pages live", PlanScenarios.split),
        Scenario("7", "past the threshold an idle Today tab is archived, shown in the archive, restorable", PlanScenarios.autoArchive),
        Scenario("8", "Cmd+W closes the page: OnBeforeClose logged and no surface left", PlanScenarios.closeTab),
        Scenario("9", "restart restores spaces, Pinned, Today, current tab, sidebar width; only it loads", PlanScenarios.restart),
        Scenario("R2", "sidebar hidden: peeking the left edge keeps the archive open", RegressionScenarios.peekKeepsArchive),
        Scenario("R3", "a Cmd+click link opens a background Today tab that loads", cefOnly: "a click on a link in a page",
                 RegressionScenarios.cmdClickLink),
        Scenario("R5a", "a tab left with Ctrl+Tab after 11h is not archived an hour later", RegressionScenarios.ctrlTabStamps),
        Scenario("R5b", "a tab dropped on another space after 13h is not archived by the next sweep", RegressionScenarios.moveStamps),
        Scenario("R6", "Ctrl+Tab, then Ctrl+Tab again, returns to the starting tab", RegressionScenarios.ctrlTabTwice),
        Scenario("R7a", "a page that calls window.close() leaves no blank card behind a current row", cefOnly: "window.close() in a page",
                 RegressionScenarios.pageCloses),
        Scenario("R7b", "a crashed renderer is recovered without any other input", cefOnly: "a renderer process to crash",
                 RegressionScenarios.rendererCrash),
        Scenario("R8", "a window saved off every display reopens on screen", RegressionScenarios.offscreenWindow),
        Scenario("R9", "after a space switch only the current space's surface is in the window; screen shows it", RegressionScenarios.onlyCurrentSurface),
        Scenario("R10", "a GPU process crash leaves the native sidebar working and pages repaint", cefOnly: "a GPU process to crash",
                 RegressionScenarios.gpuCrash),
        Scenario("N1", "app-priority keys never reach the page; page-priority keys do; press twice takes Cmd+S",
                 cefOnly: "page titles written by keys.html's key listener", NativeScenarios.keyPriorities),
        Scenario("N2", "focus goes to the command bar and back to the page; no CEF host window is ever key", NativeScenarios.focusRoundTrip),
        Scenario("N3", "pixel layout: title row, URL pill, favorites, rows, dock frames equal the constants", NativeScenarios.pixelLayout),
        Scenario("N4", "quit with three pages and a split exits 0 with no crash report", NativeScenarios.cleanQuit),
    ] + Wave2Scenarios.all + CompletionScenarios.all + IdentityScenarios.all + TransferScenarios.all + SplitToolsScenarios.all + SplitParentScenarios.all
}

// MARK: - Shared reading helpers

let white = [255, 255, 255, 255]
let hour = 3_600.0

/// Top-level tab rows of a section (folders and splits are not tabs).
func tabRows(_ rows: [Row]) -> [TabRow] {
    rows.compactMap { if case .tab(let t) = $0 { t } else { nil } }
}

/// Every tab the window lists: favorites, then Pinned and Today with folder children and split panes.
func allTabs(_ v: WindowSnapshot) -> [TabRow] {
    func tabs(_ rows: [Row]) -> [TabRow] {
        rows.flatMap { row -> [TabRow] in
            switch row {
            case .tab(let t): [t]
            case .folder(let f): tabs(f.children)
            case .split(let s): s.panes
            }
        }
    }
    return v.favorites.tiles + tabs(v.space.pinned.rows) + tabs(v.space.today.rows)
}

func currentTab(_ v: WindowSnapshot) -> TabRow? { allTabs(v).first { $0.status == .current } }
func todayIDs(_ v: WindowSnapshot) -> [ItemID] { v.space.today.rows.map(\.id) }
func pinnedIDs(_ v: WindowSnapshot) -> [ItemID] { v.space.pinned.rows.map(\.id) }
func tab(_ id: ItemID, in v: WindowSnapshot) -> TabRow? { allTabs(v).first { $0.id == id } }

func isCommandBar(_ overlay: OverlaySnapshot?) -> Bool { if case .commandBar? = overlay { true } else { false } }
/// The Library is open on its archive page.
func isArchive(_ overlay: OverlaySnapshot?) -> Bool { if case .library(let l)? = overlay { l.page == .archive } else { false } }

/// The visible actual view for `id`, or a Check naming what is there instead.
func visible(_ n: NativeFacts, _ id: ViewID) throws -> ActualView {
    guard let view = n.actual[id.identifier] else { throw Check(description: "native().actual has no \(id.identifier)") }
    try expect(!view.hidden, "\(id.identifier) is hidden")
    return view
}

func isShown(_ n: NativeFacts, _ id: ViewID) -> Bool { n.actual[id.identifier].map { !$0.hidden } ?? false }

func contains(_ outer: ActualView, _ inner: ActualView) -> Bool {
    outer.frame.insetBy(dx: -0.5, dy: -0.5).contains(inner.frame)
}

/// The point 40 pt below the top of a card, horizontally centred: inside the page and clear of the stub engine's
/// centred URL label and of index.html's link at (40, 40).
func cardProbe(_ card: CGRect) -> CGPoint { CGPoint(x: card.midX.rounded(.down), y: card.minY + 40) }

/// A theme that differs clearly from the default (Arc's Drab preset 9).
let drabTheme = SpaceTheme(colors: [ThemePresets.drab[8]], texture: .grain, intensity: 0.25, appearance: .auto)

/// Creates a space through the reducer (the dialog's Save) and waits until the window shows it.
@discardableResult
func createSpace(_ app: AppUnderTest, title: String) throws -> SpaceID {
    try app.dispatch(.space(.create(title: title, icon: .none, theme: drabTheme)))
    var id: SpaceID?
    try app.waitUntil("the window to switch to the new space \"\(title)\"") {
        let v = try app.view()
        id = v.space.id
        return v.space.title == title
    }
    return id!
}

/// Cmd+T, type the URL, Return: the way a user opens a tab. Returns the new Today row once it is current.
@discardableResult
func openTab(_ app: AppUnderTest, _ url: URL) throws -> TabRow {
    let before = todayIDs(try app.view())
    try app.press("cmd+t")
    try app.waitUntil("Cmd+T to open the command bar") { isCommandBar(try app.view().overlay) }
    try app.waitUntil("the command bar input to take focus") {
        let n = try app.native()
        try expect(n.firstResponder.hasSuffix(":" + ViewID.commandBarInput.identifier), "first responder is \(n.firstResponder)")
        return true
    }
    try app.type(url.absoluteString)
    try app.press("return")
    var row: TabRow?
    try app.waitUntil("a new Today row for \(url.absoluteString)") {
        let v = try app.view()
        row = tabRows(v.space.today.rows).first { !before.contains($0.id) }
        try expect(row != nil, "Today is \(todayIDs(v).count) rows, was \(before.count)")
        return true
    }
    try expect(row!.status == .current, "the new row \(row!.id) has status \(row!.status), expected current")
    return row!
}

/// Waits until the tab's title is `title` (page-reported titles exist only on the CEF engine).
func waitForTitle(_ app: AppUnderTest, _ id: ItemID, _ title: String, timeout: Double = 8) throws {
    try app.waitUntil("tab \(id) to be titled \"\(title)\"", timeout: timeout) {
        let current = tab(id, in: try app.view())?.title
        try expect(current == title, "title is \(current.map { "\"\($0)\"" } ?? "absent")")
        return true
    }
}

/// Samples a pixel until two samples 150 ms apart agree within 2 (a crossfade has finished).
func settledPixel(_ app: AppUnderTest, _ point: CGPoint, timeout: Double = 5) throws -> [Int] {
    var last = try app.pixel(point)
    let deadline = uptime() + timeout
    while uptime() < deadline {
        app.sleep(0.15)
        let next = try app.pixel(point)
        if distance(last, next) <= 2 { return next }
        last = next
    }
    throw Check(description: "the pixel at \(point) kept changing for \(timeout) s")
}
