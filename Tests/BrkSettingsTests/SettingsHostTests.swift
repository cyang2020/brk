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
                          advanced: AdvancedSettings = .default, profiles: [ProfileSettingsRow]? = nil) -> SettingsSnapshot {
        SettingsSnapshot(
            pane: pane, general: general,
            profiles: profiles ?? [ProfileSettingsRow(profile: ProfileRow(id: .default, name: "Default", icon: nil, spaceTitles: ["Personal", "Work"], isDefault: true),
                                          settings: .default)],
            links: links, routes: routes,
            spaces: [SpaceCandidate(id: personal, title: "Personal", icon: .none, isCurrent: false),
                     SpaceCandidate(id: work, title: "Work", icon: .none, isCurrent: false)],
            engines: SearchEngine.builtIn.map { SearchEngineCandidate(id: $0.id, name: $0.name, keyword: $0.keyword) },
            shortcuts: ActionID.allCases.map { action in
                let binding = KeyBindings.resolve(overrides: [:])[action]!
                return ShortcutRow(action: action, title: action.spec.title, menu: action.spec.menu,
                                   state: binding.state, source: binding.source, priority: binding.priority)
            }, max: max, advanced: advanced)
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
        func type(_ field: String, _ text: String, submit: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> [Command] {
            guard let textField: NSTextField = view(field) else { XCTFail("no field \(field)", file: file, line: line); return [] }
            sent = []
            textField.stringValue = text
            textField.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: textField))
            if submit { textField.sendAction(textField.action, to: textField.target) }
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

    func testMountedShortcutEditorIsScrollableAndRecordsChanges() throws {
        let f = Fixture()
        f.render(snapshot(pane: .shortcuts))
        func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
        }
        let recorders = descendants(f.host, ChordRecorderView.self)
        XCTAssertEqual(recorders.count, ActionID.allCases.count, "the real editor must be mounted")
        let scroller = try XCTUnwrap(descendants(f.host, NSScrollView.self).first)
        let document = try XCTUnwrap(scroller.documentView)
        XCTAssertGreaterThan(document.frame.height, scroller.contentSize.height)
        if let screen = f.window.screen {
            XCTAssertGreaterThanOrEqual(f.window.frame.minY, screen.visibleFrame.minY)
            XCTAssertLessThanOrEqual(f.window.frame.maxY, screen.visibleFrame.maxY)
        }
        let last = try XCTUnwrap(recorders.last)
        last.scrollToVisible(last.bounds)
        f.settle()
        XCTAssertFalse(last.visibleRect.isEmpty, "the final shortcut must be reachable")
        f.sent = []
        last.start()
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 1,
                                    windowNumber: f.window.windowNumber, context: nil, characters: "e",
                                    charactersIgnoringModifiers: "e", isARepeat: false, keyCode: Key.e.code)!
        XCTAssertTrue(last.handle(event))
        XCTAssertEqual(f.sent.count, 1)
        guard case .settings(.shortcuts(.setChord(_, KeyChord([.command, .option], .e))))? = f.sent.first else {
            return XCTFail("the mounted recorder did not dispatch its chord: \(f.sent)")
        }
        last.start()
        f.render(snapshot(pane: .general))
        XCTAssertFalse(last.isRecording, "changing pane releases the recorder's keyboard monitor")
        XCTAssertFalse(f.window.firstResponder === last)
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

    /// Drives F3's mounted native text fields and pop-ups. SwiftUI identifiers belong to its accessibility
    /// elements rather than these AppKit views, so the controls are selected by their displayed values.
    func testTheLinksPaneEditsAirTrafficControlRoutes() throws {
        let f = Fixture()
        let route = LinkRoute(id: spotify, pattern: "open.spotify.com", destination: .space(personal))
        f.render(snapshot(pane: .links, routes: [LinkRouteRow(route: route, destinationTitle: "Personal")]))
        func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
        }
        let destinations = descendants(f.host, NSPopUpButton.self).filter { $0.itemTitles.contains("Most Recent Space") }
        XCTAssertEqual(destinations.count, 2, "default and new route destinations; existing rows build their borderless menus on open")

        let fields = descendants(f.host, NSTextField.self).filter { $0.isEditable }
        let pattern = try XCTUnwrap(fields.first { $0.stringValue == "open.spotify.com" })
        f.sent = []
        pattern.stringValue = "spotify.com"
        pattern.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: pattern))
        f.settle()
        XCTAssertEqual(f.sent, [.settings(.links(.updateRoute(LinkRoute(id: spotify, pattern: "spotify.com", destination: .space(personal)))))])

        let draft = try XCTUnwrap(fields.first { $0.stringValue.isEmpty })
        f.sent = []
        draft.stringValue = "news.ycombinator.com"
        draft.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: draft))
        f.settle()
        XCTAssertEqual(f.sent, [], "typing a draft must not create a route")
        draft.sendAction(draft.action, to: draft.target)
        f.settle()
        guard case .settings(.links(.addRoute(let added)))? = f.sent.first else { return XCTFail("Return did not add the route: \(f.sent)") }
        XCTAssertEqual(added.pattern, "news.ycombinator.com")
        XCTAssertEqual(added.destination, .mostRecentSpace)
        XCTAssertFalse(added.id.rawValue.isEmpty)

        f.sent = []
        let fallback = try XCTUnwrap(destinations.first)
        fallback.selectItem(withTitle: "Little Arc")
        fallback.menu?.performActionForItem(at: fallback.indexOfSelectedItem)
        f.settle()
        XCTAssertEqual(f.sent, [.settings(.links(.defaultRoute(.littleArc)))])
    }

    func testProfilesEditorCreatesRenamesAndProtectsDefaultProfile() throws {
        let f = Fixture()
        f.render(snapshot(pane: .profiles))
        XCTAssertEqual(f.view("createProfile", NSButton.self)?.isEnabled, false)
        XCTAssertEqual(f.view("deleteProfile-default", NSButton.self)?.isEnabled, false)
        XCTAssertEqual(f.view("deleteUnusedProfiles", NSButton.self)?.isEnabled, false)
        XCTAssertEqual(f.type("newProfileName", "Work", submit: false), [])
        f.settle()
        XCTAssertEqual(f.click("createProfile"), [.profile(.create(name: "Work", icon: nil))])
        XCTAssertEqual(f.type("newProfileName", "Via Return"), [.profile(.create(name: "Via Return", icon: nil))])
        XCTAssertEqual(f.type("profileName-default", "Personal"), [.profile(.rename(.default, name: "Personal"))])
    }

    func testProfileSettingsStayScopedAndDownloadsCanReturnToDefault() {
        let f = Fixture()
        let id = ProfileID("work")
        var settings = ProfileSettings.default
        settings.downloadsDirectory = "/Users/me/Inbox"
        settings.promptForDownloadLocation = true
        let row = ProfileSettingsRow(profile: ProfileRow(id: id, name: "Work", icon: nil, spaceTitles: [], isDefault: false), settings: settings)
        f.render(snapshot(pane: .profiles, profiles: [snapshot(pane: nil).profiles[0], row]))
        XCTAssertEqual(f.pick("autoArchive-work", "7 days"), [.settings(.profile(id, .autoArchive(.sevenDays)))])
        XCTAssertEqual(f.pick("searchEngine-work", "Bing"), [.settings(.profile(id, .searchEngine(SearchEngineID("bing"))))])
        XCTAssertEqual(f.pick("downloadLocation-work", "Use Downloads"),
                       [.settings(.profile(id, .downloadsDirectory(nil))), .settings(.profile(id, .promptForDownloadLocation(false)))])
        XCTAssertEqual(f.view("deleteProfile-work", NSButton.self)?.isEnabled, true)
        XCTAssertEqual(f.view("deleteUnusedProfiles", NSButton.self)?.isEnabled, true)
        XCTAssertEqual(f.click("deleteProfile-default"), [])
    }

    func testProfileNameCommitsFromTheNativeFieldEditor() throws {
        let f = Fixture()
        f.render(snapshot(pane: .profiles))
        let field = try XCTUnwrap(f.view("profileName-default", NSTextField.self))
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("Personal", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        f.settle()
        XCTAssertEqual(f.sent, [.profile(.rename(.default, name: "Personal"))])
    }

    func testEscapeCancelsProfileDeletionWithoutClosingSettings() throws {
        let f = Fixture()
        let row = ProfileSettingsRow(profile: ProfileRow(id: ProfileID("unused"), name: "Unused", icon: nil,
                                                         spaceTitles: [], isDefault: false), settings: .default)
        f.render(snapshot(pane: .profiles, profiles: [snapshot(pane: nil).profiles[0], row]))
        f.window.orderFront(nil)
        defer { f.window.orderOut(nil) }
        XCTAssertEqual(f.click("deleteProfile-unused"), [])
        f.settle()
        let sheet = try XCTUnwrap(f.window.attachedSheet, "the mounted editor presents its confirmation")
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                                      windowNumber: sheet.windowNumber, context: nil, characters: "\u{1b}",
                                      charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: Key.escape.code)!
        _ = sheet.performKeyEquivalent(with: escape)
        f.settle()
        XCTAssertEqual(f.sent, [], "cancel must not delete a profile or close Settings")
        XCTAssertNil(f.window.attachedSheet)
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
