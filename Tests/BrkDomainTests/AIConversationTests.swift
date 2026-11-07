import BrkBase
@testable import BrkDomain
import XCTest

/// The Max panel's conversation in the reducer: which effects leave, what the panel shows.
final class AIConversationTests: XCTestCase {
    private func enabled() -> Driver {
        let d = Driver()
        for feature in AIFeature.allCases { d.user(.settings(.max(.feature(feature, true)))) }
        d.system(.aiProvidersDetected([.claude, .codex]))
        return d
    }
    private func firstTurn(_ t: Transition) throws -> AIRequestID {
        for case .ai(let id, _, _) in t.effects { return id }
        throw XCTSkip("no AI request in \(t.effects)")
    }
    private func turn(_ t: Transition) throws -> (conversation: AIRequestID, turn: AIRequestID) {
        for case .aiTurn(let conversation, let turn, _) in t.effects { return (conversation, turn) }
        throw XCTSkip("no turn in \(t.effects)")
    }

    func testAskOpensAReadOnlySessionAndItsFirstTurnIsTheRequest() throws {
        let d = enabled()
        let t = d.user(.assist(.ask("Why?")))
        let id = try firstTurn(t)
        XCTAssertTrue(t.effects.contains(.aiOpenConversation(id, folder: nil, choice: .auto)), "\(t.effects)")
        XCTAssertLessThan(try XCTUnwrap(t.effects.firstIndex(of: .aiOpenConversation(id, folder: nil, choice: .auto))), try XCTUnwrap(t.effects.firstIndex(of: .ai(id, .ask("Why?"), choice: .auto))), "the session is ready for its first turn")
        XCTAssertEqual(d.view.ai?.conversation?.id, id)
        XCTAssertNil(d.view.ai?.conversation?.folder)
        XCTAssertEqual(d.view.ai?.title, "Why?")
    }

    func testFollowUpIsATurnInTheSameSessionAndWaitsItsTurn() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("Why?"))))
        d.system(.aiPartial(id, "Because"))
        XCTAssertEqual(d.view.ai?.conversation?.items, [.assistant("Because")])
        // One turn at a time: the panel offers Stop while one runs.
        XCTAssertTrue(d.user(.assist(.followUp("And then?"))).effects.isEmpty)
        d.system(.aiResult(id, .text("Because of this.")))
        XCTAssertEqual(d.view.ai?.conversation?.items, [.assistant("Because of this.")])
        XCTAssertEqual(d.view.ai?.busy, false)
        let next = try turn(d.user(.assist(.followUp("And then?"))))
        XCTAssertEqual(next.conversation, id)
        XCTAssertEqual(d.view.ai?.busy, true)
        d.system(.aiPartial(next.turn, "After"))
        d.system(.aiResult(next.turn, .text("After that.")))
        XCTAssertEqual(d.view.ai?.conversation?.items, [.assistant("Because of this."), .user("And then?"), .assistant("After that.")])
        XCTAssertEqual(d.view.ai?.text, "After that.")
    }

    func testAStopKeepsWhatWasWrittenAndTheSession() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("Why?"))))
        d.system(.aiPartial(id, "Because"))
        let t = d.user(.assist(.stop))
        XCTAssertTrue(t.effects.contains(.aiCancel(id)))
        XCTAssertFalse(t.effects.contains(.aiCloseConversation(id)), "Stop ends the turn, not the conversation")
        XCTAssertEqual(d.view.ai?.conversation?.items, [.assistant("Because"), .notice("Stopped.")])
        XCTAssertEqual(d.view.ai?.busy, false)
        XCTAssertNoThrow(try turn(d.user(.assist(.followUp("Go on")))))
    }

    func testClosingThePanelEndsTheSession() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("Why?"))))
        d.system(.aiResult(id, .text("Because.")))
        XCTAssertTrue(d.user(.assist(.dismiss)).effects.contains(.aiCloseConversation(id)))
        XCTAssertNil(d.view.ai)
    }

    func testANewQuestionReplacesTheConversation() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("Why?"))))
        d.system(.aiResult(id, .text("Because.")))
        let t = d.user(.assist(.ask("What?")))
        XCTAssertTrue(t.effects.contains(.aiCloseConversation(id)), "\(t.effects)")
    }

    func testAnotherAgentEndsTheConversationAndKeepsItsText() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("Why?"))))
        d.system(.aiResult(id, .text("Because.")))
        XCTAssertTrue(d.user(.settings(.max(.provider(.codex)))).effects.contains(.aiCloseConversation(id)))
        XCTAssertEqual(d.view.ai?.conversation?.ended, true)
        XCTAssertTrue(d.user(.assist(.followUp("More"))).effects.isEmpty)
    }

    func testStepsAndTextKeepTheirOrder() throws {
        let d = enabled()
        let id = try firstTurn(d.user(.assist(.ask("Do it"))))
        d.system(.aiPartial(id, "First."))
        d.system(.aiConversation(id, .step(AIAgentStep(id: "s", title: "Run: ls", state: .running), turn: id)))
        d.system(.aiPartial(id, "First.Then."))
        d.system(.aiConversation(id, .step(AIAgentStep(id: "s", title: "Run: ls", state: .done), turn: id)))
        XCTAssertEqual(d.view.ai?.conversation?.items, [.assistant("First."), .step(AIAgentStep(id: "s", title: "Run: ls", state: .done)), .assistant("Then.")])
        d.system(.aiResult(id, .text("First.Then. Finished.")))
        XCTAssertEqual(d.view.ai?.conversation?.items.last, .assistant("Then. Finished."))
    }

    func testAFolderSessionStartsOnlyFromTheUsersChoice() throws {
        let d = enabled()
        XCTAssertTrue(d.user(.assist(.chooseFolder)).effects.contains(.aiChooseFolder(d.window)))
        XCTAssertNil(d.view.ai, "asking for a folder starts nothing")
        // The panel was cancelled: nothing.
        assertUnchanged(d.state, d.system(.aiFolderChosen(d.window, nil)))
        let t = d.system(.aiFolderChosen(d.window, "/tmp/project"))
        let open = try XCTUnwrap(t.effects.lazy.compactMap { effect -> (AIRequestID, String?)? in
            if case .aiOpenConversation(let id, let folder, _) = effect { (id, folder) } else { nil }
        }.first)
        XCTAssertEqual(open.1, "/tmp/project")
        XCTAssertEqual(d.view.ai?.conversation?.folder, "/tmp/project")
        XCTAssertEqual(d.view.ai?.busy, false, "it waits for the first message")
        XCTAssertFalse(t.effects.contains { if case .ai = $0 { true } else { false } })
    }

    func testHomeAndTheRootAreRefusedAsWorkingFolders() {
        let d = enabled()
        for folder in [NSHomeDirectory(), NSHomeDirectory() + "/", "/"] {
            let t = d.system(.aiFolderChosen(d.window, folder))
            XCTAssertFalse(t.effects.contains { if case .aiOpenConversation = $0 { true } else { false } }, folder)
            XCTAssertNil(d.view.ai)
        }
        XCTAssertNotNil(AIValidation.workingFolderRefusal("relative/path", home: "/Users/x"))
        XCTAssertNil(AIValidation.workingFolderRefusal("/Users/x/code", home: "/Users/x"))
    }

    func testAFolderSessionHasNoDeadlineButAReadOnlyTurnDoes() throws {
        let d = enabled()
        d.system(.aiFolderChosen(d.window, "/tmp/project"))
        let t = d.user(.assist(.followUp("Build it")))
        XCTAssertFalse(t.effects.contains { if case .aiWatch = $0 { true } else { false } }, "a command the user allowed may take as long as it needs")
        let d2 = enabled()
        let id = try firstTurn(d2.user(.assist(.ask("Why?"))))
        d2.system(.aiResult(id, .text("Because.")))
        XCTAssertTrue(d2.user(.assist(.followUp("More"))).effects.contains { if case .aiWatch = $0 { true } else { false } })
    }

    func testApprovalsGoToTheAgentOnceAndGoWithTheTurn() throws {
        let d = enabled()
        d.system(.aiFolderChosen(d.window, "/tmp/project"))
        let next = try turn(d.user(.assist(.followUp("Write it"))))
        let approval = AIAgentApproval(id: "a", title: "Write x", detail: "", options: [.init(id: "yes", title: "Allow", kind: .allowOnce), .init(id: "no", title: "Deny", kind: .deny)])
        d.system(.aiConversation(next.conversation, .approval(approval, turn: next.turn)))
        // An option the agent did not offer is not an answer.
        XCTAssertTrue(d.user(.assist(.approve(approval: "a", option: "always"))).effects.isEmpty)
        XCTAssertTrue(d.user(.assist(.approve(approval: "a", option: "yes"))).effects.contains(.aiApprove(conversation: next.conversation, approval: "a", option: "yes")))
        XCTAssertTrue(d.user(.assist(.approve(approval: "a", option: "yes"))).effects.isEmpty, "answered once")
        // Unanswered, it goes with the turn.
        let again = AIAgentApproval(id: "b", title: "Write y", detail: "", options: approval.options)
        d.system(.aiConversation(next.conversation, .approval(again, turn: next.turn)))
        d.user(.assist(.stop))
        XCTAssertFalse(d.view.ai!.conversation!.items.contains { if case .approval(let a) = $0 { a.id == "b" } else { false } })
        // A late report about a finished turn changes nothing.
        d.system(.aiConversation(next.conversation, .approval(again, turn: next.turn)))
        XCTAssertFalse(d.view.ai!.conversation!.items.contains { if case .approval(let a) = $0 { a.id == "b" } else { false } })
    }

    func testPrivateWindowsHaveNoAgent() throws {
        let d = enabled()
        d.user(.window(.newIncognito))
        let window = try XCTUnwrap(d.state.doc.windows.first { $0.value.kind == .incognito }?.key)
        XCTAssertFalse(d.user(.assist(.chooseFolder), in: window).effects.contains(.aiChooseFolder(window)))
        XCTAssertFalse(d.system(.aiFolderChosen(window, "/tmp/project")).effects.contains { if case .aiOpenConversation = $0 { true } else { false } })
    }

    func testRepliesWrappedInACodeBlockStillParse() throws {
        XCTAssertEqual(AIReplyCodec.preview("```json\n{\"blocked\":true}\n```")?.blocked, true)
        XCTAssertEqual(AIReplyCodec.nodes("Here it is:\n```json\n[{\"id\":0,\"text\":\"x\"}]\n```")?.first?.text, "x")
        XCTAssertEqual(AIReplyCodec.groups("```\n[{\"folder\":\"a\",\"tabs\":[\"t\"]}]\n```")?.first?.folder, "a")
    }

    func testModelAndEffortAreKeptPerAgent() {
        let d = enabled()
        d.system(.aiAgents([AIAgentStatus(kind: .claude, state: .ready, models: [AIAgentModel(id: "opus", name: "Opus", efforts: ["low", "high"]), AIAgentModel(id: "tiny", name: "Tiny", efforts: ["low"])])]))
        d.user(.settings(.max(.agentModel(.claude, "opus"))))
        d.user(.settings(.max(.agentEffort(.claude, "high"))))
        XCTAssertEqual(d.snapshot.settings.max.settings.agentOptions?[.claude], AIAgentOptions(model: "opus", effort: "high"))
        XCTAssertNil(d.snapshot.settings.max.settings.agentOptions?[.codex])
        // A model that does not offer the effort: the effort goes back to the agent's default.
        d.user(.settings(.max(.agentModel(.claude, "tiny"))))
        XCTAssertEqual(d.snapshot.settings.max.settings.agentOptions?[.claude], AIAgentOptions(model: "tiny", effort: nil))
        d.user(.settings(.max(.agentModel(.claude, nil))))
        XCTAssertNil(d.snapshot.settings.max.settings.agentOptions)
    }

    func testOpeningTheCardAsksTheAgentsAndMaxOnAtLaunchDoesToo() {
        let d = enabled()
        XCTAssertTrue(d.user(.settings(.max(.showAgents(true)))).effects.contains(.aiRefreshAgents))
        XCTAssertTrue(d.snapshot.settings.max.agentCardOpen)
        XCTAssertTrue(d.system(.aiAgentsWanted).effects.contains(.aiRefreshAgents))
        XCTAssertFalse(Driver().system(.aiAgentsWanted).effects.contains(.aiRefreshAgents), "Max off: no agent is started at launch")
    }

    func testAutomaticPassesOverASignedOutAgent() {
        let d = enabled()
        XCTAssertEqual(d.snapshot.settings.max.active, .claude)
        d.system(.aiAgents([AIAgentStatus(kind: .claude, state: .notSignedIn)]))
        XCTAssertEqual(d.snapshot.settings.max.active, .codex)
        XCTAssertEqual(d.snapshot.settings.max.askProvider, "Codex")
    }

    func testOldSettingsFilesStillDecode() throws {
        let old = #"{"provider":"codex","renamePinnedTabs":true,"tidyTabs":false}"#
        let settings = try JSONDecoder().decode(MaxSettings.self, from: Data(old.utf8))
        XCTAssertEqual(settings.provider, .codex)
        XCTAssertNil(settings.agentOptions)
    }
}
