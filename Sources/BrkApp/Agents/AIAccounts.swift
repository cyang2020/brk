import BrkDomain
import Foundation

/// Whose account an agent session runs on (docs/design/ai-native.md, "账号：订阅或 API key"): the CLI's own signed-in
/// subscription, or an API key the user gave Brk for that service. A key goes only into the environment of the process
/// Brk starts; Brk never runs a login command and never touches the CLI's stored sign-in.
enum AIService: String, Sendable, CaseIterable {
    case anthropic, openai

    init?(_ kind: AIProviderKind) {
        switch kind {
        case .claude: self = .anthropic
        case .codex: self = .openai
        case .gemini, .cursor, .opencode: return nil
        }
    }
}

enum AIAccountChoice: Equatable, Sendable {
    case subscription
    case apiKey(String)

    var key: String? { if case .apiKey(let key) = self { key } else { nil } }
}

@MainActor enum AIAccounts {
    /// The seam slice A fills from the Keychain and its settings pane. Until then every service uses its subscription.
    static var read: (AIService) -> AIAccountChoice = { _ in .subscription }

    static func choice(for kind: AIProviderKind) -> AIAccountChoice {
        guard let service = AIService(kind), case .apiKey(let key) = read(service), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .subscription }
        return .apiKey(key.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// How a key reaches each CLI, checked on this machine (claude 2.1.318, codex-cli 0.164.0, 2026-11-08).
enum AIAccountWiring {
    /// Claude Code reads ANTHROPIC_API_KEY and then reports `apiKeySource: ANTHROPIC_API_KEY`; its stored sign-in is not used.
    static let anthropicVariable = "ANTHROPIC_API_KEY"
    /// `codex app-server` reads neither CODEX_API_KEY nor OPENAI_API_KEY (both tried: the requests went out with no key).
    /// A model provider of Brk's own reads the key from this variable (`env_key`), so `~/.codex/auth.json` is neither
    /// read nor written.
    static let openAIVariable = "BRK_OPENAI_API_KEY"
    static let openAIProvider = "brk-openai"

    /// Codex's arguments for a key: the provider, chosen, and nothing of the stored sign-in (`forced_login_method="api"`,
    /// credentials kept in memory only).
    static let codexKeyArguments: [String] = [
        "-c", "model_providers.\(openAIProvider)={name=\"OpenAI API key\",base_url=\"https://api.openai.com/v1\",env_key=\"\(openAIVariable)\",wire_api=\"responses\"}",
        "-c", "model_provider=\"\(openAIProvider)\"",
        "-c", "forced_login_method=\"api\"",
        "-c", "cli_auth_credentials_store=\"ephemeral\"",
    ]

    static func environment(_ kind: AIProviderKind, account: AIAccountChoice) -> [String: String] {
        guard let key = account.key else { return [:] }
        switch kind {
        case .claude: return [anthropicVariable: key]
        case .codex: return [openAIVariable: key]
        case .gemini, .cursor, .opencode: return [:]
        }
    }

    static func codexArguments(account: AIAccountChoice) -> [String] { account.key == nil ? [] : codexKeyArguments }
}
