import BrkBase
import CoreGraphics
import Foundation
@testable import BrkDomain

/// One sample of every `Command` and `SystemEvent` case, with a name per case from an exhaustive switch: adding a
/// case does not compile until it has a name here, and the pinned counts in ReduceSpecTests then ask for a sample
/// and a behavior test (found by scanning the test sources for a dispatch of that case).
enum CommandInventory {
    static let item = ItemID("ghost-item"), space = SpaceID("ghost-space")

    static let commands: [Command] = [
        .commandBar(.open(.newTab)), .commandBar(.submit("example.com")), .commandBar(.dismiss),
        .archive(.open), .archive(.restore(ArchiveID("ghost"))), .archive(.restoreLast), .archive(.clear),
        .tab(.focus(item)), .tab(.step(.next)), .tab(.cycleRecent(.next)), .tab(.close(.focused)), .tab(.archive(.item(item))),
        .tab(.togglePin(.focused)), .tab(.reset(.focused)), .tab(.clearToday),
        .page(.back(.focused)), .page(.forward(.focused)), .page(.reload(.focused, ignoringCache: false)), .page(.stop(.focused)),
        .page(.zoom(.reset)), .page(.toggleDevTools), .page(.copyURL),
        .item(.beginRename(.focused)), .item(.rename(item, title: "x")), .item(.move(item, to: .space(space))), .item(.newFolder),
        .item(.toggleFolder(item)), .item(.deleteFolder(item)), .item(.setIcon(item, .emoji("x"))),
        .space(.create(title: "", icon: .none, theme: .default)), .space(.update(space, title: "x", icon: nil, theme: nil)),
        .space(.delete(space)), .space(.move(space, index: 0)), .space(.focus(space)), .space(.step(.previous)),
        .space(.togglePinnedSection(.current)),
        .split(.addPane), .split(.closePane), .split(.resize(item, fractions: [:])), .split(.setOrientation(item, .vertical)),
        .sidebar(.toggle), .sidebar(.resize(width: 300)), .sidebar(.peek(true)), .sidebar(.openDialog(.newSpace)),
        .sidebar(.popupMenu(.plusButton, at: .zero)),
        .app(.quit), .app(.hide), .app(.hideOthers), .app(.minimize), .app(.toggleFullScreen), .app(.exit),
        .settings(.autoArchive(.sevenDays)),
    ]

    static let events: [SystemEvent] = [
        .page(PageID(item), .committed(URL(string: "https://example.com/")!)), .page(PageID(item), .titleChanged("x")),
        .page(PageID(item), .faviconChanged(nil)), .page(PageID(item), .loadingChanged(isLoading: true, canGoBack: false, canGoForward: false)),
        .page(PageID(item), .loadFailed(code: -1, description: "x", url: "x")), .page(PageID(item), .rendererGone),
        .page(PageID(item), .closedByPage), .page(PageID(item), .gainedFocus),
        .page(PageID(item), .openRequested(URL(string: "https://example.com/")!, .foregroundTab)), .page(PageID(item), .closed),
        .clockTick,
        .window(WindowID("ghost"), .geometry(bounds: .zero, contentSize: .zero)), .window(WindowID("ghost"), .modifiersChanged(held: [])),
        .window(WindowID("ghost"), .closed),
    ]

    static func area(_ command: Command) -> String {
        switch command {
        case .commandBar: "commandBar"
        case .archive: "archive"
        case .tab: "tab"
        case .page: "page"
        case .item: "item"
        case .space: "space"
        case .split: "split"
        case .sidebar: "sidebar"
        case .app: "app"
        case .settings: "settings"
        }
    }

    static func name(_ command: Command) -> String {
        let leaf: String = switch command {
        case .commandBar(let c): switch c { case .open: "open"; case .submit: "submit"; case .dismiss: "dismiss" }
        case .archive(let c): switch c { case .open: "open"; case .restore: "restore"; case .restoreLast: "restoreLast"; case .clear: "clear" }
        case .tab(let c):
            switch c {
            case .focus: "focus"
            case .step: "step"
            case .cycleRecent: "cycleRecent"
            case .close: "close"
            case .archive: "archive"
            case .togglePin: "togglePin"
            case .reset: "reset"
            case .clearToday: "clearToday"
            }
        case .page(let c):
            switch c {
            case .back: "back"
            case .forward: "forward"
            case .reload: "reload"
            case .stop: "stop"
            case .zoom: "zoom"
            case .toggleDevTools: "toggleDevTools"
            case .copyURL: "copyURL"
            }
        case .item(let c):
            switch c {
            case .beginRename: "beginRename"
            case .rename: "rename"
            case .move: "move"
            case .newFolder: "newFolder"
            case .toggleFolder: "toggleFolder"
            case .deleteFolder: "deleteFolder"
            case .setIcon: "setIcon"
            }
        case .space(let c):
            switch c {
            case .create: "create"
            case .update: "update"
            case .delete: "delete"
            case .move: "move"
            case .focus: "focus"
            case .step: "step"
            case .togglePinnedSection: "togglePinnedSection"
            }
        case .split(let c): switch c { case .addPane: "addPane"; case .closePane: "closePane"; case .resize: "resize"; case .setOrientation: "setOrientation" }
        case .sidebar(let c):
            switch c {
            case .toggle: "toggle"
            case .resize: "resize"
            case .peek: "peek"
            case .openDialog: "openDialog"
            case .popupMenu: "popupMenu"
            }
        case .app(let c):
            switch c {
            case .quit: "quit"
            case .hide: "hide"
            case .hideOthers: "hideOthers"
            case .minimize: "minimize"
            case .toggleFullScreen: "toggleFullScreen"
            case .exit: "exit"
            }
        case .settings(let c): switch c { case .autoArchive: "autoArchive" }
        }
        return "\(area(command)).\(leaf)"
    }

    static func name(_ event: SystemEvent) -> String {
        switch event {
        case .page(_, let e):
            switch e {
            case .committed: "page.committed"
            case .titleChanged: "page.titleChanged"
            case .faviconChanged: "page.faviconChanged"
            case .loadingChanged: "page.loadingChanged"
            case .loadFailed: "page.loadFailed"
            case .rendererGone: "page.rendererGone"
            case .closedByPage: "page.closedByPage"
            case .gainedFocus: "page.gainedFocus"
            case .openRequested: "page.openRequested"
            case .closed: "page.closed"
            }
        case .clockTick: "clockTick"
        case .window(_, let e):
            switch e {
            case .geometry: "window.geometry"
            case .modifiersChanged: "window.modifiersChanged"
            case .closed: "window.closed"
            }
        }
    }

    /// What a dispatch of the case looks like in a test: `.tab(.focus(` for commands, the event's own case for page
    /// and window events (tests send those through `d.page(tab, ...)` and `.window(window, ...)`).
    static func pattern(for name: String) -> String {
        let parts = name.split(separator: ".").map(String.init)
        switch name {
        case "page.closed": return #"page\([^\n]*\.closed\)"#
        case "window.closed": return #"\.window\([^\n]*\.closed\)"#
        case "clockTick": return #"\.clockTick\b"#
        default:
            if name.hasPrefix("page."), events.contains(where: { Self.name($0) == name }) { return #"\."# + parts[1] + #"\b"# }
            if name.hasPrefix("window.") { return #"\."# + parts[1] + #"\("# }
            return #"\."# + parts[0] + #"\(\s*\."# + parts[1] + #"\b"#
        }
    }

    /// Every test source of this target except this inventory.
    static func testSources() throws -> String {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") && $0 != "CommandInventory.swift" }
            .map { try String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }
}
