import BrkBase
import Foundation

// Owner: F1 (model and rules), with F2 (per-profile values), F3 (Links), F4 (Shortcuts). The settings model mirrors
// Arc's panes (anatomy-m 4.1, 4.2): General, Profiles (one record per profile), Links, Shortcuts (`Doc.keyOverrides`),
// Max, Advanced. Account, App Icon and Staff are dropped by the user's decisions (no account, no referrals).
// Every value is saved (`Doc.settings`), changed only through `.settings(...)` commands, and read by the projection
// into `SettingsSnapshot`. Defaults are ours where Arc ships none (anatomy-m 4.1: no defaults plist).

/// The panes of the settings window, in Arc 1.170's toolbar order (P38 captures: account, General, Profiles, Max,
/// Links, Shortcuts, Icon, Advanced), minus the account pane (no account) and staff.
public enum SettingsPane: String, Hashable, Sendable, Codable, CaseIterable {
    case general, profiles, max, links, shortcuts, icon, advanced
}

struct Settings: Sendable, Equatable {
    var general: GeneralSettings
    /// One record per profile in `Doc.profiles`; normalize adds a default record for a profile that lacks one.
    var profiles: [ProfileID: ProfileSettings]
    var links: LinkSettings
    var max: MaxSettings
    var advanced: AdvancedSettings

    static let `default` = Settings(general: .default, profiles: [.default: .default], links: .default, max: .default, advanced: .default)
}

/// Arc's General pane (anatomy-m 4.2). Ad blocker, previews and translation come with their features (later waves).
public struct GeneralSettings: Hashable, Sendable, Codable {
    /// "Warn before quitting" (user default `shouldWarnBeforeQuitting`).
    public var warnBeforeQuitting: Bool
    /// The "is not your default web browser" notice was dismissed for this launch's default-browser state.
    public var defaultBrowserPromptDismissed: Bool
    /// View > Appearance: "Websites, Easels, and Notes will use:" (rows 88 to 90).
    public var webAppearance: WebAppearance
    /// The Icon pane's choice for the Dock and the About window; nil is `.original`.
    public var appIcon: AppIconChoice? = nil
    /// View > Developer > "Allow JavaScript from Apple Events": AppleScript's `execute` runs only while this is on.
    /// Nil (older files) is off, as in Arc and Chrome.
    public var javaScriptFromAppleEvents: Bool? = nil
    /// Arc's ad blocker ("Use Arc's built-in protection against ads, pop-ups, and trackers"): Brk's blocking rules
    /// on every site without its own choice in Website Controls. Nil is on.
    public var blockAds: Bool? = nil
    /// Arc's "Block Cookie Banners": hide matching cookie banners on every site without its own choice. Nil is off.
    public var hideCookieBanners: Bool? = nil

    public static let `default` = GeneralSettings(warnBeforeQuitting: false, defaultBrowserPromptDismissed: false, webAppearance: .automatic)
}

public enum WebAppearance: String, Hashable, Sendable, Codable, CaseIterable { case automatic, light, dark }

/// The app icons the Icon pane offers (Arc: the alternate app icons of its Icon pane). Brk draws its own set.
public enum AppIconChoice: String, Hashable, Sendable, Codable, CaseIterable {
    case original, candy, neon, graphite, schoolbook, colorful
}

/// Arc: `ProfilePreferences.State` (anatomy-m 1.12) plus the profile's auto-archive threshold (anatomy-m 4.3,
/// `AutoArchiveTimeThresholdsPerProfile`).
public struct ProfileSettings: Hashable, Sendable, Codable {
    public var siteSearchEngines: [SearchEngine]? = nil
    public var searchEngine: SearchEngineID
    /// "Include search engine suggestions" (`searchSuggestEnabled`).
    public var searchSuggestions: Bool
    /// "Archive tabs after" for this profile's spaces.
    public var autoArchive: AutoArchiveThreshold
    /// "Download location": a directory path, or nil for the system Downloads folder.
    public var downloadsDirectory: String?
    /// Ask where to save every download (`promptForDownloadFilePath`).
    public var promptForDownloadLocation: Bool
    /// "New documents" (Arc: Default Document App, `defaultDocumentsApp`): what the command bar's New document row
    /// opens in this profile's spaces. Nil is Arc's "——" (none).
    public var documentApp: DocumentApp? = nil

    public static let `default` = ProfileSettings(searchEngine: SearchEngine.google.id, searchSuggestions: true, autoArchive: .default,
                                                  downloadsDirectory: nil, promptForDownloadLocation: false)
}

/// A web app the Profiles pane's "New documents" can name (Arc: `NoteDocument`'s web document types with their
/// `newDocURL`; the addresses are Arc's own table, `BaseModels`: doc.new, sheet.new, slide.new, word.new,
/// app.notion.com/new, figma.new, figjam.new). Arc's own note (`arcNote`) is not one: Brk has no Notes.
public enum DocumentApp: String, Hashable, Sendable, Codable, CaseIterable {
    case googleDocs, googleSheets, googleSlides, microsoftWord, notion, figma, figjam

    /// Where a new document of this app starts.
    public var newDocumentURL: URL {
        switch self {
        case .googleDocs: URL(string: "https://doc.new")!
        case .googleSheets: URL(string: "https://sheet.new")!
        case .googleSlides: URL(string: "https://slide.new")!
        case .microsoftWord: URL(string: "https://word.new")!
        case .notion: URL(string: "https://app.notion.com/new")!
        case .figma: URL(string: "https://figma.new")!
        case .figjam: URL(string: "https://figjam.new")!
        }
    }

    /// The pop-up's name for the app.
    public var title: String {
        switch self {
        case .googleDocs: "Google Docs"
        case .googleSheets: "Google Sheets"
        case .googleSlides: "Google Slides"
        case .microsoftWord: "Microsoft Word"
        case .notion: "Notion"
        case .figma: "Figma"
        case .figjam: "FigJam"
        }
    }

    /// The command bar row (Arc's comment on its string: "Action to create a new document; e.g. 'New Google Doc'").
    public var newDocumentTitle: String {
        switch self {
        case .googleDocs: "New Google Doc"
        case .googleSheets: "New Google Sheet"
        case .googleSlides: "New Google Slides"
        case .microsoftWord: "New Word Document"
        case .notion: "New Notion Page"
        case .figma: "New Figma File"
        case .figjam: "New FigJam Board"
        }
    }
}

/// Arc's Links pane (anatomy-m 4.2, visual-and-copy.md "Little Arc", "Peek", "Air Traffic Control").
public struct LinkSettings: Hashable, Sendable, Codable {
    /// "Links from other apps open in Little Arc" (`openExternalLinksInLittleBrowserEnabled`).
    public var externalLinksInLittleArc: Bool
    /// "Open Little Arc when clicking on links with ⌥⌘ held".
    public var optionCommandClickLittleArc: Bool
    /// "Open a Peek window when clicking on links with Shift held".
    public var shiftClickPeek: Bool
    /// "Open a Peek window when clicking on links to other sites" ("Note: This only affects Favorites and Pinned tabs").
    public var peekFromPinnedAndFavorites: Bool
    /// "Archive Little Arcs after:" (one global value, anatomy-m 4.3).
    public var littleArcAutoArchive: AutoArchiveThreshold
    /// Where an external link with no matching route lands; nil is "Most Recent Space".
    public var defaultRoute: LinkDestination?
    /// "Open Little Arc when I press ⌥⌘N in any app": the system-wide New Little Arc Window shortcut; nil is on.
    public var globalLittleArcShortcut: Bool? = nil

    /// Where a link from another app opens when no route matches: Air Traffic Control's "Default" pop-up. A space
    /// (or an older file's saved Little Arc) wins; otherwise "Links from other apps open in Little Arc" decides
    /// between Little Arc and the most recent space, so the switch and the pop-up always say the same thing.
    public var externalDefault: LinkDestination {
        if let defaultRoute, defaultRoute != .mostRecentSpace { return defaultRoute }
        return externalLinksInLittleArc ? .littleArc : .mostRecentSpace
    }

    /// Little Arcs archive after 6 hours by default ("6 hours (default)" in Arc 1.170's Links pane, P38-f).
    public static let `default` = LinkSettings(externalLinksInLittleArc: true, optionCommandClickLittleArc: true, shiftClickPeek: true,
                                               peekFromPinnedAndFavorites: true, littleArcAutoArchive: .sixHours, defaultRoute: nil)
}

/// One Air Traffic Control route (Arc: `StorableLinkRouting`, edited in `LinkRoutingDialog`): links whose URL
/// matches `pattern` open at `destination`. How the text is compared is `match` (Arc's "URL [Contains ▾]" pop-up);
/// matching is `LinkRoute.matches`.
public struct LinkRoute: Hashable, Sendable, Codable {
    public let id: LinkRouteID
    public var pattern: String
    public var destination: LinkDestination
    /// Nil (routes saved before the pop-up existed) is `.matches`.
    public var match: LinkMatch? = nil

    public init(id: LinkRouteID, pattern: String, destination: LinkDestination, match: LinkMatch? = nil) {
        self.id = id
        self.pattern = pattern
        self.destination = destination
        self.match = match
    }

    /// `.contains`: the URL, lowercased, contains the text (an empty text, a fresh New Route row, matches nothing).
    /// `.matches`: a case-insensitive host match (F3): "spotify.com" matches that host only; "*.spotify.com" matches
    /// the bare host and any subdomain depth. The stored pattern is already normalized (`normalizedPattern`,
    /// Rules/Windows.swift); a pattern typed with a scheme or path still matches because it is normalized here too.
    /// No host: no match.
    public func matches(_ url: URL) -> Bool {
        if match == .contains {
            let text = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !text.isEmpty && url.absoluteString.lowercased().contains(text)
        }
        guard let host = url.host?.lowercased(), let pattern = LinkRoute.normalizedPattern(pattern) else { return false }
        if pattern.hasPrefix("*.") {
            let base = String(pattern.dropFirst(2))
            return host == base || host.hasSuffix("." + base)
        }
        return host == pattern
    }
}

/// How a route compares its text with a link (Arc: `LinkRoutingURLMatchType`, cases `matches` and `contains`, in
/// that order).
public enum LinkMatch: String, Hashable, Sendable, Codable, CaseIterable {
    case matches, contains
}

/// Where a routed link opens. Arc: `LinkDestination` space(...) | littleArc(...), plus "Most Recent Space".
public enum LinkDestination: Hashable, Sendable, Codable {
    case space(SpaceID)
    case littleArc
    case mostRecentSpace
}

/// Arc's Max pane, replaced by the user's decision: AI stand-ins run the user's local coding agent (`claude`, `codex`,
/// `gemini`, `cursor-agent`, `opencode`); no API keys. `provider` picks which; the per-feature switches come with their
/// features.
public struct MaxSettings: Hashable, Sendable, Codable {
    public var provider: AIProviderChoice
    /// Max `renamedPinnedTabs`: rename a tab with a tidier title when it is pinned.
    public var renamePinnedTabs: Bool
    /// Max `tidyTabs`: "Organize Today Tabs" groups Today into folders.
    public var tidyTabs: Bool
    public var features: [AIFeature: Bool]? = nil
    public var translationExclusions: [ProfileID: AITranslationExclusions]? = nil
    /// "Automatically enable future Arc Max features": a feature the user never switched follows this; nil is off.
    public var autoEnableFutureFeatures: Bool? = nil
    /// The model and effort the user picked per agent; nothing stored means the agent's own default.
    public var agentOptions: [AIProviderKind: AIAgentOptions]? = nil
    /// The model and effort for the basic features (names, Tidy, previews, downloads, translation, decisions), per
    /// agent, apart from the conversation's; nothing stored means `AIAgentOptions.basicDefault`.
    public var basicOptions: [AIProviderKind: AIAgentOptions]? = nil
    /// Per service, the signed-in subscription or an API key (docs/design/ai-native.md, 账号：订阅或 API key). Nothing
    /// stored is `AIService.defaultWay`. The key itself is in the Keychain, never here.
    public var accounts: [AIService: AIAccountWay]? = nil
    /// Which backend answers decisions; nil is `.automatic`.
    public var decisions: AIDecisionChoice? = nil
    /// This month's use of the basic features, per feature and route. Counts only; no prompt text.
    public var usage: AIUsageLedger? = nil

    public static let `default` = MaxSettings(provider: .auto, renamePinnedTabs: false, tidyTabs: false)

    /// Turn Off Max sets the tool to off and keeps each switch's choice for Turn On Max; while off, no feature runs and
    /// none offers itself (no Tidy on the divider, no Ask row), and the pane shows every switch off, as Arc's does (P38-b).
    public var isOn: Bool { provider != .off }
    /// Tidy Tabs and Tidy Tab Titles as they act now: their switch, and Max on.
    public var tidyOn: Bool { isOn && tidyTabs }
    public var titlesOn: Bool { isOn && renamePinnedTabs }
}

/// A model and effort picked in the Max pane. Identifiers as the agent reported them.
public struct AIAgentOptions: Hashable, Sendable, Codable {
    public var model: String?
    public var effort: String?
    public init(model: String? = nil, effort: String? = nil) { self.model = model; self.effort = effort }

    /// The small models T3 Code names threads with: one-shot work does not need the conversation's model. Only Claude
    /// and Codex return answers in a schema; the other agents have no basic channel.
    public static func basicDefault(_ kind: AIProviderKind) -> AIAgentOptions? {
        switch kind {
        case .claude: AIAgentOptions(model: "claude-haiku-5-5")
        case .codex: AIAgentOptions(model: "gpt-6-luna", effort: "low")
        case .gemini, .cursor, .opencode: nil
        }
    }
}

/// A service the user can pay with a subscription (a signed-in CLI) or an API key. TypeSafe has only keys and answers
/// decisions only.
public enum AIService: String, Hashable, Sendable, Codable, CaseIterable {
    case anthropic, openai, typesafe
    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .typesafe: "TypeSafe"
        }
    }
    /// The agent whose subscription this service is; nil for TypeSafe.
    public var agent: AIProviderKind? {
        switch self {
        case .anthropic: .claude
        case .openai: .codex
        case .typesafe: nil
        }
    }
    public static func of(_ kind: AIProviderKind) -> AIService? {
        switch kind {
        case .claude: .anthropic
        case .codex: .openai
        case .gemini, .cursor, .opencode: nil
        }
    }
    public var defaultWay: AIAccountWay { self == .typesafe ? .apiKey : .subscription }
}

/// Stored as "subscription" or "key": state.json never holds the text "apikey" (the AIMax scenario checks for it).
public enum AIAccountWay: String, Hashable, Sendable, Codable, CaseIterable { case subscription, apiKey = "key" }

/// Whether a service has a key in the Keychain and what its last Test said. The key is never part of this.
public struct AIKeyStatus: Hashable, Sendable, Codable {
    public var stored: Bool
    public var test: AIKeyTest?
    public init(stored: Bool, test: AIKeyTest? = nil) { self.stored = stored; self.test = test }
}
public enum AIKeyTest: Hashable, Sendable, Codable {
    case testing
    /// The key works; the models it may use, as the service listed them.
    case works(models: [String])
    case failed(String)
}

/// Which backend answers decisions (choose, score, yes/no). Automatic is JevK5 on this Mac when it is ready, else the
/// basic-features text model (no probabilities, so its answers only suggest).
public enum AIDecisionChoice: String, Hashable, Sendable, Codable, CaseIterable {
    case automatic
    /// OpenAI's Decisions API with the OpenAI key.
    case openai
    /// TypeSafe's Jev with the TypeSafe key.
    case jev
    /// Always the basic-features text model.
    case textModel
}

/// What a basic request cost, as its service reported it.
public struct AIUsageCount: Hashable, Sendable, Codable {
    public var requests: Int
    public var inputTokens: Int
    public var outputTokens: Int
    /// Input tokens read from the service's cache, included in `inputTokens`.
    public var cachedTokens: Int
    /// Approximate dollars, for API-key use; nil when the price is not known.
    public var cost: Double?
    public init(requests: Int = 1, inputTokens: Int = 0, outputTokens: Int = 0, cachedTokens: Int = 0, cost: Double? = nil) {
        self.requests = requests; self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.cachedTokens = cachedTokens; self.cost = cost
    }
    public static func + (a: AIUsageCount, b: AIUsageCount) -> AIUsageCount {
        AIUsageCount(requests: a.requests + b.requests, inputTokens: a.inputTokens + b.inputTokens, outputTokens: a.outputTokens + b.outputTokens,
                     cachedTokens: a.cachedTokens + b.cachedTokens, cost: a.cost == nil && b.cost == nil ? nil : (a.cost ?? 0) + (b.cost ?? 0))
    }
}

/// One line of the usage table: a feature on one route ("Name Tabs", Anthropic, API key).
public struct AIUsageKey: Hashable, Sendable, Codable, Comparable {
    public var feature: String
    public var service: AIService
    public var way: AIAccountWay
    public init(feature: String, service: AIService, way: AIAccountWay) { self.feature = feature; self.service = service; self.way = way }
    public static func < (a: AIUsageKey, b: AIUsageKey) -> Bool {
        (a.feature, a.service.rawValue, a.way.rawValue) < (b.feature, b.service.rawValue, b.way.rawValue)
    }
}

/// The current month's counts ("2026-11"); a new month starts the table again.
public struct AIUsageLedger: Hashable, Sendable, Codable {
    public var month: String
    public var rows: [AIUsageKey: AIUsageCount]
    public init(month: String, rows: [AIUsageKey: AIUsageCount] = [:]) { self.month = month; self.rows = rows }
}

extension MaxSettings {
    public func way(_ service: AIService) -> AIAccountWay { accounts?[service] ?? service.defaultWay }

    /// The basic features' model and effort for an agent: the user's pick, else the small default.
    public func basic(_ kind: AIProviderKind) -> AIAgentOptions? {
        basicOptions?[kind] ?? AIAgentOptions.basicDefault(kind)
    }
}

/// Which local agent answers AI requests. `.auto` takes the first of `AIProviderKind.allCases` that is installed and,
/// once its status is known, signed in; else behaves as `.off` (`Session.detectedAI` says what was found at launch).
public enum AIProviderChoice: String, Hashable, Sendable, Codable, CaseIterable { case off, auto, claude, codex, gemini, cursor, opencode }

/// A local coding agent the app can run. The raw value is what settings store; `executableNames` is what is looked for.
public enum AIProviderKind: String, Hashable, Sendable, Codable, CaseIterable {
    case claude, codex, gemini, cursor, opencode
    /// The commands that start this agent, first match wins. Cursor installs `cursor-agent` (and an `agent` alias).
    public var executableNames: [String] {
        switch self {
        case .cursor: ["cursor-agent"]
        default: [rawValue]
        }
    }
}

/// Arc's Advanced pane (anatomy-m 4.2). Switches whose features are later waves are stored now so the pane can
/// show them; their consumers arrive with the features.
public struct AdvancedSettings: Hashable, Sendable, Codable {
    /// "When opening Arc, restore windows from previous session".
    public var restoreWindowsOnLaunch: Bool
    /// "Play Arc sound effects".
    public var soundEffects: Bool
    /// "Haptic feedback when reordering tabs".
    public var hapticsOnReorder: Bool
    /// "Show full URL when Toolbar is enabled".
    public var showFullURLInToolbar: Bool
    /// "Allow window dragging from the top of webpages".
    public var windowDraggingFromPages: Bool
    /// "Enable Picture in Picture when you leave a video tab".
    public var autoPictureInPicture: Bool
    /// "Allow websites to get your theme data".
    public var themeToCSS: Bool
    /// "Enable Boosts on websites you visit".
    public var boostsEnabled: Bool
    /// "Enable Shared Quotes when highlighting text."
    public var sharedQuotes: Bool

    public static let `default` = AdvancedSettings(restoreWindowsOnLaunch: true, soundEffects: true, hapticsOnReorder: true,
                                                   showFullURLInToolbar: false, windowDraggingFromPages: true, autoPictureInPicture: true,
                                                   themeToCSS: false, boostsEnabled: true, sharedQuotes: true)
}

/// A browser profile (Arc: `ADKModels.Profile`, `ProfilesUI`). The default profile always exists and cannot be
/// deleted; a profile with spaces cannot be deleted ("Only Profiles not assigned to any Spaces can be deleted.").
struct Profile: Sendable, Equatable {
    let id: ProfileID
    var name: String
    var icon: CustomIcon?

    static let `default` = Profile(id: .default, name: "Default", icon: nil)
}

/// One of Arc's remappable shortcuts after the user changed it (Arc: `StorableKeyBindings.userOverrides`).
/// A nil `chord` unsets the shortcut; a nil `priority` keeps the table's.
public struct KeyOverride: Hashable, Sendable, Codable {
    public var chord: KeyChord?
    public var priority: KeyPriority?

    public init(chord: KeyChord?, priority: KeyPriority?) {
        self.chord = chord
        self.priority = priority
    }
}

/// Arc: `SearchEngine` (`name`, `keyword`, `searchURLTemplate`, `faviconURL`, `isPrepopulated`). `template` and
/// `suggestTemplate` take the query at `{q}` (percent-encoded). Built-ins are the ones Chromium prepopulates;
/// user-added engines are a later wave.
public struct SearchEngine: Hashable, Sendable, Codable {
    public let id: SearchEngineID
    public var name: String
    public var keyword: String
    public var template: String
    /// OpenSearch suggestions JSON (`["q", ["s1", "s2"]]`), or nil when the engine has none.
    public var suggestTemplate: String?

    public init(id: SearchEngineID, name: String, keyword: String, template: String, suggestTemplate: String?) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.template = template
        self.suggestTemplate = suggestTemplate
    }

    public static let google = SearchEngine(id: SearchEngineID("google"), name: "Google", keyword: "google",
                                            template: "https://www.google.com/search?q={q}",
                                            suggestTemplate: "https://suggestqueries.google.com/complete/search?client=firefox&q={q}")
    public static let duckDuckGo = SearchEngine(id: SearchEngineID("duckduckgo"), name: "DuckDuckGo", keyword: "duckduckgo",
                                                template: "https://duckduckgo.com/?q={q}",
                                                suggestTemplate: "https://duckduckgo.com/ac/?type=list&q={q}")
    public static let bing = SearchEngine(id: SearchEngineID("bing"), name: "Bing", keyword: "bing",
                                          template: "https://www.bing.com/search?q={q}",
                                          suggestTemplate: "https://www.bing.com/osjson.aspx?query={q}")
    public static let ecosia = SearchEngine(id: SearchEngineID("ecosia"), name: "Ecosia", keyword: "ecosia",
                                            template: "https://www.ecosia.org/search?q={q}",
                                            suggestTemplate: "https://ac.ecosia.org/?type=list&q={q}")
    public static let kagi = SearchEngine(id: SearchEngineID("kagi"), name: "Kagi", keyword: "kagi",
                                          template: "https://kagi.com/search?q={q}", suggestTemplate: nil)

    public static let builtIn: [SearchEngine] = [.google, .duckDuckGo, .bing, .ecosia, .kagi]

    /// Sites the command bar offers site search on ("Search Wikipedia" and Tab when the input completes to
    /// wikipedia.org; Arc 1.170, P02-c and Q01-b of the 2026-11-03 captures). Never a default engine, so the Profiles
    /// pane does not list them. Arc reads these from Chromium's keyword table, which was not dumped; the sites are the
    /// top domains with a well-known search page, and the keyword is the domain the input completes to.
    public static let siteSearchSites: [SearchEngine] = [
        site("Wikipedia", "wikipedia.org", "https://en.wikipedia.org/wiki/Special:Search?search={q}"),
        site("YouTube", "youtube.com", "https://www.youtube.com/results?search_query={q}"),
        site("Google Docs", "docs.google.com", "https://docs.google.com/document/u/0/?q={q}"),
        site("Google Drive", "drive.google.com", "https://drive.google.com/drive/search?q={q}"),
        site("Google Maps", "maps.google.com", "https://www.google.com/maps/search/{q}"),
        site("GitHub", "github.com", "https://github.com/search?q={q}"),
        site("Amazon", "amazon.com", "https://www.amazon.com/s?k={q}"),
        site("Reddit", "reddit.com", "https://www.reddit.com/search/?q={q}"),
    ]

    /// Every engine site search can reach for a profile: the built-ins, the sites above, then the user's own.
    public static func siteSearchable(_ settings: ProfileSettings) -> [SearchEngine] {
        builtIn + siteSearchSites + (settings.siteSearchEngines ?? [])
    }

    private static func site(_ name: String, _ domain: String, _ template: String) -> SearchEngine {
        SearchEngine(id: SearchEngineID("site:" + domain), name: name, keyword: domain, template: template, suggestTemplate: nil)
    }

    public static func builtIn(_ id: SearchEngineID) -> SearchEngine? { builtIn.first { $0.id == id } }

    /// encodeURIComponent: everything but A-Z a-z 0-9 - _ . ! ~ * ' ( ) is percent-encoded.
    static let queryAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

    /// The search URL for `query`; nil only if the template is malformed.
    public func searchURL(_ query: String) -> URL? {
        URL(string: template.replacingOccurrences(of: "{q}", with: query.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed) ?? ""))
    }

    /// The suggestions URL for `query`; nil when the engine has no suggest endpoint.
    public func suggestURL(_ query: String) -> URL? {
        guard let suggestTemplate else { return nil }
        return URL(string: suggestTemplate.replacingOccurrences(of: "{q}", with: query.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed) ?? ""))
    }
}

/// The Library's pages, in the order of Arc's navigation column (Arc: `HomePageID` screenshotsAndCaptures,
/// downloads, easelsAndNotes, spaces, boosts, archive). History is not one of them: Cmd+Y opens it in the content
/// area (`HistoryPage`), as Arc opens arc://history.
public enum LibraryPage: String, Hashable, Sendable, Codable, CaseIterable {
    case media, downloads, easelsAndNotes, spaces, boosts, archive
    /// Brk's own: every Space's AI conversations of the profile (docs/design/ai-threads.md), after Archived Tabs.
    case conversations
}

/// One file download (Arc: `StorableDownloadMetadata`; Library "Downloads" page, `DownloadMenu`).
struct Download: Sendable, Equatable {
    let id: DownloadID
    let url: URL
    var filename: String
    /// Where the file is (being) written; nil until the engine knows.
    var path: String?
    var received: Int64
    var total: Int64?
    var state: DownloadState
    let startedAt: Instant
    /// The profile of the page that started it (the Downloads page lists the current space's profile).
    let profile: ProfileID
    var end: DownloadEnd?
}

public enum DownloadState: String, Hashable, Sendable, Codable {
    case choosingDestination, inProgress, cancelling, finished, failed, cancelled, interrupted
    public var isActive: Bool { self == .choosingDestination || self == .inProgress || self == .cancelling }
}

/// Something the local AI tool is asked to do (`Effect.ai`). The prompt text is built by BrkApp's provider from
/// the task; the reducer applies the outcome (`SystemEvent.aiResult`) to the item the task names.
public enum AITask: Hashable, Sendable, Codable {
    /// A short title for the tab (Max `renamedPinnedTabs`); the outcome becomes its `customTitle`.
    case renameTab(ItemID, title: String, url: URL)
    /// Group Today into folders (Max `tidyTabs`, "Organize Today Tabs"); the outcome is a JSON plan the reducer
    /// turns into `.item` moves. TODO(later wave): the plan format.
    case tidyToday(SpaceID, tabs: [AITab])
    /// Free text (Ask Arc, ChatGPT in the command bar).
    case ask(String)
    case pageQuestion(String, AIPageContent)
    case summarize(AIPageContent)
    case renameDownload(DownloadID, original: String)
    case instant(String)
    case browse(String, [AIPageContent])
    case translate(target: String, content: AIPageContent)
    /// Short names for tabs (Brk's Name Tabs), several in one request; the outcome is `AIReply.tabNames`.
    case nameTabs([AITab])
    /// A name for a folder or group from the tabs in it; the outcome is `AIReply.text`.
    case nameFolder(ItemID, tabs: [AITab])
    /// The command bar's `translate` prefix: the text in `target`; the outcome is `AIReply.text`.
    case translateText(String, target: String)
    /// A decision (`DecisionRequest`) for a feature; the outcome is `AIReply.decision`. `hint` is what a local decision
    /// model needs beyond the request to ask it the way it was measured (BrkApp's local backend only).
    case decide(DecisionRequest, feature: AIFeature, hint: AIDecisionHint? = nil)

    /// One-shot work for the basic-features model, answered in a schema. The others are conversations.
    public var isBasic: Bool {
        switch self {
        case .ask, .pageQuestion, .browse: false
        default: true
        }
    }
}

/// Place New Tabs for JevK5 (slice B's measurement, verify/ai-native/b-local-models): the five groups nearest the new
/// tab by meaning, then JevK5 picks among them. The new tab, and each `group` option's tabs by option name.
public enum AIDecisionHint: Hashable, Sendable, Codable {
    case placement(question: String, subject: AITab, members: [String: [AITab]], profile: ProfileID)
}

public struct AITab: Hashable, Sendable, Codable {
    public let id: ItemID
    public let title: String
    public let url: URL
    public init(id: ItemID, title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }
}

public enum AIOutcome: Hashable, Sendable, Codable {
    /// A conversation's answer.
    case text(String)
    /// A basic task's answer, already in its schema's shape.
    case reply(AIReply)
    /// No provider: `.off`, or `.auto` found neither `claude` nor `codex` on PATH.
    case unavailable
    case failed(String)
}
