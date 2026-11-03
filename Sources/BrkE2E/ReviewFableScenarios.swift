// Adopted by the parent from the withdrawn claude-fable-5-1 review of a4cc460 (worktree t3-7a0ccbfc). The hostile-page
// probe proved a spoofing surface (synthetic pointerover triggered a preview) and a crash class; it stays as a regression.
import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation

/// Review probes (claude-fable-5-1) for the sidebar-tabs slice. Names start with SidebarTools so the harness enables
/// the loopback GitHub fixture. Each probe records observations as notes; a thrown Check lists the violated expectations.
enum ReviewFableScenarios {
    static let all = [
        Scenario("SidebarToolsReviewHostile", "page script triggers a link preview without hover; userinfo URL; setting-off and tab close dismiss; two profiles plus private", cefOnly: "context-scoped network and hover", hostile),
    ]
    /// Probes the parent has not yet attributed; run them by hand with --only.
    static let unregistered = [
        Scenario("SidebarToolsReviewToken", "typed GitHub token leaves no trace in the data directory or logs; freshness boundary", cefOnly: "native sheet", token),
        Scenario("SidebarToolsReviewMeeting", "non-.ics path, malformed .ics, javascript meeting URL and join feedback afterwards", cefOnly: "native file handling", meeting),
        Scenario("SidebarToolsReviewGlow", "real progress samples; load failure clears progress", cefOnly: "engine callbacks", glow),
        Scenario("SidebarToolsReviewPolling", "preview observer cost with many frames: previews on versus off", cefOnly: "devtools polling", polling),
    ]
    private static func page(_ app: AppUnderTest, _ item: ItemID) -> PageID { PageID(window: app.window!, item: item) }
    private static func panel(_ app: AppUnderTest, _ action: SidebarPanelControlAction) throws {
        let result = try app.send(.sidebarPanel(window: app.window, action: action))
        guard result == .ok else { throw Check(description: "Native panel action failed: \(result)") }
    }
    private static func visiblePopover(_ app: AppUnderTest) throws -> Bool {
        try app.native().appWindows.contains { $0.isVisible && $0.className.contains("Popover") }
    }
    private static func literal(_ text: String) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed), as: UTF8.self)
    }
    private static func previewTarget(_ app: AppUnderTest) -> URL {
        var components = URLComponents(url: app.site.url("sidebar-preview-target"), resolvingAgainstBaseURL: false)!
        components.host = "preview.brk.test"
        return components.url!
    }
    /// A page on source.brk.test with one anchor to the preview target at the given position. Returns the page and its surface frame.
    private static func sourcePage(_ app: AppUnderTest, href: URL, left: Int, top: Int, text: String = "Deliberate hover") throws -> (PageID, CGRect) {
        var source = URLComponents(url: app.site.url("index.html"), resolvingAgainstBaseURL: false)!
        source.host = "source.brk.test"
        let sourceURL = source.url!
        let item = try app.load(sourceURL), id = page(app, item)
        try app.waitForPageInput(id, at: sourceURL)
        try app.evaluate(id, "document.body.innerHTML='<a id=preview style=\\\"position:absolute;left:\(left)px;top:\(top)px;margin:0;display:block;width:300px;height:150px\\\">\(text)</a>';document.getElementById('preview').href=\(try literal(href.absoluteString));document.title='Hover fixture ready'")
        try app.waitUntil("hover fixture DOM ready") { try tab(item, in: app.view())?.title == "Hover fixture ready" }
        try app.waitUntil("isolated hover observer") { try (app.native().pages[id]?.linkPreviewFrameCount ?? 0) > 0 }
        let frame = try app.native().pages[id]!.surfaceFrame!
        return (id, frame)
    }
    private static func setCookie(_ app: AppUnderTest, label: String) throws {
        let url = previewTarget(app)
        let cookieTab = try app.load(url)
        try app.waitForPageInput(page(app, cookieTab), at: url)
        try app.evaluate(page(app, cookieTab), "document.cookie='brkSidebarProfile=\(label);path=/';document.title='cookie \(label) set'")
        try app.waitUntil("cookie marker") { try tab(cookieTab, in: app.view())?.title == "cookie \(label) set" }
    }
    private static func hoverAnchor(_ app: AppUnderTest, _ frame: CGRect, left: Int, top: Int) throws {
        try app.hover(CGPoint(x: frame.minX + 10, y: frame.minY + 10))
        try app.hover(CGPoint(x: frame.minX + CGFloat(left) + 60, y: frame.minY + CGFloat(top) + 60))
    }

    @Sendable static func hostile(_ app: AppUnderTest) throws {
        var findings: [String] = []
        let target = previewTarget(app)
        try setCookie(app, label: "Public")

        // 1. A page script dispatches a synthetic pointerover on an anchor the pointer never touches.
        let (id, frame) = try sourcePage(app, href: target, left: 600, top: 400)
        try app.hover(CGPoint(x: frame.minX + 10, y: frame.minY + 10)); app.sleep(0.5)
        try expect(try app.native().pages[id]?.linkPreviewTitle == nil, "a preview showed before any hover or script")
        let before = app.site.requestCount("/sidebar-preview-target")
        try app.evaluate(id, "document.getElementById('preview').dispatchEvent(new PointerEvent('pointerover',{bubbles:true,composed:true}));document.title='Synthetic pointerover dispatched'")
        try app.waitUntil("synthetic event marker") { try tab(id.item, in: app.view())?.title == "Synthetic pointerover dispatched" }
        var triggered = false
        try? app.waitUntil("script-triggered preview", timeout: 5) {
            triggered = try app.native().pages[id]?.linkPreviewTitle != nil || app.site.requestCount("/sidebar-preview-target") > before
            return triggered
        }
        app.sleep(0.3)
        let facts = try app.native()
        let hostileNote = "hostile pointerover: fetched=\(app.site.requestCount("/sidebar-preview-target") - before) title=\(facts.pages[id]?.linkPreviewTitle ?? "nil") url=\(facts.pages[id]?.linkPreviewURL?.absoluteString ?? "nil") popoverVisible=\(try visiblePopover(app)) error=\(facts.pages[id]?.linkPreviewError ?? "nil")"
        app.note(hostileNote)
        if triggered {
            _ = try? app.panelScreenshot("script-triggered-card")
            findings.append("page script triggered a credentialed preview fetch and a native card without pointer hover (\(hostileNote))")
        }
        try app.press("escape")
        try app.waitUntil("card closed") { try app.native().pages[id]?.linkPreviewTitle == nil }

        // 2. Userinfo in the destination URL is displayed as-is.
        var spoof = URLComponents(url: app.site.url("sidebar-preview-target"), resolvingAgainstBaseURL: false)!
        spoof.user = "accounts.google.com"
        try app.evaluate(id, "document.getElementById('preview').href=\(try literal(spoof.url!.absoluteString));document.getElementById('preview').textContent='Sign in to Google';document.title='Spoof href set'")
        try app.waitUntil("spoof marker") { try tab(id.item, in: app.view())?.title == "Spoof href set" }
        try hoverAnchor(app, frame, left: 600, top: 400)
        var shownURL: URL?
        try? app.waitUntil("spoof card", timeout: 6) { shownURL = try app.native().pages[id]?.linkPreviewURL; return shownURL != nil }
        app.sleep(0.3)
        let spoofNote = "userinfo href: shownURL=\(shownURL?.absoluteString ?? "nil") title=\(try app.native().pages[id]?.linkPreviewTitle ?? "nil") error=\(try app.native().pages[id]?.linkPreviewError ?? "nil")"
        app.note(spoofNote)
        if let shownURL, shownURL.absoluteString.contains("accounts.google.com@") {
            _ = try? app.panelScreenshot("userinfo-card")
            findings.append("card displays a userinfo-bearing URL verbatim (\(spoofNote))")
        }

        // 3. Turning the setting off while a card is visible dismisses it.
        if shownURL != nil {
            try app.dispatch(.tabTools(.preferences(includeFavorites: true, previews: false)))
            app.sleep(0.5)
            let still = try visiblePopover(app), title = try app.native().pages[id]?.linkPreviewTitle
            app.note("setting off while card visible: popoverVisible=\(still) title=\(title ?? "nil")")
            if still || title != nil { findings.append("disabling the preview setting left a visible web link card") }
            try app.dispatch(.tabTools(.preferences(includeFavorites: true, previews: true)))
        }

        // 4. Closing the tab while a card is visible dismisses it.
        try app.evaluate(id, "document.getElementById('preview').href=\(try literal(target.absoluteString));document.title='Target href restored'")
        try app.waitUntil("restore marker") { try tab(id.item, in: app.view())?.title == "Target href restored" }
        try hoverAnchor(app, frame, left: 600, top: 400)
        try app.waitUntil("card for close test", timeout: 8) { try app.native().pages[id]?.linkPreviewTitle == "Public preview destination" }
        try app.dispatch(.tab(.close(.focused)))
        app.sleep(0.6)
        let afterClose = try visiblePopover(app)
        app.note("tab close while card visible: popoverVisible=\(afterClose)")
        if afterClose { findings.append("closing the tab left the web link card visible") }

        // 5. Two public profiles: the second profile's preview must not carry the first profile's cookie.
        try app.dispatch(.profile(.create(name: "Review Profile", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings),
              settings.profiles.contains(where: { $0.profile.name == "Review Profile" }) else { throw Check(description: "review profile missing") }
        let dockBefore = try app.view().dock.count
        try app.dispatch(.sidebar(.openDialog(.newSpace)))
        try app.type("Review Space")
        let pill = try visible(app.native(), .spaceToolsControl("profile")).frame
        _ = try app.send(.captureContextMenu(window: app.window, point: CGPoint(x: pill.midX, y: pill.midY), choose: "Review Profile")); app.sleep(0.5)
        try app.click(.spaceToolsControl("save"))
        try app.waitUntil("second profile space") { try app.view().dock.count == dockBefore + 1 && app.view().urlPill.profile?.name == "Review Profile" }
        let (second, secondFrame) = try sourcePage(app, href: target, left: 40, top: 40)
        let secondBefore = app.site.requestCount("/sidebar-preview-target")
        try hoverAnchor(app, secondFrame, left: 40, top: 40)
        var secondTitle: String?
        try? app.waitUntil("second profile preview", timeout: 8) { secondTitle = try app.native().pages[second]?.linkPreviewTitle; return secondTitle != nil }
        app.note("second profile (no cookie) preview title=\(secondTitle ?? "nil") fetched=\(app.site.requestCount("/sidebar-preview-target") - secondBefore)")
        if secondTitle == nil { findings.append("no preview appeared in the second profile within 8 s") }
        if secondTitle == "Public preview destination" { findings.append("second profile's preview carried the default profile's cookie") }
        try app.press("escape")
        try setCookie(app, label: "Private")
        try app.dispatch(.tab(.focus(second.item)))
        try app.waitForPageInput(second, at: try tab(second.item, in: app.view())!.url!)
        try hoverAnchor(app, secondFrame, left: 40, top: 40)
        var secondLabeled: String?
        try? app.waitUntil("second profile labeled preview", timeout: 8) { secondLabeled = try app.native().pages[second]?.linkPreviewTitle; return secondLabeled != nil }
        app.note("second profile after its own cookie: title=\(secondLabeled ?? "nil")")
        if secondLabeled != "Private preview destination" { findings.append("second profile did not see its own cookie in the preview (\(secondLabeled ?? "nil"))") }
        try app.press("escape")
        try app.dispatch(.tabTools(.jumpSpace(1)))
        try app.waitUntil("default space") { try app.view().urlPill.profile == nil }
        let (first, firstFrame) = try sourcePage(app, href: target, left: 40, top: 40)
        try hoverAnchor(app, firstFrame, left: 40, top: 40)
        var firstTitle: String?
        try? app.waitUntil("default profile preview", timeout: 8) { firstTitle = try app.native().pages[first]?.linkPreviewTitle; return firstTitle != nil }
        app.note("default profile after the second profile set its cookie: title=\(firstTitle ?? "nil")")
        if firstTitle != "Public preview destination" { findings.append("default profile preview did not keep its own cookie (\(firstTitle ?? "nil"))") }
        try app.press("escape")

        // 6. Private window: preview fetched there leaves no byte trace in the data directory after the window closes.
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello), let other = hello.windows.first(where: { $0 != first.window }) else { throw Check(description: "private window missing") }
        let publicWindow = app.window
        app.window = other
        var marker = URLComponents(url: app.site.url("sidebar-preview-target"), resolvingAgainstBaseURL: false)!
        marker.host = "preview.brk.test"; marker.query = "trace=ReviewFablePrivateMarker"
        let (priv, privFrame) = try sourcePage(app, href: marker.url!, left: 40, top: 40)
        try hoverAnchor(app, privFrame, left: 40, top: 40)
        var privTitle: String?
        try? app.waitUntil("private preview", timeout: 8) { privTitle = try app.native().pages[priv]?.linkPreviewTitle; return privTitle != nil }
        app.note("private window preview title=\(privTitle ?? "nil")")
        try app.dispatch(.window(.close))
        app.window = publicWindow
        try app.flush()
        app.sleep(1)
        let hits = scan(app.dataDirectory, for: "ReviewFablePrivateMarker")
        app.note("private marker trace in data directory after close: \(hits.isEmpty ? "none" : hits.joined(separator: ", "))")
        if !hits.isEmpty { findings.append("private preview URL found on disk: \(hits)") }

        if !findings.isEmpty { throw Check(description: "FINDINGS: " + findings.joined(separator: " || ")) }
    }

    @Sendable static func token(_ app: AppUnderTest) throws {
        let secret = "ghp_ReviewFableSecret42XYZ"
        let item = try currentTab(app.view())!.id
        try app.waitForPageInput(page(app, item), at: app.site.url("index.html"))
        try app.dispatch(.tab(.togglePin(.focused)))
        let root = try app.view().favorites.root
        try app.dispatch(.item(.move(item, to: .into(parent: root, index: 0))))
        try app.dispatch(.tabTools(.site(.connectGitHub(favorite: item))))
        try panel(app, .focus(identifier: ViewID.tabTool("repository").identifier))
        try app.type("fixture/repo")
        try app.press("tab")
        try app.type(secret)
        app.note("first responder before Connect: \(try app.native().firstResponder)")
        try panel(app, .button("Connect"))
        try app.waitUntil("HTTP unread badge") { try app.view().favorites.tiles.first?.badge == 2 }
        app.note("status after connect: \(try app.view().favorites.tiles.first?.sourceStatus ?? "nil")")
        _ = try app.advanceClock(seconds: 299)
        let at299 = try app.view().favorites.tiles.first
        _ = try app.advanceClock(seconds: 1)
        let at300 = try app.view().favorites.tiles.first
        app.note("freshness 299s: badge=\(String(describing: at299?.badge)) status=\(at299?.sourceStatus ?? "nil"); 300s: badge=\(String(describing: at300?.badge)) status=\(at300?.sourceStatus ?? "nil")")
        try app.flush()
        app.sleep(0.5)
        let hits = scan(app.dataDirectory, for: secret)
        app.note("token trace after flush: \(hits.isEmpty ? "none" : hits.joined(separator: ", "))")
        try app.restart()
        let hitsAfterRestart = scan(app.dataDirectory, for: secret)
        app.note("token trace after restart: \(hitsAfterRestart.isEmpty ? "none" : hitsAfterRestart.joined(separator: ", ")); badge after restart=\(String(describing: try app.view().favorites.tiles.first?.badge))")
        try expect(hits.isEmpty && hitsAfterRestart.isEmpty, "token persisted: \(hits + hitsAfterRestart)")
    }

    @Sendable static func meeting(_ app: AppUnderTest) throws {
        var findings: [String] = []
        let home = try currentTab(app.view())!.id
        let calendar = try app.load(URL(string: "https://calendar.google.com/")!)
        try app.dispatch(.page(.stop(.focused)))
        let root = try app.view().favorites.root
        try app.dispatch(.item(.move(calendar, to: .into(parent: root, index: 0))))
        try app.dispatch(.tab(.focus(home)))
        try app.waitForPageInput(page(app, home), at: app.site.url("index.html"))
        func tile() throws -> TabRow? { try app.view().favorites.tiles.first { $0.id == calendar } }
        func toast() throws -> String { try app.view().tabTools.toast?.text ?? "nil" }

        let txt = app.dataDirectory.appendingPathComponent("notes.txt")
        try Data("BEGIN:VCALENDAR".utf8).write(to: txt)
        try app.dispatch(.tabTools(.site(.selectCalendar(txt, join: true))))
        app.note("non-.ics path: toast=\(try toast()) sheet=\(try app.native().sheetClass ?? "none")")

        let bad = app.dataDirectory.appendingPathComponent("bad.ics")
        try Data("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n:broken\r\nEND:VEVENT\r\nEND:VCALENDAR".utf8).write(to: bad)
        try app.dispatch(.tabTools(.site(.selectCalendar(bad, join: true))))
        try app.waitUntil("malformed feedback") { try app.view().tabTools.toast?.text.contains("could not be read") == true }
        app.note("malformed .ics: toast=\(try toast()) tileStatus=\(try tile()?.sourceStatus ?? "nil") tileSubtitle=\(try tile()?.subtitle ?? "nil")")
        _ = try app.screenshot("malformed-calendar")

        try app.press("ctrl+cmd+j")
        try app.waitUntil("panel after failure", timeout: 6) { try app.native().sheetClass != nil }
        let afterFailure = try toast()
        app.note("Ctrl+Cmd+J after malformed file: toast=\(afterFailure) sheet=\(try app.native().sheetClass ?? "none")")
        if afterFailure.contains("expired") { findings.append("Ctrl+Cmd+J after a malformed .ics reports 'Calendar expired' although no calendar was ever read (toast: \(afterFailure))") }
        try panel(app, .button("Cancel"))
        try app.waitUntil("panel dismissed") { try app.native().sheetClass == nil }
        app.note("after Cancel: toast=\(try toast()) tileStatus=\(try tile()?.sourceStatus ?? "nil")")

        let now = try app.advanceClock(seconds: 0)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        func date(_ offset: Int64) -> String { formatter.string(from: Date(timeIntervalSince1970: Double(now.milliseconds + offset * 1000) / 1000)) }
        let js = app.dataDirectory.appendingPathComponent("js.ics")
        let ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:\(date(-60))\r\nDTEND:\(date(600))\r\nSUMMARY:Script meeting\r\nURL:javascript:alert(1)\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nDTSTART:\(date(-60))\r\nDTEND:\(date(600))\r\nSUMMARY:File meeting\r\nLOCATION:file:///etc/hosts\r\nEND:VEVENT\r\nEND:VCALENDAR"
        try Data(ics.utf8).write(to: js)
        try app.dispatch(.tabTools(.site(.selectCalendar(js, join: true))))
        try app.waitUntil("join feedback for script/file meetings", timeout: 6) { try app.view().tabTools.toast?.text.contains("No available meeting") == true || app.view().tabTools.toast?.text.contains("could not be read") == true }
        let joined = try currentTab(app.view())
        app.note("javascript:/file: meetings: toast=\(try toast()) currentTab=\(joined?.url?.absoluteString ?? "nil") tileStatus=\(try tile()?.sourceStatus ?? "nil") tileSubtitle=\(try tile()?.subtitle ?? "nil")")
        if joined?.url?.scheme == "javascript" || joined?.url?.isFileURL == true { findings.append("a javascript: or file: meeting URL was opened") }
        if !findings.isEmpty { throw Check(description: "FINDINGS: " + findings.joined(separator: " || ")) }
    }

    @Sendable static func glow(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("held-document")), id = page(app, item)
        try app.waitUntil("real intermediate engine progress") { let p = try app.view().urlPill; return p.loading && p.loadProgress > 0 && p.loadProgress < 1 }
        let samples = try app.native().pages[id]?.loadProgressSamples ?? []
        let pill = try app.view().urlPill
        app.note("held document: pill.loadProgress=\(pill.loadProgress) engine samples=\(samples)")
        app.site.releaseHeldDocument()
        try app.waitUntil("completion clears") { let p = try app.view().urlPill; return !p.loading && p.loadProgress == 0 }
        try app.dispatch(.commandBar(.open(.editCurrent))); try app.dispatch(.commandBar(.submit(app.site.url("fail").absoluteString)))
        try app.waitUntil("failed load settles", timeout: 10) {
            guard case .pageObservations(let values) = try app.send(.pageObservations), let state = values[id] else { return false }
            return !(try app.view().urlPill.loading) && state.committedURL != app.site.url("held-document")
        }
        let after = try app.view().urlPill
        app.note("after dropped connection: loading=\(after.loading) loadProgress=\(after.loadProgress) text=\(after.text ?? "nil") samples=\(try app.native().pages[id]?.loadProgressSamples ?? [])")
        try expect(after.loadProgress == 0 && !after.loading, "failure left progress \(after.loadProgress) loading \(after.loading)")
        _ = try app.screenshot("after-failure")
    }

    @Sendable static func polling(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("index.html")), id = page(app, item)
        try app.waitForPageInput(id, at: app.site.url("index.html"))
        let frame = try app.native().pages[id]!.surfaceFrame!
        try app.hover(CGPoint(x: frame.minX + 5, y: frame.maxY - 5))
        app.sleep(1)
        let singleOn = cpuPercent(seconds: 6)
        let frames = (0..<30).map { _ in "<iframe srcdoc=\"<a href='http://127.0.0.1/x'>x</a>\" style='width:60px;height:40px'></iframe>" }.joined()
        try app.evaluate(id, "document.body.innerHTML=\(try literal(frames));document.title='Frames ready'")
        try app.waitUntil("frames ready") { try tab(item, in: app.view())?.title == "Frames ready" }
        try app.waitUntil("isolated worlds for frames", timeout: 20) { try (app.native().pages[id]?.linkPreviewFrameCount ?? 0) >= 31 }
        try app.hover(CGPoint(x: frame.minX + 5, y: frame.maxY - 5))
        app.sleep(1)
        let manyOn = cpuPercent(seconds: 8)
        try app.dispatch(.tabTools(.preferences(includeFavorites: true, previews: false)))
        app.sleep(1.5)
        let manyOff = cpuPercent(seconds: 8)
        try app.dispatch(.tabTools(.preferences(includeFavorites: true, previews: true)))
        app.note(String(format: "process-tree CPU while idle: 1 frame previews on %.1f%%; 31 frames previews on %.1f%%; 31 frames previews off %.1f%%", singleOn, manyOn, manyOff))
    }

    private static func shell(_ script: String) -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sh"); process.arguments = ["-c", script]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
    /// Seconds of CPU consumed so far by the app and every descendant process.
    private static func cpuSeconds() -> Double {
        let root = Trap.appPID
        let script = "pids=\(root); queue=\(root); while [ -n \"$queue\" ]; do next=''; for p in $queue; do kids=$(pgrep -P $p | tr '\\n' ' '); next=\"$next $kids\"; done; queue=$(echo $next); pids=\"$pids $queue\"; done; ps -o time= -p $(echo $pids | tr ' ' ',')"
        return shell(script).split(whereSeparator: \.isNewline).reduce(0.0) { total, line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Double($0) ?? 0 }
            return total + parts.reversed().enumerated().reduce(0.0) { $0 + $1.element * pow(60, Double($1.offset)) }
        }
    }
    private static func cpuPercent(seconds: Double) -> Double {
        let before = cpuSeconds(); Thread.sleep(forTimeInterval: seconds); let after = cpuSeconds()
        return (after - before) / seconds * 100
    }
    private static func scan(_ directory: URL, for needle: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        let bytes = Data(needle.utf8)
        var hits: [String] = []
        for case let file as URL in enumerator {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true, let data = try? Data(contentsOf: file), data.range(of: bytes) != nil else { continue }
            hits.append(file.path.replacingOccurrences(of: directory.path, with: ""))
        }
        return hits
    }
}
