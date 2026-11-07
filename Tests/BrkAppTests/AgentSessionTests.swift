import BrkBase
import BrkDomain
import BrkEngine
import Darwin
import Foundation
import XCTest
@testable import BrkApp

/// Every agent's session protocol against Tests/Fixtures/ai-provider, which speaks them and never opens the network.
@MainActor
final class AgentSessionTests: XCTestCase {
    private var fixture: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ai-provider") }

    private final class Recorder {
        var partials: [AIRequestID: String] = [:]
        var finished: [AIRequestID: AIOutcome] = [:]
        var steps: [AIAgentStep] = []
        var approvals: [AIAgentApproval] = []
        var started: (model: String?, effort: String?)?
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brk-agent-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func session(_ kind: AIProviderKind, access: AgentAccess = .readOnly, model: String? = nil, directory: URL, log: URL? = nil, child: URL? = nil, readOnlyMode: String? = nil) -> (AgentSession, Recorder) {
        let recorder = Recorder()
        var environment = ProcessInfo.processInfo.environment
        if let readOnlyMode { environment["BRK_AI_FIXTURE_ACP_READONLY"] = readOnlyMode }
        if let log { environment["BRK_AI_FIXTURE_LOG"] = log.path }
        if let child { environment["BRK_AI_FIXTURE_CHILD"] = child.path }
        let spec = AgentSpec(kind: kind, executable: fixture, model: model, effort: nil, access: access, directory: directory)
        let session = AgentSession(spec: spec, environment: environment, plain: false) { output in
            switch output {
            case .started(let model, let effort): recorder.started = (model, effort)
            case .partial(let turn, let text): recorder.partials[turn] = text
            case .finished(let turn, let outcome): recorder.finished[turn] = outcome
            case .step(let step, _):
                if let index = recorder.steps.firstIndex(where: { $0.id == step.id }) { recorder.steps[index] = step } else { recorder.steps.append(step) }
            case .approval(let approval, _): recorder.approvals.append(approval)
            case .approvalClosed, .notice: break
            }
        }
        return (session, recorder)
    }

    private func wait(_ what: String, seconds: Double = 15, _ condition: @MainActor () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > end { XCTFail("timed out: \(what)"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func entries(_ log: URL) -> [[String: Any]] {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(whereSeparator: \.isNewline).compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    func testEveryAgentStreamsAndAnswersFollowUpsInOneProcess() async throws {
        for kind in AIProviderKind.allCases {
            let folder = try directory(), log = folder.appendingPathComponent("log.jsonl")
            let (session, recorder) = session(kind, directory: folder, log: log)
            let first = AIRequestID("first"), second = AIRequestID("second")
            session.send("fixture:stream", turn: first)
            try await wait("\(kind): text before the end") { recorder.partials[first] == "first\n" }
            XCTAssertNil(recorder.finished[first], "\(kind) ended early")
            try await wait("\(kind): the end") { recorder.finished[first] != nil }
            XCTAssertEqual(recorder.finished[first], .text("first\nsecond"), "\(kind)")
            if kind == .claude { XCTAssertEqual(recorder.started?.model, "claude-fixture-opus", "what the agent says it runs, when the list does not name it") }
            session.send("next", turn: second)
            try await wait("\(kind): the follow-up") { recorder.finished[second] != nil }
            XCTAssertEqual(recorder.finished[second], .text("Fixture answer to: next"), "\(kind)")
            let prompts = entries(log).filter { $0["prompt"] != nil }
            XCTAssertEqual(prompts.count, 2, "\(kind)")
            XCTAssertEqual(Set(prompts.compactMap { $0["pid"] as? Int32 }).count, 1, "\(kind) started a process per turn")
            let pid = try XCTUnwrap(prompts.first?["pid"] as? Int32)
            await session.close()
            XCTAssertTrue(kill(pid, 0) == -1 && errno == ESRCH, "\(kind) outlived its session")
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "\(kind)'s read-only folder stayed")
        }
    }

    func testReadOnlyArgumentsAreTheStrictestAndToolsNeverSkipApproval() {
        let folder = URL(fileURLWithPath: "/tmp/x")
        func spec(_ kind: AIProviderKind, _ access: AgentAccess) -> AgentSpec { AgentSpec(kind: kind, executable: fixture, model: nil, effort: nil, access: access, directory: folder) }
        let claude = ClaudeBackend.arguments(spec(.claude, .readOnly))
        XCTAssertEqual(claude[claude.firstIndex(of: "--tools")! + 1], "")
        XCTAssertTrue(claude.contains("--strict-mcp-config") && claude.contains("--no-session-persistence"))
        XCTAssertEqual(claude[claude.firstIndex(of: "--setting-sources")! + 1], "")
        XCTAssertFalse(claude.contains("--permission-prompt-tool"))
        let codex = CodexBackend.arguments(spec(.codex, .readOnly))
        for part in ["features.shell_tool=false", "web_search=\"disabled\"", "mcp_servers={}", "sandbox_mode=\"read-only\"", "approval_policy=\"never\""] { XCTAssertTrue(codex.contains(part), part) }
        let gemini = ACPBackend.arguments(spec(.gemini, .readOnly))
        XCTAssertTrue(gemini.contains("--skip-trust"), "plan mode falls back to default in a folder that is not trusted")
        XCTAssertEqual(gemini[gemini.firstIndex(of: "--approval-mode")! + 1], "plan")
        XCTAssertEqual(ACPBackend.readOnlyMode(.cursor), "ask")
        XCTAssertEqual(ACPBackend.readOnlyMode(.opencode), "plan")
        for kind in AIProviderKind.allCases {
            let tools: [String]
            switch kind {
            case .claude: tools = ClaudeBackend.arguments(spec(kind, .tools))
            case .codex: tools = CodexBackend.arguments(spec(kind, .tools))
            default: tools = ACPBackend.arguments(spec(kind, .tools))
            }
            for bad in ["--dangerously-skip-permissions", "--allow-dangerously-skip-permissions", "bypassPermissions", "--yolo", "-y", "--force", "--approval-mode"] {
                XCTAssertFalse(tools.contains(bad), "\(kind): \(bad)")
            }
        }
        XCTAssertTrue(ClaudeBackend.arguments(spec(.claude, .tools)).contains("--permission-prompt-tool"))
    }

    func testToolsAskAndTheAnswerDecides() async throws {
        for kind in AIProviderKind.allCases {
            let folder = try directory()
            let (session, recorder) = session(kind, access: .tools, directory: folder)
            session.begin()
            try await wait("\(kind): started") { recorder.started != nil }
            let file = folder.appendingPathComponent("written.txt")
            let denied = AIRequestID("denied")
            session.send("fixture:tool", turn: denied)
            try await wait("\(kind): the question") { recorder.approvals.count == 1 }
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "\(kind) ran before the answer")
            let question = recorder.approvals[0]
            XCTAssertTrue(question.options.contains { $0.kind == .allowOnce } && question.options.contains { $0.kind == .deny }, "\(kind): \(question.options)")
            session.answer(approval: question.id, option: question.options.first { $0.kind == .deny }!.id)
            try await wait("\(kind): the end") { recorder.finished[denied] != nil }
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "\(kind): Deny wrote the file")
            let allowed = AIRequestID("allowed")
            session.send("fixture:tool", turn: allowed)
            try await wait("\(kind): the question again") { recorder.approvals.count == 2 }
            session.answer(approval: recorder.approvals[1].id, option: recorder.approvals[1].options.first { $0.kind == .allowOnce }!.id)
            try await wait("\(kind): the end again") { recorder.finished[allowed] != nil }
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "\(kind): Allow did not write the file")
            XCTAssertTrue(recorder.steps.contains { $0.state == .done }, "\(kind): \(recorder.steps)")
            await session.close()
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "\(kind): closing removed the user's folder")
        }
    }

    func testAReadOnlySessionAnswersApprovalsItselfAndNeverWrites() async throws {
        for kind in [AIProviderKind.claude, .codex] {
            let folder = try directory()
            let (session, recorder) = session(kind, directory: folder)
            let turn = AIRequestID("turn")
            session.send("fixture:tool", turn: turn)
            try await wait("\(kind): the end") { recorder.finished[turn] != nil }
            XCTAssertTrue(recorder.approvals.isEmpty, "\(kind) showed an approval")
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("written.txt").path))
            await session.close()
        }
    }

    func testAReadOnlySessionThatCannotEnterItsReadOnlyModeSendsNothing() async throws {
        for (kind, readOnlyMode) in [(AIProviderKind.gemini, "absent"), (.gemini, "fails"), (.cursor, "absent"), (.cursor, "fails"), (.opencode, "fails")] {
            let folder = try directory()
            let log = folder.appendingPathComponent("log")
            let (session, recorder) = session(kind, directory: folder, log: log, readOnlyMode: readOnlyMode)
            let turn = AIRequestID("turn")
            session.send("the page's text", turn: turn)
            try await wait("\(kind) \(readOnlyMode): the end") { recorder.finished[turn] != nil }
            guard case .failed(let message)? = recorder.finished[turn] else { XCTFail("\(kind) \(readOnlyMode) answered"); continue }
            XCTAssertTrue(message.contains("read-only mode"), message)
            XCTAssertFalse(entries(log).contains { $0["prompt"] != nil }, "\(kind) \(readOnlyMode) got the text")
            await session.close()
        }
    }

    func testStopEndsTheCommandInItsOwnGroupAndTheSessionGoesOn() async throws {
        for kind in [AIProviderKind.claude, .codex, .gemini] {
            let folder = try directory(), childFile = folder.appendingPathComponent("child")
            let (session, recorder) = session(kind, access: .tools, directory: folder, child: childFile)
            session.begin()
            try await wait("\(kind): started") { recorder.started != nil }
            let turn = AIRequestID("running")
            session.send("fixture:slowstop", turn: turn)
            try await wait("\(kind): the command") { FileManager.default.fileExists(atPath: childFile.path) }
            let child = try XCTUnwrap(Int32(String(contentsOf: childFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
            XCTAssertEqual(kill(child, 0), 0)
            XCTAssertNotEqual(getpgid(child), getpgid(getpid()))
            session.stop(turn: turn)
            try await wait("\(kind): the command gone") { kill(child, 0) == -1 && errno == ESRCH }
            let next = AIRequestID("next")
            session.send("still here", turn: next)
            try await wait("\(kind): the next answer") { recorder.finished[next] != nil }
            XCTAssertEqual(recorder.finished[next], .text("Fixture answer to: still here"), "\(kind)")
            await session.close()
        }
    }

    func testAnAgentThatIgnoresStopIsEndedAndTheNextMessageStartsAnother() async throws {
        let folder = try directory(), log = folder.appendingPathComponent("log.jsonl")
        let (session, recorder) = session(.claude, access: .tools, directory: folder, log: log)
        let turn = AIRequestID("hung")
        session.send("fixture:hang", turn: turn)
        try await wait("the agent hangs") { entries(log).contains { $0["prompt"] as? String == "fixture:hang" } }
        let pid = try XCTUnwrap(entries(log).last?["pid"] as? Int32)
        session.stop(turn: turn)
        try await wait("Brk ends it", seconds: 8) { kill(pid, 0) == -1 && errno == ESRCH }
        let next = AIRequestID("next")
        session.send("again", turn: next)
        try await wait("a new process answers") { recorder.finished[next] != nil }
        XCTAssertEqual(recorder.finished[next], .text("Fixture answer to: again"))
        XCTAssertNotEqual(entries(log).filter { $0["prompt"] != nil }.last?["pid"] as? Int32, pid)
        await session.close()
    }

    func testAFailureComesBackWithTheReason() async throws {
        let folder = try directory()
        let (session, recorder) = session(.claude, directory: folder)
        let turn = AIRequestID("fail")
        session.send("fixture:fail", turn: turn)
        try await wait("the failure") { recorder.finished[turn] != nil }
        guard case .failed(let message)? = recorder.finished[turn] else { return XCTFail("\(String(describing: recorder.finished[turn]))") }
        XCTAssertTrue(message.contains("23") && message.contains("Terminal"), message)
        await session.close()
    }

    func testASignedOutAgentIsToldApart() async throws {
        let folder = try directory()
        let (session, recorder) = session(.claude, directory: folder)
        let turn = AIRequestID("signedout")
        session.send("fixture:signedout", turn: turn)
        try await wait("the message") { recorder.finished[turn] != nil }
        XCTAssertEqual(recorder.finished[turn], .failed(AgentCopy.notSignedIn(.claude)))
        await session.close()
        XCTAssertTrue(AgentCopy.notSignedIn(.gemini).contains("Terminal"))
        XCTAssertTrue(AgentCopy.missing(.cursor).contains("cursor-agent"))
    }

    /// A request that names an agent gets that agent or the reason it cannot, whatever else is installed.
    func testAnExplicitChoiceNeverFallsBackToAnotherAgent() async throws {
        XCTAssertEqual(AIProviderSeam.resolve(.gemini, active: .claude, detected: [.claude]), .gemini)
        XCTAssertEqual(AIProviderSeam.resolve(.cursor, active: .claude, detected: [.claude]), .cursor)
        XCTAssertEqual(AIProviderSeam.resolve(.auto, active: .codex, detected: [.claude, .codex]), .codex)
        XCTAssertNil(AIProviderSeam.resolve(.off, active: .claude, detected: [.claude]))
        XCTAssertNil(AIProviderSeam.provider(for: .gemini, detected: [.claude], active: .claude))
        let outcome = await AIProviderSeam.answer(.ask("x"), choice: .gemini, detected: [.claude], active: .claude)
        XCTAssertEqual(outcome, .failed(AgentCopy.missing(.gemini)))
        // The same through a conversation, the way the panel asks.
        var events: [SystemEvent] = []
        let services = AIServices(engine: StubEngine(), send: { events.append($0) })
        let max = try JSONDecoder().decode(MaxSnapshot.self, from: Data(#"{"settings":{"provider":"auto","renamePinnedTabs":false,"tidyTabs":false},"detected":["claude"],"active":"claude","agents":[],"agentCardOpen":false}"#.utf8))
        let id = AIRequestID("explicit")
        services.openConversation(id, folder: nil, choice: .auto, max: max)
        services.answer(id, task: .ask("x"), choice: .gemini, max: max)
        XCTAssertEqual(events, [.aiResult(id, .failed(AgentCopy.missing(.gemini)))])
    }

    func testTheOneShotProviderRunsReadOnlyAndCleansUp() async throws {
        let provider = AgentOneShot(kind: .codex, executable: fixture, options: AIAgentOptions(model: "fixture-sol"))
        var partial: String?
        let text = try await provider.run("what", onPartial: { partial = $0 })
        XCTAssertEqual(text, "Fixture answer to: what")
        XCTAssertNotNil(partial)
    }

    func testStatusComesFromTheAgentsThemselves() async throws {
        let environment = ProcessInfo.processInfo.environment
        let claude = await AgentCatalog.status(.claude, executable: fixture, environment: environment)
        XCTAssertEqual(claude.state, .ready)
        XCTAssertEqual(claude.version, "9.9.9-fixture")
        XCTAssertEqual(claude.models.map(\.id), ["fixture-haiku"], "the agent's default is the pane's Default entry")
        let codex = await AgentCatalog.status(.codex, executable: fixture, environment: environment)
        XCTAssertEqual(codex.models.map(\.id), ["fixture-sol"], "hidden models stay hidden")
        XCTAssertEqual(codex.models.first?.efforts, ["low", "high"])
        let gemini = await AgentCatalog.status(.gemini, executable: fixture, environment: environment)
        XCTAssertEqual(gemini.models.map(\.id), ["fixture-flash", "fixture-pro"])
        XCTAssertEqual(gemini.models.first(where: \.isDefault)?.id, "fixture-flash")
    }

    func testAgentsRunWithoutKeysOrAParentAgentsSettings() {
        let environment = AgentEnvironment.forAgent(.cursor, base: ["ANTHROPIC_API_KEY": "x", "OPENAI_API_KEY": "x", "CLAUDE_CODE_ENTRYPOINT": "sdk", "CLAUDE_CONFIG_DIR": "/c", "CODEX_HOME": "/h", "PATH": "/usr/bin", "HOME": "/u"])
        XCTAssertNil(environment["ANTHROPIC_API_KEY"])
        XCTAssertNil(environment["OPENAI_API_KEY"])
        XCTAssertNil(environment["CLAUDE_CODE_ENTRYPOINT"])
        XCTAssertEqual(environment["CLAUDE_CONFIG_DIR"], "/c")
        XCTAssertEqual(environment["CODEX_HOME"], "/h")
        XCTAssertEqual(environment["NO_OPEN_BROWSER"], "1", "Brk never starts a sign-in")
        XCTAssertTrue(environment["PATH"]!.contains("/opt/homebrew/bin"), "a GUI app's PATH is short")
        XCTAssertTrue(environment["PATH"]!.hasPrefix("/usr/bin") || environment["PATH"]!.contains("/usr/bin"))
    }

    func testFindsCursorUnderItsOwnCommandName() throws {
        let folder = try directory()
        let tool = folder.appendingPathComponent("cursor-agent")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        XCTAssertEqual(AIProviderSeam.executable(for: .cursor, environment: ["PATH": folder.path], alsoIn: []), tool)
        XCTAssertEqual(AIProviderSeam.detect(environment: ["PATH": folder.path], alsoIn: []), [.cursor])
    }

    func testTheLoginShellsPathIsRead() async throws {
        let folder = try directory()
        let shell = folder.appendingPathComponent("fake-shell")
        try Data("#!/bin/sh\necho 'noise from a startup file'\nprintf '%s\\n' '__BRK_PATH_START__'\necho /from/the/login/shell:/usr/bin\nprintf '%s\\n' '__BRK_PATH_END__'\n".utf8).write(to: shell)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        await AgentEnvironment.loadShellPath(shell: shell.path)
        XCTAssertEqual(AgentEnvironment.searchPath(environment: [:]).first, "/from/the/login/shell")
    }

    func testProcessTreeFindsADescendantInAnotherGroup() throws {
        let table = [ProcessTree.Entry(pid: 10, parent: 1, group: 10), .init(pid: 11, parent: 10, group: 10), .init(pid: 12, parent: 11, group: 12), .init(pid: 13, parent: 12, group: 12), .init(pid: 20, parent: 1, group: 20)]
        XCTAssertEqual(ProcessTree.members(root: 10, in: table), [10, 11, 12, 13])
        XCTAssertFalse(ProcessTree.snapshot().isEmpty)
    }

    func testLineSplitterKeepsAPartialLine() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.feed(Data("ab".utf8)), [])
        XCTAssertEqual(splitter.feed(Data("c\nde\nf".utf8)).map { String(decoding: $0, as: UTF8.self) }, ["abc", "de"])
        XCTAssertEqual(splitter.feed(Data("\n".utf8)).map { String(decoding: $0, as: UTF8.self) }, ["f"])
    }

    func testStepTitlesAndCommandsReadPlainly() {
        XCTAssertEqual(ClaudeBackend.title(tool: "Bash", input: ["command": "ls\n-la"]), "Run: ls -la")
        XCTAssertEqual(ClaudeBackend.title(tool: "Edit", input: ["file_path": "/a.swift"]), "Edit /a.swift")
        XCTAssertEqual(CodexBackend.plainCommand("/bin/zsh -lc 'cat hello.txt'"), "cat hello.txt")
        XCTAssertEqual(CodexBackend.plainCommand("/bin/zsh -lc \"printf 'hi' > a.txt\""), "printf 'hi' > a.txt")
        XCTAssertEqual(CodexBackend.step(["type": "fileChange", "id": "x", "changes": [["path": "/a"]]], state: .done)?.title, "Edit /a")
        XCTAssertNil(CodexBackend.step(["type": "agentMessage", "id": "x"], state: .done))
    }
}
