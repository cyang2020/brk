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
    static let splitOffer = SplitDropOffer(window: WindowID("ghost"), source: item, target: ItemID("target"),
        sourceParent: ItemID("parent"), targetParent: ItemID("parent"), panes: [ItemID("target")],
        orientation: .horizontal, context: .profile(.default))

    static let siteTarget = SiteTarget(document: DocumentToken(browser: BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), sequence: 1), context: .profile(profile), origin: SiteOrigin(example)!)

    /// `.window(.close)` is last: on a driver with a second standard window it removes the dispatching window.
    static let commands: [Command] = [
        .assist(.open(.question)), .assist(.ask("why")), .assist(.askPage("why")), .assist(.browse(question: "why", sources: [example])),
        .assist(.instant("query")), .assist(.translate("English")), .assist(.organizeToday), .assist(.undoOrganize),
        .assist(.renameDownload(download)), .assist(.cancel), .assist(.dismiss), .assist(.searchFallback),
        .assist(.neverTranslateSite), .assist(.neverTranslateLanguage),
        .commandBar(.queryChangedForSite(SearchEngine.google.id, "x")), .commandBar(.calculate("2+2")),
        .sidebarData(.welcome), .sidebarData(.tour), .sidebarData(.importFile), .sidebarData(.syncSettings),
        .sidebarData(.importSelected(URL(fileURLWithPath: "/tmp/fixture"), format: .bookmarksHTML)),
        .sidebarData(.connectSelectedFolder(URL(fileURLWithPath: "/tmp/fixture"))), .sidebarData(.exportSelected(URL(fileURLWithPath: "/tmp/fixture.json"))), .sidebarData(.cancelFilePanel),
        .sidebarData(.syncNow), .sidebarData(.disconnect), .sidebarData(.completeOnboarding(OnboardingChoices())),
        .find(.open(replace: false)), .find(.query(FindQuery(text: "x"))), .find(.step(.next)), .find(.close),
        .find(.useSelection), .find(.jumpToSelection), .find(.captureScope), .find(.replaceCurrent("y")), .find(.replaceAll("y")),
        .commandBar(.open(.newTab)), .commandBar(.submit("example.com")), .commandBar(.submitSearch(engine: SearchEngine.duckDuckGo.id, query: "x")),
        .commandBar(.queryChanged("exa")), .commandBar(.dismiss),
        .archive(.restore(ArchiveID("ghost"))), .archive(.restoreLast), .archive(.requestClear), .archive(.clear),
        .tab(.focus(item)), .tab(.step(.next)), .tab(.cycleRecent(.next)), .tab(.close(.focused)), .tab(.archive(.item(item))),
        .tab(.togglePin(.focused)), .tab(.reset(.focused)), .tab(.clearToday),
        .tabTools(.site(.connectCalendar)), .tabTools(.resetPinned), .tabTools(.cycleLinear(.next)), .tabTools(.jumpItem(1)), .tabTools(.jumpSpace(1)),
        .tabTools(.select(item, .range)), .tabTools(.bulk(.items([item]), .archive)), .tabTools(.reveal), .tabTools(.sidebarStep(.next)),
        .tabTools(.leaveSidebar), .tabTools(.folders(expanded: true)), .tabTools(.cancelRecent), .tabTools(.chooseIcon(item)),
        .tabTools(.iconPickerClosed), .tabTools(.mute(.focused)), .tabTools(.dismissToast), .tabTools(.dismissArchiveEducation),
        .tabTools(.preferences(includeFavorites: true, previews: false)),
        .page(.back(.focused)), .page(.forward(.focused)), .page(.reload(.focused, ignoringCache: false)), .page(.stop(.focused)),
        .page(.developer(.source)), .page(.output(.pdf)), .page(.cancelOutput), .page(.zoom(.reset)), .page(.toggleDevTools), .page(.cast), .page(.copyURL(.plain)),
        .item(.beginRename(.focused)), .item(.rename(item, title: "x")), .item(.move(item, to: .space(space))), .item(.newFolder),
        .item(.toggleFolder(item)), .item(.deleteFolder(item)), .item(.setIcon(item, .emoji("x"))),
        .space(.create(title: "", icon: .none, theme: .default)), .space(.update(space, title: "x", icon: nil, theme: nil)),
        .space(.delete(space)), .space(.move(space, index: 0)), .space(.focus(space)), .space(.step(.previous)),
        .space(.togglePinnedSection(.current)), .space(.requestDelete(space)), .space(.confirmDelete(space, token: "ghost", confirmed: false)), .space(.exportIntoFolder(space)),
        .split(.addPane), .split(.closePane), .split(.closePaneAt(item)), .split(.resize(item, fractions: [:])), .split(.setOrientation(item, .vertical)),
        .split(.orientCurrent(.vertical)), .split(.focusPane(1)), .split(.stepPane(.next)), .split(.separatePane(.focused)),
        .split(.separateAll), .split(.toggleExpanded), .split(.restore), .split(.dropTab(splitOffer, edge: .left)),
        .sidebar(.toggleToolbar), .sidebar(.toggleSpaceHeader), .sidebar(.toggle), .sidebar(.resize(width: 300)), .sidebar(.peek(true)), .sidebar(.openDialog(.newSpace)),
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
        .site(.loadBlockingRules), .site(.selectedBlockingRules(URL(fileURLWithPath: "/tmp/fixture"), .profile(profile))), .site(.resetBlockingRules),
        .site(.extensionIncognito("ghost", false)), .site(.extensionShortcut("ghost", "run", "cmd+shift+u")),
        .site(.nativeExtensions), .site(.pinExtension("ghost", true)), .site(.invokeExtension("ghost")), .site(.removeExtension("ghost")),
        .site(.controls), .site(.closeControls), .site(.rule(siteTarget, SiteRule())),
        .site(.permission(siteTarget, SiteOrigin(example)!, [.notifications], .deny)), .site(.appearance(.dark)),
        .site(.cancelClearing), .site(.clearProfile(profile, [.cookies])),
        .site(.clear(kinds: [.cookies], scope: .site, reload: true)), .site(.confirmClear("ghost", false)),
        .site(.installSelectedExtension(URL(fileURLWithPath: "/tmp/fixture"))), .site(.executeExtensionInstall(URL(fileURLWithPath: "/tmp/fixture"), .profile(profile))),
        .site(.extensions), .site(.extensionShortcuts), .site(.addExtension),
        .boost(.create), .boost(.legacy), .boost(.editCurrent), .boost(.edit("ghost")), .boost(.gallery), .boost(.preset("reader")),
        .boost(.update(Boost(id: "ghost", name: "Ghost", scope: .allSites))), .boost(.save), .boost(.cancel), .boost(.zap),
        .boost(.enable("ghost", false)), .boost(.remove("ghost")), .boost(.export("ghost")), .boost(.importFile),
        .boost(.importSelected(URL(fileURLWithPath: "/tmp/boost.json"))), .boost(.exportSelected("ghost", URL(fileURLWithPath: "/tmp/boost.json"))),
        .later(.boosts),
        .window(.close),
    ]

    static let events: [SystemEvent] = [
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .loadProgress(0.5)),
        .boost(.loaded(profile, BoostCatalog(), error: nil)),
        .page(siteTarget.document.browser, .boostFailed(siteTarget.document, "fixture")),
        .sidebarData(.syncPoll),
        .find(.failed(FindRequestID("ghost"), .unavailable)),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .committed(URL(string: "https://example.com/")!)), .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .titleChanged("x")),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .faviconChanged(nil)), .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .loadingChanged(isLoading: true, canGoBack: false, canGoForward: false)),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .loadFailed(code: -1, description: "x", url: "x")), .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .rendererGone),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .closedByPage), .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .gainedFocus),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .openRequested(URL(string: "https://example.com/")!, .foregroundTab)),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .closed),
        .download(DownloadUpdate(id: download, owner: DownloadOwner(browser: BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), context: ContextEpoch(context: .profile(profile), generation: 1), policy: .default), details: DownloadDetails(url: example, suggestedName: "x.zip"), revision: 1, stage: .choosingDestination)),
        .contextDisposed(.completed(DisposalID("ghost"), .profile(profile), .deletionScheduledForNextLaunch)),
        .siteResult("ghost", .cancelled), .clockTick,
        .spaceExportFinished(WindowID("ghost"), token: "ghost", .cancelled),
        .exportFinished(WindowID("ghost"), .cancelled),
        .output(OutputUpdate(id: OutputID("ghost-output"), document: DocumentToken(browser: BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), sequence: 1), stage: .rendering)),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .zoomChanged(125)),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .fullscreenChanged(true)),
        .window(WindowID("ghost"), .becameKey), .window(WindowID("ghost"), .resignedKey), .window(WindowID("ghost"), .activity),
        .page(siteTarget.document.browser, .websitePolicyApplied(WebsitePolicyStatus(document: siteTarget.document, appearance: .automatic, themeApplied: false, frozen: false, error: nil))),
        .websiteRulesLoaded(.profile(profile), .failed("fixture")),
        .extensionOperationFailed(.profile(profile), "fixture"),
        .extensionsRead(ExtensionCatalog(context: .profile(profile), extensions: [], error: "fixture")),
        .profileDataCleared(ClearProfileDataResult(request: ClearProfileData(id: "ghost", profile: profile, kinds: [.cookies]), completed: [], error: "fixture")),
        .siteDataCleared(ClearSiteDataResult(request: ClearSiteData(id: "ghost", target: siteTarget, kinds: [.cookies]), completed: [], error: "fixture")),
        .window(WindowID("ghost"), .geometry(bounds: .zero, contentSize: .zero)), .window(WindowID("ghost"), .modifiersChanged(held: [])),
        .window(WindowID("ghost"), .closed),
        .externalURL(example), .suggestions(WindowID("ghost"), query: "x", ["xy"]), .aiProvidersDetected([.claude]),
        .aiResult(AIRequestID("ghost"), .unavailable),
        .aiPartial(AIRequestID("ghost"), "partial"), .aiPageRead(AIRequestID("ghost"), siteTarget.document.browser.page, nil),
        .aiDeadline(AIRequestID("ghost")), .aiHoverReady(WindowID("ghost"), example), .aiTranslated(AIRequestID("ghost"), false),
        .aiDownloadRenamed(download, originalPath: "/tmp/ghost", newPath: nil, error: nil),
        .page(siteTarget.document.browser, .linkHovered(nil)),
    ]

    static func area(_ command: Command) -> String {
        switch command {
        case .boost: "boost"
        case .assist: "assist"
        case .find: "find"
        case .sidebarData: "sidebarData"
        case .commandBar: "commandBar"
        case .archive: "archive"
        case .tab: "tab"
        case .tabTools: "tabTools"
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
        case .site: "site"
        case .profile: "profile"
        case .later: "later"
        }
    }

    static func name(_ command: Command) -> String {
        let leaf: String = switch command {
        case .boost(let c):
            switch c {
            case .create: "create"
            case .legacy: "legacy"
            case .editCurrent: "editCurrent"
            case .edit: "edit"
            case .gallery: "gallery"
            case .preset: "preset"
            case .update: "update"
            case .save: "save"
            case .cancel: "cancel"
            case .zap: "zap"
            case .enable: "enable"
            case .remove: "remove"
            case .export: "export"
            case .importFile: "importFile"
            case .importSelected: "importSelected"
            case .exportSelected: "exportSelected"
            }
        case .assist(let intent):
            switch intent {
            case .open: "open"
            case .ask: "ask"
            case .askPage: "askPage"
            case .browse: "browse"
            case .instant: "instant"
            case .translate: "translate"
            case .organizeToday: "organizeToday"
            case .undoOrganize: "undoOrganize"
            case .renameDownload: "renameDownload"
            case .cancel: "cancel"
            case .dismiss: "dismiss"
            case .searchFallback: "searchFallback"
            case .neverTranslateSite: "neverTranslateSite"
            case .neverTranslateLanguage: "neverTranslateLanguage"
            }
        case .find(let c):
            switch c {
            case .open: "open"
            case .query: "query"
            case .step: "step"
            case .close: "close"
            case .useSelection: "useSelection"
            case .jumpToSelection: "jumpToSelection"
            case .captureScope: "captureScope"
            case .replaceCurrent: "replaceCurrent"
            case .replaceAll: "replaceAll"
            }
        case .sidebarData(let c):
            switch c {
            case .welcome: "welcome"
            case .tour: "tour"
            case .importFile: "importFile"
            case .importSelected: "importSelected"
            case .connectSelectedFolder: "connectSelectedFolder"
            case .exportSelected: "exportSelected"
            case .cancelFilePanel: "cancelFilePanel"
            case .syncSettings: "syncSettings"
            case .syncNow: "syncNow"
            case .disconnect: "disconnect"
            case .completeOnboarding: "completeOnboarding"
            }
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
        case .archive(let c): switch c { case .restore: "restore"; case .restoreLast: "restoreLast"; case .requestClear: "requestClear"; case .clear: "clear" }
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
        case .tabTools(let c):
            switch c {
            case .site: "site"
            case .resetPinned: "resetPinned"
            case .cycleLinear: "cycleLinear"
            case .jumpItem: "jumpItem"
            case .jumpSpace: "jumpSpace"
            case .select: "select"
            case .bulk: "bulk"
            case .reveal: "reveal"
            case .sidebarStep: "sidebarStep"
            case .leaveSidebar: "leaveSidebar"
            case .folders: "folders"
            case .cancelRecent: "cancelRecent"
            case .chooseIcon: "chooseIcon"
            case .iconPickerClosed: "iconPickerClosed"
            case .mute: "mute"
            case .dismissToast: "dismissToast"
            case .dismissArchiveEducation: "dismissArchiveEducation"
            case .preferences: "preferences"
            }
        case .page(let c):
            switch c {
            case .back: "back"
            case .forward: "forward"
            case .reload: "reload"
            case .stop: "stop"
            case .zoom: "zoom"
            case .toggleDevTools: "toggleDevTools"
            case .cast: "cast"
            case .developer: "developer"
            case .output: "output"
            case .cancelOutput: "cancelOutput"
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
            case .requestDelete: "requestDelete"
            case .confirmDelete: "confirmDelete"
            case .exportIntoFolder: "exportIntoFolder"
            case .create: "create"
            case .update: "update"
            case .delete: "delete"
            case .move: "move"
            case .focus: "focus"
            case .step: "step"
            case .togglePinnedSection: "togglePinnedSection"
            }
        case .split(let c): switch c {
            case .addPane: "addPane"; case .closePane: "closePane"; case .closePaneAt: "closePaneAt"; case .resize: "resize"; case .setOrientation: "setOrientation"
            case .orientCurrent: "orientCurrent"; case .focusPane: "focusPane"; case .stepPane: "stepPane"
            case .separatePane: "separatePane"; case .separateAll: "separateAll"; case .toggleExpanded: "toggleExpanded"
            case .restore: "restore"; case .dropTab: "dropTab"
            }
        case .sidebar(let c):
            switch c {
            case .toggleToolbar: "toggleToolbar"
            case .toggleSpaceHeader: "toggleSpaceHeader"
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
        case .site(let c):
            switch c {
            case .loadBlockingRules: "loadBlockingRules"
            case .selectedBlockingRules: "selectedBlockingRules"
            case .resetBlockingRules: "resetBlockingRules"
            case .nativeExtensions: "nativeExtensions"
            case .extensionIncognito: "extensionIncognito"
            case .extensionShortcut: "extensionShortcut"
            case .pinExtension: "pinExtension"
            case .invokeExtension: "invokeExtension"
            case .removeExtension: "removeExtension"
            case .controls: "controls"
            case .closeControls: "closeControls"
            case .rule: "rule"
            case .permission: "permission"
            case .appearance: "appearance"
            case .clear: "clear"
            case .clearProfile: "clearProfile"
            case .cancelClearing: "cancelClearing"
            case .confirmClear: "confirmClear"
            case .extensions: "extensions"
            case .extensionShortcuts: "extensionShortcuts"
            case .installSelectedExtension: "installSelectedExtension"
            case .executeExtensionInstall: "executeExtensionInstall"
            case .addExtension: "addExtension"
            }
        case .later(let feature): feature.rawValue
        }
        return "\(area(command)).\(leaf)"
    }

    static func name(_ event: SystemEvent) -> String {
        switch event {
        case .boost: "boost"
        case .sidebarData: "sidebarData"
        case .page(_, let e):
            switch e {
            case .browserCreated: "page.browserCreated"
            case .documentChanged: "page.documentChanged"
            case .navigationRequested: "page.navigationRequested"
            case .committed: "page.committed"
            case .zoomChanged: "page.zoomChanged"
            case .fullscreenChanged: "page.fullscreenChanged"
            case .titleChanged: "page.titleChanged"
            case .linkHovered: "page.linkHovered"
            case .faviconChanged: "page.faviconChanged"
            case .audioChanged: "page.audioChanged"
            case .loadingChanged: "page.loadingChanged"
            case .loadFailed: "page.loadFailed"
            case .boostFailed: "page.boostFailed"
            case .websitePolicyApplied: "page.websitePolicyApplied"
            case .loadProgress: "page.loadProgress"
            case .rendererGone: "page.rendererGone"
            case .closedByPage: "page.closedByPage"
            case .gainedFocus: "page.gainedFocus"
            case .openRequested: "page.openRequested"
            case .closed: "page.closed"
            }
        case .find: "find"
        case .exportFinished: "exportFinished"
        case .output: "output"
        case .download: "download"
        case .websiteRulesLoaded: "websiteRulesLoaded"
        case .extensionOperationFailed: "extensionOperationFailed"
        case .extensionsRead: "extensionsRead"
        case .siteDataCleared: "siteDataCleared"
        case .profileDataCleared: "profileDataCleared"
        case .contextDisposed: "contextDisposed"
        case .siteResult: "siteResult"
        case .clockTick: "clockTick"
        case .spaceExportFinished: "spaceExportFinished"
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
        case .aiPartial: "aiPartial"
        case .aiPageRead: "aiPageRead"
        case .aiDeadline: "aiDeadline"
        case .aiHoverReady: "aiHoverReady"
        case .aiTranslated: "aiTranslated"
        case .aiDownloadRenamed: "aiDownloadRenamed"
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
