import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// The AI panel's look on a real-launched Brk (docs/design/ai-panel.md, "验收"): the user's price-watch conversation,
/// "盯着这三个商品页的价格，每小时更新一次", typed into the composer and sent with Return, answered by the fixture agent through
/// Brk's real tool bridge (it lists and reads the three shop tabs, makes a page and keeps it with an hourly refresh); a
/// shop's price changes and the hour passes, so the refresh's notice shows; then the same window in four Spaces (default
/// light, light blue, gradient purple, dark), the + menu open, and a folder session's approval card with its command
/// shown. Real clicks and keys; the control socket reads state, moves the test clock and takes the window's pictures.
/// The facts each picture is checked for go to `panel-look.txt`.
enum AIPanelLookScenarios {
    nonisolated(unsafe) private static var pid: Int32 = 0

    static let spaces: [(name: String, title: String, theme: SpaceTheme?)] = [
        ("light", "Home", nil),
        ("sky", "浅蓝", SpaceTheme(colors: [ThemePresets.pastel[7]], texture: .grain, intensity: 0.25, appearance: .light)),
        ("grape", "渐变紫", SpaceTheme(colors: [RGBA(hex: "#C4B2F2"), RGBA(hex: "#E7B3DC")], texture: .grain, intensity: 0.35, appearance: .light)),
        ("dark", "深色", SpaceTheme(colors: [ThemePresets.drab[0]], texture: .grain, intensity: 0.25, appearance: .dark)),
    ]

    /// macOS's own permission dialogs (UserNotificationCenter, "access files in your Desktop folder") can sit at the
    /// screen's right, over the panel's + menu and approval card; nobody but the user answers them, so the window moves
    /// to the screen's left edge, clear of them.
    static func clearOfSystemDialogs(_ app: AppUnderTest) throws {
        var frame = try app.native().windowFrame
        frame.origin.x = CGDisplayBounds(CGMainDisplayID()).minX
        try app.setWindowFrame(frame)
        app.sleep(0.5)
    }

    private static func screen(_ app: AppUnderTest, _ point: CGPoint) throws -> CGPoint {
        let facts = try app.native()
        let top = CGDisplayBounds(CGMainDisplayID()).height - facts.windowFrame.maxY
        return CGPoint(x: facts.windowFrame.minX + point.x, y: top + point.y)
    }
    /// A control's frame once two reads 0.2 s apart agree.
    private static func stillFrame(_ app: AppUnderTest, _ id: ViewID) throws -> CGRect {
        var last: CGRect?
        for _ in 0..<25 {
            let now = try visible(app.native(), id).frame
            if now == last { return now }
            last = now
            usleep(200_000)
        }
        return try XCTUnwrapValue(last)
    }
    private static func click(_ app: AppUnderTest, _ id: ViewID) throws {
        let frame = try stillFrame(app, id)
        try PhysicalPointer.click(app, at: try screen(app, CGPoint(x: frame.midX, y: frame.midY)), window: app.window!)
        usleep(300_000)
    }
    private static func key(_ modifiers: Modifiers, _ key: Key) throws {
        try NativeSystemInput.postSystemWide(KeyChord(modifiers, key))
        usleep(250_000)
    }
    /// Chinese text arrives as a person's input method would leave it: pasted, then Return.
    private static func paste(_ text: String) throws {
        let saved = shell("/usr/bin/pbpaste", input: nil)
        _ = shell("/usr/bin/pbcopy", input: text)
        defer { _ = shell("/usr/bin/pbcopy", input: saved) }
        try key(.command, .v)
        usleep(300_000)
    }
    private static func shell(_ path: String, input: String?) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.environment = ["LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"]
        let output = Pipe(), feed = Pipe()
        process.standardOutput = output; process.standardInput = feed
        guard (try? process.run()) != nil else { return "" }
        if let input { feed.fileHandleForWriting.write(Data(input.utf8)) }
        try? feed.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
    private static func tabRows(_ rows: [Row]) -> [TabRow] {
        rows.flatMap { row -> [TabRow] in
            switch row {
            case .tab(let t): [t]
            case .split(let s): s.panes
            case .folder(let f): tabRows(f.children)
            }
        }
    }
    private static func shop(_ app: AppUnderTest, _ name: String) throws -> TabRow {
        try XCTUnwrapValue(tabRows(try app.view().space.today.rows).first { $0.url?.absoluteString.hasSuffix("shop-\(name).html") == true })
    }
    /// The three shops in the shown Space, the kettle shown last (setup: the command bar's own commands).
    private static func openShops(_ app: AppUnderTest) throws {
        for name in ["kettle", "toaster", "blender"] where (try? shop(app, name)) == nil {
            try app.dispatch(.commandBar(.open(.newTab)))
            try app.dispatch(.commandBar(.submit(app.site.url("shop-\(name).html").absoluteString)))
            try app.waitUntil("shop-\(name) open", timeout: 15) { (try? shop(app, name)) != nil }
        }
        let kettle = try shop(app, "kettle")
        try click(app, .row(kettle.id))
        try app.waitUntil("the kettle shown", timeout: 10) { try shop(app, "kettle").status == .current }
    }

    private final class Log {
        let url: URL
        var failures = 0
        init(_ url: URL) { self.url = url; try? Data().write(to: url) }
        func write(_ line: String) {
            print("[panel-look] " + line)
            if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data((line + "\n").utf8)); try? handle.close() }
        }
        func check(_ name: String, _ body: () throws -> String) {
            do { write("PASS \(name): \(try body())") } catch { failures += 1; write("FAIL \(name): \(error)") }
        }
    }

    /// Where the panel's parts are, against the layout's own numbers.
    private static func geometry(_ app: AppUnderTest) throws -> String {
        let facts = try app.native()
        let panel = try XCTUnwrapValue(facts.computed.aiPanel)
        let card = try XCTUnwrapValue(facts.computed.cards.first?.rect)
        let shown = try XCTUnwrapValue(facts.actual["ai-document"]?.frame)
        try expect(shown == panel, "the panel's view \(shown) is not its column \(panel)")
        try expect(card.maxX == panel.minX, "the card ends at \(card.maxX), the column starts at \(panel.minX)")
        let transcript = try XCTUnwrapValue(facts.actual[ViewID.aiControl("transcript").identifier]?.frame)
        let pages = facts.actual.filter { $0.key.hasPrefix("ai-page-") && !$0.key.hasPrefix("ai-page-row-") && !$0.key.hasPrefix("ai-page-leaving") && !$0.key.hasPrefix("ai-page-card") && !$0.value.hidden }
        for (id, page) in pages {
            try expect(page.frame.minX >= transcript.minX - 0.5 && page.frame.maxX <= transcript.maxX + 0.5, "\(id) \(page.frame) runs out of the transcript \(transcript)")
        }
        let composer = try XCTUnwrapValue(facts.actual[ViewID.aiControl("composer").identifier]?.frame)
        return "panel \(panel), card ends \(card.maxX), transcript \(transcript.width) wide, pages \(pages.map { "\($0.value.frame.width)×\($0.value.frame.height)" }), composer \(composer)"
    }

    /// The window's picture as sRGB pixels, and how many pixels a point is.
    private struct Picture {
        let pixels: [UInt8], width: Int, height: Int, scale: Double
        init(_ url: URL, contentWidth: Double) throws {
            guard let provider = CGDataProvider(url: url as CFURL),
                  let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                  let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw Check(description: "unreadable capture") }
            width = image.width; height = image.height; scale = Double(image.width) / contentWidth
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Check(description: "no bitmap") }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            pixels = buffer
        }
        /// The mean color of `rect` (window points, top-left origin).
        func mean(_ rect: CGRect) -> [Double] {
            var sum = [0.0, 0.0, 0.0], n = 0.0
            for y in Int(rect.minY * scale)..<max(Int(rect.minY * scale) + 1, Int(rect.maxY * scale)) where y >= 0 && y < height {
                for x in Int(rect.minX * scale)..<max(Int(rect.minX * scale) + 1, Int(rect.maxX * scale)) where x >= 0 && x < width {
                    let i = (y * width + x) * 4
                    for c in 0..<3 { sum[c] += Double(pixels[i + c]) }
                    n += 1
                }
            }
            return sum.map { n > 0 ? $0 / n : 0 }
        }
    }
    private static func hex(_ c: [Double]) -> String { String(format: "#%02X%02X%02X", Int(c[0].rounded()), Int(c[1].rounded()), Int(c[2].rounded())) }
    private static func distance(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).map { abs($0 - $1) }.max() ?? 0 }

    /// The Space's accent as the panel paints it (`Palette.focusColor`): light, the primary's hue at relative luminance
    /// 0.097 (`themeShade`); dark, the hue at HSB saturation min(0.53, 9 × s) and brightness 0.8.
    private static func accent(_ theme: ResolvedTheme) -> [Double] {
        let p = theme.gradient.first ?? RGBA(0.5, 0.5, 0.5)
        if theme.scheme == .light { let c = themeShade(p, luminance: 0.097); return [c.red * 255, c.green * 255, c.blue * 255] }
        let hi = max(p.red, p.green, p.blue), lo = min(p.red, p.green, p.blue), d = hi - lo
        var hue = 0.0
        if d > 0 {
            hue = hi == p.red ? ((p.green - p.blue) / d).truncatingRemainder(dividingBy: 6) : hi == p.green ? (p.blue - p.red) / d + 2 : (p.red - p.green) / d + 4
            hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
        }
        let s = min(0.53, (hi > 0 ? d / hi : 0) * 9), v = 0.8
        let c = v * s, x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double) = switch hue { case ..<60: (c, x, 0); case ..<120: (x, c, 0); case ..<180: (0, c, x); case ..<240: (0, x, c); case ..<300: (x, 0, c); default: (c, 0, x) }
        return [(r + m) * 255, (g + m) * 255, (b + m) * 255]
    }

    /// The spec's four checks on one window picture: the panel's background is the window's own next to it, the user's
    /// message and the composer are the sidebar's current row, the send button is the Space's accent, no page leaves
    /// the transcript (`geometry`).
    private static func colours(_ app: AppUnderTest, _ shot: URL) throws -> String {
        let facts = try app.native(), view = try app.view()
        let picture = try Picture(shot, contentWidth: facts.contentSize.width)
        let panel = try XCTUnwrapValue(facts.computed.aiPanel), card = try XCTUnwrapValue(facts.computed.cards.first?.rect)
        // 1. Above the card's top and inside the panel's inset, at the same height: one background.
        let outside = picture.mean(CGRect(x: card.maxX - 8, y: 2, width: 5, height: 5)), inside = picture.mean(CGRect(x: panel.minX + 2, y: 2, width: 5, height: 5))
        let below = picture.mean(CGRect(x: card.maxX - 40, y: card.maxY + 3, width: 30, height: 4)), panelLow = picture.mean(CGRect(x: panel.minX + 2, y: card.maxY + 3, width: 5, height: 4))
        try expect(distance(outside, inside) <= 6 && distance(below, panelLow) <= 6, "the panel has a fill of its own: \(hex(inside)) beside \(hex(outside)), \(hex(panelLow)) beside \(hex(below))")
        // 2. The current row's fill, the user's message and the composer.
        let current = try XCTUnwrapValue(view.space.today.rows.lazy.compactMap { row -> TabRow? in if case .tab(let t) = row, t.status == .current { t } else { nil } }.first)
        let rowFrame = try visible(facts, .row(current.id)).frame
        let rowFill = picture.mean(CGRect(x: rowFrame.maxX - 15, y: rowFrame.minY + 5, width: 3, height: 3))
        let bubble = try visible(facts, .aiControl("user-0")).frame
        let bubbleFill = picture.mean(CGRect(x: bubble.maxX - 7, y: bubble.midY - 1, width: 3, height: 3))
        let composer = try visible(facts, .aiControl("composer")).frame
        let composerFill = picture.mean(CGRect(x: composer.maxX - 44, y: composer.minY + 4, width: 3, height: 3))
        try expect(distance(rowFill, bubbleFill) <= 8 && distance(rowFill, composerFill) <= 8, "row \(hex(rowFill)), message \(hex(bubbleFill)), composer \(hex(composerFill))")
        // 3. The send button.
        let send = try visible(facts, .aiControl("send")).frame
        let sendFill = picture.mean(CGRect(x: send.minX + 4, y: send.midY - 1, width: 3, height: 3)), wanted = accent(view.theme)
        try expect(distance(sendFill, wanted) <= 10, "send \(hex(sendFill)), the Space's accent \(hex(wanted))")
        return "background \(hex(inside)) beside \(hex(outside)); row \(hex(rowFill)), message \(hex(bubbleFill)), composer \(hex(composerFill)); send \(hex(sendFill)) for accent \(hex(wanted))"
    }

    private static func route(_ app: AppUnderTest) throws {
        guard WindowServerKeys.allowed else { throw Check(description: "posting events is not allowed for this runner") }
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
        pid = hello.pid
        let log = Log(app.shotsDirectory.appendingPathComponent("panel-look.txt"))
        try clearOfSystemDialogs(app)
        // Max on with the fixture agent, the basic layer off (Name Tabs would rename the shops).
        try app.dispatch(.settings(.max(.provider(.claude))))
        for feature in AIFeature.allCases { try app.dispatch(.settings(.max(.feature(feature, !AIFeature.basicLayer.contains(feature))))) }
        let home = try app.view().space.id
        var page: AIPageID?

        log.check("the price watch, typed into the composer and sent with Return") {
            // The fixture site is shared by a run's scenarios: the kettle starts at its own price again.
            app.site.restore("/shop-kettle.html")
            try openShops(app)
            // The header's New Conversation, before there is a panel to click it in.
            try app.dispatch(.assist(.newConversation))
            try app.waitUntil("the panel", timeout: 8) { try app.view().ai?.conversation?.fresh == true }
            try click(app, .aiControl("input"))
            try paste("盯着这三个商品页的价格，每小时更新一次")
            try key([], .returnKey)
            try app.waitUntil("the turn started", timeout: 10) { try app.view().ai?.busy == true }
            try app.waitUntil("the answer", timeout: 60) { try app.view().ai?.busy == false }
            let ai = try XCTUnwrapValue(try app.view().ai)
            let steps: [AIAgentStep] = ai.conversation?.items.compactMap { item -> AIAgentStep? in if case .step(let s) = item { s } else { nil } } ?? []
            try expect(steps.count >= 5 && steps.allSatisfy { $0.kind != nil && $0.state == .done }, "steps \(steps)")
            page = try XCTUnwrapValue(ai.pages.first?.id)
            try expect(ai.pages.first?.schedule == .hourly, "the page's schedule \(String(describing: ai.pages.first?.schedule))")
            try app.waitUntil("the step line", timeout: 5) { try app.native().actual[ViewID.aiControl("steps-0").identifier]?.hidden == false }
            return "\(steps.count) steps (\(steps.compactMap(\.kind?.rawValue).joined(separator: ", "))), page \(page!.rawValue), \(AIStepWords.summary(steps, .zh))"
        }

        log.check("the kettle drops to €34.50 and the hour passes: the refresh's notice") {
            let page = try XCTUnwrapValue(page)
            app.site.replace(in: "/shop-kettle.html", "€39.00", with: "€34.50")
            _ = try app.advanceClock(seconds: 3_660)
            try app.waitUntil("the refresh's notice", timeout: 120) {
                try app.view().ai?.conversation?.items.last.map { if case .notice(let text) = $0 { text.contains("已更新") } else { false } } == true
            }
            let notice = try app.view().ai?.conversation?.items.last
            try app.waitUntil("the page loaded again", timeout: 10) { try (app.view().ai?.pages.first { $0.id == page }?.revision ?? 0) > 0 }
            app.sleep(2)
            return "\(String(describing: notice))"
        }

        log.check("a chip for the next message") {
            try app.dispatch(.assist(.attach([.tab(try shop(app, "kettle").id.rawValue)])))
            try app.waitUntil("the chip", timeout: 5) { try app.view().ai?.conversation?.attached.count == 1 }
            return "Steel Kettle"
        }

        for (index, space) in spaces.enumerated() {
            log.check("the panel in the \(space.name) Space") {
                if let theme = space.theme {
                    // One Space, its theme changed: since step 7 each Space has its own conversation list
                    // (docs/design/ai-threads.md), and a new Space would show its own, empty one.
                    try app.dispatch(.space(.update(home, title: space.title, icon: nil, theme: theme)))
                    try app.waitUntil("the \(space.name) Space", timeout: 8) { try app.view().space.title == space.title && app.view().theme.scheme == (theme.appearance == .dark ? .dark : .light) }
                } else {
                    try expect(try app.view().space.id == home, "not the first Space")
                }
                try expect(try app.view().space.id == home, "the window left the Space")
                try expect(try app.view().ai?.conversation != nil, "the panel left with the Space")
                // Off the panel, so no control shows its hover fill.
                try PhysicalPointer.click(app, at: try screen(app, CGPoint(x: (try app.native().computed.contentArea.midX), y: 300)), window: app.window!)
                app.sleep(1.5)
                let facts = try geometry(app)
                let shot = try app.screenshot("\(index + 1)-\(space.name)")
                return "\(try app.view().theme.scheme) scheme; \(facts); \(try colours(app, shot.url))"
            }
        }

        log.check("the + menu") {
            try click(app, .aiControl("plus"))
            try app.waitUntil("the menu", timeout: 5) { try app.native().actual[ViewID.aiControl("agent").identifier]?.hidden == false }
            app.sleep(0.6)
            _ = try app.screenshot("5-plus-menu")
            let rows = try app.native().actual.keys.filter { ["ai-folder", "ai-agent", "ai-permissions", "ai-agent-settings"].contains($0) }
            try click(app, .aiControl("input"))
            try key([], .escape)
            try app.waitUntil("the menu closed", timeout: 5) { try app.native().actual[ViewID.aiControl("agent").identifier]?.hidden != false }
            return "rows \(rows.sorted())"
        }

        log.check("Work in a Folder… from the + menu, then the approval card for a command") {
            // A test instance answers the folder question with this folder.
            try FileManager.default.createDirectory(at: app.dataDirectory.appendingPathComponent("ai-work", isDirectory: true), withIntermediateDirectories: true)
            try click(app, .aiControl("plus"))
            try app.waitUntil("the menu", timeout: 5) { try app.native().actual[ViewID.aiControl("folder").identifier]?.hidden == false }
            try click(app, .aiControl("folder"))
            try app.waitUntil("a folder session", timeout: 15) { try app.view().ai?.conversation?.folder != nil }
            try click(app, .aiControl("input"))
            try paste("看看这个文件夹里有什么 fixture:command")
            try key([], .returnKey)
            try app.waitUntil("the approval", timeout: 15) { try app.native().actual[ViewID.aiControl("approval-deny").identifier]?.hidden == false }
            try click(app, .aiControl("approval-command"))
            app.sleep(0.8)
            try PhysicalPointer.click(app, at: try screen(app, CGPoint(x: (try app.native().computed.contentArea.midX), y: 300)), window: app.window!)
            app.sleep(0.8)
            _ = try app.screenshot("6-approval")
            let approval = try XCTUnwrapValue(try app.view().ai?.conversation?.items.lazy.compactMap { item -> AIAgentApproval? in if case .approval(let a) = item, a.answer == nil { a } else { nil } }.first)
            try click(app, .aiControl("approval-deny"))
            try app.waitUntil("the turn ended", timeout: 15) { try app.view().ai?.busy == false }
            return "“\(AIStepWords.approval(approval, agent: "Claude", folder: try app.view().ai?.conversation?.folder, .zh))”; kind \(approval.kind?.rawValue ?? "nil")"
        }

        log.write("failures: \(log.failures)")
        if log.failures > 0 { throw Check(description: "\(log.failures) checks failed; see panel-look.txt") }
    }
}
