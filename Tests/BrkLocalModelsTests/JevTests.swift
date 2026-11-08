import BrkBase
import Foundation
@testable import BrkLocalModels
import XCTest

final class JevTests: XCTestCase {
    /// The user message must be byte for byte what JevK5's Python writes (json.dumps, ensure_ascii=False, its default
    /// separators): its temperature was fitted on those tokens. Expected text produced by Python's json.dumps.
    func testPromptMatchesJevK5sPythonByteForByte() {
        let prompt = JevPrompt.prompt(state: .text("Tab \"知乎\"\nline"), criterion: "Pick one", options: ["db: 数据库", "none: None of these"])
        let user = #"{"evidence": "Tab \"知乎\"\nline", "criterion": "Pick one", "options": [{"letter": "A", "description": "db: 数据库"}, {"letter": "B", "description": "none: None of these"}]}"#
        XCTAssertEqual(prompt, "<|im_start|>system\nApply the supplied criterion to the supplied evidence. Choose exactly one listed option. "
            + "Respond with only its uppercase letter, with no explanation or reasoning.<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n"
            + "<|im_start|>assistant\n<think>\n\n</think>\n\n")
    }

    func testQuoteEscapesLikePython() {
        XCTAssertEqual(JevJSON.quote("a\u{01}b\\c\t"), #""a\u0001b\\c\t""#)
        XCTAssertEqual(JevJSON.quote("东京 ⇄ 大阪"), "\"东京 ⇄ 大阪\"")
    }

    func testOptionTextsPerKind() {
        XCTAssertEqual(JevQuestion.noul("Is it?").options.map(\.text), ["true: The proposition is true.", "false: The proposition is false."])
        XCTAssertEqual(JevQuestion.noul("Is it?", whenTrue: "It is a duplicate").options.map(\.text),
                       ["true: It is a duplicate", "false: The proposition is false."])
        XCTAssertEqual(JevQuestion.choice("Which?", [("db", "数据库"), ("none", nil)]).options.map(\.text), ["db: 数据库", "none: none"])
        XCTAssertEqual(JevQuestion.score("How bad?", levels: ["fine", "bad"]).options.map(\.text), ["0: fine", "1: bad"])
        XCTAssertEqual(JevQuestion.choice("Which?", [("a", nil)]).problem, "a choice needs at least two options")
        XCTAssertEqual(JevQuestion.choice("Which?", [("a", nil), ("a", "x")]).problem, "repeated option keys")
    }

    func testDistributionFloorsMissingLettersAndAppliesTemperature() {
        let top = ["A": -0.1, "B": -2.5, "x": -4.0]
        let (p, missing) = JevPrompt.distribution(top: top, count: 3, temperature: 1.22)
        XCTAssertTrue(missing)
        XCTAssertEqual(p.reduce(0, +), 1, accuracy: 1e-9)
        // C is missing: it reads as the lowest returned value minus 2.
        let expected = [-0.1, -2.5, -6.0].map { exp(($0 + 0.1) / 1.22) }
        let total = expected.reduce(0, +)
        for (a, b) in zip(p, expected.map { $0 / total }) { XCTAssertEqual(a, b, accuracy: 1e-12) }
    }

    func testRequestBodyKeepsTheCallersOrderAndReadsBack() throws {
        let request = JevRequest(state: .text("Order #7120 shows delivered to No. 17; the customer lives at No. 71."), model: "jevk5",
                                 questions: [("what", .choice("What happened to the parcel?", [("misdelivered", nil), ("delivered", nil), ("unknown", "Not enough")])),
                                             ("refund", .noul("Is a refund due?"))])
        let body = JevJSON.body(request)
        XCTAssertEqual(body, #"{"state":"Order #7120 shows delivered to No. 17; the customer lives at No. 71.","model":"jevk5","questions":{"what":{"type":"choice","instructions":"What happened to the parcel?","criteria":{"misdelivered":null,"delivered":null,"unknown":"Not enough"}},"refund":{"type":"noul","instructions":"Is a refund due?"}}}"#)
        let back = try JevJSON.request(Data(body.utf8))
        XCTAssertEqual(back.questions.map(\.key), ["refund", "what"])
        XCTAssertEqual(back.questions[1].question.criteria.map(\.key), ["delivered", "misdelivered", "unknown"])
        XCTAssertEqual(back.state, request.state)
    }

    func testReadsTheReadmesCurlRequest() throws {
        let body = #"{"state": "Order #7120 shows delivered to No. 17; the customer lives at No. 71.", "questions": {"what": {"type": "choice", "instructions": "What happened to the parcel?", "criteria": ["delivered", "misdelivered", "unknown"]}}}"#
        let request = try JevJSON.request(Data(body.utf8))
        XCTAssertEqual(request.questions.first?.question.options.map(\.text), ["delivered: delivered", "misdelivered: misdelivered", "unknown: unknown"])
        let scored = try JevJSON.request(Data(#"{"state": {"a": 1}, "questions": {"s": {"type": "score", "instructions": "How?", "criteria": ["low", "high"]}}}"#.utf8))
        XCTAssertEqual(scored.state, .json(#"{"a":1}"#))
        XCTAssertEqual(scored.questions[0].question.options.map(\.text), ["0: low", "1: high"])
    }

    func testAnswerShapes() throws {
        let noul = JevAnswer(.noul, ids: ["true", "false"], probabilities: [0.2, 0.8])
        XCTAssertEqual(noul.noul, 0.2)
        XCTAssertEqual(noul.confidence, 0.8)
        let choice = JevAnswer(.choice, ids: ["a", "b", "none"], probabilities: [0.1, 0.7, 0.2])
        XCTAssertEqual(choice.choice, "b")
        XCTAssertEqual(choice.probabilities?["none"], 0.2)
        let score = JevAnswer(.score, ids: ["0", "1", "2"], probabilities: [0.2, 0.3, 0.5])
        XCTAssertEqual(try XCTUnwrap(score.score), 1.3, accuracy: 1e-12)
        let json = String(decoding: try JevJSON.response(JevResponse(model: "m", answers: ["n": noul], usage: JevUsage(inputTokens: 12), latencyMS: 5)), as: UTF8.self)
        XCTAssertEqual(json, #"{"answers":{"n":{"confidence":0.8,"noul":0.2,"type":"noul"}},"latency_ms":5,"model":"m","usage":{"input_tokens":12,"output_tokens":0}}"#)
    }

    // MARK: Many options

    /// A model that always prefers the option whose text is "pick", and spreads the rest evenly.
    private func picker(calls: LockedCounter) -> JevPass {
        { options in
            calls.increment()
            let weights = options.map { $0 == "pick" ? 10.0 : 1.0 }
            let total = weights.reduce(0, +)
            return (weights.map { $0 / total }, options.count * 10)
        }
    }

    func testUpTo16OptionsIsOnePassUntouched() async throws {
        let calls = LockedCounter()
        let texts = (0..<16).map { $0 == 9 ? "pick" : "o\($0)" }
        let result = try await JevSpread.probabilities(texts, temperature: 0.5, pass: picker(calls: calls))
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(result.probabilities[9], 10.0 / 25, accuracy: 1e-12)
    }

    func testKnockoutTakesCeilPlusOnePassesAndKeepsTheBest() async throws {
        for n in [17, 40, 60, 151] {
            let calls = LockedCounter()
            let texts = (0..<n).map { $0 == n - 3 ? "pick" : "o\($0)" }
            let result = try await JevSpread.probabilities(texts, temperature: 0.93, pass: picker(calls: calls))
            XCTAssertEqual(calls.value, (n + 15) / 16 + 1, "n = \(n)")
            XCTAssertEqual(result.probabilities.count, n)
            XCTAssertEqual(result.probabilities.reduce(0, +), 1, accuracy: 1e-9)
            XCTAssertEqual(result.probabilities.indices.max { result.probabilities[$0] < result.probabilities[$1] }, n - 3)
            XCTAssertEqual(result.tokens, n * 10 + 16 * 10, "n = \(n)")
        }
    }

    func testGroupsAreContiguousAndNearlyEqual() {
        XCTAssertEqual(JevSpread.groups(40, 3), [0..<14, 14..<27, 27..<40])
        XCTAssertEqual(JevSpread.groups(17, 2), [0..<9, 9..<17])
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

final class JevNoneRuleTests: XCTestCase {
    func testNoneWinsOnlyAboveTheThreshold() {
        let likelyNone = JevAnswer(.choice, ids: ["db", "tokyo", "none"], probabilities: [0.08, 0.02, 0.90])
        let ruled = JevNoneRule.apply(likelyNone, none: "none")
        XCTAssertEqual(ruled.choice, "db")
        XCTAssertEqual(ruled.confidence, 0.8, accuracy: 1e-12)
        XCTAssertNil(ruled.probabilities?["none"])
        XCTAssertEqual(ruled.probabilities?.values.reduce(0, +) ?? 0, 1, accuracy: 1e-12)
        let surelyNone = JevAnswer(.choice, ids: ["db", "tokyo", "none"], probabilities: [0.02, 0.01, 0.97])
        XCTAssertEqual(JevNoneRule.apply(surelyNone, none: "none"), surelyNone)
        let noNoneOption = JevAnswer(.choice, ids: ["a", "b"], probabilities: [0.4, 0.6])
        XCTAssertEqual(JevNoneRule.apply(noNoneOption, none: "none"), noNoneOption)
    }
}

final class LocalDecisionBackendTests: XCTestCase {
    private let request = DecisionRequest(state: .string("New tab\nTitle: MySQL 索引优化实战 - 掘金"), questions: [
        "group": .choice("Which group?", options: [DecisionOption("db", "数据库"), DecisionOption("tokyo", "东京旅行")], none: "None of these groups"),
        "close": .noul("Should the user close it?"),
        "fit": .score("How well does it fit?", levels: ["badly", "partly", "well"]),
    ])

    func testTheRequestGoesOverInTheJevShape() {
        let jev = LocalDecisionBackend.jevRequest(request)
        XCTAssertEqual(jev.state, .text("New tab\nTitle: MySQL 索引优化实战 - 掘金"))
        XCTAssertEqual(jev.questions.map(\.key), ["close", "fit", "group"])
        XCTAssertEqual(jev.questions[2].question.options.map(\.text), ["db: 数据库", "tokyo: 东京旅行", "none_of_the_above: None of these groups"])
        XCTAssertEqual(jev.questions[1].question.options.map(\.text), ["0: badly", "1: partly", "2: well"])
        XCTAssertEqual(jev.questions[0].question.kind, .noul)
        let structured = LocalDecisionBackend.jevRequest(DecisionRequest(state: .object(["title": .string("x")]), questions: ["q": .noul("?")]))
        XCTAssertEqual(structured.state, .json(#"{"title":"x"}"#))
    }

    func testAnswersComeBackInSliceAsShapeWithTheNoneRule() throws {
        let reply = JevResponse(model: "jevk5-4b-v0.3-q4", answers: [
            "group": JevAnswer(.choice, ids: ["db", "tokyo", "none_of_the_above"], probabilities: [0.09, 0.01, 0.90]),
            "close": JevAnswer(.noul, ids: ["true", "false"], probabilities: [0.3, 0.7]),
            "fit": JevAnswer(.score, ids: ["0", "1", "2"], probabilities: [0.1, 0.2, 0.7]),
        ], usage: JevUsage(inputTokens: 300), latencyMS: 900)
        let answers = try LocalDecisionBackend.answers(reply, for: request, backend: "jevk5-4b-v0.3-q4")
        XCTAssertTrue(request.accepts(answers))
        guard case .choice(let name, let probabilities)? = answers["group"] else { return XCTFail() }
        XCTAssertEqual(name, "db")
        XCTAssertEqual(try XCTUnwrap(probabilities?["db"]), 0.9, accuracy: 1e-9)
        XCTAssertEqual(DecisionBand(answers["group"]?.probability), .act)
        XCTAssertEqual(answers["close"], .noul(false, probability: 0.3))
        guard case .score(let level, let expected)? = answers["fit"] else { return XCTFail() }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(try XCTUnwrap(expected), 1.6, accuracy: 1e-9)
    }
}
