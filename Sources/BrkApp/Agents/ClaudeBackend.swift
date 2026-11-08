import BrkDomain
import Foundation

/// `claude -p` with streaming JSON on both pipes: one long-lived process per session, a user message per turn on stdin,
/// and control requests in both directions (Brk asks to initialize and interrupt; the agent asks to use a tool).
/// With `--permission-prompt-tool stdio` every tool that needs permission comes to Brk as `can_use_tool`.
@MainActor final class ClaudeBackend: AgentBackend {
    var events: (@MainActor (AgentBackendEvent) -> Void)?
    private(set) var process: AgentProcess?
    private(set) var resumeID: String?
    private let spec: AgentSpec
    private let environment: [String: String]
    private var splitter = LineSplitter()
    private var nextRequest = 1
    private var pendingApprovals: [String: (toolUse: String, input: [String: Any], suggestions: [[String: Any]], tool: String)] = [:]
    private var models: [[String: Any]] = []
    private var streamedText = false
    private var interrupting = false
    private var openSteps: Set<String> = []

    init(spec: AgentSpec, environment: [String: String]) {
        self.spec = spec
        self.environment = environment
    }

    /// The command line. Read-only has no tools at all, ignores every settings file and MCP server, and keeps nothing.
    static func arguments(_ spec: AgentSpec) -> [String] {
        var arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
        if let model = spec.model { arguments += ["--model", model] }
        if let effort = spec.effort { arguments += ["--effort", effort] }
        switch spec.access {
        case .readOnly:
            arguments += ["--tools", "", "--permission-mode", "dontAsk", "--no-session-persistence", "--disable-slash-commands", "--strict-mcp-config", "--setting-sources", "",
                          // Asked to act, a model with no tools can write out a tool call as text; this makes it say it cannot.
                          "--append-system-prompt", "You are answering inside a web browser and have no tools here: you cannot read or write files, run commands or browse. If asked to, say so briefly."]
        case .tools:
            arguments += ["--permission-prompt-tool", "stdio", "--permission-mode", "default"]
            if let resume = spec.resume { arguments += ["--resume", resume] }
        case .browser:
            // The user's settings still load, so their skills do (dropping the user source drops ~/.claude/skills too).
            // What would let a tool through without the panel is overridden from the command line: an ask rule for every
            // built-in tool beats their allow rules (deny, then ask, then allow), no hook runs (a PermissionRequest hook
            // could answer for the user), and no MCP server but Brk's loads. Checked on claude 2.1.318: with
            // `Bash(python3:*)` allowed in ~/.claude/settings.json, `python3 -c …` reached Brk as `can_use_tool`.
            arguments += ["--permission-prompt-tool", "stdio", "--permission-mode", "default", "--strict-mcp-config",
                          "--tools", Self.browserTools.joined(separator: ","), "--settings", Self.browserSettings,
                          "--append-system-prompt", BrkToolCatalog.rules]
            if let tools = spec.tools { arguments += ["--mcp-config", Self.mcpConfig(tools), "--allowedTools", "mcp__\(BrkToolCatalog.server)"] }
            if let resume = spec.resume { arguments += ["--resume", resume] }
        case .refresh:
            // Read-only's switches (no built-in tool, no settings file, so no hook, plugin or skill; no slash commands,
            // nothing kept), and Brk's server alone, its refresh tools allowed by name. In `dontAsk` mode a tool that is
            // not allowed is refused without asking.
            arguments += ["--tools", "", "--permission-mode", "dontAsk", "--no-session-persistence", "--disable-slash-commands", "--strict-mcp-config", "--setting-sources", "",
                          "--append-system-prompt", BrkToolCatalog.refreshRules]
            if let tools = spec.tools {
                arguments += ["--mcp-config", Self.mcpConfig(tools), "--allowedTools", BrkToolCatalog.refreshTools.map { "mcp__\(BrkToolCatalog.server)__\($0.rawValue)" }.joined(separator: ",")]
            }
        }
        return arguments
    }

    /// The built-in tools a browser session has: enough for skills (which read their files and run their CLIs) and the
    /// web. Subagents, scheduling and the rest stay out.
    static let browserTools = ["Bash", "Read", "Write", "Edit", "Skill", "WebFetch", "WebSearch"]

    static var browserSettings: String {
        let settings: [String: Any] = ["disableAllHooks": true, "permissions": ["ask": browserTools]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys]), as: UTF8.self)
    }

    static func mcpConfig(_ tools: AgentToolsLink) -> String {
        let config: [String: Any] = ["mcpServers": [BrkToolCatalog.server: ["type": "stdio", "command": tools.command, "args": tools.arguments]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: config, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    /// In a browser session, what Brk answers itself instead of asking: Brk's own tools (their approvals are Brk's), a
    /// skill being loaded, and reading a file of an installed skill or of the session's own empty folder. A skill's
    /// instructions are not the user's data; what a skill then runs asks like anything else.
    static func answersItself(tool: String, input: [String: Any], directory: URL, home: String = NSHomeDirectory()) -> Bool {
        if tool.hasPrefix("mcp__\(BrkToolCatalog.server)__") || tool == "Skill" { return true }
        guard tool == "Read", let path = input["file_path"] as? String, path.hasPrefix("/") else { return false }
        func real(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path }
        let file = URL(fileURLWithPath: path).standardizedFileURL.path
        if real(file).hasPrefix(real(directory.path) + "/") { return true }
        // Installed skills are often links to another folder (~/.claude/skills/lark-doc -> ~/.agents/skills/lark-doc):
        // a file is the skill's when, followed to where it really is, it stays inside that skill's own folder.
        for root in [home + "/.claude/skills", home + "/.claude/plugins"] where file.hasPrefix(root + "/") {
            guard let skill = file.dropFirst(root.count + 1).split(separator: "/").first else { return false }
            return real(file).hasPrefix(real(root + "/" + skill) + "/")
        }
        return false
    }

    func start() throws {
        let process = AgentProcess(executable: spec.executable, arguments: Self.arguments(spec), directory: spec.directory, environment: environment)
        self.process = process
        try process.start(output: { [weak self] in self?.feed($0) }, exit: { [weak self] status, stderr in self?.exited(status, stderr) })
        control(["subtype": "initialize"])
    }

    private func control(_ request: [String: Any]) {
        let id = "brk-\(nextRequest)"
        nextRequest += 1
        write(["type": "control_request", "request_id": id, "request": request])
    }

    private func write(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        process?.write(data)
    }

    func send(_ text: String) {
        streamedText = false
        interrupting = false
        write(["type": "user", "message": ["role": "user", "content": [["type": "text", "text": text]]] as [String: Any],
               "parent_tool_use_id": NSNull(), "session_id": resumeID ?? ""])
    }

    func interrupt() {
        interrupting = true
        control(["subtype": "interrupt"])
    }

    func answer(approval: String, option: String) {
        guard let pending = pendingApprovals.removeValue(forKey: approval) else { return }
        var response: [String: Any]
        if option == "deny" {
            response = ["behavior": "deny", "message": "The user declined this in Brk.", "toolUseID": pending.toolUse]
        } else {
            response = ["behavior": "allow", "updatedInput": pending.input, "toolUseID": pending.toolUse]
            if option == "session" {
                // A rule for this tool in this session. Claude also suggests switching the whole session to accept
                // edits; Brk leaves that out so "for this session" stays about the tool the user saw.
                var updates: [[String: Any]] = pending.suggestions.filter { $0["type"] as? String != "setMode" }.map { var update = $0; update["destination"] = "session"; return update }
                if updates.isEmpty {
                    updates = [["type": "addRules", "rules": [["toolName": pending.tool]], "behavior": "allow", "destination": "session"]]
                }
                response["updatedPermissions"] = updates
            }
        }
        write(["type": "control_response", "response": ["subtype": "success", "request_id": approval, "response": response] as [String: Any]])
    }

    private func feed(_ chunk: Data) {
        for line in splitter.feed(chunk) where !line.isEmpty {
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            receive(object)
        }
        if splitter.overflowed { process?.stop() }
    }

    private func receive(_ object: [String: Any]) {
        switch object["type"] as? String {
        case "control_response":
            guard let response = object["response"] as? [String: Any], let body = response["response"] as? [String: Any] else { return }
            if let listed = body["models"] as? [[String: Any]] {
                models = listed
                events?(.ready(model: modelName(nil), effort: spec.effort))
            }
        case "control_request":
            guard let id = object["request_id"] as? String, let request = object["request"] as? [String: Any],
                  request["subtype"] as? String == "can_use_tool" else {
                // Nothing else is implemented: an answer, so the agent does not wait for one.
                if let id = object["request_id"] as? String {
                    write(["type": "control_response", "response": ["subtype": "error", "request_id": id, "error": "Not supported by Brk"] as [String: Any]])
                }
                return
            }
            let tool = request["tool_name"] as? String ?? "Tool"
            let input = request["input"] as? [String: Any] ?? [:]
            if spec.access == .readOnly || spec.access == .refresh {
                // Read-only and a refresh never ask; a request that arrives anyway is refused without showing it.
                write(["type": "control_response", "response": ["subtype": "success", "request_id": id,
                       "response": ["behavior": "deny", "message": "Tools are off in this conversation.", "toolUseID": request["tool_use_id"] ?? ""] as [String: Any]] as [String: Any]])
                return
            }
            pendingApprovals[id] = (request["tool_use_id"] as? String ?? "", input, request["permission_suggestions"] as? [[String: Any]] ?? [], tool)
            if spec.access == .browser, Self.answersItself(tool: tool, input: input, directory: spec.directory) {
                answer(approval: id, option: "once")
                return
            }
            // A browser session asks every time: no rule for the rest of the session.
            let options: [AIAgentApproval.Option] = spec.access == .browser
                ? [.init(id: "once", title: "Allow", kind: .allowOnce), .init(id: "deny", title: "Deny", kind: .deny)]
                : [.init(id: "once", title: "Allow", kind: .allowOnce), .init(id: "session", title: "Allow for Session", kind: .allowSession), .init(id: "deny", title: "Deny", kind: .deny)]
            events?(.approval(AIAgentApproval(id: id, title: Self.title(tool: tool, input: input), detail: Self.detail(tool: tool, input: input), options: options)))
        case "control_cancel_request":
            if let id = object["request_id"] as? String, pendingApprovals.removeValue(forKey: id) != nil { events?(.approvalClosed(id)) }
        case "system":
            guard object["subtype"] as? String == "init" else { return }
            resumeID = object["session_id"] as? String
            events?(.ready(model: modelName(object["model"] as? String), effort: spec.effort))
        case "stream_event":
            // Subagents' text is theirs; the panel shows what the conversation's agent says.
            guard object["parent_tool_use_id"] is NSNull || object["parent_tool_use_id"] == nil, let event = object["event"] as? [String: Any] else { return }
            switch event["type"] as? String {
            case "content_block_start":
                if (event["content_block"] as? [String: Any])?["type"] as? String == "text", streamedText { events?(.text("\n\n")) }
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta", let text = delta["text"] as? String {
                    streamedText = true
                    events?(.text(text))
                }
            default: break
            }
        case "assistant":
            let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            for block in content where block["type"] as? String == "tool_use" {
                guard let id = block["id"] as? String, openSteps.insert(id).inserted else { continue }
                events?(.step(AIAgentStep(id: id, title: Self.title(tool: block["name"] as? String ?? "Tool", input: block["input"] as? [String: Any] ?? [:]), state: .running)))
                stepTitles[id] = Self.title(tool: block["name"] as? String ?? "Tool", input: block["input"] as? [String: Any] ?? [:])
            }
        case "user":
            let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            for block in content where block["type"] as? String == "tool_result" {
                guard let id = block["tool_use_id"] as? String, let title = stepTitles.removeValue(forKey: id) else { continue }
                openSteps.remove(id)
                events?(.step(AIAgentStep(id: id, title: title, state: block["is_error"] as? Bool == true ? .failed : .done)))
            }
        case "result":
            // Ending a turn ends whatever it was still doing.
            for id in openSteps { if let title = stepTitles.removeValue(forKey: id) { events?(.step(AIAgentStep(id: id, title: title, state: .failed))) } }
            openSteps = []
            for id in pendingApprovals.keys { events?(.approvalClosed(id)) }
            pendingApprovals = [:]
            if let usage = object["usage"] as? [String: Any] {
                let read = usage["cache_read_input_tokens"] as? Int ?? 0, write = usage["cache_creation_input_tokens"] as? Int ?? 0
                events?(.usage(AIUsageCount(requests: max(1, object["num_turns"] as? Int ?? 1), inputTokens: (usage["input_tokens"] as? Int ?? 0) + read + write,
                                            outputTokens: usage["output_tokens"] as? Int ?? 0, cachedTokens: read,
                                            cost: spec.account == .subscription ? nil : object["total_cost_usd"] as? Double)))
            }
            let text = object["result"] as? String
            if interrupting { events?(.turnEnded(.interrupted)) }
            else if object["is_error"] as? Bool == true {
                let message = text ?? (object["errors"] as? [String])?.joined(separator: " ") ?? "Claude could not finish this."
                events?(.turnEnded(.failed(AgentFailureText.isSignIn(message) ? AgentCopy.notSignedIn(.claude) : message)))
            } else { events?(.turnEnded(.completed(text: streamedText ? nil : text))) }
        default: break
        }
    }
    private var stepTitles: [String: String] = [:]

    /// The name the user knows. What the agent says it runs comes first: the user's own settings can pick a model the
    /// list's default entry does not name. "claude-fable-5-1" reads as the entry called "Fable 5.1".
    private func modelName(_ reported: String?) -> String? {
        if let reported {
            let named = models.lazy.compactMap { $0["displayName"] as? String }.first {
                reported.hasSuffix($0.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ".", with: "-"))
            }
            return named ?? reported
        }
        if let chosen = spec.model, let entry = models.first(where: { $0["value"] as? String == chosen }) { return entry["displayName"] as? String ?? chosen }
        if let entry = models.first(where: { $0["value"] as? String == "default" }), let description = entry["description"] as? String,
           let name = description.components(separatedBy: " · ").first, !name.isEmpty { return name }
        return spec.model
    }

    private func exited(_ status: Int32, _ stderr: String) {
        events?(.exited(status == 0 ? nil : Self.failure(status, stderr)))
    }

    static func failure(_ status: Int32, _ stderr: String) -> String {
        if AgentFailureText.isSignIn(stderr) { return AgentCopy.notSignedIn(.claude) }
        return AIProviderError.failed(status: status, stderr: stderr).description
    }

    static func title(tool: String, input: [String: Any]) -> String {
        let text = { (key: String) in input[key] as? String }
        switch tool {
        case "Bash": return "Run: " + AgentCopy.oneLine(text("command") ?? "")
        case "Read": return "Read " + (text("file_path") ?? "a file")
        case "Write": return "Write " + (text("file_path") ?? "a file")
        case "Edit", "MultiEdit", "NotebookEdit": return "Edit " + (text("file_path") ?? text("notebook_path") ?? "a file")
        case "Grep", "Glob": return "Search: " + AgentCopy.oneLine(text("pattern") ?? "")
        case "WebFetch": return "Fetch " + (text("url") ?? "a page")
        case "WebSearch": return "Search the web: " + AgentCopy.oneLine(text("query") ?? "")
        case "Task": return "Start a helper: " + AgentCopy.oneLine(text("description") ?? "")
        case "TodoWrite": return "Update the task list"
        case "Skill": return "Use the skill " + (text("skill") ?? text("name") ?? "")
        default: return BrkToolCatalog.stepTitle(tool) ?? tool
        }
    }

    static func detail(tool: String, input: [String: Any]) -> String {
        switch tool {
        case "Bash": return AgentCopy.detail(input["command"] as? String ?? "")
        case "Write": return AgentCopy.detail(input["content"] as? String ?? "")
        case "Edit": return AgentCopy.detail(input["new_string"] as? String ?? "")
        default:
            guard let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]) else { return "" }
            return AgentCopy.detail(String(decoding: data, as: UTF8.self))
        }
    }
}
