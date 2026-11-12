import BrkBase
import BrkDomain
import Foundation
import Security

/// The user's API keys: in the login Keychain, one generic password per service, readable only while the Mac is
/// unlocked and never synced. Never in state.json, a snapshot, a command or a log. A test instance (control socket)
/// keeps them in memory only, so a test never touches the person's Keychain.
@MainActor final class AIKeyStore {
    static let shared = AIKeyStore(memoryOnly: ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil)

    private let memoryOnly: Bool
    /// Read once per launch; a Keychain read can ask the person when the app's signature changed since the key was saved.
    private var cache: [AIService: String?] = [:]
    private var tests: [AIService: AIKeyTest] = [:]
    /// Counts each service's saves and removals: a test still running for the key before says nothing afterwards.
    private var saves: [AIService: Int] = [:]
    /// Tells the reducer which services have keys (`SystemEvent.aiKeys`).
    var onChange: (@MainActor ([AIService: AIKeyStatus]) -> Void)?

    init(memoryOnly: Bool) { self.memoryOnly = memoryOnly }

    private var serviceName: String { (Bundle.main.bundleIdentifier ?? Product.name) + ".ai-keys" }

    func key(_ service: AIService) -> String? {
        if let cached = cache[service] { return cached }
        guard !memoryOnly else { return nil }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName,
                                    kSecAttrAccount as String: service.rawValue, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let value = SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess ? (item as? Data).map { String(decoding: $0, as: UTF8.self) } : nil
        cache[service] = .some(value)
        return value
    }

    /// Which services have a key, from the Keychain item's attributes only: the secret is read when a request needs it.
    var stored: Set<AIService> { Set(AIService.allCases.filter(has)) }

    func has(_ service: AIService) -> Bool {
        if let cached = cache[service] { return cached != nil }
        guard !memoryOnly else { return false }
        if let known = present[service] { return known }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName,
                                    kSecAttrAccount as String: service.rawValue, kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        let found = SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
        present[service] = found
        return found
    }
    private var present: [AIService: Bool] = [:]

    /// Saves a key (trimmed), or removes it for nil or empty text. Returns a sentence when the Keychain refused.
    @discardableResult func store(_ service: AIService, _ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tests[service] = nil
        saves[service, default: 0] += 1
        present[service] = nil
        defer { report() }
        if memoryOnly { cache[service] = .some(trimmed.isEmpty ? nil : trimmed); return nil }
        let match: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName, kSecAttrAccount as String: service.rawValue]
        SecItemDelete(match as CFDictionary)
        guard !trimmed.isEmpty else { cache[service] = .some(nil); return nil }
        var add = match
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrLabel as String] = "\(Product.name) \(service.displayName) API key"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            cache[service] = nil
            let refusal = "The Keychain did not save the key (\(status))."
            tests[service] = .failed(refusal)
            return refusal
        }
        cache[service] = .some(trimmed)
        return nil
    }

    func test(_ service: AIService) {
        guard let key = key(service) else { return }
        tests[service] = .testing
        report()
        let save = saves[service, default: 0]
        Task { [weak self] in
            let result = await AIKeyTester.test(service, key: key)
            guard let self, self.saves[service, default: 0] == save else { return }
            self.tests[service] = result
            self.report()
        }
    }

    var statuses: [AIService: AIKeyStatus] {
        Dictionary(uniqueKeysWithValues: AIService.allCases.map { ($0, AIKeyStatus(stored: has($0), test: tests[$0])) })
    }

    func report() { onChange?(statuses) }
}

/// How a service is paid for, for the processes Brk starts (slice C's agent sessions): the user's subscription, or
/// their API key. Brk never changes the CLI's own login (no `codex login --with-api-key`, which rewrites
/// ~/.codex/auth.json); a key goes only into the environment of a process Brk starts.
enum AICredential: Equatable, Sendable {
    case subscription
    case apiKey(String)

    /// The environment variable a CLI reads the key from.
    static func variable(_ service: AIService) -> String? {
        switch service {
        case .anthropic: "ANTHROPIC_API_KEY"
        case .openai: "OPENAI_API_KEY"
        case .typesafe: nil
        }
    }
}

@MainActor enum AIAccounts {
    /// The way the user chose for this service, with the key when it is a key and one is saved. A key chosen but not
    /// saved is the subscription.
    static func credential(for service: AIService, settings: MaxSettings, keys: AIKeyStore = .shared) -> AICredential {
        guard settings.way(service) == .apiKey, let key = keys.key(service) else { return .subscription }
        return .apiKey(key)
    }
}
