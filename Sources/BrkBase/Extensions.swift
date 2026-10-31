import Foundation

public struct BrowserExtension: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let version: String
    public let enabled: Bool
    public let supportsNativeAction: Bool
    public init(id: String, name: String, version: String, enabled: Bool, supportsNativeAction: Bool = false) {
        self.supportsNativeAction = supportsNativeAction
        self.id = id; self.name = name; self.version = version; self.enabled = enabled
    }
}

public struct ExtensionCatalog: Hashable, Sendable, Codable {
    public let context: BrowsingContext
    public let extensions: [BrowserExtension]
    public let error: String?
    public init(context: BrowsingContext, extensions: [BrowserExtension], error: String?) {
        self.context = context; self.extensions = extensions; self.error = error
    }
}
