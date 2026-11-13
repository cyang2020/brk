import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// What a person does on a web page, with real input only: clicks and right clicks posted to the window server, keys
/// at the HID tap. The control socket sets up (loads the fixture, sets the theme and the appearance, has the page call
/// a dialog) and reads state; it never makes the step being tested. Every step runs once in light; in dark each menu,
/// sheet and the find bar is opened again, checked to be drawn dark and closed: the user's Mac is dark and this one
/// light, and three dark-only bugs reached the user on 2026-11-12.
enum PageRealScenarios {
    static let all = [
        Scenario("PageReal-Menus", "real right clicks on a page, a link and an image pick rows of their menus (Back, Open Link in New Tab, Open Image in New Tab, Translate); alert, confirm, prompt and beforeunload answered with real keys and clicks; the menus and sheets drawn light and dark",
                 cefOnly: "Chromium's context menus and page dialogs", menus),
        Scenario("PageReal-Keys", "real keys and clicks on a page: the find bar (typing, Return, Shift-Return, its arrows, Escape, ×), zoom keys, Print and Save Page As opened and cancelled, a download from a link; the find bar and sheets drawn light and dark",
                 cefOnly: "Chromium's find, zoom, outputs and downloads", keys),
    ]

    // MARK: Real input

    /// A window point (top-left content coordinates) on the screen (top-left origin, as mouse events take it).
    private static func screen(_ app: AppUnderTest, _ point: CGPoint) throws -> CGPoint {
        let frame = try app.native().windowFrame
        return CGPoint(x: frame.minX + point.x, y: CGDisplayBounds(CGMainDisplayID()).height - frame.maxY + point.y)
    }

    private static func pid(_ app: AppUnderTest) throws -> Int32 { try XCTUnwrapValue(app.hello?.pid) }

    /// Brk is the active app with its window (or that window's sheet) key, so window-server input reaches it.
    private static func front(_ app: AppUnderTest) throws {
        try app.perform(.activateApp(window: try XCTUnwrapValue(app.window)))
        try app.waitUntil("Brk active with its window or sheet key", timeout: 4) {
            let facts = try app.native()
            return facts.appActive == true && (facts.isKey || facts.sheetClass != nil)
        }
    }

    /// A real click (or right click) at a screen point, posted only while one of this Brk's windows (or its sheet) is
    /// the frontmost window there.
    private static func click(_ app: AppUnderTest, screen at: CGPoint, right: Bool = false) throws {
        try front(app)
        guard PhysicalPointer.frontmost(at: at)?.pid == (try pid(app)) else {
            throw Check(description: "another window is in front of Brk at \(at) (\(String(describing: PhysicalPointer.frontmost(at: at)))); nothing posted")
        }
        try PhysicalPointer.post(clickAt: at, right: right)
    }

    private static func click(_ app: AppUnderTest, _ point: CGPoint, right: Bool = false) throws {
        try click(app, screen: try screen(app, point), right: right)
    }

    /// A key chord at the HID tap, as the keyboard sends it, once Brk is in front.
    private static func key(_ app: AppUnderTest, _ modifiers: Modifiers, _ key: Key) throws {
        try front(app)
        try NativeSystemInput.postSystemWide(KeyChord(modifiers, key))
        usleep(150_000)
    }

    /// Text typed as a keyboard types it, into whatever has Brk's focus (a sheet's field or the find bar).
    private static func type(_ app: AppUnderTest, _ text: String) throws {
        try front(app)
        try PhysicalKeys.strike(text)
        usleep(150_000)
    }

    // MARK: Pictures

    /// RGBA bytes of a screen rect (top-left origin) from a fresh capture saved as `<scenario>-<name>.png`: menus are
    /// windows of their own that the control socket's screenshots leave out. Refused while another app's window covers
    /// part of the rect: the picture is whatever the shared screen shows there.
    private static func capture(_ app: AppUnderTest, _ rect: CGRect, _ name: String) throws -> (bytes: [UInt8], width: Int) {
        try expectUncovered(app, rect, name)
        let url = app.shotsDirectory.appendingPathComponent("\(app.scenarioID)-\(name).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))", url.path]
        try process.run(); process.waitUntilExit()
        return try bytes(of: url)
    }

    private static func bytes(of url: URL) throws -> (bytes: [UInt8], width: Int) {
        guard let provider = CGDataProvider(url: url as CFURL),
              let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw Check(description: "\(url.lastPathComponent) unreadable")
        }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw Check(description: "no bitmap context") }
        return (bytes, image.width)
    }

    /// The median brightness (0 to 255) of RGBA bytes: a menu's or a sheet's background, past its text.
    private static func median(_ bytes: [UInt8]) -> Int {
        var values: [Int] = []
        for i in stride(from: 0, to: bytes.count - 3, by: 4) { values.append((Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3) }
        values.sort()
        return values.isEmpty ? 0 : values[values.count / 2]
    }

    /// Light things are light and dark things dark: the background of a menu, sheet or the find bar drawn in `scheme`.
    private static func expectDrawn(_ what: String, brightness: Int, in scheme: Scheme) throws {
        try expect(scheme == .dark ? brightness < 110 : brightness > 150, "\(what) is drawn with brightness \(brightness) in \(scheme)")
    }

    /// How many pixels of RGBA bytes stand more than 90 levels from `background`: a word's glyphs, which a caret alone
    /// (about 2 by 36 pixels at 2x) never reaches.
    private static func inked(_ bytes: [UInt8], from background: Int) -> Int {
        var count = 0
        for i in stride(from: 0, to: bytes.count - 3, by: 4) where abs((Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3 - background) > 90 { count += 1 }
        return count
    }

    /// Throws unless this run's Brk owns the frontmost window (its menus included) at the middle and near each corner of
    /// a screen rect (top-left origin).
    private static func expectUncovered(_ app: AppUnderTest, _ rect: CGRect, _ what: String) throws {
        let pid = try pid(app)
        let inner = rect.insetBy(dx: min(12, rect.width / 4), dy: min(12, rect.height / 4))
        for point in [CGPoint(x: inner.midX, y: inner.midY), CGPoint(x: inner.minX, y: inner.minY), CGPoint(x: inner.maxX, y: inner.minY),
                      CGPoint(x: inner.minX, y: inner.maxY), CGPoint(x: inner.maxX, y: inner.maxY)] {
            let owner = NativeSystemInput.frontOwner(at: point)
            guard owner?.pid == pid else {
                throw Check(description: "another window (\(owner?.name ?? "none")) is in front of Brk's \(what) at \(point): no picture taken")
            }
        }
    }

    // MARK: Menus

    /// After a real right click: waits for the menu, checks it is drawn in `scheme`, then picks its row `row` with a real
    /// click (`nil`: a real Escape). Returns the menu's rows and its height on screen. Nothing here asks the app anything
    /// while the menu is up: it tracks inside a main-queue job, so the control socket answers only once it has closed.
    @discardableResult
    private static func choose(_ app: AppUnderTest, _ row: String?, in scheme: Scheme, shot: String) throws -> (rows: [String], height: Double) {
        let pid = try pid(app)
        var frame: CGRect?, rows: [(title: String, frame: CGRect, enabled: Bool)] = []
        let deadline = uptime() + 6
        while uptime() < deadline {
            frame = NativeSystemInput.openMenuFrame(pid: pid)
            rows = frame.map { NativeSystemInput.openMenuRows(pid: pid, in: $0) } ?? []
            if frame != nil, !rows.isEmpty { break }
            usleep(100_000)
        }
        guard let frame else { throw Check(description: "no menu opened for \(shot)") }
        defer {
            if NativeSystemInput.openMenuFrame(pid: pid) != nil { PhysicalKeys.press(KeyChord([], .escape), pid: pid) }
        }
        guard !rows.isEmpty else {
            try NativeSystemInput.postSystemWide(KeyChord([], .escape))
            throw Check(description: "the \(shot) menu is on screen at \(frame) but Accessibility lists no rows")
        }
        usleep(250_000)   // the menu's fade-in
        let titles = rows.map(\.title)
        let picture = try capture(app, frame.insetBy(dx: 6, dy: 6), "\(scheme)-\(shot)")
        if let row {
            guard let target = rows.first(where: { $0.title == row }), target.enabled else {
                try NativeSystemInput.postSystemWide(KeyChord([], .escape))
                throw Check(description: "the \(shot) menu has no enabled \(row): \(rows.map { "\($0.title)\($0.enabled ? "" : " (off)")" })")
            }
            let point = CGPoint(x: target.frame.midX, y: target.frame.midY)
            guard frame.contains(point) else { throw Check(description: "\(row) at \(point) is outside its menu \(frame)") }
            try PhysicalPointer.post(clickAt: point)
        } else {
            try NativeSystemInput.postSystemWide(KeyChord([], .escape))
        }
        let closed = uptime() + 4
        while NativeSystemInput.openMenuFrame(pid: pid) != nil, uptime() < closed { usleep(100_000) }
        try expect(NativeSystemInput.openMenuFrame(pid: pid) == nil, "the \(shot) menu stayed open after \(row ?? "Escape")")
        try expectDrawn("the \(shot) menu", brightness: median(picture.bytes), in: scheme)
        return (titles, frame.height)
    }

    // MARK: Page facts

    private static func current(_ app: AppUnderTest) throws -> TabRow { try XCTUnwrapValue(currentTab(app.view())) }

    /// The centre of a page element in window coordinates, read back through the page's title.
    private static func element(_ app: AppUnderTest, _ page: PageID, _ selector: String) throws -> CGPoint {
        let text = try read(app, page, "(r=>Math.round(r.left+r.width/2)+','+Math.round(r.top+r.height/2))(document.querySelector('\(selector)').getBoundingClientRect())")
        let parts = text.split(separator: ",").compactMap { Double($0) }
        try expect(parts.count == 2, "no place for \(selector): \(text)")
        let surface = try XCTUnwrapValue(try app.native().pages[page]?.surfaceFrame)
        return CGPoint(x: surface.minX + parts[0], y: surface.minY + parts[1])
    }

    /// A point of the page where nothing is: below the fixture's content.
    private static func blank(_ app: AppUnderTest, _ page: PageID) throws -> CGPoint {
        let surface = try XCTUnwrapValue(try app.native().pages[page]?.surfaceFrame)
        return CGPoint(x: surface.midX + 120, y: surface.maxY - 60)
    }

    /// What the page reports through its title for a script expression.
    private static func read(_ app: AppUnderTest, _ page: PageID, _ expression: String) throws -> String {
        let marker = "read" + String(UUID().uuidString.prefix(6))
        try app.evaluate(page, "document.title='\(marker):'+(\(expression))")
        var out = ""
        try app.waitUntil("the page's \(expression)") {
            let title = try current(app).title
            guard title.hasPrefix(marker + ":") else { return false }
            out = String(title.dropFirst(marker.count + 1)); return true
        }
        return out
    }

    private static func waitURL(_ app: AppUnderTest, _ url: URL, _ what: String, timeout: Double = 10) throws {
        try app.waitUntil(what, timeout: timeout) { try current(app).url == url }
    }

    /// The current Space on a theme that follows macOS's light or dark mode, as every theme made in the theme editor or
    /// imported from Arc with a light and a dark style does (the user's). A fresh profile's default theme resolves a
    /// light palette even when macOS is dark, so using it for both passes never exercised the bar's dark colors.
    private static func followSystemTheme(_ app: AppUnderTest) throws {
        var theme = SpaceTheme.default
        var pair = ThemeVariants(legacy: theme)
        pair.selection = .auto
        theme.variants = pair
        try app.dispatch(.space(.update(try app.view().space.id, title: nil, icon: nil, theme: theme)))
    }

    private static func scheme(_ app: AppUnderTest, _ scheme: Scheme) throws {
        try app.perform(.simulateSystemAppearance(scheme))
        try app.waitUntil("the app and the Space's theme drawn \(scheme)") {
            let appearance = try app.native().effectiveAppearance, theme = try app.view().theme.scheme
            return appearance == scheme.rawValue && theme == scheme
        }
    }

    // MARK: PageReal-Menus

    @Sendable static func menus(_ app: AppUnderTest) throws {
        try app.requireCEF("real menus")
        defer { try? app.perform(.simulateSystemAppearance(nil)) }
        try followSystemTheme(app)
        let start = app.site.url("page-real.html")
        let item = try app.load(start)
        let page = PageID(window: try XCTUnwrapValue(app.window), item: item)
        try app.waitForPageInput(page, at: start)
        try scheme(app, .light)
        try contextMenus(app, page, start)
        try dialogs(app, page)
        try beforeUnload(app, page)
        try scheme(app, .dark)
        try drawnDark(app, page, start)
        try translate(app)
        // The current tab-close path does not ask a guarded page (the two-phase close is tracked separately). Its
        // browser must still close; another is left for the quit after this scenario, which must not wait on it either.
        let closing = try guardedTab(app, "close=1")
        try key(app, .command, .w)
        try app.waitUntil("the guarded tab gone") { !allTabs(try app.view()).contains { $0.id == closing.item } }
        try app.waitUntil("the guarded tab's browser closed", timeout: 6) { try app.pageLog().contains { $0.page == closing && $0.kind == .closed } }
        _ = try guardedTab(app, "quit=1")
        app.passed("⌘W closed a guarded page's browser")
    }

    /// A new tab on the guarded fixture, with a real click in it so Chromium would ask before it goes.
    private static func guardedTab(_ app: AppUnderTest, _ query: String) throws -> PageID {
        let url = app.site.url("page-real.html?guard=1&\(query)")
        let page = PageID(window: try XCTUnwrapValue(app.window), item: try app.load(url))
        try app.waitForPageInput(page, at: url)
        try click(app, try blank(app, page))
        return page
    }

    /// The page back on `url` (setup between steps).
    private static func go(_ app: AppUnderTest, _ page: PageID, _ url: URL) throws {
        guard try current(app).url != url else { return }
        try app.evaluate(page, "location.href=\(String(decoding: try JSONEncoder().encode(url.absoluteString), as: UTF8.self))")
        try app.waitForPageInput(page, at: url)
    }

    /// The page, link and image menus, each from a real right click, a row picked with a real click; Escape closes one.
    private static func contextMenus(_ app: AppUnderTest, _ page: PageID, _ start: URL) throws {
        let appearance = Scheme.light
        try go(app, page, start)
        // A real click on the link gives the tab a page to go back to.
        let linked = app.site.url("page2.html?from=link")
        try click(app, try element(app, page, "#link"))
        try waitURL(app, linked, "the linked page after a real click")
        try app.waitForPageInput(page, at: linked)
        // High on the page: Escape closes the menu and nothing happens.
        let tabs = allTabs(try app.view()).count
        let surface = try XCTUnwrapValue(try app.native().pages[page]?.surfaceFrame)
        try click(app, CGPoint(x: surface.midX + 120, y: surface.minY + 80), right: true)
        let high = try choose(app, nil, in: appearance, shot: "escape")
        app.sleep(0.4)
        try expect(try current(app).url == linked && allTabs(try app.view()).count == tabs, "Escape on the page menu did something")
        // Low on the page (near the screen's bottom) the same menu shows whole: one that kept its top at the pointer ran
        // off the screen, showed a scroll arrow and hid its last rows.
        try click(app, try blank(app, page), right: true)
        let low = try choose(app, "Back", in: appearance, shot: "page-menu")
        try expect(low.rows == high.rows && abs(low.height - high.height) < 2,
                   "the page menu opened low is cut off: \(low.height) pt tall against \(high.height) pt opened high")
        try waitURL(app, start, "Back from the page menu")
        try app.waitForPageInput(page, at: start)
        app.passed("Escape closed the page menu; opened low it showed whole and its Back went back")

        // Open Link in New Tab: a new tab with the link, the page stays.
        try click(app, try element(app, page, "#link"), right: true)
        let linkRows = try choose(app, "Open Link in New Tab", in: appearance, shot: "link-menu")
        try app.waitUntil("a tab for the link") { allTabs(try app.view()).contains { $0.url == linked } }
        try expect(try current(app).url == start, "Open Link in New Tab left the page")
        try closeOthers(app, keeping: page)

        // Open Image in New Tab.
        let image = app.site.url("rim-red.png")
        try click(app, try element(app, page, "#img"), right: true)
        let imageRows = try choose(app, "Open Image in New Tab", in: appearance, shot: "image-menu")
        try app.waitUntil("a tab for the image") { allTabs(try app.view()).contains { $0.url == image } }
        try closeOthers(app, keeping: page)
        app.note("page menu: \(high.rows.joined(separator: ", ")); link menu: \(linkRows.rows.joined(separator: ", ")); image menu: \(imageRows.rows.joined(separator: ", "))")
        app.passed("link and image menu rows opened tabs")
    }

    /// Closes every tab of Today but `page`'s (setup between steps, not a step).
    private static func closeOthers(_ app: AppUnderTest, keeping page: PageID) throws {
        for tab in allTabs(try app.view()) where tab.id != page.item { try app.dispatch(.tab(.close(.item(tab.id)))) }
        try app.dispatch(.tab(.focus(page.item)))
        try app.waitUntil("only the fixture tab left") { allTabs(try app.view()).map(\.id) == [page.item] }
    }

    /// The sheet's button titled `title`, clicked with the real pointer.
    private static func clickButton(_ app: AppUnderTest, _ title: String) throws {
        let pid = try pid(app)
        var frame: CGRect?
        try app.waitUntil("the sheet's \(title)") { frame = NativeSystemInput.frame(pid: pid, title: title, roles: ["AXButton"]); return frame != nil }
        let button = try XCTUnwrapValue(frame)
        try click(app, screen: CGPoint(x: button.midX, y: button.midY))
    }

    private static func sheet(_ app: AppUnderTest) throws -> Bool { try app.native().sheetClass != nil }

    /// The words of the open sheet, as Accessibility reads them.
    private static func sheetTexts(_ app: AppUnderTest) throws -> [String] {
        let pid = try pid(app)
        guard let frame = NativeSystemInput.sheetFrame(pid: pid) else { return [] }
        return NativeSystemInput.staticTexts(pid: pid).filter { frame.intersects($0.frame) }.map(\.text)
    }

    /// The sheet as the screen shows it (a save panel's contents are drawn by another process), checked to be drawn
    /// in `scheme` and kept as a picture.
    private static func sheetDrawn(_ app: AppUnderTest, _ name: String, _ appearance: Scheme) throws {
        app.sleep(0.5)   // the sheet's slide-in
        try front(app)
        let pid = try pid(app)
        var frame: CGRect?
        try app.waitUntil("the \(name) sheet's place on screen") { frame = NativeSystemInput.sheetFrame(pid: pid); return frame != nil }
        let picture = try capture(app, try XCTUnwrapValue(frame).insetBy(dx: 8, dy: 8), "\(appearance)-\(name)")
        try expectDrawn("the \(name) sheet", brightness: median(picture.bytes), in: appearance)
    }

    /// alert, confirm and prompt from the page, answered with real Return, clicks, typing and Escape.
    private static func dialogs(_ app: AppUnderTest, _ page: PageID) throws {
        let appearance = Scheme.light
        try app.evaluate(page, "setTimeout(()=>{alert('Hello from the page');document.title='alert:closed'},0)")
        try app.waitUntil("the alert's sheet") { try sheet(app) }
        try sheetDrawn(app, "alert", appearance)
        // Titled by the site that asks, as in Chrome, not by the page's whole address.
        let site = app.site.url("page-real.html")
        let asker = "\(site.host ?? ""):\(site.port ?? 0) says"
        let alertWords = try sheetTexts(app)
        try expect(alertWords.contains(asker), "the alert is not titled \(asker): \(alertWords)")
        try key(app, [], .returnKey)
        try app.waitUntil("Return answers the alert") { try current(app).title == "alert:closed" }
        try expect(try !sheet(app), "the alert's sheet stayed")

        try app.evaluate(page, "setTimeout(()=>{document.title='confirm:'+confirm('Keep going?')},0)")
        try app.waitUntil("the confirm's sheet") { try sheet(app) }
        try clickButton(app, "Cancel")
        try app.waitUntil("a click on Cancel answers false") { try current(app).title == "confirm:false" }
        try app.evaluate(page, "setTimeout(()=>{document.title='confirm:'+confirm('Keep going?')},0)")
        try app.waitUntil("the second confirm's sheet") { try sheet(app) }
        try clickButton(app, "OK")
        try app.waitUntil("a click on OK answers true") { try current(app).title == "confirm:true" }

        try app.evaluate(page, "setTimeout(()=>{document.title='prompt:'+prompt('Your name?','Brk')},0)")
        try app.waitUntil("the prompt's sheet") { try sheet(app) }
        try sheetDrawn(app, "prompt", appearance)
        try type(app, "Ada")
        try key(app, [], .returnKey)
        var answer = ""
        try app.waitUntil("typing replaces the default text and Return answers") { answer = try current(app).title; return answer.hasPrefix("prompt:") }
        try expect(answer == "prompt:Ada", "the prompt answered \(answer)")
        try app.evaluate(page, "setTimeout(()=>{document.title='prompt:'+prompt('Your name?','Brk')},0)")
        try app.waitUntil("the second prompt's sheet") { try sheet(app) }
        try key(app, [], .escape)
        try app.waitUntil("Escape answers null") { try current(app).title == "prompt:null" }
        app.passed("alert, confirm and prompt answered with real keys and clicks")
    }

    /// The fixture again with ?guard=1, used with a real click: Chromium asks only on a page the person has used.
    private static func openGuarded(_ app: AppUnderTest, _ page: PageID) throws -> URL {
        let guarded = app.site.url("page-real.html?guard=1")
        try go(app, page, guarded)
        try click(app, try blank(app, page))
        return guarded
    }

    /// A page that asks before it goes: Reload with a real ⌘R, Stay keeps it, Reload reloads; a real click on a link
    /// asks Leave this page?, Leave goes.
    private static func beforeUnload(_ app: AppUnderTest, _ page: PageID) throws {
        let guarded = try openGuarded(app, page)
        try app.evaluate(page, "marker='kept'")
        try key(app, .command, .r)
        try app.waitUntil("Reload this page? after ⌘R") { try sheet(app) }
        try sheetDrawn(app, "reload-asks", .light)
        let words = try sheetTexts(app)
        try expect(words.contains("Reload this page?") && words.contains("Changes you made may not be saved."), "the reload sheet says \(words)")
        try clickButton(app, "Stay")
        try app.waitUntil("Stay closes the sheet") { try !sheet(app) }
        app.sleep(0.5)
        try expect(try read(app, page, "marker") == "kept", "Stay reloaded the page")
        try key(app, .command, .r)
        try app.waitUntil("⌘R asks again after Stay", timeout: 5) { try sheet(app) }
        try clickButton(app, "Reload")
        try app.waitUntil("Reload reloads the page") { try !sheet(app) }
        try app.waitForPageInput(page, at: guarded)
        try app.waitUntil("a fresh document") { try read(app, page, "marker") == "fresh" }
        app.passed("⌘R on a guarded page asked; Stay kept it, Reload reloaded")

        let away = app.site.url("page2.html?from=away")
        try click(app, try element(app, page, "#away"))
        try app.waitUntil("Leave this page? after a real click on a link") { try sheet(app) }
        try key(app, [], .returnKey)
        try waitURL(app, away, "Leave goes to the link")
        try app.waitForPageInput(page, at: away)
        app.passed("a link on a guarded page asked; Return left")
    }

    /// In dark: the page, link and image menus each opened with a real right click and closed with Escape; the alert,
    /// the prompt and Reload this page? each opened and answered. Each must be drawn dark.
    private static func drawnDark(_ app: AppUnderTest, _ page: PageID, _ start: URL) throws {
        try go(app, page, start)
        try click(app, try blank(app, page), right: true)
        try choose(app, nil, in: .dark, shot: "page-menu")
        try click(app, try element(app, page, "#link"), right: true)
        try choose(app, nil, in: .dark, shot: "link-menu")
        try click(app, try element(app, page, "#img"), right: true)
        try choose(app, nil, in: .dark, shot: "image-menu")

        try app.evaluate(page, "setTimeout(()=>{alert('Hello from the page');document.title='alert:closed'},0)")
        try app.waitUntil("the alert's sheet") { try sheet(app) }
        try sheetDrawn(app, "alert", .dark)
        try key(app, [], .returnKey)
        try app.waitUntil("Return answers the alert") { try current(app).title == "alert:closed" }
        try app.evaluate(page, "setTimeout(()=>{document.title='prompt:'+prompt('Your name?','Brk')},0)")
        try app.waitUntil("the prompt's sheet") { try sheet(app) }
        try sheetDrawn(app, "prompt", .dark)
        try key(app, [], .escape)
        try app.waitUntil("Escape answers null") { try current(app).title == "prompt:null" }

        _ = try openGuarded(app, page)
        try key(app, .command, .r)
        try app.waitUntil("Reload this page? after ⌘R") { try sheet(app) }
        try sheetDrawn(app, "reload-asks", .dark)
        try clickButton(app, "Stay")
        try app.waitUntil("Stay closes the sheet") { try !sheet(app) }
        app.passed("dark: the page, link and image menus, the alert, the prompt and Reload this page? are drawn dark")
    }

    /// Translate to English from the page menu of a French page, with the fixture agent, in dark.
    private static func translate(_ app: AppUnderTest) throws {
        // Max's Translate Pages is off on a fresh profile; the row then only says where to turn it on.
        try app.dispatch(.settings(.max(.feature(.translation, true))))
        let french = app.site.url("lang-french.html")
        let item = try app.load(french)
        let page = PageID(window: try XCTUnwrapValue(app.window), item: item)
        try app.waitForPageInput(page, at: french)
        // The menu offers the row once the page's language is known, as the pill does.
        try app.waitUntil("the page's language known", timeout: 10) { try app.view().urlPill.translation == .available }
        try click(app, try blank(app, page), right: true)
        let rows = try choose(app, "Translate to English", in: .dark, shot: "translate-menu")
        try app.waitUntil("the page translated", timeout: 30) { try app.view().urlPill.translation == .translated(from: "French") }
        app.passed("Translate to English from the page menu translated the page (\(rows.rows.count) rows)")
    }

    // MARK: PageReal-Keys

    @Sendable static func keys(_ app: AppUnderTest) throws {
        try app.requireCEF("real keys")
        defer { try? app.perform(.simulateSystemAppearance(nil)) }
        try followSystemTheme(app)
        let start = app.site.url("page-real.html")
        let item = try app.load(start)
        let page = PageID(window: try XCTUnwrapValue(app.window), item: item)
        try app.waitForPageInput(page, at: start)
        try click(app, try blank(app, page))
        for appearance in [Scheme.light, .dark] {
            try scheme(app, appearance)
            try find(app, page, appearance)
            try outputs(app, page, appearance)
        }
        try zoom(app, page)
        try download(app, page)
    }

    private static func find(_ app: AppUnderTest) throws -> FindSnapshot? { try app.view().find }

    private static func matches(_ app: AppUnderTest, ordinal: Int, _ what: String) throws {
        try app.waitUntil(what) { let f = try find(app); return f?.count == 3 && f?.searching == false && f?.ordinal == ordinal }
    }

    /// The find bar with real typing. In light: Return, Shift-Return, its arrows and Escape; in dark only the bar drawn
    /// and ×. The bar must be drawn in the appearance and its query must stand out from it.
    private static func find(_ app: AppUnderTest, _ page: PageID, _ appearance: Scheme) throws {
        try key(app, .command, .f)
        try app.waitUntil("the find bar's field focused") { try app.native().firstResponder.hasSuffix(":" + ViewID.findQuery.identifier) }
        try type(app, "needle")
        try matches(app, ordinal: 1, "three matches typed")
        if appearance == .light {
            try key(app, [], .returnKey)
            try matches(app, ordinal: 2, "Return steps to the next match")
            try key(app, .shift, .returnKey)
            try matches(app, ordinal: 1, "Shift-Return steps back")
            let facts = try app.native()
            let next = try visible(facts, .findNext).frame, previous = try visible(facts, .findPrevious).frame
            try click(app, CGPoint(x: next.midX, y: next.midY))
            try matches(app, ordinal: 2, "the down arrow steps on")
            try click(app, CGPoint(x: previous.midX, y: previous.midY))
            try matches(app, ordinal: 1, "the up arrow steps back")
        }
        let facts = try app.native()
        let bar = try visible(facts, .findBar).frame, query = try visible(facts, .findQuery).frame
        let background = median(try SidebarReviewScenarios.pixels(app, "\(appearance)-find-bar", bar.insetBy(dx: 4, dy: 4)))
        try expectDrawn("the find bar", brightness: background, in: appearance)
        // "needle" at 2x stands out by several hundred pixels; the caret after it by under a hundred.
        let ink = inked(try SidebarReviewScenarios.pixels(app, "\(appearance)-find-query", query.intersection(bar)), from: background)
        try expect(Double(ink) > 62.5 * facts.backingScale * facts.backingScale,
                   "the find query barely shows in \(appearance): \(ink) pixels stand out from the bar's \(background)")
        app.note("\(appearance) find bar: background \(background), \(ink) pixels of the query stand out from it")
        if appearance == .light {
            try key(app, [], .escape)
        } else {
            let close = try visible(try app.native(), .findClose).frame
            try click(app, CGPoint(x: close.midX, y: close.midY))
        }
        try app.waitUntil("the find bar closed") { try find(app) == nil }
        try app.waitUntil("the page has the keys back") { try app.native().focusedPage == page }
        app.passed(appearance == .light ? "light: find with real typing, Return, Shift-Return, arrows and Escape" : "dark: the find bar drawn dark, its query readable, × closed it")
    }

    private static func outputStage(_ app: AppUnderTest) throws -> OutputStage? { try app.view().output?.stage }

    private static let outputStatus = ViewID.tabTool("output-status")

    /// ⌘P and ⇧⌘S open their sheets; real Cancel clicks close each silently. A real Save then writes the page to the
    /// owned fixture destination. Its status is measured after the sheet closes: AppKit dims the parent behind a sheet.
    private static func outputs(_ app: AppUnderTest, _ page: PageID, _ appearance: Scheme) throws {
        try key(app, .command, .p)
        try app.waitUntil("the print sheet after ⌘P", timeout: 20) { try sheet(app) }
        try sheetDrawn(app, "print", appearance)
        try clickButton(app, "Cancel")
        try app.waitUntil("Print cancelled", timeout: 10) { if case .terminal(.cancelled)? = try outputStage(app) { return true }; return false }
        try app.waitUntil("the print sheet gone") { try !sheet(app) }
        try expect(!isShown(try app.native(), outputStatus), "a status line stays after Print was cancelled")

        try key(app, [.shift, .command], .s)
        try app.waitUntil("the save sheet after ⇧⌘S", timeout: 10) { try app.native().sheetClass?.contains("SavePanel") == true }
        try sheetDrawn(app, "save", appearance)
        try clickButton(app, "Cancel")
        try app.waitUntil("Save Page As cancelled", timeout: 10) { if case .terminal(.cancelled)? = try outputStage(app) { return true }; return false }
        try app.waitUntil("the save sheet gone") { try !sheet(app) }
        try expect(!isShown(try app.native(), outputStatus), "a status line stays after Save Page As was cancelled")

        // Setup chooses an owned directory and filename; the key opens the actual panel and the real Save click
        // accepts it. Neither configureSavePanel nor a control-channel answer completes the panel.
        let destination = app.dataDirectory.appendingPathComponent("\(appearance)-page.mhtml")
        try app.perform(.configureSavePanel(window: app.window, path: destination.path))
        try key(app, [.shift, .command], .s)
        try app.waitUntil("the save sheet for the real Save click") { try app.native().sheetClass?.contains("SavePanel") == true }
        try clickButton(app, "Save")
        try app.waitUntil("Save wrote the page", timeout: 15) {
            guard case .terminal(.saved(let receipt))? = try outputStage(app) else { return false }
            return receipt.url.resolvingSymlinksInPath() == destination.resolvingSymlinksInPath() && receipt.bytes > 0
                && FileManager.default.fileExists(atPath: destination.path)
        }
        try app.waitUntil("the completed save sheet gone") { try !sheet(app) }
        try front(app)
        let facts = try app.native()
        let line = try visible(facts, outputStatus).frame
        let pixels = try SidebarReviewScenarios.pixels(app, "\(appearance)-saved-status", line.insetBy(dx: 2, dy: 2))
        let ink = inked(pixels, from: median(pixels))
        try expect(Double(ink) > 37.5 * facts.backingScale * facts.backingScale,
                   "the saved status barely shows in \(appearance): \(ink) pixels stand out from its background \(median(pixels))")
        app.note("\(appearance) saved status: background \(median(pixels)), \(ink) ink pixels")
        app.passed("\(appearance): Print and Save sheets drew \(appearance); Cancel was silent; a real Save wrote the file and its status reads over the active page")
    }

    /// ⌘= twice, ⌘- and ⌘0 with the page focused.
    private static func zoom(_ app: AppUnderTest, _ page: PageID) throws {
        try click(app, try blank(app, page))
        let steps: [(Modifiers, Key, Int)] = [(.command, .equals, 110), (.command, .equals, 125), (.command, .minus, 110), (.command, .zero, 100)]
        for (modifiers, key, percent) in steps {
            try self.key(app, modifiers, key)
            try app.waitUntil("\(percent)% after ⌘\(key)") { try app.view().urlPill.zoomPercent == percent }
        }
        app.passed("⌘=, ⌘- and ⌘0 zoomed the page")
    }

    /// A real click on a download link: the file lands in the profile's folder.
    private static func download(_ app: AppUnderTest, _ page: PageID) throws {
        let directory = app.dataDirectory.appendingPathComponent("downloads", isDirectory: true).path
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(directory))))
        try click(app, try element(app, page, "#dl"))
        try app.dispatch(.library(.open(.downloads)))
        try app.waitUntil("fixture.txt downloaded", timeout: 15) {
            guard case .library(let library)? = try app.view().overlay,
                  let row = library.downloads.first(where: { $0.filename == "fixture.txt" }) else { return false }
            return row.state == .finished && row.path == directory + "/fixture.txt" && FileManager.default.fileExists(atPath: directory + "/fixture.txt")
        }
        app.passed("a real click on a download link saved the file")
    }
}
