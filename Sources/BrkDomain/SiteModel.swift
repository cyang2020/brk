import BrkBase
import Foundation

public enum SiteCommand: Hashable, Sendable, Codable {
    case controls
    case closeControls
    case rule(SiteTarget, SiteRule)
    case permission(SiteTarget, SiteOrigin, Set<SiteCapability>, SitePermission)
    case appearance(WebsiteAppearance)
    case clear(kinds: Set<SiteDataKind>, scope: SiteDataScope, reload: Bool)
    case clearProfile(ProfileID, Set<SiteDataKind>)
    case cancelClearing
    case confirmClear(String, Bool)
    case loadBlockingRules
    case selectedBlockingRules(URL, BrowsingContext)
    case resetBlockingRules
    case nativeExtensions
    case pinExtension(String, Bool)
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
