import BrkBase
import Foundation

/// Where the basic features run: the agent's CLI on the user's subscription, or the service's API with the user's key.
/// The app runs it; the Max pane says it. Gemini, Cursor and OpenCode have no way to answer in a schema, so they have
/// no basic route.
public enum AIBasicRoute: Hashable, Sendable, Codable {
    case cli(AIProviderKind, model: String?, effort: String?)
    case api(AIService, model: String, effort: String?)
    case unavailable(String)

    public var service: AIService? {
        switch self {
        case .cli(let kind, _, _): AIService.of(kind)
        case .api(let service, _, _): service
        case .unavailable: nil
        }
    }
    public var way: AIAccountWay? {
        switch self {
        case .cli: .subscription
        case .api: .apiKey
        case .unavailable: nil
        }
    }
    public var model: String? {
        switch self {
        case .cli(_, let model, _): model
        case .api(_, let model, _): model
        case .unavailable: nil
        }
    }

    /// The route for this request. `keys` are the services with a key in the Keychain; `active` is what Automatic
    /// resolved to. A service's chosen way wins; a service with only a key works without its CLI, and one with only
    /// its CLI works without a key. An agent named explicitly is never answered by another.
    public static func resolve(_ settings: MaxSettings, choice: AIProviderChoice? = nil, detected: [AIProviderKind],
                               signedOut: Set<AIProviderKind> = [], keys: Set<AIService>, active: AIProviderKind? = nil) -> AIBasicRoute {
        let choice = choice ?? settings.provider
        func route(_ kind: AIProviderKind, explicit: Bool) -> AIBasicRoute? {
            guard let service = AIService.of(kind) else { return nil }
            let options = settings.basic(kind)
            let model = options?.model ?? AIAgentOptions.basicDefault(kind)?.model ?? ""
            let key = keys.contains(service)
            if settings.way(service) == .apiKey, key { return .api(service, model: model, effort: options?.effort) }
            if detected.contains(kind), explicit || !signedOut.contains(kind) { return .cli(kind, model: options?.model, effort: options?.effort) }
            if key { return .api(service, model: model, effort: options?.effort) }
            return nil
        }
        switch choice {
        case .off: return .unavailable(AICopy.maxOff)
        case .auto:
            let order = ([active].compactMap { $0 } + [.claude, .codex]).filter { AIService.of($0) != nil }
            for kind in order { if let found = route(kind, explicit: false) { return found } }
            for kind in order where detected.contains(kind) { if let found = route(kind, explicit: true) { return found } }
            return .unavailable(AICopy.noBasicRoute)
        default:
            guard let kind = choice.kind else { return .unavailable(AICopy.noBasicRoute) }
            guard let service = AIService.of(kind) else { return .unavailable(AICopy.noSchema(kind)) }
            return route(kind, explicit: true) ?? .unavailable(AICopy.nothingFor(kind, service))
        }
    }
}

/// Who answers decisions now.
public enum AIDecisionRoute: Hashable, Sendable, Codable {
    /// JevK5 on this Mac (slice B's runtime).
    case local
    case openai
    case jev
    /// The basic-features text model, answering in a schema without probabilities.
    case textModel(AIBasicRoute)

    public var givesProbabilities: Bool {
        if case .textModel = self { false } else { true }
    }

    /// The user's choice when it can run; a service chosen without its key is Automatic. Automatic follows slice B's
    /// measurements (docs/design/ai-native.md, 第 0 步): yes/no questions go to JevK5 on this Mac when it is ready
    /// (0.7 s, offline); choices such as a new tab's group go to the basic-features text model (114 of 121 right with
    /// Haiku or Luna), and to JevK5 only when there is no agent and no key.
    public static func resolve(_ settings: MaxSettings, keys: Set<AIService>, localReady: Bool, basic: AIBasicRoute, yesNo: Bool = false) -> AIDecisionRoute {
        switch settings.decisions ?? .automatic {
        case .openai where keys.contains(.openai): return .openai
        case .jev where keys.contains(.typesafe): return .jev
        case .textModel: return .textModel(basic)
        default:
            if yesNo && localReady { return .local }
            if case .unavailable = basic, localReady { return .local }
            return .textModel(basic)
        }
    }
}

extension AICopy {
    public static let nameWithAI = "Name with AI"
    public static let moveTo = "Move to"
    public static let cleanupDuplicates = "Duplicates"
    public static let cleanupStale = "Not Opened Lately"
    public static let cleanupTooltip = "Tabs you might close"
    public static let maxOff = "Max is off. Turn it on in Settings → Max."
    public static let noBasicRoute = "Basic AI features need Claude Code or Codex signed in on this Mac, or an Anthropic or OpenAI API key. Set one up in Settings → Max."
    public static func noSchema(_ kind: AIProviderKind) -> String {
        "\(kind.displayName) cannot return answers in a fixed shape, so basic AI features need Claude or Codex, or an Anthropic or OpenAI API key. Choose one in Settings → Max."
    }
    public static func nothingFor(_ kind: AIProviderKind, _ service: AIService) -> String {
        "\(kind.displayName) is not installed on this Mac and no \(service.displayName) API key is saved. Install it, or add a key in Settings → Max."
    }
}

extension AppState {
    /// The services with a key in the Keychain.
    var storedKeys: Set<AIService> { Set(session.ai.keys.filter { $0.value.stored }.map(\.key)) }

    /// Where the basic features run now (`AIBasicRoute.resolve` on this state).
    public var basicRoute: AIBasicRoute {
        AIBasicRoute.resolve(doc.settings.max, detected: session.detectedAI,
                             signedOut: Set(session.ai.agents.filter { $0.value.state == .notSignedIn }.map(\.key)),
                             keys: storedKeys, active: activeAgent)
    }
}
