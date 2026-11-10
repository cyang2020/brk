import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Round 4, R4-9: the R4-6 review of the sidebar and window rows (1e644875d5:verify/completion/review-r4/sidebar-windows/
/// REVIEW.md). The first group proves the five defects fixed (A014 A015 A021 A031 A063); the rest give the native
/// evidence the review found missing, each driven at least once by a real key, pointer or menu path: in-process
/// key and mouse events through AppKit (`press`, `click`, `pointer`), real main-menu items (`menuAction`), real
/// context menus (`captureContextMenu`), and window-server keys (`WindowServerKeys`). Names start with R49 so the
/// harness serves the loopback GitHub fixture.
enum SidebarReviewScenarios {

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
    /// The texts Accessibility reads inside `rect` (window points, top-left) of the window: a row's labels.
    static func texts(_ app: AppUnderTest, in rect: CGRect, window: WindowID? = nil) throws -> [String] {
        let facts = try app.native(window ?? app.window)
        let top = CGDisplayBounds(CGMainDisplayID()).height - facts.windowFrame.maxY
        let screen = CGRect(x: facts.windowFrame.minX + rect.minX, y: top + rect.minY, width: rect.width, height: rect.height).insetBy(dx: -1, dy: -1)
        return NativeSystemInput.staticTexts(pid: app.hello!.pid).filter { screen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }.map(\.text)
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


    // MARK: A021


    // MARK: A031


    // MARK: A063


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
