import BrkBase
import Foundation

public enum SiteCommand: Hashable, Sendable, Codable {
    case controls
    case closeControls
    case rule(SiteTarget, SiteRule)
    /// View > Developer > "Turn on/off Developer Mode for this site" (Ctrl+D): the focused page's site's Developer
    /// Mode, the same switch as the site controls' row.
    case toggleDeveloperMode
    case permission(SiteTarget, SiteOrigin, Set<SiteCapability>, SitePermission)
    case appearance(WebsiteAppearance)
    case clear(kinds: Set<SiteDataKind>, scope: SiteDataScope, reload: Bool)
    case clearProfile(ProfileID, Set<SiteDataKind>)
    case cancelClearing
    case confirmClear(String, Bool)
    case loadBlockingRules
    case selectedBlockingRules(URL, BrowsingContext)
    case resetBlockingRules
    /// Turn one of the profile's filter lists on or off (by `FilterListRecord.id`).
    case filterList(String, Bool)
    /// Whether Brk downloads filter list updates for the profile.
    case filterUpdates(Bool)
    /// Download every enabled subscription now.
    case updateFilterLists
    case nativeExtensions
    case pinExtension(String, Bool)
    case extensionIncognito(String, Bool)
    case extensionShortcut(String, String, String)
    case invokeExtension(String)
    case removeExtension(String)
    case extensions
    case extensionShortcuts
    case installSelectedExtension(URL)
    case executeExtensionInstall(URL, BrowsingContext)
    case addExtension
}

public struct SiteControlSnapshot: Sendable, Equatable, Codable {
    public let context: BrowsingContext?
    public let applied: WebsitePolicyStatus?
    public let rulesVersion: Int
    public let rulesError: String?
    public let extensionsLoaded: Bool?
    public let extensions: [BrowserExtension]
    public let pinnedExtensions: [String]
    public let extensionError: String?
    public let target: SiteTarget?
    public let profileName: String
    public let rule: SiteRule
    public let appearance: WebsiteAppearance
    public let clearing: Bool
    public let result: ClearSiteDataResult?
    /// The security row's Secure (else the red Insecure): an https page whose certificate and content Chromium found
    /// clean. An https page the engine has not reported on yet (still loading) counts as secure; http never does.
    public var secure: Bool = false
    /// The engine's report for this document, nil until it has made one (the details page says why it is insecure).
    public var security: PageSecurity? = nil
    /// The profile's EasyList-syntax lists and whether updates download.
    public var filterLists: [FilterListRecord] = []
    public var filterUpdates = true
}

struct SiteSession: Sendable, Equatable {
    var profileClears: [ProfileID: ClearProfileData] = [:]
    var profileResults: [ProfileID: ClearProfileDataResult] = [:]
    var extensionErrors: [BrowsingContext: String] = [:]
    var rulesErrors: [BrowsingContext: String] = [:]
    var catalogs: [BrowsingContext: ExtensionCatalog] = [:]
    var controls: Set<WindowID> = []
    var privatePreferences: [PrivateSessionID: SitePreferences] = [:]
    var confirmations: [String: ClearSiteData] = [:]
    var running: [String: ClearSiteData] = [:]
    var results: [WindowID: ClearSiteDataResult] = [:]
}
