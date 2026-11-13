import BrkBase
import CoreGraphics
import Foundation
import XCTest
@testable import BrkDomain

/// Every command the app can send, in every kind of window, and every shortcut in every place the keyboard can be
/// (the full audit of 2026-11-12 found 408 user steps under no test at all). Each command and key is reduced from
/// the same rich state, never from the previous one's result, so one rule's quirk cannot hide another's. Afterwards
/// the state must hold the cross-entity rules `normalize` keeps (normalize finds nothing left to repair, plus the
/// checks in `Fixture.violations`), `project` must draw every open window, and a changed saved part must restore
/// without repairs and without a private page in it.
///
/// The commands: one sample of every case (`CommandInventory`), every menu item's, shortcut's and command bar row's
/// command (`ActionID`), and the commands of every context menu the window's rows, spaces and conversations open
/// (built by the domain, with real ids). The windows: a standard window with Favorites, a Pinned folder, a split,
/// a second space, an archive, a download, an Easel and an AI conversation; an incognito, a Little Arc or a blank
/// window beside it; a first launch's single window; and the closed last standard window (`Session.closedWindow`),
/// which the menus, the Dock and the Settings window send to, while another window is open and while none is.
///
/// The first two tests take over 2 s: about 3,100 commands and 1,200 key presses are reduced, and every new state is
/// projected (about 2 ms on these states, 40 % of it the Settings window's shortcut table), which comes to about 6 s
/// and 2 s on a Mac mini M1. They replace ReduceSpecTests' reduce-is-total test (3.7 s), which reduced the inventory
/// alone, one command after another.
final class CommandSweepTests: XCTestCase {
    /// The sweep's fixture, built once.
    private static let fixture = Fixture()

    func test_everyCommandInEveryWindowKind() {
        let f = Self.fixture
        var failures: [(input: String, what: String)] = []
        for kind in Fixture.Kind.allCases {
            let (state, window) = f.base(kind)
            failures += f.violations(state, in: kind).map { ("\(kind) before any command", $0) }
            for command in f.commands(for: kind) {
                let t = reduce(state, .user(window, command), f.ctx)
                guard t.changed || !t.effects.isEmpty else { continue }
                failures += f.violations(t, from: state, in: kind).map { ("\(kind) \(command)", $0) }
            }
        }
        // Page, download, AI and system events: what arrives on its own while the windows are as above.
        for kind in [Fixture.Kind.standard, .closedWithOthersOpen] {
            let (state, _) = f.base(kind)
            for event in CommandInventory.events {
                let t = reduce(state, .system(event), f.ctx)
                guard t.changed || !t.effects.isEmpty else { continue }
                failures += f.violations(t, from: state, in: kind).map { ("\(kind) \(event)", $0) }
            }
        }
        XCTAssertTrue(failures.isEmpty, summary(failures))
    }

    /// Where the keyboard is decides the stage a key arrives in: CEF before and after a page (a text field in the page
    /// marks the press editable), the window's key-equivalent path while a native view has focus (the command bar's
    /// field and the AI composer are editable text; the sidebar, the Library and a capture's selection are not).
    func test_everyShortcutInEveryFocusState() {
        let f = Self.fixture
        let map = KeyRouting.defaultMap
        var failures: [(input: String, what: String)] = []
        var pressID: UInt64 = 1
        for focus in Fixture.Focus.allCases {
            let (state, window, kind, page, editable) = f.focused(focus)
            if focus == .capture { XCTAssertNotNil(state.session.windows[window]?.capture, "no capture to press keys in") }
            if !focus.sweptByCommands { failures += f.violations(state, in: kind).map { ("\(focus) before any key", $0) } }
            for (chord, entry) in map.entries.sorted(by: { $0.key.description < $1.key.description }) {
                pressID += 1
                let press = KeyPress(chord: chord, phase: .down, isRepeat: false, editableFieldFocused: editable)
                let label = "\(focus) \(chord) (\(entry.action))"
                var t = reduce(state, .key(window, KeyInput(press: press, stage: page ? .beforePage : .menu, pressID: PressID(raw: pressID))), f.ctx)
                if page {
                    switch entry.priority {
                    case .app: if !t.keyHandled { failures.append((label, "an app shortcut went to the page")) }
                    case .page: if t.keyHandled { failures.append((label, "a page-first shortcut was taken before the page")) }
                    case .pageThenApp: break
                    }
                    // The page did not consume it: the second delivery of the same press.
                    if !t.keyHandled { t = reduce(t.state, .key(window, KeyInput(press: press, stage: .afterPage, pressID: PressID(raw: pressID))), f.ctx) }
                } else if entry.action.standardEdit != nil, t.keyHandled {
                    failures.append((label, "an Edit menu key was taken from AppKit's text editing"))
                }
                // A key runs its command from the state it is pressed in; the states the command sweep starts from were
                // checked there, saved results included.
                guard !focus.sweptByCommands, t.changed || !t.effects.isEmpty else { continue }
                failures += f.violations(t, from: state, in: kind, file: false).map { (label, $0) }
            }
        }
        XCTAssertTrue(failures.isEmpty, summary(failures))
    }

    /// Every main-menu item, Dock and status-item row, shortcut and command bar row is an `ActionID` (the app has no
    /// other list), and the sweep reduces each one's command in every window kind; an extension can never be given a
    /// chord Brk routes, so no extension shortcut runs a command the sweep does not know.
    func test_everyMenuItemAndShortcutIsInTheSweep() {
        let f = Self.fixture
        for kind in Fixture.Kind.allCases {
            let swept = Set(f.commands(for: kind))
            for action in ActionID.allCases {
                XCTAssertTrue(swept.contains(action.spec.command), "\(kind): \(action) is not swept")
                XCTAssertTrue(swept.contains(action.spec.barCommand), "\(kind): \(action)'s command bar row is not swept")
            }
        }
        let routed = KeyRouting.defaultMap.entries.keys.filter { chord in
            !chord.modifiers.intersection([.command, .control]).isEmpty && chord.key.menuKeyEquivalent.range(of: "^[a-z0-9]$", options: .regularExpression) != nil
        }
        XCTAssertFalse(routed.isEmpty)
        for chord in routed {
            XCTAssertNotNil(ExtensionShortcuts.error(for: chord, extensionID: "ext", command: "run", catalog: [], overrides: [:]),
                            "an extension may take \(chord), which runs \(KeyRouting.defaultMap.lookup(chord)!.action)")
        }
    }
}

/// The failures grouped by what went wrong (ids left out), most frequent first, each with the first input it happened to.
private func summary(_ failures: [(input: String, what: String)]) -> String {
    var groups: [String: [(input: String, what: String)]] = [:]
    for failure in failures {
        groups[failure.what.replacingOccurrences(of: #"d\d+-\d+"#, with: "<id>", options: .regularExpression), default: []].append(failure)
    }
    return "\(failures.count) failures:\n" + groups.sorted { $0.value.count > $1.value.count }
        .map { "\($0.value.count) × \($0.key.prefix(300))\n    first: \($0.value[0].input.prefix(300))" }.joined(separator: "\n")
}

/// The rich states and the checks. A class, so the one instance's id counter is shared by every reduction.
private final class Fixture: @unchecked Sendable {
    enum Kind: CaseIterable { case fresh, standard, incognito, little, blank, closedWithOthersOpen, closedAlone }
    /// Where the keyboard is. A Peek's page and a capture being selected are where the audit's ⌘T, ⌘L and Esc steps were
    /// never pressed.
    enum Focus: CaseIterable {
        case page, pageTextField, sidebar, commandBar, library, aiComposer, littleArc, peek, capture

        /// The state is one the command sweep starts from, so a key there runs its command from a state already swept.
        var sweptByCommands: Bool { [.page, .pageTextField, .littleArc].contains(self) }
    }

    /// The standard window alone, and with each other kind beside it (one at a time: each window drawn costs every
    /// projection about a millisecond). The closed window has the incognito window beside it, or nothing.
    let rich, withIncognito, withLittle, withBlank: AppState
    /// A first launch: one space, one window, one tab (single things are where "the last one" rules bite).
    let fresh: AppState
    let closedWithOthersOpen, closedAlone: AppState
    let standard: WindowID, incognito: WindowID, little: WindowID, blank: WindowID
    static let privateHost = "private.example.com"
    private let ids: Counter
    let now: Instant
    var ctx: Context { Context(now: now, newID: ids.next, calendar: Driver.calendar) }
    private var projections = 0
    private var commandsByKind: [Kind: [Command]] = [:]

    init() {
        let ids = Counter(), now = T0.advanced(by: .seconds(3_600))
        self.ids = ids
        self.now = now
        fresh = Driver().state
        let d = Driver()
        standard = d.window
        let home = d.view.space.id
        d.page(d.todayIDs[0], .titleChanged("Fixture Home"))
        for feature in AIFeature.allCases { d.user(.settings(.max(.feature(feature, !AIFeature.basicLayer.contains(feature))))) }
        d.system(.aiProvidersDetected([.claude, .codex]))
        let favorite = d.open("fav.example.com")
        d.user(.item(.move(favorite, to: .into(parent: d.view.favorites.root, index: 0))))
        d.user(.item(.newFolder))
        let folder = d.pinnedIDs[0]
        d.user(.item(.rename(folder, title: "Reading")))
        let inFolder = d.open("folder.example.com")
        d.user(.item(.move(inFolder, to: .into(parent: folder, index: 0))))
        let pinned = d.open("pinned.example.com")
        d.user(.tab(.togglePin(.item(pinned))))
        let gone = d.open("gone.example.com")
        d.user(.tab(.close(.item(gone))))
        let downloading = d.open("download.example.com")
        d.download(downloading, DownloadID("fixture-download"), .receiving(TransferProgress(received: 0, total: 100)),
                   details: DownloadDetails(url: url("http://download.example.com/file.zip"), suggestedName: "file.zip"))
        d.download(downloading, DownloadID("fixture-download"), .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/fixture-file.zip"), bytes: 100))))
        d.user(.easel(.create))
        d.newSpace("Work")
        d.open("work.example.com")
        d.user(.space(.focus(home)))
        d.open("page2.example.com")
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("pane.example.com")))
        d.commitRequested()
        for case .ai(let id, _, _) in d.user(.assist(.ask("Which tab is cheapest?"))).effects {
            d.system(.aiResult(id, .text("The second one.")))
        }
        d.user(.assist(.dismiss))
        d.system(.window(d.window, .geometry(bounds: CGRect(x: 10, y: 20, width: 1400, height: 900), contentSize: CGSize(width: 1400, height: 872))))

        let opener = d.window
        let ctx = { Context(now: now, newID: ids.next, calendar: Driver.calendar) }
        // The engine's side of opening a page: its browser is created, the requested address commits and its document
        // is ready (captures, Boosts, Find and the site controls act on a ready document only).
        func settle(_ input: AppState) -> AppState {
            var s = input
            for spec in project(s, ProjectionContext(now: now, calendar: Driver.calendar)).pages {
                if s.session.live[spec.id]?.browser == nil, spec.initialURL != nil {
                    let token = BrowserToken(page: spec.id, generation: (s.session.generations[spec.id] ?? 0) + 1)
                    s = reduce(s, .system(.page(token, .browserCreated(spec.context, .unavailable))), ctx()).state
                }
                if let requested = s.session.live[spec.id]?.requestedURL, let token = s.session.live[spec.id]?.browser {
                    s = reduce(s, .system(.page(token, .committed(requested))), ctx()).state
                }
                let ready = if case .ready? = s.session.live[spec.id]?.document { true } else { false }
                if !ready, let token = s.session.live[spec.id]?.browser {
                    let document = DocumentToken(browser: token, sequence: 1)
                    for change in [DocumentAvailability.loading(document), .ready(document)] {
                        s = reduce(s, .system(.page(token, .documentChanged(change))), ctx()).state
                    }
                }
            }
            return s
        }
        let richState = settle(d.state)
        rich = richState
        func opening(_ command: Command, in s: AppState, then input: String?) -> (AppState, WindowID) {
            var next = reduce(s, .user(opener, command), ctx()).state
            let id = Set(next.doc.windows.keys).subtracting(s.doc.windows.keys).first!
            if let input { next = reduce(next, .user(id, .commandBar(.submit(input))), ctx()).state }
            return (settle(next), id)
        }
        let littleArc = Command.window(.newLittle(url("http://little.example.com/")))
        let privateWindow = opening(.window(.newIncognito), in: richState, then: Self.privateHost)
        let littleWindow = opening(littleArc, in: richState, then: nil)
        let blankWindow = opening(.window(.newBlank), in: richState, then: "blank.example.com")
        (withIncognito, incognito) = (privateWindow.0, privateWindow.1)
        (withLittle, little) = (littleWindow.0, littleWindow.1)
        (withBlank, blank) = (blankWindow.0, blankWindow.1)
        closedWithOthersOpen = reduce(privateWindow.0, .system(.window(opener, .closed)), ctx()).state
        closedAlone = reduce(richState, .system(.window(opener, .closed)), ctx()).state
        precondition(closedWithOthersOpen.session.closedWindow == standard && closedWithOthersOpen.doc.windows.count == 2
                     && closedAlone.session.closedWindow == standard && closedAlone.doc.windows.count == 1, "the closed window fixture")
    }

    func base(_ kind: Kind) -> (AppState, WindowID) {
        switch kind {
        case .fresh: (fresh, fresh.doc.windows.keys.sorted()[0])
        case .standard: (rich, standard)
        case .incognito: (withIncognito, incognito)
        case .little: (withLittle, little)
        case .blank: (withBlank, blank)
        case .closedWithOthersOpen: (closedWithOthersOpen, standard)
        case .closedAlone: (closedAlone, standard)
        }
    }

    /// The state with the keyboard in `focus`, the window the key goes to, whether a page has it (CEF's two stages)
    /// and whether the focused field takes text.
    func focused(_ focus: Focus) -> (AppState, WindowID, Kind, page: Bool, editable: Bool) {
        func after(_ command: Command) -> AppState { reduce(rich, .user(standard, command), ctx).state }
        switch focus {
        case .page: return (rich, standard, .standard, true, false)
        case .pageTextField: return (rich, standard, .standard, true, true)
        case .sidebar: return (after(.tabTools(.reveal)), standard, .standard, false, false)
        case .commandBar: return (after(.commandBar(.open(.newTab))), standard, .standard, false, true)
        case .library: return (after(.library(.open(nil))), standard, .standard, false, false)
        case .aiComposer: return (after(.assist(.togglePanel)), standard, .standard, false, true)
        case .littleArc: return (withLittle, little, .little, true, false)
        case .peek: return (after(.peek(.open(url("http://peeked.example.com/")))), standard, .standard, true, false)
        case .capture: return (after(.capture(.begin(.area))), standard, .standard, false, false)
        }
    }

    /// Every command for a window of `kind`, without repeats.
    func commands(for kind: Kind) -> [Command] {
        if let known = commandsByKind[kind] { return known }
        let (state, window) = base(kind)
        var all = CommandInventory.commands
        for action in ActionID.allCases { all += [action.spec.command, action.spec.barCommand] }
        let snapshot = project(state, ProjectionContext(now: now, calendar: Driver.calendar))
        // The context menus the window's rows, spaces and conversations open, as the views ask for them.
        var requests: [PopupMenuRequest] = []
        if let view = snapshot.windows[window] {
            let rows = rowIDs(view)
            requests += rows.map(PopupMenuRequest.item) + [.selection(Array(rows.prefix(3)))]
            requests += view.dock.flatMap { [PopupMenuRequest.space($0.id), .spaceControls($0.id), .spaceCard($0.id), .todayCleanup($0.id)] }
        }
        requests += state.doc.spaceOrder.map(PopupMenuRequest.space) + state.session.ai.answers.values.compactMap(\.conversation?.id).map(PopupMenuRequest.conversation)
        for request in requests {
            let t = reduce(state, .user(window, .sidebar(.popupMenu(request, at: .zero))), ctx)
            for case .popupMenu(_, let menu, _) in t.effects { all += menu.actions.map(\.command) }
            all.append(.sidebar(.popupMenu(request, at: .zero)))
        }
        var seen: Set<Command> = []
        let unique = all.filter { seen.insert($0).inserted }
        commandsByKind[kind] = unique
        return unique
    }

    private func rowIDs(_ view: WindowSnapshot) -> [ItemID] {
        func walk(_ rows: [Row]) -> [ItemID] {
            rows.flatMap { row -> [ItemID] in
                switch row {
                case .tab(let t): [t.id]
                case .split(let s): [s.id] + s.panes.map(\.id)
                case .folder(let f): [f.id] + walk(f.children)
                }
            }
        }
        return view.favorites.tiles.map(\.id) + walk(view.space.pinned.rows) + walk(view.space.today.rows)
    }

    /// What is wrong with what an input did in a window of `kind` that started from `base`, in words; empty when nothing
    /// is. `file`: also check the saved part when it changed (about a millisecond).
    func violations(_ t: Transition, from base: AppState, in kind: Kind, file: Bool = true) -> [String] {
        let state = t.state
        var out: [String] = []
        if let closed = base.session.closedWindow, state.session.closedWindow == closed {
            // An input that leaves the window closed must not change what it would show, open a dialog in it or ask it
            // for a panel or menu: nobody would see any of it (BrkApp has no host for the closed window).
            if state.doc.windows[closed]?.space != base.doc.windows[closed]?.space || state.doc.windows[closed]?.activeBySpace != base.doc.windows[closed]?.activeBySpace {
                out.append("the closed window shows something else and stays closed")
            }
            // A toast there (Copy URL, Copy Brk Info) goes unseen and expires; the copy itself needs no window.
            var before = base.session.windows[closed], after = state.session.windows[closed]
            before?.toast = nil; after?.toast = nil
            if before != after { out.append("the closed window's session changed while it stays closed") }
            for effect in t.effects where hostWindow(of: effect) == closed { out.append("the closed window is asked to show \(effect)") }
        }
        guard t.changed else { return out }
        out += violations(state, in: kind)
        // A tab added with no address that is neither shown nor loading: an empty row whose page never opens (the
        // address it was asked for lives only with a loaded page).
        let shown = state.onScreenTabs(), loading = Set(state.session.loaded.map(\.item))
        for item in state.doc.tree.allTabs() where base.doc.tree[item] == nil && state.tab(item)?.url == nil && !shown.contains(item) && !loading.contains(item) {
            out.append("tab \(item) was added with no address, not shown and not loading")
        }
        if file, t.docChanged {
            let data = StateCodec.encode(state)
            if data.range(of: Data(Self.privateHost.utf8)) != nil { out.append("a private page's address reached the saved file") }
            // Restored where the saved part changes in its own way: the standard window's (fresh, rich, closed alone) and a
            // Little Arc's Open In. Incognito and blank windows' own tabs are never saved, and the closed window beside
            // the incognito one saves what it saves alone.
            if [.fresh, .standard, .little, .closedAlone].contains(kind) {
                let restored = StateCodec.restore(data, seed: RestoreSeed(startURL: nil, contentSize: Driver.contentSize), ctx: ctx)
                if restored.outcome != .restored(repairs: []) { out.append("the saved file restores as \(restored.outcome)") }
            }
        }
        return out
    }

    /// What is wrong with a state itself, in words: the rules `normalize` keeps and a few it cannot repair, and the
    /// projection of its windows.
    func violations(_ state: AppState, in kind: Kind) -> [String] {
        var out: [String] = []
        var normalized = state
        normalize(&normalized)
        if normalized != state {
            let parts = [normalized.doc != state.doc ? "doc" : nil,
                         normalized.session.windows != state.session.windows ? "window sessions" : nil,
                         normalized.session.loaded != state.session.loaded ? "loaded pages" : nil,
                         normalized.session.scratch != state.session.scratch ? "scratch trees" : nil].compactMap { $0 }
            out.append("normalize still had to repair \(parts.isEmpty ? "the session" : parts.joined(separator: ", "))")
        }
        let windows = Set(state.doc.windows.keys)
        if Set(state.session.windows.keys) != windows || Set(state.session.scratch.keys) != windows {
            out.append("windows, sessions and scratch trees differ")
        }
        if let closed = state.session.closedWindow {
            if state.doc.windows[closed]?.kind != .standard { out.append("the closed window is not a standard window") }
            if state.session.loaded.contains(where: { $0.window == closed }) { out.append("the closed window holds loaded pages") }
            if state.session.windows[closed]?.overlay != nil { out.append("the closed window has an overlay nobody can see") }
            if state.doc.windows.values.contains(where: { $0.kind == .standard && $0.id != closed }) { out.append("a closed window beside an open standard window") }
        }
        for (id, window) in state.doc.windows {
            if state.doc.spaces[window.space] == nil { out.append("window \(id) is on a missing space") }
            if window.kind == .little, state.session.scratch[id]?.allTabs().isEmpty != false,
               !{ if case .commandBar? = state.session.windows[id]?.overlay { true } else { false } }() {
                out.append("a Little Arc with no tab and no command bar")
            }
        }
        if state.doc.windows.values.contains(where: { $0.kind == .incognito }), state.session.privateSession == nil {
            out.append("an incognito window without a private session")
        }
        if !state.session.loaded.allSatisfy(state.owns) { out.append("a loaded page no window owns") }
        if !Set(state.session.live.keys).isSubset(of: state.session.loaded) { out.append("a live page that is not loaded") }
        if !state.onScreenPages().filter(state.owns).isSubset(of: state.session.loaded) { out.append("a page on screen that is not loaded") }
        // The closed window brought back beside the incognito window draws what the standard and incognito kinds draw.
        guard !(kind == .closedWithOthersOpen && state.session.closedWindow == nil) else { return out }
        // Light and dark take turns: both see about half the inputs of every kind.
        projections += 1
        let scheme: Scheme = projections.isMultiple(of: 2) ? .light : .dark
        let snapshot = project(state, ProjectionContext(now: now, calendar: Driver.calendar, systemScheme: scheme))
        if Set(snapshot.windows.keys) != windows.subtracting(state.session.closedWindow.map { [$0] } ?? []) {
            out.append("the \(scheme) projection does not draw exactly the open windows")
        }
        if snapshot.closedWindow != state.session.closedWindow { out.append("the projection names another closed window") }
        if snapshot.pages.contains(where: { $0.id.window == state.session.closedWindow || state.doc.windows[$0.id.window] == nil }) {
            out.append("the projection asks for a page in a window that is closed or gone")
        }
        for (id, view) in snapshot.windows where view.kind != state.doc.windows[id]?.kind { out.append("window \(id) projects as \(view.kind)") }
        return out
    }

    /// The window an effect shows something on: BrkApp drops it when that window has no host (a sheet, panel, popover or
    /// menu attaches to it). Minimize and full screen act on the window itself, which is moot while it is closed.
    private func hostWindow(of effect: Effect) -> WindowID? {
        switch effect {
        case .iconPicker(let window, _, _), .popupMenu(let window, _, _), .export(_, let window), .exportSpaceFolder(let window, _, _),
             .aiChooseFolder(let window), .chooseWebsiteRules(let window, _), .confirmLocalExtension(let window, _, _), .addLocalExtension(let window, _):
            window
        case .siteRequest(let request): request.window
        case .sidebarData(.panel(let window, _)), .sidebarData(.importSelected(let window, _, _, _)), .sidebarData(.connectSelectedFolder(let window, _, _)):
            window
        default: nil
        }
    }
}
