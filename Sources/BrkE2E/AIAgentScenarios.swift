import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// The provider layer against Tests/Fixtures/ai-provider speaking each agent's real session protocol (the harness sets
/// BRK_AI_FIXTURE_PROTOCOL for "AIAgent…" ids). Keys and clicks go through the window server, the way a user's do.
enum AIAgentScenarios {
    static let all: [Scenario] = [AIProviderChoice.claude, .codex, .gemini, .cursor, .opencode].flatMap { choice -> [Scenario] in
        let name = choice.rawValue
        return [
            Scenario("AIAgentChat-\(name)", "\(name): streaming, follow-up in one process, read-only flags, Stop ends what the turn started", cefOnly: "native panel") { try chat($0, choice) },
            Scenario("AIAgentTools-\(name)", "\(name): a folder session asks before a tool runs; Deny writes nothing, Allow writes the file", cefOnly: "native panel") { try tools($0, choice) },
        ]
    } + [
        Scenario("AIAgentForcedStop", "a turn that ignores the agent's own stop is ended by Brk, whole tree; the next message starts a new process", cefOnly: "native panel", forcedStop),
        Scenario("AIAgentSettings", "the Max pane's Local AI card, always there under Enable Max, lists what the agent reports; the choice reaches the next session", cefOnly: "native settings", settings),
        Scenario("AIAgentQuit", "quit ends a session with tools on and the command it started", cefOnly: "native shutdown", quit),
    ]

    private static func prepare(_ app: AppUnderTest, _ choice: AIProviderChoice) throws {
        for feature in AIFeature.allCases { try app.dispatch(.settings(.max(.feature(feature, true)))) }
        try app.dispatch(.settings(.max(.provider(choice))))
    }

    private static func calls(_ app: AppUnderTest) -> [[String: Any]] {
        let data = (try? String(contentsOf: app.dataDirectory.appendingPathComponent("ai-fixture.jsonl"), encoding: .utf8)) ?? ""
        return data.split(whereSeparator: \.isNewline).compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }
    private static func prompts(_ app: AppUnderTest) -> [[String: Any]] { calls(app).filter { $0["prompt"] != nil } }

    private static func screen(_ app: AppUnderTest, _ view: ViewID) throws -> CGPoint {
        let facts = try app.native()
        let frame = try visible(facts, view).frame
        // The window's frame has its origin at the screen's bottom left; a mouse event's point at the top left.
        let top = CGDisplayBounds(CGMainDisplayID()).height - facts.windowFrame.maxY
        return CGPoint(x: facts.windowFrame.minX + frame.midX, y: top + frame.midY)
    }

    /// A real click on a control in the panel, after checking this Brk's window is what is under the pointer.
    private static func click(_ app: AppUnderTest, _ view: ViewID) throws {
        try PhysicalPointer.click(app, at: try screen(app, view), window: app.window!)
    }

    private static let codes: [Character: (CGKeyCode, Bool)] = {
        var map: [Character: (CGKeyCode, Bool)] = [" ": (49, false), ":": (41, true), "-": (27, false), ".": (47, false), "/": (44, false), "?": (44, true)]
        for (letter, code) in zip("asdfhgzxcvbqwerytuiopnmljk", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 32, 34, 31, 35, 45, 46, 37, 38, 40] as [CGKeyCode]) { map[letter] = (code, false) }
        for (digit, code) in zip("1234567890", [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] as [CGKeyCode]) { map[digit] = (code, false) }
        return map
    }()

    /// Real key codes at the window server, what a keyboard sends: a click into the input first, Return last.
    private static func typeIntoInput(_ app: AppUnderTest, _ text: String) throws {
        try click(app, .aiControl("input"))
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            event.flags = flags; event.post(tap: .cghidEventTap); usleep(15_000)
        }
        for character in text {
            guard let (code, shifted) = codes[character] else { throw Check(description: "no key for \(character)") }
            if shifted { post(56, true, .maskShift) }
            post(code, true, shifted ? .maskShift : []); post(code, false, shifted ? .maskShift : [])
            if shifted { post(56, false, []) }
        }
        post(36, true, []); post(36, false, [])
    }

    private static func waitAnswer(_ app: AppUnderTest, contains expected: String, timeout: Double = 20) throws {
        try app.waitUntil("the answer contains \(expected)", timeout: timeout) {
            try app.view().ai?.busy == false && app.view().ai?.text.contains(expected) == true
        }
    }

    private static func gone(_ pid: Int32) -> Bool { kill(pid, 0) == -1 && errno == ESRCH }

    private static func childFile(_ app: AppUnderTest) -> URL { app.dataDirectory.appendingPathComponent("ai-fixture-child") }

    private static func chat(_ app: AppUnderTest, _ choice: AIProviderChoice) throws {
        try prepare(app, choice)
        try app.dispatch(.assist(.ask("fixture:stream")))
        try app.waitUntil("text before the turn ended", timeout: 15) { try app.view().ai?.busy == true && app.view().ai?.text == "first\n" }
        _ = try app.screenshot("AIAgentChat-\(choice.rawValue)-stream")
        try waitAnswer(app, contains: "second")
        let heading = try app.view().ai?.conversation
        try expect(heading?.agent == choice.kind && heading?.folder == nil, "the panel names \(String(describing: heading?.agent)), folder \(String(describing: heading?.folder))")
        // A question's conversation has Brk's tab tools: never a flag that skips approval, the user's allow rules,
        // hooks and other MCP servers overridden, the agent's own tools asking every time.
        let first = try XCTUnwrapValue(prompts(app).first)
        let argv = first["argv"] as? [String] ?? []
        for bad in ["--dangerously-skip-permissions", "--allow-dangerously-skip-permissions", "bypassPermissions", "--yolo", "-y", "--force"] { try expect(!argv.contains(bad), "started with \(bad): \(argv)") }
        switch choice {
        case .claude:
            try expect(argv.contains("--strict-mcp-config") && argv.contains("--mcp-config") && argv.contains("--permission-prompt-tool") && argv.contains { $0.contains("\"disableAllHooks\":true") }, "claude browser arguments: \(argv)")
        case .codex: try expect(argv.contains { $0.hasPrefix("mcp_servers={brk=") } && argv.contains("web_search=\"disabled\"") && argv.contains("features.apps=false"), "codex browser arguments: \(argv)")
        case .gemini: try expect(argv.contains("plan") && argv.contains("--skip-trust") && argv.contains("brk"), "gemini browser arguments: \(argv)")
        default: break
        }
        if [AIProviderChoice.cursor, .opencode].contains(choice) {
            let wanted = choice == .cursor ? "ask" : "plan"
            try expect(calls(app).contains { ($0["params"] as? [String: Any])?["modeId"] as? String == wanted }, "\(choice) did not ask for its \(wanted) mode")
        }
        // A tool of the agent's own asks, with no "for this session"; denied, nothing is written.
        try typeIntoInput(app, "fixture:tool")
        try app.waitUntil("an approval or the end of the turn", timeout: 15) {
            let ai = try app.view().ai
            return ai?.busy == false || ai?.conversation?.items.contains { if case .approval(let a) = $0 { a.answer == nil } else { false } } == true
        }
        if let approval = try app.view().ai?.conversation?.items.lazy.compactMap({ item -> AIAgentApproval? in if case .approval(let a) = item, a.answer == nil { a } else { nil } }).first {
            try expect(!approval.options.contains { $0.kind == .allowSession }, "a browser session offered \(approval.options)")
            let deny = try XCTUnwrapValue(approval.options.first { $0.kind == .deny })
            try app.dispatch(.assist(.approve(approval: approval.id, option: deny.id)))
            try app.waitUntil("the turn ended after Deny", timeout: 15) { try app.view().ai?.busy == false }
        }
        try expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: first["cwd"] as? String ?? "/nonexistent").appendingPathComponent("written.txt").path), "a denied tool wrote a file")
        // A follow-up, typed: the same process.
        try typeIntoInput(app, "second question")
        try waitAnswer(app, contains: "second question")
        let all = prompts(app)
        try expect(all.count == 3 && Set(all.compactMap { $0["pid"] as? Int32 }).count == 1, "turns ran in \(Set(all.compactMap { $0["pid"] as? Int32 })) processes")
        // Stop: the process stays, the command the turn started does not.
        try typeIntoInput(app, "fixture:slowstop")
        try app.waitUntil("the turn's command runs", timeout: 15) { FileManager.default.fileExists(atPath: childFile(app).path) }
        let child = try XCTUnwrapValue(Int32(String(contentsOf: childFile(app), encoding: .utf8)))
        _ = try app.screenshot("AIAgentChat-\(choice.rawValue)-running")
        try click(app, .aiControl("stop"))
        try app.waitUntil("Stop ends the command", timeout: 10) { gone(child) }
        try expect(try app.view().ai?.conversation?.items.contains(.notice("Stopped.")) == true, "no word that it stopped")
        try typeIntoInput(app, "after the stop")
        try waitAnswer(app, contains: "after the stop")
        try FileManager.default.removeItem(at: childFile(app))
        _ = try app.screenshot("AIAgentChat-\(choice.rawValue)-after")
        try app.dispatch(.assist(.dismiss))
        let pid = try XCTUnwrapValue(prompts(app).last?["pid"] as? Int32)
        try app.waitUntil("closing the panel ends the process", timeout: 8) { gone(pid) }
    }

    private static func tools(_ app: AppUnderTest, _ choice: AIProviderChoice) throws {
        try prepare(app, choice)
        let folder = app.dataDirectory.appendingPathComponent("ai-work", isDirectory: true)
        try app.dispatch(.assist(.ask("hello")))
        try waitAnswer(app, contains: "hello")
        try expect(!FileManager.default.fileExists(atPath: folder.path), "a folder exists before the user chose one")
        // Only the explicit button opens a session with tools on; the panel answers with the fixture's folder.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try click(app, .aiControl("folder"))
        try app.waitUntil("a session in the folder", timeout: 15) {
            let conversation = try app.view().ai?.conversation
            return conversation?.folder == folder.path && conversation?.agent == choice.kind
        }
        _ = try app.screenshot("AIAgentTools-\(choice.rawValue)-open")
        // Deny: nothing written, the turn goes on without it.
        try typeIntoInput(app, "fixture:tool")
        try app.waitUntil("the approval shows", timeout: 15) { try app.native().actual[ViewID.aiControl("approval-deny").identifier]?.hidden == false }
        _ = try app.screenshot("AIAgentTools-\(choice.rawValue)-approval")
        let file = folder.appendingPathComponent("written.txt")
        try expect(!FileManager.default.fileExists(atPath: file.path), "the tool ran before the answer")
        try click(app, .aiControl("approval-deny"))
        try waitAnswer(app, contains: "You said no")
        try expect(!FileManager.default.fileExists(atPath: file.path), "Deny wrote the file")
        // Allow: written.
        try typeIntoInput(app, "fixture:tool")
        try app.waitUntil("the approval shows again", timeout: 15) { try app.native().actual[ViewID.aiControl("approval-allowOnce").identifier]?.hidden == false }
        try click(app, .aiControl("approval-allowOnce"))
        try waitAnswer(app, contains: "Done")
        try expect(FileManager.default.fileExists(atPath: file.path), "Allow did not write the file")
        let conversation = try app.view().ai?.conversation
        let steps = conversation?.items.compactMap { item -> AIAgentStep? in if case .step(let step) = item { step } else { nil } } ?? []
        try expect(steps.contains { $0.state == .done }, "no finished step in \(steps)")
        _ = try app.screenshot("AIAgentTools-\(choice.rawValue)-done")
        // Started with approvals on, no flag that skips them.
        let argv = try XCTUnwrapValue(prompts(app).last?["argv"] as? [String])
        for bad in ["--dangerously-skip-permissions", "--allow-dangerously-skip-permissions", "bypassPermissions", "--yolo", "-y", "--force"] { try expect(!argv.contains(bad), "started with \(bad): \(argv)") }
        if choice == .claude { try expect(argv.contains("--permission-prompt-tool") && argv.contains("default"), "claude tool arguments: \(argv)") }
        if choice == .codex {
            let thread = calls(app).compactMap { $0["thread"] as? [String: Any] }.last
            try expect(thread?["approvalPolicy"] as? String == "untrusted", "codex approval policy: \(String(describing: thread))")
        }
    }

    private static func forcedStop(_ app: AppUnderTest) throws {
        try prepare(app, .claude)
        try app.dispatch(.assist(.ask("fixture:hang")))
        try app.waitUntil("the agent hangs", timeout: 15) { prompts(app).last?["prompt"] as? String == "fixture:hang" }
        let pid = try XCTUnwrapValue(prompts(app).last?["pid"] as? Int32)
        try click(app, .aiControl("stop"))
        try app.waitUntil("Brk ends a process that ignores everything", timeout: 8) { gone(pid) }
        try typeIntoInput(app, "still here")
        try waitAnswer(app, contains: "still here")
        try expect(prompts(app).last?["pid"] as? Int32 != pid, "the next message did not start a new process")
    }

    private static func settings(_ app: AppUnderTest) throws {
        try prepare(app, .claude)
        try app.dispatch(.settings(.openPane(.max)))
        var max: MaxSnapshot?
        try app.waitUntil("the agents answered", timeout: 25) {
            guard case .settings(let settings) = try app.send(.settings) else { return false }
            max = settings.max
            return settings.max.agents.allSatisfy { $0.state == .ready }
        }
        let claude = try XCTUnwrapValue(max?.agents.first { $0.kind == .claude })
        try expect(claude.version == "9.9.9-fixture" && claude.models.map(\.id) == ["fixture-haiku"], "claude reported \(claude)")
        let codex = try XCTUnwrapValue(max?.agents.first { $0.kind == .codex })
        try expect(codex.models.map(\.id) == ["fixture-sol"] && codex.models[0].efforts == ["low", "high"], "codex reported \(codex)")
        let gemini = try XCTUnwrapValue(max?.agents.first { $0.kind == .gemini })
        try expect(gemini.models.map(\.id) == ["fixture-flash", "fixture-pro"], "gemini reported \(gemini)")
        try app.dispatch(.settings(.max(.agentModel(.claude, "fixture-haiku"))))
        try app.dispatch(.settings(.max(.agentEffort(.claude, "high"))))
        try app.flush()
        try app.dispatch(.assist(.ask("which model")))
        try waitAnswer(app, contains: "which model")
        let argv = try XCTUnwrapValue(prompts(app).last?["argv"] as? [String])
        try expect(zip(argv, argv.dropFirst()).contains { $0 == "--model" && $1 == "fixture-haiku" } && zip(argv, argv.dropFirst()).contains { $0 == "--effort" && $1 == "high" }, "the choice did not reach the agent: \(argv)")
        let shownModel = try app.view().ai?.conversation?.model
        try expect(shownModel == "Fixture Haiku", "the panel names \(String(describing: shownModel))")
        // The pane, with the card under Enable Max, for the eye.
        app.sleep(0.5)
        var settingsWindow: AppWindowFact?
        try app.waitUntil("the settings window") { settingsWindow = try app.native().appWindows.first { $0.className == "NSWindow" && $0.isVisible }; return settingsWindow != nil }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(settingsWindow!.number), app.shotsDirectory.appendingPathComponent("AIAgentSettings-card.png").path]
        try capture.run(); capture.waitUntilExit()
    }

    private static func quit(_ app: AppUnderTest) throws {
        try prepare(app, .claude)
        let folder = app.dataDirectory.appendingPathComponent("ai-work", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try app.dispatch(.assist(.chooseFolder))
        try app.waitUntil("a session in the folder", timeout: 15) { try app.view().ai?.conversation?.agent == .claude }
        try app.dispatch(.assist(.followUp("fixture:slowstop")))
        try app.waitUntil("the turn's command runs", timeout: 15) { FileManager.default.fileExists(atPath: childFile(app).path) }
        let child = try XCTUnwrapValue(Int32(String(contentsOf: childFile(app), encoding: .utf8)))
        let agent = try XCTUnwrapValue(prompts(app).last?["pid"] as? Int32)
        _ = try app.quit()
        for pid in [agent, child] { try expect(gone(pid), "quit left \(pid) alive") }
    }
}

func XCTUnwrapValue<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) throws -> T {
    guard let value else { throw Check(description: "\(file):\(line) expected a value") }
    return value
}
