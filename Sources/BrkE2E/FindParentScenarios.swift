import BrkBase
import BrkDomain
import BrkLayout
import CoreGraphics

extension FindScenarios {
    @Sendable static func repeatedFindFocus(_ app: AppUnderTest) throws {
        let page = try setup(app)
        try app.press("cmd+f")
        try typeQuery(app, "needle")
        try matches(app, 3)
        let card = try app.native().computed.cards[0].rect
        try app.click(at: CGPoint(x: card.midX, y: card.minY + 300))
        try focus(app, page)
        try app.press("cmd+f")
        try app.waitUntil("repeated Find focuses its existing query") {
            try app.native().firstResponder.hasSuffix(":" + ViewID.findQuery.identifier)
        }
        try app.press("cmd+a")
        try app.type("apple")
        try matches(app, 6)
        try app.screenshot("repeated-find-focus")
    }

}
