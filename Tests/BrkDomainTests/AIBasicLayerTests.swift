import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// The basic AI layer's rules (Rules/AssistBasic.swift, AIRoutes.swift, BrkBase/Decisions.swift): every reply arrives
/// already in its schema's shape, decisions carry probabilities or not, and the reducer checks them against the browser.
final class AIBasicLayerTests: XCTestCase {
    private func driver(_ features: [AIFeature]) -> Driver {
        let d = Driver()
        for feature in features { d.user(.settings(.max(.feature(feature, true)))) }
        return d
    }
    private func aiEffects(_ t: Transition) -> [(AIRequestID, AITask)] { aiEffects(t.effects) }
    private func aiEffects(_ effects: [Effect]) -> [(AIRequestID, AITask)] {
        effects.compactMap { if case .ai(let id, let task, _) = $0 { (id, task) } else { nil } }
    }
    /// The page finishes loading with this title; the effects of every step.
    @discardableResult
    private func settle(_ d: Driver, _ tab: ItemID, title: String) -> [Effect] {
        let page = PageID(window: d.window, item: tab)
        let browser = d.state.session.live[page]?.browser ?? BrowserToken(page: page, generation: 1)
        let doc = DocumentToken(browser: browser, sequence: (d.state.session.live[page]?.documentSequence ?? 0) + 1)
        return [d.page(tab, .loadingChanged(isLoading: true, canGoBack: false, canGoForward: false)),
                d.page(tab, .documentChanged(.loading(doc))),
                d.page(tab, .titleChanged(title)),
                d.page(tab, .documentChanged(.ready(doc))),
                d.page(tab, .loadingChanged(isLoading: false, canGoBack: false, canGoForward: false))].flatMap(\.effects)
    }
    /// The pause is over.
    private func tick(_ d: Driver) -> Transition {
        d.advance(.seconds(2))
        return d.system(.aiBasicTick)
    }

    // MARK: Routes

    func testRoutesFollowTheChosenWayAndWorkWithOnlyAKeyOrOnlyACLI() {
        var max = MaxSettings.default
        max.provider = .auto
        XCTAssertEqual(AIBasicRoute.resolve(max, detected: [.claude], keys: []), .cli(.claude, model: "claude-haiku-5-5", effort: nil))
        XCTAssertEqual(AIBasicRoute.resolve(max, detected: [.codex], keys: []), .cli(.codex, model: "gpt-6-luna", effort: "low"))
        // A key with the subscription chosen: the CLI wins while it is there, the key when it is not.
        XCTAssertEqual(AIBasicRoute.resolve(max, detected: [.claude], keys: [.anthropic]), .cli(.claude, model: "claude-haiku-5-5", effort: nil))
        XCTAssertEqual(AIBasicRoute.resolve(max, detected: [], keys: [.anthropic]), .api(.anthropic, model: "claude-haiku-5-5", effort: nil))
        max.accounts = [.anthropic: .apiKey]
        XCTAssertEqual(AIBasicRoute.resolve(max, detected: [.claude], keys: [.anthropic]), .api(.anthropic, model: "claude-haiku-5-5", effort: nil))
        XCTAssertEqual(AIBasicRoute.resolve(max, detected: [.claude], keys: []), .cli(.claude, model: "claude-haiku-5-5", effort: nil), "a key chosen but not saved uses the subscription")
        // Automatic skips a signed-out CLI for a working one.
        max.accounts = nil
        XCTAssertEqual(AIBasicRoute.resolve(max, detected: [.claude, .codex], signedOut: [.claude], keys: []), .cli(.codex, model: "gpt-6-luna", effort: "low"))
        // An agent named explicitly is never answered by another.
        max.provider = .codex
        XCTAssertEqual(AIBasicRoute.resolve(max, detected: [.claude], keys: []), .unavailable(AICopy.nothingFor(.codex, .openai)))
        max.provider = .gemini
        XCTAssertEqual(AIBasicRoute.resolve(max, detected: [.gemini, .claude], keys: [.anthropic]), .unavailable(AICopy.noSchema(.gemini)))
        max.provider = .off
        XCTAssertEqual(AIBasicRoute.resolve(max, detected: [.claude], keys: []), .unavailable(AICopy.maxOff))
        max.provider = .claude
        max.basicOptions = [.claude: AIAgentOptions(model: "claude-sonnet-5-5", effort: "low")]
        XCTAssertEqual(AIBasicRoute.resolve(max, detected: [.claude], keys: []), .cli(.claude, model: "claude-sonnet-5-5", effort: "low"))
    }

    func testAccountsAndModelsAreSettingsAndKeysAreNot() throws {
        let d = Driver()
        d.user(.settings(.max(.account(.anthropic, .apiKey))))
        d.user(.settings(.max(.basicModel(.claude, "claude-sonnet-5-5"))))
        d.user(.settings(.max(.decisions(.jev))))
        XCTAssertEqual(d.state.doc.settings.max.way(.anthropic), .apiKey)
        XCTAssertEqual(d.state.doc.settings.max.basic(.claude)?.model, "claude-sonnet-5-5")
        d.user(.settings(.max(.basicModel(.claude, nil))))
        XCTAssertNil(d.state.doc.settings.max.basicOptions, "back to the default stores nothing")
        // Test asks only for a saved key; the key itself never enters the state.
        XCTAssertFalse(d.user(.settings(.max(.testKey(.openai)))).effects.contains(.aiTestKey(.openai)))
        d.system(.aiKeys([.openai: AIKeyStatus(stored: true)], localDecisions: false))
        XCTAssertTrue(d.user(.settings(.max(.testKey(.openai)))).effects.contains(.aiTestKey(.openai)))
        XCTAssertEqual(d.snapshot.settings.max.keys[.openai]?.test, .testing)
        d.system(.aiKeys([.openai: AIKeyStatus(stored: true, test: .works(models: ["gpt-6-luna"]))], localDecisions: false))
        XCTAssertEqual(d.snapshot.settings.max.keys[.openai]?.test, .works(models: ["gpt-6-luna"]))
        let file = String(decoding: d.savedFile, as: UTF8.self)
        XCTAssertTrue(file.contains("\"key\""), "the chosen way is saved")
        XCTAssertFalse(file.lowercased().contains("apikey"), "AIMax's guard: no \"apikey\" in the file")
        XCTAssertFalse(file.lowercased().contains("sk-"), "no key text in the file")
        XCTAssertFalse(file.contains("works"), "a key test is session only")
        let restored = StateCodec.restore(d.savedFile, seed: RestoreSeed(startURL: start, contentSize: Driver.contentSize), ctx: d.ctx)
        XCTAssertEqual(restored.state.doc.settings.max.decisions, .jev)
        XCTAssertEqual(restored.state.doc.settings.max.accounts, [.anthropic: .apiKey])
    }

    // MARK: Name Tabs

    func testNewTabsAreNamedInBatchesAfterThePauseAndAtMostTwoRequestsRunAtOnce() throws {
        let d = driver([.tabNames])
        var tabs: [ItemID] = []
        for n in 0..<20 {
            let tab = d.open("https://site\(n).example/page")
            settle(d, tab, title: "A very long page title number \(n) | Example Site")
            tabs.append(tab)
        }
        XCTAssertTrue(aiEffects(d.system(.aiBasicTick)).isEmpty, "nothing before the pause")
        let first = aiEffects(tick(d))
        XCTAssertEqual(first.count, AINaming.inFlight)
        guard case .nameTabs(let batch) = first[0].1 else { return XCTFail("\(first)") }
        XCTAssertEqual(batch.count, AINaming.batch)
        XCTAssertTrue(batch[0].title.hasPrefix("A very long page title"))
        // An answer frees a place: the next batch goes.
        let names = Dictionary(uniqueKeysWithValues: batch.map { ($0.id.rawValue, "Page " + $0.url.host!.replacingOccurrences(of: ".example", with: "")) })
        let after = aiEffects(d.system(.aiResult(first[0].0, .reply(.tabNames(names)))))
        XCTAssertEqual(after.count, 1, "20 tabs: 8 + 8 asked, the answer lets the last 4 go")
        guard case .nameTabs(let rest) = after.first?.1 else { return XCTFail() }
        XCTAssertEqual(rest.count, 4)
        for tab in batch {
            XCTAssertEqual(d.row(tab.id)?.title, "Page " + tab.url.host!.replacingOccurrences(of: ".example", with: ""))
            XCTAssertEqual(d.state.tab(tab.id)?.aiName?.host, tab.url.host)
            XCTAssertNil(d.state.tab(tab.id)?.customTitle, "an AI name is not a custom title")
        }
    }

    func testAUserTitleIsNeverTouchedAndAMoveToAnotherSiteNamesAgain() throws {
        let d = driver([.tabNames])
        let tab = d.open("https://news.example/story")
        settle(d, tab, title: "Breaking: something happened today - News Example")
        let (id, task) = try XCTUnwrap(aiEffects(tick(d)).first)
        guard case .nameTabs = task else { return XCTFail() }
        d.system(.aiResult(id, .reply(.tabNames([tab.rawValue: "\"Something happened.\""]))))
        XCTAssertEqual(d.row(tab)?.title, "Something happened", "quotes and the full stop go")
        // The same address elsewhere takes the name without asking.
        let twin = d.open("https://news.example/story")
        settle(d, twin, title: "Breaking: something happened today - News Example")
        XCTAssertEqual(d.row(twin)?.title, "Something happened")
        XCTAssertTrue(aiEffects(tick(d)).isEmpty)
        // Another site: the old name goes at once and a new one is asked.
        d.page(tab, .committed(url("https://docs.example/guide")))
        XCTAssertNil(d.state.tab(tab)?.aiName)
        settle(d, tab, title: "Getting started guide")
        let again = aiEffects(tick(d))
        XCTAssertEqual(again.count, 1)
        // The user renames it: it is theirs for good.
        d.user(.item(.rename(tab, title: "My guide")))
        XCTAssertTrue(d.state.tab(tab)?.userNamed == true)
        d.system(.aiResult(again[0].0, .reply(.tabNames([tab.rawValue: "Docs Guide"]))))
        XCTAssertEqual(d.row(tab)?.title, "My guide")
        d.page(tab, .committed(url("https://other.example/")))
        settle(d, tab, title: "Other")
        XCTAssertTrue(aiEffects(tick(d)).isEmpty)
        // Return on the AI's name unchanged keeps it the AI's.
        d.user(.item(.rename(twin, title: "Something happened")))
        XCTAssertFalse(d.state.tab(twin)?.userNamed == true)
    }

    func testAnswersInTheWrongShapeChangeNothing() throws {
        let d = driver([.tabNames])
        d.user(.settings(.max(.tidyTabs(true))))
        for n in 0..<3 { _ = d.open("https://t\(n).example/") }
        let before = d.todayIDs
        let (id, task) = try XCTUnwrap(aiEffects(d.user(.assist(.organizeToday))).first)
        guard case .tidyToday = task else { return XCTFail() }
        // Prose is not an answer for a basic task, even prose that looks like the plan.
        d.system(.aiResult(id, .text("[{\"folder\":\"Reading\",\"tabs\":[]}]")))
        XCTAssertEqual(d.todayIDs, before)
        XCTAssertTrue(d.view.tabTools.toast?.text.contains("did not match") == true, "\(String(describing: d.view.tabTools.toast))")
    }

    /// The entries of a popup menu, as the sidebar's right-click asks for it.
    private func menu(_ d: Driver, _ request: PopupMenuRequest) -> [MenuEntry] {
        for case .popupMenu(_, let model, _) in d.user(.sidebar(.popupMenu(request, at: .zero))).effects { return model.entries }
        return []
    }
    private func titles(_ entries: [MenuEntry]) -> [String] { entries.compactMap { if case .action(let title, _, _) = $0 { title } else { nil } } }
    private func folderTitle(_ d: Driver, _ id: ItemID) -> String? { if case .folder(let f)? = d.state.doc.tree[id]?.body { f.title } else { nil } }

    // MARK: Folder names

    func testNameWithAIIsOnTheMenuOnlyWhenOnAndRenamesWithUndo() throws {
        let d = Driver()
        let tab = d.open("https://recipes.example/soup"), stew = d.open("https://recipes.example/stew")
        let folder = try XCTUnwrap(aiGroup(d, named: "Untitled", tabs: [tab, stew]))
        func menu() -> [String] { titles(self.menu(d, .item(folder))) }
        XCTAssertFalse(menu().contains(AICopy.nameWithAI), "Arc's menu while the switch is off")
        d.user(.settings(.max(.feature(.folderNames, true))))
        XCTAssertTrue(menu().contains(AICopy.nameWithAI))
        let (id, task) = try XCTUnwrap(aiEffects(d.user(.assist(.nameFolder(folder)))).first)
        guard case .nameFolder(folder, let tabs) = task else { return XCTFail("\(task)") }
        XCTAssertEqual(tabs.map(\.id), [tab, stew])
        d.system(.aiResult(id, .reply(.text("Soups"))))
        XCTAssertEqual(folderTitle(d, folder), "Soups")
        XCTAssertTrue(d.view.tabTools.toast?.text.contains("Named “Soups”") == true)
        d.user(.tabTools(.undoToast))
        XCTAssertEqual(folderTitle(d, folder), "Untitled")
    }

    /// A Today group made the way Tidy makes one, with the AI's name in its plan.
    private func aiGroup(_ d: Driver, named name: String, tabs: [ItemID]) -> ItemID? {
        let tidy = d.state.doc.settings.max.tidyTabs
        d.user(.settings(.max(.tidyTabs(true))))
        defer { if !tidy { d.user(.settings(.max(.tidyTabs(false)))) } }
        guard let (id, task) = aiEffects(d.user(.assist(.organizeToday))).first, case .tidyToday(_, let eligible) = task else { return nil }
        let rest = eligible.map(\.id).filter { !tabs.contains($0) }
        var plan = [AIGroupPlan(folder: name, tabs: tabs.map(\.rawValue))]
        if !rest.isEmpty { plan.append(AIGroupPlan(folder: "Other", tabs: rest.map(\.rawValue))) }
        d.system(.aiResult(id, .reply(.groups(plan))))
        return d.state.doc.tree[tabs[0]]?.parent
    }

    // MARK: Place New Tabs

    private func placementDriver() throws -> (Driver, ItemID) {
        let d = driver([.tabPlacement])
        let group = try XCTUnwrap(aiGroup(d, named: "Recipes", tabs: [d.open("https://recipes.example/soup"), d.open("https://recipes.example/salad")]))
        return (d, group)
    }

    private func placementRequest(_ d: Driver, _ tab: ItemID) throws -> (AIRequestID, DecisionRequest) {
        let t = settle(d, tab, title: "Chicken noodle soup recipe")
        let (id, task) = try XCTUnwrap(aiEffects(t).first)
        guard case .decide(let request, .tabPlacement, _) = task else { throw XCTSkip("\(task)") }
        return (id, request)
    }

    func testASureAnswerMovesTheNewTabWithUndoAndNoProbabilityOnlySuggests() throws {
        let (d, group) = try placementDriver()
        let tab = d.open("https://recipes.example/noodles")
        let (id, request) = try placementRequest(d, tab)
        XCTAssertEqual(request.questions["group"]?.choiceNames.first, "Recipes")
        XCTAssertEqual(request.questions["group"]?.choiceNames.last, DecisionQuestion.noneName)
        XCTAssertNil(request.questions["space"], "one Space: no Space question")
        d.system(.aiResult(id, .reply(.decision(DecisionAnswers(answers: ["group": .choice("Recipes", probabilities: ["Recipes": 0.93, DecisionQuestion.noneName: 0.07])], backend: "jevk5")))))
        XCTAssertEqual(d.state.doc.tree[tab]?.parent, group)
        XCTAssertTrue(d.view.tabTools.toast?.text.contains("Moved to “Recipes”") == true)
        d.user(.tabTools(.undoToast))
        XCTAssertNotEqual(d.state.doc.tree[tab]?.parent, group)

        let other = d.open("https://recipes.example/stew")
        let (second, _) = try placementRequest(d, other)
        d.system(.aiResult(second, .reply(.decision(DecisionAnswers(answers: ["group": .choice("Recipes", probabilities: nil)], backend: "text")))))
        XCTAssertNotEqual(d.state.doc.tree[other]?.parent, group, "no probability: never moved")
        XCTAssertEqual(d.row(other)?.aiSuggestion, AISuggestionLabel(action: "Move to", name: "Recipes"))
        d.user(.assist(.acceptSuggestion(other)))
        XCTAssertEqual(d.state.doc.tree[other]?.parent, group)
        XCTAssertNil(d.state.session.ai.basic.suggestions[other])
    }

    func testAnotherSpaceIsOnlyEverSuggested() throws {
        let (d, _) = try placementDriver()
        let home = d.view.space.id
        let work = d.newSpace("Work")
        d.user(.space(.focus(home)))
        let tab = d.open("https://jira.example/board")
        let (id, request) = try placementRequest(d, tab)
        XCTAssertEqual(Set(request.questions["space"]?.choiceNames ?? []), Set([d.state.displayTitle(of: home), "Work"]))
        d.system(.aiResult(id, .reply(.decision(DecisionAnswers(answers: ["space": .choice("Work", probabilities: ["Work": 0.99])], backend: "jevk5")))))
        XCTAssertEqual(d.state.role(of: tab)?.space, home, "however sure, the tab stays")
        XCTAssertEqual(d.row(tab)?.aiSuggestion?.text, "Move to Work")
        d.user(.assist(.acceptSuggestion(tab)))
        XCTAssertEqual(d.state.role(of: tab)?.space, work)
    }

    func testOnlyNewTabsAreAskedAndAMovedTabIsLeftAlone() throws {
        let (d, _) = try placementDriver()
        let tab = d.open("https://recipes.example/rice")
        d.user(.tab(.togglePin(.item(tab))))
        XCTAssertTrue(aiEffects(settle(d, tab, title: "Rice")).isEmpty, "moved by hand before its page loaded")
        d.user(.settings(.max(.feature(.tabPlacement, false))))
        let off = d.open("https://recipes.example/bread")
        XCTAssertTrue(aiEffects(settle(d, off, title: "Bread")).isEmpty)
    }

    // MARK: Suggest Tabs to Close

    func testDuplicatesAndLongUnvisitedTodayTabsAreListedBesideTidy() throws {
        let d = driver([.tabCleanup])
        let old = d.open("https://old.example/")
        _ = d.open("https://filler.example/")
        d.advance(.seconds(8 * 3_600))
        let a = d.open("https://dup.example/page"), b = d.open("https://dup.example/page/")
        let fresh = d.open("https://fresh.example/")
        let found = d.state.cleanupCandidatesForTest(d.view.space.id, now: d.ctx.now)
        XCTAssertEqual(found.duplicates.count, 1, "one of the two copies")
        XCTAssertTrue([a, b].contains(found.duplicates[0]))
        XCTAssertTrue(found.stale.contains(old), "past half the 12-hour archive time")
        XCTAssertFalse(found.stale.contains(fresh))
        XCTAssertEqual(d.view.space.today.cleanup, found.duplicates.count + found.stale.count)
        let entries = menu(d, .todayCleanup(d.view.space.id))
        XCTAssertTrue(entries.contains(.header(AICopy.cleanupDuplicates)))
        XCTAssertTrue(entries.contains(.header(AICopy.cleanupStale)))
        let archive = Command.tabTools(.bulk(.items([old]), .archive))
        XCTAssertTrue(entries.contains { if case .action(let title, archive, true) = $0 { title.hasPrefix("Archive “") } else { false } }, "\(entries)")
        d.user(archive)
        XCTAssertNil(d.state.tab(old), "archived from the list")
        d.user(.settings(.max(.feature(.tabCleanup, false))))
        XCTAssertEqual(d.view.space.today.cleanup, 0)
        XCTAssertTrue(menu(d, .todayCleanup(d.view.space.id)).isEmpty)
    }

    func testTheAddressRuleIsSliceBs() {
        func same(_ a: String, _ b: String) -> Bool { AICleanup.addressKey(url(a)) == AICleanup.addressKey(url(b)) }
        XCTAssertTrue(same("https://www.example.com/page#usage", "http://example.com/page"))
        XCTAssertTrue(same("https://m.example.com/a/index.html", "https://example.com/a/"))
        XCTAssertTrue(same("https://example.com/p?utm_source=x&id=3&fbclid=1", "https://example.com/p?id=3"))
        XCTAssertTrue(same("https://en.m.wikipedia.org/wiki/Arc", "https://en.wikipedia.org/wiki/Arc"))
        XCTAssertFalse(same("https://example.com/p?id=3", "https://example.com/p?id=4"))
        XCTAssertFalse(same("https://example.com/xm5", "https://example.com/xm6"))
        XCTAssertNil(AICleanup.addressKey(url("file:///tmp/a.html")))
    }

    func testEmbeddingCandidatesAreAskedYesOrNoOnePairAtATimeAndAYesJoinsTheList() throws {
        let d = driver([.tabCleanup])
        d.system(.aiProvidersDetected([.claude]))
        let news = d.open("https://news.example/"), front = d.open("https://news.example/news")
        let other = d.open("https://news.example/jobs")
        d.page(news, .titleChanged("Hacker News"))
        d.page(front, .titleChanged("Hacker News"))
        XCTAssertEqual(d.view.space.today.cleanup, 0, "different addresses: not duplicates by the rule")
        let t = d.system(.aiDuplicateCandidates([AIDuplicatePair(a: front, b: news, similarity: 0.95), AIDuplicatePair(a: other, b: news, similarity: 0.93)]))
        let asked = aiEffects(t)
        XCTAssertEqual(asked.count, 2, "one request per pair, as slice B measured JevK5")
        let (id, task) = try XCTUnwrap(asked.first)
        guard case .decide(let request, .tabCleanup, nil) = task else { return XCTFail("\(task)") }
        XCTAssertEqual(request.questions, ["same_page": .noul("Are these two browser tabs the same web page (the same document or item, perhaps with a different address form), rather than two different pages on the same site or topic?")])
        guard case .string(let text) = request.state else { return XCTFail("\(request.state)") }
        XCTAssertEqual(text, "Tab 1: Hacker News\nAddress 1: https://news.example/news\nTab 2: Hacker News\nAddress 2: https://news.example/", "the titles the sidebar shows")
        d.system(.aiResult(id, .reply(.decision(DecisionAnswers(answers: ["same_page": .noul(true, probability: 0.97)], backend: "jevk5")))))
        d.system(.aiResult(asked[1].0, .reply(.decision(DecisionAnswers(answers: ["same_page": .noul(false, probability: 0.1)], backend: "jevk5")))))
        let found = d.state.cleanupCandidatesForTest(d.view.space.id, now: d.ctx.now)
        XCTAssertEqual(found.duplicates, [front])
        XCTAssertEqual(d.view.space.today.cleanup, 1)
    }

    // MARK: Usage

    func testNamesAndTheUsersMarkSurviveARestart() throws {
        let d = driver([.tabNames])
        let tab = d.open("https://keep.example/")
        settle(d, tab, title: "Keep this page")
        let (id, _) = try XCTUnwrap(aiEffects(tick(d)).first)
        d.system(.aiResult(id, .reply(.tabNames([tab.rawValue: "Kept"]))))
        let renamed = d.open("https://mine.example/")
        d.user(.item(.rename(renamed, title: "Mine")))
        let restored = StateCodec.restore(d.savedFile, seed: RestoreSeed(startURL: start, contentSize: Driver.contentSize), ctx: d.ctx)
        XCTAssertEqual(restored.state.tab(tab)?.aiName, AITabName(title: "Kept", host: "keep.example"))
        XCTAssertTrue(restored.state.tab(renamed)?.userNamed == true)
    }
}

extension AppState {
    func cleanupCandidatesForTest(_ space: SpaceID, now: Instant) -> (duplicates: [ItemID], stale: [ItemID]) {
        guard let value = doc.spaces[space] else { return ([], []) }
        return AICleanup.candidates(tree: doc.tree, space: value, now: now, threshold: doc.settings.profiles[value.profile]?.autoArchive ?? .default,
                                    near: session.ai.basic.nearDuplicates)
    }
}
