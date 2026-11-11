import BrkBase
import CoreGraphics
import Foundation
@testable import BrkDomain

/// One sample of every `Command` and `SystemEvent` case, with a name per case from an exhaustive switch: adding a
/// case does not compile until it has a name here, and the pinned counts in ReduceSpecTests then ask for a sample
/// and a behavior test (found by scanning the test sources for a dispatch of that case).
enum CommandInventory {
    static let item = ItemID("ghost-item"), space = SpaceID("ghost-space"), profile = ProfileID("ghost-profile")
    static let download = DownloadID("ghost-download"), route = LinkRouteID("ghost-route"), easel = EaselID("ghost-easel")
    static let example = URL(string: "https://example.com/")!
    static let splitOffer = SplitDropOffer(window: WindowID("ghost"), source: item, target: ItemID("target"),
        sourceParent: ItemID("parent"), targetParent: ItemID("parent"), panes: [ItemID("target")],
        orientation: .horizontal, context: .profile(.default))

    static let siteTarget = SiteTarget(document: DocumentToken(browser: BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), sequence: 1), context: .profile(profile), origin: SiteOrigin(example)!)

    /// `.window(.close)` is last: on a driver with a second standard window it removes the dispatching window.
    static let commands: [Command] = [
        .assist(.open(.question)), .assist(.ask("why")), .assist(.askAgent("why", agent: .claude)), .assist(.askPage("why")), .assist(.browse(question: "why", sources: [example])),
        .assist(.instant("query")), .assist(.translate("English")), .assist(.organizeToday), .assist(.undoOrganize),
        .assist(.renameDownload(download)), .assist(.cancel), .assist(.dismiss),
        .assist(.neverTranslateSite), .assist(.neverTranslateLanguage),
        .assist(.useOriginal), .assist(.languageSettings), .assist(.previewHover(true)), .assist(.sharePreview),
        .assist(.followUp("why")), .assist(.stop), .assist(.chooseFolder), .assist(.approve(approval: "a", option: "b")),
        .assist(.attach([.tab("ghost"), .folder(ItemID("ghost")), .space(SpaceID("ghost"))])), .assist(.detach("ghost")), .assist(.mention("x")), .assist(.openTabLink("ghost")),
        .assist(.newConversation), .assist(.keepPage(AIPageID("ghost"))),
        .assist(.pageLink(AIPageID("ghost"), URL(string: "https://ghost.example/")!)), .assist(.answerPageLink(true)),
        .assist(.pageSave(AIPageID("ghost"), "{}")), .assist(.livePage(AIPageID("ghost"), .refreshNow)), .archive(.delete(ArchiveID("ghost"))),
        .assist(.panelPage(.list)), .assist(.showConversation(AIRequestID("ghost"))), .assist(.listSearch("x")), .assist(.listAsk("why")),
        .assist(.beginRenameConversation(AIRequestID("ghost"))), .assist(.renameConversation(AIRequestID("ghost"), "x")),
        .assist(.moveConversation(AIRequestID("ghost"), space)), .assist(.pickAgent(.codex, model: nil)),
        .assist(.togglePanel), .assist(.panelWidth(500)), .assist(.hoverConversation(AIRequestID("ghost"))), .assist(.hoverChip("ghost")),
        .capture(.open("ghost")), .capture(.begin(.area)), .capture(.select(CaptureRegion(x:0,y:0,width:0.5,height:0.5))), .capture(.cancel),
        .capture(.preview("ghost")), .capture(.export("ghost")), .capture(.remove("ghost")), .capture(.insertInEasel("ghost")),
        .capture(.act(.copy)),
        .page(.pictureInPicture(.document)),
        .commandBar(.queryChangedForSite(SearchEngine.google.id, "x")), .commandBar(.calculate("2+2")),
        .commandBar(.splitTab(.right, ItemID("ghost"))), .commandBar(.copyAnswer("3.048 m")), .commandBar(.local(.open, path: "/ghost/file.txt")), .commandBar(.prefixQuery(.files, "x")), .commandBar(.splitOpen(.right, "example.com")), .window(.place(.leftHalf)), .commandBar(.openDictionary("word")),
        .sidebarData(.welcome), .sidebarData(.tour), .sidebarData(.importFile), .sidebarData(.importBrowser), .sidebarData(.syncSettings),
        .sidebarData(.importSelected(URL(fileURLWithPath: "/tmp/fixture"), format: .bookmarksHTML)),
        .sidebarData(.connectSelectedFolder(URL(fileURLWithPath: "/tmp/fixture"))), .sidebarData(.exportSelected(URL(fileURLWithPath: "/tmp/fixture.json"))), .sidebarData(.cancelFilePanel),
        .sidebarData(.syncNow), .sidebarData(.disconnect), .sidebarData(.completeOnboarding(OnboardingChoices())),
        .find(.open(replace: false)), .find(.query(FindQuery(text: "x"))), .find(.step(.next)), .find(.close),
        .find(.useSelection), .find(.jumpToSelection), .find(.captureScope), .find(.replaceCurrent("y")), .find(.replaceAll("y")),
        .commandBar(.open(.newTab)), .commandBar(.submit("example.com")), .commandBar(.submitSearch(engine: SearchEngine.duckDuckGo.id, query: "x")),
        .commandBar(.queryChanged("exa")), .commandBar(.ran("x")), .commandBar(.dismiss),
        .archive(.restore(ArchiveID("ghost"))), .archive(.restoreLast), .archive(.requestClear), .archive(.clear),
        .tab(.focus(item)), .tab(.step(.next)), .tab(.cycleRecent(.next)), .tab(.close(.focused)), .tab(.archive(.item(item))),
        .tab(.togglePin(.focused)), .tab(.reset(.focused)), .tab(.clearToday), .tab(.newDocument),
        .tabTools(.site(.connectCalendar)), .tabTools(.resetPinned), .tabTools(.cycleLinear(.next)), .tabTools(.jumpItem(1)), .tabTools(.jumpSpace(1)),
        .tabTools(.select(item, .range)), .tabTools(.bulk(.items([item]), .archive)), .tabTools(.reveal), .tabTools(.sidebarStep(.next)),
        .tabTools(.leaveSidebar), .tabTools(.folders(expanded: true)), .tabTools(.cancelRecent), .tabTools(.chooseIcon(item)),
        .tabTools(.dismissLittleTip), .tabTools(.iconPickerClosed), .tabTools(.mute(.focused)), .tabTools(.dismissToast), .tabTools(.quoteLinkCopied), .tabTools(.dismissArchiveEducation), .tabTools(.dismissFavoritesHint), .tabTools(.undoToast),
        .tabTools(.preferences(includeFavorites: true, previews: false)), .tabTools(.copyLinks(.items([item]))), .tabTools(.openInSplit(.items([item]))),
        .tabTools(.newNestedFolder(item)), .tabTools(.folderToSpace(item)), .tabTools(.customize(item)), .tabTools(.addToSplit(item)),
        .tabTools(.spaceIntoFolder(space, into: space)),
        .tabTools(.siteDisplay(host: "github.com", .unreadBadge, on: false)), .tabTools(.closeGroup(item)), .tabTools(.removeGroupHeader(item)),
        .tabTools(.openFolder(item)), .tabTools(.replacePinned(item)), .tabTools(.muteAll(true)), .split(.addPaneAt(.left)),
        .page(.back(.focused)), .page(.forward(.focused)), .page(.reload(.focused, ignoringCache: false)), .page(.stop(.focused)),
        .page(.developer(.source)), .page(.output(.pdf)), .page(.cancelOutput), .page(.zoom(.reset)), .page(.toggleDevTools), .page(.cast), .page(.copyURL(.plain)), .page(.shareQuote),
        .item(.beginRename(.focused)), .item(.rename(item, title: "x")), .item(.move(item, to: .space(space))), .item(.dropOnSpaceHeader(item)), .item(.newFolder),
        .item(.toggleFolder(item)), .item(.deleteFolder(item)), .item(.setIcon(item, .emoji("x"))),
        .space(.create(title: "", icon: .none, theme: .default)), .space(.update(space, title: "x", icon: nil, theme: nil)),
        .space(.delete(space)), .space(.move(space, index: 0)), .space(.focus(space)), .space(.step(.previous)),
        .space(.togglePinnedSection(.current)), .space(.requestDelete(space)), .space(.confirmDelete(space, token: "ghost", confirmed: false)), .space(.exportIntoFolder(space)),
        .space(.inSpace(space, .newFolder)),
        .split(.addPane), .split(.addPaneBefore), .split(.movePane(.previous)), .split(.closePane), .split(.closePaneAt(item)), .split(.resize(item, fractions: [:])), .split(.setOrientation(item, .vertical)),
        .split(.orientCurrent(.vertical)), .split(.focusPane(1)), .split(.stepPane(.next)), .split(.separatePane(.focused)),
        .split(.separateAll), .split(.toggleExpanded), .split(.restore), .split(.dropTab(splitOffer, edge: .left)), .split(.replacePane(splitOffer, pane: 0)), .split(.joinRow(item, onto: ItemID("target"))),
        .sidebar(.toggleToolbar), .sidebar(.toggleSpaceHeader), .sidebar(.toggle), .sidebar(.resize(width: 300)), .sidebar(.peek(true)), .sidebar(.openDialog(.newSpace)),
        .app(.quit), .app(.hide), .app(.hideOthers), .app(.minimize), .app(.toggleFullScreen), .app(.exit),
        .app(.showAbout), .app(.setAsDefaultBrowser), .app(.export(.space(.current))), .app(.revealDataDirectory), .app(.standardEdit(.copy)),
        .app(.help(.copyInfo)), .page(.navigate(.focused, example)), .site(.toggleDeveloperMode),
        .settings(.autoArchive(.sevenDays)), .settings(.general(.warnBeforeQuitting(true))), .settings(.profile(.default, .searchSuggestions(false))),
        .settings(.links(.shiftClickPeek(false))), .settings(.shortcuts(.setChord(.newTab, KeyChord(.command, .e)))),
        .settings(.max(.provider(.off))), .settings(.advanced(.soundEffects(false))), .settings(.openPane(.links)), .settings(.closeWindow),
        .settings(.openBrowserPage(.passwords, profile: .default)),
        .library(.open(.archive)), .library(.close), .library(.openHistory), .library(.cancelDownload(download)), .library(.revealDownload(download)),
        .library(.removeHistoryVisit(HistoryVisitID("ghost"))), .library(.removeDownload(download)), .library(.clearDownloads), .library(.removeHistory(example)), .library(.clearHistory), .library(.historySearch("x")),
        .library(.conversationQuery(ConversationLibraryQuery(text: "x"))), .library(.selectConversation(AIRequestID("ghost"))), .library(.moveConversation(AIRequestID("ghost"), space)),
        .library(.requestDeleteConversation(AIRequestID("ghost"))), .library(.confirmDeleteConversation(AIRequestID("ghost"), token: "t", confirmed: false)),
        .library(.flyout(.expanded)), .library(.littleDownload(.dismiss(download))),
        .window(.openInFolder(item)), .window(.newBlank), .window(.toggleStayOnTop), .window(.new), .window(.newIncognito), .window(.newLittle(example)), .window(.openIn(.current)),
        .peek(.email), .peek(.open(example)), .peek(.close), .peek(.openAsTab), .peek(.openInSplit),
        .profile(.create(name: "Work", icon: nil)), .profile(.rename(profile, name: "x")), .profile(.delete(profile)),
        .profile(.assign(.current, to: profile)), .profile(.openDialog(.create)),
        .site(.loadBlockingRules), .site(.selectedBlockingRules(URL(fileURLWithPath: "/tmp/fixture"), .profile(profile))), .site(.resetBlockingRules), .site(.filterList("easylist", false)), .site(.filterUpdates(false)), .site(.updateFilterLists),
        .site(.extensionIncognito("ghost", false)), .site(.extensionShortcut("ghost", "run", "cmd+shift+u")),
        .site(.nativeExtensions), .site(.pinExtension("ghost", true)), .site(.invokeExtension("ghost")), .site(.removeExtension("ghost")),
        .site(.controls), .site(.closeControls), .site(.rule(siteTarget, SiteRule())),
        .site(.permission(siteTarget, SiteOrigin(example)!, [.notifications], .deny)), .site(.appearance(.dark)),
        .site(.cancelClearing), .site(.clearProfile(profile, [.cookies])),
        .site(.clear(kinds: [.cookies], scope: .site, reload: true)), .site(.confirmClear("ghost", false)),
        .site(.installSelectedExtension(URL(fileURLWithPath: "/tmp/fixture"))), .site(.executeExtensionInstall(URL(fileURLWithPath: "/tmp/fixture"), .profile(profile))),
        .site(.extensions), .site(.extensionShortcuts), .site(.addExtension),
        .boost(.create), .boost(.legacy), .boost(.editCurrent), .boost(.edit("ghost")), .boost(.gallery), .boost(.preset("reader")),
        .boost(.update(Boost(id: "ghost", name: "Ghost", scope: .allSites))), .boost(.save), .boost(.close), .boost(.discard), .boost(.zap),
        .boost(.inspect), .boost(.page(.css)),
        .boost(.enable("ghost", false)), .boost(.remove("ghost")), .boost(.export("ghost")), .boost(.importFile),
        .boost(.importSelected(URL(fileURLWithPath: "/tmp/boost.json"))), .boost(.exportSelected("ghost", URL(fileURLWithPath: "/tmp/boost.json"))),
        .page(.media(.item(item), MediaPlayerID(document: "ghost", frame: 0, element: "ghost"), .pause)),
        .page(.mediaSession(.item(item), .pause)),
        .page(.mediaVolume(.item(item), 0.5)),
        .page(.closeMiniPlayer(item)),
        .easel(.create), .easel(.open(easel)), .easel(.rename(easel, title: "x")), .easel(.stepTitleSize(easel, by: 1)),
        .easel(.add(easel, EaselElement(id: "ghost", shape: .rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10)))),
        .easel(.update(easel, [])), .easel(.remove(easel, ["ghost"])), .easel(.duplicate(easel, ["ghost"])),
        .easel(.chooseImage(easel, at: .zero)), .easel(.importImage(easel, from: URL(fileURLWithPath: "/tmp/ghost.png"), at: .zero)),
        .easel(.share(easel)), .easel(.requestDelete(easel)), .easel(.confirmDelete(easel, token: "ghost", confirmed: true)),
        .later(.boosts),
        .window(.close),
    ]

    static let events: [SystemEvent] = [
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .loadProgress(0.5)),
        .boost(.loaded(profile, BoostCatalog(), error: nil)),
        .page(siteTarget.document.browser, .boostFailed(siteTarget.document, "fixture")),
        .capture(.exported(WindowID("ghost"), "fixture")),
        .easel(.imageImported(WindowID("ghost"), easel, element: "ghost", file: URL(fileURLWithPath: "/tmp/ghost.png"), size: CGSize(width: 10, height: 10), at: .zero)),
        .easel(.shared(WindowID("ghost"), easel, URL(fileURLWithPath: "/tmp/ghost.png"))), .easel(.failed(WindowID("ghost"), easel, "fixture")),
        .page(siteTarget.document.browser, .documentPictureInPictureChanged(siteTarget.document, true, error: nil)),
        .page(BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), .mediaChanged(DocumentToken(browser: BrowserToken(page: PageID(window: WindowID("ghost"), item: item), generation: 1), sequence: 1), [], error: nil)),
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
        .page(siteTarget.document.browser, .securityChanged(PageSecurity(document: siteTarget.document, secureConnection: true, certificateError: true, insecureContent: false))),
        .websiteRulesLoaded(.profile(profile), .failed("fixture")),
        .filterListFetched(.profile(profile), "easylist", .offline),
        .extensionOperationFailed(.profile(profile), "fixture"),
        .extensionsRead(ExtensionCatalog(context: .profile(profile), extensions: [], error: "fixture")),
        .profileDataCleared(ClearProfileDataResult(request: ClearProfileData(id: "ghost", profile: profile, kinds: [.cookies]), completed: [], error: "fixture")),
        .siteDataCleared(ClearSiteDataResult(request: ClearSiteData(id: "ghost", target: siteTarget, kinds: [.cookies]), completed: [], error: "fixture")),
        .window(WindowID("ghost"), .geometry(bounds: .zero, contentSize: .zero)), .window(WindowID("ghost"), .modifiersChanged(held: [])),
        .window(WindowID("ghost"), .closed),
        .externalURL(example), .suggestions(WindowID("ghost"), query: "x", ["xy"]), .aiProvidersDetected([.claude]),
        .localResults(WindowID("ghost"), LocalResults(query: "x", apps: [], files: [])), .meaningResults(WindowID("ghost"), MeaningResults(text: "x", scope: .commandBar, hits: [])), .barTranslationDue(WindowID("ghost"), "x"), .definition(WindowID("ghost"), BarDefinition(word: "x", text: nil)), .currencyRates(CurrencyRates(date: "2026-11-06", perEuro: ["EUR": 1])),
        .globalShortcut(.registered(KeyChord([.option, .command], .n))),
        .aiResult(AIRequestID("ghost"), .unavailable),
        .aiPartial(AIRequestID("ghost"), "partial"), .aiPageRead(AIRequestID("ghost"), siteTarget.document.browser.page, nil),
        .aiDeadline(AIRequestID("ghost")), .aiHoverReady(WindowID("ghost"), example, nil), .aiTranslated(AIRequestID("ghost"), false),
        .aiDownloadRenamed(download, originalPath: "/tmp/ghost", newPath: nil, error: nil),
        .aiConversation(AIRequestID("ghost"), .notice("x")), .conversationsLoaded([], []), .aiAgents([]), .aiAgentsWanted, .aiFolderChosen(WindowID("ghost"), nil),
        .localModels(LocalModelsSnapshot()),
        .agentRead(AgentReadRequest(call: "ghost", window: WindowID("ghost"), tab: "ghost", part: .text)),
        .agentAct(AgentActRequest(call: "ghost", window: WindowID("ghost"), act: .close([ItemID("ghost")]))), .aiMentionMatches(WindowID("ghost"), query: "x", ["ghost"]),
        .aiPageRefresh(AIPageID("ghost"), run: AIRequestID("ghost"), .finished(.failed, detail: nil)), .aiPageSaved(AIPageID("ghost"), "{}"),
        .page(siteTarget.document.browser, .linkHovered(nil)),
    ]

    static func area(_ command: Command) -> String {
        switch command {
        case .boost: "boost"
        case .assist: "assist"
        case .capture: "capture"
        case .easel: "easel"
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
            case .close: "close"
            case .discard: "discard"
            case .zap: "zap"
            case .inspect: "inspect"
            case .page: "page"
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
            case .askAgent: "askAgent"
            case .askPage: "askPage"
            case .browse: "browse"
            case .instant: "instant"
            case .translate: "translate"
            case .organizeToday: "organizeToday"
            case .undoOrganize: "undoOrganize"
            case .renameDownload: "renameDownload"
            case .nameFolder: "nameFolder"
            case .acceptSuggestion: "acceptSuggestion"
            case .dismissSuggestion: "dismissSuggestion"
            case .cancel: "cancel"
            case .dismiss: "dismiss"
            case .neverTranslateSite: "neverTranslateSite"
            case .neverTranslateLanguage: "neverTranslateLanguage"
            case .useOriginal: "useOriginal"
            case .languageSettings: "languageSettings"
            case .previewHover: "previewHover"
            case .sharePreview: "sharePreview"
            case .followUp: "followUp"
            case .stop: "stop"
            case .chooseFolder: "chooseFolder"
            case .approve: "approve"
            case .attach: "attach"
            case .detach: "detach"
            case .mention: "mention"
            case .openTabLink: "openTabLink"
            case .newConversation: "newConversation"
            case .keepPage: "keepPage"
            case .pageLink: "pageLink"
            case .answerPageLink: "answerPageLink"
            case .pageSave: "pageSave"
            case .livePage: "livePage"
            case .panelPage: "panelPage"
            case .showConversation: "showConversation"
            case .togglePanel: "togglePanel"
            case .panelWidth: "panelWidth"
            case .hoverConversation: "hoverConversation"
            case .hoverChip: "hoverChip"
            case .listSearch: "listSearch"
            case .listAsk: "listAsk"
            case .beginRenameConversation: "beginRenameConversation"
            case .renameConversation: "renameConversation"
            case .pickAgent: "pickAgent"
            case .moveConversation: "moveConversation"
            }
        case .easel(let c):
            switch c {
            case .create: "create"
            case .open: "open"
            case .rename: "rename"
            case .stepTitleSize: "stepTitleSize"
            case .add: "add"
            case .update: "update"
            case .remove: "remove"
            case .duplicate: "duplicate"
            case .chooseImage: "chooseImage"
            case .importImage: "importImage"
            case .share: "share"
            case .requestDelete: "requestDelete"
            case .confirmDelete: "confirmDelete"
            }
        case .capture(let c):
            switch c {
            case .open: "open"
            case .begin: "begin"
            case .select: "select"
            case .cancel: "cancel"
            case .act: "act"
            case .preview: "preview"
            case .export: "export"
            case .remove: "remove"
            case .insertInEasel: "insertInEasel"
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
            case .importBrowser: "importBrowser"
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
            case .copyAnswer: "copyAnswer"
            case .local: "local"
            case .prefixQuery: "prefixQuery"
            case .splitOpen: "splitOpen"
            case .splitTab: "splitTab"
            case .openDictionary: "openDictionary"
            case .open: "open"
            case .submit: "submit"
            case .submitSearch: "submitSearch"
            case .queryChanged: "queryChanged"
            case .dismiss: "dismiss"
            case .ran: "ran"
            }
        case .archive(let c): switch c { case .restore: "restore"; case .restoreLast: "restoreLast"; case .requestClear: "requestClear"; case .clear: "clear"; case .delete: "delete" }
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
            case .newDocument: "newDocument"
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
            case .dismissLittleTip: "dismissLittleTip"
            case .dismissFavoritesHint: "dismissFavoritesHint"
            case .undoToast: "undoToast"
            case .quoteLinkCopied: "quoteLinkCopied"
            case .preferences: "preferences"
            case .copyLinks: "copyLinks"
            case .openInSplit: "openInSplit"
            case .newNestedFolder: "newNestedFolder"
            case .folderToSpace: "folderToSpace"
            case .customize: "customize"
            case .addToSplit: "addToSplit"
            case .spaceIntoFolder: "spaceIntoFolder"
            case .siteDisplay: "siteDisplay"
            case .closeGroup: "closeGroup"
            case .removeGroupHeader: "removeGroupHeader"
            case .openFolder: "openFolder"
            case .replacePinned: "replacePinned"
            case .muteAll: "muteAll"
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
            case .pictureInPicture: "pictureInPicture"
            case .media: "media"
            case .mediaSession: "mediaSession"
            case .mediaVolume: "mediaVolume"
            case .closeMiniPlayer: "closeMiniPlayer"
            case .output: "output"
            case .cancelOutput: "cancelOutput"
            case .copyURL: "copyURL"
            case .shareQuote: "shareQuote"
            case .navigate: "navigate"
            }
        case .item(let c):
            switch c {
            case .beginRename: "beginRename"
            case .rename: "rename"
            case .move: "move"
            case .dropOnSpaceHeader: "dropOnSpaceHeader"
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
            case .inSpace: "inSpace"
            }
        case .split(let c): switch c {
            case .addPane: "addPane"; case .addPaneAt: "addPaneAt"; case .addPaneBefore: "addPaneBefore"; case .movePane: "movePane"; case .closePane: "closePane"; case .closePaneAt: "closePaneAt"; case .resize: "resize"; case .setOrientation: "setOrientation"
            case .orientCurrent: "orientCurrent"; case .focusPane: "focusPane"; case .stepPane: "stepPane"
            case .separatePane: "separatePane"; case .separateAll: "separateAll"; case .toggleExpanded: "toggleExpanded"
            case .restore: "restore"; case .dropTab: "dropTab"; case .replacePane: "replacePane"; case .joinRow: "joinRow"
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
            case .help: "help"
            case .standardEdit: "standardEdit"
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
            case .openBrowserPage: "openBrowserPage"
            }
        case .library(let c):
            switch c {
            case .open: "open"
            case .close: "close"
            case .openHistory: "openHistory"
            case .cancelDownload: "cancelDownload"
            case .revealDownload: "revealDownload"
            case .removeDownload: "removeDownload"
            case .clearDownloads: "clearDownloads"
            case .removeHistoryVisit: "removeHistoryVisit"
            case .removeHistory: "removeHistory"
            case .clearHistory: "clearHistory"
            case .historySearch: "historySearch"
            case .conversationQuery: "conversationQuery"
            case .selectConversation: "selectConversation"
            case .moveConversation: "moveConversation"
            case .requestDeleteConversation: "requestDeleteConversation"
            case .confirmDeleteConversation: "confirmDeleteConversation"
            case .flyout: "flyout"
            case .littleDownload: "littleDownload"
            }
        case .window(let c):
            switch c {
            case .newBlank: "newBlank"
            case .place: "place"
            case .toggleStayOnTop: "toggleStayOnTop"
            case .new: "new"
            case .newIncognito: "newIncognito"
            case .newLittle: "newLittle"
            case .close: "close"
            case .openIn: "openIn"
            case .openInFolder: "openInFolder"
            }
        case .peek(let c): switch c { case .email: "email"; case .open: "open"; case .close: "close"; case .openAsTab: "openAsTab"; case .openInSplit: "openInSplit" }
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
            case .filterList: "filterList"
            case .filterUpdates: "filterUpdates"
            case .updateFilterLists: "updateFilterLists"
            case .nativeExtensions: "nativeExtensions"
            case .extensionIncognito: "extensionIncognito"
            case .extensionShortcut: "extensionShortcut"
            case .pinExtension: "pinExtension"
            case .invokeExtension: "invokeExtension"
            case .removeExtension: "removeExtension"
            case .controls: "controls"
            case .closeControls: "closeControls"
            case .rule: "rule"
            case .toggleDeveloperMode: "toggleDeveloperMode"
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
        case .capture: "capture"
        case .easel(let e):
            switch e {
            case .imageImported: "easel.imageImported"
            case .shared: "easel.shared"
            case .failed: "easel.failed"
            }
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
            case .documentPictureInPictureChanged: "page.documentPictureInPictureChanged"
            case .mediaChanged: "page.mediaChanged"
            case .audioChanged: "page.audioChanged"
            case .loadingChanged: "page.loadingChanged"
            case .loadFailed: "page.loadFailed"
            case .boostFailed: "page.boostFailed"
            case .websitePolicyApplied: "page.websitePolicyApplied"
            case .securityChanged: "page.securityChanged"
            case .loadProgress: "page.loadProgress"
            case .rendererGone: "page.rendererGone"
            case .closedByPage: "page.closedByPage"
            case .languageDetected: "page.languageDetected"
            case .translateRequested: "page.translateRequested"
            case .linkMenuRequested: "page.linkMenuRequested"
            case .selectionChanged: "page.selectionChanged"
            case .gainedFocus: "page.gainedFocus"
            case .openRequested: "page.openRequested"
            case .closed: "page.closed"
            }
        case .find: "find"
        case .exportFinished: "exportFinished"
        case .output: "output"
        case .download: "download"
        case .websiteRulesLoaded: "websiteRulesLoaded"
        case .filterListFetched: "filterListFetched"
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
        case .localResults: "localResults"
        case .meaningResults: "meaningResults"
        case .barTranslationDue: "barTranslationDue"
        case .definition: "definition"
        case .currencyRates: "currencyRates"
        case .aiProvidersDetected: "aiProvidersDetected"
        case .globalShortcut: "globalShortcut"
        case .aiResult: "aiResult"
        case .aiPartial: "aiPartial"
        case .aiPageRead: "aiPageRead"
        case .aiDeadline: "aiDeadline"
        case .aiHoverReady: "aiHoverReady"
        case .aiTranslated: "aiTranslated"
        case .aiDownloadRenamed: "aiDownloadRenamed"
        case .aiConversation: "aiConversation"
        case .conversationsLoaded: "conversationsLoaded"
        case .aiAgents: "aiAgents"
        case .aiAgentsWanted: "aiAgentsWanted"
        case .aiFolderChosen: "aiFolderChosen"
        case .aiKeys: "aiKeys"
        case .aiUsage: "aiUsage"
        case .aiBasicTick: "aiBasicTick"
        case .aiDuplicateCandidates: "aiDuplicateCandidates"
        case .localModels: "localModels"
        case .agentRead: "agentRead"
        case .agentAct: "agentAct"
        case .aiMentionMatches: "aiMentionMatches"
        case .aiPageRefresh: "aiPageRefresh"
        case .aiPageSaved: "aiPageSaved"
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
        case "exportFinished", "output", "download", "contextDisposed", "clockTick", "externalURL", "suggestions", "aiProvidersDetected", "aiResult", "globalShortcut": return #"\."# + name + #"\b"#
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
