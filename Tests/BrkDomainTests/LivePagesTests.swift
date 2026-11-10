import BrkBase
@testable import BrkDomain
import XCTest

/// Live AI pages in the reducer: schedules and their catch-up, the refresh's data checked against the page's shape, the
/// row's mark, the page's own saves and their caps, weekdays in Today, deleting for good, and the command bar finding
/// conversations. T0 is Monday 2026-09-21 14:13:20 UTC; the Driver's calendar is UTC.
final class LivePagesTests: XCTestCase {
    private let calendar = Driver.calendar
    private func at(_ text: String) -> Instant {
        let formatter = ISO8601DateFormatter()
        return Instant(milliseconds: Int64(formatter.date(from: text)!.timeIntervalSince1970 * 1000))
    }

    // MARK: Schedules

    func testSlotsAreTheLatestHourDayOrWeekdayAtOrBeforeNow() {
        XCTAssertEqual(AIPageSchedule.hourly.latestSlot(atOrBefore: T0, calendar: calendar), at("2026-09-21T14:00:00Z"))
        XCTAssertEqual(AIPageSchedule.daily(hour: 9, minute: 0).latestSlot(atOrBefore: T0, calendar: calendar), at("2026-09-21T09:00:00Z"))
        XCTAssertEqual(AIPageSchedule.daily(hour: 18, minute: 30).latestSlot(atOrBefore: T0, calendar: calendar), at("2026-09-20T18:30:00Z"))
        XCTAssertEqual(AIPageSchedule.weekly(weekday: 2, hour: 9, minute: 0).latestSlot(atOrBefore: T0, calendar: calendar), at("2026-09-21T09:00:00Z"), "Monday")
        XCTAssertEqual(AIPageSchedule.weekly(weekday: 2, hour: 15, minute: 0).latestSlot(atOrBefore: T0, calendar: calendar), at("2026-09-14T15:00:00Z"), "later today: last Monday")
        XCTAssertEqual(AIPageSchedule.weekly(weekday: 3, hour: 9, minute: 0).latestSlot(atOrBefore: T0, calendar: calendar), at("2026-09-15T09:00:00Z"), "Tuesday")
        XCTAssertFalse(AIPageSchedule.daily(hour: 24, minute: 0).isValid)
        XCTAssertFalse(AIPageSchedule.weekly(weekday: 8, hour: 9, minute: 0).isValid)
    }

    func testWeekdaysParse() {
        XCTAssertEqual(AIPageWeekdays.parse("monday"), 2)
        XCTAssertEqual(AIPageWeekdays.parse("Sun"), 1)
        XCTAssertEqual(AIPageWeekdays.parse("周一"), 2)
        XCTAssertEqual(AIPageWeekdays.parse("星期六"), 7)
        XCTAssertNil(AIPageWeekdays.parse("someday"))
        XCTAssertEqual(AIPageWeekdays.normalized([6, 2, 2, 9]), [2, 6])
        XCTAssertNil(AIPageWeekdays.normalized([1, 2, 3, 4, 5, 6, 7]), "every day is no restriction")
    }

    // MARK: Shapes

    private let prices: [String: Any] = [
        "type": "object", "required": ["items"], "additionalProperties": false,
        "properties": ["items": ["type": "array", "maxItems": 10, "items": [
            "type": "object", "required": ["id", "name", "price"],
            "properties": ["id": ["type": "string"], "name": ["type": "string", "maxLength": 80], "price": ["type": "number", "minimum": 0],
                           "currency": ["type": "string", "enum": ["EUR", "USD"]]]]]],
    ]

    func testDataIsCheckedAgainstTheDeclaredShape() {
        let good: [String: Any] = ["items": [["id": "kettle", "name": "Kettle", "price": 39.0, "currency": "EUR"]]]
        XCTAssertNil(AIPageShape.problem(good, prices))
        XCTAssertEqual(AIPageShape.problem(["items": [["id": "k", "name": "K", "price": "39"]]], prices), "data.items[0].price must be number")
        XCTAssertEqual(AIPageShape.problem(["items": [["id": "k", "name": "K"]]], prices), "data.items[0].price is missing")
        XCTAssertEqual(AIPageShape.problem(["items": [], "leak": "x"], prices), "data.leak is not in the page's shape")
        XCTAssertEqual(AIPageShape.problem(["items": [["id": "k", "name": "K", "price": -1]]], prices), "data.items[0].price is below 0.0")
        XCTAssertEqual(AIPageShape.problem(["items": [["id": "k", "name": "K", "price": 1, "currency": "GBP"]]], prices), "data.items[0].currency is not one of the allowed values")
        XCTAssertEqual(AIPageShape.problem(["items": Array(repeating: ["id": "k", "name": "K", "price": 1], count: 11)], prices), "data.items has more than 10 items")
        XCTAssertEqual(AIPageShape.problem(["items": [["id": "k", "name": String(repeating: "x", count: 81), "price": 1]]], prices), "data.items[0].name is longer than 80 characters")
        XCTAssertEqual(AIPageShape.problem(["items": true], prices), "data.items must be array")
        XCTAssertNil(AIPageShape.shapeProblem(prices))
        XCTAssertEqual(AIPageShape.shapeProblem(["type": "thing"]), "unknown type thing")
    }

    func testAShapeIsInferredFromTheFirstDataWhenNoneWasDeclared() throws {
        let data = try XCTUnwrap(AIPageShape.object(#"{"items":[{"id":"a","price":1.5,"note":null},{"id":"b","price":2}],"updated":"x","on":true}"#))
        let shape = AIPageShape.infer(data)
        XCTAssertNil(AIPageShape.problem(data, shape))
        XCTAssertNil(AIPageShape.problem(["items": [["id": "c", "price": 3, "note": "now a string"]], "updated": "y", "on": false, "extra": 1], shape), "extra keys and a null's new type pass")
        XCTAssertNotNil(AIPageShape.problem(["items": [["id": "c", "price": "3"]], "updated": "y", "on": false], shape), "a number stays a number")
        XCTAssertNotNil(AIPageShape.problem(["items": [], "on": false], shape), "a key the data had stays required")
        XCTAssertNotNil(AIPageShape.problem(["items": [["price": 3]], "updated": "y", "on": false], shape), "each item keeps its id")
    }

    // MARK: A kept page with a schedule

    private func enabled() -> Driver {
        let d = Driver()
        for feature in AIFeature.allCases { d.user(.settings(.max(.feature(feature, !AIFeature.basicLayer.contains(feature))))) }
        d.system(.aiProvidersDetected([.claude, .codex]))
        d.system(.aiAgents([AIAgentStatus(kind: .claude, state: .ready), AIAgentStatus(kind: .codex, state: .ready)]))
        return d
    }
    private let schema = #"{"properties":{"items":{"items":{"properties":{"id":{"type":"string"},"price":{"type":"number"}},"required":["id","price"],"type":"object"},"type":"array"}},"required":["items"],"type":"object"}"#
    private let kettle = URL(string: "http://127.0.0.1:9/shop-kettle.html")!

    /// A conversation with a rendered page kept as a tab with `live`, the way the agent's `brk_page_save` keeps it.
    private func keptPage(_ d: Driver, live: [AIPageLiveChange] = [.schedule(.hourly)], data: String? = #"{"items":[{"id":"kettle","price":39}]}"#,
                          schema: String? = nil, agent: AIProviderKind = .claude) throws -> (conversation: AIRequestID, page: AIPageID) {
        let opened = d.open(kettle.absoluteString)
        XCTAssertNotNil(opened)
        let t = d.user(.assist(.ask("盯着这三个商品页的价格，每小时更新一次")))
        let id = try XCTUnwrap(t.effects.lazy.compactMap { if case .ai(let id, _, _) = $0 { id } else { nil } }.first)
        d.system(.aiConversation(id, .started(agent: agent, name: agent.displayName, model: agent == .claude ? "claude-sonnet-5-5" : "gpt-6-astra", effort: nil)))
        let page = AIPageID("page-1")
        d.system(.aiConversation(id, .page(AIPageRecord(id: page, title: "Price Watch", html: URL(fileURLWithPath: "/tmp/brk-test-pages/page-1.html"), height: 300, data: data,
                                                        conversation: id, profile: .default, createdAt: T0, readPages: true, schema: schema ?? self.schema, sources: [kettle]))))
        let kept = d.system(.agentAct(AgentActRequest(call: "save", window: d.window, act: .keepPage(page, title: nil, conversation: id, live: live))))
        XCTAssertTrue(kept.effects.contains { if case .agentActDone("save", .done) = $0 { true } else { false } }, "\(kept.effects)")
        d.system(.aiResult(id, .text("Kept.")))
        return (id, page)
    }
    private func refreshes(_ t: Transition) -> [AIPageRefreshRun] { t.effects.compactMap { if case .aiRefreshPage(let run) = $0 { run } else { nil } } }
    private func pageRow(_ d: Driver, _ page: AIPageID) -> TabRow? { d.allTabRows.first { $0.url == AIPageTab.url(page) } }

    func testKeepingWithRefreshSetsTheScheduleAndTheFirstRunIsTheNextSlot() throws {
        let d = enabled()
        let (_, page) = try keptPage(d)
        let live = try XCTUnwrap(d.state.savedPages[page]?.live)
        XCTAssertEqual(live.schedule, .hourly)
        XCTAssertEqual(live.lastRun, d.now)
        XCTAssertNil(pageRow(d, page)?.liveMark)
        XCTAssertEqual(pageRow(d, page)?.sourceStatus, "Refreshes every hour")
        d.advance(.seconds(40 * 60))
        XCTAssertEqual(refreshes(d.system(.clockTick)), [], "14:53: not yet")
        d.advance(.seconds(7 * 60))
        let runs = refreshes(d.system(.clockTick))
        XCTAssertEqual(runs.count, 1, "15:00:20")
        let run = try XCTUnwrap(runs.first)
        XCTAssertEqual(run.page, page)
        XCTAssertEqual(run.agent, .claude)
        XCTAssertEqual(run.model, "claude-haiku-5-5", "the small basic model by default")
        XCTAssertEqual(run.sources, [kettle])
        XCTAssertEqual(run.schema, schema)
        XCTAssertTrue(run.history.contains("盯着这三个商品页的价格"))
        XCTAssertEqual(run.now, d.now, "the agent is told Brk's time, not its own")
        XCTAssertTrue(pageRow(d, page)?.loading == true, "the row shows it working")
        XCTAssertEqual(refreshes(d.system(.clockTick)), [], "one run at a time")
    }

    func testAMissedSlotRunsOnceAtTheNextLaunch() throws {
        let d = enabled()
        let (_, page) = try keptPage(d)
        // Quit: the saved records come back at the next launch, three days later.
        let pages = Array(d.state.savedPages.values), conversations = Array(d.state.savedConversations.values)
        let file = d.savedFile
        let next = Driver(file: file)
        next.advance(.seconds(3 * 86_400))
        XCTAssertEqual(refreshes(next.system(.conversationsLoaded(conversations, pages))).count, 0, "the agents have not said they are ready yet")
        next.system(.aiProvidersDetected([.claude]))
        let runs = refreshes(next.system(.aiAgents([AIAgentStatus(kind: .claude, state: .ready)])))
        XCTAssertEqual(runs.count, 1, "seventy-two missed slots, one run")
        next.system(.aiPageRefresh(page, run: runs[0].run, .finished(.updated, detail: nil)))
        next.advance(.seconds(30))
        XCTAssertEqual(refreshes(next.system(.clockTick)), [], "the run took the latest slot")
    }

    func testNoRefreshWhileMaxIsOffOrWithoutAWindowOfTheProfile() throws {
        let d = enabled()
        let (_, page) = try keptPage(d)
        d.user(.settings(.max(.provider(.off))))
        d.advance(.seconds(3_600))
        XCTAssertEqual(refreshes(d.system(.clockTick)), [])
        d.user(.assist(.livePage(page, .refreshNow)))
        XCTAssertEqual(d.state.savedPages[page]?.live?.outcome?.kind, .failed, "Refresh Now says why on the row")
        XCTAssertTrue(d.state.savedPages[page]?.live?.outcome?.detail?.contains("Max is off") == true)
    }

    func testARefreshsDataReplacesTheDataWhenItFitsAndMarksTheRow() throws {
        let d = enabled()
        let (conversation, page) = try keptPage(d)
        let run = try XCTUnwrap(refreshes(d.user(.assist(.livePage(page, .refreshNow)))).first)
        let before = d.state.savedPages[page]!
        // Wrong shapes and another run change nothing.
        d.system(.aiPageRefresh(page, run: run.run, .data(#"{"items":[{"id":"kettle","price":"cheap"}]}"#)))
        d.system(.aiPageRefresh(page, run: run.run, .data(#"{"rows":[]}"#)))
        d.system(.aiPageRefresh(page, run: AIRequestID("old-run"), .data(#"{"items":[{"id":"kettle","price":1}]}"#)))
        XCTAssertEqual(d.state.savedPages[page]?.data, before.data)
        d.system(.aiPageRefresh(page, run: run.run, .data(#"{"items":[{"price":34.5,"id":"kettle"}]}"#)))
        let after = try XCTUnwrap(d.state.savedPages[page])
        XCTAssertEqual(after.data, #"{"items":[{"id":"kettle","price":34.5}]}"#)
        XCTAssertEqual(after.revision, 1, "views load the page again")
        d.system(.aiPageRefresh(page, run: run.run, .finished(.updated, detail: nil)))
        XCTAssertEqual(d.state.savedPages[page]?.live?.outcome?.kind, .updated)
        XCTAssertEqual(pageRow(d, page)?.liveMark, .changed)
        XCTAssertFalse(pageRow(d, page)?.loading ?? true)
        // The conversation was in Chinese: Brk's notice is too, with the time of the refresh.
        XCTAssertEqual(d.state.savedConversations[conversation]?.items.last, .notice("\(AIWords.clock(d.now, calendar: Driver.calendar)) 已更新「Price Watch」"))
        // Showing the page is looking at it.
        d.user(.tab(.focus(pageRow(d, page)!.id)))
        XCTAssertNil(pageRow(d, page)?.liveMark)
        XCTAssertEqual(d.view.aiPages.first?.content?.revision, 1)
    }

    func testAPageThatRefreshesItselfIsNotAutoArchivedButItsRowsCloseStillArchives() throws {
        let d = enabled()
        let (conversation, page) = try keptPage(d)
        d.user(.tab(.focus(d.todayIDs.last!)))
        d.advance(.seconds(3 * 86_400))
        let runs = refreshes(d.system(.clockTick))
        XCTAssertEqual(runs.count, 1, "the sweep left it in Today, so its slot runs")
        XCTAssertNotNil(pageRow(d, page))
        XCTAssertFalse(d.state.doc.archive.contains { $0.tab.url == ConversationPage.url(conversation) }, "its conversation has no row to sweep (step 8)")
        XCTAssertNotNil(d.state.savedConversations[conversation])
        d.system(.aiPageRefresh(page, run: runs[0].run, .finished(.updated, detail: nil)))
        d.user(.tab(.close(.item(try XCTUnwrap(pageRow(d, page)).id))))
        XCTAssertTrue(d.state.doc.archive.contains { $0.tab.url == AIPageTab.url(page) }, "the × archives it")
        d.advance(.seconds(3_600))
        XCTAssertEqual(refreshes(d.system(.clockTick)), [], "an archived page does not refresh")
    }

    func testAnHourlyAndAWeeklyPageDueAtOnceBothRefreshWithoutWaitingForEachOther() throws {
        let d = enabled()
        let (conversation, hourly) = try keptPage(d)
        let weekly = AIPageID("page-2")
        d.system(.aiConversation(conversation, .page(AIPageRecord(id: weekly, title: "Reading List", html: URL(fileURLWithPath: "/tmp/brk-test-pages/page-2.html"), height: 300,
                                                                  data: #"{"items":[{"id":"a","price":1}]}"#, conversation: conversation, profile: .default,
                                                                  createdAt: T0, readPages: true, schema: schema))))
        let kept = d.system(.agentAct(AgentActRequest(call: "w", window: d.window, act: .keepPage(weekly, title: nil, conversation: conversation,
                                                                                               live: [.schedule(.weekly(weekday: 2, hour: 9, minute: 0))]))))
        XCTAssertTrue(kept.effects.contains { if case .agentActDone("w", .done) = $0 { true } else { false } })
        d.user(.tab(.focus(d.todayIDs.last!)))
        // A week on (Monday 28 September, 14:13): the hourly slot and the weekly one have both passed.
        d.advance(.seconds(7 * 86_400))
        let runs = refreshes(d.system(.clockTick))
        XCTAssertEqual(Set(runs.map(\.page)), [hourly, weekly], "both start on the same tick")
        XCTAssertEqual(Set(runs.map(\.run)).count, 2)
        XCTAssertNotNil(pageRow(d, hourly), "the sweep left both in Today")
        XCTAssertNotNil(pageRow(d, weekly))
        XCTAssertTrue(pageRow(d, hourly)?.loading == true && pageRow(d, weekly)?.loading == true)
        let hourlyRun = try XCTUnwrap(runs.first { $0.page == hourly }), weeklyRun = try XCTUnwrap(runs.first { $0.page == weekly })
        // Each run's data goes to its own page only; one finishing does not end the other.
        d.system(.aiPageRefresh(hourly, run: weeklyRun.run, .data(#"{"items":[{"id":"kettle","price":1}]}"#)))
        XCTAssertEqual(d.state.savedPages[hourly]?.data, #"{"items":[{"id":"kettle","price":39}]}"#, "another page's run cannot write here")
        d.system(.aiPageRefresh(hourly, run: hourlyRun.run, .data(#"{"items":[{"id":"kettle","price":30}]}"#)))
        d.system(.aiPageRefresh(hourly, run: hourlyRun.run, .finished(.updated, detail: nil)))
        XCTAssertTrue(pageRow(d, weekly)?.loading == true, "the weekly run goes on")
        XCTAssertEqual(refreshes(d.system(.clockTick)), [], "neither starts again while one still runs")
        d.system(.aiPageRefresh(weekly, run: weeklyRun.run, .data(#"{"items":[{"id":"b","price":2}]}"#)))
        d.system(.aiPageRefresh(weekly, run: weeklyRun.run, .finished(.updated, detail: nil)))
        XCTAssertEqual(d.state.savedPages[hourly]?.live?.outcome?.kind, .updated)
        XCTAssertEqual(d.state.savedPages[weekly]?.live?.outcome?.kind, .updated)
        XCTAssertEqual(pageRow(d, hourly)?.liveMark, .changed)
        XCTAssertEqual(pageRow(d, weekly)?.liveMark, .changed)
        d.advance(.seconds(60))
        XCTAssertEqual(refreshes(d.system(.clockTick)), [], "both took their latest slot")
        d.advance(.seconds(3_600))
        XCTAssertEqual(refreshes(d.system(.clockTick)).map(\.page), [hourly], "the next hour is the hourly page's alone")
    }

    func testTheSameDataIsNoChangeAndSaysNothing() throws {
        let d = enabled()
        let (conversation, page) = try keptPage(d)
        let items = d.state.savedConversations[conversation]?.items
        let run = try XCTUnwrap(refreshes(d.user(.assist(.livePage(page, .refreshNow)))).first)
        d.system(.aiPageRefresh(page, run: run.run, .data(#"{"items":[{"id":"kettle","price":39}]}"#)))
        d.system(.aiPageRefresh(page, run: run.run, .finished(.updated, detail: nil)))
        XCTAssertEqual(d.state.savedPages[page]?.live?.outcome?.kind, .unchanged)
        XCTAssertNil(pageRow(d, page)?.liveMark)
        XCTAssertEqual(d.state.savedConversations[conversation]?.items, items)
    }

    func testAFlaggedRefreshChangesNothingAndMarksTheRow() throws {
        let d = enabled()
        let (conversation, page) = try keptPage(d)
        let before = d.state.savedPages[page]?.data
        let run = try XCTUnwrap(refreshes(d.user(.assist(.livePage(page, .refreshNow)))).first)
        d.system(.aiPageRefresh(page, run: run.run, .finished(.flagged, detail: "Brk flagged the source http://127.0.0.1:9/shop-kettle.html: it contains “ignore previous instructions”")))
        XCTAssertEqual(d.state.savedPages[page]?.data, before)
        XCTAssertEqual(d.state.savedPages[page]?.live?.outcome?.kind, .flagged)
        XCTAssertEqual(pageRow(d, page)?.liveMark, .attention)
        XCTAssertTrue(pageRow(d, page)?.sourceStatus?.contains("last refresh stopped") == true)
        XCTAssertTrue(d.state.savedConversations[conversation]?.items.last.map { if case .notice(let t) = $0 { t.hasPrefix("已停止更新「Price Watch」") } else { false } } == true)
        // Data that arrives after the run ended is not taken.
        d.system(.aiPageRefresh(page, run: run.run, .data(#"{"items":[{"id":"kettle","price":1}]}"#)))
        XCTAssertEqual(d.state.savedPages[page]?.data, before)
    }

    func testChangingTheScheduleToNeverStopsTheRefreshes() throws {
        let d = enabled()
        let (_, page) = try keptPage(d)
        d.user(.assist(.livePage(page, .schedule(.weekly(weekday: 2, hour: 9, minute: 0)))))
        XCTAssertEqual(d.state.savedPages[page]?.live?.schedule, .weekly(weekday: 2, hour: 9, minute: 0))
        d.user(.assist(.livePage(page, .schedule(nil))))
        d.advance(.seconds(86_400))
        XCTAssertEqual(refreshes(d.system(.clockTick)), [], "Never")
    }

    // MARK: The page's own saves

    func testAPagesSaveIsKeptWhenItFitsAndARefreshNeverChangesIt() throws {
        let d = enabled()
        let (_, page) = try keptPage(d)
        d.user(.assist(.pageSave(page, #"{"ticked":["kettle"],"notes":{"kettle":"wait for €30"}}"#)))
        XCTAssertEqual(d.state.savedPages[page]?.saved, #"{"notes":{"kettle":"wait for €30"},"ticked":["kettle"]}"#)
        XCTAssertEqual(d.state.savedPages[page]?.revision, nil, "a save does not reload the page")
        XCTAssertEqual(d.view.aiPages.first?.content?.saved, nil, "the card is not shown")
        d.user(.tab(.focus(pageRow(d, page)!.id)))
        XCTAssertEqual(d.view.aiPages.first?.content?.saved, #"{"notes":{"kettle":"wait for €30"},"ticked":["kettle"]}"#)
        // The next refresh reads it and keeps it.
        let run = try XCTUnwrap(refreshes(d.user(.assist(.livePage(page, .refreshNow)))).first)
        XCTAssertEqual(run.saved, #"{"notes":{"kettle":"wait for €30"},"ticked":["kettle"]}"#)
        d.system(.aiPageRefresh(page, run: run.run, .data(#"{"items":[{"id":"kettle","price":30}]}"#)))
        d.system(.aiPageRefresh(page, run: run.run, .finished(.updated, detail: nil)))
        XCTAssertEqual(d.state.savedPages[page]?.saved, #"{"notes":{"kettle":"wait for €30"},"ticked":["kettle"]}"#)
        // Saved in the page's file: the record round-trips.
        let record = try XCTUnwrap(d.state.savedPages[page])
        let decoded = try JSONDecoder().decode(AIPageRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
    }

    func testSavesAreCappedCheckedAndRateLimited() throws {
        let d = enabled()
        let (_, page) = try keptPage(d)
        d.user(.assist(.pageSave(page, "[1,2]")))
        d.user(.assist(.pageSave(page, "not json")))
        d.user(.assist(.pageSave(page, #"{"note":"\#(String(repeating: "x", count: AIPageLimits.saved))"}"#)))
        XCTAssertNil(d.state.savedPages[page]?.saved)
        d.user(.assist(.pageSave(AIPageID("someone-else"), #"{"a":1}"#)))
        XCTAssertNil(d.state.savedPages[AIPageID("someone-else")])
        // Refused saves count against the minute too; the next minute starts afresh.
        d.advance(.seconds(60))
        for n in 0..<AIPageLimits.savesPerMinute { d.user(.assist(.pageSave(page, #"{"n":\#(n)}"#))) }
        XCTAssertEqual(d.state.savedPages[page]?.saved, #"{"n":59}"#)
        d.user(.assist(.pageSave(page, #"{"n":60}"#)))
        XCTAssertEqual(d.state.savedPages[page]?.saved, #"{"n":59}"#, "the sixty-first save in a minute is refused")
        d.advance(.seconds(61))
        d.user(.assist(.pageSave(page, #"{"n":61}"#)))
        XCTAssertEqual(d.state.savedPages[page]?.saved, #"{"n":61}"#)
    }

    // MARK: Weekdays

    func testAPageShownOnChosenWeekdaysIsOutOfTodayOnTheOthersButStaysFindable() throws {
        let d = enabled()
        let (_, page) = try keptPage(d, live: [.schedule(.hourly), .weekdays([2])])
        XCTAssertNotNil(pageRow(d, page), "Monday: shown")
        d.advance(.seconds(86_400))
        XCTAssertNil(pageRow(d, page), "Tuesday: out of Today")
        XCTAssertTrue(d.state.doc.tree.allTabs().contains { d.state.tab($0)?.url == AIPageTab.url(page) }, "the row is still there")
        d.user(.commandBar(.open(.newTab)))
        XCTAssertTrue(d.bar?.tabs.contains { $0.url == AIPageTab.url(page) } == true, "the command bar still finds it")
        d.user(.commandBar(.dismiss))
        // Not archived while it waits for its day.
        d.advance(.seconds(6 * 86_400))
        d.system(.clockTick)
        XCTAssertFalse(d.state.doc.archive.contains { $0.tab.url == AIPageTab.url(page) })
        XCTAssertNotNil(pageRow(d, page), "the next Monday")
        d.user(.assist(.livePage(page, .weekdays(nil))))
        d.advance(.seconds(86_400))
        XCTAssertNotNil(pageRow(d, page), "every day again")
    }

    // MARK: Delete for good

    func testDeletingAConversationForGoodDeletesItsTranscriptPagesAndTheirRows() throws {
        let d = enabled()
        let (conversation, page) = try keptPage(d)
        XCTAssertFalse(d.allTabRows.contains { $0.url == ConversationPage.url(conversation) }, "a conversation has no row (step 8)")
        d.user(.library(.requestDeleteConversation(conversation)))
        let request = try XCTUnwrap(d.view.pendingConversationDeletion)
        XCTAssertEqual(request.pages, 1)
        d.user(.library(.confirmDeleteConversation(conversation, token: request.token, confirmed: true)))
        XCTAssertNil(d.state.savedConversations[conversation])
        XCTAssertNil(d.state.savedPages[page])
        XCTAssertNil(pageRow(d, page), "the kept page's row goes too")
        XCTAssertFalse(d.state.doc.archive.contains { $0.tab.url == AIPageTab.url(page) })
    }

    func testDeletingAnArchivedPageDeletesOnlyThePage() throws {
        let d = enabled()
        let (conversation, page) = try keptPage(d)
        d.user(.tab(.close(.item(try XCTUnwrap(pageRow(d, page)).id))))
        let entry = try XCTUnwrap(d.archive().first { $0.url == AIPageTab.url(page) })
        XCTAssertEqual(entry.deletable, .page)
        XCTAssertEqual(refreshes(d.user(.archive(.restore(entry.id)))), [], "restoring is not refreshing")
        d.user(.tab(.close(.item(try XCTUnwrap(pageRow(d, page)).id))))
        let again = try XCTUnwrap(d.archive().first { $0.url == AIPageTab.url(page) })
        d.user(.archive(.delete(again.id)))
        XCTAssertNil(d.state.savedPages[page])
        XCTAssertNotNil(d.state.savedConversations[conversation])
        XCTAssertNil(d.archive().first { $0.url == AIPageTab.url(page) })
    }

    func testDeletingARefreshingPageStopsItsRefresh() throws {
        let d = enabled()
        let (_, page) = try keptPage(d)
        let run = try XCTUnwrap(refreshes(d.user(.assist(.livePage(page, .refreshNow)))).first)
        d.user(.tab(.close(.item(try XCTUnwrap(pageRow(d, page)).id))))
        let entry = try XCTUnwrap(d.archive().first { $0.url == AIPageTab.url(page) })
        let t = d.user(.archive(.delete(entry.id)))
        XCTAssertTrue(t.effects.contains(.aiStopRefresh(run.run)), "\(t.effects)")
    }

    func testAnArchivedTabIsNotDeletable() throws {
        let d = enabled()
        let tab = d.open("https://example.com/a")
        d.user(.tab(.close(.item(tab))))
        let entry = try XCTUnwrap(d.archive().first { $0.url == url("https://example.com/a") })
        XCTAssertNil(entry.deletable)
        d.user(.archive(.delete(entry.id)))
        XCTAssertNotNil(d.archive().first { $0.url == url("https://example.com/a") })
    }

    // MARK: The command bar

    func testTheCommandBarListsConversationsWithWhatWasSaid() throws {
        let d = enabled()
        let (conversation, _) = try keptPage(d)
        d.user(.commandBar(.open(.newTab)))
        let candidate = try XCTUnwrap(d.bar?.conversations.first)
        XCTAssertEqual(candidate.id, conversation)
        XCTAssertEqual(candidate.title, "盯着这三个商品页的价格，每小时更新一次")
        XCTAssertTrue(candidate.text.contains("Kept."))
        XCTAssertTrue(candidate.text.contains("Price Watch"), "a page's title counts as said")
    }

    func testTheTabToolsListNoArchivedConversationOrPage() throws {
        let d = enabled()
        let (conversation, page) = try keptPage(d)
        _ = conversation
        d.user(.tab(.close(.item(try XCTUnwrap(d.allTabRows.first { $0.url == AIPageTab.url(page) }).id))))
        XCTAssertTrue(d.state.doc.archive.contains { $0.tab.url == AIPageTab.url(page) })
        let archived = d.state.agentArchivedTabs(profile: .default)
        XCTAssertFalse(archived.contains { NativePages.shows($0.url) }, "\(archived.map(\.url))")
        XCTAssertFalse(d.state.agentHistory(profile: .default).contains { NativePages.shows($0.url) })
    }

    func testConversationsGoIntoTheMeaningIndexByTitleAndQuestionsOnly() throws {
        let d = enabled()
        let (conversation, _) = try keptPage(d)
        let items = d.state.searchCorpus()[.default] ?? []
        let entry = try XCTUnwrap(items.first { $0.kind == .conversation })
        XCTAssertEqual(entry.id, conversation.rawValue)
        XCTAssertTrue(entry.title.contains("盯着这三个商品页的价格"))
        XCTAssertFalse(entry.title.contains("Kept."), "the agent's answers stay out: they can quote pages")
        let found = d.state.meaningCandidates(MeaningResults(text: "比价", scope: .commandBar, hits: [MeaningHit(key: "conversation:" + conversation.rawValue, score: 0.9)]), profile: .default)
        XCTAssertEqual(found, [MeaningCandidate(place: .conversation, title: "盯着这三个商品页的价格，每小时更新一次", url: ConversationPage.url(conversation))])
    }
}
