import AppKit
import Foundation

// regions <arc.png> <brk.png> [--out out.png] [--crop x y w h]  (crop in points; images are 2x)
// Prints the differing share and the differing regions: differing pixels are grouped on a 16 pt grid into connected
// blocks, biggest first, with the block's box in points, its differing pixel count and its share of the whole image.
// --out writes Arc | Brk | difference for the crop at full size.

func load(_ path: String) -> CGImage? {
    NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
}
func rgba(_ img: CGImage) -> ([UInt8], Int, Int) {
    let w = img.width, h = img.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    return (Array(UnsafeBufferPointer(start: p, count: w * h * 4)), w, h)
}
let args = CommandLine.arguments
guard args.count >= 3, let arc = load(args[1]), let brk = load(args[2]) else { print("usage: regions arc brk [--out f] [--crop x y w h]"); exit(2) }
var outPath: String? = nil
var crop: (Int, Int, Int, Int)? = nil
var cell = 8
var i = 3
while i < args.count {
    if args[i] == "--out" { outPath = args[i + 1]; i += 2 }
    else if args[i] == "--crop" { crop = (Int(args[i + 1])!, Int(args[i + 2])!, Int(args[i + 3])!, Int(args[i + 4])!); i += 5 }
    else if args[i] == "--cell" { cell = Int(args[i + 1])!; i += 2 }
    else { i += 1 }
}
let (pa, wa, ha) = rgba(arc)
let (pb, wb, hb) = rgba(brk)
let w = min(wa, wb), h = min(ha, hb)
let thr = Int(ProcessInfo.processInfo.environment["THR"] ?? "24")!
// CGContext rows are bottom up in memory only for drawing; the premultiplied buffer starts at the image's top row here
// when read through the context's data pointer (row 0 is the top), which is how scan.swift reads it.
var mask = [Bool](repeating: false, count: w * h)
var total = 0
for y in 0..<h {
    for x in 0..<w {
        let oa = (y * wa + x) * 4, ob = (y * wb + x) * 4
        if abs(Int(pa[oa]) - Int(pb[ob])) > thr || abs(Int(pa[oa + 1]) - Int(pb[ob + 1])) > thr || abs(Int(pa[oa + 2]) - Int(pb[ob + 2])) > thr {
            mask[y * w + x] = true; total += 1
        }
    }
}
print(String(format: "share %.2f%%  (%d of %d)  sizes %dx%d vs %dx%d", 100 * Double(total) / Double(w * h), total, w * h, wa, ha, wb, hb))
// grid
let gc = cell * 2
let gw = w / gc + 1, gh = h / gc + 1
var count = [Int](repeating: 0, count: gw * gh)
for y in 0..<h { for x in 0..<w where mask[y * w + x] { count[(y / gc) * gw + x / gc] += 1 } }
var seen = [Bool](repeating: false, count: gw * gh)
struct Block { var x0: Int, y0: Int, x1: Int, y1: Int, n: Int }
var blocks: [Block] = []
for gy in 0..<gh { for gx in 0..<gw {
    guard count[gy * gw + gx] > 0, !seen[gy * gw + gx] else { continue }
    var stack = [(gx, gy)]; seen[gy * gw + gx] = true
    var b = Block(x0: gx, y0: gy, x1: gx, y1: gy, n: 0)
    while let (cx, cy) = stack.popLast() {
        b.n += count[cy * gw + cx]; b.x0 = min(b.x0, cx); b.x1 = max(b.x1, cx); b.y0 = min(b.y0, cy); b.y1 = max(b.y1, cy)
        for dy in -1...1 { for dx in -1...1 {
            let nx = cx + dx, ny = cy + dy
            if nx >= 0, ny >= 0, nx < gw, ny < gh, count[ny * gw + nx] > 0, !seen[ny * gw + nx] { seen[ny * gw + nx] = true; stack.append((nx, ny)) }
        } }
    }
    blocks.append(b)
} }
blocks.sort { $0.n > $1.n }
for b in blocks.prefix(25) {
    // exact box within the block's grid area
    var mx0 = w, my0 = h, mx1 = -1, my1 = -1
    for y in (b.y0 * gc)..<min(h, (b.y1 + 1) * gc) { for x in (b.x0 * gc)..<min(w, (b.x1 + 1) * gc) where mask[y * w + x] {
        mx0 = min(mx0, x); mx1 = max(mx1, x); my0 = min(my0, y); my1 = max(my1, y)
    } }
    // the shift of the Brk image that best matches Arc inside this box (position errors show a big drop)
    var best = (dx: 0, dy: 0, n: Int.max)
    let R = 16
    let area = (mx1 - mx0 + 1) * (my1 - my0 + 1)
    if area < 1_200_000 {
        for dy in -R...R { for dx in -R...R {
            var n = 0
            for y in my0...my1 { for x in mx0...mx1 {
                let bx = x + dx, by = y + dy
                guard bx >= 0, by >= 0, bx < wb, by < hb else { n += 1; continue }
                let oa = (y * wa + x) * 4, ob = (by * wb + bx) * 4
                if abs(Int(pa[oa]) - Int(pb[ob])) > thr || abs(Int(pa[oa + 1]) - Int(pb[ob + 1])) > thr || abs(Int(pa[oa + 2]) - Int(pb[ob + 2])) > thr { n += 1 }
            } }
            if n < best.n { best = (dx, dy, n) }
        } }
    }
    let shift = best.n == Int.max ? "" : String(format: "  brk shift %+.1f,%+.1f pt leaves %d of %d", -Double(best.dx) / 2, -Double(best.dy) / 2, best.n, b.n)
    print(String(format: "  %5.2f%%  x %d..%d  y %d..%d pt  (%dx%d)", 100 * Double(b.n) / Double(w * h), mx0 / 2, mx1 / 2, my0 / 2, my1 / 2, (mx1 - mx0 + 1) / 2, (my1 - my0 + 1) / 2) + shift)
}
if let outPath {
    let (cx, cy, cw, ch) = crop ?? (0, 0, w / 2, h / 2)
    let px = cx * 2, py = cy * 2, pw = min(cw * 2, w - px), ph = min(ch * 2, h - py)
    let gap = 12
    let W = pw * 3 + gap * 2, H = ph
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let cropRect = CGRect(x: px, y: py, width: pw, height: ph)
    if let a = arc.cropping(to: cropRect) { ctx.draw(a, in: CGRect(x: 0, y: 0, width: pw, height: ph)) }
    if let b = brk.cropping(to: cropRect) { ctx.draw(b, in: CGRect(x: pw + gap, y: 0, width: pw, height: ph)) }
    if let b = brk.cropping(to: cropRect) { ctx.setAlpha(0.3); ctx.draw(b, in: CGRect(x: (pw + gap) * 2, y: 0, width: pw, height: ph)); ctx.setAlpha(1) }
    ctx.setFillColor(CGColor(red: 0.9, green: 0.15, blue: 0.25, alpha: 1))
    for y in 0..<ph { for x in 0..<pw where mask[(y + py) * w + x + px] {
        ctx.fill(CGRect(x: (pw + gap) * 2 + x, y: ph - 1 - y, width: 1, height: 1))
    } }
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
    print("wrote \(outPath) \(W)x\(H)")
}
