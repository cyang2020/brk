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
    case window(WindowID, WindowEffect)
    case app(AppEffect)
    /// A native popup menu built from state; each entry carries the command it dispatches when chosen.
    case popupMenu(WindowID, MenuModel, at: CGPoint)
    /// Share-by-link replaced by a file: BrkApp shows a save panel (JSON or HTML) and writes `ExportCodec`'s bytes.
    case export(ExportDocument, owner: WindowID)
    case exportSpaceFolder(WindowID, token: String, document: ExportDocument)
    /// Run a task through the local AI command-line tool (BrkApp/AIProvider.swift); the answer comes back as
    /// `SystemEvent.aiResult(id, outcome)`. `choice` is the Max setting; `detected` what launch found on PATH.
    case ai(AIRequestID, AITask, choice: AIProviderChoice)
    case aiCancel(AIRequestID)
    case aiRead(AIRequestID, DocumentToken)
    case aiTranslate(AIRequestID, AIPageContent, [AITextNode])
    case aiWatch(AIRequestID, seconds: Int)
    case aiHover(WindowID, URL?)
    case aiRenameDownload(DownloadID, originalPath: String, filename: String)
    /// Fetch the default engine's OpenSearch suggestions for `query` (BrkApp debounces by
    /// Metrics.commandBar.suggestionDebounce); the answer is `SystemEvent.suggestions(window, query:, results)`.
    case fetchSuggestions(WindowID, query: String, url: URL)
    /// Drop a request context's data: incognito when its last window closed, a profile when it was deleted.
    case disposeContext(ContextDisposal)
    case loadWebsiteRules(URL, BrowsingContext)
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
