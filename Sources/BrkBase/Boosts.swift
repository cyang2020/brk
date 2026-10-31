import Foundation

public enum BoostScope: Hashable, Sendable, Codable {
    case origin(SiteOrigin), host(String), allSites
    public func matches(_ url: URL) -> Bool {
        guard let origin = SiteOrigin(url) else { return false }
        switch self {
        case .origin(let expected): return origin == expected
        case .host(let host): return origin.url.host?.lowercased() == host
        case .allSites: return true
        }
    }
    public var label: String {
        switch self { case .origin(let origin): origin.value; case .host(let host): host; case .allSites: "All websites" }
    }
}

/// Execution input only. Editing, trust decisions and persistence belong to BrkDomain.
public struct BoostInjection: Hashable, Sendable, Codable {
    public let id: String
    public let scope: BoostScope
    public let css: String
    public let javascript: String
    public let allowPrivate: Bool
    public init(id: String, scope: BoostScope, css: String, javascript: String, allowPrivate: Bool) {
        self.id = id; self.scope = scope; self.css = css; self.javascript = javascript; self.allowPrivate = allowPrivate
    }
}

public struct BoostPolicy: Hashable, Sendable, Codable {
    public var boosts: [BoostInjection] = []
    public init(boosts: [BoostInjection] = []) { self.boosts = boosts }
}
