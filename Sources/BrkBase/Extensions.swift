import Foundation

public struct BrowserExtension: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let version: String
    public let enabled: Bool
    public let incognitoAllowed: Bool?
    public let canChangeIncognito: Bool?
    public let commands: [BrowserExtensionCommand]?
    public let supportsNativeAction: Bool
    public init(id: String, name: String, version: String, enabled: Bool, supportsNativeAction: Bool = false, incognitoAllowed: Bool? = nil, canChangeIncognito: Bool? = nil, commands: [BrowserExtensionCommand]? = nil) {
        self.incognitoAllowed = incognitoAllowed; self.canChangeIncognito = canChangeIncognito; self.commands = commands
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

public struct BrowserExtensionCommand: Hashable, Sendable, Codable, Identifiable {
    public let name: String
    public let description: String
    public let keybinding: String
    public let active: Bool
    public var id: String { name }
    public init(name: String, description: String, keybinding: String, active: Bool) {
        self.name = name; self.description = description; self.keybinding = keybinding; self.active = active
    }
}

public enum ExtensionEdit: Hashable, Sendable {
    case incognito(Bool)
    case shortcut(command: String, chord: KeyChord?)
}
