import AppKit
// usage: zone2 <png>... : which drop preview shows in a 1280x776 pt window capture (content card at x 228..1270, y 10..766)
for path in CommandLine.arguments.dropFirst() {
    guard let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: path))) else { continue }
    func px(_ x: Double, _ y: Double) -> Int { let c = rep.colorAt(x: Int(x * 2), y: Int(y * 2))!.usingColorSpace(.sRGB)!; return Int((c.redComponent * 255).rounded()) + Int((c.greenComponent * 255).rounded()) + Int((c.blueComponent * 255).rounded()) }
    let frame = px(229, 400) < 420 && px(1268.5, 400) < 420
    func pane(_ x: Double, _ y: Double) -> Bool { px(x, y) <= 759 }      // a drop pane's pale fill; a page's margin is white (764 or 765)
    let tl = pane(238, 24), tr = pane(1260, 24), bl = pane(238, 752), br = pane(1260, 752)
    let kind = frame ? "MIDDLE" : bl && br && !tl ? "BOTTOM" : tl && tr && !bl ? "TOP" : bl && !br ? "LEFT" : br && !bl ? "RIGHT" : !tl && !tr && !bl && !br ? "none" : "? \(tl) \(tr) \(bl) \(br)"
    print((path as NSString).lastPathComponent.padding(toLength: 34, withPad: " ", startingAt: 0), kind)
}
