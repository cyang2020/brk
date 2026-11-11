import BrkBase
import BrkControl
import CoreGraphics
import Foundation

/// Chromium's autofill suggestions picked with the real mouse. On CEF 154 the list opened and previewed but no pick ever
/// filled the field: Chromium accepts a suggestion only after its UI thread reports one idle moment, and CEF's external
/// message pump never ran idle work while any delayed task was pending (CEF #4332, fixed in CEF 156).
enum AutofillScenarios {
    static let all = [
        Scenario("Autofill-Pick", "an address saved by submitting a form is offered in the empty field and a real click on the suggestion fills it",
                 cefOnly: "autofill is Chromium's", pick),
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
