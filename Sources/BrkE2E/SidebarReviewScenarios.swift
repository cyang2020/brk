import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Round 4, R4-9: the R4-6 review of the sidebar and window rows (verify/completion/review-r4/sidebar-windows/
/// REVIEW.md). The first group proves the five defects fixed (A014 A015 A021 A031 A063); the rest give the native
/// evidence the review found missing, each driven at least once by a real key, pointer or menu path: in-process
/// key and mouse events through AppKit (`press`, `click`, `pointer`), real main-menu items (`menuAction`), real
/// context menus (`captureContextMenu`), and window-server keys (`WindowServerKeys`). Names start with R49 so the
/// harness serves the loopback GitHub fixture.
enum SidebarReviewScenarios {
    static let all = [
        Scenario("R49-Badge", "a cancelled reconnect from the Favorite's menu keeps the unread dot", cefOnly: "native sheet and Favorite overlay", badge),
        Scenario("R49-Meeting", "Ctrl+Cmd+J answers in a private window and Little Arc; an unreadable file is not called expired", cefOnly: "native windows and calendar file", meeting),
        Scenario("R49-Icons", "the icon popover's planet, skull, restaurant and medical glyphs set the folder icon", cefOnly: "native popover", icons),
        Scenario("R49-MailCard", "hovering a Gmail Favorite with Previews on shows the mail card; the site switch turns it off", cefOnly: "native hover card", mailCard),
        Scenario("R49-ThemeUndo", "Cmd+Z and Shift+Cmd+Z step through the theme panel's edits", cefOnly: "native theme panel", themeUndo),
        Scenario("R49-Texture", "changing the space texture changes the drawn background", cefOnly: "Metal theme background", texture),
    ]

    // MARK: Helpers

    static func page(_ app: AppUnderTest, _ item: ItemID, _ window: WindowID? = nil) -> PageID { PageID(window: window ?? app.window!, item: item) }
    static func centre(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
    static func frame(_ app: AppUnderTest, _ identifier: String, window: WindowID? = nil) throws -> CGRect? {
        guard let view = try app.native(window ?? app.window).actual[identifier], !view.hidden else { return nil }
        return view.frame
    }
    static func panel(_ app: AppUnderTest, _ action: SidebarPanelControlAction, window: WindowID? = nil) throws {
        let result = try app.send(.sidebarPanel(window: window ?? app.window, action: action))
        guard result == .ok else { throw Check(description: "native panel action \(action) answered \(result)") }
    }
    static func panelOpen(_ app: AppUnderTest) throws -> Bool {
        if case .failed = try app.send(.sidebarPanel(window: app.window, action: .inspect)) { return false }
        return true
    }
    /// A real right-click at `point` and, with `choose`, a click on that row of the real menu. Returns the rows.
    @discardableResult
    static func contextMenu(_ app: AppUnderTest, at point: CGPoint, choose: String? = nil, window: WindowID? = nil) throws -> [String] {
        let result = try app.send(.captureContextMenu(window: window ?? app.window, point: point, choose: choose))
        guard case .menuItems(let items) = result else { throw Check(description: "no context menu at \(point): \(result)") }
        if let choose { try expect(items.contains(choose.components(separatedBy: " › ")[0]), "the menu has no \(choose): \(items)") }
        return items
    }
    static func windows(_ app: AppUnderTest) throws -> [WindowID] {
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "hello did not answer") }
        return hello.windows
    }
    /// The window `body` opens (by a key press or menu), and its kind.
    static func newWindow(_ app: AppUnderTest, _ what: String, kind: WindowKind, _ body: () throws -> Void) throws -> WindowID {
        let before = Set(try windows(app))
        try body()
        var made: WindowID?
        try app.waitUntil(what) {
            made = try windows(app).first { !before.contains($0) && (try? app.view($0).kind) == kind }
            return made != nil
        }
        return made!
    }
    /// A Favorite of `address` that never loads (the fixture does not need the real site).
    static func stoppedFavorite(_ app: AppUnderTest, _ address: String) throws -> ItemID {
        let item = try app.load(URL(string: address)!)
        try app.dispatch(.page(.stop(.focused)))
        try app.dispatch(.item(.move(item, to: .into(parent: try app.view().favorites.root, index: Int.max))))
        return item
    }
    static func toast(_ app: AppUnderTest, _ window: WindowID? = nil) throws -> String? { try app.view(window ?? app.window).tabTools.toast?.text }
    static func log(_ app: AppUnderTest, _ name: String, _ text: String) {
        let url = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/\(app.scenarioID)-\(name)")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: A014

    @Sendable static func badge(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        try app.waitForPageInput(page(app, home), at: app.site.url("index.html"))
        let github = try stoppedFavorite(app, "https://github.com/")
        try app.dispatch(.tab(.focus(home)))
        func connect(choose button: String) throws {
            try app.waitUntil("no source sheet open") { try !panelOpen(app) }
            let tile = try visible(app.native(), .favorite(github)).frame
            try contextMenu(app, at: centre(tile), choose: "Connect GitHub Notifications…")
            try app.waitUntil("the source sheet") { try panelOpen(app) }
            if button == "Connect" {
                try panel(app, .focus(identifier: ViewID.tabTool("repository").identifier))
                try app.type("fixture/repo")
            }
            try panel(app, .button(button))
        }
        try connect(choose: "Connect")
        try app.waitUntil("the unread dot") { try app.view().favorites.tiles.first { $0.id == github }?.badgeTint == .black }
        try expect(try frame(app, "favorite-badge-" + github.rawValue) != nil, "no native dot after connecting")
        _ = try app.screenshot("dot-before-cancel")
        let requests = app.site.requestCount("/repos/fixture/repo/notifications")
        // F9: the same menu again, then Cancel in the sheet.
        try connect(choose: "Cancel")
        try app.waitUntil("the cancel toast") { try toast(app) == "Source selection cancelled" }
        let tile = try app.view().favorites.tiles.first { $0.id == github }
        try expect(tile?.badge == 2 && tile?.badgeTint == .black, "cancelling the reconnect changed the badge: \(String(describing: tile?.badge)) \(String(describing: tile?.badgeTint))")
        try expect(try frame(app, "favorite-badge-" + github.rawValue) != nil, "the native dot went away after Cancel")
        try expect(app.site.requestCount("/repos/fixture/repo/notifications") == requests, "Cancel still read the notifications")
        _ = try app.screenshot("dot-after-cancel")
        app.passed("Favorite menu → Connect GitHub Notifications… → Cancel keeps the dot and the count")
    }

    // MARK: A015

    @Sendable static func meeting(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        try app.waitForPageInput(page(app, home), at: app.site.url("index.html"))
        let now = try app.advanceClock(seconds: 0)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        func date(_ offset: Int64) -> String { formatter.string(from: Date(timeIntervalSince1970: Double(now.milliseconds + offset * 1000) / 1000)) }
        let destination = URL(string: "https://example.com/?brk=R49-Meeting")!
        let good = app.dataDirectory.appendingPathComponent("meetings.ics")
        try Data("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:\(date(-60))\r\nDTEND:\(date(600))\r\nSUMMARY:Fixture meeting\r\nURL:\(destination.absoluteString)\r\nEND:VEVENT\r\nEND:VCALENDAR".utf8).write(to: good)
        try app.dispatch(.tabTools(.site(.selectCalendar(good, join: false))))
        try app.waitUntil("the calendar read") { try toast(app)?.contains("Calendar updated") == true }
        let standard = app.window!

        // A private window: Shift+Cmd+N, then Ctrl+Cmd+J there.
        let incognito = try newWindow(app, "Shift+Cmd+N opens a private window", kind: .incognito) { try app.press("shift+cmd+n") }
        _ = try app.send(.activate(window: incognito))
        app.window = incognito
        try app.waitUntil("the private window is key") { try app.native(incognito).isKey }
        try app.press("ctrl+cmd+j")
        try app.waitUntil("feedback in the private window") { try toast(app, incognito) == TopAppCopy.joinMeetingNeedsStandardWindow }
        try expect(try frame(app, ViewID.tabTool("toast").identifier, window: incognito) != nil, "the private window draws no toast")
        try expect(!allTabs(try app.view(incognito)).contains { $0.url == destination } && !allTabs(try app.view(standard)).contains { $0.url == destination },
                   "the meeting opened from the private window")
        _ = try app.screenshot("private-feedback", window: incognito)
        try app.dispatch(.window(.close))
        app.window = standard

        // Little Arc: Opt+Cmd+N, then Ctrl+Cmd+J there.
        _ = try app.send(.activate(window: standard))
        let little = try newWindow(app, "Opt+Cmd+N opens Little Arc", kind: .little) { try app.press("alt+cmd+n") }
        _ = try app.send(.activate(window: little))
        app.window = little
        try app.waitUntil("Little Arc is key") { try app.native(little).isKey }
        try app.waitUntil("Little Arc's bar") { isCommandBar(try app.view(little).overlay) }
        let littleURL = app.site.url("page2.html?little=meeting")
        try app.type(littleURL.absoluteString); try app.press("return")
        var littleTab: ItemID?
        try app.waitUntil("the page in Little Arc") { littleTab = tabRows(try app.view(little).scratch?.rows ?? []).first { $0.url == littleURL }?.id; return littleTab != nil }
        try app.waitForPageInput(page(app, littleTab!, little), at: littleURL)
        try app.press("ctrl+cmd+j")
        try app.waitUntil("feedback in Little Arc") { try toast(app, little) == TopAppCopy.joinMeetingNeedsStandardWindow }
        try expect(try frame(app, ViewID.tabTool("toast").identifier, window: little) != nil, "Little Arc draws no toast")
        _ = try app.screenshot("little-feedback", window: little)
        try app.dispatch(.window(.close))
        app.window = standard
        _ = try app.send(.activate(window: standard))
        app.passed("Ctrl+Cmd+J in a private window and in Little Arc says why nothing opens")

        // F6: a .ics file that is not iCalendar, then Ctrl+Cmd+J in the standard window.
        let bad = app.dataDirectory.appendingPathComponent("bad.ics")
        try Data("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n:broken\r\nEND:VEVENT\r\nEND:VCALENDAR".utf8).write(to: bad)
        try app.dispatch(.tabTools(.site(.selectCalendar(bad, join: false))))
        try app.waitUntil("the read failure") { try toast(app)?.contains("could not be read") == true }
        try app.waitForPageInput(page(app, home), at: app.site.url("index.html"))
        try app.press("ctrl+cmd+j")
        try app.waitUntil("the unreadable-file feedback") { try toast(app) == TopAppCopy.calendarUnreadable }
        try expect(!(try toast(app) ?? "").contains("expired"), "an unreadable file was called expired")
        try app.waitUntil("the file panel offered again", timeout: 6) { try app.native().sheetClass != nil }
        _ = try app.screenshot("unreadable-feedback")
        try panel(app, .button("Cancel"))
        try app.waitUntil("the panel closed") { try app.native().sheetClass == nil }
        app.passed("Ctrl+Cmd+J after an unreadable .ics says the file is unreadable and offers the panel")
    }

    // MARK: A021

    @Sendable static func icons(_ app: AppUnderTest) throws {
        try app.dispatch(.item(.newFolder))
        try app.press("return")
        guard let folder = try app.view().space.pinned.rows.first(where: { $0.kind == .folder })?.id else { throw Check(description: "no pinned folder") }
        let names: [NamedIcon] = [.medical, .planet, .restaurant, .skull]
        for (i, icon) in names.enumerated() {
            let row = try visible(app.native(), .row(folder)).frame
            try contextMenu(app, at: centre(row), choose: "Change Icon…")
            try app.waitUntil("the icon popover") { try panelOpen(app) }
            if i == 0 { _ = try app.panelScreenshot("popover") }
            try panel(app, .button(icon.rawValue))
            try app.waitUntil("\(icon.rawValue) set on the folder") {
                guard case .folder(let f)? = try app.view().space.pinned.rows.first(where: { $0.id == folder }) else { return false }
                return f.icon == .named(icon)
            }
            try app.waitUntil("the popover closed") { try !panelOpen(app) }
            _ = try app.screenshot("folder-\(icon.rawValue)")
        }
        try app.flush(); try app.restart()
        guard case .folder(let restored)? = try app.view().space.pinned.rows.first(where: { $0.id == folder }) else { throw Check(description: "folder lost") }
        try expect(restored.icon == .named(.skull), "the drawn icon did not survive the restart: \(String(describing: restored.icon))")
        _ = try app.screenshot("folder-skull-restarted")
    }

    // MARK: A031

    @Sendable static func mailCard(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        try app.waitForPageInput(page(app, home), at: app.site.url("index.html"))
        let gmail = try stoppedFavorite(app, "https://mail.google.com/mail/u/0/")
        try app.dispatch(.tab(.focus(home)))
        try app.waitForPageInput(page(app, home), at: app.site.url("index.html"))
        try app.dispatch(.tabTools(.preferences(includeFavorites: true, previews: true)))
        guard case .mail(let site, let unread, let messages)? = try app.view().favorites.tiles.first(where: { $0.id == gmail })?.hoverCard else {
            throw Check(description: "the Gmail Favorite projects no mail card")
        }
        try expect(site == "Gmail" && unread == nil && messages.isEmpty, "a mailbox Brk never saw: \(site) \(String(describing: unread)) \(messages)")
        let tile = try visible(app.native(), .favorite(gmail)).frame
        try app.hover(CGPoint(x: tile.midX, y: tile.midY))
        try app.waitUntil("the mail card", timeout: 4) { try frame(app, "sidebar-hover-card") != nil }
        let card = try frame(app, "sidebar-hover-card")!
        try expect(card.minX >= tile.maxX, "the card is not beside the sidebar: \(card) vs \(tile)")
        _ = try app.screenshot("mail-card")
        // Leaving the tile for the page closes it.
        let surface = try app.native().pages[page(app, home)]!.surfaceFrame!
        try app.hover(CGPoint(x: surface.maxX - 40, y: surface.maxY - 40))
        try app.waitUntil("the card closed", timeout: 3) { try frame(app, "sidebar-hover-card") == nil }
        // The Favorite's own switch, through its real menu.
        try contextMenu(app, at: centre(tile), choose: "Show Hover Preview")
        try app.waitUntil("the site switch off") { try app.view().favorites.tiles.first(where: { $0.id == gmail })?.hoverCard == nil }
        try app.hover(CGPoint(x: tile.midX, y: tile.midY))
        app.sleep(1)
        try expect(try frame(app, "sidebar-hover-card") == nil, "a card opened with Show Hover Preview off")
        app.note("The mailbox itself is never loaded (no network, no account); the card shows Arc's signed-out text. Its message list and unread count are unit-tested (SidebarReviewFixTests).")
    }

    // MARK: A063

    @Sendable static func themeUndo(_ app: AppUnderTest) throws {
        func theme() throws -> SpaceTheme? { if case .theme(_, let t)? = try app.view().dialog { return t } else { return nil } }
        let start = try app.view().space.id
        try app.perform(.menuAction("Edit Theme…"))
        try app.waitUntil("Edit Theme… opened the panel") { try theme() != nil }
        func primary() throws -> RGBA? { try theme()?.variants?.light.colors.first?.color ?? theme()?.colors.first }
        let originalPrimary = try primary()
        // Two edits: a preset on the next page, then a second color.
        try SpaceToolsScenarios.clickWhenShown(app, "theme-presets-next")
        try SpaceToolsScenarios.clickWhenShown(app, "theme-preset-3")
        try app.waitUntil("the preset applied") { try primary() != originalPrimary }
        let afterPreset = try theme()!
        try SpaceToolsScenarios.clickWhenShown(app, "theme-add")
        try app.waitUntil("a second color") { (try theme()?.variants?.light.colors.count ?? 0) == 2 }
        let afterAdd = try theme()!
        _ = try app.screenshot("two-edits")
        try app.press("cmd+z")
        try app.waitUntil("Cmd+Z took back the added color") { try theme()?.variants?.light.colors.count == afterPreset.variants?.light.colors.count && primary() == afterPreset.variants?.light.colors.first?.color }
        if WindowServerKeys.allowed {
            try WindowServerKeys.press(app, KeyChord(.command, .z), window: app.window!)
        } else {
            app.note("window-server keys not permitted for this runner; the second Cmd+Z is in-process")
            try app.press("cmd+z")
        }
        try app.waitUntil("Cmd+Z took back the preset") { try primary() == originalPrimary }
        try expect(try app.view().space.id == start, "undo changed the space")
        _ = try app.screenshot("undone")
        try app.press("shift+cmd+z")
        try app.waitUntil("Shift+Cmd+Z redid the preset") { try primary() == afterPreset.variants?.light.colors.first?.color }
        try app.press("shift+cmd+z")
        try app.waitUntil("Shift+Cmd+Z redid the added color") { try theme()?.variants?.light.colors.count == afterAdd.variants?.light.colors.count }
        _ = try app.screenshot("redone")
        try app.press("escape")
        try app.waitUntil("Esc closed the panel") { try app.view().dialog == nil }
        app.passed("Edit Theme… (menu) → preset, add → Cmd+Z ×2 (one window-server) → Shift+Cmd+Z ×2")
    }

    // MARK: A062

    /// RGBA bytes of `rect` (window points) in a fresh window screenshot.
    static func pixels(_ app: AppUnderTest, _ name: String, _ rect: CGRect) throws -> [UInt8] {
        let shot = try app.screenshot(name)
        guard let provider = CGDataProvider(url: shot.url as CFURL),
              let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw Check(description: "screenshot \(shot.url.lastPathComponent) unreadable")
        }
        let scale = Double(image.width) / max(1, try app.native().contentSize.width)
        let box = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
        guard let crop = image.cropping(to: box) else { throw Check(description: "crop \(box) outside \(image.width)x\(image.height)") }
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return true
        }
        guard drawn else { throw Check(description: "no bitmap context") }
        return bytes
    }
    /// Mean absolute difference per color channel between two same-size RGBA buffers.
    static func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var total = 0, count = 0
        for i in stride(from: 0, to: a.count, by: 4) { for c in 0..<3 { total += abs(Int(a[i + c]) - Int(b[i + c])); count += 1 } }
        return Double(total) / Double(count)
    }

    @Sendable static func texture(_ app: AppUnderTest) throws {
        let space = try app.view().space.id
        // The window background above the card, right of the sidebar, where nothing else draws.
        let area = try app.native().computed.contentArea
        let band = CGRect(x: area.minX + 20, y: 1, width: area.width - 40, height: max(4, area.minY - 2))
        func set(_ texture: Texture, _ label: String) throws -> [UInt8] {
            let theme = SpaceTheme(colors: [ThemePresets.drab[8]], texture: texture, noise: 1, intensity: 0.6, appearance: .light)
            try app.dispatch(.space(.update(space, title: nil, icon: nil, theme: theme)))
            try app.waitUntil("the space shows \(texture.rawValue)") { try app.view().theme.texture == texture }
            app.sleep(1.5)   // the crossfade
            _ = try settledPixel(app, CGPoint(x: band.midX, y: band.midY))
            return try pixels(app, "texture-\(label)", band)
        }
        _ = try set(.grain, "warmup")   // the colors change once, so every later change is the texture alone
        var drawn: [Texture: [UInt8]] = [:]
        for texture in Texture.allCases { drawn[texture] = try set(texture, texture.rawValue) }
        let again = try set(.grain, "grain-again")
        let stable = meanDifference(again, drawn[.grain]!)
        var record = String(format: "band %@ (points); grain drawn twice differs by %.3f per channel\n", "\(band)", stable)
        var pairs: [(Texture, Texture, Double)] = []
        for (i, a) in Texture.allCases.enumerated() { for b in Texture.allCases.dropFirst(i + 1) { pairs.append((a, b, meanDifference(drawn[a]!, drawn[b]!))) } }
        for (a, b, d) in pairs { record += String(format: "%@ vs %@: %.3f\n", a.rawValue, b.rawValue, d) }
        log(app, "differences.txt", record)
        try expect(stable < 0.5, "grain drew differently the second time (\(stable) per channel)")
        for (a, b, d) in pairs { try expect(d > max(0.3, 2 * stable), "\(a.rawValue) and \(b.rawValue) draw the same background (\(d) per channel, grain against itself \(stable))") }
        app.note("Textures are a Brk option Arc 1.170 does not have (ROUND3-BRIEF); set through the space update command, which no Brk control sends today.")
    }
}
