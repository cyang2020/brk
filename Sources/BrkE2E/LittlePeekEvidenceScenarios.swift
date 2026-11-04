import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Round 4, R4-9: native evidence for Little Arc, Peek and folders the R4-6 review found missing (A083 A084 A085 A087
/// A088 A089 A090).
enum LittlePeekEvidenceScenarios {
    static let all = [
        Scenario("R49-LittleChrome", "Little Arc's header: the host pill edits the address, the chevron lists spaces, no sidebar; it is not restored after a restart", cefOnly: "native Little Arc panel", littleChrome),
        Scenario("R49-OpenIn", "Open In from Little Arc's space list and from Peek with Cmd+O and its button: the page moves, the host closes, history starts over", cefOnly: "native Little Arc and Peek", openIn),
        Scenario("R49-LittleEntry", "Option+Cmd+click opens a link in Little Arc; a link sent with open(1) to a registered copy opens in its Little Arc, cold and warm", cefOnly: "Launch Services and native clicks", littleEntry),
        Scenario("R49-PeekLinks", "a click on a link to another site from a pinned tab and a Favorite opens a Peek; same-site links navigate; a private window gets no Peek", cefOnly: "real page links", peekLinks),
        Scenario("R49-PeekEmail", "Shift+Cmd+E opens the Gmail Peek; Peek's own buttons open a local page as a tab, in a split, and close it", cefOnly: "native Peek", peekEmail),
        Scenario("R49-Folders", "New Nested Folder… from the menu, a click folds and unfolds, Rename… names it, Delete archives every tab inside", cefOnly: "native folder rows and menus", folders),
        Scenario("R49-FoldersAll", "Collapse All and Expand All Folders act on this window and this space only and keep the hierarchy", cefOnly: "two native windows", foldersAll),
    ]

    private typealias S = SidebarReviewScenarios
    private typealias E = SidebarEvidenceScenarios

    static func littleWindows(_ app: AppUnderTest) throws -> [WindowID] {
        try S.windows(app).filter { (try? app.view($0).kind) == .little }
    }
    /// The link in index.html (left 40, top 40) of the window's first card, in window points.
    static func indexLink(_ app: AppUnderTest, _ window: WindowID? = nil) throws -> CGPoint {
        let card = try app.native(window ?? app.window).computed.cards[0].rect
        return CGPoint(x: card.minX + 52, y: card.minY + 48)
    }
    static func historyLength(_ app: AppUnderTest, _ page: PageID, item: ItemID, window: WindowID? = nil) throws -> Int? {
        try app.evaluate(page, "document.title='history:'+history.length")
        var length: Int?
        try app.waitUntil("history length") {
            let title = allTabs(try app.view(window ?? page.window)).first { $0.id == item }?.title ?? ""
            length = title.hasPrefix("history:") ? Int(title.dropFirst(8)) : nil
            return length != nil
        }
        return length
    }
    /// A page on `host` (mapped to the fixture server) whose one link goes to `target`.
    static func linkPage(_ app: AppUnderTest, host: String, target: URL) throws -> (ItemID, URL) {
        var components = URLComponents(url: app.site.url("index.html"), resolvingAgainstBaseURL: false)!
        components.host = host
        components.query = "links=\(host)"
        let url = components.url!
        let item = try app.load(url)
        try app.waitForPageInput(S.page(app, item), at: url)
        let literal = String(decoding: try JSONSerialization.data(withJSONObject: target.absoluteString, options: .fragmentsAllowed), as: UTF8.self)
        try app.evaluate(S.page(app, item), "document.getElementById('next').href=\(literal);document.title='links ready'")
        try app.waitUntil("the link points at \(target)") { try tab(item, in: app.view())?.title == "links ready" }
        return (item, url)
    }
    static func brkTest(_ app: AppUnderTest, _ host: String, _ path: String) -> URL {
        var components = URLComponents(url: app.site.url(path), resolvingAgainstBaseURL: false)!
        components.host = host
        return components.url!
    }

    // MARK: A083

    @Sendable static func littleChrome(_ app: AppUnderTest) throws {
        let standard = app.window!
        let other = try createSpace(app, title: "Little target")
        try app.dispatch(.space(.focus(try app.view().dock[0].id)))
        let little = try S.newWindow(app, "Opt+Cmd+N opens Little Arc", kind: .little) { try app.press("alt+cmd+n") }
        _ = try app.send(.activate(window: little))
        app.window = little
        try app.waitUntil("the bar in Little Arc") { isCommandBar(try app.view(little).overlay) }
        let url = app.site.url("page2.html?little=chrome")
        try app.type(url.absoluteString); try app.press("return")
        var item: ItemID?
        try app.waitUntil("the page in Little Arc") {
            guard case .tab(let row)? = try app.view(little).scratch?.rows.first else { return false }
            item = row.id
            return row.url == url
        }
        try app.waitForPageInput(S.page(app, item!, little), at: url)
        let n = try app.native(little)
        try expect(!isShown(n, .sidebar) && n.computed.sidebar == nil, "Little Arc draws a sidebar")
        try expect(isShown(n, .tabTool("little-host")) && isShown(n, .peekOpenIn), "the header has no host pill or Open In")
        _ = try app.screenshot("little-header", window: little)
        // The host pill edits the address.
        try app.click(.tabTool("little-host"))
        try app.waitUntil("the pill opened the address editor") {
            guard case .commandBar(let bar)? = try app.view(little).overlay else { return false }
            return bar.initialQuery.contains("page2.html")
        }
        try app.press("escape")
        try app.waitUntil("the editor closed") { try app.view(little).overlay == nil }
        // The chevron lists the spaces.
        let open = try visible(app.native(little), .peekOpenIn).frame
        try app.click(at: CGPoint(x: open.maxX - 10, y: open.midY))
        try app.waitUntil("the space list") { isShown(try app.native(little), .tabTool("little-space-\(other)")) }
        _ = try app.screenshot("little-spaces", window: little)
        try app.press("escape")
        app.sleep(0.3)
        try app.flush(); try app.restart()
        try expect(try littleWindows(app).isEmpty, "a Little Arc came back after the restart")
        try expect(!allTabs(try app.view()).contains { $0.url == url }, "the Little Arc page was restored into the window")
        _ = standard
    }

    // MARK: A084

    @Sendable static func openIn(_ app: AppUnderTest) throws {
        let standard = app.window!
        let home = try currentTab(app.view())!.id
        let first = try app.view().space.id
        let other = try createSpace(app, title: "Open target")
        try app.dispatch(.space(.focus(first)))
        try app.waitUntil("first space") { try app.view().space.id == first }
        // Little Arc: two pages of history, then the chevron's list → the other space.
        try app.dispatch(.window(.newLittle(app.site.url("page2.html?openin=start"))))
        var little: WindowID?
        try app.waitUntil("a Little Arc") { little = try littleWindows(app).first; return little != nil }
        var item: ItemID?
        try app.waitUntil("its page") { guard case .tab(let row)? = try app.view(little!).scratch?.rows.first, row.loaded else { return false }; item = row.id; return true }
        try app.waitForPageInput(S.page(app, item!, little!), at: app.site.url("page2.html?openin=start"))
        _ = try app.send(.dispatch(window: little, command: .commandBar(.open(.editCurrent))))
        _ = try app.send(.dispatch(window: little, command: .commandBar(.submit(app.site.url("red.html?openin=moved").absoluteString))))
        try app.waitUntil("navigated in Little Arc") { try E.committed(app, S.page(app, item!, little!)) == app.site.url("red.html?openin=moved") }
        try expect(try historyLength(app, S.page(app, item!, little!), item: item!, window: little) == 2, "the Little Arc page has no history to lose")
        _ = try app.send(.activate(window: little!))
        app.window = little
        let button = try visible(app.native(little), .peekOpenIn).frame
        try app.click(at: CGPoint(x: button.maxX - 10, y: button.midY))
        try app.waitUntil("the space list") { isShown(try app.native(little), .tabTool("little-space-\(other)")) }
        try app.click(.tabTool("little-space-\(other)"))
        app.window = standard
        try app.waitUntil("Little Arc closed") { try littleWindows(app).isEmpty }
        try app.waitUntil("the page at the top of the other space's Today") {
            let v = try app.view(standard)
            return v.space.id == other && tabRows(v.space.today.rows).first?.url == app.site.url("red.html?openin=moved")
        }
        let moved = tabRows(try app.view().space.today.rows).first!.id
        try app.waitForPageInput(S.page(app, moved), at: app.site.url("red.html?openin=moved"))
        try expect(try historyLength(app, S.page(app, moved), item: moved) == 1, "Open In carried the session history")
        app.passed("Little Arc → chevron → other space: moved to its Today, panel closed, history starts over")
        // Peek, then Cmd+O (Open Little Arc or Peek in…): into the current space's Today.
        try app.dispatch(.space(.focus(first)))
        try app.waitUntil("first space") { try app.view().space.id == first }
        try app.dispatch(.tab(.focus(home)))
        try app.waitForPageInput(S.page(app, home), at: app.site.url("index.html"))
        try app.click(at: try indexLink(app), modifiers: "shift")
        try app.waitUntil("a Peek") { if case .peek(let p)? = try app.view().overlay { return p.page != nil } else { return false } }
        try app.press("cmd+o")
        try app.waitUntil("Cmd+O moved the Peek page into Today") { try app.view().overlay == nil && tabRows(app.view().space.today.rows).first?.url == app.site.url("page2.html") }
        // Peek's open-as-tab button.
        try app.dispatch(.tab(.focus(home)))
        try app.waitForPageInput(S.page(app, home), at: app.site.url("index.html"))
        try app.click(at: try indexLink(app), modifiers: "shift")
        try app.waitUntil("a Peek again") { if case .peek(let p)? = try app.view().overlay { return p.page != nil } else { return false } }
        let todayBefore = todayIDs(try app.view()).count
        try app.waitUntil("the Peek buttons") { isShown(try app.native(), .peekOpenIn) }
        try app.click(.peekOpenIn)
        try app.waitUntil("the button opened it as a tab") { try app.view().overlay == nil && todayIDs(app.view()).count == todayBefore + 1 }
        // A folder destination (the command the Open In menu's "Folder:" rows send; no Brk control shows that menu).
        let crate = try E.newFolder(app, "Open box")
        try app.dispatch(.window(.newLittle(app.site.url("page2.html?openin=folder"))))
        try app.waitUntil("a Little Arc") { little = try littleWindows(app).first; return little != nil }
        try app.waitUntil("its page") { guard case .tab(let row)? = try app.view(little!).scratch?.rows.first else { return false }; return row.loaded }
        _ = try app.send(.dispatch(window: little, command: .window(.openInFolder(crate))))
        try app.waitUntil("into the folder") {
            let v = try app.view(standard)
            return E.folder(crate, in: v.space.pinned.rows)?.children.contains { tab($0.id, in: v)?.url == app.site.url("page2.html?openin=folder") } == true
        }
        try expect(try littleWindows(app).isEmpty, "the Little Arc stayed after Open in folder")
    }

    // MARK: A085

    @Sendable static func littleEntry(_ app: AppUnderTest) throws {
        // Option+Cmd+click on a link in a standard window.
        let home = try currentTab(app.view())!.id
        try app.waitForPageInput(S.page(app, home), at: app.site.url("index.html"))
        guard case .settings(let settings) = try app.send(.settings) else { throw Check(description: "settings") }
        try expect(settings.links.optionCommandClickLittleArc && settings.links.externalLinksInLittleArc, "the Little Arc link settings are not on by default")
        try app.click(at: try indexLink(app), modifiers: "alt+cmd")
        var little: WindowID?
        try app.waitUntil("Option+Cmd+click opened Little Arc") {
            little = try littleWindows(app).first { tabRows(try app.view($0).scratch?.rows ?? []).contains { $0.url == app.site.url("page2.html") } }
            return little != nil
        }
        try expect(try app.view().space.today.rows.count == 1 && E.committed(app, S.page(app, home)) == app.site.url("index.html"), "the click also navigated or added a tab")
        _ = try app.send(.dispatch(window: little, command: .window(.close)))
        app.passed("Option+Cmd+click: the link opened in Little Arc, the page stayed")
        try littleFromLaunchServices(app)
    }

    /// A clone of the built bundle under its own bundle id (so no other Brk can receive its links), with the e2e
    /// environment in LSEnvironment, registered with lsregister; `open -a <clone> <url>` hands the URL to it the way
    /// any other app's link does (Launch Services sends the GetURL Apple Event). Unregistered and deleted afterwards;
    /// the user's default browser is read before and after and must not change.
    static func littleFromLaunchServices(_ app: AppUnderTest) throws {
        let bundle = app.executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = app.dataDirectory.appendingPathComponent("links")
        let copy = root.appendingPathComponent("Brk R49 Links.app"), data = root.appendingPathComponent("data")
        let socket = root.appendingPathComponent("c.sock").path
        let bundleID = "dev.brk.e2e.r49." + UUID().uuidString.prefix(8).lowercased()
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let defaultBefore = NativeSystemInput.defaultHandler(for: URL(string: "https://example.com")!)
        try run("/bin/cp", ["-cR", bundle.path, copy.path])
        let plist = copy.appendingPathComponent("Contents/Info.plist").path
        var edits = ["Set :CFBundleIdentifier \(bundleID)", "Set :CFBundleName Brk R49 Links", "Delete :NSDockTilePlugIn"]
        let environment = ["BRK_CONTROL_SOCKET": socket, "BRK_DATA_DIR": data.path, "BRK_TEST_CLOCK": "1",
                           "BRK_START_URL": app.site.url("index.html").absoluteString, "BRK_SUGGEST_URL": app.site.url("suggest").absoluteString]
        edits.append("Delete :LSEnvironment")
        edits.append("Add :LSEnvironment dict")
        for (key, value) in environment.sorted(by: { $0.key < $1.key }) { edits.append("Add :LSEnvironment:\(key) string \(value)") }
        for edit in edits { _ = try? run("/usr/libexec/PlistBuddy", ["-c", edit, plist]) }
        try? FileManager.default.removeItem(at: copy.appendingPathComponent("Contents/PlugIns/BrkDockTile.plugin"))
        try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", copy.path])
        try run(lsregister, ["-f", copy.path])
        let client = ControlClient(path: socket)
        var pid: Int32?
        defer {
            if client.isConnected { _ = try? client.send(.quit, timeout: 5); client.close() }
            if let pid {
                let deadline = uptime() + 15
                while kill(pid, 0) == 0, uptime() < deadline { usleep(200_000) }
                if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            }
            _ = try? run(lsregister, ["-u", copy.path])
            try? FileManager.default.removeItem(at: copy)
        }
        var record = "clone \(copy.path), bundle id \(bundleID)\ndefault https handler before: \(defaultBefore ?? "none")\n"
        func send(_ op: ControlOp) throws -> ControlResult { try client.send(op, timeout: 15) }
        func littleWith(_ query: String) throws -> Bool {
            guard case .hello(let hello) = try send(.hello) else { return false }
            for id in hello.windows {
                guard case .view(let v) = try send(.view(window: id)), v.kind == .little else { continue }
                if tabRows(v.scratch?.rows ?? []).contains(where: { $0.url?.query == query }) { return true }
            }
            return false
        }
        // Cold: nothing of this bundle runs; Launch Services starts it with the link.
        let cold = app.site.url("page2.html?external=cold")
        try run("/usr/bin/open", ["-a", copy.path, cold.absoluteString])
        record += "open -a <clone> \(cold.absoluteString)\n"
        let deadline = uptime() + 40
        while true {
            do { try client.connect(timeout: 0.5); break } catch { if uptime() > deadline { throw Check(description: "the clone never opened its control socket: \(error)") } }
        }
        guard case .hello(let hello) = try send(.hello) else { throw Check(description: "the clone did not answer") }
        pid = hello.pid
        record += "launched by Launch Services: pid \(hello.pid)\n"
        try app.waitUntil("the cold link in the clone's Little Arc", timeout: 30) { try littleWith("external=cold") }
        // Warm: the running clone gets the next one.
        let warm = app.site.url("page2.html?external=warm")
        try run("/usr/bin/open", ["-a", copy.path, warm.absoluteString])
        try app.waitUntil("the warm link in a Little Arc of the same clone") { try littleWith("external=warm") }
        guard case .hello(let again) = try send(.hello), again.pid == hello.pid else { throw Check(description: "a second clone process started") }
        record += "warm link reached pid \(again.pid)\n"
        // A private link stays out: Little Arc opens in the profile's public context only for public links (the
        // clone has no private window, so its Little Arc pages are public; nothing else to check without one).
        let defaultAfter = NativeSystemInput.defaultHandler(for: URL(string: "https://example.com")!)
        record += "default https handler after: \(defaultAfter ?? "none")\n"
        try expect(defaultAfter == defaultBefore, "the default browser changed: \(defaultBefore ?? "none") -> \(defaultAfter ?? "none")")
        if case .hello(let h) = try send(.hello), let little = try h.windows.first(where: { if case .view(let v) = try send(.view(window: $0)) { return v.kind == .little } else { return false } }) {
            let shot = app.shotsDirectory.appendingPathComponent("\(app.scenarioID)-external-little.png")
            _ = try send(.screenshot(window: little, path: shot.path))
        }
        S.log(app, "launch-services.txt", record)
        app.note("A clone under bundle id \(bundleID) took links from /usr/bin/open -a, cold and warm; default https handler unchanged (\(defaultAfter ?? "none")); the clone was unregistered and deleted.")
    }

    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw Check(description: "\(tool) \(arguments.joined(separator: " ")) failed: \(text)") }
        return text
    }

    // MARK: A087

    @Sendable static func peekLinks(_ app: AppUnderTest) throws {
        let target = brkTest(app, "other.brk.test", "page2.html")
        // A pinned tab on one site, its link to another: the click opens a Peek, the pinned page stays.
        let (pinned, pinnedURL) = try linkPage(app, host: "pinned.brk.test", target: target)
        try app.dispatch(.item(.move(pinned, to: .into(parent: try app.view().space.pinned.root, index: 0))))
        try app.dispatch(.tab(.focus(pinned)))
        try app.waitForPageInput(S.page(app, pinned), at: pinnedURL)
        try app.click(at: try indexLink(app))
        try app.waitUntil("a Peek on the other site") { if case .peek(let p)? = try app.view().overlay { return p.tab.url == target } else { return false } }
        try expect(try E.committed(app, S.page(app, pinned)) == pinnedURL, "the pinned tab navigated away")
        _ = try app.screenshot("pinned-peek")
        try app.press("escape")
        try app.waitUntil("Peek closed") { try app.view().overlay == nil }
        // A Favorite: the same.
        let (favorite, favoriteURL) = try linkPage(app, host: "favorite.brk.test", target: target)
        try app.dispatch(.item(.move(favorite, to: .into(parent: try app.view().favorites.root, index: 0))))
        try app.dispatch(.tab(.focus(favorite)))
        try app.waitForPageInput(S.page(app, favorite), at: favoriteURL)
        try app.click(at: try indexLink(app))
        try app.waitUntil("a Peek from the Favorite") { if case .peek(let p)? = try app.view().overlay { return p.tab.url == target } else { return false } }
        try app.press("escape")
        try app.waitUntil("Peek closed") { try app.view().overlay == nil }
        // A same-site link from the pinned tab navigates the tab itself.
        let same = brkTest(app, "pinned.brk.test", "red.html")
        try app.dispatch(.tab(.focus(pinned)))
        try app.waitForPageInput(S.page(app, pinned), at: pinnedURL)
        let literal = String(decoding: try JSONSerialization.data(withJSONObject: same.absoluteString, options: .fragmentsAllowed), as: UTF8.self)
        try app.evaluate(S.page(app, pinned), "document.getElementById('next').href=\(literal);document.title='same ready'")
        try app.waitUntil("same-site link") { try tab(pinned, in: app.view())?.title == "same ready" }
        try app.click(at: try indexLink(app))
        try app.waitUntil("the pinned tab followed its own site's link") { try E.committed(app, S.page(app, pinned)) == same }
        try expect(try app.view().overlay == nil, "a same-site link opened a Peek")
        // A Today tab's link to another site just navigates.
        let (today, _) = try linkPage(app, host: "today.brk.test", target: target)
        try app.click(at: try indexLink(app))
        try app.waitUntil("the Today tab navigated") { try E.committed(app, S.page(app, today)) == target }
        try expect(try app.view().overlay == nil, "a Today tab's link opened a Peek")
        // A private window: Shift+click opens no Peek anywhere.
        let standard = app.window!
        let incognito = try S.newWindow(app, "a private window", kind: .incognito) { try app.press("shift+cmd+n") }
        guard case .loaded(let privateItem) = try app.send(.load(window: incognito, url: app.site.url("index.html"))) else { throw Check(description: "private page") }
        try app.waitForPageInput(S.page(app, privateItem, incognito), at: app.site.url("index.html"))
        app.window = incognito
        try app.click(at: try indexLink(app, incognito), modifiers: "shift")
        app.sleep(1)
        let privateOverlay = try app.view(incognito).overlay
        let isPeek: Bool = if case .peek? = privateOverlay { true } else { false }
        try expect(!isPeek, "a Peek opened in the private window")
        try expect(try app.view(standard).overlay == nil, "the private click opened something in the public window")
        S.log(app, "private-shift-click.txt", "private window after Shift+click: overlay \(String(describing: privateOverlay)); scratch rows \(tabRows(try app.view(incognito).scratch?.rows ?? []).map { $0.url?.absoluteString ?? "-" })\n")
        app.window = standard
    }

    // MARK: A088

    @Sendable static func peekEmail(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        try app.waitForPageInput(S.page(app, home), at: app.site.url("index.html"))
        try app.press("shift+cmd+e")
        var peekPage: PageID?
        try app.waitUntil("Shift+Cmd+E opened a Peek on Gmail") {
            guard case .peek(let p)? = try app.view().overlay else { return false }
            peekPage = p.page
            return p.tab.url == URL(string: "https://mail.google.com/mail/u/0/")!
        }
        if let peekPage { try app.dispatch(.page(.stop(.item(peekPage.item)))) }
        try app.waitUntil("the Peek card and its buttons") { let n = try app.native(); return isShown(n, .peek) && isShown(n, .peekClose) && isShown(n, .peekOpenIn) && isShown(n, .peekSplit) }
        _ = try app.screenshot("email-peek")
        try app.click(.peekClose)
        try app.waitUntil("the close button closed it") { try app.view().overlay == nil }
        try expect(!allTabs(try app.view()).contains { $0.url?.host == "mail.google.com" }, "the Gmail Peek left a tab")
        app.note("The Gmail page itself is a remote site and was stopped at once; the Peek controls are exercised on a local page below instead of a signed-in mailbox.")
        // Peek's buttons on a local page: as a tab, in a split.
        func peekLocal() throws {
            try app.dispatch(.tab(.focus(home)))
            try app.waitForPageInput(S.page(app, home), at: app.site.url("index.html"))
            try app.click(at: try indexLink(app), modifiers: "shift")
            try app.waitUntil("a local Peek") { if case .peek(let p)? = try app.view().overlay { return p.page != nil && p.tab.url == app.site.url("page2.html") } else { return false } }
            try app.waitUntil("its buttons") { isShown(try app.native(), .peekSplit) }
        }
        try peekLocal()
        try app.click(.peekSplit)
        try app.waitUntil("the split button put it beside the page") { let c = try app.view().content; return try c.panes.count == 2 && app.view().overlay == nil }
        try app.dispatch(.split(.closePane))
        try peekLocal()
        try app.click(.peekOpenIn)
        try app.waitUntil("the tab button made it a Today tab") { try app.view().overlay == nil && currentTab(app.view())?.url == app.site.url("page2.html") }
    }

    // MARK: A089

    @Sendable static func folders(_ app: AppUnderTest) throws {
        let a = try E.loadReady(app, "page2.html?folder=a")
        let b = try E.loadReady(app, "page2.html?folder=b")
        let outer = try E.newFolder(app, "Outer")
        try app.dispatch(.item(.move(a, to: .into(parent: outer, index: 0))))
        // New Nested Folder… from the folder's real menu, named by typing.
        try S.contextMenu(app, at: S.centre(try visible(app.native(), .row(outer)).frame), choose: "New Nested Folder…")
        var inner: ItemID?
        try app.waitUntil("a nested folder in rename") {
            inner = E.folder(outer, in: try app.view().space.pinned.rows)?.children.first { $0.kind == .folder }?.id
            return try inner != nil && app.view().renaming == inner
        }
        try app.press("cmd+a"); try app.type("Inner"); try app.press("return")
        try app.waitUntil("Inner named") { E.folder(inner!, in: try app.view().space.pinned.rows)?.title == "Inner" }
        try app.dispatch(.item(.move(b, to: .into(parent: inner!, index: 0))))
        // A click on the row folds and unfolds it.
        try app.click(.row(outer))
        try app.waitUntil("folded") { let n = try app.native(); return try E.folder(outer, in: app.view().space.pinned.rows)?.collapsed == true && !isShown(n, .row(a)) && !isShown(n, .row(inner!)) }
        try app.click(.row(outer))
        try app.waitUntil("unfolded") { let n = try app.native(); return try E.folder(outer, in: app.view().space.pinned.rows)?.collapsed == false && isShown(n, .row(a)) && isShown(n, .row(inner!)) }
        // Rename… from its menu.
        try S.contextMenu(app, at: S.centre(try visible(app.native(), .row(outer)).frame), choose: "Rename…")
        try app.waitUntil("rename field") { try app.view().renaming == outer }
        try app.press("cmd+a"); try app.type("Projects"); try app.press("return")
        try app.waitUntil("renamed") { E.folder(outer, in: try app.view().space.pinned.rows)?.title == "Projects" }
        _ = try app.screenshot("nested")
        // Delete from its menu: the folder, the nested one and both tabs go to the archive.
        try S.contextMenu(app, at: S.centre(try visible(app.native(), .row(outer)).frame), choose: "Delete")
        try app.waitUntil("the folder deleted") { try E.folder(outer, in: app.view().space.pinned.rows) == nil && tab(a, in: app.view()) == nil && tab(b, in: app.view()) == nil }
        try app.dispatch(.library(.open(.archive)))
        guard case .library(let library)? = try app.view().overlay else { throw Check(description: "no archive") }
        let archived = library.archive?.groups.flatMap(\.entries) ?? []
        S.log(app, "archive.txt", archived.map { "\($0.title) \($0.url?.absoluteString ?? "(folder)") \($0.reason)" }.joined(separator: "\n"))
        for path in ["page2.html?folder=a", "page2.html?folder=b"] {
            try expect(archived.contains { $0.url == app.site.url(path) && $0.reason == .containerDeleted }, "\(path) is not archived as container-deleted: \(archived.map { "\($0.url?.absoluteString ?? "-") \($0.reason)" })")
        }
        try expect(try E.folder(inner!, in: app.view().space.pinned.rows) == nil, "the nested folder stayed")
        if case .library? = try app.view().overlay { try app.dispatch(.library(.close)) }
    }

    // MARK: A090

    @Sendable static func foldersAll(_ app: AppUnderTest) throws {
        let a = try E.loadReady(app, "page2.html?all=a")
        let outer = try E.newFolder(app, "Outer")
        try app.dispatch(.item(.move(a, to: .into(parent: outer, index: 0))))
        try app.dispatch(.tabTools(.newNestedFolder(outer)))
        try app.press("cmd+a"); try app.type("Inner"); try app.press("return")
        let inner = E.folder(outer, in: try app.view().space.pinned.rows)!.children.first { $0.kind == .folder }!.id
        let b = try E.loadReady(app, "page2.html?all=b")
        try app.dispatch(.item(.move(b, to: .into(parent: inner, index: 0))))
        func shape(_ rows: [Row]) -> [String] {
            rows.flatMap { row -> [String] in
                switch row {
                case .folder(let f): ["(\(f.id.rawValue)"] + shape(f.children) + [")"]
                default: [row.id.rawValue]
                }
            }
        }
        let hierarchy = shape(try app.view().space.pinned.rows)
        let first = app.window!, space = try app.view().space.id
        let other = try S.newWindow(app, "a second window", kind: .standard) { try app.press("cmd+n") }
        // A second space with its own folder.
        let elsewhere = try createSpace(app, title: "Folders elsewhere")
        let far = try E.newFolder(app, "Far")
        try app.dispatch(.space(.focus(space)))
        try app.waitUntil("first space") { try app.view().space.id == space }
        _ = try app.send(.activate(window: first))
        try app.waitUntil("first window key") { try app.native(first).isKey }
        try app.perform(.menuAction("Collapse All Folders"))
        try app.waitUntil("both folders collapsed here") {
            let rows = try app.view().space.pinned.rows
            return E.folder(outer, in: rows)?.collapsed == true
        }
        try app.dispatch(.item(.toggleFolder(outer)))   // peek inside: the nested folder is collapsed too
        try app.waitUntil("Inner collapsed too") { E.folder(inner, in: try app.view().space.pinned.rows)?.collapsed == true }
        try app.dispatch(.item(.toggleFolder(outer)))
        try expect(E.folder(outer, in: try app.view(other).space.pinned.rows)?.collapsed == false, "the other window's folder collapsed")
        try expect(shape(try app.view().space.pinned.rows) == hierarchy, "Collapse All changed the hierarchy")
        _ = try app.send(.dispatch(window: other, command: .space(.focus(elsewhere))))
        try app.waitUntil("the other window on the other space") { try app.view(other).space.id == elsewhere }
        try expect(E.folder(far, in: try app.view(other).space.pinned.rows)?.collapsed == false, "the other space's folder collapsed")
        try app.perform(.menuAction("Expand All Folders"))
        try app.waitUntil("expanded here") {
            let rows = try app.view().space.pinned.rows
            return E.folder(outer, in: rows)?.collapsed == false && E.folder(inner, in: rows)?.collapsed == false
        }
        try expect(shape(try app.view().space.pinned.rows) == hierarchy, "Expand All changed the hierarchy")
        _ = try app.screenshot("expanded")
    }
}
