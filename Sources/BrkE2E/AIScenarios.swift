import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation

/// Every AI scenario launches only Tests/Fixtures/ai-provider. Pages and filesystem destinations are owned fixtures.
enum AIScenarios {
    static let all = [
        Scenario("AICommand", "Opt+Cmd+G asks with streaming, cancel and actionable failure", cefOnly: "native command bar", command),
        Scenario("AIPage", "main-frame question attribution excludes controls, frames and private pages", cefOnly: "CEF main document", page),
        Scenario("AIHover", "Shift held over a link opens Arc's answer card under it; a plain hover does not; leaving closes the readers", cefOnly: "CEF status hover", hover),
        Scenario("AIOrganize", "Today's divider Tidy groups Today, the undo toast restores order and restart preserves tabs", cefOnly: "native Today groups", organize),
        Scenario("AIDownload", "completed fixture downloads rename without overwriting a collision", cefOnly: "CEF downloads", download),
        Scenario("AIInstant", "Shift+Return in the command bar heads Today with the searching row, opens the verified result, fails in place", cefOnly: "CEF reachability", instant),
        Scenario("AIAskRow", "a question in the command bar lists the Ask row that asks the local tool; the tool's name then Tab asks it", cefOnly: "native command bar", askRow),
        Scenario("AITidyTitles", "a Today tab dragged into Pinned gets its tidy title, as Arc's P47-a", cefOnly: "native sidebar drag", tidyTitles),
        Scenario("AIBrowse", "selected sources use owning profile cookies, citations and close all readers", cefOnly: "CEF hidden pages", browse),
        Scenario("AITranslate", "page menu Translate to English, the pill's Translated and popover, Use Original's undo toast and ⌘Z, never-translate", cefOnly: "CEF isolated world", translate),
        Scenario("AIMax", "native Max pane persists delivered switches and provider choice without an API key", cefOnly: "native settings", maxPane),
        Scenario("AIQuit", "quit reaps active and already-cancelled fixture CLIs", cefOnly: "native shutdown", quit),
    ]
    private static func enable(_ app: AppUnderTest, _ features: [AIFeature] = AIFeature.allCases) throws {
        for feature in features { try app.dispatch(.settings(.max(.feature(feature, true)))) }
    }
    private static func answer(_ app: AppUnderTest, contains expected: String) throws {
        try app.waitUntil("AI answer containing \(expected)", timeout: 15) {
            let facts = try app.native()
            try expect(!facts.appWindows.contains { $0.isKey && $0.className.contains("CefNSWindow") }, "AI work activated a CEF window")
            return try app.view().ai?.busy == false && app.view().ai?.text.contains(expected) == true
        }
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
    /// Max's 5-Second Previews (Arc P45-a): a plain hover over an ordinary link opens nothing; with Shift held for
    /// about two seconds the card opens under the link (the page's own link box, 6 points left, 6.5 below), shows the
    /// summary's title and details, and closes when the pointer leaves link and card.
    private static func hover(_ app: AppUnderTest) throws {
        try enable(app)
        let source = try load(app)
        try app.evaluate(source, "document.querySelector('#preview').addEventListener('mouseover',e=>document.title=e.isTrusted?'ai-trusted-hover':'ai-untrusted-hover')")
        let card = try visible(app.native(), .card(0)).frame
        let link = CGPoint(x: card.minX + 90, y: card.minY + 48)
        try app.hover(link)
        try waitForTitle(app, source.item, "ai-trusted-hover")
        app.sleep(3)
        try expect(try app.view().aiPreview == nil, "a plain hover over an ordinary link opened the preview card")
        try app.hover(CGPoint(x: card.minX + 90, y: card.minY + 200))
        app.sleep(0.4)
        try NativeSystemInput.setShift(true)
        defer { try? NativeSystemInput.setShift(false) }
        try app.hover(link)
        try app.waitUntil("Arc's card with the summary", timeout: 20) {
            guard let preview = try app.view().aiPreview else { return false }
            return !preview.busy && preview.title.hasPrefix("Fixture preview") && !preview.details.isEmpty
        }
        try NativeSystemInput.setShift(false)
        let preview = try app.view().aiPreview!
        try expect(try app.view().ai == nil, "the summary went to the answer panel")
        let shown = try visible(app.native(), .aiControl("preview-card")).frame
        guard let box = preview.link else { throw Check(description: "the page did not report the hovered link's box") }
        try expect(abs(shown.minX - (card.minX + box.minX - 6)) <= 1.5 && abs(shown.minY - (card.minY + box.maxY + 6.5)) <= 1.5,
                   "card at \(shown), link box \(box) in the page at \(card.origin)")
        try expect(abs(shown.width - 299) <= 0.5, "card width \(shown.width)")
        try expect(try currentTab(app.view())?.id == source.item, "preview took tab focus")
        try app.waitUntil("AI readers closed", timeout: 10) { try readersClosed(app) }
        _ = try app.screenshot("AIHover-card")
        try app.hover(CGPoint(x: card.minX + 600, y: card.minY + 420))
        try app.waitUntil("card closes off the link") { try app.view().aiPreview == nil }
        try app.evaluate(source, "document.querySelector('#preview').href='http://127.0.0.1:9/unavailable'")
        try NativeSystemInput.setShift(true)
        try app.hover(link)
        try app.waitUntil("the card says the source is unavailable", timeout: 20) { try app.view().aiPreview?.failure?.contains("unavailable") == true }
        try NativeSystemInput.setShift(false)
        try app.waitUntil("AI readers closed", timeout: 10) { try readersClosed(app) }
        try expect(try readersClosed(app), "unavailable reader remained")
    }
    /// Max's Tidy Tabs (Arc P46-b): with seven Today tabs the divider shows Tidy; a click groups Today (the fixture's
    /// plan: one Reading group), Arc's undo toast undoes it, and the groups survive a restart.
    private static func organize(_ app: AppUnderTest) throws {
        try enable(app); try app.dispatch(.settings(.max(.tidyTabs(true))))
        // The divider between Pinned and Today (where Tidy and Clear live) shows once Pinned has a row.
        try app.dispatch(.tab(.togglePin(.item(currentTab(app.view())!.id))))
        _ = try load(app)
        var n = 0
        while todayIDs(try app.view()).count < 7 { n += 1; _ = try load(app, "ai-source.html?tab=\(n)") }
        try app.waitUntil("Tidy offered with seven Today tabs") { try app.view().space.today.canTidy }
        let before = todayIDs(try app.view())
        let clear = try visible(app.native(), .todayClear).frame
        try app.hover(CGPoint(x: clear.minX - 60, y: clear.midY))
        app.sleep(0.4)
        _ = try app.screenshot("AIOrganize-tidy")
        try app.click(.todayTidy)
        try app.waitUntil("Today grouped", timeout: 15) { if case .folder? = try app.view().space.today.rows.first { return true }; return false }
        guard case .folder(let group)? = try app.view().space.today.rows.first else { throw Check(description: "Today group missing") }
        try expect(group.group && group.children.map(\.id) == before, "plan moved wrong tabs")
        try expect(try app.view().tabTools.toast?.text == "Tidied Tabs! Use" && app.view().tabTools.toast?.keycap == "⌘Z", "no undo toast")
        try expect(try app.view().ai == nil, "Tidy opened the answer panel")
        _ = try app.screenshot("AIOrganize-group")
        try app.dispatch(.tabTools(.undoToast))   // the toast's ⌘Z
        try expect(todayIDs(try app.view()) == before, "undo changed tab order")
        try app.click(.todayTidy)
        try app.waitUntil("Today grouped again", timeout: 15) { if case .folder? = try app.view().space.today.rows.first { return true }; return false }
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
    private static func openBar(_ app: AppUnderTest) throws {
        try app.press("cmd+t")
        try app.waitUntil("command bar") { if case .commandBar? = try app.view().overlay { return true }; return false }
    }
    /// Max's Instant Links (Arc P48-a): Shift+Return on a web search closes the bar and heads Today with "Searching
    /// the web for you…" while the tool's answer is verified in a hidden reader, then the result opens as a Today tab;
    /// a reply with no safe address leaves "Oops, something went wrong." until its × is clicked.
    private static func instant(_ app: AppUnderTest) throws {
        try enable(app)
        let destination = app.site.url("ai-source.html")
        try openBar(app)
        try app.type("open \(destination.absoluteString) slowly")
        try app.press("shift+return")
        try app.waitUntil("the searching row heads Today") {
            guard case .tab(let row)? = try app.view().space.today.rows.first else { return false }
            return row.instant == .searching && row.title == "Searching the web for you…"
        }
        try expect(try app.view().overlay == nil && app.view().ai == nil, "the bar stayed or the answer panel opened")
        _ = try app.screenshot("AIInstant-row")
        try app.waitUntil("validated destination opened", timeout: 20) { try currentTab(app.view())?.url == destination }
        try expect(!(try app.view().space.today.rows.contains { if case .tab(let t) = $0 { t.instant != nil } else { false } }), "the row stayed")
        try app.waitUntil("AI readers closed", timeout: 10) { try readersClosed(app) }
        try expect(try readersClosed(app), "instant reader leaked")
        try openBar(app)
        try app.type("nothing to open here")
        try app.press("shift+return")
        try app.waitUntil("Arc's failed row", timeout: 15) {
            guard case .tab(let row)? = try app.view().space.today.rows.first else { return false }
            return row.instant == .failed && row.title == "Oops, something went wrong."
        }
        guard case .tab(let failed)? = try app.view().space.today.rows.first else { throw Check(description: "failed row missing") }
        _ = try app.screenshot("AIInstant-failed")
        try app.click(.rowClose(failed.id))
        try app.waitUntil("the × removes the row") { try app.view().space.today.rows.first?.id != failed.id }
        // Return alone still searches as before.
        try openBar(app)
        try app.type("plain search words")
        try app.press("return")
        try app.waitUntil("plain Return searched") { try currentTab(app.view())?.url?.absoluteString.contains("plain") == true }
    }
    /// Arc's Ask ChatGPT → row (P49) with the local tool's name: a question lists it; choosing it asks the tool.
    /// Typing the tool's name and Tab opens the bar's question mode (Arc: start typing "ChatGPT", hit Tab).
    private static func askRow(_ app: AppUnderTest) throws {
        try enable(app)
        try openBar(app)
        try app.type("how do browsers render fonts")
        guard case .commandBar(let bar)? = try app.view().overlay, let provider = bar.askProvider else { throw Check(description: "no Ask provider in the bar") }
        try app.waitUntil("the Ask row") { try app.native().actual[ViewID.aiControl("ask-row").identifier]?.hidden == false }
        _ = try app.screenshot("AIAskRow-bar")
        try app.click(.aiControl("ask-row"))
        try answer(app, contains: "Fixture answer")
        try expect(calls(app).last?["prompt"] as? String == "how do browsers render fonts", "the Ask row asked something else")
        try openBar(app)
        try app.type(String(provider.prefix(3)))
        try app.press("tab")
        try app.waitUntil("question mode after \(provider) and Tab") { if case .commandBar(let bar)? = try app.view().overlay { return bar.aiMode == .question }; return false }
        try app.press("escape")
    }
    /// Max's Tidy Tab Titles (Arc P47-a): a Today tab dragged into Pinned gets the tool's shorter title.
    private static func tidyTitles(_ app: AppUnderTest) throws {
        try enable(app)
        // Pinned gets a row to drop under before Tidy Tab Titles is on.
        let home = try currentTab(app.view())!.id
        try app.dispatch(.tab(.togglePin(.item(home))))
        try app.dispatch(.settings(.max(.renamePinnedTabs(true))))
        let tab = try load(app, "ai-source.html").item
        try waitForTitle(app, tab, "AI Source")
        let facts = try app.native()
        let from = try visible(facts, .row(tab)).frame, pinned = try visible(facts, .row(home)).frame
        let drop = CGPoint(x: pinned.midX, y: pinned.midY + pinned.height * 0.3)
        try app.perform(.pointer(window: app.window, phase: .down, point: CGPoint(x: from.midX, y: from.midY)))
        try app.perform(.pointer(window: app.window, phase: .dragged, point: CGPoint(x: from.midX + 8, y: from.midY - 4)))
        try app.perform(.pointer(window: app.window, phase: .dragged, point: CGPoint(x: (from.midX + drop.x) / 2, y: (from.midY + drop.y) / 2)))
        try app.perform(.pointer(window: app.window, phase: .dragged, point: drop))
        app.sleep(0.3)
        try app.perform(.pointer(window: app.window, phase: .up, point: drop))
        try app.waitUntil("dragged into Pinned") { tabRows(try app.view().space.pinned.rows).contains { $0.id == tab } }
        try waitForTitle(app, tab, "Fixture Tab", timeout: 15)
        _ = try app.screenshot("AITidyTitles-pinned")
        try app.flush(); try app.restart()
        try expect(try BrkE2E.tab(tab, in: app.view())?.title == "Fixture Tab", "the tidy title did not survive a restart")
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
    /// Arc's translation (P50): the French page offers Translation Available on the pill; the page menu's Translate
    /// to English (after Cast…) translates in place keeping the DOM; the pill reads Translated, opens Arc's popover;
    /// Use Original brings the French back with "Translated back to French! Use ⌘Z to undo."; ⌘Z re-translates;
    /// Never Translate This Site restores the page and holds after a restart without asking the tool.
    private static func translate(_ app: AppUnderTest) throws {
        try enable(app)
        let page = try load(app)
        try app.evaluate(page, "window.keptInput=document.querySelector('#field');window.keptButton=document.querySelector('#button');keptInput.value='USER_EDIT';keptButton.click();")
        try app.waitUntil("Translation Available on the pill") { try app.view().urlPill.translation == .available }
        _ = try visible(app.native(), .aiControl("pill-translation"))
        let card = try visible(app.native(), .card(0)).frame
        guard case .menuItems(let titles) = try app.send(.captureContextMenu(window: app.window, point: CGPoint(x: card.minX + 500, y: card.minY + 115), choose: "Translate to English")) else {
            throw Check(description: "no page menu")
        }
        guard let cast = titles.firstIndex(of: "Cast…"), titles.indices.contains(cast + 1), titles[cast + 1] == "Translate to English" else {
            throw Check(description: "Translate to English is not after Cast…: \(titles)")
        }
        try app.waitUntil("Translated on the pill", timeout: 30) { try app.view().urlPill.translation == .translated(from: "French") }
        try expect(try app.view().ai == nil, "translation opened the answer panel")
        try app.evaluate(page, "document.title=(document.querySelector('#greeting').textContent==='Hello World'&&keptInput===document.querySelector('#field')&&keptInput.value==='USER_EDIT'&&keptButton.dataset.clicked==='yes'&&window.fixtureIdentity.value===17&&document.querySelector('iframe').contentDocument.body.textContent.includes('SUBFRAME_SECRET'))?'ai-dom-ok':'ai-dom-bad'")
        try waitForTitle(app, page.item, "ai-dom-ok")
        _ = try app.screenshot("AITranslate-translated")
        try app.click(.aiControl("pill-translation"))
        var popover: AppWindowFact?
        try app.waitUntil("Arc's translation popover") {
            popover = try app.native().appWindows.first { $0.className.contains("Popover") && $0.isVisible }
            return popover != nil
        }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(popover!.number), app.shotsDirectory.appendingPathComponent("AITranslate-popover.png").path]
        try capture.run(); capture.waitUntilExit()
        try app.click(.aiControl("translation-use-original"))
        try app.waitUntil("Use Original's toast") { try app.view().tabTools.toast?.text == "Translated back to French! Use" && app.view().tabTools.toast?.keycap == "⌘Z" }
        try greeting(app, page, "Bonjour Monde", "ai-original")
        try expect(try app.view().urlPill.translation == .available, "the pill still says Translated")
        _ = try app.screenshot("AITranslate-original")
        try app.dispatch(.tabTools(.undoToast))   // the toast's ⌘Z
        try greeting(app, page, "Hello World", "ai-again")
        let count = calls(app).count
        try app.dispatch(.assist(.neverTranslateSite))
        try greeting(app, page, "Bonjour Monde", "ai-never")
        try expect(try app.view().urlPill.translation == nil, "a never-translated site still offers translation")
        try app.flush(); try app.restart()
        try app.waitForPageInput(page, at: app.site.url("ai.html"))
        try app.dispatch(.assist(.translate("English")))
        try app.waitUntil("refused for the site") { try app.view().tabTools.toast?.text.contains("never translates") == true }
        try expect(calls(app).count == count, "never-translate site invoked CLI")
    }
    /// The swap of translated and own text runs in the page after the command: the heading is read until it shows.
    private static func greeting(_ app: AppUnderTest, _ page: PageID, _ text: String, _ tag: String) throws {
        try app.waitUntil("the heading reads \(text)", timeout: 10) {
            try app.evaluate(page, "document.title=document.querySelector('#greeting').textContent==='\(text)'?'\(tag)':'\(tag)-not'")
            app.sleep(0.3)
            return try BrkE2E.tab(page.item, in: app.view())?.title == tag
        }
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
        let cancelled = calls(app).last!["pid"] as! Int32
        try app.dispatch(.assist(.cancel))
        try app.dispatch(.assist(.ask("fixture:hang")))
        try app.waitUntil("second fixture CLI to hang") { calls(app).filter { $0["prompt"] as? String == "fixture:hang" }.count == 2 }
        let active = calls(app).last!["pid"] as! Int32
        _ = try app.quit()
        for pid in [cancelled, active] { try expect(kill(pid, 0) == -1 && errno == ESRCH, "quit left provider PID \(pid) alive") }
    }
}
