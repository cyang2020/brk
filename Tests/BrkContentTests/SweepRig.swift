import AppKit
import BrkBase
@testable import BrkContent
@testable import BrkDomain
import BrkLayout
@testable import BrkSidebar
import XCTest

/// A standard window as the app draws it, in one appearance, built from the reducer's state and drawn by the real root
/// view; `render` may change the snapshot first, for what the reducer only reaches through a page or a file (a playing
/// tab, a card's meetings, downloads).
@MainActor
final class SweepRig {
    static let size = CGSize(width: 1280, height: 776)
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let look: SurfaceChecks.Look
    var scheme: Scheme { look.mac }
    let now = Instant(milliseconds: 1_790_000_000_000)
    let calendar = SweepRig.utc
    private let ids: IDs
    var state: AppState
    let id: WindowID
    let window: NSWindow
    let root: WindowRootView
    private(set) var shown: WindowSnapshot?
    /// What the window's views sent.
    var sent: [Command] {
        get { log.sent }
        set { log.sent = newValue }
    }
    private final class Log { var sent: [Command] = [] }
    private let log: Log

    /// The window, made while the app is in `look.mac` (`SurfaceChecks.appearing`), its Space in `look`'s colour.
    init(_ look: SurfaceChecks.Look = SurfaceChecks.Look(mac: .light, navy: false)) throws {
        let ids = IDs(), log = Log(), now = Instant(milliseconds: 1_790_000_000_000)
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: Self.size),
                                       ctx: Context(now: now, newID: ids.next)).state
        let projection = ProjectionContext(now: now, calendar: Self.utc, systemScheme: look.mac)
        let window = try XCTUnwrap(project(state, projection).windows.keys.sorted().first)
        if look.navy, let space = project(state, projection).windows[window]?.space.id {
            let theme = SpaceTheme(colors: [SurfaceChecks.Look.navyColor], texture: .grain, intensity: SpaceTheme.default.intensity, appearance: .auto)
            state = reduce(state, .user(window, .space(.update(space, title: nil, icon: nil, theme: theme))), Context(now: now, newID: ids.next)).state
        }
        id = window
        self.look = look
        self.ids = ids
        self.log = log
        self.state = state
        self.window = SurfaceChecks.window(Self.size)
        root = WindowRootView(dispatch: { [log] in log.sent.append($0) })
        self.window.contentView = root
    }

    func close() { window.close() }

    var ctx: Context { Context(now: now, newID: ids.next, calendar: calendar) }
    var projection: ProjectionContext { ProjectionContext(now: now, calendar: calendar, systemScheme: look.mac) }

    func run(_ command: Command) { state = reduce(state, .user(id, command), ctx).state }
    func system(_ event: SystemEvent) { state = reduce(state, .system(event), ctx).state }
    func snapshot() -> WindowSnapshot { project(state, projection).windows[id]! }

    /// Opens a tab on `path` of the fixture host and returns it.
    @discardableResult
    func open(_ path: String) -> ItemID? {
        let before = Set(snapshot().space.today.rows.map(\.id))
        run(.commandBar(.open(.newTab)))
        run(.commandBar(.submit("http://127.0.0.1:9/" + path)))
        return snapshot().space.today.rows.map(\.id).first { !before.contains($0) }
    }

    @discardableResult
    func render(_ edit: (inout WindowSnapshot) -> Void = { _ in }) -> WindowSnapshot {
        var value = snapshot()
        edit(&value)
        root.render(value, frames: WindowLayout.compute(value, contentSize: Self.size), surface: { _ in nil })
        root.layoutSubtreeIfNeeded()
        shown = value
        return value
    }

    /// What the window shows behind its views: the theme's colour (the Metal background's first frame).
    var base: NSColor {
        let c = (shown ?? snapshot()).theme.windowColor
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    /// The labels of `views` (the whole window by default) that do not read, then the pointer over everything in them.
    /// Fails when the pointer reached fewer than `reach` tracking areas.
    func check(_ name: String, _ views: [NSView]? = nil, base: NSColor? = nil, reach: Int = 1, exempt: (NSTextField) -> Bool = { _ in false },
               file: StaticString = #filePath, line: UInt = #line) -> [String] {
        var problems: [String] = [], reached = 0
        for target in views ?? [root] {
            problems += SurfaceChecks.unreadable(in: target, base: base ?? self.base, "\(look) \(name)", exempt: exempt)
            reached += SurfaceChecks.sweep(target, in: target.window ?? window)
        }
        XCTAssertGreaterThanOrEqual(reached, reach, "\(look) \(name): the pointer reached \(reached) tracking areas", file: file, line: line)
        return problems
    }

    /// The root's subview of type `T` (an overlay the root keeps to itself).
    func overlay<T: NSView>(_ type: T.Type) -> T? { root.subviews.lazy.compactMap { $0 as? T }.first }

    // MARK: State

    struct Sidebar {
        var favorites: [ItemID] = []
        var pinned: [ItemID] = []
        var collapsed: ItemID
        var open: ItemID
        var group: ItemID
        var playing: ItemID
    }

    /// Favorites (one a calendar, one mail), two Pinned tabs (one a site with a card), a collapsed and an open folder, a
    /// group, a split, Today, and three Spaces in the dock; Previews on.
    func buildSidebar() throws -> Sidebar {
        run(.tabTools(.preferences(includeFavorites: false, previews: true)))
        for path in ["b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"] { open(path) }
        let today = snapshot().space.today.rows.map(\.id)
        XCTAssertGreaterThanOrEqual(today.count, 12)
        for (index, item) in today.prefix(3).enumerated() { run(.item(.move(item, to: .into(parent: snapshot().favorites.root, index: index)))) }
        run(.tab(.togglePin(.item(today[3]))))
        run(.tab(.togglePin(.item(today[4]))))
        func folder(_ items: [ItemID], group: Bool) throws -> ItemID {
            run(.tabTools(.bulk(.items(items), .newFolder(group: group))))
            return try XCTUnwrap(state.doc.tree[items[0]]?.parent)
        }
        let collapsed = try folder([today[5], today[6]], group: false)
        run(.item(.rename(collapsed, title: "Reading")))
        run(.item(.toggleFolder(collapsed)))
        let open = try folder([today[7], today[8]], group: false)
        run(.item(.rename(open, title: "Projects")))
        let group = try folder([today[9], today[10]], group: true)
        run(.item(.rename(group, title: "Research")))   // a new group opens with its name field; this ends it
        run(.split(.addPane))
        run(.commandBar(.submit("http://127.0.0.1:9/split")))
        let home = snapshot().space.id
        for (title, color) in [("Work", ThemePresets.drab[3]), ("Travel", ThemePresets.drab[6])] {
            run(.space(.create(title: title, icon: .none, theme: SpaceTheme(colors: [color], texture: .grain, intensity: 0.25, appearance: .auto))))
        }
        run(.space(.focus(home)))
        return Sidebar(favorites: Array(today.prefix(3)), pinned: [today[3], today[4]], collapsed: collapsed, open: open, group: group, playing: today[11])
    }

    /// What only a page or a file gives the sidebar: the calendar's meetings, the mail and site cards, a playing tab and
    /// its mini player, the Library button's items.
    func decorate(_ value: inout WindowSnapshot, _ sidebar: Sidebar) {
        let hour: Int64 = 3_600_000
        let later = Instant(milliseconds: now.milliseconds + hour / 4)
        let page = { (title: String, ago: Int64) in HoverPage(title: title, url: URL(string: "https://linear.app/brk/\(ago)")!, visitedAt: Instant(milliseconds: self.now.milliseconds - ago)) }
        for index in value.favorites.tiles.indices {
            switch value.favorites.tiles[index].id {
            case sidebar.favorites[1]:
                value.favorites.tiles[index].subtitle = "in 15m"
                value.favorites.tiles[index].hoverCard = .calendar(site: "calendar.google.com", meetings: [
                    HoverMeeting(title: "Design review", start: later, end: Instant(milliseconds: later.milliseconds + hour), joinURL: URL(string: "https://meet.google.com/abc")),
                    HoverMeeting(title: "Lunch", start: Instant(milliseconds: later.milliseconds + 2 * hour), end: Instant(milliseconds: later.milliseconds + 3 * hour), joinURL: nil),
                ])
            case sidebar.favorites[2]:
                value.favorites.tiles[index].badge = 34
                value.favorites.tiles[index].hoverCard = .mail(site: "mail.google.com", unread: 34, messages: [page("Inbox (8,965)", hour), page("Reminder", 2 * hour)])
            default: break
            }
        }
        func edit(_ rows: inout [Row], _ change: (inout TabRow) -> Void, where match: (TabRow) -> Bool) {
            for index in rows.indices {
                switch rows[index] {
                case .tab(var tab) where match(tab): change(&tab); rows[index] = .tab(tab)
                case .folder(var folder): edit(&folder.children, change, where: match); rows[index] = .folder(folder)
                case .split(var split):
                    for pane in split.panes.indices where match(split.panes[pane]) { change(&split.panes[pane]) }
                    rows[index] = .split(split)
                default: break
                }
            }
        }
        edit(&value.space.pinned.rows, { $0.hoverCard = .recentPages(site: "linear.app", pages: [page("BRK-12 Sidebar", hour), page("BRK-9 Cards", 3 * hour)]) },
             where: { $0.id == sidebar.pinned[1] })
        let player = MediaPlayer(id: MediaPlayerID(document: "d", frame: 0, element: "v"), kind: .video, paused: false, ended: false, hasNextTrack: true)
        edit(&value.space.today.rows, { $0.audible = true; $0.mediaPlayers = [player] }, where: { $0.id == sidebar.playing })
        value.miniPlayers = [MiniPlayerSnapshot(tab: sidebar.playing, title: "Lo-fi beats to sidebar to", favicon: nil, icon: nil, playing: true, muted: false,
                                                hasNextTrack: true, hasPreviousTrack: true, volume: 0.6)]
        value.libraryFlyout = LibraryFlyoutSnapshot(items: libraryItems(), badge: nil)
    }

    /// Two downloads (one running) and a capture, oldest first, at paths that do not exist (a press must not open a file).
    func libraryItems() -> [LibraryFlyoutItem] {
        let minute: Int64 = 60_000
        func download(_ id: String, _ name: String, _ state: DownloadState, received: Int64, total: Int64?, ago: Int64) -> LibraryFlyoutItem {
            let row = DownloadRow(id: DownloadID(id), filename: name, url: URL(string: "https://files.example.com/\(name)")!,
                                  path: "/nonexistent/brk-sweep/\(name)", received: received, total: total, state: state,
                                  startedAt: Instant(milliseconds: now.milliseconds - ago * minute))
            return LibraryFlyoutItem(key: .download(row.id), content: .download(row), date: row.startedAt)
        }
        return [download("d1", "report.pdf", .finished, received: 2_048_000, total: 2_048_000, ago: 50),
                LibraryFlyoutItem(key: .capture("cap1"), content: .capture(capture("cap1", ago: 20), file: nil), date: Instant(milliseconds: now.milliseconds - 20 * minute)),
                download("d2", "dataset.zip", .inProgress, received: 30_000_000, total: 90_000_000, ago: 1)]
    }

    func capture(_ id: String, ago minutes: Int64) -> CaptureRecord {
        let page = PageID(window: self.id, item: ItemID("captured"))
        let request = CaptureRequest(id: id, document: DocumentToken(browser: BrowserToken(page: page, generation: 1), sequence: 1), context: .profile(.default),
                                     mode: .area, title: "Pricing table", url: URL(string: "https://example.com/pricing")!,
                                     createdAt: Instant(milliseconds: now.milliseconds - minutes * 60_000))
        return CaptureRecord(request: request, profile: .default, image: CaptureImage(png: Data([1]), width: 640, height: 400, scale: 2))
    }
}
