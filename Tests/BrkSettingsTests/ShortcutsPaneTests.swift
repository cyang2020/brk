import AppKit
import BrkBase
@testable import BrkDomain
import SwiftUI
import XCTest
@testable import BrkSettings

/// Owner: F4. The Shortcuts pane content: the recorder turns a key press into `.setChord`, the rows say what
/// routing does (conflicts by name, macOS's own chords), and the list is sectioned and filterable.
@MainActor
final class ShortcutsPaneTests: XCTestCase {
    private func rows(_ overrides: [ActionID: KeyOverride] = [:]) -> [ShortcutRow] {
        let resolved = KeyBindings.resolve(overrides: overrides)
        return ActionID.allCases.map { a in
            ShortcutRow(action: a, title: a.spec.title, menu: a.spec.menu, state: resolved[a]!.state, source: resolved[a]!.source, priority: resolved[a]!.priority)
        }
    }

    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    /// a chord with ⌘, ⌃ or ⌥ (or F12) is recorded by physical key; Esc cancels, Delete removes, a plain letter or a
    /// key the table cannot name is refused
    func test_theRecorderReadsAPressAsArcsTableWould() {
        XCTAssertEqual(ChordRecorderView.interpret(keyCode: Key.e.code, flags: .command), .record(KeyChord(.command, .e)))
        for supported in [Key.b, .v, .x] {
            XCTAssertEqual(ChordRecorderView.interpret(keyCode: supported.code, flags: .command), .record(KeyChord(.command, supported)))
        }
        XCTAssertEqual(ChordRecorderView.interpret(keyCode: Key.equals.code, flags: [.control, .shift, .capsLock]), .record(KeyChord([.control, .shift], .equals)))
        XCTAssertEqual(ChordRecorderView.interpret(keyCode: Key.f12.code, flags: []), .record(KeyChord([], .f12)))
        XCTAssertEqual(ChordRecorderView.interpret(keyCode: 53, flags: []), .cancel)
        XCTAssertEqual(ChordRecorderView.interpret(keyCode: 51, flags: []), .clear)
        XCTAssertEqual(ChordRecorderView.interpret(keyCode: Key.e.code, flags: .shift), .refuse(ShortcutsCopy.needsModifier))
        XCTAssertEqual(ChordRecorderView.interpret(keyCode: 10, flags: .command), .refuse(ShortcutsCopy.unsupportedKey), "The ISO section key has no Key case")
    }

    /// clicking starts a recording; the next accepted press is dispatched once and ends it; a refused press keeps it
    /// going with the note; Delete dispatches the unset; nothing is taken once it ended
    func test_recordingDispatchesTheChordOnce() {
        let view = ChordRecorderView(frame: CGRect(x: 0, y: 0, width: 132, height: 24))
        var recorded: [KeyChord?] = []
        view.record = { recorded.append($0) }
        view.state = .valid(KeyChord(.command, .t))
        XCTAssertEqual(view.accessibilityLabel(), "⌘T")
        XCTAssertFalse(view.handle(key(Key.e.code, .command)), "not recording: the press goes on to the app")
        view.start()
        XCTAssertEqual(view.accessibilityLabel(), ShortcutsCopy.recording)
        XCTAssertTrue(view.handle(key(Key.e.code, [])))
        XCTAssertTrue(view.isRecording)
        XCTAssertEqual(view.accessibilityLabel(), ShortcutsCopy.needsModifier)
        XCTAssertTrue(view.handle(key(Key.e.code, .command)))
        XCTAssertFalse(view.isRecording)
        XCTAssertEqual(recorded, [KeyChord(.command, .e)])
        view.start()
        view.handle(key(51, []))
        XCTAssertEqual(recorded, [KeyChord(.command, .e), nil])
        view.start()
        view.handle(key(53, []))
        XCTAssertEqual(recorded.count, 2, "Esc records nothing")
        XCTAssertFalse(view.isRecording)
    }

    func test_theRecorderTakesCommandEventsAndStopsWhenFocusLeaves() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let view = ChordRecorderView(frame: CGRect(x: 0, y: 0, width: 132, height: 24))
        window.contentView = view
        window.orderFront(nil)
        defer { view.stop(); window.orderOut(nil) }
        var recorded: [KeyChord?] = []
        view.record = { recorded.append($0) }
        view.start()
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 1,
                                    windowNumber: window.windowNumber, context: nil, characters: "e",
                                    charactersIgnoringModifiers: "e", isARepeat: false, keyCode: Key.e.code)!
        NSApp.sendEvent(event)
        XCTAssertEqual(recorded, [KeyChord(.command, .e)])
        XCTAssertFalse(view.isRecording)
        view.start()
        XCTAssertTrue(view.isRecording)
        window.makeFirstResponder(nil)
        XCTAssertFalse(view.isRecording, "a recorder that loses focus must release the event monitor")
    }

    /// the row notes: Arc's conflict sentence with the other action's name, and the system-shortcut note
    func test_rowNotesNameTheConflictAndSystemChords() {
        let clash = rows([.reloadPage: KeyOverride(chord: KeyChord(.command, .t), priority: nil)])
        let reload = clash.first { $0.action == .reloadPage }!
        XCTAssertEqual(ShortcutsCopy.conflict(reload, among: clash), "⌘T is already in use by New Tab…")
        let three = rows([.reloadPage: KeyOverride(chord: KeyChord(.command, .t), priority: nil),
                          .newWindow: KeyOverride(chord: KeyChord(.command, .t), priority: nil)])
        XCTAssertEqual(ShortcutsCopy.conflict(three.first { $0.action == .newTab }!, among: three), "⌘T is already in use by New Window and one other action")
        XCTAssertNil(ShortcutsCopy.conflict(clash.first { $0.action == .newWindow }!, among: clash))
        XCTAssertEqual(ShortcutsCopy.priority(.pageThenApp), "Press this shortcut once to use the website's shortcut. Press it twice to use \(Product.name)'s shortcut.")
    }

    /// changed shortcuts first, then the defaults by name as Arc sorts them; the filter matches titles and shortcuts
    func test_sectionsPutTheUsersShortcutsFirstAndFilter() {
        let list = rows([.reloadPage: KeyOverride(chord: KeyChord([.option, .command], .r), priority: nil)])
        let sections = ShortcutsPane.sections(list, filter: "")
        XCTAssertEqual(sections.map(\.title), [ShortcutsCopy.customized, ShortcutsCopy.defaults])
        XCTAssertEqual(sections.first?.rows.map(\.action), [.reloadPage])
        XCTAssertEqual(sections.flatMap(\.rows).count, ActionID.allCases.count)
        let titles = sections[1].rows.map(ShortcutsCopy.title(of:))
        XCTAssertEqual(titles, titles.sorted { $0.compare($1, options: .caseInsensitive) == .orderedAscending }, "Default Shortcuts by name")
        XCTAssertEqual(["Capture Full Page", "Capture in Portrait Mode", "Capture…"].sorted { $0.compare($1, options: .caseInsensitive) == .orderedAscending },
                       ["Capture Full Page", "Capture in Portrait Mode", "Capture…"], "Arc's order in P38-e")
        XCTAssertEqual(Set(ShortcutsPane.sections(list, filter: "⌘T").flatMap(\.rows).map(\.action)), [.newTab, .reopenLastClosedTab], "⌘T and ⇧⌘T")
        let refresh = ShortcutsPane.sections(list, filter: "refresh").flatMap(\.rows).map(\.action)
        XCTAssertEqual(refresh.first, .reloadPage, "the customized one first")
        XCTAssertEqual(Set(refresh), [.reloadPage, .forceReloadPage, .clearCookies, .clearCache])
        XCTAssertEqual(ShortcutsPane.sections(rows(), filter: "").map(\.title), [ShortcutsCopy.defaults], "nothing customized")
    }

    /// rendered for real (SwiftUI in an NSHostingView): one shortcut field per action, each showing its shortcut
    func test_thePaneShowsAFieldPerActionWithItsShortcut() {
        let list = rows([.newTab: KeyOverride(chord: KeyChord(.command, .e), priority: nil)])
        let host = NSHostingView(rootView: ShortcutsPane(rows: list, dispatch: { _ in }, height: 6000).frame(width: 700))
        host.frame = CGRect(x: 0, y: 0, width: 700, height: 6000)
        host.layoutSubtreeIfNeeded()
        func recorders(_ view: NSView) -> [ChordRecorderView] { (view as? ChordRecorderView).map { [$0] } ?? view.subviews.flatMap(recorders) }
        let fields = recorders(host)
        XCTAssertEqual(fields.count, ActionID.allCases.count)
        XCTAssertEqual(fields.first?.accessibilityLabel(), "⌘E", "the customized New Tab… comes first")
        XCTAssertTrue(fields.contains { $0.accessibilityLabel() == "⇧⌘N" }, "New Incognito Window")
        XCTAssertTrue(fields.contains { $0.accessibilityLabel() == ShortcutsCopy.record }, "unset rows offer to record")
        XCTAssertTrue(fields.contains { ($0.subviews.first as? NSTextField)?.stringValue == ShortcutsCopy.unsetCap }, "and show Arc's ---")
    }
}
