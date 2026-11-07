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
            arguments += ["--tools", "", "--permission-mode", "dontAsk", "--no-session-persistence", "--disable-slash-commands", "--strict-mcp-config", "--setting-sources", ""]
        case .tools:
            arguments += ["--permission-prompt-tool", "stdio", "--permission-mode", "default"]
            if let resume = spec.resume { arguments += ["--resume", resume] }
        }
        return arguments
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
            if spec.access == .readOnly {
                // Read-only never asks; a request that arrives anyway is refused without showing it.
                write(["type": "control_response", "response": ["subtype": "success", "request_id": id,
                       "response": ["behavior": "deny", "message": "Tools are off in this conversation.", "toolUseID": request["tool_use_id"] ?? ""] as [String: Any]] as [String: Any]])
                return
            }
            pendingApprovals[id] = (request["tool_use_id"] as? String ?? "", input, request["permission_suggestions"] as? [[String: Any]] ?? [], tool)
            events?(.approval(AIAgentApproval(id: id, title: Self.title(tool: tool, input: input), detail: Self.detail(tool: tool, input: input), options: [
                .init(id: "once", title: "Allow", kind: .allowOnce), .init(id: "session", title: "Allow for Session", kind: .allowSession), .init(id: "deny", title: "Deny", kind: .deny),
            ])))
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

    /// The name the user knows: the chosen model's, else the default entry's first words ("Opus 5.5 · Best for…").
    private func modelName(_ reported: String?) -> String? {
        if let chosen = spec.model, let entry = models.first(where: { $0["value"] as? String == chosen }) { return entry["displayName"] as? String ?? chosen }
        if let entry = models.first(where: { $0["value"] as? String == "default" }), let description = entry["description"] as? String,
           let name = description.components(separatedBy: " · ").first, !name.isEmpty { return name }
        return spec.model ?? reported
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
        default: return tool
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
