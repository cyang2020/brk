import Foundation

public struct WebsiteBlockingRules: Hashable, Sendable, Codable {
    public let version: Int
    public let blockedHosts: [String]
    public let blockedPathPrefixes: [String]
    public let cosmeticSelectors: [String]
    public init(version: Int, blockedHosts: [String], blockedPathPrefixes: [String], cosmeticSelectors: [String]) {
        self.version = version; self.blockedHosts = blockedHosts; self.blockedPathPrefixes = blockedPathPrefixes; self.cosmeticSelectors = cosmeticSelectors
    }
    public static let builtIn = WebsiteBlockingRules(version: 1,
        blockedHosts: ["doubleclick.net", "googlesyndication.com", "google-analytics.com", "adservice.google.com", "scorecardresearch.com"],
        blockedPathPrefixes: ["/brk-blocked-ad/", "/brk-blocked-tracker/"],
        cosmeticSelectors: [".adsbygoogle", "[data-ad-slot]", ".brk-advertisement"])
}

public enum WebsiteRulesUpdate: Hashable, Sendable { case loaded(WebsiteBlockingRules), failed(String) }
