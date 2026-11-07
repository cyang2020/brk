import BrkBase
import BrkDomain
import Foundation

/// The Agent Client Protocol: JSON-RPC 2.0 on stdio, spoken by `gemini --acp`, `cursor-agent acp` and `opencode acp`.
/// `session/new` makes the session and lists models and modes; `session/prompt` is a turn whose reply is its end,
/// `session/update` carries text and tool calls, `session/request_permission` asks for approval.
///
/// Gemini and Cursor were not signed in on the machine this was written on, so only the handshake and the signed-out
/// message ran on them; opencode was not installed at all. Their turns ran against Tests/Fixtures/ai-provider only.
@MainActor final class ACPBackend: AgentBackend {
    var events: (@MainActor (AgentBackendEvent) -> Void)?
    private(set) var process: AgentProcess?
    var resumeID: String? { spec.access == .tools && canLoad ? session : nil }
    private let spec: AgentSpec
    private let environment: [String: String]
    private var peer: JSONRPCPeer?
    private var session: String?
    private var canLoad = false
    private var queued: String?
    private var pendingApprovals: [String: (id: Any, options: [[String: Any]])] = [:]
    private var interrupting = false
    private var modelName: String?
    private var steps: [String: String] = [:]

    init(spec: AgentSpec, environment: [String: String]) {
        self.spec = spec
        self.environment = environment
    }

    /// Gemini's plan mode is its read-only mode, but it silently falls back to asking when the folder is not trusted,
    /// and the empty folder Brk made is safe to trust (`--skip-trust` holds for this process only). Extensions and MCP
    /// servers, which add tools, stay off.
    static func arguments(_ spec: AgentSpec) -> [String] {
        switch spec.kind {
        case .gemini:
            var arguments = ["--acp"]
            if spec.access == .readOnly { arguments += ["--skip-trust", "--approval-mode", "plan", "--extensions", "none", "--allowed-mcp-server-names", "brk-none"] }
            if let model = spec.model { arguments += ["--model", model] }
            return arguments
        default:
            return ["acp"]
        }
    }

    /// The mode a read-only session asks for: Cursor's ask, the others' plan.
    static func readOnlyMode(_ kind: AIProviderKind) -> String { kind == .cursor ? "ask" : "plan" }

    func start() throws {
        if spec.kind == .cursor {
            // Cursor's ACP `authenticate` starts a browser sign-in when signed out, so its status command goes first.
            let status = AgentProcess(executable: spec.executable, arguments: ["status"], directory: spec.directory, environment: environment)
            let output = StringBox()
            try status.start(output: { output.append($0) }, exit: { [weak self] _, _ in
                guard let self else { return }
                if output.text.lowercased().contains("not logged in") { self.events?(.exited(AgentCopy.notSignedIn(.cursor))); return }
                do { try self.launch() } catch { self.events?(.exited("\(error)")) }
            })
            return
        }
        try launch()
    }

    private func launch() throws {
        let process = AgentProcess(executable: spec.executable, arguments: Self.arguments(spec), directory: spec.directory, environment: environment)
        self.process = process
        let peer = JSONRPCPeer(process: process, tagged: true)
        self.peer = peer
        peer.onNotification = { [weak self] in self?.notification($0, $1) }
        peer.onRequest = { [weak self] in self?.request($0, $1, $2) }
        try process.start(output: { [weak peer] in peer?.feed($0) }, exit: { [weak self] status, stderr in
            guard let self else { return }
            self.peer?.failPending("\(self.spec.kind.displayName) stopped.")
            self.events?(.exited(status == 0 ? nil : Self.failure(self.spec.kind, status, stderr)))
        })
        peer.request("initialize", ["protocolVersion": 1, "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": false], "terminal": false] as [String: Any],
                                    "clientInfo": ["name": "brk", "title": Product.name, "version": "1"]]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): self.events?(.exited(error.message))
            case .success(let body):
                self.canLoad = (body["agentCapabilities"] as? [String: Any])?["loadSession"] as? Bool == true
                if self.spec.kind == .cursor { self.authenticate() } else { self.openSession() }
            }
        }
    }

    private func authenticate() {
        peer?.request("authenticate", ["methodId": "cursor_login"]) { [weak self] result in
            guard let self else { return }
            if case .failure = result { self.events?(.exited(AgentCopy.notSignedIn(.cursor))); self.process?.stop(); return }
            self.openSession()
        }
    }

    private func openSession() {
        let parameters: [String: Any] = ["cwd": spec.directory.path, "mcpServers": [Any]()]
        let opened: JSONRPCPeer.Reply = { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                let message = error.data ?? error.message
                self.events?(.exited(AgentFailureText.isSignIn(message) ? AgentCopy.notSignedIn(self.spec.kind) : message))
                self.process?.stop()
            case .success(let body):
                if self.session == nil { self.session = body["sessionId"] as? String }
                self.configure(body)
            }
        }
        if let resume = spec.resume {
            session = resume
            peer?.request("session/load", parameters.merging(["sessionId": resume]) { _, new in new }, reply: opened)
        } else {
            peer?.request("session/new", parameters, reply: opened)
        }
    }

    /// Model, effort and read-only mode, each only if the agent offers it, then the turn that waited for them.
    private func configure(_ body: [String: Any]) {
        guard let session else { events?(.exited("\(spec.kind.displayName) did not start a session.")); return }
        let catalog = ACPCatalog.models(body)
        modelName = catalog.first { $0.id == spec.model }?.name ?? catalog.first { $0.isDefault }?.name ?? spec.model
        if let model = spec.model, spec.kind != .gemini {
            if let option = ACPCatalog.optionID(body, category: "model") { peer?.request("session/set_config_option", ["sessionId": session, "configId": option, "value": model]) }
            else { peer?.request("session/set_model", ["sessionId": session, "modelId": model]) }
        }
        if let effort = spec.effort, let option = ACPCatalog.optionID(body, category: "thought_level") {
            peer?.request("session/set_config_option", ["sessionId": session, "configId": option, "value": effort])
        }
        if spec.access == .readOnly {
            let wanted = Self.readOnlyMode(spec.kind)
            let modes = ((body["modes"] as? [String: Any])?["availableModes"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            if modes.contains(wanted), (body["modes"] as? [String: Any])?["currentModeId"] as? String != wanted {
                peer?.request("session/set_mode", ["sessionId": session, "modeId": wanted])
            }
        }
        events?(.ready(model: modelName, effort: spec.effort))
        if let queued { self.queued = nil; send(queued) }
    }

    func send(_ text: String) {
        guard let session else { queued = text; return }
        interrupting = false
        peer?.request("session/prompt", ["sessionId": session, "prompt": [["type": "text", "text": text]]]) { [weak self] result in
            guard let self else { return }
            self.closeApprovals()
            switch result {
            case .failure(let error):
                let message = error.data ?? error.message
                if self.interrupting { self.events?(.turnEnded(.interrupted)); return }
                self.events?(.turnEnded(.failed(AgentFailureText.isSignIn(message) ? AgentCopy.notSignedIn(self.spec.kind) : message)))
            case .success(let body):
                if self.interrupting || body["stopReason"] as? String == "cancelled" { self.events?(.turnEnded(.interrupted)) }
                else if body["stopReason"] as? String == "refusal" { self.events?(.turnEnded(.failed("\(self.spec.kind.displayName) declined to answer."))) }
                else { self.events?(.turnEnded(.completed(text: nil))) }
            }
        }
    }

    func interrupt() {
        interrupting = true
        closeApprovals()
        if let session { peer?.notify("session/cancel", ["sessionId": session]) }
    }

    /// A permission request left open would hold the agent up: cancelled, as the protocol asks.
    private func closeApprovals() {
        for (key, pending) in pendingApprovals {
            peer?.respond(pending.id, ["outcome": ["outcome": "cancelled"]])
            events?(.approvalClosed(key))
        }
        pendingApprovals = [:]
    }

    func answer(approval: String, option: String) {
        guard let pending = pendingApprovals.removeValue(forKey: approval) else { return }
        peer?.respond(pending.id, ["outcome": ["outcome": "selected", "optionId": option]])
    }

    private func notification(_ method: String, _ params: [String: Any]) {
        guard method == "session/update", let update = params["update"] as? [String: Any] else { return }
        switch update["sessionUpdate"] as? String {
        case "agent_message_chunk":
            if let text = (update["content"] as? [String: Any])?["text"] as? String { events?(.text(text)) }
        case "tool_call":
            guard let id = update["toolCallId"] as? String else { return }
            let title = update["title"] as? String ?? "Tool"
            steps[id] = title
            events?(.step(AIAgentStep(id: id, title: title, state: Self.state(update["status"] as? String))))
        case "tool_call_update":
            guard let id = update["toolCallId"] as? String else { return }
            let title = update["title"] as? String ?? steps[id] ?? "Tool"
            steps[id] = title
            events?(.step(AIAgentStep(id: id, title: title, state: Self.state(update["status"] as? String))))
        case "current_mode_update", "config_option_update", "available_commands_update", "plan", "agent_thought_chunk", "user_message_chunk": break
        default: break
        }
    }

    private static func state(_ status: String?) -> AIAgentStep.State {
        switch status {
        case "completed": .done
        case "failed", "cancelled": .failed
        default: .running
        }
    }

    private func request(_ id: Any, _ method: String, _ params: [String: Any]) {
        guard method == "session/request_permission" else { peer?.refuse(id, "Not supported by Brk"); return }
        let options = params["options"] as? [[String: Any]] ?? []
        if spec.access == .readOnly {
            // Read-only: the reject option, or no answer at all if the agent offers none. Never shown, never allowed.
            if let reject = options.first(where: { ($0["kind"] as? String)?.hasPrefix("reject") == true })?["optionId"] as? String {
                peer?.respond(id, ["outcome": ["outcome": "selected", "optionId": reject]])
            } else { peer?.respond(id, ["outcome": ["outcome": "cancelled"]]) }
            return
        }
        let tool = params["toolCall"] as? [String: Any] ?? [:]
        let key = "\(id)"
        pendingApprovals[key] = (id, options)
        let shown: [AIAgentApproval.Option] = options.compactMap {
            guard let option = $0["optionId"] as? String else { return nil }
            let name = $0["name"] as? String ?? option
            switch $0["kind"] as? String {
            case "allow_once": return .init(id: option, title: name, kind: .allowOnce)
            case "allow_always": return .init(id: option, title: name, kind: .allowSession)
            case "reject_once", "reject_always": return .init(id: option, title: name, kind: .deny)
            default: return nil
            }
        }
        events?(.approval(AIAgentApproval(id: key, title: tool["title"] as? String ?? "Use a tool", detail: AgentCopy.detail(Self.detail(tool)), options: shown)))
    }

    private static func detail(_ tool: [String: Any]) -> String {
        let locations = (tool["locations"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
        if !locations.isEmpty { return locations.joined(separator: "\n") }
        guard let raw = tool["rawInput"], JSONSerialization.isValidJSONObject(raw), let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func failure(_ kind: AIProviderKind, _ status: Int32, _ stderr: String) -> String {
        if AgentFailureText.isSignIn(stderr) { return AgentCopy.notSignedIn(kind) }
        return AIProviderError.failed(status: status, stderr: stderr).description
    }
}

/// What `session/new` says it offers: `models` (the older shape), or `configOptions` by category.
enum ACPCatalog {
    static func models(_ body: [String: Any]) -> [AIAgentModel] {
        let efforts = values(body, category: "thought_level")
        if let block = body["models"] as? [String: Any], let list = block["availableModels"] as? [[String: Any]] {
            let current = block["currentModelId"] as? String
            return list.compactMap {
                guard let id = $0["modelId"] as? String else { return nil }
                return AIAgentModel(id: id, name: $0["name"] as? String ?? id, efforts: efforts, isDefault: id == current)
            }
        }
        let current = optionID(body, category: "model").flatMap { currentValue(body, id: $0) }
        return values(body, category: "model").map { AIAgentModel(id: $0, name: name(body, category: "model", value: $0) ?? $0, efforts: efforts, isDefault: $0 == current) }
    }
    static func optionID(_ body: [String: Any], category: String) -> String? {
        (body["configOptions"] as? [[String: Any]])?.first { $0["category"] as? String == category }?["id"] as? String
    }
    private static func currentValue(_ body: [String: Any], id: String) -> String? {
        (body["configOptions"] as? [[String: Any]])?.first { $0["id"] as? String == id }?["currentValue"] as? String
    }
    private static func values(_ body: [String: Any], category: String) -> [String] {
        let option = (body["configOptions"] as? [[String: Any]])?.first { $0["category"] as? String == category }
        return (option?["options"] as? [[String: Any]] ?? []).compactMap { $0["value"] as? String }
    }
    private static func name(_ body: [String: Any], category: String, value: String) -> String? {
        let option = (body["configOptions"] as? [[String: Any]])?.first { $0["category"] as? String == category }
        return (option?["options"] as? [[String: Any]])?.first { $0["value"] as? String == value }?["name"] as? String
    }
}
