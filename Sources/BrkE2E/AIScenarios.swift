import BrkBase
import BrkControl
import BrkDomain
import Foundation

/// Every AI scenario launches only Tests/Fixtures/ai-provider. Pages and filesystem destinations are owned fixtures.
enum AIScenarios {
    static let all = [
        Scenario("AICommand", "Opt+Cmd+G asks with streaming, cancel and actionable failure", cefOnly: "native command bar", command),
        Scenario("AIPage", "main-frame question attribution excludes controls, frames and private pages", cefOnly: "CEF main document", page),
        Scenario("AIHover", "deliberate real link hover summarizes and cancellation closes hidden readers", cefOnly: "CEF status hover", hover),
        Scenario("AIOrganize", "Today plan creates groups, undo restores order and restart preserves tabs", cefOnly: "native Today groups", organize),
        Scenario("AIDownload", "completed fixture downloads rename without overwriting a collision", cefOnly: "CEF downloads", download),
        Scenario("AIInstant", "proposed destination loads in a hidden reader before opening", cefOnly: "CEF reachability", instant),
        Scenario("AIBrowse", "selected sources use owning profile cookies, citations and close all readers", cefOnly: "CEF hidden pages", browse),
        Scenario("AITranslate", "text node translation preserves DOM, controls, events and never-translate settings", cefOnly: "CEF isolated world", translate),
        Scenario("AIMax", "native Max pane persists delivered switches and provider choice without an API key", cefOnly: "native settings", maxPane),
        Scenario("AIQuit", "quit terminates and reaps a running fixture CLI", cefOnly: "native shutdown", quit),
    ]
    private static func enable(_ app: AppUnderTest, _ features: [AIFeature] = AIFeature.allCases) throws {
        for feature in features { try app.dispatch(.settings(.max(.feature(feature, true)))) }
    }
    private static func answer(_ app: AppUnderTest, contains expected: String) throws {
        try app.waitUntil("AI answer containing \(expected)", timeout: 15) { try app.view().ai?.busy == false && app.view().ai?.text.contains(expected) == true }
    }
    private static func load(_ app: AppUnderTest, _ path: String = "ai.html") throws -> PageID {
        let url = app.site.url(path), item = try app.load(url), page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: url)
        return page
    }
    private static func calls(_ app: AppUnderTest) -> [[String: Any]] {
        let data = (try? String(contentsOf: app.dataDirectory.appendingPathComponent("ai-fixture.jsonl"), encoding: .utf8)) ?? ""
        return data.split(whereSeparator: \.isNewline).compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }
    private static func readersClosed(_ app: AppUnderTest) throws -> Bool {
        guard case .pageLog(let log) = try app.send(.pageLog) else { return false }
        let readers = log.filter { $0.page.item.rawValue.hasPrefix("ai-") }
        let created = Set(readers.filter { $0.kind == .created }.map { BrowserToken(page: $0.page, generation: $0.generation) })
        let closed = Set(readers.filter { $0.kind == .closed }.map { BrowserToken(page: $0.page, generation: $0.generation) })
        return !created.isEmpty && created.isSubset(of: closed)
    }
    private static func command(_ app: AppUnderTest) throws {
        try enable(app)
        try app.press("option+cmd+g")
        try app.waitUntil("Ask command bar") { if case .commandBar(let bar)? = try app.view().overlay { return bar.aiMode == .question }; return false }
        try app.type("fixture:stream"); try app.press("return")
        try app.waitUntil("partial output before completion") { try app.view().ai?.busy == true && app.view().ai?.text == "first\n" }
        _ = try app.screenshot("AICommand-stream")
        try answer(app, contains: "second")
        try app.dispatch(.assist(.ask("fixture:hang")))
        try app.waitUntil("fixture started") { calls(app).contains { ($0["prompt"] as? String) == "fixture:hang" } }
        let pid = calls(app).last!["pid"] as! Int32
        try app.dispatch(.assist(.cancel))
        try app.waitUntil("cancelled process reaped") { kill(pid, 0) == -1 && errno == ESRCH }
        try answer(app, contains: "cancelled")
        try app.dispatch(.assist(.ask("fixture:fail")))
        try answer(app, contains: "23")
        try expect(try app.view().ai!.text.contains("Terminal"), "failure lacks an action")
        try app.dispatch(.assist(.ask("fixture:empty")))
        try answer(app, contains: "no answer")
    }
    private static func page(_ app: AppUnderTest) throws {
        try enable(app)
        let source = try load(app)
        try app.dispatch(.assist(.askPage("What color is the river?")))
        try answer(app, contains: "river is blue")
        let result = try app.view().ai!
        try expect(result.sources.map(\.url) == [app.site.url("ai.html")], "source attribution changed")
        let prompt = calls(app).last!["prompt"] as! String
        for secret in ["FORM_SECRET", "TEXTAREA_SECRET", "HIDDEN_SENTINEL", "PRIVATE_MARKER", "SUBFRAME_SECRET"] { try expect(!prompt.contains(secret), "extraction leaked \(secret)") }
        _ = try app.screenshot("AIPage-answer")
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
        let privateWindow = try hello.windows.first { try app.view($0).kind == .incognito }!
        let count = calls(app).count
        _ = try app.send(.dispatch(window: privateWindow, command: .assist(.askPage("Do not read"))))
        try expect(try app.view(privateWindow).ai!.text.contains("private"), "private page was accepted")
        try expect(calls(app).count == count, "private page reached the provider")
        try expect(try app.view(source.window).ai?.sources.count == 1, "other window answer changed")
    }
    private static func hover(_ app: AppUnderTest) throws {
        try enable(app)
        let source = try load(app)
        let card = try visible(app.native(), .card(0)).frame
        try app.hover(CGPoint(x: card.minX + 90, y: card.minY + 48))
        try answer(app, contains: "Fixture preview")
        try expect(try currentTab(app.view())?.id == source.item, "preview took tab focus")
        try app.waitUntil("AI readers closed", timeout: 10) { try readersClosed(app) }
        try expect(try readersClosed(app), "preview retained reader")
        _ = try app.screenshot("AIHover-preview")
        try app.hover(CGPoint(x: card.minX + 90, y: card.minY + 160))
        try app.evaluate(source, "document.querySelector('#preview').href='http://127.0.0.1:9/unavailable'")
        try app.hover(CGPoint(x: card.minX + 90, y: card.minY + 48))
        try answer(app, contains: "unavailable")
        try app.waitUntil("AI readers closed", timeout: 10) { try readersClosed(app) }
        try expect(try readersClosed(app), "unavailable reader remained")
    }
    private static func organize(_ app: AppUnderTest) throws {
        try enable(app); try app.dispatch(.settings(.max(.tidyTabs(true))))
        _ = try load(app); _ = try load(app, "ai-source.html")
        let before = todayIDs(try app.view())
        try app.dispatch(.assist(.organizeToday)); try answer(app, contains: "Organized")
        guard case .folder(let group)? = try app.view().space.today.rows.first else { throw Check(description: "Today group missing") }
        try expect(group.children.map(\.id) == before, "plan moved wrong tabs")
        _ = try app.screenshot("AIOrganize-group")
        try app.dispatch(.assist(.undoOrganize))
        try expect(todayIDs(try app.view()) == before, "undo changed tab order")
        try app.dispatch(.assist(.organizeToday)); try answer(app, contains: "Organized")
        try app.flush(); try app.restart()
        guard case .folder(let restored)? = try app.view().space.today.rows.first else { throw Check(description: "Today group not restored") }
        try expect(restored.children.map(\.id) == before, "group children changed on restart")
    }
    private static func download(_ app: AppUnderTest) throws {
        try enable(app)
        try app.dispatch(.settings(.max(.renamePinnedTabs(true))))
        let home = try currentTab(app.view())!.id
        try app.dispatch(.commandBar(.open(.editCurrent)))
        try app.dispatch(.commandBar(.submit(app.site.url("ai-source.html").absoluteString)))
        try waitForTitle(app, home, "AI Source")
        try app.dispatch(.tab(.togglePin(.item(home))))
        try waitForTitle(app, home, "Fixture Tab")
        let directory = app.dataDirectory.appendingPathComponent("ai-downloads")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = directory.appendingPathComponent("Reading.txt")
        try Data("KEEP".utf8).write(to: existing)
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(directory.path))))
        _ = try app.load(app.site.url("download"))
        try app.dispatch(.library(.open(.downloads)))
        try app.waitUntil("download renamed") {
            guard case .library(let library)? = try app.view().overlay else { return false }
            return library.downloads.first?.filename == "Reading (1).txt" && library.downloads.first?.state == .finished
        }
        let renamed = directory.appendingPathComponent("Reading (1).txt")
        try expect(try Data(contentsOf: existing) == Data("KEEP".utf8), "collision overwritten")
        try expect(try Data(contentsOf: renamed) == Data("fixture download\n".utf8), "renamed bytes changed")
        _ = try app.screenshot("AIDownload-renamed")
    }
    private static func instant(_ app: AppUnderTest) throws {
        try enable(app)
        let destination = app.site.url("ai-source.html")
        try app.dispatch(.assist(.instant(destination.absoluteString)))
        try answer(app, contains: "Opened")
        try app.waitUntil("validated destination opened") { try currentTab(app.view())?.url == destination }
        try app.waitUntil("AI readers closed", timeout: 10) { try readersClosed(app) }
        try expect(try readersClosed(app), "instant reader leaked")
        try app.dispatch(.assist(.instant("invalid reply")))
        try answer(app, contains: "Search Instead")
        _ = try app.screenshot("AIInstant-fallback")
    }
    private static func browse(_ app: AppUnderTest) throws {
        try enable(app)
        let page = try load(app)
        try app.evaluate(page, "document.cookie='ai_scope=fixture-public;path=/'")
        let sources = [app.site.url("ai-source.html"), app.site.url("ai.html")]
        try app.dispatch(.assist(.browse(question: "Compare the river facts", sources: sources)))
        try answer(app, contains: "[2]")
        let result = try app.view().ai!
        try expect(result.sources.map(\.url) == sources, "citations refer to unsupplied sources")
        let prompt = calls(app).last!["prompt"] as! String
        try expect(prompt.contains("ai_scope=fixture-public"), "hidden reader lost owning profile cookies")
        try expect(!prompt.contains("FORM_SECRET") && !prompt.contains("SUBFRAME_SECRET"), "browse leaked controls or frames")
        try expect(try currentTab(app.view())?.id == page.item, "browse stole selection")
        try app.waitUntil("AI readers closed", timeout: 10) { try readersClosed(app) }
        try expect(try readersClosed(app), "browse readers leaked")
        var closed = false
        try app.waitUntil("hidden readers close") {
            if case .pageLog(let log) = try app.send(.pageLog) { closed = log.filter { $0.page.item.rawValue.hasPrefix("ai-") && $0.kind == .closed }.count == sources.count }
            return closed
        }
        _ = try app.screenshot("AIBrowse-citations")
    }
    private static func translate(_ app: AppUnderTest) throws {
        try enable(app)
        let page = try load(app)
        try app.evaluate(page, "window.keptInput=document.querySelector('#field');window.keptButton=document.querySelector('#button');keptInput.value='USER_EDIT';keptButton.click();")
        try app.dispatch(.assist(.translate("English"))); try answer(app, contains: "Page translated")
        try app.evaluate(page, "document.title=(document.querySelector('#greeting').textContent==='Hello World'&&keptInput===document.querySelector('#field')&&keptInput.value==='USER_EDIT'&&keptButton.dataset.clicked==='yes'&&window.fixtureIdentity.value===17&&document.querySelector('iframe').contentDocument.body.textContent.includes('SUBFRAME_SECRET'))?'ai-dom-ok':'ai-dom-bad'")
        try waitForTitle(app, page.item, "ai-dom-ok")
        _ = try app.screenshot("AITranslate-dom")
        try app.dispatch(.assist(.neverTranslateSite)); try app.flush(); try app.restart()
        try app.waitForPageInput(page, at: app.site.url("ai.html"))
        let count = calls(app).count
        try app.dispatch(.assist(.translate("English"))); try answer(app, contains: "never translates")
        try expect(calls(app).count == count, "never-translate site invoked CLI")
    }
    private static func maxPane(_ app: AppUnderTest) throws {
        try enable(app)
        try app.dispatch(.settings(.max(.provider(.codex))))
        try app.dispatch(.settings(.openPane(.max)))
        var settingsWindow: AppWindowFact?
        try app.waitUntil("visible owned settings window") {
            settingsWindow = try app.native().appWindows.first { $0.className == "NSWindow" && $0.isVisible }
            return settingsWindow != nil
        }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(settingsWindow!.number), app.shotsDirectory.appendingPathComponent("AIMax-settings.png").path]
        try capture.run(); capture.waitUntilExit()
        try expect(capture.terminationStatus == 0, "settings capture failed")
        try app.flush(); try app.restart()
        guard case .settings(let settings) = try app.send(.settings) else { throw Check(description: "no settings") }
        let max = settings.max.settings
        try expect(max.provider == .codex && AIFeature.allCases.allSatisfy(max.enabled), "Max switches did not persist")
        try expect(!String(decoding: Data(contentsOf: app.dataDirectory.appendingPathComponent("state.json")), as: UTF8.self).lowercased().contains("apikey"), "API key field persisted")
    }
    private static func quit(_ app: AppUnderTest) throws {
        try enable(app)
        try app.dispatch(.assist(.ask("fixture:hang")))
        try app.waitUntil("fixture CLI to hang") { calls(app).last?["prompt"] as? String == "fixture:hang" }
        let pid = calls(app).last!["pid"] as! Int32
        _ = try app.quit()
        try expect(kill(pid, 0) == -1 && errno == ESRCH, "quit left provider PID \(pid) alive")
    }
}
