import BrkBase
import CoreGraphics
import Foundation

/// What the reducer asks the outside world to do, besides changing state. Executed by `AppStore` after the new
/// snapshot is rendered (so a page created by this transition exists before it is navigated).
///
/// Only imperative one-shots are effects. Anything that is a function of state (which pages are live, which windows
/// exist, what has keyboard focus, frames) is derived from the snapshot and reconciled, never sent as an effect.
public enum Effect: Hashable, Sendable {
    case capture(CaptureEffect)
    case easel(EaselEffect)
    case sound(MediaSoundEvent)
    case find(FindRequest)
    case boost(BoostEffect)
    case sidebarData(SidebarDataEffect)
    case page(PageID, PageAction)
    case iconPicker(WindowID, ItemID, initial: CustomIcon? = nil)
    case siteRequest(SiteRequest)
    case output(OutputRequest)
    case cancelOutput(OutputID)
    case copyToPasteboard(String)
    /// Shared Quotes: read the page's highlighted text, then copy `SharedQuote.text` for it (the plain copy when
    /// nothing is highlighted).
    case copySharedQuote(PageID, url: URL, title: String, format: CopyURLFormat)
    case window(WindowID, WindowEffect)
    case app(AppEffect)
    /// A native popup menu built from state; each entry carries the command it dispatches when chosen.
    case popupMenu(WindowID, MenuModel, at: CGPoint)
    /// Share-by-link replaced by a file: BrkApp shows a save panel (JSON or HTML) and writes `ExportCodec`'s bytes.
    case export(ExportDocument, owner: WindowID)
    case exportSpaceFolder(WindowID, token: String, document: ExportDocument)
    /// Run a task through a local agent (BrkApp/AIProvider.swift); the answer comes back as
    /// `SystemEvent.aiResult(id, outcome)`. `choice` picks the agent for this request: an agent named explicitly runs or
    /// says why it cannot, never another one; only `.auto` chooses, from what is installed and signed in.
    case ai(AIRequestID, AITask, choice: AIProviderChoice)
    case aiCancel(AIRequestID)
    /// Keep a session for this conversation; it stays for `aiTurn`. `folder` nil: tools off, strictest read-only mode, and
    /// the `.ai` request with the same id is its first turn and names its agent. A folder: tools on, approvals on, chosen
    /// by the user, and this `choice` names the agent.
    /// `tabs`: the window whose profile Brk's tab tools serve (`AgentTabs`); the agent's own tools then ask every time.
    case aiOpenConversation(AIRequestID, folder: String?, choice: AIProviderChoice, tabs: WindowID? = nil)
    /// The chips sent with the conversation's next message; the agent reads their text with Brk's tools.
    case aiAttach(AIRequestID, [AIAttachment])
    /// The text after @ changed. The title and address matches are already in the snapshot; this is where a search by
    /// meaning can add its own (`SystemEvent.aiMentionMatches`). BrkApp has none yet.
    case aiMentionSearch(WindowID, String)
    /// The answer to `SystemEvent.agentRead` and `SystemEvent.agentAct`, for the tool call `call`.
    case agentReadDone(String, AgentReadOutcome)
    case agentActDone(String, AgentActOutcome)
    /// The next user message in a conversation; it answers as request `turn` (`aiPartial`, `aiResult`).
    case aiTurn(conversation: AIRequestID, turn: AIRequestID, AITask)
    case aiApprove(conversation: AIRequestID, approval: String, option: String)
    /// The conversation is over: its session and every process it started go.
    case aiCloseConversation(AIRequestID)
    /// Ask the user for a working folder; the answer is `SystemEvent.aiFolderChosen`.
    case aiChooseFolder(WindowID)
    /// Ask every installed agent about itself; the answer is `SystemEvent.aiAgents`. Nothing is sent to a model.
    case aiRefreshAgents
    case aiRead(AIRequestID, DocumentToken)
    case aiTranslate(AIRequestID, AIPageContent, [AITextNode])
    case aiWatch(AIRequestID, seconds: Int)
    /// The link under the pointer in the window's shown document, or none: BrkApp waits for Shift held over it (Arc's
    /// 5-Second Previews), asks the document where the link is and answers `SystemEvent.aiHoverReady`.
    case aiHover(WindowID, URL?, DocumentToken?)
    /// Swap a translated page between the translation and its own text (Use Original, ⌘Z after it).
    case aiShowTranslation(DocumentToken, translated: Bool)
    case aiRenameDownload(DownloadID, originalPath: String, filename: String)
    /// Fetch the default engine's OpenSearch suggestions for `query` (BrkApp debounces by
    /// Metrics.commandBar.suggestionDebounce); the answer is `SystemEvent.suggestions(window, query:, results)`.
    case fetchSuggestions(WindowID, query: String, url: URL)
    /// Look for a file and app by name (BrkApp debounces like the suggestions); the answer is `SystemEvent.localResults`.
    case searchLocal(WindowID, LocalSearchRequest)
    /// A text to translate under the `translate` prefix: after a pause in typing the answer is
    /// `SystemEvent.barTranslationDue`. Any later key cancels it.
    case barTranslationDue(WindowID, String)
    /// Ask macOS's offline dictionary about a word (BrkApp debounces); the answer is `SystemEvent.definition`.
    case lookUpWord(WindowID, String)
    /// The word in Dictionary.app, through its `dict:` address.
    case openDictionary(String)
    /// Open a file with its default app, or launch an app.
    case openLocalFile(String)
    /// A currency question was typed: BrkApp reads its cache and fetches at most once a day; the answer is
    /// `SystemEvent.currencyRates`.
    case needCurrencyRates
    /// Drop a request context's data: incognito when its last window closed, a profile when it was deleted.
    case disposeContext(ContextDisposal)
    case loadWebsiteRules(URL, BrowsingContext)
    /// Download a subscription's text into `FilterListStore`; the answer is `SystemEvent.filterListFetched`.
    case fetchFilterList(BrowsingContext, FilterListRecord)
    case chooseWebsiteRules(WindowID, BrowsingContext)
    case editExtension(String, ExtensionEdit, BrowsingContext)
    case queryExtensions(BrowsingContext)
    case invokeExtension(String, SiteTarget)
    case removeExtension(String, BrowsingContext, PageID)
    case cancelSiteData(String)
    case clearSiteData(ClearSiteData)
    case clearProfileData(ClearProfileData)
    case confirmSiteData(ClearSiteData)
    case confirmLocalExtension(WindowID, BrowsingContext, URL)
    case installLocalExtension(PageID, BrowsingContext, URL)
    case addLocalExtension(WindowID, BrowsingContext)
    case cancelDownload(DownloadID)
    /// Reveal a downloaded file in the Finder.
    case revealFile(String)
}

/// What "Share…" produces: a title and a tree of entries (folders keep their children). `ExportCodec` (Codec.swift)
/// turns it into JSON or Netscape bookmark HTML, so the file format has one home.
public struct ExportDocument: Hashable, Sendable, Codable {
    public var title: String
    public var entries: [ExportEntry]
    public init(title: String, entries: [ExportEntry]) {
        self.title = title
        self.entries = entries
    }
}

public enum ExportEntry: Hashable, Sendable, Codable {
    case link(title: String, url: URL)
    indirect case folder(title: String, children: [ExportEntry])
}

public enum ExportFormat: String, Hashable, Sendable, Codable, CaseIterable { case json, html }

public enum ExportOutcome: Hashable, Sendable, Codable {
    case saved(URL), cancelled, failed(String)
    public var message: String {
        switch self {
        case .saved(let url): "Exported \(url.lastPathComponent)"
        case .cancelled: "Export cancelled"
        case .failed(let reason): "Export failed: \(reason)"
        }
    }
}

public enum WindowEffect: Hashable, Sendable {
    /// On the window's screen's visible frame (the next screen's for `nextDisplay`; with one screen it stays).
    case place(WindowSnap)
    case requestArchiveClear
    case toggleFullScreen
    case pageFullScreen(Bool)
    /// Esc with nothing to close: leave full screen if the window is in it, else nothing (the reducer does not
    /// track full-screen state; the window does).
    case leaveFullScreen
    case miniaturize
    /// Close the NSWindow (Shift+Cmd+W on the last standard window: AppKit's close-and-quit path follows).
    case close
}

public enum AppEffect: Hashable, Sendable {
    /// Starts the ordered shutdown (BrkApp/Lifecycle.swift): flush state, close pages, CEF shutdown, exit.
    case quit
    case hide
    case hideOthers
    case beep
    /// The standard about panel.
    case showAbout
    /// Raises the existing settings window even when the requested pane is already open.
    case showSettings
    /// `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` for http and https (macOS asks the user).
    case registerAsDefaultBrowser
    /// The data directory in the Finder.
    case revealDataDirectory
    /// A Help menu row BrkApp runs (`HelpAction`; never `.open`, which the reducer handles): `owner` is the window it
    /// came from, where a resolved page opens and an alert attaches.
    case help(HelpAction, owner: WindowID)
    /// An Edit menu item reached through a remapped chord while a page had the key (`AppCommand.standardEdit`).
    case standardEdit(StandardEdit)
}

public struct MenuModel: Hashable, Sendable {
    public var entries: [MenuEntry]
    public init(entries: [MenuEntry]) { self.entries = entries }
}

public enum MenuEntry: Hashable, Sendable {
    case action(title: String, command: Command, enabled: Bool)
    /// A choice with a check mark when `on` (Set Profile's profiles).
    case choice(title: String, command: Command, on: Bool)
    /// A grey caption that cannot be chosen (the split menu's "Tab Options").
    case header(String)
    /// A row that opens `entries` to its right (Share, Move to, Set Profile). An empty submenu shows disabled.
    case submenu(title: String, entries: [MenuEntry])
    case separator
}

extension MenuModel {
    /// Every choosable row, submenus included, depth first: (title, command, enabled).
    public var actions: [(title: String, command: Command, enabled: Bool)] {
        func walk(_ entries: [MenuEntry]) -> [(title: String, command: Command, enabled: Bool)] {
            entries.flatMap { entry -> [(title: String, command: Command, enabled: Bool)] in
                switch entry {
                case .action(let title, let command, let enabled): [(title, command, enabled)]
                case .choice(let title, let command, _): [(title, command, true)]
                case .submenu(_, let children): walk(children)
                case .header, .separator: []
                }
            }
        }
        return walk(entries)
    }
}
