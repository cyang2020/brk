import AppKit
import BrkBase
@testable import BrkDomain
import BrkLayout
import BrkUIKit
import XCTest
@testable import BrkSettings

/// Owner: F1. The settings window's content, driven the way a user drives it: find the control by its
/// `settings-field-<name>` identifier, click it, read the command it sent. Every control shows only the snapshot.
@MainActor
final class SettingsHostTests: XCTestCase {
    private let personal = SpaceID("s-personal"), work = SpaceID("s-work")
    private let spotify = LinkRouteID("r-spotify"), github = LinkRouteID("r-github")

    private func snapshot(pane: SettingsPane?, general: GeneralSettings = .default, links: LinkSettings = .default,
                          routes: [LinkRouteRow] = [], max: MaxSnapshot = MaxSnapshot(settings: .default, detected: [], active: nil),
                          advanced: AdvancedSettings = .default) -> SettingsSnapshot {
        SettingsSnapshot(
            pane: pane, general: general,
            profiles: [ProfileSettingsRow(profile: ProfileRow(id: .default, name: "Default", icon: nil, spaceTitles: ["Personal", "Work"], isDefault: true),
                                          settings: .default)],
            links: links, routes: routes,
            spaces: [SpaceCandidate(id: personal, title: "Personal", icon: .none, isCurrent: false),
                     SpaceCandidate(id: work, title: "Work", icon: .none, isCurrent: false)],
            engines: SearchEngine.builtIn.map { SearchEngineCandidate(id: $0.id, name: $0.name, keyword: $0.keyword) },
            shortcuts: [], max: max, advanced: advanced)
    }

    /// A host in a window, as BrkApp shows it, recording what it dispatches.
    @MainActor private final class Fixture {
        /// What the host sent; its own object, so the host's closure does not keep the fixture (and its window) alive.
        final class Log { var sent: [Command] = [] }
        let host: SettingsHost
        let window: NSWindow
        private let log = Log()
        var sent: [Command] {
            get { log.sent }
            set { log.sent = newValue }
        }

        init(defaultBrowser: Bool = false) {
            host = SettingsHost(dispatch: { [log] in log.sent.append($0) })
            host.defaultBrowserCheck = { defaultBrowser }
            window = NSWindow(contentRect: CGRect(origin: .zero, size: Metrics.settings.windowSize.value), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
        }

        func render(_ snapshot: SettingsSnapshot) {
            host.render(snapshot)
            settle()
        }

        func settle() {
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
        }

        func view<T: NSView>(_ field: String, _ type: T.Type = T.self) -> T? {
            find(ViewID.settingsField(field).identifier) as? T
        }

        func find(_ identifier: String) -> NSView? {
            func walk(_ view: NSView) -> NSView? {
                if view.accessibilityIdentifier() == identifier { return view }
                for child in view.subviews { if let found = walk(child) { return found } }
                return nil
            }
            return walk(host)
        }

        /// Clicks a checkbox or button and returns what it sent.
        func click(_ field: String, file: StaticString = #filePath, line: UInt = #line) -> [Command] {
            guard let button: NSButton = view(field) else { XCTFail("no control \(field)", file: file, line: line); return [] }
            sent = []
            button.performClick(nil)
            return sent
        }

        /// Picks a pop-up item by title and returns what it sent.
        func pick(_ field: String, _ title: String, file: StaticString = #filePath, line: UInt = #line) -> [Command] {
            guard let popUp: NSPopUpButton = view(field) else { XCTFail("no pop-up \(field)", file: file, line: line); return [] }
            guard popUp.itemTitles.contains(title) else { XCTFail("\(field) has no item \(title): \(popUp.itemTitles)", file: file, line: line); return [] }
            sent = []
            popUp.selectItem(withTitle: title)
            popUp.sendAction(popUp.action, to: popUp.target)
            return sent
        }

        /// Types into a text field and presses Return.
        func type(_ field: String, _ text: String, file: StaticString = #filePath, line: UInt = #line) -> [Command] {
            guard let textField: NSTextField = view(field) else { XCTFail("no field \(field)", file: file, line: line); return [] }
            sent = []
            textField.stringValue = text
            textField.sendAction(textField.action, to: textField.target)
            return sent
        }
    }

    func testRendersEveryPaneHeadless() {
        let f = Fixture()
        for pane in SettingsPane.allCases {
            f.render(snapshot(pane: pane))
            XCTAssertNotNil(f.find("settings-pane-\(pane.rawValue)"), "\(pane) is not on screen")
        }
        f.render(snapshot(pane: nil))
        XCTAssertNotNil(f.find("settings-pane-advanced"), "a closing window keeps its last pane instead of going blank")
        XCTAssertEqual(f.host.accessibilityIdentifier(), "settings")
    }

    func testCopyNamesEveryPaneAndChoice() {
        XCTAssertEqual(SettingsPane.allCases.map(SettingsCopy.title), ["General", "Max", "Profiles", "Shortcuts", "Links", "Advanced"])
        XCTAssertEqual(AutoArchiveThreshold.allCases.map(SettingsCopy.threshold), ["1 hour", "6 hours", "12 hours", "24 hours", "7 days", "30 days", "Never"])
        XCTAssertEqual(SettingsCopy.state(.unset), "None")
        XCTAssertEqual(SettingsCopy.state(.valid(KeyChord([.shift, .command], .t))), "⇧⌘T")
        XCTAssertEqual(SettingsCopy.state(.conflict(KeyChord([.shift, .command], .n), with: [.newFolder]), titles: { _ in "New Folder…" }),
                       "⇧⌘N is already in use by “New Folder…”")
        XCTAssertEqual(SettingsCopy.state(.conflict(KeyChord(.command, .e), with: [.newFolder, .newTab, .newWindow]), titles: { _ in "X" }),
                       "⌘E is already in use by “X” and 2 other actions")
        XCTAssertEqual(SettingsCopy.detected([.claude], active: .claude), "Found on PATH: claude. Using claude.")
        XCTAssertEqual(SettingsCopy.detected([], active: nil), "No local AI command-line tool found on PATH.")
    }

    /// each checkbox, pop-up and button sends its one `.settings(...)` command and keeps showing the snapshot
    func testEveryFieldDispatchesItsSettingsCommand() {
        let f = Fixture()
        f.render(snapshot(pane: .general))
        XCTAssertEqual(f.click("warnBeforeQuitting"), [.settings(.general(.warnBeforeQuitting(true)))])
        XCTAssertEqual(f.view("warnBeforeQuitting", NSButton.self)?.state, .off, "the checkbox waits for the snapshot")
        XCTAssertEqual(f.pick("webAppearance", "Dark"), [.settings(.general(.webAppearance(.dark)))])
        XCTAssertEqual(f.view("webAppearance", NSPopUpButton.self)?.titleOfSelectedItem, "Automatic", "the pop-up waits for the snapshot")
        XCTAssertEqual(f.pick("webAppearance", "Automatic"), [], "choosing the current value sends nothing")
        XCTAssertEqual(f.click("profileSettings"), [.settings(.openPane(.profiles))])
        XCTAssertEqual(f.click("setAsDefaultBrowser"), [.app(.setAsDefaultBrowser)])
        XCTAssertEqual(f.click("dismissDefaultBrowserPrompt"), [.settings(.general(.dismissDefaultBrowserPrompt))])
        var general = GeneralSettings.default
        general.warnBeforeQuitting = true
        f.render(snapshot(pane: .general, general: general))
        XCTAssertEqual(f.view("warnBeforeQuitting", NSButton.self)?.state, .on, "the next snapshot shows the answer")
        XCTAssertEqual(f.click("warnBeforeQuitting"), [.settings(.general(.warnBeforeQuitting(false)))])

        f.render(snapshot(pane: .max))
        XCTAssertEqual(f.pick("aiProvider", "codex"), [.settings(.max(.provider(.codex)))])
        XCTAssertEqual(f.click("renamePinnedTabs"), [.settings(.max(.renamePinnedTabs(true)))])
        XCTAssertEqual(f.click("tidyTabs"), [.settings(.max(.tidyTabs(true)))])

        f.render(snapshot(pane: .profiles))
        XCTAssertEqual(f.pick("autoArchive-default", "1 hour"), [.settings(.profile(.default, .autoArchive(.oneHour)))])
        XCTAssertEqual(f.pick("searchEngine-default", "DuckDuckGo"), [.settings(.profile(.default, .searchEngine(SearchEngineID("duckduckgo"))))])
        XCTAssertEqual(f.click("searchSuggestions-default"), [.settings(.profile(.default, .searchSuggestions(false)))])
        XCTAssertEqual(f.view("downloadLocation-default", NSPopUpButton.self)?.itemTitles, ["Downloads", "Ask where to save each download", "", "Other…"])
        XCTAssertEqual(f.pick("downloadLocation-default", "Ask where to save each download"),
                       [.settings(.profile(.default, .promptForDownloadLocation(true)))])
        var offered: [String?] = []
        f.host.chooseFolder = { offered.append($0); return "/Users/me/Inbox" }
        XCTAssertEqual(f.pick("downloadLocation-default", "Other…"), [.settings(.profile(.default, .downloadsDirectory("/Users/me/Inbox")))])
        XCTAssertEqual(offered, [nil], "the folder panel starts at the current folder (the system Downloads)")
        f.host.chooseFolder = { _ in nil }
        XCTAssertEqual(f.pick("downloadLocation-default", "Other…"), [], "a cancelled panel sends nothing")

        f.render(snapshot(pane: .links))
        XCTAssertEqual(f.click("shiftClickPeek"), [.settings(.links(.shiftClickPeek(false)))])
        XCTAssertEqual(f.click("peekFromPinnedAndFavorites"), [.settings(.links(.peekFromPinnedAndFavorites(false)))])
        XCTAssertEqual(f.click("externalLinksInLittleArc"), [.settings(.links(.externalLinksInLittleArc(false)))])
        XCTAssertEqual(f.click("optionCommandClickLittleArc"), [.settings(.links(.optionCommandClickLittleArc(false)))])
        XCTAssertEqual(f.pick("littleArcAutoArchive", "7 days"), [.settings(.links(.littleArcAutoArchive(.sevenDays)))])

        f.render(snapshot(pane: .advanced))
        XCTAssertEqual(f.click("restoreWindowsOnLaunch"), [.settings(.advanced(.restoreWindowsOnLaunch(false)))])
        XCTAssertEqual(f.click("soundEffects"), [.settings(.advanced(.soundEffects(false)))])
        XCTAssertEqual(f.click("hapticsOnReorder"), [.settings(.advanced(.hapticsOnReorder(false)))])
        XCTAssertEqual(f.click("showFullURLInToolbar"), [.settings(.advanced(.showFullURLInToolbar(true)))])
        XCTAssertEqual(f.click("windowDraggingFromPages"), [.settings(.advanced(.windowDraggingFromPages(false)))])
        XCTAssertEqual(f.click("autoPictureInPicture"), [.settings(.advanced(.autoPictureInPicture(false)))])
        XCTAssertEqual(f.click("themeToCSS"), [.settings(.advanced(.themeToCSS(true)))])
        XCTAssertEqual(f.click("boostsEnabled"), [.settings(.advanced(.boostsEnabled(false)))])
        XCTAssertEqual(f.click("sharedQuotes"), [.settings(.advanced(.sharedQuotes(false)))])
    }

    /// Arc's pane toolbar: one selectable item per pane in Arc's enum order, with an icon; the window is titled
    /// with the open pane; clicking an item opens that pane
    func testThePaneToolbarMatchesArcsOrderAndIcons() {
        let f = Fixture()
        f.render(snapshot(pane: .links))
        guard let toolbar = f.window.toolbar else { return XCTFail("no toolbar") }
        XCTAssertEqual(f.window.toolbarStyle, .preference)
        XCTAssertEqual(toolbar.items.map(\.itemIdentifier.rawValue),
                       ["settings-pane-general", "settings-pane-max", "settings-pane-profiles", "settings-pane-shortcuts", "settings-pane-links", "settings-pane-advanced"])
        XCTAssertEqual(toolbar.items.map(\.label), ["General", "Max", "Profiles", "Shortcuts", "Links", "Advanced"])
        XCTAssertTrue(toolbar.items.allSatisfy { $0.image != nil }, "every pane has its icon")
        XCTAssertEqual(toolbar.selectedItemIdentifier?.rawValue, "settings-pane-links")
        XCTAssertEqual(f.window.title, "Links")
        XCTAssertNotNil(f.find("settings-pane-links"))
        XCTAssertNil(f.find("settings-pane-general"))

        f.sent = []
        let max = toolbar.items[1]
        NSApp.sendAction(max.action!, to: max.target, from: max)
        XCTAssertEqual(f.sent, [.settings(.openPane(.max))])
        f.render(snapshot(pane: .max))
        XCTAssertEqual(toolbar.selectedItemIdentifier?.rawValue, "settings-pane-max")
        XCTAssertEqual(f.window.title, "Max")
    }

    /// the route list edits Air Traffic Control: every route's destination offers Most Recent Space, Little Arc
    /// and each space; routes move, change, are removed and added
    func testTheLinksPaneEditsAirTrafficControlRoutes() {
        let f = Fixture()
        let a = LinkRoute(id: spotify, pattern: "open.spotify.com", destination: .space(personal))
        let b = LinkRoute(id: github, pattern: "*.github.com", destination: .littleArc)
        f.render(snapshot(pane: .links, routes: [LinkRouteRow(route: a, destinationTitle: "Personal"), LinkRouteRow(route: b, destinationTitle: "Little Arc")]))

        let destination: NSPopUpButton? = f.view("route-r-spotify-destination")
        XCTAssertEqual(destination?.itemTitles, ["Most Recent Space", "Little Arc", "", "Personal", "Work"])
        XCTAssertEqual(destination?.titleOfSelectedItem, "Personal")
        XCTAssertEqual(f.pick("route-r-spotify-destination", "Work"),
                       [.settings(.links(.updateRoute(LinkRoute(id: spotify, pattern: "open.spotify.com", destination: .space(work)))))])
        XCTAssertEqual(f.type("route-r-spotify-pattern", "spotify.com"),
                       [.settings(.links(.updateRoute(LinkRoute(id: spotify, pattern: "spotify.com", destination: .space(personal)))))])
        XCTAssertNil(f.view("route-r-spotify-up", NSButton.self), "the first route cannot move up")
        XCTAssertNil(f.view("route-r-github-down", NSButton.self), "the last route cannot move down")
        XCTAssertEqual(f.click("route-r-spotify-down"), [.settings(.links(.moveRoute(spotify, index: 1)))])
        XCTAssertEqual(f.click("route-r-github-up"), [.settings(.links(.moveRoute(github, index: 0)))])
        XCTAssertEqual(f.click("route-r-github-remove"), [.settings(.links(.removeRoute(github)))])

        XCTAssertEqual(f.click("route-add"), [], "an empty pattern adds nothing")
        XCTAssertEqual(f.type("route-new-pattern", " news.ycombinator.com "), [], "typing a new route sends nothing before Add")
        f.settle()
        XCTAssertEqual(f.pick("route-new-destination", "Work"), [])
        f.settle()
        let added = f.click("route-add")
        guard case .settings(.links(.addRoute(let route)))? = added.first, added.count == 1 else { return XCTFail("no route added: \(added)") }
        XCTAssertEqual(route.pattern, "news.ycombinator.com")
        XCTAssertEqual(route.destination, .space(work))
        XCTAssertFalse(route.id.rawValue.isEmpty)

        XCTAssertEqual(f.pick("defaultRoute", "Little Arc"), [.settings(.links(.defaultRoute(.littleArc)))])
        var links = LinkSettings.default
        links.defaultRoute = .littleArc
        f.render(snapshot(pane: .links, links: links))
        XCTAssertEqual(f.view("defaultRoute", NSPopUpButton.self)?.titleOfSelectedItem, "Little Arc")
        XCTAssertEqual(f.pick("defaultRoute", "Most Recent Space"), [.settings(.links(.defaultRoute(nil)))])
    }

    /// " is not your default web browser." shows until the app is the default browser or the notice is dismissed
    func testTheDefaultBrowserNoticeShowsUntilDismissedOrDefault() {
        let f = Fixture(defaultBrowser: false)
        f.render(snapshot(pane: .general))
        XCTAssertEqual(f.view("defaultBrowserNotice", NSTextField.self)?.stringValue, "\(Product.name) is not your default web browser.")
        var dismissed = GeneralSettings.default
        dismissed.defaultBrowserPromptDismissed = true
        f.render(snapshot(pane: .general, general: dismissed))
        XCTAssertNil(f.view("defaultBrowserNotice", NSTextField.self))

        let g = Fixture(defaultBrowser: true)
        g.render(snapshot(pane: .general))
        XCTAssertNil(g.view("defaultBrowserNotice", NSTextField.self), "no notice once the app is the default browser")
        XCTAssertNotNil(g.view("warnBeforeQuitting", NSButton.self))
    }

    /// Max shows what launch found on PATH and what the choice resolves to
    func testTheMaxPaneShowsTheDetectedTools() {
        let f = Fixture()
        var max = MaxSettings.default
        max.provider = .auto
        f.render(snapshot(pane: .max, max: MaxSnapshot(settings: max, detected: [.codex], active: .codex)))
        XCTAssertEqual(f.view("aiStatus", NSTextField.self)?.stringValue, "Found on PATH: codex. Using codex.")
        XCTAssertEqual(f.view("aiProvider", NSPopUpButton.self)?.itemTitles, ["Off", "Automatic", "claude", "codex"])
        XCTAssertEqual(f.view("aiProvider", NSPopUpButton.self)?.titleOfSelectedItem, "Automatic")
        f.render(snapshot(pane: .max, max: MaxSnapshot(settings: max, detected: [], active: nil)))
        XCTAssertEqual(f.view("aiStatus", NSTextField.self)?.stringValue, "No local AI command-line tool found on PATH.")
    }

    /// Cmd+W and Esc close the window (when nothing inside took the key); other chords pass
    func testCommandWAndEscapeCloseTheWindow() {
        let f = Fixture()
        f.render(snapshot(pane: .links))
        func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1, windowNumber: f.window.windowNumber, context: nil,
                             characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        f.sent = []
        XCTAssertTrue(f.window.performKeyEquivalent(with: key(Key.w.code, "w", .command)))
        XCTAssertEqual(f.sent, [.settings(.closeWindow)])
        f.sent = []
        XCTAssertTrue(f.window.performKeyEquivalent(with: key(Key.escape.code, "\u{1b}", [])))
        XCTAssertEqual(f.sent, [.settings(.closeWindow)])
        f.sent = []
        XCTAssertFalse(f.window.performKeyEquivalent(with: key(Key.w.code, "W", [.command, .shift])))
        XCTAssertFalse(f.window.performKeyEquivalent(with: key(Key.comma.code, ",", .command)), "Cmd+, goes on to the menu (Preferences…)")
        XCTAssertEqual(f.sent, [])
    }
    /// "Warn before quitting": no question while it is off; while on, the answer decides, and "Quit, and don’t ask
    /// again" turns the setting off
    func testWarnBeforeQuittingAsksAndCanStopAsking() {
        final class Log { var sent: [Command] = [] }
        let log = Log()
        var asked: [NSAlert] = []
        let record: Dispatch = { log.sent.append($0) }
        XCTAssertTrue(QuitWarning.shouldQuit(.default, dispatch: record) { asked.append($0); return .init(quit: false, dontAskAgain: false) })
        XCTAssertTrue(asked.isEmpty, "no question while the setting is off")

        var on = GeneralSettings.default
        on.warnBeforeQuitting = true
        XCTAssertFalse(QuitWarning.shouldQuit(on, dispatch: record) { asked.append($0); return .init(quit: false, dontAskAgain: true) })
        XCTAssertEqual(log.sent, [], "Cancel keeps asking, whatever the box says")
        XCTAssertEqual(asked.first?.suppressionButton?.title, "Quit, and don’t ask again")
        XCTAssertEqual(asked.first?.showsSuppressionButton, true)
        XCTAssertEqual(asked.first?.buttons.map(\.title), ["Quit", "Cancel"])
        XCTAssertTrue(QuitWarning.shouldQuit(on, dispatch: record) { _ in .init(quit: true, dontAskAgain: false) })
        XCTAssertEqual(log.sent, [])
        XCTAssertTrue(QuitWarning.shouldQuit(on, dispatch: record) { _ in .init(quit: true, dontAskAgain: true) })
        XCTAssertEqual(log.sent, [.settings(.general(.warnBeforeQuitting(false)))])
    }
}
