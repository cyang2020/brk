import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// W2-1 to W2-12: the wave-2 scenarios (docs/design/swift/wave2.md). Each is registered `pending: "<owner>"` and
/// SKIPPED without a launch until its owner makes it pass and removes the tag; the body is the contract: the steps
/// and the literal assertions the worker's feature must satisfy on the real engine. Constants are from `Metrics`.
enum Wave2Scenarios {
    static let all: [Scenario] = [
        Scenario("W2-1", "Preferences… opens the settings window on a pane; a Links toggle persists across a restart", settingsWindow),
        Scenario("W2-2", "a profile has its own cookies: a cookie set in the Work profile is not seen by the default one", cefOnly: "cookies in a page",
                 pending: "F2", profileContexts),
        Scenario("W2-3", "an incognito window's tabs browse off the record and are gone after a restart", pending: "F2", incognito),
        Scenario("W2-4", "Cmd+N opens a second standard window that shares the sidebar", pending: "F3", newWindow),
        Scenario("W2-5", "Cmd+Opt+N opens Little Arc at Arc's default size; Open in moves its tab into the space", pending: "F3", littleArc),
        Scenario("W2-6", "Shift+click opens a Peek over the content; Esc closes it and its page", cefOnly: "a click on a link in a page",
                 pending: "F3", peek),
        Scenario("W2-7", "a link from another app follows Air Traffic Control, else opens a Little Arc", pending: "F3", externalLinks),
        Scenario("W2-8", "every menu action is a command bar result: typing 'preferences' and Enter opens the settings", pending: "F4", typeTravel),
        Scenario("W2-9", "a remapped shortcut routes and the old chord reaches the page; the Shortcuts pane shows the state",
                 cefOnly: "page titles written by keys.html's key listener", pending: "F4", remap),
        Scenario("W2-10", "typing in the command bar fetches the engine's suggestions and shows them", pending: "F4", suggestions),
        Scenario("W2-11", "a download lands in the Library's Downloads page and on disk", cefOnly: "a real download", pending: "F5", downloads),
        Scenario("W2-12", "Cmd+Y opens the Library's History page listing the visits", pending: "F5", history),
    ]

    /// W2-1 (F1): `openSettings(.links)` shows the settings window; `settings` reports the pane; a click on the
    /// Shift+click toggle flips `links.shiftClickPeek`; after `flush` and a restart the value holds and the window
    /// is closed (the pane is session state).
    @Sendable static func settingsWindow(_ app: AppUnderTest) throws {
        guard case .dispatched = try app.send(.openSettings(pane: .links)) else { throw Check(description: "openSettings did not dispatch") }
        try app.waitUntil("the settings window on the Links pane") {
            guard case .settings(let s) = try app.send(.settings) else { return false }
            return s.pane == .links
        }
        try app.waitUntil("a window with the settings identifier") {
            try app.native().appWindows.contains { $0.className.hasSuffix("NSWindow") && $0.isVisible }
        }
        guard case .settings(let before) = try app.send(.settings) else { throw Check(description: "settings did not answer") }
        try expect(before.links.shiftClickPeek, "Shift+click Peek is on by default")
        try app.click(.settingsField("shiftClickPeek"))
        try app.waitUntil("the toggle to flip the setting") {
            guard case .settings(let s) = try app.send(.settings) else { return false }
            return s.links.shiftClickPeek == false
        }
        try app.screenshot("settings-links")
        try app.flush()
        try app.restart()
        guard case .settings(let after) = try app.send(.settings) else { throw Check(description: "settings did not answer after restart") }
        try expect(after.links.shiftClickPeek == false, "the toggle did not survive the restart")
        try expect(after.pane == nil, "the settings window reopened on its own")
    }

    /// W2-2 (F2): a Work profile is created and assigned to a new space; `cookie.html#set` loaded there sets a
    /// cookie (title "cookie:brk=1"); the same page loaded in the default profile's space sees none ("cookie:");
    /// the URL pill shows the Work badge.
    @Sendable static func profileContexts(_ app: AppUnderTest) throws {
        let work = try createSpace(app, title: "Work")
        try app.dispatch(.profile(.create(name: "Work", icon: nil)))
        var profile: ProfileID?
        try app.waitUntil("the Work profile in settings") {
            guard case .settings(let s) = try app.send(.settings) else { return false }
            profile = s.profiles.first { $0.profile.name == "Work" }?.profile.id
            return profile != nil
        }
        try app.dispatch(.profile(.assign(.space(work), to: profile!)))
        try app.waitUntil("the Work badge in the URL pill") { try app.view().urlPill.profile?.name == "Work" }
        let setter = try openTab(app, app.site.url("cookie.html#set"))
        try waitForTitle(app, setter.id, "cookie:brk=1")
        try app.click(.dockSpace(try app.view().dock[0].id))
        try app.waitUntil("the default space") { try app.view().urlPill.profile == nil }
        let reader = try openTab(app, app.site.url("cookie.html"))
        try waitForTitle(app, reader.id, "cookie:")
        try app.screenshot("profiles")
    }

    /// W2-3 (F2): Shift+Cmd+N (or the dispatch while the nib conflict stands) opens an incognito window; a page
    /// loaded there is `BrowsingContext.incognito`; the pill shows the incognito badge; after a restart only the
    /// standard window is back and history has no trace of the page.
    @Sendable static func incognito(_ app: AppUnderTest) throws {
        try app.dispatch(.window(.newIncognito))
        var incognito: WindowID?
        try app.waitUntil("an incognito window") {
            guard case .hello(let h) = try app.send(.hello) else { return false }
            incognito = h.windows.first { (try? app.view($0))?.kind == .incognito }
            return incognito != nil
        }
        try app.perform(.dispatch(window: incognito, command: .commandBar(.submit(app.site.url("page2.html").absoluteString))))
        try app.waitUntil("the incognito tab in its own section") { try app.view(incognito!).scratch?.rows.count == 1 }
        try expect(try app.view(incognito!).urlPill.profile?.incognito == true, "no incognito badge")
        try app.screenshot("incognito", window: incognito)
        try app.flush()
        try app.restart()
        guard case .hello(let h) = try app.send(.hello) else { throw Check(description: "no hello after restart") }
        try expect(h.windows.count == 1, "\(h.windows.count) windows after restart, expected the standard one only")
        try app.dispatch(.library(.open(.history)))
        try app.waitUntil("the History page") { isLibrary(try app.view().overlay, page: .history) }
        guard case .library(let library)? = try app.view().overlay else { throw Check(description: "no library") }
        try expect(!library.history.contains { $0.url == app.site.url("page2.html") }, "the incognito visit is in history")
    }

    /// W2-4 (F3): Cmd+N opens a second standard window on the same space; a tab opened in one shows in both
    /// sidebars; both windows are restored after a restart.
    @Sendable static func newWindow(_ app: AppUnderTest) throws {
        try app.press("cmd+n")
        var second: WindowID?
        try app.waitUntil("a second window") {
            guard case .hello(let h) = try app.send(.hello) else { return false }
            second = h.windows.first { $0 != app.window }
            return h.windows.count == 2
        }
        try expect(try app.view(second!).kind == .standard, "the new window is not standard")
        try expect(try app.view(second!).space.id == app.view().space.id, "the new window is on another space")
        try app.perform(.dispatch(window: second, command: .commandBar(.dismiss)))
        try app.perform(.dispatch(window: second, command: .commandBar(.submit(app.site.url("page2.html").absoluteString))))
        try app.waitUntil("the tab in both sidebars") {
            let a = try app.view().space.today.rows.map(\.id), b = try app.view(second!).space.today.rows.map(\.id)
            return a.count == 2 && a == b
        }
        try app.screenshot("two-windows")
        try app.flush()
        try app.restart()
        guard case .hello(let h) = try app.send(.hello) else { throw Check(description: "no hello after restart") }
        try expect(h.windows.count == 2, "\(h.windows.count) windows after restart, expected 2")
    }

    /// W2-5 (F3): Cmd+Opt+N opens a Little Arc window (`kind == .little`, no sidebar, content size
    /// Metrics.littleArc.defaultSize) with the command bar; a URL typed there is its one tab; Cmd+O "Open in" moves
    /// the tab to the top of the current space's Today in the standard window and closes the Little Arc.
    @Sendable static func littleArc(_ app: AppUnderTest) throws {
        try app.press("cmd+opt+n")
        var little: WindowID?
        try app.waitUntil("a Little Arc window") {
            guard case .hello(let h) = try app.send(.hello) else { return false }
            little = h.windows.first { (try? app.view($0))?.kind == .little }
            return little != nil
        }
        let v = try app.view(little!)
        try expect(!v.sidebar.visible, "Little Arc shows a sidebar")
        try expect(isCommandBar(v.overlay), "Little Arc did not open with the command bar")
        let n = try app.send(.native(window: little))
        guard case .native(let facts) = n else { throw Check(description: "no native facts for the Little Arc window") }
        let size = Metrics.littleArc.defaultSize.value
        try expect(near(CGRect(origin: .zero, size: facts.contentSize), CGRect(origin: .zero, size: size), tolerance: 1),
                   "Little Arc content size \(facts.contentSize), expected \(size)")
        try app.perform(.dispatch(window: little, command: .commandBar(.submit(app.site.url("page2.html").absoluteString))))
        try app.waitUntil("the Little Arc's one tab") { try app.view(little!).scratch?.rows.count == 1 }
        try app.screenshot("little-arc", window: little)
        let before = todayIDs(try app.view())
        try app.perform(.dispatch(window: little, command: .window(.openIn(.current))))
        try app.waitUntil("the tab at the top of Today and the Little Arc gone") {
            guard case .hello(let h) = try app.send(.hello) else { return false }
            let today = todayIDs(try app.view())
            return h.windows.count == 1 && today.count == before.count + 1 && !before.contains(today[0])
        }
        try expect(try currentTab(app.view())?.url == app.site.url("page2.html"), "the moved tab is not current")
    }

    /// W2-6 (F3): Shift+click on fixture home's link opens a Peek on page2: `view().overlay` is `.peek`, the `peek`
    /// view's frame equals `computed.peek` (the content area inset Metrics.peek.inset), the peeked page is live and
    /// has focus; Esc closes it, its page leaves `native().pages`, and Today did not grow.
    @Sendable static func peek(_ app: AppUnderTest) throws {
        let before = todayIDs(try app.view())
        try app.settle()
        try app.click(at: CGPoint(x: try app.native().computed.cards[0].rect.minX + 40, y: try app.native().computed.cards[0].rect.minY + 40), modifiers: "shift")
        var page: PageID?
        try app.waitUntil("a Peek on page2") {
            guard case .peek(let p)? = try app.view().overlay else { return false }
            page = p.page
            return p.tab.url == app.site.url("page2.html") && page != nil
        }
        try app.waitUntil("the peek card at computed.peek with its page live") {
            let n = try app.native()
            let card = try visible(n, .peek)
            guard let rect = n.computed.peek else { throw Check(description: "computed frames have no peek") }
            try expect(near(card.frame, rect), "peek at \(card.frame), computed \(rect)")
            try expect(near(rect, n.computed.contentArea.insetBy(dx: Metrics.peek.inset.value, dy: Metrics.peek.inset.value)), "peek inset is not \(Metrics.peek.inset.value)")
            try expect(n.pages[page!] != nil, "the peeked page has no surface")
            try expect(n.focusedPage == page, "focus is on \(n.focusedPage?.description ?? "nothing"), not the peek")
            return true
        }
        try app.screenshot("peek")
        try app.press("escape")
        try app.waitUntil("the peek to close") { try app.view().overlay == nil && app.native().pages[page!] == nil }
        try expect(todayIDs(try app.view()) == before, "the peek left a Today tab behind")
    }

    /// W2-7 (F3): `externalURL` with default settings opens a Little Arc on the link; with "Links from other apps
    /// open in Little Arc" off and a route `127.0.0.1 -> Work`, the link lands at the top of Work's Today.
    @Sendable static func externalLinks(_ app: AppUnderTest) throws {
        try app.perform(.externalURL(url: app.site.url("page2.html")))
        var little: WindowID?
        try app.waitUntil("a Little Arc on the link") {
            guard case .hello(let h) = try app.send(.hello) else { return false }
            little = h.windows.first { (try? app.view($0))?.kind == .little }
            guard let little else { return false }
            let v = try app.view(little)
            return v.scratch?.rows.first.flatMap { tab($0.id, in: v) }?.url == app.site.url("page2.html")
        }
        try app.perform(.dispatch(window: little, command: .window(.close)))
        let work = try createSpace(app, title: "Work")
        try app.click(.dockSpace(try app.view().dock[0].id))
        try app.waitUntil("the first space") { try app.view().space.id != work }
        try app.dispatch(.settings(.links(.externalLinksInLittleArc(false))))
        try app.dispatch(.settings(.links(.addRoute(LinkRoute(id: LinkRouteID("fixture"), pattern: "127.0.0.1", destination: .space(work))))))
        try app.perform(.externalURL(url: app.site.url("red.html")))
        try app.waitUntil("the routed link at the top of Work's Today") {
            let v = try app.view()
            return v.space.id == work && tabRows(v.space.today.rows).first?.url == app.site.url("red.html")
        }
        try app.screenshot("routed-link")
    }

    /// W2-8 (F4): Cmd+T, typing "preferences" shows a Preferences… result; Enter opens the settings on General;
    /// Cmd+, does the same from a page.
    @Sendable static func typeTravel(_ app: AppUnderTest) throws {
        try app.press("cmd+t")
        try app.waitUntil("the command bar") { isCommandBar(try app.view().overlay) }
        try app.type("preferences")
        try app.waitUntil("a result row") { isShown(try app.native(), .commandBarResult(0)) }
        try app.screenshot("type-travel")
        try app.press("return")
        try app.waitUntil("the settings window on General") {
            guard case .settings(let s) = try app.send(.settings) else { return false }
            return s.pane == .general
        }
        try app.dispatch(.settings(.closeWindow))
        try app.press("cmd+,")
        try app.waitUntil("Cmd+, to open the settings") {
            guard case .settings(let s) = try app.send(.settings) else { return false }
            return s.pane == .general
        }
    }

    /// W2-9 (F4): New Tab remapped to Cmd+E: Cmd+E opens the bar; Cmd+T reaches keys.html (title shows cmd+t);
    /// the Shortcuts pane lists New Tab as valid on cmd+e and user-defined.
    @Sendable static func remap(_ app: AppUnderTest) throws {
        let keys = try openTab(app, app.site.url("keys.html"))
        try waitForTitle(app, keys.id, "keys:loads=1")
        try app.dispatch(.settings(.shortcuts(.setChord(.newTab, KeyChord(.command, .e)))))
        try app.press("cmd+e")
        try app.waitUntil("Cmd+E to open the command bar") { isCommandBar(try app.view().overlay) }
        try app.press("escape")
        try app.waitUntil("focus back on the page") { try app.native().focusedPage == PageID(keys.id) }
        try app.press("cmd+t")
        try waitForTitle(app, keys.id, NativeScenarios.keyTitle("cmd+t"))
        try expect(!isCommandBar(try app.view().overlay), "Cmd+T still opened the bar after the remap")
        guard case .settings(let s) = try app.send(.settings) else { throw Check(description: "settings did not answer") }
        let row = s.shortcuts.first { $0.action == .newTab }
        try expect(row?.state == .valid(KeyChord(.command, .e)), "Shortcuts pane state \(String(describing: row?.state))")
        try expect(row?.source == .userDefined, "Shortcuts pane source \(String(describing: row?.source))")
        try app.perform(.openSettings(pane: .shortcuts))
        try app.waitUntil("the Shortcuts pane") { try app.send(.settings).isSettingsPane(.shortcuts) }
        try app.screenshot("shortcuts-pane")
    }

    /// W2-10 (F4): typing "swi" in the bar asks the fixture suggest endpoint (BRK_SUGGEST_URL) and the bar shows
    /// "swift" and "swim" under the typed row; turning suggestions off stops the fetch.
    @Sendable static func suggestions(_ app: AppUnderTest) throws {
        try app.press("cmd+t")
        try app.waitUntil("the command bar") { isCommandBar(try app.view().overlay) }
        try app.type("swi")
        try app.waitUntil("suggestions from the fixture endpoint") {
            guard case .commandBar(let bar)? = try app.view().overlay else { return false }
            return bar.suggestions == ["swift", "swim"] && bar.suggestedFor == "swi"
        }
        try app.waitUntil("the suggestion rows on screen") {
            let n = try app.native()
            return isShown(n, .commandBarResult(1)) && isShown(n, .commandBarResult(2))
        }
        try app.screenshot("suggestions")
        try app.press("escape")
        try app.dispatch(.settings(.profile(.default, .searchSuggestions(false))))
        try app.press("cmd+t")
        try app.type("swi")
        app.sleep(0.6)
        guard case .commandBar(let bar)? = try app.view().overlay else { throw Check(description: "the bar closed") }
        try expect(bar.suggestions.isEmpty, "suggestions arrived with the setting off")
    }

    /// W2-11 (F5): with the profile's download location set to the data directory, loading `/download` saves
    /// `fixture.txt` there; the Downloads page lists it finished with its path, and the file exists.
    @Sendable static func downloads(_ app: AppUnderTest) throws {
        let directory = app.dataDirectory.appendingPathComponent("downloads", isDirectory: true).path
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(directory))))
        try app.load(app.site.url("download"))
        try app.press("cmd+shift+j")
        try app.waitUntil("the Downloads page with fixture.txt finished", timeout: 15) {
            guard case .library(let library)? = try app.view().overlay, library.page == .downloads else { return false }
            guard let row = library.downloads.first(where: { $0.filename == "fixture.txt" }) else { return false }
            return row.state == .finished && row.path?.hasPrefix(directory) == true && FileManager.default.fileExists(atPath: row.path!)
        }
        try app.waitUntil("the download row on screen") {
            guard case .library(let library)? = try app.view().overlay, let row = library.downloads.first else { return false }
            return isShown(try app.native(), .downloadEntry(row.id))
        }
        try app.screenshot("downloads")
    }

    /// W2-12 (F5): after visiting page2, Cmd+Y opens the Library on History with both visits newest first; the
    /// history rows are on screen inside the Library's page area.
    @Sendable static func history(_ app: AppUnderTest) throws {
        try openTab(app, app.site.url("page2.html"))
        try app.settle()
        try app.press("cmd+y")
        try app.waitUntil("the History page") { isLibrary(try app.view().overlay, page: .history) }
        guard case .library(let library)? = try app.view().overlay else { throw Check(description: "no library") }
        try expect(library.history.map(\.url) == [app.site.url("page2.html"), app.site.url("index.html")],
                   "history is \(library.history.map(\.url.absoluteString))")
        try app.waitUntil("the rows inside the Library's page area") {
            let n = try app.native()
            let host = try visible(n, .library), row = try visible(n, .historyEntry(0))
            try expect(contains(host, row), "history row \(row.frame) outside the library \(host.frame)")
            return true
        }
        try app.screenshot("history")
    }
}

/// The Library is open on `page`.
func isLibrary(_ overlay: OverlaySnapshot?, page: LibraryPage) -> Bool { if case .library(let l)? = overlay { l.page == page } else { false } }

extension ControlResult {
    func isSettingsPane(_ pane: SettingsPane) -> Bool { if case .settings(let s) = self { s.pane == pane } else { false } }
}
