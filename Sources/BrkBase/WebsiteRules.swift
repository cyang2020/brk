import Foundation

public struct WebsiteBlockingRules: Hashable, Sendable, Codable {
    public let version: Int
    public let blockedHosts: [String]
    public let blockedPathPrefixes: [String]
    public let cosmeticSelectors: [String]
    public let blockedURLPrefixes: [String]?
    public init(version: Int, blockedHosts: [String], blockedPathPrefixes: [String], cosmeticSelectors: [String], blockedURLPrefixes: [String]? = nil) {
        self.blockedURLPrefixes = blockedURLPrefixes
        self.version = version; self.blockedHosts = blockedHosts; self.blockedPathPrefixes = blockedPathPrefixes; self.cosmeticSelectors = cosmeticSelectors
    }
    public static let builtIn: WebsiteBlockingRules = {
        guard let file = Bundle.main.url(forResource: "website-rules", withExtension: "json") ?? Bundle.module.url(forResource: "website-rules", withExtension: "json"),
              let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? Int, let hosts = object["blockedHosts"] as? [String],
              let paths = object["blockedPathPrefixes"] as? [String], let selectors = object["cosmeticSelectors"] as? [String] else {
            preconditionFailure("The bundled website rule resource is invalid")
        }
        return WebsiteBlockingRules(version: version, blockedHosts: hosts, blockedPathPrefixes: paths, cosmeticSelectors: selectors)
    }()
}

public enum WebsiteRulesUpdate: Hashable, Sendable { case loaded(WebsiteBlockingRules), failed(String) }
