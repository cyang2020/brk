import BrkBase
import CoreGraphics
import Foundation
@testable import BrkDomain

/// One sample of every `Command` and `SystemEvent` case, with a name per case from an exhaustive switch: adding a
/// case does not compile until it has a name here, and the pinned counts in ReduceSpecTests then ask for a sample
/// and a behavior test (found by scanning the test sources for a dispatch of that case).
enum CommandInventory {
    static let item = ItemID("ghost-item"), space = SpaceID("ghost-space"), profile = ProfileID("ghost-profile")
    static let download = DownloadID("ghost-download"), route = LinkRouteID("ghost-route")
    static let example = URL(string: "https://example.com/")!

    /// `.window(.close)` is last: on a driver with a second standard window it removes the dispatching window.
    static let commands: [Command] = [
        .commandBar(.queryChangedForSite(SearchEngine.google.id, "x")), .commandBar(.calculate("2+2")), .commandBar(.open(.newTab)), .commandBar(.submit("example.com")), .commandBar(.submitSearch(engine: SearchEngine.duckDuckGo.id, query: "x")),
        .commandBar(.queryChanged("exa")), .commandBar(.dismiss),
        .archive(.restore(ArchiveID("ghost"))), .archive(.restoreLast), .archive(.clear),
        .tab(.focus(item)), .tab(.step(.next)), .tab(.cycleRecent(.next)), .tab(.close(.focused)), .tab(.archive(.item(item))),
        .tab(.togglePin(.focused)), .tab(.reset(.focused)), .tab(.clearToday),
        .page(.back(.focused)), .page(.forward(.focused)), .page(.reload(.focused, ignoringCache: false)), .page(.stop(.focused)),
        .page(.developer(.source)), .page(.output(.pdf)), .page(.zoom(.reset)), .page(.toggleDevTools), .page(.copyURL(.plain)),
        .item(.beginRename(.focused)), .item(.rename(item, title: "x")), .item(.move(item, to: .space(space))), .item(.newFolder),
        .item(.toggleFolder(item)), .item(.deleteFolder(item)), .item(.setIcon(item, .emoji("x"))),
        .space(.create(title: "", icon: .none, theme: .default)), .space(.update(space, title: "x", icon: nil, theme: nil)),
        .space(.delete(space)), .space(.move(space, index: 0)), .space(.focus(space)), .space(.step(.previous)),
        .space(.togglePinnedSection(.current)),
        .split(.addPane), .split(.closePane), .split(.resize(item, fractions: [:])), .split(.setOrientation(item, .vertical)),
        .sidebar(.toggle), .sidebar(.resize(width: 300)), .sidebar(.peek(true)), .sidebar(.openDialog(.newSpace)),
        .sidebar(.popupMenu(.plusButton, at: .zero)),
        .app(.quit), .app(.hide), .app(.hideOthers), .app(.minimize), .app(.toggleFullScreen), .app(.exit),
        .app(.showAbout), .app(.setAsDefaultBrowser), .app(.export(.space(.current))), .app(.revealDataDirectory),
        .settings(.autoArchive(.sevenDays)), .settings(.general(.warnBeforeQuitting(true))), .settings(.profile(.default, .searchSuggestions(false))),
        .settings(.links(.shiftClickPeek(false))), .settings(.shortcuts(.setChord(.newTab, KeyChord(.command, .e)))),
        .settings(.max(.provider(.off))), .settings(.advanced(.soundEffects(false))), .settings(.openPane(.links)), .settings(.closeWindow),
        .library(.open(.archive)), .library(.close), .library(.cancelDownload(download)), .library(.revealDownload(download)),
        .library(.removeHistoryVisit(HistoryVisitID("ghost"))), .library(.removeDownload(download)), .library(.clearDownloads), .library(.removeHistory(example)), .library(.clearHistory),
        .window(.openInFolder(item)), .window(.newBlank), .window(.toggleStayOnTop), .window(.new), .window(.newIncognito), .window(.newLittle(example)), .window(.openIn(.current)),
        .peek(.email), .peek(.open(example)), .peek(.close),
        .profile(.create(name: "Work", icon: nil)), .profile(.rename(profile, name: "x")), .profile(.delete(profile)),
        .profile(.assign(.current, to: profile)), .profile(.openDialog(.create)),
        .later(.boosts),
        .window(.close),
    ]

    static let events: [SystemEvent] = [
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .committed(URL(string: "https://example.com/")!)), .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .titleChanged("x")),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .faviconChanged(nil)), .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .loadingChanged(isLoading: true, canGoBack: false, canGoForward: false)),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .loadFailed(code: -1, description: "x", url: "x")), .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .rendererGone),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .closedByPage), .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .gainedFocus),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .openRequested(URL(string: "https://example.com/")!, .foregroundTab)),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .closed),
        .download(DownloadUpdate(id: download, owner: DownloadOwner(browser: BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), context: ContextEpoch(context: .profile(profile), generation: 1), policy: .default), details: DownloadDetails(url: example, suggestedName: "x.zip"), revision: 1, stage: .choosingDestination)),
        .contextDisposed(.completed(DisposalID("ghost"), .profile(profile), .deletionScheduledForNextLaunch)),
        .exportFinished(WindowID("ghost"), .cancelled),
        .output(OutputUpdate(id: OutputID("ghost-output"), document: DocumentToken(browser: BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), sequence: 1), stage: .rendering)),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .zoomChanged(125)),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .fullscreenChanged(true)),
        .window(WindowID("ghost"), .becameKey), .window(WindowID("ghost"), .resignedKey), .window(WindowID("ghost"), .activity),
        .clockTick,
        .window(WindowID("ghost"), .geometry(bounds: .zero, contentSize: .zero)), .window(WindowID("ghost"), .modifiersChanged(held: [])),
        .window(WindowID("ghost"), .closed),
        .externalURL(example), .suggestions(WindowID("ghost"), query: "x", ["xy"]), .aiProvidersDetected([.claude]),
        .aiResult(AIRequestID("ghost"), .unavailable),
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
        case .library: "library"
        case .window: "window"
        case .peek: "peek"
        case .profile: "profile"
        case .later: "later"
        }
    }

    static func name(_ command: Command) -> String {
        let leaf: String = switch command {
        case .commandBar(let c):
            switch c {
            case .queryChangedForSite: "queryChangedForSite"
            case .calculate: "calculate"
            case .open: "open"
            case .submit: "submit"
            case .submitSearch: "submitSearch"
            case .queryChanged: "queryChanged"
            case .dismiss: "dismiss"
            }
        case .archive(let c): switch c { case .restore: "restore"; case .restoreLast: "restoreLast"; case .clear: "clear" }
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
            case .developer: "developer"
            case .output: "output"
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
            case .showAbout: "showAbout"
            case .setAsDefaultBrowser: "setAsDefaultBrowser"
            case .export: "export"
            case .revealDataDirectory: "revealDataDirectory"
            }
        case .settings(let c):
            switch c {
            case .autoArchive: "autoArchive"
            case .general: "general"
            case .profile: "profile"
            case .links: "links"
            case .shortcuts: "shortcuts"
            case .max: "max"
            case .advanced: "advanced"
            case .openPane: "openPane"
            case .closeWindow: "closeWindow"
            }
        case .library(let c):
            switch c {
            case .open: "open"
            case .close: "close"
            case .cancelDownload: "cancelDownload"
            case .revealDownload: "revealDownload"
            case .removeDownload: "removeDownload"
            case .clearDownloads: "clearDownloads"
            case .removeHistoryVisit: "removeHistoryVisit"
            case .removeHistory: "removeHistory"
            case .clearHistory: "clearHistory"
            }
        case .window(let c):
            switch c {
            case .newBlank: "newBlank"
            case .toggleStayOnTop: "toggleStayOnTop"
            case .new: "new"
            case .newIncognito: "newIncognito"
            case .newLittle: "newLittle"
            case .close: "close"
            case .openIn: "openIn"
            case .openInFolder: "openInFolder"
            }
        case .peek(let c): switch c { case .email: "email"; case .open: "open"; case .close: "close" }
        case .profile(let c):
            switch c {
            case .create: "create"
            case .rename: "rename"
            case .delete: "delete"
            case .assign: "assign"
            case .openDialog: "openDialog"
            }
        case .later(let feature): feature.rawValue
        }
        return "\(area(command)).\(leaf)"
    }

    static func name(_ event: SystemEvent) -> String {
        switch event {
        case .page(_, let e):
            switch e {
            case .browserCreated: "page.browserCreated"
            case .documentChanged: "page.documentChanged"
            case .navigationRequested: "page.navigationRequested"
            case .committed: "page.committed"
            case .zoomChanged: "page.zoomChanged"
            case .fullscreenChanged: "page.fullscreenChanged"
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
        case .exportFinished: "exportFinished"
        case .output: "output"
        case .download: "download"
        case .contextDisposed: "contextDisposed"
        case .clockTick: "clockTick"
        case .window(_, let e):
            switch e {
            case .becameKey: "window.becameKey"
            case .resignedKey: "window.resignedKey"
            case .activity: "window.activity"
            case .geometry: "window.geometry"
            case .modifiersChanged: "window.modifiersChanged"
            case .closed: "window.closed"
            }
        case .externalURL: "externalURL"
        case .suggestions: "suggestions"
        case .aiProvidersDetected: "aiProvidersDetected"
        case .aiResult: "aiResult"
        }
    }

    /// What a dispatch of the case looks like in a test: `.tab(.focus(` for commands, the event's own case for page
    /// and window events (tests send those through `d.page(tab, ...)` and `.window(window, ...)`), the bare case
    /// name for the app-wide events.
    static func pattern(for name: String) -> String {
        let parts = name.split(separator: ".").map(String.init)
        switch name {
        case "page.closed": return #"page\([^\n]*\.closed\)"#
        case "window.becameKey", "window.resignedKey", "window.activity": return #"\."# + parts[1] + #"\b"#
        case "window.closed": return #"\.window\([^\n]*\.closed\)"#
        case "exportFinished", "output", "download", "contextDisposed", "clockTick", "externalURL", "suggestions", "aiProvidersDetected", "aiResult": return #"\."# + name + #"\b"#
        default:
            if parts.count == 1 { return #"\."# + parts[0] + #"\b"# }
            if name.hasPrefix("later.") { return #"\.later\(\s*\."# + parts[1] + #"\b"# }
            if name.hasPrefix("page."), events.contains(where: { Self.name($0) == name }) { return #"\."# + parts[1] + #"\b"# }
            if name.hasPrefix("window.") && events.contains(where: { Self.name($0) == name }) { return #"\."# + parts[1] + #"\("# }
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
