import BrkBase
import CoreGraphics
import Foundation
import XCTest
@testable import BrkDomain

let pendingW4 = "W4: not implemented yet"
let pendingW5 = "W5: not implemented yet"

let T0 = Instant(milliseconds: 1_790_000_000_000)
let minute: Duration = .seconds(60)
let hour: Duration = .seconds(3_600)
let start = URL(string: "http://127.0.0.1:9/a")!

func url(_ text: String) -> URL { URL(string: text)! }

/// The app's state owner in miniature: one `AppState`, changed only through `reduce`, read only through `project`
/// and `StateCodec`. Ported from the Electron spec's Driver. A fixed clock (`now`, moved by `advance`) and a counter
/// for ids make every run deterministic.
final class Driver {
    private(set) var state: AppState
    private(set) var now = T0
    let window: WindowID
    let outcome: RestoreOutcome
    private let ids = Counter()
    private var transferDetails: [DownloadID: DownloadDetails] = [:]
    private var transferRevisions: [DownloadID: UInt64] = [:]
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static let startURL = start
    static let contentSize = CGSize(width: 1280, height: 776)

    init(file: Data? = nil, startURL: URL? = Driver.startURL) {
        let restored = StateCodec.restore(file, seed: RestoreSeed(startURL: startURL, contentSize: Driver.contentSize),
                                          ctx: Context(now: now, newID: ids.next))
        state = restored.state
        outcome = restored.outcome
        window = project(restored.state, ProjectionContext(now: now, calendar: Driver.calendar)).windows.keys.sorted()[0]
        announceBrowsers()
        // The default fixture starts after its initial document has committed. Tests of provisional startup use StateCodec directly.
        if file == nil { commitRequested() }
    }

    var ctx: Context { Context(now: now, newID: ids.next) }

    @discardableResult
    func user(_ command: Command, in window: WindowID? = nil) -> Transition { apply(reduce(state, .user(window ?? self.window, command), ctx)) }

    @discardableResult
    func system(_ event: SystemEvent) -> Transition {
        if case .page(_, .closed) = event {
            let t = reduce(state, .system(event), ctx)
            state = t.state
            return t
        }
        return apply(reduce(state, .system(event), ctx))
    }

    @discardableResult
    func page(_ tab: ItemID, _ event: PageEvent, in owner: WindowID? = nil) -> Transition {
        let page = PageID(window: owner ?? window, item: tab)
        let token = state.session.live[page]?.browser ?? BrowserToken(page: page, generation: 1)
        return system(.page(token, event))
    }

    @discardableResult
    func download(_ tab: ItemID, _ id: DownloadID, _ stage: DownloadStage, details: DownloadDetails? = nil, in owner: WindowID? = nil) -> Transition {
        if let details { transferDetails[id] = details }
        transferRevisions[id, default: 0] += 1
        let page = PageID(window: owner ?? window, item: tab)
        let browser = state.session.live[page]?.browser ?? BrowserToken(page: page, generation: 1)
        return system(.download(DownloadUpdate(id: id,
            owner: DownloadOwner(browser: browser, context: ContextEpoch(context: state.browsingContext(of: tab), generation: 1), policy: .default),
            details: transferDetails[id] ?? DownloadDetails(url: start, suggestedName: "fixture"),
            revision: transferRevisions[id]!, stage: stage)))
    }

    @discardableResult
    func key(_ chord: KeyChord, stage: KeyStage, pressID: UInt64, isRepeat: Bool = false, in window: WindowID? = nil) -> Transition {
        let press = KeyPress(chord: chord, phase: .down, isRepeat: isRepeat, editableFieldFocused: false)
        let input = KeyInput(press: press, stage: stage, pressID: PressID(raw: pressID))
        return apply(reduce(state, .key(window ?? self.window, input), ctx))
    }

    func advance(_ duration: Duration) { now = now.advanced(by: duration) }

    var snapshot: AppSnapshot { project(state, ProjectionContext(now: now, calendar: Driver.calendar)) }
    var view: WindowSnapshot { snapshot.windows[window]! }
    func view(of window: WindowID) -> WindowSnapshot { snapshot.windows[window]! }
    var todayIDs: [ItemID] { view.space.today.rows.map(\.id) }
    var pinnedIDs: [ItemID] { view.space.pinned.rows.map(\.id) }
    var favoriteIDs: [ItemID] { view.favorites.tiles.map(\.id) }
    var paneIDs: [ItemID] { view.content.panes.map(\.tab) }
    var loadedIDs: Set<ItemID> { Set(snapshot.pages.map(\.id.item)) }
    var savedFile: Data { StateCodec.encode(state) }

    /// Every tab row the window shows: Favorites tiles, Pinned and Today rows, folders' children and split panes.
    var allTabRows: [TabRow] {
        func walk(_ rows: [Row]) -> [TabRow] {
            rows.flatMap { row -> [TabRow] in
                switch row {
                case .tab(let r): [r]
                case .split(let s): s.panes
                case .folder(let f): walk(f.children)
                }
            }
        }
        return view.favorites.tiles + walk(view.space.pinned.rows) + walk(view.space.today.rows)
    }

    var current: TabRow? { allTabRows.first { $0.status == .current } }
    func row(_ id: ItemID) -> TabRow? { allTabRows.first { $0.id == id } }

    /// The archive list the archive page would show (groups flattened, newest first), read without changing state.
    func archive() -> [ArchiveEntry] {
        let opened = reduce(state, .user(window, .library(.open(.archive))), ctx).state
        guard case .library(let library)? = project(opened, ProjectionContext(now: now, calendar: Driver.calendar)).windows[window]?.overlay, let page = library.archive else {
            XCTFail("the archive did not open")
            return []
        }
        return page.groups.flatMap(\.entries)
    }

    /// The command bar overlay, if open.
    var bar: CommandBarSnapshot? {
        if case .commandBar(let bar)? = view.overlay { return bar }
        return nil
    }

    /// The saved file, parsed: what the next launch reads.
    var saved: [String: Any] { (try? JSONSerialization.jsonObject(with: savedFile) as? [String: Any]) ?? [:] }
    var savedDoc: [String: Any] { saved["doc"] as? [String: Any] ?? [:] }

    func commitRequested(in owner: WindowID? = nil) {
        for spec in snapshot.pages where owner == nil || spec.id.window == owner {
            if let requested = state.session.live[spec.id]?.requestedURL { page(spec.id.item, .committed(requested), in: spec.id.window) }
        }
    }

    /// Cmd+T, type, Enter. Returns the new tab's id.
    @discardableResult
    func open(_ input: String) -> ItemID {
        let before = Set(todayIDs)
        user(.commandBar(.open(.newTab)))
        user(.commandBar(.submit(input)))
        let added = todayIDs.filter { !before.contains($0) }
        precondition(added.count == 1, "open(\(input)) added \(added.count) tabs")
        page(added[0], .committed(resolveTypedInput(input)!))
        return added[0]
    }

    /// A new space through the dialog's command; returns its id (the window switches to it).
    @discardableResult
    func newSpace(_ title: String, color: RGBA = ThemePresets.drab[8]) -> SpaceID {
        user(.space(.create(title: title, icon: .none, theme: SpaceTheme(colors: [color], texture: .grain, intensity: 0.25, appearance: .auto))))
        return view.space.id
    }

    private func announceBrowsers() {
        for spec in snapshot.pages where spec.initialURL != nil && state.session.live[spec.id]?.browser == nil {
            let token = BrowserToken(page: spec.id, generation: (state.session.generations[spec.id] ?? 0) + 1)
            state = reduce(state, .system(.page(token, .browserCreated(spec.context, .unavailable))), ctx).state
        }
    }

    private func apply(_ t: Transition) -> Transition {
        state = t.state
        announceBrowsers()
        return t
    }
}

/// The transition changed nothing: the same state value, no rev bump, nothing to save.
func assertUnchanged(_ before: AppState, _ t: Transition, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(t.state == before, "state changed", file: file, line: line)
    XCTAssertFalse(t.changed, "changed", file: file, line: line)
    XCTAssertFalse(t.docChanged, "docChanged", file: file, line: line)
}

/// Fresh ids "d<driver>-<n>": a per-driver prefix, so a restored driver's new ids never collide with the ids in the
/// file it restored (the app uses UUIDs).
final class Counter: @unchecked Sendable {
    private static let drivers = NSLock()
    nonisolated(unsafe) private static var count = 0
    private let lock = NSLock()
    private let prefix: String
    private var n = 0

    init() {
        prefix = Counter.drivers.withLock { Counter.count += 1; return "d\(Counter.count)" }
    }

    func next() -> String { lock.withLock { n += 1; return "\(prefix)-\(n)" } }
}

/// JSON helpers for the hand-edited state files of the restore cases.
func jsonObject(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }
func jsonData(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }

/// The popup menu a transition asked for, if any.
func popup(_ t: Transition) -> MenuModel? {
    for case .popupMenu(_, let menu, _) in t.effects { return menu }
    return nil
}

func titles(_ menu: MenuModel) -> [String] {
    menu.entries.compactMap { if case .action(let title, _, _) = $0 { title } else { nil } }
}

func command(_ menu: MenuModel, _ title: String) -> Command? {
    for case .action(let t, let command, _) in menu.entries where t == title { return command }
    return nil
}
