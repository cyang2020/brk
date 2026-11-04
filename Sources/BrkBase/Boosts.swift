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

    /// The host a typed host scope matches, written as committed URLs report it (review F8 and #21): an
    /// internationalised name in its ASCII form (`bücher.example` -> `xn--bcher-kva.example`), an IPv6 address
    /// without brackets (`[::1]` and `::1` -> `::1`), lowercased; nil when the text names no host.
    public static func host(typed text: String) -> String? {
        var typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty, !typed.contains("/"), !typed.contains(" ") else { return nil }
        if typed.filter({ $0 == ":" }).count > 1, !typed.hasPrefix("[") { typed = "[" + typed + "]" }
        guard let host = URL(string: "http://" + typed + "/")?.host(percentEncoded: false), !host.isEmpty, !host.contains("%") else { return nil }
        return host.lowercased()
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
