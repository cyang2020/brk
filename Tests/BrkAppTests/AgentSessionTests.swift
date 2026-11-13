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

    private func session(_ kind: AIProviderKind, access: AgentAccess = .readOnly, model: String? = nil, directory: URL, log: URL? = nil, child: URL? = nil, readOnlyMode: String? = nil,
                         resume: String? = nil, bridge: URL? = nil, streamRelease: URL? = nil) -> (AgentSession, Recorder) {
        let recorder = Recorder()
        var environment = ProcessInfo.processInfo.environment
        if let readOnlyMode { environment["BRK_AI_FIXTURE_ACP_READONLY"] = readOnlyMode }
        if let log { environment["BRK_AI_FIXTURE_LOG"] = log.path }
        if let child { environment["BRK_AI_FIXTURE_CHILD"] = child.path }
        if let bridge { environment["BRK_AI_FIXTURE_BRIDGE"] = bridge.path }
        if let streamRelease { environment["BRK_AI_FIXTURE_STREAM_RELEASE"] = streamRelease.path }
        var spec = AgentSpec(kind: kind, executable: fixture, model: model, effort: nil, access: access, directory: directory)
        spec.resume = resume
        let session = AgentSession(spec: spec, environment: environment, plain: false) { output in
            switch output {
            case .started(let model, let effort): recorder.started = (model, effort)
            case .partial(let turn, let text): recorder.partials[turn] = text
            case .finished(let turn, let outcome): recorder.finished[turn] = outcome
            case .step(let step, _):
                if let index = recorder.steps.firstIndex(where: { $0.id == step.id }) { recorder.steps[index] = step } else { recorder.steps.append(step) }
            case .approval(let approval, _): recorder.approvals.append(approval)
            case .approvalClosed, .notice, .usage: break
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
            let release = folder.appendingPathComponent("release-stream")
            let (session, recorder) = session(kind, directory: folder, log: log, streamRelease: release)
            let first = AIRequestID("first"), second = AIRequestID("second")
            session.send("fixture:stream", turn: first)
            try await wait("\(kind): text before the end") { recorder.partials[first] == "first\n" }
            XCTAssertNil(recorder.finished[first], "\(kind) ended early")
            try Data().write(to: release)
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

    /// The first message starts the agent, so the turn begins before the agent is up. What the agent starts on its way
    /// up (here the shell that ends its tree if Brk crashes; for a real agent also Brk's tab tools bridge) is not the
    /// turn's: a Stop of that first turn leaves it.
    func testStoppingTheFirstTurnLeavesWhatTheAgentStartedOnItsWayUp() async throws {
        let folder = try directory(), childFile = folder.appendingPathComponent("child"), log = folder.appendingPathComponent("calls.jsonl")
        let (session, _) = session(.claude, access: .tools, directory: folder, log: log, child: childFile)
        let turn = AIRequestID("first")
        session.send("fixture:slowstop", turn: turn)
        try await wait("the command") { FileManager.default.fileExists(atPath: childFile.path) }
        let child = try XCTUnwrap(Int32(String(contentsOf: childFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let agent = try XCTUnwrap(entries(log).first?["pid"] as? Int32)
        let watchers = ProcessTree.members(root: agent, in: ProcessTree.snapshot()).subtracting([agent, child])
        XCTAssertFalse(watchers.isEmpty, "the watcher shell runs beside the agent")
        session.stop(turn: turn)
        try await wait("the command gone") { kill(child, 0) == -1 && errno == ESRCH }
        // A stop's second signal, the one a shell cannot ignore, follows the first after `AgentProcess.grace`.
        try await Task.sleep(for: .seconds(AgentProcess.grace + 0.5))
        for watcher in watchers { XCTAssertEqual(kill(watcher, 0), 0, "the watcher \(watcher) was ended with the turn") }
        await session.close()
    }

    /// The user can stop the first turn before the agent is even up. What the agent starts on its way up and as that turn
    /// begins is still not the turn's: the watcher shell, and the MCP servers Claude may start only after it answered
    /// initialize (Brk's tab tools bridge among them; here the fixture's stand-in). The command the turn ran goes.
    func testAStopBeforeTheAgentIsUpLeavesWhatItStartedOnItsWayUp() async throws {
        let folder = try directory(), log = folder.appendingPathComponent("calls.jsonl")
        let childFile = folder.appendingPathComponent("child"), bridgeFile = folder.appendingPathComponent("bridge")
        let (session, _) = session(.claude, access: .tools, directory: folder, log: log, child: childFile, bridge: bridgeFile)
        let turn = AIRequestID("first")
        session.send("fixture:slowstop", turn: turn)
        session.stop(turn: turn)
        try await wait("the command") { FileManager.default.fileExists(atPath: childFile.path) }
        func pid(_ file: URL) throws -> Int32 { try XCTUnwrap(Int32(String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))) }
        let child = try pid(childFile), bridge = try pid(bridgeFile)
        let agent = try XCTUnwrap(entries(log).first?["pid"] as? Int32)
        let watchers = ProcessTree.members(root: agent, in: ProcessTree.snapshot()).subtracting([agent, child, bridge])
        XCTAssertFalse(watchers.isEmpty, "the watcher shell runs beside the agent")
        try await wait("the command gone") { kill(child, 0) == -1 && errno == ESRCH }
        try await Task.sleep(for: .seconds(AgentProcess.grace + 0.5))
        for kept in watchers.union([bridge]) { XCTAssertEqual(kill(kept, 0), 0, "\(kept) was ended with the stopped turn (bridge \(bridge))") }
        await session.close()
    }

    /// Codex in a tab conversation: a command outside its sandbox's safe list asks in the panel, every time (no Allow for
    /// Session), as Claude and the ACP agents do.
    func testCodexInATabConversationAsksBeforeACommand() async throws {
        let folder = try directory()
        let (session, recorder) = session(.codex, access: .browser, directory: folder)
        let turn = AIRequestID("command")
        session.send("fixture:tool", turn: turn)
        try await wait("an approval or the answer") { !recorder.approvals.isEmpty || recorder.finished[turn] != nil }
        let approval = try XCTUnwrap(recorder.approvals.first, "declined without asking: \(String(describing: recorder.finished[turn]))")
        XCTAssertEqual(approval.options.map(\.kind), [.allowOnce, .deny])
        session.answer(approval: approval.id, option: approval.options[0].id)
        try await wait("the answer") { recorder.finished[turn] != nil }
        guard case .text(let text)? = recorder.finished[turn] else { return XCTFail("\(String(describing: recorder.finished[turn]))") }
        XCTAssertTrue(text.hasSuffix("Done."), text)
        await session.close()
    }

    /// An ACP agent continuing its session (`session/load`) first sends the earlier conversation back as updates; they are
    /// not the new reply. gemini-cli sends most of them after its reply to session/load, so a folder conversation (no mode
    /// to set) would otherwise send the message while the replay is still coming.
    func testAResumedACPSessionsReplayIsNotPartOfTheReply() async throws {
        for access in [AgentAccess.tools, .browser] {
            let folder = try directory()
            let (session, recorder) = session(.gemini, access: access, directory: folder, resume: "fixture-acp-session")
            let turn = AIRequestID("after-resume")
            session.send("hello again", turn: turn)
            try await wait("\(access): the answer") { recorder.finished[turn] != nil }
            XCTAssertEqual(recorder.finished[turn], .text("Fixture answer to: hello again"), "\(access)")
            XCTAssertTrue(recorder.steps.isEmpty, "\(access): \(recorder.steps)")
            await session.close()
        }
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

    /// The agent said its model has no quota left and to switch model; the person picked another in the Max pane through
    /// the panel's Agent…: the next message goes to that model, in the same conversation (2026-11-07, a real launch:
    /// it went to the old model again and failed the same way).
    func testAModelPickedDuringAConversationTakesTheNextMessage() async throws {
        let folder = try directory(), log = folder.appendingPathComponent("calls.jsonl")
        let variables = ["BRK_CONTROL_SOCKET": folder.appendingPathComponent("unused.sock").path, "BRK_AI_FIXTURE_EXECUTABLE": fixture.path,
                         "BRK_AI_FIXTURE_PROTOCOL": "1", "BRK_AI_FIXTURE_LOG": log.path]
        for (name, value) in variables { setenv(name, value, 1) }
        defer { for name in variables.keys { unsetenv(name) } }
        var events: [SystemEvent] = []
        let services = AIServices(engine: StubEngine(), send: { events.append($0) })
        func max(_ model: String?) throws -> MaxSnapshot {
            var snapshot = try JSONDecoder().decode(MaxSnapshot.self, from: Data(#"{"settings":{"provider":"claude","renamePinnedTabs":false,"tidyTabs":false},"detected":["claude"],"active":"claude","agents":[],"askProvider":"Claude"}"#.utf8))
            if let model { snapshot.settings.agentOptions = [.claude: AIAgentOptions(model: model)] }
            return snapshot
        }
        let work = try directory(), id = AIRequestID("conversation")
        services.openConversation(id, folder: work.path, choice: .claude, max: try max(nil))
        let first = AIRequestID("first"), second = AIRequestID("second")
        services.turn(conversation: id, turn: first, task: .ask("hello"), max: try max(nil))
        try await wait("the first answer") { events.contains { if case .aiResult(first, _) = $0 { true } else { false } } }
        services.turn(conversation: id, turn: second, task: .ask("again"), max: try max("fixture-haiku"))
        try await wait("the second answer") { events.contains { if case .aiResult(second, _) = $0 { true } else { false } } }
        XCTAssertTrue(events.contains(.aiConversation(id, .notice(AgentCopy.modelChanged))), "the panel says the model changed")
        let calls = entries(log).filter { $0["prompt"] != nil }
        let argv = try XCTUnwrap(calls.last?["argv"] as? [String])
        XCTAssertEqual(zip(argv, argv.dropFirst()).first { $0.0 == "--model" }?.1, "fixture-haiku", "\(argv)")
        XCTAssertTrue(argv.contains("--resume"), "a session with tools on goes on where it was: \(argv)")
        XCTAssertNotEqual(calls.first?["pid"] as? Int32, calls.last?["pid"] as? Int32, "a new process for the new model")
        services.cancelAll()
    }

    /// A tab conversation works in a temporary folder of Brk's. A model picked between messages starts a new process in
    /// that folder; the old session's close must leave it to the new one.
    func testAModelPickedDuringATabConversationKeepsItsFolder() async throws {
        let folder = try directory(), log = folder.appendingPathComponent("calls.jsonl")
        let variables = ["BRK_CONTROL_SOCKET": folder.appendingPathComponent("unused.sock").path, "BRK_AI_FIXTURE_EXECUTABLE": fixture.path,
                         "BRK_AI_FIXTURE_PROTOCOL": "1", "BRK_AI_FIXTURE_LOG": log.path]
        for (name, value) in variables { setenv(name, value, 1) }
        defer { for name in variables.keys { unsetenv(name) } }
        var events: [SystemEvent] = []
        let services = AIServices(engine: StubEngine(), send: { events.append($0) })
        defer { services.cancelAll() }
        func max(_ model: String?) throws -> MaxSnapshot {
            var snapshot = try JSONDecoder().decode(MaxSnapshot.self, from: Data(#"{"settings":{"provider":"claude","renamePinnedTabs":false,"tidyTabs":false},"detected":["claude"],"active":"claude","agents":[],"askProvider":"Claude"}"#.utf8))
            if let model { snapshot.settings.agentOptions = [.claude: AIAgentOptions(model: model)] }
            return snapshot
        }
        let id = AIRequestID("conversation"), second = AIRequestID("second")
        services.openConversation(id, folder: nil, choice: .claude, max: try max(nil), tabs: WindowID("window"))
        services.answer(id, task: .ask("hello"), choice: .claude, max: try max(nil))
        try await wait("the first answer") { events.contains { if case .aiResult(id, _) = $0 { true } else { false } } }
        services.turn(conversation: id, turn: second, task: .ask("again"), max: try max("fixture-haiku"))
        try await wait("the second answer") { events.contains { if case .aiResult(second, _) = $0 { true } else { false } } }
        let calls = entries(log).filter { $0["prompt"] != nil }
        let first = try XCTUnwrap(calls.first?["pid"] as? Int32), work = try XCTUnwrap(calls.last?["cwd"] as? String)
        XCTAssertNotEqual(first, calls.last?["pid"] as? Int32, "a new process for the new model")
        XCTAssertEqual(calls.first?["cwd"] as? String, work, "in the same folder")
        try await wait("the first process gone") { kill(first, 0) == -1 }
        // The old session's close runs once its process has exited.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(FileManager.default.fileExists(atPath: work), "the new process's folder was deleted")
    }

    /// A closed session is waited for at quit while it closes, and forgotten once it has.
    func testAClosedConversationIsForgottenOnceItHasClosed() async throws {
        let folder = try directory()
        let variables = ["BRK_CONTROL_SOCKET": folder.appendingPathComponent("unused.sock").path, "BRK_AI_FIXTURE_EXECUTABLE": fixture.path, "BRK_AI_FIXTURE_PROTOCOL": "1"]
        for (name, value) in variables { setenv(name, value, 1) }
        defer { for name in variables.keys { unsetenv(name) } }
        let services = AIServices(engine: StubEngine(), send: { _ in })
        defer { services.cancelAll() }
        let max = try JSONDecoder().decode(MaxSnapshot.self, from: Data(#"{"settings":{"provider":"claude","renamePinnedTabs":false,"tidyTabs":false},"detected":["claude"],"active":"claude","agents":[],"askProvider":"Claude"}"#.utf8))
        for n in 0..<3 {
            let id = AIRequestID("conversation-\(n)")
            services.openConversation(id, folder: folder.path, choice: .claude, max: max)
            services.closeConversation(id)
        }
        XCTAssertFalse(services.closing.isEmpty, "quit waits for the closes")
        try await wait("the closes forgotten", seconds: 5) { services.closing.isEmpty }
    }

    func testTheLoginShellsPathIsRead() async throws {
        let folder = try directory()
        let shell = folder.appendingPathComponent("fake-shell")
        try Data("#!/bin/sh\necho 'noise from a startup file'\nprintf '%s\\n' '__BRK_PATH_START__'\necho /from/the/login/shell:/usr/bin\nprintf '%s\\n' '__BRK_PATH_END__'\n".utf8).write(to: shell)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        await AgentEnvironment.loadShellPath(shell: shell.path)
        XCTAssertEqual(AgentEnvironment.searchPath(environment: [:]).first, "/from/the/login/shell")
    }
}
