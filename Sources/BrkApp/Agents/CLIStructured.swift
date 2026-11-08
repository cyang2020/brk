import BrkBase
import BrkDomain
import Foundation

/// Claude Code on the user's subscription, one read-only process per request. `--json-schema` makes Claude Code give
/// the model a StructuredOutput tool and check what it returns; the answer is the `result` line's `structured_output`,
/// never its text. Read-only as in docs/design/ai-agents.md: no tools, no MCP, no settings files, nothing kept, an empty
/// folder of its own. `--system-prompt` replaces Claude Code's long default prompt (measured 2026-11-08 on Haiku 5.5:
/// a tab name in 1.6 s at half the cost).
@MainActor final class ClaudeStructured: StructuredRunner {
    let executable: URL
    let model: String?
    let effort: String?
    private let environment: [String: String]

    init(executable: URL, model: String?, effort: String?, environment: [String: String]) {
        self.executable = executable
        self.model = model
        self.effort = effort
        self.environment = environment
    }

    static func arguments(model: String?, effort: String?, instructions: String, schema: String) -> [String] {
        var arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"]
        if let model { arguments += ["--model", model] }
        if let effort { arguments += ["--effort", effort] }
        arguments += ["--tools", "", "--permission-mode", "dontAsk", "--no-session-persistence", "--disable-slash-commands",
                      "--strict-mcp-config", "--setting-sources", "", "--system-prompt", instructions, "--json-schema", schema]
        return arguments
    }

    func run(_ prompt: StructuredPrompt) async throws -> StructuredAnswer {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-ai-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = AgentProcess(executable: executable, arguments: Self.arguments(model: model, effort: effort, instructions: prompt.instructions, schema: prompt.schema.text),
                                   directory: directory, environment: environment)
        let wait = OneAnswer<StructuredAnswer>()
        var splitter = LineSplitter()
        let model = self.model
        try process.start(output: { chunk in
            for line in splitter.feed(chunk) where !line.isEmpty {
                guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], object["type"] as? String == "result" else { continue }
                wait.finish(Self.answer(object, model: model))
            }
        }, exit: { status, stderr in
            wait.finish(.failure(AIRouteError.message(status == 0 ? "Claude stopped before it answered." : ClaudeBackend.failure(status, stderr))))
        })
        for message: [String: Any] in [
            ["type": "control_request", "request_id": "brk-1", "request": ["subtype": "initialize"]],
            ["type": "user", "message": ["role": "user", "content": [["type": "text", "text": prompt.input]]] as [String: Any], "parent_tool_use_id": NSNull(), "session_id": ""],
        ] {
            if var data = try? JSONSerialization.data(withJSONObject: message) { data.append(0x0A); process.write(data) }
        }
        defer { process.stop() }
        return try await wait.value(timeout: prompt.timeout)
    }

    /// The `result` line: the checked object, or why there is none.
    static func answer(_ result: [String: Any], model: String?) -> Result<StructuredAnswer, Error> {
        if result["is_error"] as? Bool == true {
            let text = result["result"] as? String ?? (result["errors"] as? [String])?.joined(separator: " ") ?? "Claude could not finish this."
            return .failure(AIRouteError.message(AgentFailureText.isSignIn(text) ? AgentCopy.notSignedIn(.claude) : text))
        }
        guard let object = result["structured_output"], !(object is NSNull),
              let json = try? JSONSerialization.data(withJSONObject: object) else { return .failure(AIRouteError.message(AIRouteError.wrongShape)) }
        let usage = result["usage"] as? [String: Any] ?? [:]
        let read = usage["cache_read_input_tokens"] as? Int ?? 0, write = usage["cache_creation_input_tokens"] as? Int ?? 0
        let count = AIUsageCount(inputTokens: (usage["input_tokens"] as? Int ?? 0) + read + write, outputTokens: usage["output_tokens"] as? Int ?? 0, cachedTokens: read)
        return .success(StructuredAnswer(json: json, usage: count))
    }
}

/// Codex on the user's subscription: one long-lived read-only `codex app-server` for every request, an ephemeral
/// thread per request with `outputSchema` on `turn/start`, so the answer is the final message's JSON. Starting
/// `codex exec` per request carries Codex's whole system prompt each time (15,768 input tokens, 3.6 s); here the
/// thread's `baseInstructions` replace it and Codex's extra features are off (measured 2026-11-08 on gpt-6-luna: about
/// 2 s, 10,500 input tokens, mostly cached from the second request). The process ends after two idle minutes.
@MainActor final class CodexStructured: StructuredRunner {
    let executable: URL
    let model: String?
    let effort: String?
    private let server: CodexAppServer

    init(executable: URL, model: String?, effort: String?, server: CodexAppServer) {
        self.executable = executable
        self.model = model
        self.effort = effort
        self.server = server
    }

    func run(_ prompt: StructuredPrompt) async throws -> StructuredAnswer {
        try await server.answer(prompt, model: model, effort: effort)
    }
}

@MainActor final class CodexAppServer {
    let executable: URL
    private let environment: [String: String]
    private var process: AgentProcess?
    private var peer: JSONRPCPeer?
    private var ready: OneAnswer<Void>?
    private var turns: [String: Turn] = [:]
    private var idle: Task<Void, Never>?
    private let directory: URL
    static let idleSeconds = 120

    private final class Turn {
        let wait = OneAnswer<StructuredAnswer>()
        var text = ""
        var usage = AIUsageCount()
        let model: String?
        init(model: String?) { self.model = model }
    }

    init(executable: URL, environment: [String: String]) {
        self.executable = executable
        self.environment = environment
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-ai-codex-" + UUID().uuidString, isDirectory: true)
    }

    /// Read-only for the whole process, as `CodexBackend`'s, plus every Codex feature a one-shot answer does not need
    /// (hooks, plugins, apps, helpers, the browser, memories, AGENTS.md), so none of them sees page text. Codex ignores
    /// a feature name it does not know.
    static let arguments: [String] = {
        var arguments = ["app-server", "-c", "features.shell_tool=false", "-c", "web_search=\"disabled\"", "-c", "mcp_servers={}",
                         "-c", "sandbox_mode=\"read-only\"", "-c", "approval_policy=\"never\"", "-c", "project_doc_max_bytes=0"]
        for feature in ["hooks", "plugins", "apps", "multi_agent", "goals", "image_generation", "computer_use", "browser_use", "browser_use_external",
                        "in_app_browser", "unified_exec", "view_image", "skill_search", "tool_suggest", "sleep_tool", "memories"] {
            arguments += ["-c", "features.\(feature)=false"]
        }
        return arguments
    }()

    func answer(_ prompt: StructuredPrompt, model: String?, effort: String?) async throws -> StructuredAnswer {
        idle?.cancel()
        defer { scheduleIdle() }
        try await start()
        guard let peer else { throw AIRouteError.message("Codex could not be started.") }
        var thread: [String: Any] = ["cwd": directory.path, "sandbox": "read-only", "approvalPolicy": "never", "ephemeral": true, "baseInstructions": prompt.instructions]
        if let model { thread["model"] = model }
        let opened = OneAnswer<String>()
        peer.request("thread/start", thread) { result in
            switch result {
            case .success(let body):
                if let id = (body["thread"] as? [String: Any])?["id"] as? String { opened.finish(.success(id)) }
                else { opened.finish(.failure(AIRouteError.message("Codex did not open a thread."))) }
            case .failure(let error):
                opened.finish(.failure(AIRouteError.message(AgentFailureText.isSignIn(error.message) ? AgentCopy.notSignedIn(.codex) : error.message)))
            }
        }
        let id = try await opened.value(timeout: .seconds(30))
        let turn = Turn(model: model)
        turns[id] = turn
        defer { turns[id] = nil }
        var params: [String: Any] = ["threadId": id, "input": [["type": "text", "text": prompt.input, "text_elements": []] as [String: Any]],
                                     "outputSchema": prompt.schema.object]
        if let effort { params["effort"] = effort }
        if let model { params["model"] = model }
        peer.request("turn/start", params) { result in
            if case .failure(let error) = result {
                turn.wait.finish(.failure(AIRouteError.message(AgentFailureText.isSignIn(error.message) ? AgentCopy.notSignedIn(.codex) : error.message)))
            }
        }
        return try await turn.wait.value(timeout: prompt.timeout)
    }

    private func start() async throws {
        if let ready { return try await ready.value(timeout: .seconds(30)) }
        let ready = OneAnswer<Void>()
        self.ready = ready
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let process = AgentProcess(executable: executable, arguments: Self.arguments, directory: directory, environment: environment)
        let peer = JSONRPCPeer(process: process, tagged: false)
        self.process = process
        self.peer = peer
        peer.onNotification = { [weak self] in self?.notification($0, $1) }
        // Read-only never asks; anything that does is refused.
        peer.onRequest = { [weak peer] id, method, _ in
            switch method {
            case "item/commandExecution/requestApproval", "item/fileChange/requestApproval": peer?.respond(id, ["decision": "decline"])
            case "execCommandApproval", "applyPatchApproval": peer?.respond(id, ["decision": "denied"])
            default: peer?.refuse(id, "Not supported by Brk")
            }
        }
        do {
            try process.start(output: { [weak peer] in peer?.feed($0) }, exit: { [weak self] status, stderr in
                self?.exited(status == 0 ? "Codex stopped before it answered." : CodexBackend.failure(status, stderr))
            })
        } catch { self.ready = nil; throw AIRouteError.message("Codex could not be started: \(error)") }
        peer.request("initialize", ["clientInfo": ["name": "brk", "title": Product.name, "version": "1"], "capabilities": ["experimentalApi": true]]) { [weak self] result in
            guard case .success = result else { ready.finish(.failure(AIRouteError.message("Codex could not start."))); self?.shutDown(); return }
            self?.peer?.notify("initialized")
            self?.peer?.request("account/read") { result in
                if case .success(let body) = result, body["account"] == nil || body["account"] is NSNull, body["requiresOpenaiAuth"] as? Bool == true {
                    ready.finish(.failure(AIRouteError.message(AgentCopy.notSignedIn(.codex))))
                    self?.shutDown()
                } else { ready.finish(.success(())) }
            }
        }
        try await ready.value(timeout: .seconds(30))
    }

    private func notification(_ method: String, _ params: [String: Any]) {
        guard let thread = params["threadId"] as? String, let turn = turns[thread] else { return }
        switch method {
        case "item/agentMessage/delta": turn.text += params["delta"] as? String ?? ""
        case "item/completed":
            if let item = params["item"] as? [String: Any], item["type"] as? String == "agentMessage", let text = item["text"] as? String { turn.text = text }
        case "thread/tokenUsage/updated":
            let last = (params["tokenUsage"] as? [String: Any])?["last"] as? [String: Any] ?? [:]
            turn.usage = AIUsageCount(inputTokens: last["inputTokens"] as? Int ?? 0, outputTokens: last["outputTokens"] as? Int ?? 0, cachedTokens: last["cachedInputTokens"] as? Int ?? 0)
        case "turn/completed":
            let body = params["turn"] as? [String: Any] ?? [:]
            if body["status"] as? String == "failed" {
                let message = (body["error"] as? [String: Any])?["message"] as? String ?? "Codex could not finish this."
                turn.wait.finish(.failure(AIRouteError.message(AgentFailureText.isSignIn(message) ? AgentCopy.notSignedIn(.codex) : message)))
            } else if let data = turn.text.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
                // With outputSchema the final message is the schema's object.
                turn.wait.finish(.success(StructuredAnswer(json: data, usage: turn.usage)))
            } else { turn.wait.finish(.failure(AIRouteError.message(AIRouteError.wrongShape))) }
        default: break
        }
    }

    private func exited(_ reason: String) {
        ready?.finish(.failure(AIRouteError.message(reason)))
        for turn in turns.values { turn.wait.finish(.failure(AIRouteError.message(reason))) }
        peer?.failPending(reason)
        process = nil; peer = nil; ready = nil
    }

    private func scheduleIdle() {
        idle?.cancel()
        idle = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(Self.idleSeconds)) } catch { return }
            guard let self, self.turns.isEmpty else { return }
            self.shutDown()
        }
    }

    func shutDown() {
        let dead = process
        process = nil; peer = nil; ready = nil
        dead?.stop()
        try? FileManager.default.removeItem(at: directory)
    }
}

/// One value, delivered once: the first `finish` wins; a deadline and the caller's cancellation end the wait too.
@MainActor final class OneAnswer<Value: Sendable> {
    private var result: Result<Value, Error>?
    private var waiters: [CheckedContinuation<Value, Error>] = []

    func finish(_ value: Result<Value, Error>) {
        guard result == nil else { return }
        result = value
        let list = waiters
        waiters = []
        for waiter in list { waiter.resume(with: value) }
    }

    func value(timeout: Duration) async throws -> Value {
        if let result { return try result.get() }
        let deadline = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(.failure(AIRouteError.message(AIRouteError.timedOut)))
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let result { continuation.resume(with: result) } else { waiters.append(continuation) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }
}
