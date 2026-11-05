import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Round 5's remaining behaviours: the command bar's list for a question (P49, A140), the language of a page that
/// declares none (A141), the auto-archive banner as Arc's binary describes it (A082), Ask on Page's rows (A135). A page
/// closing itself (Q12, A049) is in `PageSiteFixScenarios.openerTab` and `RegressionScenarios.pageCloses`.
enum RemainingBehaviourScenarios {
    static let all = [
        Scenario("AIAskRows", "P49: a question lists the typed row, a suggestion, the Ask row and two more suggestions; the highlight is the theme's shade, grey under white", cefOnly: "native command bar", askRows),
        Scenario("AILanguageDetect", "a page that declares no language: French text offers Translation Available, Translate to English and Translated from French; English and very short text offer nothing; a declared language wins", cefOnly: "language of the page", languageDetect),
        Scenario("AIPageRowStyle", "Ask on Page's bar row and its question row have the size, icon column and highlight of the bar's other rows", cefOnly: "native command bar", askOnPageRows),
        Scenario("R52-ArchiveBanner", "A082: no banner before the first auto-archive; then Arc's card at the bottom of the sidebar: title, message, Got it, sizes and colors from Arc's binary; Settings dismisses it and opens Profiles", archiveBanner),
        Scenario("R52-ArchiveBannerDismiss", "A082: Got it dismisses the banner for good, also after a restart", archiveBannerDismiss),
    ]

    private static func isCommandBarOpen(_ app: AppUnderTest) throws -> Bool { isCommandBar(try app.view().overlay) }

    private static func near(_ pixel: [Int], _ expected: [Int], tolerance: Int = 3) -> Bool {
        zip(pixel.prefix(3), expected).allSatisfy { abs($0 - $1) <= tolerance }
    }

    /// A screenshot's pixel at a window point, as the visual pairs read it (converted to sRGB). `AppUnderTest.pixel` reads
    /// mid greys some 6 levels lighter than the same screenshot does (#ABABAB as [177, 177, 177]).
    private static func shotPixel(_ app: AppUnderTest, _ name: String, _ point: CGPoint) throws -> [Int] {
        let shot = try app.screenshot(name), frame = try app.native().windowFrame
        guard let provider = CGDataProvider(url: shot.url as CFURL), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw Check(description: "cannot read \(shot.url.path)")
        }
        let scale = Double(image.width) / frame.width
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.translateBy(x: -(point.x * scale).rounded(.down), y: -(Double(image.height) - (point.y * scale).rounded(.down) - 1))
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes.map(Int.init)
    }

    // MARK: AIAskRows (A140)

    @Sendable static func askRows(_ app: AppUnderTest) throws {
        for feature in AIFeature.allCases { try app.dispatch(.settings(.max(.feature(feature, true)))) }
        let space = try app.view().space.id
        // White, as the parent's retake of P49: grey highlight (Q01-a #ABABAB).
        try app.dispatch(.space(.update(space, title: nil, icon: nil, theme: SpaceTheme(colors: [RGBA(1, 1, 1, 1)], texture: .grain, intensity: 0.8, appearance: .auto))))
        try CommandBarEvidenceScenarios.type(app, "how do browsers render fonts", until: "how do browsers render html")
        var rows: [[String]] = []
        try app.waitUntil("five rows") { rows = try CommandBarEvidenceScenarios.rowTexts(app); return rows.count == 5 }
        let titles = rows.map { $0.first ?? "" }
        try expect(titles == ["how do browsers render fonts", "how do browsers render text", "how do browsers render fonts", "browser font rendering", "how do browsers render html"], "the rows are \(rows)")
        guard case .commandBar(let bar)? = try app.view().overlay, let provider = bar.askProvider else { throw Check(description: "no Ask provider") }
        try expect(rows[2].contains("Ask " + provider), "the third row is \(rows[2])")
        let row = try visible(app.native(), .commandBarResult(0)).frame
        let pixel = try shotPixel(app, "rows-white", CGPoint(x: row.maxX - 40, y: row.midY))
        try expect(near(pixel, [0xAB, 0xAB, 0xAB]), "the white theme's highlight is \(pixel)")
        try app.press("escape")
        try app.waitUntil("the bar closed") { try !isCommandBarOpen(app) }
        // The fixture's #F2EAE4: the highlight takes the theme (P02-b measured #B8A89B over the pill).
        try app.dispatch(.space(.update(space, title: nil, icon: nil, theme: SpaceTheme(colors: [RGBA(0xF2 / 255, 0xEA / 255, 0xE4 / 255, 1)], texture: .grain, intensity: 0.25, appearance: .auto))))
        try CommandBarEvidenceScenarios.type(app, "how do browsers render fonts", until: "how do browsers render html")
        let beigeRow = try visible(app.native(), .commandBarResult(0)).frame
        let beige = try shotPixel(app, "rows-beige", CGPoint(x: beigeRow.maxX - 40, y: beigeRow.midY))
        try expect(near(beige, [0xB8, 0xA8, 0x9B]), "the #F2EAE4 theme's highlight is \(beige)")
        app.passed("Five rows in Arc's order; the highlight is #ABABAB under white and #B8A89B under #F2EAE4 (\(pixel), \(beige))")
        // Browse for Me stays in Advanced → More Settings… (the user's decision): no bar row and no menu item.
        try expect(!rows.flatMap { $0 }.contains { $0.contains("Browse") }, "a Browse row in the list")
        guard case .menuItems(let tabs) = try app.send(.menuBarItems(menu: "Tabs")) else { throw Check(description: "no Tabs menu") }
        // Both keep hidden menu items for their shortcuts and for the command bar's actions.
        let shown = tabs.filter { ($0.hasPrefix("Browse for Me") || $0.hasPrefix("Ask on Page")) && !$0.hasSuffix("hidden") }
        try expect(shown.isEmpty, "Tabs shows \(shown)")
        try app.press("escape")
    }

    // MARK: AILanguageDetect (A141)

    private static func load(_ app: AppUnderTest, _ path: String) throws -> PageID {
        let url = app.site.url(path), item = try app.load(url), page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: url)
        return page
    }

    private static func pageMenu(_ app: AppUnderTest, choose: String? = nil) throws -> [String] {
        let card = try visible(app.native(), .card(0)).frame
        guard case .menuItems(let titles) = try app.send(.captureContextMenu(window: app.window, point: CGPoint(x: card.minX + 500, y: card.minY + 300), choose: choose)) else {
            throw Check(description: "no page menu")
        }
        return titles
    }

    @Sendable static func languageDetect(_ app: AppUnderTest) throws {
        for feature in AIFeature.allCases { try app.dispatch(.settings(.max(.feature(feature, true)))) }
        // English without a declaration: no second line (the recognizer has answered once the tab settled).
        _ = try load(app, "lang-english.html")
        app.sleep(2)
        let english = try app.view().urlPill.translation
        try expect(english == nil, "an English page offers \(String(describing: english))")
        try expect(!(try pageMenu(app)).contains("Translate to English"), "the English page's menu offers Translate to English")
        // Too little text to tell.
        _ = try load(app, "lang-short.html")
        app.sleep(2)
        try expect(try app.view().urlPill.translation == nil, "a one-word page offers a translation")
        // A declared language wins over the text.
        _ = try load(app, "lang-declared-english.html")
        app.sleep(2)
        try expect(try app.view().urlPill.translation == nil, "the declared English page offers a translation")
        // French without a declaration: the pill's second line, the page menu, and French in the popover's words.
        _ = try load(app, "lang-french.html")
        try app.waitUntil("Translation Available on the undeclared French page") { try app.view().urlPill.translation == .available }
        _ = try visible(app.native(), .aiControl("pill-translation"))
        _ = try app.screenshot("french-available")
        let titles = try pageMenu(app, choose: "Translate to English")
        try expect(titles.contains("Translate to English"), "the page menu is \(titles)")
        try app.waitUntil("Translated from French", timeout: 30) { try app.view().urlPill.translation == .translated(from: "French") }
        _ = try app.screenshot("french-translated")
        app.passed("Undeclared French: Translation Available, Translate to English, Translated from French; undeclared English, one word and declared English: nothing")
    }

    // MARK: AIPageRowStyle (A135)

    @Sendable static func askOnPageRows(_ app: AppUnderTest) throws {
        for feature in AIFeature.allCases { try app.dispatch(.settings(.max(.feature(feature, true)))) }
        let page = try load(app, "ai.html")
        _ = page
        let found = try CommandBarEvidenceScenarios.type(app, "Ask on Page", until: "Ask on Page…", exact: false)
        let n = try app.native()
        let row = try visible(n, .commandBarResult(found.0)).frame
        let rows = (0..<found.1.count).compactMap { n.actual[ViewID.commandBarResult($0).identifier]?.frame }
        try expect(Set(rows.map(\.height)).count == 1 && Set(rows.map(\.minX)).count == 1, "the rows differ: \(rows)")
        _ = try app.screenshot("action-row")
        for _ in 0..<found.0 { try app.press("down") }
        try app.press("return")
        try app.waitUntil("the bar's question mode") { if case .commandBar(let bar)? = try app.view().overlay { return bar.aiMode == .page }; return false }
        try app.type("what does this page say")
        try app.waitUntil("the question's row") { isShown(try app.native(), .commandBarResult(0)) }
        let question = try visible(app.native(), .commandBarResult(0)).frame
        try expect(question.height == row.height && question.minX == row.minX && question.width == row.width, "the question row is \(question), the bar's rows \(row)")
        let texts = try SidebarReviewScenarios.texts(app, in: question)
        try expect(texts.contains("what does this page say"), "the question row reads \(texts)")
        let highlight = try shotPixel(app, "question-row", CGPoint(x: question.maxX - 120, y: question.midY))
        let other = try shotPixel(app, "question-row", CGPoint(x: row.maxX - 120, y: row.midY))
        try expect(near(highlight, other, tolerance: 6), "the question row's highlight \(highlight) against the bar's \(other)")
        app.passed("Ask on Page's rows have the size, inset and highlight of the bar's other rows")
        try app.press("escape")
    }

    // MARK: R52-ArchiveBanner (A082)

    /// Two more tabs, the shown one stays; 13 hours on, the sweep archives the others and the banner appears.
    private static func earnBanner(_ app: AppUnderTest) throws {
        _ = try app.load(app.site.url("page2.html"))
        let shown = try app.load(app.site.url("red.html"))
        try waitForTitle(app, shown, "Red")
        try expect(try app.view().tabTools.archiveEducation == nil, "the banner shows before anything was archived")
        try expect(!isShown(try app.native(), .tabTool("education")), "the banner is on screen before anything was archived")
        try app.advanceClock(seconds: 13 * 3600)
        try app.waitUntil("the first auto-archive brings the banner") { try app.view().tabTools.archiveEducation == "12 hours" }
        try app.waitUntil("the banner on screen") { isShown(try app.native(), .tabTool("education")) }
    }

    @Sendable static func archiveBanner(_ app: AppUnderTest) throws {
        try earnBanner(app)
        let n = try app.native()
        let card = try visible(n, .tabTool("education")).frame, button = try visible(n, .tabTool("education-dismiss")).frame
        let list = n.computed.sidebar?.tablistViewport ?? .zero
        try expect(card.minX == list.minX + 10 && abs(card.width - (list.width - 20)) < 0.5, "the card is \(card) in the list \(list): 8 + 2 in from the sides")
        try expect(abs(card.maxY - (list.maxY - 10)) < 0.5, "the card's bottom is \(card.maxY), the list's \(list.maxY): 8 + 2 above it")
        try expect(abs(button.minX - (card.minX + 12)) < 0.5 && abs(card.maxX - button.maxX - 12) < 0.5 && abs(card.maxY - button.maxY - 12) < 0.5, "the button \(button) is not 12 in from the card \(card)")
        let texts = try SidebarReviewScenarios.texts(app, in: card)
        try expect(texts.contains("We cleaned up!") && texts.contains("Got it"), "the card reads \(texts)")
        // Under the fixture's default theme the button is the theme's dark shade with white words on it.
        let fill = try shotPixel(app, "banner", CGPoint(x: button.minX + 10, y: button.midY))
        try expect(fill[0] < 120 && fill[1] < 120 && fill[2] < 120, "the button's fill is \(fill)")
        try app.click(.tabTool("education"))
        try expect(try app.view().tabTools.archiveEducation != nil, "a click on the card's words dismissed it")
        try app.click(.tabTool("education-settings"))
        try app.waitUntil("Settings opens on Profiles") {
            guard case .settings(let settings) = try app.send(.settings) else { return false }
            return settings.pane == .profiles
        }
        try expect(try app.view().tabTools.archiveEducation == nil, "the Settings link kept the banner (Arc's dismiss reason settingsLearnMore)")
        try app.dispatch(.settings(.closeWindow))
        app.passed("The banner came with the first auto-archive, at Arc's insets, and Settings dismissed it and opened Profiles")
    }

    @Sendable static func archiveBannerDismiss(_ app: AppUnderTest) throws {
        try earnBanner(app)
        try app.click(.tabTool("education-dismiss"))
        try app.waitUntil("Got it dismisses the banner") { try app.view().tabTools.archiveEducation == nil }
        try expect(!isShown(try app.native(), .tabTool("education")), "the card stays on screen")
        try app.flush(); try app.restart()
        try expect(try app.view().tabTools.archiveEducation == nil, "the dismissal did not survive a restart")
    }
}
