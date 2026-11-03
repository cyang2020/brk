import BrkBase
import Foundation

// Owner: F1 (model and rules), with F2 (per-profile values), F3 (Links), F4 (Shortcuts). The settings model mirrors
// Arc's panes (anatomy-m 4.1, 4.2): General, Profiles (one record per profile), Links, Shortcuts (`Doc.keyOverrides`),
// Max, Advanced. Account, App Icon and Staff are dropped by the user's decisions (no account, no referrals).
// Every value is saved (`Doc.settings`), changed only through `.settings(...)` commands, and read by the projection
// into `SettingsSnapshot`. Defaults are ours where Arc ships none (anatomy-m 4.1: no defaults plist).

/// The panes of the settings window, in Arc's toolbar order (anatomy-m 4.1 enum order, minus account and staff).
public enum SettingsPane: String, Hashable, Sendable, Codable, CaseIterable {
    case general, max, profiles, shortcuts, links, advanced
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

    public static let `default` = GeneralSettings(warnBeforeQuitting: false, defaultBrowserPromptDismissed: false, webAppearance: .automatic)
}

public enum WebAppearance: String, Hashable, Sendable, Codable, CaseIterable { case automatic, light, dark }

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

    public static let `default` = ProfileSettings(searchEngine: SearchEngine.google.id, searchSuggestions: true, autoArchive: .default,
                                                  downloadsDirectory: nil, promptForDownloadLocation: false)
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

    public static let `default` = LinkSettings(externalLinksInLittleArc: true, optionCommandClickLittleArc: true, shiftClickPeek: true,
                                               peekFromPinnedAndFavorites: true, littleArcAutoArchive: .twelveHours, defaultRoute: nil)
}

/// One Air Traffic Control route (Arc: `StorableLinkRouting`): links whose host matches `pattern` open at
/// `destination`. `pattern` is a host glob ("*.spotify.com", "open.spotify.com"); matching is `LinkRoute.matches`.
public struct LinkRoute: Hashable, Sendable, Codable {
    public let id: LinkRouteID
    public var pattern: String
    public var destination: LinkDestination

    public init(id: LinkRouteID, pattern: String, destination: LinkDestination) {
        self.id = id
        self.pattern = pattern
        self.destination = destination
    }

    /// Case-insensitive host match (F3): "spotify.com" matches that host only; "*.spotify.com" matches the bare host
    /// and any subdomain depth. The stored pattern is already normalized (`normalizedPattern`, Rules/Windows.swift);
    /// a pattern typed with a scheme or path still matches because it is normalized here too. No host: no match.
    public func matches(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), let pattern = LinkRoute.normalizedPattern(pattern) else { return false }
        if pattern.hasPrefix("*.") {
            let base = String(pattern.dropFirst(2))
            return host == base || host.hasSuffix("." + base)
        }
        return host == pattern
    }
}

/// Where a routed link opens. Arc: `LinkDestination` space(...) | littleArc(...), plus "Most Recent Space".
public enum LinkDestination: Hashable, Sendable, Codable {
    case space(SpaceID)
    case littleArc
    case mostRecentSpace
}

/// Arc's Max pane, replaced by the user's decision: AI stand-ins run the user's local `claude` or `codex`
/// command-line tool; no API keys. `provider` picks which; the per-feature switches come with their features.
public struct MaxSettings: Hashable, Sendable, Codable {
    public var provider: AIProviderChoice
    /// Max `renamedPinnedTabs`: rename a tab with a tidier title when it is pinned.
    public var renamePinnedTabs: Bool
    /// Max `tidyTabs`: "Organize Today Tabs" groups Today into folders.
    public var tidyTabs: Bool
    public var features: [AIFeature: Bool]? = nil
    public var translationExclusions: [ProfileID: AITranslationExclusions]? = nil

    public static let `default` = MaxSettings(provider: .auto, renamePinnedTabs: false, tidyTabs: false)
}

/// Which local command-line tool answers AI requests. `.auto` takes `claude` when it is on PATH, else `codex`,
/// else behaves as `.off` (`Session.detectedAI` says what was found at launch).
public enum AIProviderChoice: String, Hashable, Sendable, Codable, CaseIterable { case off, auto, claude, codex }

/// A local AI command-line tool the app can run non-interactively.
public enum AIProviderKind: String, Hashable, Sendable, Codable, CaseIterable { case claude, codex }

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
    case text(String)
    /// No provider: `.off`, or `.auto` found neither `claude` nor `codex` on PATH.
    case unavailable
    case failed(String)
}
