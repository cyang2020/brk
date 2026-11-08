import BrkBase
import BrkDomain
import Foundation

/// What an installed agent says about itself: signed in or not, version, models and efforts. Each agent is asked over
/// its own protocol, with nothing sent to a model and no sign-in started. Brk reads no credential file.
@MainActor enum AgentCatalog {
    private static let seconds = 20

    static func status(_ kind: AIProviderKind, executable: URL, environment: [String: String]) async -> AIAgentStatus {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-ai-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let run = Probe(kind: kind, executable: executable, directory: directory, environment: environment)
        return await run.result()
    }

    /// One asking. It ends with the first complete answer, or at the limit, and takes its process with it.
    @MainActor private final class Probe {
        let kind: AIProviderKind
        let executable: URL
        let directory: URL
        let environment: [String: String]
        private var process: AgentProcess?
        private var peer: JSONRPCPeer?
        private var splitter = LineSplitter()
        private var continuation: CheckedContinuation<AIAgentStatus, Never>?
        private var version: String?
        private var signedOut = false

        init(kind: AIProviderKind, executable: URL, directory: URL, environment: [String: String]) {
            self.kind = kind
            self.executable = executable
            self.directory = directory
            self.environment = environment
        }

        func result() async -> AIAgentStatus {
            await withCheckedContinuation { (continuation: CheckedContinuation<AIAgentStatus, Never>) in
                self.continuation = continuation
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(AgentCatalog.seconds))
                    guard let self else { return }
                    self.finish(AIAgentStatus(kind: self.kind, state: .failed("\(self.kind.displayName) did not answer in time."), version: self.version))
                }
                do {
                    switch kind {
                    case .claude: try askClaude()
                    case .codex: try askCodex()
                    case .gemini, .cursor, .opencode: try askACP()
                    }
                } catch { finish(AIAgentStatus(kind: kind, state: .failed("\(error)"))) }
            }
        }

        private func finish(_ status: AIAgentStatus) {
            guard let continuation else { return }
            self.continuation = nil
            process?.stop()
            continuation.resume(returning: status)
        }

        private func exited(_ status: Int32, _ stderr: String) {
            peer?.failPending("stopped")
            if signedOut || AgentFailureText.isSignIn(stderr) { finish(AIAgentStatus(kind: kind, state: .notSignedIn, version: version)); return }
            finish(AIAgentStatus(kind: kind, state: status == 0 ? .ready : .failed(AIProviderError.failed(status: status, stderr: stderr).description), version: version))
        }

        /// `auth status` says whether it is signed in; `initialize` over the session protocol lists models and spends nothing.
        private func askClaude() throws {
            let status = AgentProcess(executable: executable, arguments: ["auth", "status"], directory: directory, environment: environment)
            let output = StringBox()
            try status.start(output: { output.append($0) }, exit: { [weak self] _, _ in
                guard let self else { return }
                let reply = (try? JSONSerialization.jsonObject(with: Data(output.text.utf8))) as? [String: Any]
                // An older version without the command says nothing; its first turn says whether it can answer.
                self.signedOut = reply?["loggedIn"] as? Bool == false
                do { try self.askClaudeModels() } catch { self.finish(AIAgentStatus(kind: self.kind, state: .failed("\(error)"))) }
            })
        }

        private func askClaudeModels() throws {
            let spec = AgentSpec(kind: .claude, executable: executable, model: nil, effort: nil, access: .readOnly, directory: directory)
            let process = AgentProcess(executable: executable, arguments: ClaudeBackend.arguments(spec), directory: directory, environment: environment)
            self.process = process
            try process.start(output: { [weak self] chunk in
                guard let self else { return }
                for line in self.splitter.feed(chunk) {
                    guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], object["type"] as? String == "control_response",
                          let body = (object["response"] as? [String: Any])?["response"] as? [String: Any], let models = body["models"] as? [[String: Any]] else { continue }
                    self.version = body["claude_code_version"] as? String
                    let listed = models.compactMap { model -> AIAgentModel? in
                        guard let id = model["value"] as? String else { return nil }
                        // "default" is the agent's own default; the pane's Default entry stands for it.
                        guard id != "default" else { return nil }
                        return AIAgentModel(id: id, name: model["displayName"] as? String ?? id, efforts: model["supportedEffortLevels"] as? [String] ?? [])
                    }
                    self.finish(AIAgentStatus(kind: self.kind, state: self.signedOut ? .notSignedIn : .ready, version: self.version, models: listed))
                }
            }, exit: { [weak self] in self?.exited($0, $1) })
            let message: [String: Any] = ["type": "control_request", "request_id": "brk-status", "request": ["subtype": "initialize"]]
            if var data = try? JSONSerialization.data(withJSONObject: message) { data.append(0x0A); process.write(data) }
        }

        private func askCodex() throws {
            let spec = AgentSpec(kind: .codex, executable: executable, model: nil, effort: nil, access: .readOnly, directory: directory)
            let process = AgentProcess(executable: executable, arguments: CodexBackend.arguments(spec), directory: directory, environment: environment)
            self.process = process
            let peer = JSONRPCPeer(process: process, tagged: false)
            self.peer = peer
            peer.onRequest = { [weak peer] id, _, _ in peer?.refuse(id, "Not supported by Brk") }
            try process.start(output: { [weak peer] in peer?.feed($0) }, exit: { [weak self] in self?.exited($0, $1) })
            peer.request("initialize", ["clientInfo": ["name": "brk", "title": "Brk", "version": "1"], "capabilities": ["experimentalApi": true]]) { [weak self] result in
                guard let self else { return }
                guard case .success(let body) = result else { self.finish(AIAgentStatus(kind: self.kind, state: .failed("Codex could not start."))); return }
                // "brk/0.164.0 (Mac OS …)": the version, under the client's name.
                self.version = (body["userAgent"] as? String)?.split(separator: " ").first?.split(separator: "/").last.map(String.init)
                self.peer?.notify("initialized")
                self.peer?.request("account/read") { [weak self] result in
                    guard let self else { return }
                    if case .success(let account) = result, account["account"] == nil || account["account"] is NSNull, account["requiresOpenaiAuth"] as? Bool == true {
                        self.finish(AIAgentStatus(kind: self.kind, state: .notSignedIn, version: self.version)); return
                    }
                    self.peer?.request("model/list") { [weak self] result in
                        guard let self else { return }
                        var models: [AIAgentModel] = []
                        if case .success(let list) = result {
                            models = (list["data"] as? [[String: Any]] ?? []).compactMap { model in
                                guard let id = model["id"] as? String, model["hidden"] as? Bool != true else { return nil }
                                let efforts = (model["supportedReasoningEfforts"] as? [[String: Any]] ?? []).compactMap { $0["reasoningEffort"] as? String }
                                return AIAgentModel(id: id, name: model["displayName"] as? String ?? id, efforts: efforts, isDefault: model["isDefault"] as? Bool == true)
                            }
                        }
                        self.finish(AIAgentStatus(kind: self.kind, state: .ready, version: self.version, models: models))
                    }
                }
            }
        }

        private func askACP() throws {
            if kind == .cursor {
                // Cursor's `authenticate` starts a browser sign-in when signed out, so its status command goes first.
                let status = AgentProcess(executable: executable, arguments: ["status"], directory: directory, environment: environment)
                let output = StringBox()
                try status.start(output: { output.append($0) }, exit: { [weak self] _, _ in
                    guard let self else { return }
                    if output.text.lowercased().contains("not logged in") { self.finish(AIAgentStatus(kind: self.kind, state: .notSignedIn)); return }
                    do { try self.openACP() } catch { self.finish(AIAgentStatus(kind: self.kind, state: .failed("\(error)"))) }
                })
                return
            }
            try openACP()
        }

        private func openACP() throws {
            let spec = AgentSpec(kind: kind, executable: executable, model: nil, effort: nil, access: .readOnly, directory: directory)
            let process = AgentProcess(executable: executable, arguments: ACPBackend.arguments(spec), directory: directory, environment: environment)
            self.process = process
            let peer = JSONRPCPeer(process: process, tagged: true)
            self.peer = peer
            peer.onRequest = { [weak peer] id, _, _ in peer?.refuse(id, "Not supported by Brk") }
            try process.start(output: { [weak peer] in peer?.feed($0) }, exit: { [weak self] in self?.exited($0, $1) })
            peer.request("initialize", ["protocolVersion": 1, "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": false], "terminal": false] as [String: Any]]) { [weak self] result in
                guard let self else { return }
                guard case .success(let body) = result else { self.finish(AIAgentStatus(kind: self.kind, state: .failed("\(self.kind.displayName) could not start."))); return }
                self.version = (body["agentInfo"] as? [String: Any])?["version"] as? String
                let open = { [weak self] in
                    guard let self else { return }
                    self.peer?.request("session/new", ["cwd": self.directory.path, "mcpServers": [Any]()]) { [weak self] result in
                        guard let self else { return }
                        switch result {
                        case .success(let session):
                            self.finish(AIAgentStatus(kind: self.kind, state: .ready, version: self.version, models: ACPCatalog.models(session)))
                        case .failure(let error):
                            let message = error.data ?? error.message
                            self.finish(AIAgentStatus(kind: self.kind, state: AgentFailureText.isSignIn(message) ? .notSignedIn : .failed(message), version: self.version))
                        }
                    }
                }
                if self.kind == .cursor {
                    self.peer?.request("authenticate", ["methodId": "cursor_login"]) { [weak self] result in
                        guard let self else { return }
                        if case .failure = result { self.finish(AIAgentStatus(kind: self.kind, state: .notSignedIn, version: self.version)); return }
                        open()
                    }
                } else { open() }
            }
        }
    }
}

/// One prompt in a read-only session of its own, for the features that are not a conversation. The session goes when
/// the answer is in, on cancellation, and at the deadline.
@MainActor final class AgentOneShot: AIProvider {
    let kind: AIProviderKind
    private let executable: URL
    private let options: AIAgentOptions?
    var timeout: Duration = .seconds(120)

    init(kind: AIProviderKind, executable: URL, options: AIAgentOptions?) {
        self.kind = kind
        self.executable = executable
        self.options = options
    }

    func run(_ prompt: String) async throws -> String { try await run(prompt, onPartial: { _ in }) }

    func run(_ prompt: String, onPartial: @escaping @MainActor @Sendable (String) -> Void) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-ai-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let spec = AgentSpec(kind: kind, executable: executable, model: options?.model, effort: options?.effort, access: .readOnly, directory: directory)
        let turn = AIRequestID(UUID().uuidString)
        let state = OneShotState()
        let session = AgentSession(spec: spec, environment: AgentEnvironment.forAgent(kind), plain: false) { output in
            switch output {
            case .partial(_, let text): onPartial(text)
            case .finished(_, let outcome): state.finish(outcome)
            case .notice(let message): state.finish(.failed(message))
            default: break
            }
        }
        let deadline = Task { [timeout] in
            do { try await Task.sleep(for: timeout); state.finish(.failed(AIProviderError.timedOut.description)) } catch {}
        }
        defer { deadline.cancel() }
        let outcome = await withTaskCancellationHandler {
            await state.wait { session.send(prompt, turn: turn) }
        } onCancel: { Task { @MainActor in state.finish(.failed(AIProviderError.cancelled.description)) } }
        await session.close()
        switch outcome {
        case .text(let text): return text
        case .failed(let message): throw AgentRunError(message: message)
        case .unavailable: throw AgentRunError(message: AgentCopy.missing(kind))
        case .reply: throw AgentRunError(message: AIRouteError.wrongShape)
        }
    }
}

struct AgentRunError: Error, CustomStringConvertible, Sendable {
    let message: String
    var description: String { message }
}

@MainActor private final class OneShotState: Sendable {
    private var continuation: CheckedContinuation<AIOutcome, Never>?
    private var outcome: AIOutcome?
    nonisolated init() {}
    func wait(_ start: () -> Void) async -> AIOutcome {
        await withCheckedContinuation { continuation in
            if let outcome { continuation.resume(returning: outcome); return }
            self.continuation = continuation
            start()
        }
    }
    func finish(_ value: AIOutcome) {
        guard outcome == nil else { return }
        outcome = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}
