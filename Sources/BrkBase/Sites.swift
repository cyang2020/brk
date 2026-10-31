import Foundation

/// An exact HTTP origin. Default ports share a key; paths, credentials and fragments never enter policy matching.
public struct SiteOrigin: Hashable, Sendable, Codable, CustomStringConvertible {
    public let value: String
    public var description: String { value }
    public var url: URL { URL(string: value)! }
    public init?(_ url: URL) {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host?.lowercased(), !host.isEmpty else { return nil }
        parts.scheme = scheme; parts.host = host
        parts.user = nil; parts.password = nil; parts.path = ""; parts.query = nil; parts.fragment = nil
        if parts.port == (scheme == "https" ? 443 : 80) { parts.port = nil }
        guard let value = parts.string else { return nil }
        self.value = value
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        let value = try c.decode(String.self)
        guard let url = URL(string: value), let origin = SiteOrigin(url), origin.value == value else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected a canonical HTTP origin")
        }
        self = origin
    }
    public func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(value) }
}

public enum WebsiteAppearance: String, Hashable, Sendable, Codable, CaseIterable { case automatic, light, dark }
public enum SiteCapability: String, Hashable, Sendable, Codable, CaseIterable { case camera, microphone, location, notifications, desktopCapture, other }
public enum SitePermission: String, Hashable, Sendable, Codable, CaseIterable { case ask, allow, deny }

public struct SiteRule: Hashable, Sendable, Codable {
    public var blocking = true
    public var hideCookieBanners = false
    public var suspendWhenHidden = false
    public var keepAlive = false
    public var excludeSuspension = false
    public var permissions: [SiteCapability: SitePermission] = [:]
    public init() {}
}

public struct SitePreferences: Hashable, Sendable, Codable {
    public var blockingRules: WebsiteBlockingRules? = nil
    public var pinnedExtensions: [String]? = nil
    public var appearance: WebsiteAppearance? = nil
    public var rules: [String: SiteRule] = [:]
    public var embeddedPermissions: [String: [SiteCapability: SitePermission]]? = nil
    public func permissions(for origin: SiteOrigin, embeddedIn top: SiteOrigin) -> [SiteCapability: SitePermission] {
        origin == top ? rule(for: origin).permissions : embeddedPermissions?[top.value + "\n" + origin.value] ?? [:]
    }
    public init() {}
    public func rule(for origin: SiteOrigin) -> SiteRule { rules[origin.value] ?? SiteRule() }
}

/// Immutable input to one browser. The engine receives no global application store or saved tree.
public struct WebsitePolicy: Hashable, Sendable, Codable {
    public var appearance: WebsiteAppearance = .automatic
    public var themeCSS: [String: String] = [:]
    public var preferences = SitePreferences()
    public var visible = true
    public init() {}
}

public struct SiteTarget: Hashable, Sendable, Codable {
    public let document: DocumentToken
    public let context: BrowsingContext
    public let origin: SiteOrigin
    public var page: PageID { document.browser.page }
    public init(document: DocumentToken, context: BrowsingContext, origin: SiteOrigin) {
        self.document = document; self.context = context; self.origin = origin
    }
}

public enum SiteDataKind: String, Hashable, Sendable, Codable, CaseIterable { case cookies, cache, storage, history }
public enum SiteDataScope: String, Hashable, Sendable, Codable, CaseIterable { case site, profile }

/// A profile operation needs no live page and never disposes the request context.
public struct ClearProfileData: Hashable, Sendable, Codable {
    public let id: String
    public let profile: ProfileID
    public let kinds: Set<SiteDataKind>
    public init(id: String, profile: ProfileID, kinds: Set<SiteDataKind>) {
        self.id = id; self.profile = profile; self.kinds = kinds
    }
}

public struct ClearProfileDataResult: Hashable, Sendable, Codable {
    public let request: ClearProfileData
    public let completed: Set<SiteDataKind>
    public let error: String?
    public init(request: ClearProfileData, completed: Set<SiteDataKind>, error: String?) {
        self.request = request; self.completed = completed; self.error = error
    }
}

public struct ClearSiteData: Hashable, Sendable, Codable {
    public let id: String
    public let target: SiteTarget
    public let kinds: Set<SiteDataKind>
    public let scope: SiteDataScope
    public let reload: Bool
    public init(id: String, target: SiteTarget, kinds: Set<SiteDataKind>, scope: SiteDataScope = .site, reload: Bool = false) {
        self.id = id; self.target = target; self.kinds = kinds; self.scope = scope; self.reload = reload
    }
    public var explanation: String {
        var parts: [String] = []
        if kinds.contains(.cookies) { parts.append(scope == .profile ? "All cookies in this profile." : "All cookies for \(target.origin.url.host ?? target.origin.value), at every path, including secure, HttpOnly and shared domain cookies. Other sites on that domain may be signed out.") }
        if kinds.contains(.cache) { parts.append("The HTTP cache for the entire originating profile. Chromium does not provide a site-only HTTP cache clear.") }
        if kinds.contains(.storage) { parts.append("Local storage, IndexedDB, service workers and Cache Storage for \(target.origin).") }
        if kinds.contains(.history) { parts.append(scope == .profile ? "Brk history for this profile." : "Brk history for \(target.origin).") }
        return parts.joined(separator: "\n\n")
    }
}

public struct ClearSiteDataResult: Hashable, Sendable, Codable {
    public let request: ClearSiteData
    public let completed: Set<SiteDataKind>
    public let error: String?
    public init(request: ClearSiteData, completed: Set<SiteDataKind>, error: String?) {
        self.request = request; self.completed = completed; self.error = error
    }
}

public struct SitePermissionPrompt: Hashable, Sendable, Codable {
    public let id: String
    public let target: SiteTarget
    public let requestingOrigin: SiteOrigin
    public let capabilities: Set<SiteCapability>
    public let frame: String?
    public let mask: UInt32
    public init(id: String, target: SiteTarget, requestingOrigin: SiteOrigin, capabilities: Set<SiteCapability>, frame: String?, mask: UInt32) {
        self.id = id; self.target = target; self.requestingOrigin = requestingOrigin; self.capabilities = capabilities; self.frame = frame; self.mask = mask
    }
}

public struct WebsitePolicyStatus: Hashable, Sendable, Codable {
    public let document: DocumentToken
    public let appearance: WebsiteAppearance
    public let themeApplied: Bool
    public let frozen: Bool
    public let osAuthorization: [SiteCapability: String]?
    public let htmlMediaActive: Bool?
    public let error: String?
    public init(document: DocumentToken, appearance: WebsiteAppearance, themeApplied: Bool, frozen: Bool, error: String?, osAuthorization: [SiteCapability: String]? = nil, htmlMediaActive: Bool? = nil) {
        self.osAuthorization = osAuthorization
        self.htmlMediaActive = htmlMediaActive
        self.document = document; self.appearance = appearance; self.themeApplied = themeApplied; self.frozen = frozen; self.error = error
    }
}
