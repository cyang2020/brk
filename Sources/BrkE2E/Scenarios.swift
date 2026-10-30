import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// The scenario list: the Electron plan's done predicate (1 to 9, plus the launch smoke 0), the regression scenarios
/// of electron-v1:e2e/regression.spec.ts (R2 to R10) translated to the socket, and native-only checks (N1 to N4).
/// Each body follows the steps and assertions listed for its id in docs/design/swift/module-map.md.
struct Scenario: Sendable {
    let id: String
    let title: String
    let run: @Sendable (AppUnderTest) throws -> Void
}

enum Scenarios {
    static let all: [Scenario] = [
        Scenario(id: "0", title: "launch smoke: socket answers, one window, sidebar and one card", run: todo),
        Scenario(id: "1", title: "launch: one page in one card, inset 10 and radius 6; corner shows the background", run: todo),
        Scenario(id: "2", title: "Cmd+T opens the centered command bar; Enter on a URL adds a Today tab that loads it", run: todo),
        Scenario(id: "3", title: "Cmd+D moves the tab from Today to Pinned, and again back", run: todo),
        Scenario(id: "4", title: "clicking a dock space switches space: its rows show and the background changes", run: todo),
        Scenario(id: "5", title: "Cmd+S hides the sidebar: the card fills the window with inset and radius; again restores", run: todo),
        Scenario(id: "6", title: "Ctrl+Shift+= makes a split: two cards side by side, gap 10, both pages live", run: todo),
        Scenario(id: "7", title: "past the threshold an idle Today tab is archived, shown in the archive, restorable", run: todo),
        Scenario(id: "8", title: "Cmd+W closes the page: OnBeforeClose logged and no surface left", run: todo),
        Scenario(id: "9", title: "restart restores spaces, Pinned, Today, current tab, sidebar width; only it loads", run: todo),
        Scenario(id: "R2", title: "sidebar hidden: peeking the left edge keeps the archive open", run: todo),
        Scenario(id: "R3", title: "a Cmd+click link opens a background Today tab that loads", run: todo),
        Scenario(id: "R5a", title: "a tab left with Ctrl+Tab after 11h is not archived an hour later", run: todo),
        Scenario(id: "R5b", title: "a tab dropped on another space after 13h is not archived by the next sweep", run: todo),
        Scenario(id: "R6", title: "Ctrl+Tab, then Ctrl+Tab again, returns to the starting tab", run: todo),
        Scenario(id: "R7a", title: "a page that calls window.close() leaves no blank card behind a current row", run: todo),
        Scenario(id: "R7b", title: "a crashed renderer is recovered without any other input", run: todo),
        Scenario(id: "R8", title: "a window saved off every display reopens on screen", run: todo),
        Scenario(id: "R9", title: "after a space switch only the current space's surface is in the window; screen shows it", run: todo),
        Scenario(id: "R10", title: "a GPU process crash leaves the native sidebar working and pages repaint", run: todo),
        Scenario(id: "N1", title: "app-priority keys never reach the page; page-priority keys do; press twice takes Cmd+S", run: todo),
        Scenario(id: "N2", title: "focus goes to the command bar and back to the page; no CEF host window is ever key", run: todo),
        Scenario(id: "N3", title: "pixel layout: title row, URL pill, favorites, rows, dock frames equal the constants", run: todo),
        Scenario(id: "N4", title: "quit with three pages and a split exits 0 with no crash report", run: todo),
    ]

    /// Marks a scenario not yet written; the report lists it as SKIPPED.
    static func todo(_ app: AppUnderTest) throws { throw Skipped() }
}

struct Skipped: Error {}
