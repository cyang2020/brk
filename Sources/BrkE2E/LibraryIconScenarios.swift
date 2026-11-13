import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation

/// Owner: W3. The Library button's picture moves under the real pointer as Arc's `BoxOfThingsIcon` does: the star,
/// triangle and dot above the box turn and rise while the pointer is on the button and settle back when it leaves.
/// The real pointer matters: the motion hangs on the button's own hover tracking, which an injected hover skips.
enum LibraryIconScenarios {
    static let all = [
        Scenario("LibraryIcon-HoverReal", "the real pointer on the Library button turns and lifts the star, triangle and dot above the box; leaving puts them back", cefOnly: "window-server pointer", hover),
    ]

    private static func screen(_ app: AppUnderTest, _ point: CGPoint) throws -> CGPoint {
        let frame = try app.native().windowFrame
        return CGPoint(x: frame.minX + point.x, y: CGDisplayBounds(CGMainDisplayID()).height - frame.maxY + point.y)
    }

    private static func jump(_ app: AppUnderTest, to point: CGPoint) throws {
        let at = try screen(app, point)
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        guard case .hello(let hello) = try app.send(.hello), let front = PhysicalPointer.frontmost(at: at), front.pid == hello.pid else {
            throw Check(description: "another window is in front of Brk at \(at); real pointer not moved")
        }
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// The window picture's grey levels over `area` (window points), one per pixel.
    private static func greys(_ app: AppUnderTest, _ name: String, _ area: CGRect) throws -> [Int] {
        let shot = try app.screenshot(name)
        guard let provider = CGDataProvider(url: shot.url as CFURL),
              let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw Check(description: "screenshot \(shot.url.lastPathComponent) unreadable")
        }
        let scale = Double(image.width) / max(1, try app.native().contentSize.width)
        let rect = CGRect(x: area.minX * scale, y: area.minY * scale, width: area.width * scale, height: area.height * scale).integral
        guard let crop = image.cropping(to: rect) else { throw Check(description: "the button area is outside the picture") }
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: crop.width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return true
        }
        guard drawn else { throw Check(description: "no bitmap context") }
        return bytes.map(Int.init)
    }

    private static func changed(_ a: [Int], _ b: [Int]) -> Int { zip(a, b).filter { abs($0 - $1) > 40 }.count }

    @Sendable static func hover(_ app: AppUnderTest) throws {
        try app.dispatch(.space(.update(try app.view().space.id, title: nil, icon: nil, theme: LibraryFlyoutScenarios.sky)))
        try app.settle()
        let button = try visible(app.native(), .dockLibrary).frame
        // The pieces above the box: the 28 x 13 strip from 3 pt below the button's top edge.
        let strip = CGRect(x: button.minX + 2, y: button.minY + 3, width: button.width - 4, height: 13)
        let area = try app.native().computed.contentArea
        try jump(app, to: CGPoint(x: area.midX, y: area.midY))
        app.sleep(0.8)
        let rest = try greys(app, "rest", strip)
        try jump(app, to: CGPoint(x: button.midX, y: button.midY + 6))
        app.sleep(0.9)
        let hovered = try greys(app, "hovered", strip)
        try expect(changed(rest, hovered) >= 40, "the pieces above the box did not move under the pointer (\(changed(rest, hovered)) pixels changed)")
        try jump(app, to: CGPoint(x: area.midX, y: area.midY))
        app.sleep(0.9)
        let back = try greys(app, "back", strip)
        try expect(changed(rest, back) <= 8, "the pieces did not settle back after the pointer left (\(changed(rest, back)) pixels differ from rest)")
        app.passed("the real pointer on the Library button moved \(changed(rest, hovered)) pixels of the star, triangle and dot; leaving restored them (\(changed(rest, back)) differ)")
    }
}
