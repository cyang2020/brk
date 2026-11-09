import BrkBase
import Foundation

public enum AIFeature: String, CaseIterable, Hashable, Sendable, Codable {
    case commandBar, askPage, linkPreviews, downloadRename, instantLinks, browse, translation
    /// Brk's basic AI layer (docs/design/ai-native.md, 基础 AI 功能), switched in the Max pane's agent card.
    case tabNames, folderNames, tabPlacement, tabCleanup
    /// The switch's name where the person finds it: the Max pane's row titles (P38-max-list), More Settings' rows.
    public var title: String {
        switch self {
        case .commandBar: "Ask in Command Bar"
        case .askPage: "Ask on Page"
        case .linkPreviews: "5-Second Previews"
        case .downloadRename: "Tidy Downloads"
        case .instantLinks: "Instant Links"
        case .browse: "Browse for Me"
        case .translation: "Translate Pages"
        case .tabNames: "Name Tabs"
        case .folderNames: "Name Groups and Folders"
        case .tabPlacement: "Place New Tabs"
        case .tabCleanup: "Suggest Tabs to Close"
        }
    }
    /// The basic layer's switches, in the agent card's order.
    public static let basicLayer: [AIFeature] = [.tabNames, .folderNames, .tabPlacement, .tabCleanup]
    /// Brk's own three are switched in Advanced → More Settings…; Arc's are in the Max pane.
    public var inMoreSettings: Bool { [.askPage, .browse, .translation].contains(self) }
    /// Where the switch is, as a message says it, and the pane a link opens.
    public var place: String { inMoreSettings ? "Settings → Advanced → More Settings…" : "Settings → Max" }
    public var pane: SettingsPane { inMoreSettings ? .advanced : .max }
}
public enum AIMode: String, Hashable, Sendable, Codable {
    case question, page, instant, browse, translate
    /// The switch this bar's feature has; the question bar has its own notice (P43-a).
    var feature: AIFeature? {
        switch self {
        case .question: nil
        case .page: .askPage
        case .instant: .instantLinks
        case .browse: .browse
        case .translate: .translation
        }
    }
}
public enum AIIntent: Hashable, Sendable, Codable {
    case open(AIMode)
    case ask(String)
    /// `ask` with this agent, whatever Max's setting says (the `claude` and `gpt` prefixes). If it is not on this Mac the
    /// answer says so; another agent never answers in its place.
    case askAgent(String, agent: AIProviderChoice)
    case askPage(String)
    case browse(question: String, sources: [URL])
    case instant(String)
    case translate(String)
    case organizeToday, undoOrganize
    case renameDownload(DownloadID)
    /// A folder's or group's Name with AI (right click).
    case nameFolder(ItemID)
    /// The suggestion under a new tab's title: its move, or its ×.
    case acceptSuggestion(ItemID)
    case dismissSuggestion(ItemID)
    case cancel, dismiss
    case neverTranslateSite, neverTranslateLanguage
    /// The translation popover's Use Original (P50-e): the page's own text comes back, "Translated back to French!
    /// Use ⌘Z to undo." shows, and ⌘Z puts the translation back.
    case useOriginal
    /// The translation popover's Options › Language Settings: Chromium's language settings page in a new tab (Arc's
    /// `chrome://settings/languages`).
    case languageSettings
    /// The pointer entered (true) or left (false) the 5-Second Preview card: while it is over the card the card stays
    /// although the link under it is no longer hovered.
    case previewHover(Bool)
    /// The card's share button: the previewed link's address on the pasteboard.
    case sharePreview
    /// The panel's input: the next message in the window's conversation.
    case followUp(String)
    /// The panel's Stop: the running turn ends and every process it started goes; the conversation stays.
    case stop
    /// The panel's Work in a Folder…: Brk asks for a folder. Only this starts a session with tools on.
    case chooseFolder
    /// The panel's approval buttons: the answer to a tool approval the agent asked for.
    case approve(approval: String, option: String)
    /// Tabs, a folder or a Space given to the panel's conversation (a drop on the panel, Ask AI, a pick after @): they
    /// show as chips in its input and go with the next message. With no conversation open, a new one starts.
    case attach([AIAttachmentSource])
    /// A chip's ×.
    case detach(String)
    /// The text after an @ in the panel's input, while the user types it; nil when the @ is gone.
    case mention(String?)
    /// A `brk://tab/<id>` link in an agent's answer: that tab is shown, or opened again from the archive or history.
    case openTabLink(String)
    /// The panel's New Conversation: the one it shows is put away (it stays in the list) and a new one with Brk's tab
    /// tools waits for its first message.
    case newConversation
    /// Keep as Tab on a page in an answer: the page becomes a sidebar tab of its own.
    case keepPage(AIPageID)
    /// A click on a link in an agent's page.
    case pageLink(AIPageID, URL)
    /// The answer to the window's `AIPageLinkPrompt`: open the address, or not.
    case answerPageLink(Bool)
    /// The page saved its own data (`window.brk.save`): JSON text, checked against the page's save shape.
    case pageSave(AIPageID, String)
    /// A kept page's schedule, weekdays, refresh model, or Refresh Now, from its row's menu.
    case livePage(AIPageID, AIPageLiveChange)
    /// The panel's page: a swipe over the panel, the list icon. `.list` opens a closed panel on the list (the command
    /// bar's "AI 对话").
    case panelPage(AIPanelPage)
    /// The sidebar title row's chat button, ⌥⌘A and View › Show/Hide AI Conversations (docs/design/ai-right-panel.md): an
    /// open panel closes; a closed one opens on what this Space's panel showed last, the list when it has no conversation.
    case togglePanel
    /// The gap between the card and the panel dragged: the panel's width, kept for the window like the sidebar's.
    case panelWidth(Double)
    /// A conversation shown in the panel: a list row, a strip, the Library's Continue, a notification, a command bar
    /// result, a `brk://conversation/<id>` link, a kept page's conversation button. Another Space's switches the window
    /// there first.
    case showConversation(AIRequestID)
    /// The pointer is over a list row (nil: off every row): the tabs that conversation used light up in the sidebar.
    case hoverConversation(AIRequestID?)
    /// The pointer is over a chip in the composer (its id, nil: off every chip): that tab lights up.
    case hoverChip(String?)
    /// The list's search box.
    case listSearch(String)
    /// The list page's composer: a new conversation in this Space.
    case listAsk(String)
    /// The list's row menu. Rename makes the row a text field (`AIPanelSnapshot.renaming`); its end sends the name, nil
    /// cancels. Delete for good asks first (`.library(.requestDeleteConversation)`).
    case beginRenameConversation(AIRequestID)
    case renameConversation(AIRequestID, String?)
    /// The row menu's Move to Another Space, or a list row dropped on a Space's dot in the sidebar's dock.
    case moveConversation(AIRequestID, SpaceID)
    /// The + menu's agent list: this agent and model for the conversation's next messages.
    case pickAgent(AIProviderKind, model: String?)
}

/// An agent and one of its models (`AIAgentModel.id`; nil: the agent's default), chosen for a conversation's next
/// messages in the panel's + menu.
public struct AIAgentPick: Hashable, Sendable, Codable {
    public let kind: AIProviderKind
    public let model: String?
    public init(kind: AIProviderKind, model: String?) { self.kind = kind; self.model = model }
}

/// What the + menu's agent list shows: the agents that are ready on this Mac with the models each offers (what
/// Settings → Max lists), and the model Settings → Max has chosen for each.
public struct AIAgentMenu: Hashable, Sendable, Codable {
    public var agents: [AIAgentStatus]
    public var models: [AIProviderKind: String]
    /// The agent Settings → Max resolves to now (`.auto` included).
    public var active: AIProviderKind?
    public init(agents: [AIAgentStatus], models: [AIProviderKind: String], active: AIProviderKind?) { self.agents = agents; self.models = models; self.active = active }
}

/// What the user gave the conversation, before Brk looks it up.
public enum AIAttachmentSource: Hashable, Sendable, Codable {
    /// A tab by its agent id (`AgentTabFacts.id`).
    case tab(String)
    case folder(ItemID)
    case space(SpaceID)
}

/// A chip in the panel's input and the tabs behind it.
public struct AIAttachment: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable { case tab, folder, space }
    public let kind: Kind
    /// The tab's agent id, the folder's item id or the Space's id.
    public let id: String
    public let title: String
    public let tabs: [AIAttachedTab]
    public init(kind: Kind, id: String, title: String, tabs: [AIAttachedTab]) { self.kind = kind; self.id = id; self.title = title; self.tabs = tabs }
}
public struct AIAttachedTab: Hashable, Sendable, Codable {
    public let id: String
    public let title: String
    public let url: URL?
    /// A tab of another profile than the conversation's: the user gave it, so the agent may read it, and nothing else of
    /// that profile.
    public let otherProfile: Bool
    public init(id: String, title: String, url: URL?, otherProfile: Bool) { self.id = id; self.title = title; self.url = url; self.otherProfile = otherProfile }
}
/// What @ offers while the user types after it: open tabs first, then archived ones, then history.
public struct AIMentionSnapshot: Hashable, Sendable, Codable {
    public let query: String
    public var matches: [AIAttachedTab]
    public init(query: String, matches: [AIAttachedTab]) { self.query = query; self.matches = matches }
}
public struct AITranslationExclusions: Hashable, Sendable, Codable {
    public var languages: Set<String> = []
    public var sites: Set<String> = []
    public init() {}
}
extension MaxSettings {
    /// Max on, and the user's switch, else "Automatically enable future … features" for a feature never switched.
    public func enabled(_ feature: AIFeature) -> Bool { isOn && switched(feature) }
    /// The switch alone, kept while Max is off.
    public func switched(_ feature: AIFeature) -> Bool { features?[feature] ?? autoEnableFutureFeatures ?? false }
}

/// Arc's 5-Second Preview card (P45-a): under the hovered link, the summary's title and two to four details, each an
/// SF Symbol, a bold label and a short line (Arc's `HoverCardViewModel` answer card: quickSummary, details with
/// label, icon and info).
public struct AIPreviewSnapshot: Equatable, Sendable, Codable {
    public var url: URL
    /// The page the hovered link is on, and the link's box in that page's surface (points, top-left origin); nil
    /// when the page could not say, and the card then sits at the top of the page.
    public var page: PageID
    public var link: CGRect?
    public var busy: Bool
    public var title: String
    public var details: [AIPreviewDetail] = []
    /// Arc's "No preview available" and Brk's actionable failures, in place of the details.
    public var failure: String? = nil
    /// The summary request while it runs.
    public var request: AIRequestID? = nil
}
public struct AIPreviewDetail: Hashable, Sendable, Codable {
    public let label: String
    public let icon: String
    public let info: String
    public init(label: String, icon: String, info: String) { self.label = label; self.icon = icon; self.info = info }
}
/// The summary the tool returns for a preview (Arc's `Response`): `blocked` when the page asks for JavaScript or a
/// security check, else a 3-8 word `quickSummary` and two to four `details`.
public struct AIPreviewReply: Hashable, Sendable, Codable {
    public var blocked: Bool?
    public var quickSummary: String?
    public var details: [AIPreviewDetail]?
}
/// The URL pill's second line (Arc: "Translation Available" on a page in a language other than the system's;
/// "Translated", underlined under the pointer, once translated). Nil: no second line.
public enum PillTranslation: Equatable, Sendable, Codable {
    case available
    case translating
    /// The popover's "Translated from French." names the page's own language.
    case translated(from: String)
}
/// A page translated in place (P50-b): which document, its own language and the one it was translated to, and
/// whether the translation or the original text shows now. Session only.
struct AIPageTranslation: Equatable, Sendable {
    let document: DocumentToken
    let source: String
    var target: String
    var showingTranslation: Bool
}
/// Arc's Instant Links row at the top of Today while Max looks ("Searching the web for you…", Max's flower), and
/// "Oops, something went wrong." when nothing could be opened. Session only; the row's × removes it.
struct AIInstantRow: Equatable, Sendable {
    let id: ItemID
    let request: AIRequestID
    var failed = false
    var opened: [ItemID] = []
}

public struct AISource: Hashable, Sendable, Codable {
    public let title: String
    public let url: URL
    public init(title: String, url: URL) { self.title = title; self.url = url }
}
public struct AIAnswerSnapshot: Equatable, Sendable, Codable {
    public var request: AIRequestID?
    public var title: String
    public var text: String
    public var busy: Bool
    public var sources: [AISource]
    public var isPreview: Bool = false
    public var canUndo: Bool = false
    public var language: String? = nil
    public var site: String? = nil
    /// The conversation shown in the panel; nil for a plain message (a feature that is off, a failure before asking).
    public var conversation: AIConversationSnapshot? = nil
    /// The pages the conversation's items show, filled in by the projection (`AppState.withPages`).
    public var pages: [AIPageSnapshot] = []
    /// The conversation's name, its saved title (the projection fills it in); nil before it has one.
    public var name: String? = nil
}

/// A conversation with a local agent in the Max panel. Session only, one per window. Its id is the first request's.
public struct AIConversationSnapshot: Equatable, Sendable, Codable {
    public let id: AIRequestID
    /// The agent as the app resolved it, its name for the header. Nil until the session started.
    public var agent: AIProviderKind? = nil
    public var agentName: String? = nil
    /// The model the agent says it runs, and the effort asked for. Nil: the agent's default, not told.
    public var model: String? = nil
    public var effort: String? = nil
    /// The folder the user chose for a session with tools on. Nil: tools off, the agent's strictest read-only mode.
    public var folder: String? = nil
    public var items: [AIConversationItem] = []
    /// The session ended for good (another agent chosen, Max off); no more messages.
    public var ended = false
    /// Brk's tab tools are on: the agent reads and changes this profile's tabs, and its own tools ask every time.
    public var tabs = false
    /// No message sent yet: the session starts with the first one.
    public var fresh = false
    /// The chips waiting in the input for the next message.
    public var attached: [AIAttachment] = []
    public var mention: AIMentionSnapshot? = nil
    /// Shown from its saved transcript with no session behind it (after a relaunch, or put away): the next message
    /// starts one, continuing the agent's own session where the agent keeps one.
    public var dormant = false
    /// The agent and model chosen in the + menu for its next messages; nil: Settings → Max's.
    public var pick: AIAgentPick? = nil
    public init(id: AIRequestID, folder: String? = nil, tabs: Bool = false) { self.id = id; self.folder = folder; self.tabs = tabs }
}
public enum AIConversationItem: Equatable, Sendable, Codable {
    case user(String)
    case assistant(String)
    case step(AIAgentStep)
    case approval(AIAgentApproval)
    case notice(String)
    /// A page the agent rendered (`brk_html_render`), shown inline where it was made.
    case page(AIPageRef)
}
/// What an agent's step or approval does, as Brk tells it from the tool's name: the panel words it in the conversation's
/// language and sums up a run of steps in plain words (`AIStepWords`). Nil: a tool Brk has no name for; its title shows
/// as the agent gave it.
public enum AIStepKind: String, Hashable, Sendable, Codable {
    case listTabs, searchTabs, readTab, openTab, showTab, closeTabs, moveTabs, groupTabs, splitTabs
    case listConversations, searchConversations, readConversation
    case previewPage, makePage, keepPage, changePage, readSource, writeData
    case command, readFile, writeFile, editFile, searchFiles, fetchPage, searchWeb, helper, taskList, skill
}
/// One thing the agent does (a command, a file edit, a search), as it reports it.
public struct AIAgentStep: Equatable, Sendable, Codable {
    public enum State: String, Equatable, Sendable, Codable { case running, done, failed }
    public let id: String
    /// The agent's own words for it, in English: what shows when `kind` is nil.
    public var title: String
    public var state: State
    public var kind: AIStepKind? = nil
    /// What it acts on, as the agent gave it: the command, the file, the search words, the address.
    public var subject: String? = nil
    public init(id: String, title: String, state: State, kind: AIStepKind? = nil, subject: String? = nil) {
        self.id = id; self.title = title; self.state = state; self.kind = kind; self.subject = subject
    }
}
/// A tool the agent wants to run and may not without the user's answer. `options` come from the agent.
public struct AIAgentApproval: Equatable, Sendable, Codable {
    public struct Option: Equatable, Sendable, Codable {
        public enum Kind: String, Equatable, Sendable, Codable { case allowOnce, allowSession, deny }
        public let id: String
        public let title: String
        public let kind: Kind
        public init(id: String, title: String, kind: Kind) { self.id = id; self.title = title; self.kind = kind }
    }
    public let id: String
    public let title: String
    public let detail: String
    public let options: [Option]
    /// The option chosen; nil while the agent waits.
    public var answer: String? = nil
    /// What the tool would do (`AIStepKind`) and on what, for the card's one plain sentence; nil: the title is the sentence.
    public var kind: AIStepKind? = nil
    public var subject: String? = nil
    public init(id: String, title: String, detail: String, options: [Option], kind: AIStepKind? = nil, subject: String? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.options = options; self.kind = kind; self.subject = subject
    }
}
/// What a running session reports (`SystemEvent.aiConversation`). Text arrives as `aiPartial` and `aiResult`.
public enum AIConversationEvent: Equatable, Sendable, Codable {
    case started(agent: AIProviderKind, name: String, model: String?, effort: String?)
    case step(AIAgentStep, turn: AIRequestID)
    case approval(AIAgentApproval, turn: AIRequestID)
    /// The agent no longer waits for this approval (the turn ended, or it was answered elsewhere).
    case approvalClosed(String)
    case notice(String)
    /// The agent's own session id after a turn, which a later launch continues; nil when it keeps none.
    case resumable(String?)
    /// Page text reached the conversation through Brk's tools; `flagged` when the injection check flagged it.
    case pageText(flagged: Bool)
    /// The agent rendered a page (`brk_html_render`); the app has written its HTML file.
    case page(AIPageRecord)
    /// The agent changed one of this conversation's pages (`brk_page_update`): new HTML (already written to its file),
    /// data, title or height; nil leaves that as it was.
    case pageUpdated(AIPageID, html: Bool, data: String?, schema: String?, saveSchema: String?, title: String?, height: Int?)
    /// The agent read, opened or showed these tabs with Brk's tab tools (`AgentTabFacts.id`): the conversation used them.
    case usedTabs([String])
}

/// What an installed agent says about itself, read without sending the model anything (the Max pane, the panel).
public struct AIAgentStatus: Hashable, Sendable, Codable {
    public enum State: Hashable, Sendable, Codable {
        case missing, checking, ready, notSignedIn
        case failed(String)
    }
    public let kind: AIProviderKind
    public var state: State
    public var version: String? = nil
    public var models: [AIAgentModel] = []
    public init(kind: AIProviderKind, state: State, version: String? = nil, models: [AIAgentModel] = []) {
        self.kind = kind; self.state = state; self.version = version; self.models = models
    }
}
public struct AIAgentModel: Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let efforts: [String]
    public let isDefault: Bool
    public init(id: String, name: String, efforts: [String] = [], isDefault: Bool = false) {
        self.id = id; self.name = name; self.efforts = efforts; self.isDefault = isDefault
    }
}

struct AIRequest: Equatable, Sendable {
    let window: WindowID
    let context: BrowsingContext
    var task: AITask
    var document: DocumentToken?
    var hidden: [PageSpec] = []
    var hiddenDocuments: [PageID: DocumentToken] = [:]
    var contents: [PageID: AIPageContent] = [:]
    var extracting: Set<PageID> = []
    /// Readers whose read failed once and were asked again.
    var readAgain: Set<PageID> = []
    var purpose: AIPurpose
    /// Translation: the page being translated and the translated nodes sent to it.
    var page: PageID? = nil
    var translated: [AITextNode] = []
}
enum AIPurpose: Equatable, Sendable {
    case answer, askPage(String), preview(URL), instant(String), browse(String), translate(String), organize, followUp
    /// The `translate` prefix: the answer goes in the bar's row.
    case barTranslation
    /// A page read for an agent's `brk_tab_read` call: the text goes back to the tool, not to the panel.
    case agentRead(String)
}
extension AIPurpose {
    /// Purposes that show in their own place (the preview card, the Today row, the URL pill and its popover, the
    /// Tidy button and a toast), not in the answer panel.
    var inPlace: Bool {
        switch self {
        case .preview, .instant, .translate, .organize, .barTranslation, .agentRead: true
        case .answer, .askPage, .browse, .followUp: false
        }
    }
}
struct AIOrganizeUndo: Equatable, Sendable {
    let space: SpaceID
    let original: [ItemID]
    let folders: [ItemID: [ItemID]]
}
struct AISession: Equatable, Sendable {
    var requests: [AIRequestID: AIRequest] = [:]
    var backgroundContexts: [AIRequestID: BrowsingContext] = [:]
    var answers: [WindowID: AIAnswerSnapshot] = [:]
    var answerContexts: [WindowID: BrowsingContext] = [:]
    var undo: [WindowID: AIOrganizeUndo] = [:]
    var hover: [WindowID: URL] = [:]
    var hoverDocuments: [WindowID: DocumentToken] = [:]
    var previews: [WindowID: AIPreviewSnapshot] = [:]
    /// The pointer is over the window's preview card.
    var previewHeld: Set<WindowID> = []
    var translations: [PageID: AIPageTranslation] = [:]
    var instantRows: [WindowID: [AIInstantRow]] = [:]
    /// The Today tidy in flight, by window: the Tidy button shows it is working.
    var tidying: Set<WindowID> = []
    /// What each agent said about itself last (`SystemEvent.aiAgents`); only for the Max pane and `.auto`.
    var agents: [AIProviderKind: AIAgentStatus] = [:]
    /// By conversation: how much of the running turn's text rows above its last step already show.
    var turnText: [AIRequestID: Int] = [:]
    /// A background request's window (Tidy Tab Titles, Tidy Downloads): where its result or failure is told.
    var backgroundWindows: [AIRequestID: WindowID] = [:]
    /// Name Tabs, Place New Tabs and the folder names (Rules/AssistBasic.swift).
    var basic = AIBasicSession()
    /// Which services have a key in the Keychain and their last Test (`SystemEvent.aiKeys`).
    var keys: [AIService: AIKeyStatus] = [:]
    /// JevK5 on this Mac can answer decisions now (reported with the keys).
    var localDecisions = false
    /// A download Max is renaming in the background, and the window that started it.
    var renamingDownloads: [DownloadID: WindowID] = [:]
    /// Live conversations outside a panel: still running out of sight (Rules/ConversationLive.swift). A panel's
    /// conversation stays in `answers`.
    var awayAnswers: [AIRequestID: AIAnswerSnapshot] = [:]
    /// The window a conversation out of sight runs in: the one whose panel showed it last.
    var awayWindows: [AIRequestID: WindowID] = [:]
    /// A link in an agent's page that asks before it opens, by window.
    var linkPrompts: [WindowID: AIPageLinkPrompt] = [:]
    /// Live pages refreshing now, and the run of each (Rules/LivePageRules.swift).
    var refreshing: [AIPageID: AIRequestID] = [:]
    /// Refreshing pages whose data the run has changed.
    var refreshChanged: Set<AIPageID> = []
    /// Each page's saves in the current minute (the rate cap).
    var pageSaves: [AIPageID: AIPageSaveCount] = [:]
    /// The panel's page while the panel is open in a standard window (Rules/ConversationLists.swift); absent: closed.
    var panelPage: [WindowID: AIPanelPage] = [:]
    /// The Space whose list and conversation the open panel shows: a window that moves to another Space swaps them.
    var panelSpace: [WindowID: SpaceID] = [:]
    /// What each Space's panel showed last in a window: the conversation and the page.
    var panelMemory: [WindowID: [SpaceID: AIPanelMemory]] = [:]
    /// The list's search text.
    var panelSearch: [WindowID: String] = [:]
    /// When each conversation's running turn began (a reply that ran over a minute is told when Brk is not in front).
    var turnStarted: [AIRequestID: Instant] = [:]
    /// The Library's "AI 对话" page: its search and filters, and the conversation it shows in full.
    var libraryQuery: [WindowID: ConversationLibraryQuery] = [:]
    var librarySelection: [WindowID: AIRequestID] = [:]
    /// The list row being renamed.
    var renamingConversation: [WindowID: AIRequestID] = [:]
    /// Delete for good, waiting for Cancel or Delete in the window's dialog.
    var pendingConversationDeletion: [WindowID: ConversationDeletionRequest] = [:]
    /// The saved conversations were read at launch (`SystemEvent.conversationsLoaded`): only then can a conversation row
    /// left in the sidebar be moved off it, its Space read first (docs/design/ai-right-panel.md).
    var conversationsLoaded = false
    /// The list row under the pointer, and the chip under it: what the sidebar lights (docs/design/ai-right-panel.md).
    var hoveredConversation: [WindowID: AIRequestID] = [:]
    var hoveredChip: [WindowID: String] = [:]
    /// Conversation names asked of the basic model, by request; and the conversations asked about this session.
    var conversationNaming: [AIRequestID: AIRequestID] = [:]
    var namedAsked: Set<AIRequestID> = []
}
/// A Space's panel as it was left.
struct AIPanelMemory: Equatable, Sendable {
    var conversation: AIRequestID?
    var page: AIPanelPage
}
struct AIPageSaveCount: Equatable, Sendable {
    var minute: Int64
    var saves: Int
}
public struct AIGroupPlan: Hashable, Sendable, Codable {
    public let folder: String
    public let tabs: [String]
    public init(folder: String, tabs: [String]) { self.folder = folder; self.tabs = tabs }
}
/// A basic task's answer in its schema's shape (`AITask.isBasic`). The agent's CLI checked it against the schema; the
/// reducer still checks it against the browser (ids, lengths, the tab not changed meanwhile).
public enum AIReply: Hashable, Sendable, Codable {
    /// One line: a tab or folder name, a filename, a translation.
    case text(String)
    /// `nameTabs`: a name per tab id.
    case tabNames([String: String])
    /// `tidyToday`: the groups, each named.
    case groups([AIGroupPlan])
    case preview(AIPreviewReply)
    /// `instant`: the proposed addresses, not yet checked.
    case links([String])
    case translation([AITextNode])
    case decision(DecisionAnswers)
}
/// A tab's name from Name Tabs, and the site it was made for: a tab that moves to another site is named again.
public struct AITabName: Hashable, Sendable, Codable {
    public var title: String
    public var host: String
    public init(title: String, host: String) { self.title = title; self.host = host }
}
/// Language codes and names for translation: a page's `lang` ("fr", "fr-CA"), the system's, the popover's
/// "Translated from French." and the Options menu's Choose Another Language list (Chromium's translate languages,
/// in the order and with the names of Arc's submenu, P50-f-languages).
/// Arc's words for the AI features' in-place surfaces (strings in Arc 1.170's binary).
public enum AICopy {
    /// "Title for an in progress web search item".
    public static let instantSearching = "Searching the web for you…"
    /// "Title for web search item that failed".
    public static let instantFailed = "Oops, something went wrong."
    /// The Tidy button and its tooltip on the Today divider ("Button Title; Tidy unpinned tabs in this space",
    /// "Tooltip; Use LLM to organize unpinned tabs in this space").
    public static let tidy = "Tidy"
    public static let tidyTooltip = "Organize Today Tabs"
    public static let translationAvailable = "Translation Available"
    /// "Title for the share quote affordance below the URL".
    public static let shareQuote = "Share Quote"
    public static let translated = "Translated"
    public static let translating = "Translating…"
    public static func translatedFrom(_ language: String) -> String { "Translated from \(language)." }
    public static let options = "Options"
    public static let useOriginal = "Use Original"
    /// P50-g: the popover of a page that can be translated, and its button.
    public static func translateOffer(_ language: String) -> String { "Translate this page to \(language)?" }
    public static let translate = "Translate"
    public static let chooseAnotherLanguage = "Choose Another Language"
    public static let neverTranslateSite = "Never Translate This Site"
    public static let languageSettings = "Language Settings"
    public static let noPreview = "No preview available"
}

public enum AILanguages {
    public static func base(_ code: String) -> String {
        String(code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
    }
    /// The system's first language as Translate to … names it ("English").
    public static var systemTarget: String { name(Locale.preferredLanguages.first ?? "en") }
    public static func name(_ code: String) -> String {
        let base = base(code)
        guard !base.isEmpty else { return "another language" }
        return Locale(identifier: "en_US").localizedString(forLanguageCode: base) ?? base
    }
    public static let targets: [String] = [
        "Afrikaans", "Akan", "Albanian", "Amharic", "Arabic", "Armenian", "Assamese", "Aymara", "Azerbaijani", "Bambara", "Bangla",
        "Basque", "Belarusian", "Bhojpuri", "Bosnian", "Bulgarian", "Burmese", "Catalan", "Cebuano", "Central Kurdish",
        "Chinese (Simplified)", "Chinese (Traditional)", "Corsican", "Croatian", "Czech", "Danish", "Divehi", "Dogri", "Dutch",
        "English", "Esperanto", "Estonian", "Ewe", "Filipino", "Finnish", "French", "Galician", "Ganda", "Georgian", "German",
        "Goan Konkani", "Greek", "Guarani", "Gujarati", "Haitian Creole", "Hausa", "Hawaiian", "Hebrew", "Hindi", "Hmong",
        "Hungarian", "Icelandic", "Igbo", "Iloko", "Indonesian", "Irish", "Italian", "Japanese", "Javanese", "Kannada", "Kazakh",
        "Khmer", "Kinyarwanda", "Korean", "Krio", "Kurdish", "Kyrgyz", "Lao", "Latin", "Latvian", "Lingala", "Lithuanian",
        "Luxembourgish", "Macedonian", "Maithili", "Malagasy", "Malay", "Malayalam", "Maltese", "Manipuri (Meitei Mayek)", "Māori",
        "Marathi", "Mizo", "Mongolian", "Nepali", "Northern Sotho", "Norwegian", "Nyanja", "Odia", "Oromo", "Pashto", "Persian",
        "Polish", "Portuguese", "Punjabi", "Quechua", "Romanian", "Russian", "Samoan", "Sanskrit", "Scottish Gaelic", "Serbian",
        "Shona", "Sindhi", "Sinhala", "Slovak", "Slovenian", "Somali", "Southern Sotho", "Spanish", "Sundanese", "Swahili",
        "Swedish", "Tajik", "Tamil", "Tatar", "Telugu", "Thai", "Tigrinya", "Tsonga", "Turkish", "Turkmen", "Ukrainian", "Urdu",
        "Uyghur", "Uzbek", "Vietnamese", "Welsh", "Western Frisian", "Xhosa", "Yiddish", "Yoruba", "Zulu",
    ]
}

public enum AIValidation {
    public static func destination(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 2048, !trimmed.contains(where: \.isWhitespace),
              let c = URLComponents(string: trimmed), ["https", "http"].contains(c.scheme?.lowercased()),
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              let url = c.url else { return nil }
        return url
    }
    /// Instant Links: the tool's addresses, the safe ones, at most six, each once.
    public static func destinations(_ links: [String]) -> [URL] {
        var out: [URL] = []
        for link in links {
            guard out.count < 6, let url = destination(link), !out.contains(url) else { continue }
            out.append(url)
        }
        return out
    }
    /// The preview card's answer, trimmed to what the card shows: a summary up to 120 characters and up to four
    /// details; a detail with an unknown symbol gets a dot.
    public static func preview(_ reply: AIPreviewReply) -> AIPreviewReply? {
        var reply = reply
        reply.quickSummary = reply.quickSummary.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)) }
        reply.details = Array((reply.details ?? []).filter { !$0.info.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(4)).map {
            AIPreviewDetail(label: String($0.label.prefix(40)), icon: $0.icon.isEmpty || $0.icon.count > 60 ? "circle.fill" : $0.icon, info: String($0.info.prefix(160)))
        }
        return reply.blocked == true || reply.quickSummary?.isEmpty == false || reply.details?.isEmpty == false ? reply : nil
    }
    public static func citations(_ text: String, sourceCount: Int) -> Bool {
        guard sourceCount > 0, let pattern = try? NSRegularExpression(pattern: #"\[(\d+)\]"#) else { return false }
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return !matches.isEmpty && matches.allSatisfy { match in
            guard let range = Range(match.range(at: 1), in: text), let number = Int(text[range]) else { return false }
            return (1...sourceCount).contains(number)
        }
    }
    public static func plan(_ groups: [AIGroupPlan], eligible: [AITab]) -> [AIGroupPlan]? {
        guard (1...12).contains(groups.count),
              groups.allSatisfy({ !$0.folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.folder.count <= 60 && !$0.tabs.isEmpty }) else { return nil }
        // Every id must be one Brk sent, once; a tab a small model left out stays in Today ungrouped.
        let ids = groups.flatMap(\.tabs)
        guard Set(ids).count == ids.count, Set(ids).isSubset(of: Set(eligible.map { $0.id.rawValue })) else { return nil }
        return groups
    }
    /// Why this folder cannot be a session's working folder, nil when it can. Home and every folder above it hold
    /// everything the user has; a coding session gets one project.
    public static func workingFolderRefusal(_ folder: String, home: String) -> String? {
        let standard = (folder as NSString).standardizingPath
        guard standard.hasPrefix("/") else { return "Choose a folder on this Mac." }
        let home = (home as NSString).standardizingPath
        if standard == "/" || standard == home || home.hasPrefix(standard + "/") { return "Choose a project folder, not your home folder or a folder above it." }
        return nil
    }
    /// Keep the original extension; replies may suggest only a filename stem, never a path.
    public static func filename(_ text: String, original: String) -> String? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.contains(where: { $0.isNewline || $0.isASCII && $0.asciiValue! < 32 }),
              !line.contains("/"), !line.contains("\\"), !line.contains(":"), !line.hasPrefix("."), line != ".." else { return nil }
        let ext = (original as NSString).pathExtension
        let raw = !ext.isEmpty && line.lowercased().hasSuffix("." + ext.lowercased()) ? String(line.dropLast(ext.count + 1)) : line
        let stem = String(raw.trimmingCharacters(in: CharacterSet(charactersIn: " .\"'")).prefix(100))
        guard !stem.isEmpty, !stem.hasPrefix(".") else { return nil }
        return ext.isEmpty ? stem : stem + "." + ext
    }
}
