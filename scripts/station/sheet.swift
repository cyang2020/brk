import AppKit
import Foundation

// sheet <out.png> <label> <arc.png> <brk.png> [<label> <arc.png> <brk.png> ...]
// One row per pair: label and the differing-pixel share on the left, then Arc, Brk and a difference heat map at
// one third scale. Also prints "<label>\t<diff%>\t<bbox>" per row so the numbers can be kept in a table.
// Pixels count as different when any channel differs by more than 24/255; the heat map paints those red over a
// faded copy of the Brk image. Images of different sizes are compared on their common top-left area.

func load(_ path: String) -> CGImage? {
    NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

func rgba(_ img: CGImage) -> (UnsafeMutablePointer<UInt8>, Int, Int)? {
    let w = img.width, h = img.height
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let data = ctx.data else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
    p.update(from: data.assumingMemoryBound(to: UInt8.self), count: w * h * 4)
    return (p, w, h)
}

struct Row { let label: String; let arc: CGImage?; let brk: CGImage?; var heat: CGImage?; var share = -1.0; var box = "" }

let a = CommandLine.arguments
guard a.count >= 5, (a.count - 2) % 3 == 0 else { print("usage: sheet out.png label arc brk [...]"); exit(2) }
var rows: [Row] = []
var i = 2
while i + 2 < a.count {
    var row = Row(label: a[i], arc: load(a[i + 1]), brk: load(a[i + 2]))
    if let arc = row.arc, let brk = row.brk, let (pa, wa, ha) = rgba(arc), let (pb, wb, hb) = rgba(brk),
       let heat = CGContext(data: nil, width: wb, height: hb, bitsPerComponent: 8, bytesPerRow: wb * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
       let heatData = heat.data {
        let w = min(wa, wb), h = min(ha, hb)
        heat.setAlpha(0.35); heat.draw(brk, in: CGRect(x: 0, y: 0, width: wb, height: hb)); heat.setAlpha(1)
        let hp = heatData.assumingMemoryBound(to: UInt8.self)
        var diff = 0, minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let oa = (y * wa + x) * 4, ob = (y * wb + x) * 4
                if abs(Int(pa[oa]) - Int(pb[ob])) > 24 || abs(Int(pa[oa + 1]) - Int(pb[ob + 1])) > 24 || abs(Int(pa[oa + 2]) - Int(pb[ob + 2])) > 24 {
                    diff += 1
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    // the three buffers share the same bottom-up row order, so write at the same row
                    let oh = (y * wb + x) * 4
                    hp[oh] = 230; hp[oh + 1] = 40; hp[oh + 2] = 60; hp[oh + 3] = 255
                }
            }
        }
        row.share = Double(diff) / Double(w * h)
        row.box = maxX < 0 ? "none" : "\(minX / 2),\((h - 1 - maxY) / 2)-\(maxX / 2),\((h - 1 - minY) / 2)pt"
        row.heat = heat.makeImage()
        pa.deallocate(); pb.deallocate()
        if wa != wb || ha != hb { row.box += " (sizes \(wa)x\(ha) vs \(wb)x\(hb))" }
    } else if row.arc != nil && row.brk != nil {
        row.box = "比较失败（内存不足？）"
        FileHandle.standardError.write(Data("sheet: could not allocate buffers for \(row.label)\n".utf8))
    }
    rows.append(row)
    i += 3
}

let scale = 1.0 / 3.0, gutter = 16.0, labelWidth = 150.0
let cellW = rows.map { Double(max($0.arc?.width ?? 0, $0.brk?.width ?? 0)) * scale }.max() ?? 400
let rowH = rows.map { Double(max($0.arc?.height ?? 0, $0.brk?.height ?? 0)) * scale }.max() ?? 250
let W = Int(labelWidth + 3 * cellW + 4 * gutter), H = Int(Double(rows.count) * (rowH + gutter) + gutter + 24)
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write(Data("sheet: could not allocate the sheet canvas \(W)x\(H)\n".utf8)); exit(3)
}
ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
ctx.interpolationQuality = .high
let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = ns
let font = NSFont.systemFont(ofSize: 13, weight: .semibold), small = NSFont.systemFont(ofSize: 11)
func text(_ s: String, _ x: Double, _ y: Double, _ f: NSFont, _ c: NSColor = .black) {
    (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: f, .foregroundColor: c])
}
for (k, head) in ["Arc", "Brk", "差异（红）"].enumerated() {
    text(head, labelWidth + gutter + Double(k) * (cellW + gutter), Double(H) - 20, font, .darkGray)
}
for (r, row) in rows.enumerated() {
    let top = Double(H) - 28 - gutter - Double(r + 1) * (rowH + gutter) + gutter
    text(row.label, gutter, top + rowH - 18, font)
    if row.share >= 0 { text(String(format: "差异 %.1f%%", row.share * 100), gutter, top + rowH - 36, small, row.share > 0.02 ? .systemRed : .darkGray) }
    text(row.box.isEmpty ? (row.arc == nil ? "缺 Arc 图" : "缺 Brk 图") : row.box, gutter, top + rowH - 52, small, .darkGray)
    for (k, img) in [row.arc, row.brk, row.heat].enumerated() {
        guard let img else { continue }
        let x = labelWidth + gutter + Double(k) * (cellW + gutter)
        let w = Double(img.width) * scale, h = Double(img.height) * scale
        ctx.draw(img, in: CGRect(x: x, y: top + rowH - h, width: w, height: h))
    }
    print("\(row.label)\t\(row.share >= 0 ? String(format: "%.2f%%", row.share * 100) : "n/a")\t\(row.box)")
}
guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, "public.png" as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("sheet: could not write \(a[1])\n".utf8)); exit(3)
}
CGImageDestinationAddImage(dest, out, nil); CGImageDestinationFinalize(dest)
print("wrote \(a[1]) \(W)x\(H)")
fflush(stdout)
