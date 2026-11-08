import BrkBase
import BrkDomain
import Foundation

/// `codex app-server`: JSON-RPC on stdio. A thread is the session, a turn is one message; text comes as
/// `item/agentMessage/delta`, steps as `item/started` and `item/completed`, approvals as requests from the server.
@MainActor final class CodexBackend: AgentBackend {
    var events: (@MainActor (AgentBackendEvent) -> Void)?
    private(set) var process: AgentProcess?
    var resumeID: String? { spec.access != .readOnly && spec.access != .refresh ? thread : nil }
    private let spec: AgentSpec
    private let environment: [String: String]
    private var peer: JSONRPCPeer?
    private var thread: String?
    private var turn: String?
    private var interrupting = false
    private var queued: String?
    private var pendingApprovals: [String: (id: Any, legacy: Bool)] = [:]
    private var files: [String: String] = [:]

    init(spec: AgentSpec, environment: [String: String]) {
        self.spec = spec
        self.environment = environment
    }

    /// Read-only: no shell tool, no web, no MCP servers, in the sandbox's read-only mode, so a write fails in the
    /// kernel even if a tool were to try one. These hold for the whole process, whatever a thread asks for later.
    static func arguments(_ spec: AgentSpec) -> [String] {
        let account = AIAccountWiring.codexArguments(account: spec.account)
        switch spec.access {
        case .tools: return ["app-server"] + account
        case .readOnly:
            return ["app-server", "-c", "features.shell_tool=false", "-c", "web_search=\"disabled\"", "-c", "mcp_servers={}",
                    "-c", "sandbox_mode=\"read-only\"", "-c", "approval_policy=\"never\""] + account
        case .browser:
            // Brk's server in place of the user's own, no web search (a search query can carry page text out and Codex
            // never asks before one), no ChatGPT connectors, and no network for commands in the sandbox, so a command that
            // reaches out asks to leave it. The user's ~/.codex/rules allow rules did not skip `untrusted` approvals on
            // codex-cli 0.164.0 (two exact matches, both asked).
            return ["app-server", "-c", "mcp_servers=" + (spec.tools.map(Self.mcpServer) ?? "{}"), "-c", "web_search=\"disabled\"",
                    "-c", "features.apps=false", "-c", "sandbox_workspace_write.network_access=false"] + account
        case .refresh:
            // Read-only's switches, Brk's server in place of the user's own, and every feature that gives the model a tool
            // of Codex's own turned off: no shell, no file view, no browser, no helpers, no plugins, hooks or skill search.
            return ["app-server", "-c", "mcp_servers=" + (spec.tools.map(Self.mcpServer) ?? "{}"), "-c", "web_search=\"disabled\"",
                    "-c", "sandbox_mode=\"read-only\"", "-c", "approval_policy=\"never\""]
                + refreshFeaturesOff.flatMap { ["-c", "features.\($0)=false"] } + account
        }
    }

    /// Codex 0.164.0's features that add a tool of its own, off in a refresh. Code mode stays on: it is how this Codex
    /// calls any tool, Brk's included (with it off, codex-1's refreshes called nothing: "code-mode host is disabled").
    /// What is left, asked of the model itself in a probe: apply_patch, clock__curr_time, the three MCP resource tools
    /// (Brk's server has no resources) and Brk's; apply_patch's writes are refused by the read-only sandbox.
    static let refreshFeaturesOff = ["shell_tool", "unified_exec", "apps", "plugins", "hooks", "multi_agent", "image_generation", "browser_use", "browser_use_external",
                                     "computer_use", "in_app_browser", "view_image", "skill_search", "skill_mcp_dependency_install", "goals", "tool_suggest", "sleep_tool"]

    /// `{brk={command="…",args=["…"]}}` as TOML.
    static func mcpServer(_ tools: AgentToolsLink) -> String {
        func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return "{\(BrkToolCatalog.server)={command=\(quoted(tools.command)),args=[\(tools.arguments.map(quoted).joined(separator: ","))]}}"
    }

    func start() throws {
        let process = AgentProcess(executable: spec.executable, arguments: Self.arguments(spec), directory: spec.directory, environment: environment)
        self.process = process
        let peer = JSONRPCPeer(process: process, tagged: false)
        self.peer = peer
        peer.onNotification = { [weak self] in self?.notification($0, $1) }
        peer.onRequest = { [weak self] in self?.request($0, $1, $2) }
        try process.start(output: { [weak peer] in peer?.feed($0) }, exit: { [weak self] status, stderr in
            self?.peer?.failPending("Codex stopped.")
            self?.events?(.exited(status == 0 ? nil : Self.failure(status, stderr)))
        })
        peer.request("initialize", ["clientInfo": ["name": "brk", "title": Product.name, "version": "1"], "capabilities": ["experimentalApi": true]]) { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result { self.events?(.exited(error.message)); return }
            self.peer?.notify("initialized")
            self.readAccount()
        }
    }

    /// A signed-out Codex would start a thread and fail on the first turn; saying so now is clearer.
    private func readAccount() {
        peer?.request("account/read") { [weak self] result in
            guard let self else { return }
            if case .success(let body) = result, body["account"] == nil || body["account"] is NSNull, body["requiresOpenaiAuth"] as? Bool == true {
                self.events?(.exited(AgentCopy.notSignedIn(.codex)))
                self.process?.stop()
                return
            }
            self.openThread()
        }
    }

    /// The request that opens the session's thread. A resumed thread is given the same sandbox, approval policy and
    /// instructions as a new one: left out, it would run on whatever the user's own Codex settings say.
    static func threadRequest(_ spec: AgentSpec) -> (method: String, params: [String: Any]) {
        var params: [String: Any] = ["cwd": spec.directory.path]
        if let model = spec.model { params["model"] = model }
        switch spec.access {
        case .readOnly:
            params["sandbox"] = "read-only"; params["approvalPolicy"] = "never"; params["ephemeral"] = true
        case .tools:
            // Commands not known to be safe, and every file change, ask first. T3 Code pairs this policy with the
            // read-only sandbox; told it is read-only, a small model answers that it cannot write and never asks.
            params["sandbox"] = "workspace-write"; params["approvalPolicy"] = "untrusted"
        case .browser:
            params["sandbox"] = "workspace-write"; params["approvalPolicy"] = "untrusted"
            params["developerInstructions"] = BrkToolCatalog.rules
        case .refresh:
            params["sandbox"] = "read-only"; params["approvalPolicy"] = "never"; params["ephemeral"] = true
            params["developerInstructions"] = BrkToolCatalog.refreshRules
        }
        guard let resume = spec.resume, spec.access != .readOnly, spec.access != .refresh else { return ("thread/start", params) }
        params["threadId"] = resume
        params["excludeTurns"] = true
        return ("thread/resume", params)
    }

    private func openThread() {
        let request = Self.threadRequest(spec)
        let opened: JSONRPCPeer.Reply = { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.events?(.exited(AgentFailureText.isSignIn(error.message) ? AgentCopy.notSignedIn(.codex) : error.message))
            case .success(let body):
                self.thread = (body["thread"] as? [String: Any])?["id"] as? String
                self.events?(.ready(model: body["model"] as? String ?? self.spec.model, effort: self.spec.effort ?? body["reasoningEffort"] as? String))
                if let queued = self.queued { self.queued = nil; self.send(queued) }
            }
        }
        peer?.request(request.method, request.params, reply: opened)
    }

    func send(_ text: String) {
        guard let thread else { queued = text; return }
        interrupting = false
        var params: [String: Any] = ["threadId": thread, "input": [["type": "text", "text": text, "text_elements": []] as [String: Any]]]
        if let effort = spec.effort { params["effort"] = effort }
        if let model = spec.model { params["model"] = model }
        peer?.request("turn/start", params) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.events?(.turnEnded(.failed(AgentFailureText.isSignIn(error.message) ? AgentCopy.notSignedIn(.codex) : error.message)))
            case .success(let body):
                self.turn = (body["turn"] as? [String: Any])?["id"] as? String ?? self.turn
                if self.interrupting { self.sendInterrupt() }
            }
        }
    }

    func interrupt() {
        interrupting = true
        sendInterrupt()
    }

    private func sendInterrupt() {
        guard let thread, let turn else { return }
        peer?.request("turn/interrupt", ["threadId": thread, "turnId": turn])
    }

    func answer(approval: String, option: String) {
        guard let pending = pendingApprovals.removeValue(forKey: approval) else { return }
        if pending.legacy {
            let decision = option == "accept" ? "approved" : option == "acceptForSession" ? "approved_for_session" : option == "cancel" ? "abort" : "denied"
            peer?.respond(pending.id, ["decision": decision])
        } else {
            peer?.respond(pending.id, ["decision": option])
        }
    }

    private func notification(_ method: String, _ params: [String: Any]) {
        switch method {
        case "item/agentMessage/delta":
            if let delta = params["delta"] as? String { events?(.text(delta)) }
        case "turn/started":
            if let id = (params["turn"] as? [String: Any])?["id"] as? String { turn = id }
        case "item/started":
            guard let item = params["item"] as? [String: Any], let step = Self.step(item, state: .running) else { return }
            events?(.step(step))
            if let id = item["id"] as? String, let changes = Self.changes(item) { files[id] = changes }
        case "item/completed":
            guard let item = params["item"] as? [String: Any] else { return }
            if item["type"] as? String == "agentMessage", separatorDue { events?(.text("\n\n")) }
            separatorDue = item["type"] as? String == "agentMessage"
            let status = item["status"] as? String
            guard let step = Self.step(item, state: status == "failed" || status == "declined" ? .failed : .done) else { return }
            events?(.step(step))
        case "thread/tokenUsage/updated":
            // The thread's running total; a refresh's thread is new, so the last total is the turn's.
            if let total = (params["tokenUsage"] as? [String: Any])?["total"] as? [String: Any] {
                usageUpdates += 1
                turnUsage = AIUsageCount(requests: usageUpdates, inputTokens: total["inputTokens"] as? Int ?? 0, outputTokens: total["outputTokens"] as? Int ?? 0,
                                         cachedTokens: total["cachedInputTokens"] as? Int ?? 0)
            }
        case "turn/completed":
            if let usage = turnUsage { events?(.usage(usage)); turnUsage = nil; usageUpdates = 0 }
            let body = params["turn"] as? [String: Any] ?? [:]
            separatorDue = false
            for (id, _) in pendingApprovals { events?(.approvalClosed(id)) }
            pendingApprovals = [:]
            switch body["status"] as? String {
            case "interrupted": events?(.turnEnded(.interrupted))
            case "failed":
                let message = (body["error"] as? [String: Any])?["message"] as? String ?? "Codex could not finish this."
                events?(.turnEnded(.failed(AgentFailureText.isSignIn(message) ? AgentCopy.notSignedIn(.codex) : message)))
            default: events?(.turnEnded(.completed(text: nil)))
            }
        case "serverRequest/resolved": break
        case "model/rerouted":
            if let model = params["toModel"] as? String { events?(.ready(model: model, effort: spec.effort)) }
        default: break
        }
    }
    private var separatorDue = false
    private var turnUsage: AIUsageCount?
    private var usageUpdates = 0

    private func request(_ id: Any, _ method: String, _ params: [String: Any]) {
        // Read-only never asks; anything that does ask is refused without showing it.
        switch method {
        case "item/commandExecution/requestApproval", "execCommandApproval":
            guard spec.access == .tools else { peer?.respond(id, ["decision": method == "execCommandApproval" ? "denied" : "decline"]); return }
            let command = (params["command"] as? String) ?? (params["command"] as? [String])?.joined(separator: " ") ?? ""
            let shown = Self.plainCommand(command)
            ask(id, key: "\(id)", legacy: method == "execCommandApproval", title: "Run: " + AgentCopy.oneLine(shown),
                detail: [AgentCopy.detail(shown), params["reason"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: "\n"), decisions: params["availableDecisions"] as? [Any])
        case "item/fileChange/requestApproval", "applyPatchApproval":
            guard spec.access == .tools else { peer?.respond(id, ["decision": method == "applyPatchApproval" ? "denied" : "decline"]); return }
            let known = (params["itemId"] as? String).flatMap { files[$0] }
            ask(id, key: "\(id)", legacy: method == "applyPatchApproval", title: "Change files", detail: [known ?? "", params["reason"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: "\n"), decisions: params["availableDecisions"] as? [Any])
        case "item/permissions/requestApproval":
            // More access than the sandbox gives: never granted from here. The command can still ask on its own.
            peer?.respond(id, ["permissions": [String: Any](), "scope": "turn"])
        case "mcpServer/elicitation/request":
            // Brk's own tools ask in Brk's panel themselves; anything else's question is declined.
            let brk = (spec.access == .browser || spec.access == .refresh) && params["serverName"] as? String == BrkToolCatalog.server
            peer?.respond(id, brk ? ["action": "accept", "content": [String: Any]()] : ["action": "decline"])
        case "item/tool/requestUserInput":
            peer?.respond(id, ["answers": [String: Any]()])
        default:
            peer?.refuse(id, "Not supported by Brk")
        }
    }

    /// The options the agent offers: an option to remember a rule on disk is not one of Brk's; the decision
    /// it does not list is not shown.
    private func ask(_ id: Any, key: String, legacy: Bool, title: String, detail: String, decisions: [Any]?) {
        pendingApprovals[key] = (id, legacy)
        let names = (decisions ?? ["accept", "acceptForSession", "decline"]).compactMap { $0 as? String }
        var options: [AIAgentApproval.Option] = []
        if names.contains("accept") { options.append(.init(id: "accept", title: "Allow", kind: .allowOnce)) }
        // A browser session asks every time.
        if names.contains("acceptForSession"), spec.access != .browser { options.append(.init(id: "acceptForSession", title: "Allow for Session", kind: .allowSession)) }
        // "decline" lets the turn go on without it; "cancel" also ends the turn.
        if names.contains("decline") { options.append(.init(id: "decline", title: "Deny", kind: .deny)) }
        else { options.append(.init(id: "cancel", title: "Deny", kind: .deny)) }
        events?(.approval(AIAgentApproval(id: key, title: title, detail: detail, options: options)))
    }

    /// Codex shows commands as `/bin/zsh -lc '…'`; the user wants to see the `…`.
    static func plainCommand(_ command: String) -> String {
        for prefix in ["/bin/zsh -lc ", "/bin/bash -lc ", "zsh -lc ", "bash -lc "] where command.hasPrefix(prefix) {
            var rest = String(command.dropFirst(prefix.count))
            for quote in ["'", "\""] where rest.hasPrefix(quote) && rest.hasSuffix(quote) && rest.count >= 2 { rest = String(rest.dropFirst().dropLast()) }
            return rest
        }
        return command
    }

    private static func changes(_ item: [String: Any]) -> String? {
        guard item["type"] as? String == "fileChange", let list = item["changes"] as? [[String: Any]] else { return nil }
        return list.compactMap { $0["path"] as? String }.joined(separator: "\n")
    }

    static func step(_ item: [String: Any], state: AIAgentStep.State) -> AIAgentStep? {
        guard let id = item["id"] as? String else { return nil }
        let title: String
        switch item["type"] as? String {
        case "commandExecution": title = "Run: " + AgentCopy.oneLine(plainCommand(item["command"] as? String ?? ""))
        case "fileChange":
            let paths = (item["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
            title = paths.isEmpty ? "Change files" : "Edit " + paths.joined(separator: ", ")
        case "mcpToolCall":
            let named = [item["server"] as? String, item["tool"] as? String].compactMap { $0 }.joined(separator: ": ")
            title = BrkToolCatalog.stepTitle(named) ?? named
        case "dynamicToolCall": title = item["tool"] as? String ?? "Tool"
        case "webSearch": title = "Search the web: " + AgentCopy.oneLine(item["query"] as? String ?? "")
        case "collabAgentToolCall": title = "Start a helper"
        default: return nil
        }
        return AIAgentStep(id: id, title: title, state: state)
    }

    static func failure(_ status: Int32, _ stderr: String) -> String {
        if AgentFailureText.isSignIn(stderr) { return AgentCopy.notSignedIn(.codex) }
        return AIProviderError.failed(status: status, stderr: stderr).description
    }
}
