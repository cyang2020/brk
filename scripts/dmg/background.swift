// Draws the background of the Brk disk image (scripts/make-dmg.sh): a soft light canvas, a curved arrow from the
// app's place on the left to the Applications folder on the right, and one line telling the user what to do.
// The icon places are fixed in scripts/dmg/settings.py (app at 170,190; Applications at 490,190 in a 660x400 window).
//
//   swift scripts/dmg/background.swift scripts/dmg
//
// writes background.png (660x400) and background@2x.png (1320x800); make-dmg.sh joins them into one TIFF so Finder
// picks the sharp one on Retina screens.
import AppKit

let width: CGFloat = 660, height: CGFloat = 400
let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Canvas: a light vertical gradient with a faint warm tint at the top.
    let colors = [NSColor(srgbRed: 0.995, green: 0.975, blue: 0.955, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.945, green: 0.950, blue: 0.965, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])

    // The arrow, in AppKit's bottom-up coordinates: Finder's icon centre y=190 (top-down) is 210 here.
    let y: CGFloat = height - 190
    let ink = NSColor(srgbRed: 0.20, green: 0.22, blue: 0.27, alpha: 0.55)
    ink.setStroke()
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 262, y: y + 6))
    shaft.curve(to: NSPoint(x: 392, y: y + 6), controlPoint1: NSPoint(x: 300, y: y + 36), controlPoint2: NSPoint(x: 354, y: y + 36))
    shaft.lineWidth = 3
    shaft.lineCapStyle = .round
    shaft.setLineDash([0.01, 9], count: 2, phase: 0)
    shaft.stroke()
    // The head points along the curve's last direction (from the second control point to the end).
    let tip = NSPoint(x: 396, y: y + 3), along = atan2(-30.0, 38.0), wing: CGFloat = 13
    let head = NSBezierPath()
    head.move(to: NSPoint(x: tip.x - wing * cos(along - .pi / 5), y: tip.y - wing * sin(along - .pi / 5)))
    head.line(to: tip)
    head.line(to: NSPoint(x: tip.x - wing * cos(along + .pi / 5), y: tip.y - wing * sin(along + .pi / 5)))
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // The instruction, centred near the bottom.
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let text = NSAttributedString(string: "Drag Brk into Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.20, green: 0.22, blue: 0.27, alpha: 0.80),
        .paragraphStyle: style,
    ])
    text.draw(in: NSRect(x: 0, y: 62, width: width, height: 24))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: out.appendingPathComponent("background.png"))
try render(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))
print("wrote \(out.path)/background.png and background@2x.png")
