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
                 profileContexts),
        Scenario("W2-3", "an incognito window's tabs browse off the record and are gone after a restart", incognito),
        Scenario("W2-4", "Cmd+N opens a second standard window that shares the sidebar", newWindow),
        Scenario("W2-5", "Cmd+Opt+N opens Little Arc at Arc's default size; Open in moves its tab into the space", littleArc),
        Scenario("W2-6", "Shift+click opens a Peek over the content; Esc closes it and its page", cefOnly: "a click on a link in a page",
                 peek),
        Scenario("W2-7", "a link from another app follows Air Traffic Control, else opens a Little Arc", externalLinks),
        Scenario("W2-8", "every menu action is a command bar result: typing 'preferences' and Enter opens the settings", typeTravel),
        Scenario("W2-9", "a remapped shortcut routes and the old chord reaches the page; the Shortcuts pane shows the state",
                 cefOnly: "page titles written by keys.html's key listener", remap),
        Scenario("W2-10", "typing in the command bar fetches the engine's suggestions and shows them; Tab on an engine's name enters site search",
                 suggestions),
        Scenario("W2-11", "a download lands in the Library's Downloads page and on disk", cefOnly: "a real download", downloads),
        Scenario("W2-12", "Cmd+Y opens the Library's History page listing the visits", history),
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
    /// the URL pill shows the Work badge. Then the rest of a profile's life on the real engine: the change dialog
    /// on screen; the default space moved to Work reloads its shown page in Work's context (the reader now sees the
    /// cookie); the delete dialog refuses while a space uses Work; with both spaces back on the default profile Work
    /// is deleted, its Chromium directory is marked in `profiles-to-delete` and is gone after a restart.
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
        try app.waitUntil("the badge on screen in the URL pill") {
            let n = try app.native()
            return contains(try visible(n, .urlPill), try visible(n, .profileBadge))
        }
        try app.screenshot("profile-badge")
        try app.click(.dockSpace(try app.view().dock[0].id))
        try app.waitUntil("the default space") { try app.view().urlPill.profile == nil }
        try app.waitUntil("no badge for the default profile") { !isShown(try app.native(), .profileBadge) }
        // `load`, not Cmd+T and typing: the bar's top result for the typed URL is "Switch to Tab" on the setter
        // (cookie.html#set), which would focus the setter in Work instead of opening a reader here.
        let readerID = try app.load(app.site.url("cookie.html"))
        try app.waitUntil("the reader in the default space") { tabRows(try app.view().space.today.rows).contains { $0.id == readerID } }
        try waitForTitle(app, readerID, "cookie:")
        try app.screenshot("profiles")

        let first = try app.view().space.id
        try app.dispatch(.profile(.openDialog(.change(.current))))
        try app.waitUntil("the change dialog on screen") { isShown(try app.native(), .profileDialog) }
        try app.screenshot("profile-dialog-change")
        try app.dispatch(.profile(.assign(.space(first), to: profile!)))
        try app.waitUntil("the change dialog closed") { try app.view().profileDialog == nil && !isShown(try app.native(), .profileDialog) }
        try waitForTitle(app, readerID, "cookie:brk=1")
        try expect(try app.pageLog().filter { $0.page == PageID(readerID) && $0.kind == .created }.count == 2,
                   "the reader's page was not replaced in the new context")

        try app.dispatch(.profile(.openDialog(.delete(profile!))))
        try app.waitUntil("the delete dialog on screen") { isShown(try app.native(), .profileDialog) }
        try app.screenshot("profile-dialog-delete-refused")
        try app.dispatch(.profile(.delete(profile!)))
        try expect(try app.view().profileDialog != nil, "deleting a profile with spaces was not refused")
        try app.dispatch(.profile(.openDialog(nil)))
        try app.dispatch(.profile(.assign(.space(first), to: .default)))
        try app.dispatch(.profile(.assign(.space(work), to: .default)))
        let directory = app.dataDirectory.appendingPathComponent("Chromium/Profile-\(profile!.rawValue)", isDirectory: true)
        let marker = app.dataDirectory.appendingPathComponent("profiles-to-delete")
        try expect(FileManager.default.fileExists(atPath: directory.path), "Work's pages left no Chromium directory at \(directory.path)")
        try app.dispatch(.profile(.openDialog(.create)))
        try app.waitUntil("the create dialog on screen") { isShown(try app.native(), .profileDialog) }
        try app.screenshot("profile-dialog-create")
        try app.dispatch(.profile(.openDialog(nil)))
        try app.dispatch(.profile(.delete(profile!)))
        try app.waitUntil("Work deleted and marked") {
            guard case .settings(let s) = try app.send(.settings) else { return false }
            let marked = (try? String(contentsOf: marker, encoding: .utf8))?.split(separator: "\n").contains { $0 == "Profile-\(profile!.rawValue)" } ?? false
            return s.profiles.map(\.profile.id) == [.default] && marked
        }
        try app.flush()
        try app.restart()
        try expect(!FileManager.default.fileExists(atPath: directory.path), "the deleted profile's directory survived the restart")
        try expect(!FileManager.default.fileExists(atPath: marker.path), "the marker survived the sweep")
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
        let submit = try app.send(.dispatch(window: incognito, command: .commandBar(.submit(app.site.url("page2.html").absoluteString))))
        guard case .dispatched = submit else { throw Check(description: "the submit in the incognito window answered \(AppUnderTest.describe(submit))") }
        try app.waitUntil("the incognito tab in its own section") { try app.view(incognito!).scratch?.rows.count == 1 }
        try app.waitUntil("the incognito page loaded off the record", timeout: 10) {
            guard case .tab(let row)? = try app.view(incognito!).scratch?.rows.first else { return false }
            return row.title == "Fixture Page 2"
        }
        try expect(try app.view(incognito!).urlPill.profile?.incognito == true, "no incognito badge")
        try app.waitUntil("the incognito badge on screen") {
            guard case .native(let n) = try app.send(.native(window: incognito)) else { return false }
            let v = try app.view(incognito!)
            guard let row = v.scratch?.rows.first else { return false }
            try expect(v.theme.scheme == .dark && relativeLuminance(v.theme.windowColor) < 0.18, "incognito chrome is not dark")
            return try isShown(n, .profileBadge) && contains(visible(n, .section(.scratch)), visible(n, .row(row.id)))
        }
        try app.screenshot("incognito", window: incognito)
        let privateTab = try app.view(incognito!).scratch!.rows[0].id
        try dispatch(app, window: incognito, .commandBar(.submit(app.site.url("red.html").absoluteString)))
        try app.waitUntil("a second private tab loaded") {
            let v = try app.view(incognito!)
            guard case .tab(let row)? = v.scratch?.rows.first else { return false }
            return v.scratch?.rows.count == 2 && row.title == "Red"
        }
        try app.click(.row(privateTab))
        try app.waitUntil("clicking the private sidebar row selects its page") {
            guard case .native(let native) = try app.send(.native(window: incognito)) else { return false }
            return try app.view(incognito!).content.panes.first?.tab == privateTab && native.focusedPage == PageID(privateTab)
        }
        // `press` has no window argument and falls back to an arbitrary window when the display is locked.
        // Target this window explicitly; R6 covers the native Ctrl+Tab press/release path.
        try dispatch(app, window: incognito, .tab(.close(.focused)))
        try app.waitUntil("closing the private row selects the remaining private page") {
            let v = try app.view(incognito!)
            return v.scratch?.rows.count == 1 && v.urlPill.text == displayURL(app.site.url("red.html"))
        }
        try app.flush()
        try app.restart()
        guard case .hello(let h) = try app.send(.hello) else { throw Check(description: "no hello after restart") }
        try expect(h.windows.count == 1, "\(h.windows.count) windows after restart, expected the standard one only")
        try app.dispatch(.library(.open(.history)))
        try app.waitUntil("the History page") { isLibrary(try app.view().overlay, page: .history) }
        guard case .library(let library)? = try app.view().overlay else { throw Check(description: "no library") }
        try expect(!library.history.contains { $0.url == app.site.url("page2.html") }, "the incognito visit is in history")
        try app.dispatch(.library(.open(.archive)))
        guard case .library(let archived)? = try app.view().overlay else { throw Check(description: "no archive") }
        let urls = archived.archive?.groups.flatMap(\.entries).map(\.url) ?? []
        try expect(!urls.contains(app.site.url("page2.html")), "closing the incognito row saved it in the archive")
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
        try dispatch(app, window: second, .commandBar(.dismiss))
        try dispatch(app, window: second, .commandBar(.submit(app.site.url("page2.html").absoluteString)))
        try app.waitUntil("the tab in both sidebars") {
            let a = try app.view().space.today.rows.map(\.id), b = try app.view(second!).space.today.rows.map(\.id)
            return a.count == 2 && a == b
        }
        try app.waitUntil("the second window's page loaded and both native sidebars drawn") {
            guard let row = currentTab(try app.view(second!)), row.title == "Fixture Page 2",
                  case .native(let native) = try app.send(.native(window: second)) else { return false }
            return try isShown(native, .row(row.id)) && isShown(app.native(), .row(row.id))
                && native.focusedPage == PageID(row.id) && native.pages[PageID(row.id)] != nil
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
        try dispatch(app, window: little, .commandBar(.submit(app.site.url("page2.html").absoluteString)))
        try app.waitUntil("the Little Arc's one tab") { try app.view(little!).scratch?.rows.count == 1 }
        try app.waitUntil("the Little Arc page loaded with keyboard focus") {
            guard case .tab(let row)? = try app.view(little!).scratch?.rows.first,
                  case .native(let native) = try app.send(.native(window: little)) else { return false }
            return row.title == "Fixture Page 2" && native.focusedPage == PageID(row.id)
                && native.pages[PageID(row.id)] != nil && !isShown(native, .sidebar)
        }
        try app.screenshot("little-arc", window: little)
        let before = todayIDs(try app.view())
        try dispatch(app, window: little, .window(.openIn(.current)))
        try app.waitUntil("the tab at the top of Today and the Little Arc gone") {
            guard case .hello(let h) = try app.send(.hello) else { return false }
            let today = todayIDs(try app.view())
            return h.windows.count == 1 && today.count == before.count + 1 && !before.contains(today[0])
        }
        try expect(try currentTab(app.view())?.url == app.site.url("page2.html"), "the moved tab is not current")
        try app.waitUntil("the promoted tab loaded in the standard window") {
            guard let row = currentTab(try app.view()), row.title == "Fixture Page 2" else { return false }
            let native = try app.native()
            return native.focusedPage == PageID(row.id) && native.pages[PageID(row.id)] != nil && isShown(native, .row(row.id))
        }
    }

    /// W2-6 (F3): Shift+click on fixture home's link opens a Peek on page2: `view().overlay` is `.peek`, the `peek`
    /// view's frame equals `computed.peek` (the content area inset Metrics.peek.inset), the peeked page is live and
    /// has focus; Esc closes it, its page leaves `native().pages`, and Today did not grow.
    @Sendable static func peek(_ app: AppUnderTest) throws {
        let before = todayIDs(try app.view())
        try app.settle()
        let card = try app.native().computed.cards[0].rect
        try app.click(at: CGPoint(x: card.minX + 52, y: card.minY + 48), modifiers: "shift")   // the link's middle, as R3 clicks it
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
            guard case .peek(let p)? = try app.view().overlay else { return false }
            return p.tab.title == "Fixture Page 2"
        }
        try app.screenshot("peek")
        try app.press("escape")
        try app.waitUntil("the peek to close") { try app.view().overlay == nil && app.native().pages[page!] == nil }
        try expect(todayIDs(try app.view()) == before, "the peek left a Today tab behind")
        try app.waitUntil("keyboard focus returned to the original page") {
            guard let row = currentTab(try app.view()) else { return false }
            return try app.native().focusedPage == PageID(row.id)
        }
    }

    /// W2-7 (F3): `externalURL` with default settings opens a Little Arc on the link; with "Links from other apps
    /// open in Little Arc" off and a route `127.0.0.1 -> Work`, the link lands at the top of Work's Today.
    @Sendable static func externalLinks(_ app: AppUnderTest) throws {
        try externalURL(app, app.site.url("page2.html"))
        var little: WindowID?
        try app.waitUntil("a Little Arc on the link") {
            guard case .hello(let h) = try app.send(.hello) else { return false }
            little = h.windows.first { (try? app.view($0))?.kind == .little }
            guard let little else { return false }
            guard case .tab(let row)? = try app.view(little).scratch?.rows.first else { return false }   // its one tab is a scratch row
            return row.url == app.site.url("page2.html") && row.title == "Fixture Page 2"
        }
        try dispatch(app, window: little, .window(.close))
        let work = try createSpace(app, title: "Work")
        try app.click(.dockSpace(try app.view().dock[0].id))
        try app.waitUntil("the first space") { try app.view().space.id != work }
        try app.dispatch(.settings(.links(.externalLinksInLittleArc(false))))
        try app.dispatch(.settings(.links(.addRoute(LinkRoute(id: LinkRouteID("fixture"), pattern: "127.0.0.1", destination: .space(work))))))
        try externalURL(app, app.site.url("red.html"))
        try app.waitUntil("the routed link at the top of Work's Today") {
            let v = try app.view()
            return v.space.id == work && tabRows(v.space.today.rows).first?.url == app.site.url("red.html")
                && currentTab(v)?.title == "Red"
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
    /// "swift" and "swim" under the typed row; turning suggestions off stops the fetch. Then site search: "bing"
    /// and Tab put Bing's pill before the input (the input moves right), Esc gives the plain input back.
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

        try app.press("escape")
        try app.press("cmd+t")
        try app.waitUntil("the command bar") { isCommandBar(try app.view().overlay) }
        let plain = try visible(try app.native(), .commandBarInput).frame
        try app.type("bing")
        try app.waitUntil("the site-search row") { isShown(try app.native(), .commandBarResult(1)) }
        try app.press("tab")
        try app.waitUntil("Bing's pill before the input") { try visible(try app.native(), .commandBarInput).frame.minX > plain.minX + 20 }
        try app.type("swift")
        try app.screenshot("site-search")
        try app.press("escape")
        try app.waitUntil("site search left, the bar still open") {
            let open = isCommandBar(try app.view().overlay)
            return try open && abs(visible(try app.native(), .commandBarInput).frame.minX - plain.minX) < 0.5
        }
    }

    /// W2-11 (F5): with the profile's download location set to the data directory, loading `/download` saves
    /// `fixture.txt` there; the Downloads page lists it finished with its path, and the file exists. A second
    /// download of the same name lands beside it as `fixture (1).txt`.
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
        try app.load(app.site.url("download"))
        try app.press("cmd+shift+j")
        try app.waitUntil("a second download of the same name, numbered", timeout: 15) {
            guard case .library(let library)? = try app.view().overlay, library.page == .downloads else { return false }
            let paths = library.downloads.filter { $0.state == .finished }.compactMap(\.path)
            guard paths.count == 2 else { return false }
            try expect(Set(paths) == [directory + "/fixture.txt", directory + "/fixture (1).txt"], "downloads at \(paths)")
            return paths.allSatisfy { FileManager.default.fileExists(atPath: $0) }
        }
    }

    /// W2-12 (F5): after visiting page2, Cmd+Y opens the Library on History with both visits newest first; the
    /// history rows are on screen inside the Library's page area (the content area beside its panel).
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
            guard let area = n.computed.library?.page else { throw Check(description: "computed frames have no library") }
            let host = try visible(n, .library), row = try visible(n, .historyEntry(0))
            try expect(contains(host, row), "history row \(row.frame) outside the library \(host.frame)")
            try expect(area.insetBy(dx: -0.5, dy: -0.5).contains(row.frame), "history row \(row.frame) outside the page area \(area)")
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

/// `dispatch` to a window other than the first (a Little Arc, a second window): the reply is `dispatched(rev)`,
/// which `perform` (an `ok` op) would refuse.
@discardableResult
func dispatch(_ app: AppUnderTest, window: WindowID?, _ command: Command) throws -> Int {
    let result = try app.send(.dispatch(window: window, command: command))
    guard case .dispatched(let rev) = result else { throw Check(description: "dispatch to \(window?.rawValue ?? "(key)") answered \(AppUnderTest.describe(result))") }
    return rev
}

/// A link from another app, as the GetURL Apple Event delivers it; replies `dispatched(rev)` like a dispatch.
func externalURL(_ app: AppUnderTest, _ url: URL) throws {
    let result = try app.send(.externalURL(url: url))
    guard case .dispatched = result else { throw Check(description: "externalURL answered \(AppUnderTest.describe(result))") }
}
