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

        /// Clicks a checkbox, switch, button or row and returns what it sent.
        func click(_ field: String, file: StaticString = #filePath, line: UInt = #line) -> [Command] {
            guard let control: NSControl = view(field) else { XCTFail("no control \(field)", file: file, line: line); return [] }
            sent = []
            if let toggle = control as? NSSwitch {
                toggle.state = toggle.state == .on ? .off : .on
                toggle.sendAction(toggle.action, to: toggle.target)
            } else {
                control.performClick(nil)
            }
            settle()
            return sent
        }

        func isOn(_ field: String) -> Bool? {
            (view(field) as NSSwitch?).map { $0.state == .on } ?? (view(field) as NSButton?).map { $0.state == .on }
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

    func testMountedShortcutEditorIsScrollableAndRecordsChanges() throws {
        let f = Fixture()
        f.render(snapshot(pane: .shortcuts))
        func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
        }
        let recorders = descendants(f.host, ChordRecorderView.self)
        XCTAssertEqual(recorders.count, ActionID.allCases.count, "the real editor must be mounted")
        // The list scrolls inside its box; the window keeps Arc's one size.
        func nested<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
            ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { nested($0, type) }
        }
        let scroller = try XCTUnwrap(nested(f.host, NSScrollView.self).last { recorders.first!.isDescendant(of: $0) })
        let document = try XCTUnwrap(scroller.documentView)
        XCTAssertGreaterThan(document.frame.height, scroller.contentSize.height)
        XCTAssertEqual(f.window.frame.size, Metrics.settings.windowSize.value, "the window does not grow with the list")
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

    func testProfilesEditorCreatesRenamesAndProtectsDefaultProfile() throws {
        let f = Fixture()
        f.render(snapshot(pane: .profiles))
        XCTAssertEqual(f.view("deleteProfile-default", NSButton.self)?.isEnabled, false)
        XCTAssertNil(f.view("newProfileName"), "+ asks for the name")
        XCTAssertEqual(f.click("addProfile"), [])
        XCTAssertEqual(f.view("createProfile", NSButton.self)?.isEnabled, false)
        XCTAssertEqual(f.type("newProfileName", "Work", submit: false), [])
        f.settle()
        XCTAssertEqual(f.click("createProfile"), [.profile(.create(name: "Work", icon: nil))])
        XCTAssertEqual(f.click("addProfile"), [])
        XCTAssertEqual(f.type("newProfileName", "Via Return"), [.profile(.create(name: "Via Return", icon: nil))])
        XCTAssertNil(f.view("profileName-default"), "the pencil starts a rename")
        XCTAssertEqual(f.click("editProfile"), [])
        XCTAssertEqual(f.type("profileName-default", "Personal"), [.profile(.rename(.default, name: "Personal"))])
        XCTAssertTrue(ProfilesPane.unused(snapshot(pane: nil).profiles).isEmpty, "the default profile is never unused")
    }

    func testProfileNameCommitsFromTheNativeFieldEditor() throws {
        let f = Fixture()
        f.render(snapshot(pane: .profiles))
        _ = f.click("editProfile")
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
        XCTAssertEqual(f.click("profileRow-unused"), [])
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

    /// Air Traffic Control is Arc's sheet over the Links pane (Q06-a): New Route, the two-line rows (match pop-up,
    /// text, ⊖ / Open in pop-up), Default, ×. Driven through the sheet's own controls.
    func testAirTrafficControlIsASheetOverTheLinksPane() throws {
        let f = Fixture()
        let route = LinkRoute(id: spotify, pattern: "meet.google.com", destination: .mostRecentSpace, match: .contains)
        f.render(snapshot(pane: .links, routes: [LinkRouteRow(route: route, destinationTitle: "Most Recent Space")]))
        f.window.orderFront(nil)
        defer { f.window.orderOut(nil); f.window.close() }
        XCTAssertEqual(f.click("airTrafficControl"), [], "the button only opens the sheet")
        for _ in 0..<10 where f.window.attachedSheet == nil { f.settle() }
        let sheet = try XCTUnwrap(f.window.attachedSheet, "the sheet is attached to the settings window")
        XCTAssertLessThanOrEqual(abs(sheet.frame.width - 508), 2, "Arc's 508-point sheet")
        XCTAssertLessThanOrEqual(abs(sheet.frame.height - 500), 2, "Arc's 500-point sheet")
        func find<T: NSView>(_ field: String, _ type: T.Type = T.self) -> T? {
            func walk(_ view: NSView) -> NSView? {
                if view.accessibilityIdentifier() == ViewID.settingsField(field).identifier { return view }
                for child in view.subviews { if let found = walk(child) { return found } }
                return nil
            }
            return sheet.contentView.flatMap(walk) as? T
        }
        func sent(_ action: () -> Void) -> [Command] { f.sent = []; action(); f.settle(); return f.sent }
        let id = spotify.rawValue

        let match = try XCTUnwrap(find("route-\(id)-match", NSPopUpButton.self))
        XCTAssertEqual(match.itemTitles, ["Contains", "Matches"])
        XCTAssertEqual(match.titleOfSelectedItem, "Contains")
        XCTAssertEqual(sent { match.selectItem(withTitle: "Matches"); match.sendAction(match.action, to: match.target) },
                       [.settings(.links(.updateRoute(LinkRoute(id: spotify, pattern: "meet.google.com", destination: .mostRecentSpace, match: .matches))))])

        let pattern = try XCTUnwrap(find("route-\(id)-pattern", NSTextField.self))
        XCTAssertEqual(pattern.stringValue, "meet.google.com")
        XCTAssertEqual(sent {
            pattern.stringValue = "zoom.us"
            pattern.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: pattern))
        }, [.settings(.links(.updateRoute(LinkRoute(id: spotify, pattern: "zoom.us", destination: .mostRecentSpace, match: .contains))))])

        let destination = try XCTUnwrap(find("route-\(id)-destination", NSPopUpButton.self))
        XCTAssertEqual(destination.itemTitles, ["Personal", "Work", "", "Little Arc", "Most Recent Space"])
        XCTAssertEqual(destination.titleOfSelectedItem, "Most Recent Space")
        XCTAssertEqual(sent { destination.selectItem(withTitle: "Work"); destination.sendAction(destination.action, to: destination.target) },
                       [.settings(.links(.updateRoute(LinkRoute(id: spotify, pattern: "meet.google.com", destination: .space(work), match: .contains))))])

        let fallback = try XCTUnwrap(find("defaultRoute", NSPopUpButton.self))
        XCTAssertEqual(fallback.titleOfSelectedItem, "Little Arc", "the default follows 'Links from other apps open in Little Arc'")
        XCTAssertEqual(sent { fallback.selectItem(withTitle: "Most Recent Space"); fallback.sendAction(fallback.action, to: fallback.target) },
                       [.settings(.links(.defaultRoute(.mostRecentSpace)))])

        guard case .settings(.links(.addRoute(let added)))? = sent({ (find("route-new") as NSControl?)?.performClick(nil) }).first else {
            return XCTFail("New Route did not add a route")
        }
        XCTAssertEqual(added.pattern, "")
        XCTAssertEqual(added.match, .contains)
        XCTAssertEqual(added.destination, .mostRecentSpace)
        XCTAssertEqual(sent { (find("route-\(id)-remove") as NSControl?)?.performClick(nil) }, [.settings(.links(.removeRoute(spotify)))])

        // The next snapshot has the empty row New Route added; × drops it and closes the sheet.
        let empty = LinkRoute(id: github, pattern: "", destination: .mostRecentSpace, match: .contains)
        f.render(snapshot(pane: .links, routes: [LinkRouteRow(route: route, destinationTitle: "Most Recent Space"),
                                                 LinkRouteRow(route: empty, destinationTitle: "Most Recent Space")]))
        XCTAssertNotNil(find("route-\(github.rawValue)-pattern", NSTextField.self), "the new row is in the sheet")
        XCTAssertEqual(sent { (find("routes-close") as NSControl?)?.performClick(nil) }, [.settings(.links(.removeRoute(github)))])
        for _ in 0..<10 where f.window.attachedSheet != nil { f.settle() }
        if let open = f.window.attachedSheet { f.window.endSheet(open) }
        XCTAssertNil(f.window.attachedSheet, "× closes the sheet")
    }

    func testProfileSettingsStayScopedAndDownloadsCanReturnToDefault() {
        let f = Fixture()
        let id = ProfileID("work")
        var settings = ProfileSettings.default
        settings.downloadsDirectory = "/Users/me/Inbox"
        settings.promptForDownloadLocation = true
        let row = ProfileSettingsRow(profile: ProfileRow(id: id, name: "Work", icon: nil, spaceTitles: [], isDefault: false), settings: settings)
        let rows = [snapshot(pane: nil).profiles[0], row]
        f.render(snapshot(pane: .profiles, profiles: rows))
        XCTAssertEqual(f.click("deleteProfile-default"), [], "the default profile cannot be deleted")
        XCTAssertNil(f.view("autoArchive-work"), "the list's selection decides whose settings are shown")
        XCTAssertEqual(f.click("profileRow-work"), [])
        XCTAssertEqual(f.pick("autoArchive-work", "7 days"), [.settings(.profile(id, .autoArchive(.sevenDays)))])
        XCTAssertEqual(f.pick("searchEngine-work", "Bing"), [.settings(.profile(id, .searchEngine(SearchEngineID("bing"))))])
        XCTAssertEqual(f.pick("downloadLocation-work", "Use Downloads"),
                       [.settings(.profile(id, .downloadsDirectory(nil))), .settings(.profile(id, .promptForDownloadLocation(false)))])
        XCTAssertEqual(f.view("deleteProfile-work", NSButton.self)?.isEnabled, true)
        XCTAssertEqual(ProfilesPane.unused(rows).map(\.id), [id])
        XCTAssertEqual(f.click("searchSettings-work"), [])
        XCTAssertNotNil(f.find("settings-pane-profiles"))
        XCTAssertEqual(f.click("subpageBack"), [])
        XCTAssertEqual(f.click("profileData-clearBrowsingData-work"), [])
        XCTAssertEqual(f.view("clearProfileData-work", NSButton.self)?.isEnabled, true, "Clear Browsing Data is a sub-page")
    }

    /// Max is on while any feature uses the tool, Brk's three in More Settings… too. With only those left on, the button
    /// offers Turn Off Max, which does what it says, not a Turn On Max that changes nothing.
    func testMaxPaneCountsTheMoreSettingsFeaturesAsOn() {
        let f = Fixture()
        var max = MaxSettings.default
        max.features = Dictionary(uniqueKeysWithValues: AIFeature.allCases.map { ($0, $0.inMoreSettings) })
        f.render(snapshot(pane: .max, max: MaxSnapshot(settings: max, detected: [.claude], active: .claude)))
        XCTAssertEqual(f.click("enableMax"), [.settings(.max(.enable(false)))])
    }

    /// Advanced's More Settings… picks the local tool, shows what launch found on PATH and what the choice resolves
    /// to, and switches Brk's three AI features that Arc's Max pane does not list
    func testMoreSettingsShowsTheDetectedTools() {
        let f = Fixture()
        var max = MaxSettings.default
        max.provider = .auto
        f.render(snapshot(pane: .advanced, max: MaxSnapshot(settings: max, detected: [.codex], active: .codex)))
        _ = f.click("moreSettings")
        XCTAssertEqual(f.pick("aiProvider", "codex"), [.settings(.max(.provider(.codex)))])
        XCTAssertEqual(f.click("askPage"), [.settings(.max(.feature(.askPage, true)))])
        XCTAssertEqual(f.click("browse"), [.settings(.max(.feature(.browse, true)))])
        XCTAssertEqual(f.click("translation"), [.settings(.max(.feature(.translation, true)))])
        XCTAssertEqual(f.view("aiStatus", NSTextField.self)?.stringValue, "Found on PATH: codex. Using codex.")
        XCTAssertEqual(f.view("aiProvider", NSPopUpButton.self)?.itemTitles, ["Off", "Automatic", "claude", "codex", "gemini", "cursor-agent", "opencode"])
        XCTAssertEqual(f.view("aiProvider", NSPopUpButton.self)?.titleOfSelectedItem, "Automatic")
        f.render(snapshot(pane: .advanced, max: MaxSnapshot(settings: max, detected: [], active: nil)))
        XCTAssertEqual(f.view("aiStatus", NSTextField.self)?.stringValue, "No local AI command-line tool found on PATH.")
    }
}
