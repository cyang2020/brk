import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

/// The basic layer's channel: schemas every route accepts, read-only CLI runs, the APIs' request and response shapes
/// (built from the services' references, 2026-11-08; no real key was used), decisions, keys and their read side.
@MainActor
final class AIBasicChannelTests: XCTestCase {
    private var fixture: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ai-provider") }
    private func object(_ json: String) -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:] }

    // MARK: Schemas

    func testEverySchemaIsClosedFullyRequiredAndFreeOfLimits() {
        let prompts: [StructuredPrompt] = [
            AIBasicPrompts.tabNames([AITab(id: ItemID("t"), title: "T", url: URL(string: "https://a.example")!)]),
            AIBasicPrompts.tabTitle(title: "T", url: URL(string: "https://a.example")!),
            AIBasicPrompts.folderName([]), AIBasicPrompts.tidy([]), AIBasicPrompts.groupNames([]),
            AIBasicPrompts.downloadName("a.pdf"), AIBasicPrompts.instant("q"), AIBasicPrompts.translate([], target: "English"),
            AIBasicPrompts.translateText("x", target: "German"),
            AIBasicPrompts.decision(DecisionRequest(state: .string("s"), questions: ["g": .choice("?", options: [DecisionOption("A")], none: "none"), "y": .noul("?"), "s": .score("?", levels: ["lo", "hi"])])),
        ]
        func check(_ schema: [String: Any], _ path: String) {
            for banned in ["minimum", "maximum", "minLength", "maxLength", "minItems", "maxItems", "pattern"] { XCTAssertNil(schema[banned], "\(path) has \(banned)") }
            if schema["type"] as? String == "object" {
                XCTAssertEqual(schema["additionalProperties"] as? Bool, false, path)
                let properties = schema["properties"] as? [String: Any] ?? [:]
                XCTAssertEqual(Set(schema["required"] as? [String] ?? []), Set(properties.keys), "\(path): every property required (OpenAI strict)")
                for (name, value) in properties { check(value as? [String: Any] ?? [:], path + "." + name) }
            }
            if let items = schema["items"] as? [String: Any] { check(items, path + "[]") }
        }
        for prompt in prompts {
            check(prompt.schema.object, prompt.name)
            XCTAssertEqual(prompt.schema.text, prompt.schema.text, "the same bytes each time")
            XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(prompt.input.utf8)), "\(prompt.name): the input is JSON Brk built")
        }
        let decision = prompts.last!.schema.object
        XCTAssertEqual(((decision["properties"] as? [String: Any])?["g"] as? [String: Any])?["enum"] as? [String], ["A", DecisionQuestion.noneName])
        XCTAssertTrue(AIBasicPrompts.translateText("x", target: "German").input.contains("German"))
    }

    func testTidyLeavesALoneTabInTodayInsteadOfAGroupOfOne() throws {
        let answer = StructuredAnswer(json: Data(#"{"groups":[{"name":"Recipes","tabs":["a","b"]},{"name":"Other","tabs":["c"]},{"name":"Twice","tabs":["d","d"]}]}"#.utf8), usage: AIUsageCount())
        let plan = try AIBasicPrompts.groups(answer)
        XCTAssertEqual(plan.map(\.folder), ["Recipes"], "a group needs two different tabs")
        XCTAssertTrue(AIBasicPrompts.tidy([]).instructions.contains("never make a catch-all folder"))
    }

    // MARK: Subscriptions

    func testTheClaudeRunIsReadOnlyAndAsksForTheSchema() {
        let arguments = ClaudeStructured.arguments(model: "claude-haiku-5-5", effort: "low", instructions: "Do it.", schema: #"{"type":"object"}"#)
        for flag in ["--tools", "--strict-mcp-config", "--setting-sources", "--no-session-persistence", "--disable-slash-commands", "--json-schema", "--system-prompt"] {
            XCTAssertTrue(arguments.contains(flag), flag)
        }
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--tools")! + 1], "")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--setting-sources")! + 1], "")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--permission-mode")! + 1], "dontAsk")
        XCTAssertFalse(arguments.contains("--permission-prompt-tool"))
        XCTAssertFalse(arguments.contains { $0.contains("dangerously") || $0.contains("bypass") })
        let codex = CodexAppServer.arguments
        for setting in ["features.shell_tool=false", "mcp_servers={}", "sandbox_mode=\"read-only\"", "approval_policy=\"never\"", "features.hooks=false", "project_doc_max_bytes=0"] {
            XCTAssertTrue(codex.contains(setting), setting)
        }
    }

    func testTheClaudeRunnerAnswersThroughARealProcess() async throws {
        let runner = ClaudeStructured(executable: fixture, model: "claude-haiku-5-5", effort: nil, environment: ProcessInfo.processInfo.environment)
        let tabs = [AITab(id: ItemID("t1"), title: "Swift Concurrency Guide", url: URL(string: "https://docs.example/swift")!)]
        let answer = try await runner.run(AIBasicPrompts.tabNames(tabs))
        XCTAssertEqual(try AIBasicPrompts.tabNames(answer), ["t1": "Named Swift Concurrency"])
        XCTAssertEqual(answer.usage.cachedTokens, 50)
    }

    func testTheCodexServerAnswersSeveralRequestsInOneProcess() async throws {
        let server = CodexAppServer(executable: fixture, environment: ProcessInfo.processInfo.environment)
        defer { server.shutDown() }
        let runner = CodexStructured(executable: fixture, model: "gpt-6-luna", effort: "low", server: server)
        let first = try await runner.run(AIBasicPrompts.folderName([]))
        XCTAssertEqual(try AIBasicPrompts.name(first), "Fixture Folder")
        XCTAssertEqual(first.usage.cachedTokens, 200)
        let second = try await runner.run(AIBasicPrompts.downloadName("scan_0001.pdf"))
        XCTAssertEqual(try AIBasicPrompts.filename(second), "Reading.pdf")
    }

    // MARK: API keys

    func testTheAnthropicRequestAndAnswerFollowTheMessagesAPI() throws {
        let prompt = AIBasicPrompts.tabTitle(title: "T", url: URL(string: "https://a.example")!)
        let body = AnthropicStructured.body(prompt, model: "claude-haiku-5-5", effort: "low")
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual((output["format"] as? [String: Any])?["type"] as? String, "json_schema")
        XCTAssertEqual(output["effort"] as? String, "low")
        XCTAssertEqual(body["system"] as? String, prompt.instructions)
        XCTAssertNil(body["temperature"], "API version 2026-10-21 rejects sampling parameters")
        let request = AIEndpoints.request(.anthropic, "messages", key: "sk-ant-test", body: body)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")

        let answer = try AnthropicStructured.answer(object(#"{"stop_reason":"end_turn","content":[{"type":"text","text":"{\"title\":\"Tidy\"}"}],"usage":{"input_tokens":100,"cache_read_input_tokens":1000,"cache_creation_input_tokens":0,"output_tokens":10}}"#), model: "claude-haiku-5-5")
        XCTAssertEqual(try AIBasicPrompts.title(answer), "Tidy")
        XCTAssertEqual(answer.usage.inputTokens, 1100)
        XCTAssertEqual(answer.usage.cost ?? 0, (100 * 0.10 + 1000 * 0.01 + 10 * 0.50) / 1_000_000, accuracy: 1e-12)
        XCTAssertThrowsError(try AnthropicStructured.answer(object(#"{"stop_reason":"refusal","content":[]}"#), model: "claude-haiku-5-5"))
        XCTAssertThrowsError(try AnthropicStructured.answer(object(#"{"stop_reason":"max_tokens","content":[{"type":"text","text":"{\"ti"}]}"#), model: "claude-haiku-5-5"))
    }

    func testTheOpenAIRequestAndAnswerFollowTheResponsesAPI() throws {
        let prompt = AIBasicPrompts.instant("weather in Paris")
        let body = OpenAIStructured.body(prompt, model: "gpt-6-luna", effort: "low")
        let format = try XCTUnwrap((body["text"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertEqual(format["name"] as? String, "instant_links")
        XCTAssertEqual(body["store"] as? Bool, false, "page text is not kept by the service")
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertEqual(AIEndpoints.request(.openai, "responses", key: "sk-test", body: body).value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

        let answer = try OpenAIStructured.answer(object(#"{"status":"completed","output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":"{\"urls\":[\"https://weather.example/paris\"]}"}]}],"usage":{"input_tokens":400,"input_tokens_details":{"cached_tokens":300},"output_tokens":30}}"#), model: "gpt-6-luna")
        XCTAssertEqual(try AIBasicPrompts.links(answer), ["https://weather.example/paris"])
        XCTAssertEqual(answer.usage.cachedTokens, 300)
        XCTAssertNotNil(answer.usage.cost)
        XCTAssertThrowsError(try OpenAIStructured.answer(object(#"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"No."}]}]}"#), model: "gpt-6-luna"))
        XCTAssertThrowsError(try OpenAIStructured.answer(object(#"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"}}"#), model: "gpt-6-luna"))
        XCTAssertEqual(AIEndpoints.failure(.openai, status: 401, body: [:]), "The OpenAI API key was refused (401). Check it in Settings → Max.")
    }

    func testJevSpeaksSystemOne() {
        let request = DecisionRequest(state: .string("A new tab"), questions: [
            "group": .choice("Which group?", options: [DecisionOption("Recipes"), DecisionOption("Work", "office")], none: "None fits"),
            "close": .noul("Done with it?", yes: "close it", no: "keep it"),
        ])
        let body = JevDecisions.body(request)
        XCTAssertEqual(body["model"] as? String, "jev-latest")
        XCTAssertEqual(body["state"] as? String, "A new tab")
        let group = (body["questions"] as? [String: Any])?["group"] as? [String: Any]
        XCTAssertEqual(group?["type"] as? String, "choice")
        XCTAssertEqual(Set(((group?["criteria"] as? [String: Any]) ?? [:]).keys), ["Recipes", "Work", DecisionQuestion.noneName])
        XCTAssertEqual(((body["questions"] as? [String: Any])?["close"] as? [String: Any])?["criteria"] as? [String: String], ["true": "close it", "false": "keep it"])
        XCTAssertEqual(AIEndpoints.request(.typesafe, "systemone", key: "ts-key").url?.absoluteString, "https://api.typesafe.ai/v1/systemone")
        let answers = JevDecisions.answers(object(#"{"model":"jev-1.13.0","answers":{"group":{"type":"choice","choice":"Work","confidence":0.7,"probabilities":{"Recipes":0.2,"Work":0.75,"none_of_the_above":0.05}},"close":{"type":"noul","noul":0.12}},"usage":{"input_tokens":80,"output_tokens":3}}"#), request: request)
        XCTAssertEqual(answers.backend, "jev-1.13.0")
        XCTAssertEqual(answers["group"]?.probability, 0.75)
        XCTAssertEqual(DecisionBand(answers["group"]?.probability), .suggest)
        XCTAssertEqual(answers["close"], .noul(false, probability: 0.12))
    }

    // MARK: Keys

    func testKeysLiveOnlyInTheStoreAndTheReadSideGivesThemOnlyWhenChosen() {
        let store = AIKeyStore(memoryOnly: true)
        var reported: [AIService: AIKeyStatus] = [:]
        store.onChange = { reported = $0 }
        XCTAssertFalse(store.has(.anthropic))
        XCTAssertNil(store.store(.anthropic, "  sk-ant-secret \n"))
        XCTAssertEqual(store.key(.anthropic), "sk-ant-secret")
        XCTAssertEqual(reported[.anthropic], AIKeyStatus(stored: true))
        XCTAssertEqual(store.stored, [.anthropic])
        var settings = MaxSettings.default
        XCTAssertEqual(AIAccounts.credential(for: .anthropic, settings: settings, keys: store), .subscription, "the subscription is the default")
        settings.accounts = [.anthropic: .apiKey]
        XCTAssertEqual(AIAccounts.credential(for: .anthropic, settings: settings, keys: store), .apiKey("sk-ant-secret"))
        settings.accounts = [.openai: .apiKey]
        XCTAssertEqual(AIAccounts.credential(for: .openai, settings: settings, keys: store), .subscription, "a key chosen but not saved")
        XCTAssertEqual(AICredential.variable(.anthropic), "ANTHROPIC_API_KEY")
        store.store(.anthropic, nil)
        XCTAssertFalse(store.has(.anthropic))
        XCTAssertEqual(reported[.anthropic], AIKeyStatus(stored: false))
        XCTAssertFalse(reported.description.contains("secret"), "a status never carries the key")
    }

    /// Test runs for up to a minute and Save stays clickable: a result that comes back after another key was saved is
    /// about the old key, and the new one shows none.
    func testAKeyTestStillRunningSaysNothingAboutAKeySavedAfterIt() async throws {
        URLProtocol.registerClass(HeldModelList.self)
        defer { URLProtocol.unregisterClass(HeldModelList.self) }
        let store = AIKeyStore(memoryOnly: true)
        var reported: [AIService: AIKeyStatus] = [:]
        store.onChange = { reported = $0 }
        store.store(.anthropic, "sk-ant-first")
        store.test(.anthropic)
        XCTAssertEqual(reported[.anthropic], AIKeyStatus(stored: true, test: .testing))
        let asked = await Task.detached { HeldModelList.requested() }.value
        XCTAssertTrue(asked, "the test asked the service")
        store.store(.anthropic, "sk-ant-second")
        XCTAssertEqual(reported[.anthropic], AIKeyStatus(stored: true))
        HeldModelList.release.signal()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(reported[.anthropic], AIKeyStatus(stored: true), "the first key's result shows as the second key's")
    }
}

/// Anthropic's model list, answered once the test lets it go. No request leaves the Mac.
private final class HeldModelList: URLProtocol, @unchecked Sendable {
    static let arrived = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    /// The request reached the service, within ten seconds.
    static func requested() -> Bool { arrived.wait(timeout: .now() + 10) == .success }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.anthropic.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.arrived.signal()
        _ = Self.release.wait(timeout: .now() + 10)
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"data":[{"id":"claude-first"}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
