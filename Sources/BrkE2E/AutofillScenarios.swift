import BrkBase
import BrkControl
import BrkLayout
import CoreGraphics
import Foundation

/// Chromium's autofill suggestions picked with the real mouse. On CEF 154 the list opened and previewed but no pick ever
/// filled the field: Chromium accepts a suggestion only after its UI thread reports one idle moment, and CEF's external
/// message pump never ran idle work while any delayed task was pending (CEF #4332, fixed in CEF 156).
enum AutofillScenarios {
    static let all = [
        Scenario("Autofill-Pick", "an address saved by submitting a form is offered in the empty field and a real click on the suggestion fills it",
                 cefOnly: "autofill is Chromium's", pick),
        Scenario("Password-SaveCard", "a submitted login asks with Arc's centred card, not Chromium's bubble; a real click on Save keeps it and the login page fills it next time",
                 cefOnly: "the password manager is Chromium's", saveCard),
    ]
    private typealias E = SidebarEvidenceScenarios
    static let address = "casper@example.com"

    static func pick(_ app: AppUnderTest) throws {
        guard WindowServerKeys.allowed else { throw Check(description: "no permission to post real mouse events") }
        guard let window = app.window else { throw Check(description: "no window") }
        _ = try E.loadReady(app, "autofill-email.html")
        // The fixture's field sits at (40, 40) and is 400 x 40 CSS pixels, at zoom 1.
        let card = try app.native(window).computed.cards[0].rect
        let field = CGPoint(x: card.minX + 240, y: card.minY + 60)

        // Chromium keeps a field's value as an autocomplete entry when its form is submitted.
        try PhysicalPointer.press(app, at: field, window: window) {}
        try app.type(address)
        try app.press("return")
        try app.waitUntil("the form is submitted", timeout: 10) { try currentTab(app.view())?.title == "autofill:submitted" }

        // The empty field clicked again: Chromium opens its suggestion list, a window of Brk's own below the field.
        try PhysicalPointer.press(app, at: field, window: window) {}
        let fieldOnScreen = try screen(app, field, window: window)
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
        var list: CGRect?
        try app.waitUntil("Chromium's suggestion list opens below the field", timeout: 5) {
            list = suggestionWindow(pid: hello.pid, below: fieldOnScreen)
            return list != nil
        }
        guard let list else { throw Check(description: "no suggestion list") }
        _ = try app.screenshot("1-suggestion")
        // Chromium ignores clicks in the list's first half second on purpose; a person takes longer than that.
        usleep(1_000_000)
        try PhysicalPointer.click(app, at: CGPoint(x: list.midX, y: list.midY), window: window)
        try app.waitUntil("the picked suggestion fills the field", timeout: 5) { try currentTab(app.view())?.title == "email:" + address }
        _ = try app.screenshot("2-filled")
        app.passed("a real click on Chromium's autofill suggestion fills the field")
    }

    static func saveCard(_ app: AppUnderTest) throws {
        guard WindowServerKeys.allowed else { throw Check(description: "no permission to post real mouse events") }
        guard let window = app.window else { throw Check(description: "no window") }
        _ = try E.loadReady(app, "save-login.html")
        // The fixture's fields sit at (40, 40) and (40, 90), 300 x 36 CSS pixels, at zoom 1.
        let card = try app.native(window).computed.cards[0].rect
        try PhysicalPointer.press(app, at: CGPoint(x: card.minX + 190, y: card.minY + 58), window: window) {}
        try app.type("fixture-user")
        try PhysicalPointer.press(app, at: CGPoint(x: card.minX + 190, y: card.minY + 108), window: window) {}
        try app.type("fixture-pass-123")
        try app.press("return")
        try app.waitUntil("the login is sent", timeout: 10) { try currentTab(app.view())?.title == "login:sent" }

        let prompt = ViewID.spaceToolsControl("save-prompt")
        try app.waitUntil("Arc's save-password card opens", timeout: 8) { isShown(try app.native(window), prompt) }
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
        try app.waitUntil("Chromium's own save bubble is invisible (\(String(describing: chromiumBubble(pid: hello.pid))))", timeout: 2) { chromiumBubble(pid: hello.pid) == nil }
        let facts = try app.native(window)
        let shown = try visible(facts, prompt).frame, content = facts.contentSize
        try expect(abs(shown.midX - content.width / 2) <= 1 && abs(shown.midY - content.height / 2) <= 1,
                   "the card is not centred in the window: \(shown) in \(content)")
        _ = try app.screenshot("1-card")

        try PhysicalPointer.press(app, at: centre(try visible(app.native(window), .spaceToolsControl("alert-confirm")).frame), window: window) {}
        try app.waitUntil("the card closes", timeout: 5) { !isShown(try app.native(window), prompt) }

        // Saved: the login page fills it as it loads; a click lets the page read the values.
        _ = try E.loadReady(app, "save-login.html")
        try app.waitUntil("the login page loads", timeout: 10) { try currentTab(app.view())?.title == "login" }
        let page = try app.native(window).computed.cards[0].rect
        try PhysicalPointer.press(app, at: CGPoint(x: page.midX + 200, y: page.midY), window: window) {}
        try app.waitUntil("Chromium fills the saved login", timeout: 10) { try currentTab(app.view())?.title == "login:fixture-user:filled" }
        _ = try app.screenshot("2-filled")
        app.passed("Arc's card asked, a real click on Save kept the login, and Chromium filled it on the next visit")
    }

    private static func centre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

    /// A window of Brk's the size of Chromium's save bubble (448 x 374) that is not fully transparent.
    private static func chromiumBubble(pid: Int32) -> CGRect? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list where info[kCGWindowOwnerPID as String] as? Int32 == pid && (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 {
            guard let b = info[kCGWindowBounds as String] as? [String: Double] else { continue }
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if (430...470).contains(rect.width), (340...420).contains(rect.height) { return rect }
        }
        return nil
    }

    /// `point` (window content coordinates, top-left origin) on the screen, top-left origin as CGEvent and CGWindowList use.
    private static func screen(_ app: AppUnderTest, _ point: CGPoint, window: WindowID) throws -> CGPoint {
        let frame = try app.native(window).windowFrame
        return CGPoint(x: frame.minX + point.x, y: CGDisplayBounds(CGMainDisplayID()).height - frame.maxY + point.y)
    }

    /// A small on-screen window of Brk's whose top edge is just below the field's centre: the suggestion list.
    private static func suggestionWindow(pid: Int32, below field: CGPoint) -> CGRect? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard info[kCGWindowOwnerPID as String] as? Int32 == pid, let bounds = info[kCGWindowBounds as String] as? [String: Double] else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if rect.height > 20, rect.height < 200, rect.width < 700, rect.minY > field.y, rect.minY < field.y + 80,
               rect.maxX > field.x - 220, rect.minX < field.x + 220 { return rect }
        }
        return nil
    }
}
