import BrkDomain
import Foundation

/// What a session may do. Anything carrying page or link text runs `.readOnly`; `.tools` exists only because the user
/// chose a folder and asked for it.
enum AgentAccess: Equatable, Sendable {
    /// Tools off, or the agent's strictest read-only mode, in an empty folder Brk made for this session.
    case readOnly
    /// Tools on in the user's folder, every approval the agent asks for goes to the panel.
    case tools
}

struct AgentSpec: Sendable {
    let kind: AIProviderKind
    let executable: URL
    let model: String?
    let effort: String?
    let access: AgentAccess
    let directory: URL
    /// The agent's own session id to continue, when an earlier process of this conversation had to be ended.
    var resume: String? = nil
}

/// How a turn ended.
enum AgentTurnEnd: Equatable, Sendable {
    /// `text` is the agent's own final text, used when it streamed nothing.
    case completed(text: String?)
    case interrupted
    case failed(String)
}

enum AgentBackendEvent {
    /// The session exists; the model and effort it runs with, where the agent says.
    case ready(model: String?, effort: String?)
    case text(String)
    case step(AIAgentStep)
    case approval(AIAgentApproval)
    case approvalClosed(String)
    case notice(String)
    case turnEnded(AgentTurnEnd)
    /// The process ended by itself or by a failure. The message says why, nil after an orderly stop.
    case exited(String?)
}

/// One agent's way of talking: Claude's streaming JSON, Codex's app server, ACP, or plain text for the fixture. A
/// backend owns one process; `AgentSession` owns the backend, the turn and what happens after a stop.
@MainActor protocol AgentBackend: AnyObject {
    var events: (@MainActor (AgentBackendEvent) -> Void)? { get set }
    var process: AgentProcess? { get }
    /// The agent's own session id, where it keeps one this session could continue from.
    var resumeID: String? { get }
    func start() throws
    func send(_ text: String)
    func interrupt()
    func answer(approval: String, option: String)
}

/// Words Brk says about an agent.
enum AgentCopy {
    static func notSignedIn(_ kind: AIProviderKind) -> String {
        let command = switch kind {
        case .claude: "claude"
        case .codex: "codex login"
        case .gemini: "gemini"
        case .cursor: "cursor-agent login"
        case .opencode: "opencode auth login"
        }
        return "\(kind.displayName) is not signed in. Run \(command) in Terminal to sign in, then try again."
    }
    static func missing(_ kind: AIProviderKind) -> String {
        "\(kind.displayName) is not installed: Brk did not find \(kind.executableNames[0]) on your PATH. Install it, or choose another agent in Settings → Max."
    }
    /// The Max pane's model or effort changed while a conversation was open.
    static let modelChanged = "Model or effort changed in Settings → Max: this message goes to the new choice."
    static let modelChangedFresh = "Model or effort changed in Settings → Max: this message goes to the new choice, which does not see the earlier messages."
    static func noAnswer(_ kind: AIProviderKind) -> String {
        "\(kind.displayName) did not start in time. Try it in Terminal, then try again."
    }
    /// A one-line title for a tool's input.
    static func oneLine(_ text: String, limit: Int = 160) -> String {
        let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
    }
    static func detail(_ text: String, limit: Int = 600) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
}

/// A sign-in failure as the agents word it. Their sentences change between versions, so this looks for what they share.
enum AgentFailureText {
    static func isSignIn(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["not logged in", "/login", "please log in", "please run", "authentication required", "api key is missing", "not signed in", "set an auth method"]
            .contains { lower.contains($0) }
    }
}

/// JSON-RPC over stdin and stdout, one object per line: Codex's app server (no "jsonrpc" field) and ACP (with it).
@MainActor final class JSONRPCPeer {
    struct RemoteError: Error { let code: Int; let message: String; let data: String? }
    typealias Reply = @MainActor (Result<[String: Any], RemoteError>) -> Void

    private let process: AgentProcess
    private let tagged: Bool
    private var nextID = 1
    private var pending: [Int: Reply] = [:]
    private var splitter = LineSplitter()
    var onNotification: (@MainActor (String, [String: Any]) -> Void)?
    /// A request from the agent. It always gets an answer: `respond` or `refuse`.
    var onRequest: (@MainActor (Any, String, [String: Any]) -> Void)?

    init(process: AgentProcess, tagged: Bool) { self.process = process; self.tagged = tagged }

    func feed(_ chunk: Data) {
        for line in splitter.feed(chunk) where !line.isEmpty {
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            receive(object)
        }
        if splitter.overflowed { process.stop() }
    }

    private func receive(_ object: [String: Any]) {
        if let method = object["method"] as? String {
            let params = object["params"] as? [String: Any] ?? [:]
            if let id = object["id"] { onRequest?(id, method, params) } else { onNotification?(method, params) }
            return
        }
        guard let id = object["id"] as? Int, let reply = pending.removeValue(forKey: id) else { return }
        if let error = object["error"] as? [String: Any] {
            let data = (error["data"] as? [String: Any])?["message"] as? String ?? error["data"] as? String
            reply(.failure(RemoteError(code: error["code"] as? Int ?? 0, message: error["message"] as? String ?? "Unknown error", data: data)))
        } else {
            reply(.success(object["result"] as? [String: Any] ?? [:]))
        }
    }

    private func write(_ object: [String: Any]) {
        var message = object
        if tagged { message["jsonrpc"] = "2.0" }
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        process.write(data)
    }

    func request(_ method: String, _ params: [String: Any] = [:], reply: @escaping Reply = { _ in }) {
        let id = nextID
        nextID += 1
        pending[id] = reply
        write(["id": id, "method": method, "params": params])
    }

    func notify(_ method: String, _ params: [String: Any]? = nil) {
        var message: [String: Any] = ["method": method]
        if let params { message["params"] = params }
        write(message)
    }

    func respond(_ id: Any, _ result: [String: Any]) { write(["id": id, "result": result]) }
    func refuse(_ id: Any, _ message: String) { write(["id": id, "error": ["code": -32601, "message": message] as [String: Any]]) }

    /// The process ended: nothing will answer what is still waiting.
    func failPending(_ message: String) {
        let waiting = pending
        pending = [:]
        for reply in waiting.values { reply(.failure(RemoteError(code: -1, message: message, data: nil))) }
    }
}
