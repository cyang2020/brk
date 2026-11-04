import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Round 4, R4-13: the text layout check (`ControlOp.textLayout`) over every main surface. Each surface's report goes to
/// `logs/TextLayout-<surface>.json`; a surface that does not open is a failure of its own, and the others still run, so
/// one run lists every cut text at once.
enum TextLayoutScenarios {
    static let all = [
        Scenario("TextLayout", "no text is cut on the main window at 228 and 164, blank window, Little Arc, Peek, splits, command bar, switcher, Settings and its sheets, Library, theme and Boost editors, site controls, find, menus, toasts and dialogs", cefOnly: "page surfaces and native panels", sweep),
    ]

    private typealias S = SidebarReviewScenarios
    private typealias E = SidebarEvidenceScenarios

    private static let longTitle = "Long title for truncation and readable sidebar ellipsis"
    private static let longSpace = "Research and Development Notes"

    private final class Sweep {
        let app: AppUnderTest
        private(set) var cut: [String] = []
        private(set) var unopened: [String] = []
        private var seen = Set<String>()
        private var inspected = 0
        private var summary: [[String: String]] = []
        init(_ app: AppUnderTest) { self.app = app }

        private var logs: URL { app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs") }

        func record(_ name: String, _ report: TextLayoutReport) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            if let data = try? encoder.encode(report) { try? data.write(to: logs.appendingPathComponent("TextLayout-\(name).json")) }
            inspected += report.inspected
            summary.append(["surface": name, "inspected": String(report.inspected), "cut": String(report.findings.count), "ellipsized": String(report.truncated.count)])
            for finding in report.findings {
                let line = "\(finding.problem.rawValue) \"\(finding.text)\" \(finding.view) frame \(Int(finding.frame.width))x\(Int(finding.frame.height)) needs \(Int(ceil(finding.needed.width)))x\(Int(ceil(finding.needed.height)))"
                    + (finding.clipper.map { " clipped by \($0)" } ?? "")
                if seen.insert(line).inserted { cut.append("\(name): \(line)") }
            }
            print("[textlayout] \(name): \(report.inspected) texts, \(report.findings.count) cut, \(report.truncated.count) ellipsized")
        }

        func measure(_ name: String, shot: Bool = true) throws {
            try? app.settle(timeout: 4)
            app.sleep(0.3)
            guard case .textLayout(let report) = try app.send(.textLayout) else { throw Check(description: "textLayout did not answer") }
            record(name, report)
            if shot { _ = try? app.screenshot(name) }
        }

        func measureMenu(_ name: String, at point: CGPoint) {
            do {
                guard case .textLayout(let report) = try app.send(.textLayoutMenu(window: app.window, point: point)) else { throw Check(description: "textLayoutMenu did not answer") }
                record("menu-" + name, report)
            } catch { unopened.append("menu-\(name): \(error)") }
            app.sleep(0.2)
        }

        /// Opens a surface, measures it, closes it. A surface that fails to open is listed and the sweep goes on.
        func surface(_ name: String, close: (() throws -> Void)? = nil, _ open: () throws -> Void) throws {
            do {
                try open()
                try measure(name)
            } catch let error as AppDied {
                throw error
            } catch {
                unopened.append("\(name): \(error)")
            }
            if let close {
                do { try close() } catch let error as AppDied { throw error } catch { unopened.append("\(name) (closing): \(error)") }
            }
        }

        func finish() throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            if let data = try? encoder.encode(summary) { try? data.write(to: logs.appendingPathComponent("TextLayout-summary.json")) }
            try? cut.joined(separator: "\n").appending("\n").write(to: logs.appendingPathComponent("TextLayout-cut.txt"), atomically: true, encoding: .utf8)
            app.note("\(inspected) texts measured on \(summary.count) surfaces")
            try expect(unopened.isEmpty, "surfaces that did not open: \(unopened.joined(separator: " | "))")
            try expect(cut.isEmpty, "\(cut.count) cut texts: \(cut.prefix(60).joined(separator: " | "))")
        }
    }

    private static func rowFrame(_ app: AppUnderTest, _ id: ItemID) throws -> CGRect {
        try visible(app.native(), .row(id)).frame
    }
    private static func centre(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    @Sendable static func sweep(_ app: AppUnderTest) throws {
        let sweep = Sweep(app)
        let standard = app.window!
        _ = try app.send(.activateApp(window: standard))

        // The sidebar's content: a long title in Today and Pinned, a folder with a long name, Favorites, a space with a
        // long name, an archived tab, a download and an Easel, so no page shows only its empty state.
        let firstSpace = try app.view().space.id
        let longTab = try app.load(app.site.url("page2.html?long=1"))
        try app.evaluate(PageID(window: standard, item: longTab), "document.title=\(jsString(longTitle))")
        try waitForTitle(app, longTab, longTitle)
        let second = try app.load(app.site.url("index.html?today=2"))
        let pinnedTab = try app.load(app.site.url("page2.html?pinned=1"))
        try app.dispatch(.item(.move(pinnedTab, to: .into(parent: try app.view().space.pinned.root, index: 0))))
        let folderChild = try app.load(app.site.url("index.html?folder=1"))
        let folder = try E.newFolder(app, "Reading list with a rather long name")
        try app.dispatch(.item(.move(folderChild, to: .into(parent: folder, index: 0))))
        let favorite = try app.load(app.site.url("index.html?favorite=1"))
        try app.dispatch(.item(.move(favorite, to: .into(parent: try app.view().favorites.root, index: 0))))
        let archived = try app.load(app.site.url("page2.html?archived=1"))
        try app.settle()
        try app.dispatch(.tab(.archive(.item(archived))))
        let otherSpace = try createSpace(app, title: longSpace)
        try app.dispatch(.space(.focus(firstSpace)))
        try app.waitUntil("the first space again") { try app.view().space.id == firstSpace }
        try app.dispatch(.tab(.focus(longTab)))
        try app.settle()

        // MARK: Main window
        for (width, toolbar) in [(228.0, false), (164.0, false), (228.0, true), (164.0, true), (500.0, false)] {
            try sweep.surface("main-\(Int(width))\(toolbar ? "-toolbar" : "")", close: {
                if toolbar { try app.dispatch(.sidebar(.toggleToolbar)) }
                try app.dispatch(.sidebar(.resize(width: 228)))
            }) {
                try app.dispatch(.sidebar(.resize(width: width)))
                if toolbar { try app.dispatch(.sidebar(.toggleToolbar)) }
            }
        }
        for width in [228.0, 164.0] {
            try sweep.surface("favorites-empty-\(Int(width))", close: {
                try app.dispatch(.item(.move(favorite, to: .into(parent: try app.view().favorites.root, index: 0))))
                try app.dispatch(.sidebar(.resize(width: 228)))
            }) {
                try app.dispatch(.sidebar(.resize(width: width)))
                try app.dispatch(.item(.move(favorite, to: .into(parent: try app.view().space.pinned.root, index: 0))))
                try app.waitUntil("Favorites emptied") { try app.view().favorites.tiles.isEmpty }
            }
        }
        try sweep.surface("sidebar-floating", close: {
            try app.dispatch(.sidebar(.peek(false)))
            try app.dispatch(.sidebar(.toggle))
        }) {
            try app.dispatch(.sidebar(.toggle))
            try app.waitUntil("sidebar hidden") { try !app.view().sidebar.visible }
            try app.dispatch(.sidebar(.peek(true)))
        }
        try sweep.surface("pinned-collapsed", close: { try app.dispatch(.space(.togglePinnedSection(.current))) }) {
            try app.dispatch(.space(.togglePinnedSection(.current)))
        }

        // MARK: Other windows
        try sweep.surface("window-blank", close: {
            try app.dispatch(.window(.close))
            app.window = standard
            _ = try app.send(.activateApp(window: standard))
        }) {
            let blank = try S.newWindow(app, "a blank window", kind: .blank) { try app.dispatch(.window(.newBlank)) }
            app.window = blank
            _ = try app.send(.activateApp(window: blank))
        }
        try sweep.surface("window-little-bar", close: {
            try app.dispatch(.commandBar(.submit(app.site.url("page2.html?little=1").absoluteString)))
            try sweep.measure("window-little-page")
            try app.dispatch(.window(.close))
            app.window = standard
            _ = try app.send(.activateApp(window: standard))
        }) {
            let little = try S.newWindow(app, "Little Arc", kind: .little) { try app.dispatch(.window(.newLittle(nil))) }
            app.window = little
            _ = try app.send(.activate(window: little))
        }
        try sweep.surface("peek", close: {
            try app.dispatch(.peek(.close))
            try app.waitUntil("Peek closed") { try app.view().overlay == nil }
        }) {
            try app.dispatch(.peek(.open(app.site.url("page2.html?peek=1"))))
            try app.waitUntil("a Peek") { if case .peek(let p)? = try app.view().overlay { return p.page != nil }; return false }
        }

        // MARK: Splits
        try sweep.surface("split-horizontal") {
            try app.dispatch(.tab(.focus(second)))
            try app.dispatch(.split(.addPane))
            try app.dispatch(.commandBar(.submit(app.site.url("page2.html?split=right").absoluteString)))
            try app.waitUntil("a split") { try app.view().content.split != nil }
        }
        try sweep.surface("split-vertical", close: { try app.dispatch(.split(.orientCurrent(.horizontal))) }) {
            try app.dispatch(.split(.orientCurrent(.vertical)))
        }
        try sweep.surface("split-four", close: {
            try app.dispatch(.split(.separateAll))
            try app.waitUntil("no split") { try app.view().content.split == nil }
        }) {
            for n in 3...4 {
                try app.dispatch(.split(.addPane))
                try app.dispatch(.commandBar(.submit(app.site.url("index.html?split=\(n)").absoluteString)))
            }
            try app.waitUntil("four panes") { try app.view().content.panes.count == 4 }
        }
        try app.dispatch(.tab(.focus(longTab)))

        // MARK: Command bar and switcher
        try sweep.surface("bar-newtab", close: { try app.dispatch(.commandBar(.dismiss)) }) {
            try app.press("cmd+t")
            try app.waitUntil("the command bar") { isCommandBar(try app.view().overlay) }
            try sweep.measure("bar-newtab-empty")
            try app.type("page")
            app.sleep(0.5)
            try sweep.measure("bar-newtab-page")
            try app.press("cmd+a")
            try app.type("Long title")
            app.sleep(0.5)
            try sweep.measure("bar-newtab-tab")
            try app.press("cmd+a")
            try app.type("a typed question that is much longer than the command bar is wide so the input has to scroll and the search row has to end somehow")
            app.sleep(0.5)
        }
        try sweep.surface("bar-edit", close: { try app.dispatch(.commandBar(.dismiss)) }) {
            try app.dispatch(.commandBar(.open(.editCurrent)))
            try app.waitUntil("the command bar") { isCommandBar(try app.view().overlay) }
        }
        try sweep.surface("switcher", close: { try app.press("escape") }) {
            try app.dispatch(.tab(.cycleRecent(.next)))
        }
        try app.dispatch(.tab(.focus(longTab)))

        // MARK: Settings
        for pane in SettingsPane.allCases {
            try sweep.surface("settings-\(pane.rawValue)") {
                guard case .dispatched = try app.send(.openSettings(pane: pane)) else { throw Check(description: "openSettings did not dispatch") }
                try app.waitUntil("the \(pane.rawValue) pane") {
                    guard case .settings(let s) = try app.send(.settings) else { return false }
                    return s.pane == pane
                }
            }
        }
        func sheetShown() throws -> Bool { try app.native().appWindows.contains { $0.isVisible && $0.className.contains("SheetPresentation") } }
        try sweep.surface("settings-air-traffic-control", close: {
            try app.click(.settingsField("routes-close"))
            try app.waitUntil("the sheet closed") { try !sheetShown() }
        }) {
            guard case .dispatched = try app.send(.openSettings(pane: .links)) else { throw Check(description: "openSettings did not dispatch") }
            try app.settle()
            try app.click(.settingsField("airTrafficControl"))
            try app.waitUntil("Air Traffic Control") { try sheetShown() }
            try app.click(.settingsField("route-new"))
        }
        try sweep.surface("settings-previews", close: {
            try app.click(.settingsField("previewsDone"))
            try app.waitUntil("the sheet closed") { try !sheetShown() }
        }) {
            guard case .dispatched = try app.send(.openSettings(pane: .general)) else { throw Check(description: "openSettings did not dispatch") }
            try app.settle()
            try app.click(.settingsField("previewsSettings"))
            try app.waitUntil("Previews Settings") { try sheetShown() }
        }
        try app.dispatch(.settings(.closeWindow))
        _ = try app.send(.activateApp(window: standard))

        // MARK: Library
        let download = app.site.url("download")
        _ = try? app.load(download)
        try app.settle()
        for page in LibraryPage.allCases {
            try sweep.surface("library-\(page.rawValue)") {
                try app.dispatch(.library(.open(page)))
                try app.waitUntil("the \(page.rawValue) page") {
                    if case .library(let l)? = try app.view().overlay { return l.page == page }
                    return false
                }
            }
        }
        try app.dispatch(.library(.close))
        try sweep.surface("history", close: { try app.dispatch(.tab(.focus(longTab))) }) {
            try app.dispatch(.library(.openHistory))
            try app.waitUntil("the History page") { try app.view().history != nil }
        }

        // MARK: Dialogs and the space's panels
        try sweep.surface("theme-editor", close: { try app.dispatch(.sidebar(.openDialog(nil))) }) {
            try app.dispatch(.sidebar(.openDialog(.theme(.current))))
        }
        try sweep.surface("space-icon", close: { try app.dispatch(.sidebar(.openDialog(nil))) }) {
            try app.dispatch(.sidebar(.openDialog(.icon(.current))))
        }
        try sweep.surface("space-rename", close: { try app.dispatch(.sidebar(.openDialog(nil))) }) {
            try app.dispatch(.sidebar(.openDialog(.rename(.current))))
        }
        try sweep.surface("space-new", close: { try app.dispatch(.sidebar(.openDialog(nil))) }) {
            try app.dispatch(.sidebar(.openDialog(.newSpace)))
        }
        try sweep.surface("dialog-delete-space", close: { try app.press("escape") }) {
            try app.dispatch(.space(.requestDelete(otherSpace)))
            try app.waitUntil("the delete dialog") { try isShown(app.native(), .spaceDialog) }
        }
        try app.dispatch(.easel(.create))
        try app.settle()
        guard let easelRow = tabRows(try app.view().space.pinned.rows).last(where: { $0.url?.absoluteString.hasPrefix("brk://easel/") == true }),
              let easel = easelRow.url.map({ EaselID($0.lastPathComponent) }) else { throw Check(description: "no Easel row") }
        try sweep.measure("easel-board")
        try sweep.surface("dialog-delete-easel", close: {
            try app.click(.spaceToolsControl("alert-cancel"))
            try app.waitUntil("Cancel closes the confirmation") { try app.view().pendingEaselDeletion == nil }
        }) {
            try app.dispatch(.tab(.focus(longTab)))
            try app.dispatch(.easel(.requestDelete(easel)))
            try app.waitUntil("Delete asks first") { try app.view().pendingEaselDeletion?.id == easel }
        }
        try sweep.surface("dialog-quit", close: {
            try app.click(.settingsField("quitWarning-cancel"))
            try app.waitUntil("Cancel closes the dialog") { try !app.native().appWindows.contains { $0.isVisible && $0.className.contains("Alert") } }
            try app.dispatch(.settings(.general(.warnBeforeQuitting(false))))
        }) {
            try app.dispatch(.settings(.general(.warnBeforeQuitting(true))))
            try app.press("cmd+q")
            try app.waitUntil("the Warn before quitting dialog", timeout: 10) { try app.native().appWindows.contains { $0.isVisible && $0.className.contains("Alert") } }
        }

        // MARK: Boost editor
        try sweep.surface("boost-intro") {
            try app.dispatch(.boost(.create))
            try app.waitUntil("Boost intro card") { try app.view().boostEditor?.page == .intro }
            try app.waitUntil("Boost panel window on screen") { try app.native().appWindows.contains { $0.className.hasSuffix("BoostPanelWindow") && $0.isVisible } }
            app.sleep(0.3)
        }
        try sweep.surface("boost-style") {
            try app.click(.boostControl("start"))
            try app.waitUntil("Boost editor page") { try app.view().boostEditor?.page == .style }
        }
        try sweep.surface("boost-menu", close: { try app.press("escape") }) {
            try app.click(.boostControl("menu"))
        }
        try sweep.surface("boost-code", close: {
            try app.click(.boostControl("close"))
            try app.waitUntil("the Boost closed") { try app.view().boostEditor == nil }
        }) {
            app.sleep(0.4)
            try app.click(.boostControl("code"))
            try app.waitUntil("Boost Code page") { try app.view().boostEditor?.page == .css }
        }
        _ = try app.send(.activateApp(window: standard))

        // MARK: Site controls
        try sweep.surface("site-controls") {
            try app.dispatch(.site(.controls))
            try app.waitUntil("the panel") { (try? app.send(.siteControlTexts(window: standard))).map { if case .menuItems = $0 { true } else { false } } ?? false }
        }
        try sweep.surface("site-controls-details", close: { try app.dispatch(.site(.controls)) }) {
            try app.perform(.siteControlInput(window: standard, field: "siteMore", action: .press))
            app.sleep(0.4)
        }
        _ = try app.send(.activateApp(window: standard))

        // MARK: Find
        try sweep.surface("find-nomatch") {
            try app.press("cmd+f")
            try app.type("zzzz nothing matches this query at all")
            app.sleep(0.4)
        }
        try sweep.surface("find-match", close: { try app.press("escape") }) {
            try app.press("cmd+a")
            try app.type("Page")
            app.sleep(0.4)
        }

        // MARK: Toasts
        try sweep.surface("toast-copied") {
            try app.dispatch(.page(.copyURL(.plain)))
        }
        try sweep.surface("toast-cleared", close: { try app.dispatch(.tabTools(.undoToast)) }) {
            try app.dispatch(.tab(.clearToday))
            try app.waitUntil("the Cleared Tabs toast") { try app.view().tabTools.toast != nil }
        }
        try app.settle()

        // MARK: Hover cards
        try app.dispatch(.tabTools(.preferences(includeFavorites: true, previews: true)))
        try sweep.surface("hover-tab", close: { try app.hover(CGPoint(x: 900, y: 500)) }) {
            try app.hover(centre(try rowFrame(app, longTab)))
            app.sleep(1.6)
        }
        try sweep.surface("hover-folder", close: {
            try app.hover(CGPoint(x: 900, y: 500))
            try app.dispatch(.item(.toggleFolder(folder)))
        }) {
            try app.dispatch(.item(.toggleFolder(folder)))
            app.sleep(0.4)
            try app.hover(centre(try rowFrame(app, folder)))
            app.sleep(1.6)
        }
        try app.dispatch(.tabTools(.preferences(includeFavorites: true, previews: false)))

        // MARK: Menus (native: AppKit sizes them; measured while each is open)
        let native = try app.native()
        sweep.measureMenu("today-row", at: centre(try rowFrame(app, longTab)))
        sweep.measureMenu("pinned-row", at: centre(try rowFrame(app, pinnedTab)))
        sweep.measureMenu("folder-row", at: centre(try rowFrame(app, folder)))
        sweep.measureMenu("favorite", at: centre(try visible(native, .favorite(favorite)).frame))
        sweep.measureMenu("space", at: centre(try visible(native, .dockSpace(otherSpace)).frame))
        sweep.measureMenu("dock", at: centre(try visible(native, .dock).frame))

        try sweep.finish()
    }

    private static func jsString(_ text: String) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed), as: UTF8.self)
    }
}
