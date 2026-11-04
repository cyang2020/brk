import AppKit
import BrkBase
import BrkDomain
import BrkUIKit
import SwiftUI

// The drawings Arc 1.170 puts in its settings panes (P38-b, P38-c, P38-e, P38-f), redrawn with shapes: the wavy-edged
// banners of Max and Links, Max's flowers and lettering, the feature thumbnails, the Shortcuts key caps. Arc ships
// these as images; Brk draws them so nothing of Arc's artwork is copied. Positions are the captures' pixels halved.

private var A: SettingsArtMetricsTable { ArtMetrics }

/// sRGB colours sampled from the captures.
enum ArtColor {
    static func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
    static let maxBlue = rgb(0x333DFF)
    static let maxInk = rgb(0x3139FB)
    static let flower = rgb(0xFF9999)
    static let cream = rgb(0xFFFCEA)
    static let littlePink = rgb(0xFFA0A4)
    static let littleBody = rgb(0xF5CCC9)
    static let mockChrome = rgb(0xE1E2F3)
    static let mockField = rgb(0xD5D5E8)
    static let keyBlue = rgb(0x007AFF)
    static let keyFace = rgb(0xE1EBFF)
}

/// A rectangle whose bottom edge is a wave (Arc's banners: 20-point period). The edge is highest `phase` points from
/// the left edge and every period after it.
struct WavyBottom: Shape {
    var period: CGFloat = ArtMetrics.wavePeriod.value
    var amplitude: CGFloat = ArtMetrics.waveAmplitude.value
    var phase: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.maxY - amplitude
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: mid))
        var x = rect.maxX
        while x > rect.minX {
            let step = max(1, period / 16)
            x -= step
            let y = mid + amplitude * sin((x - rect.minX - phase) / period * 2 * .pi - .pi / 2)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }
}

/// The banners' grain: a tile of faint light and dark specks, made once.
enum Grain {
    @MainActor static let tile: NSImage = {
        let side = 96
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        for _ in 0..<1400 {
            let light = next() > 0.5
            // Faint: Arc's grain varies a channel by 3 levels or so (P38-b's blue, standard deviation 2.8)
            (light ? NSColor.white : NSColor.black).withAlphaComponent(0.02 + next() * 0.04).setFill()
            NSRect(x: next() * Double(side), y: next() * Double(side), width: 0.5 + next() * 0.8, height: 0.5 + next() * 0.8).fill()
        }
        image.unlockFocus()
        return image
    }()
}

struct GrainOverlay: View {
    var body: some View {
        Image(nsImage: Grain.tile).resizable(resizingMode: .tile).allowsHitTesting(false)
    }
}

/// Max's flower (P38-b): four round petals, each split by a slit from the middle, around a small tilted square. The
/// Enable Max icon's flower is also outlined in the slits' blue.
struct MaxFlower: View {
    var size: CGFloat
    var color: Color = ArtColor.flower
    var hole: Color = ArtColor.maxInk
    var outline: CGFloat = 0

    var body: some View {
        ZStack {
            if outline > 0 { petals(hole, grow: outline * 2) }
            petals(color, grow: 0)
            ForEach(0..<4, id: \.self) { index in
                Capsule().fill(hole).frame(width: size * 0.36, height: size * 0.085)
                    .offset(x: size * 0.17).rotationEffect(.degrees(45 + Double(index) * 90))
            }
            RoundedRectangle(cornerRadius: size * 0.04).fill(hole).frame(width: size * 0.31, height: size * 0.31).rotationEffect(.degrees(10))
            RoundedRectangle(cornerRadius: size * 0.02).fill(color).frame(width: size * 0.2, height: size * 0.2).rotationEffect(.degrees(10))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-12))
    }

    private func petals(_ fill: Color, grow: CGFloat) -> some View {
        ForEach(0..<4, id: \.self) { index in
            Circle().fill(fill).frame(width: size * 0.47 + grow, height: size * 0.47 + grow)
                .offset(x: size * 0.265).rotationEffect(.degrees(45 + Double(index) * 90))
        }
    }
}

/// Text as a path, so it can be outlined (the banner's lettering).
enum GlyphPath {
    static func path(_ text: String, font: NSFont) -> CGPath {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let result = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String] as! CTFont
            for (glyph, position) in zip(glyphs, positions) {
                guard let outline = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
                // Flip to SwiftUI's top-left origin, baseline at the font's ascent.
                let transform = CGAffineTransform(translationX: position.x, y: CTFontGetAscent(runFont)).scaledBy(x: 1, y: -1)
                result.addPath(outline, transform: transform)
            }
        }
        return result
    }

    static func roundedBlack(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .black)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
}

/// One outlined letter of the banner's lettering.
struct OutlinedLetter: View {
    let letter: String
    let size: CGFloat

    var body: some View {
        let path = Path(GlyphPath.path(letter, font: GlyphPath.roundedBlack(size)))
        let bounds = path.boundingRect
        ZStack(alignment: .topLeading) {
            path.stroke(ArtColor.cream, style: StrokeStyle(lineWidth: A.letterStroke.value, lineCap: .round, lineJoin: .round))
            path.fill(ArtColor.maxInk)
        }
        .frame(width: bounds.maxX, height: bounds.maxY, alignment: .topLeading)
    }
}

// MARK: - Banners

/// Max's banner (P38-b): the blue band with flowers and the outlined MAX lettering, wavy at the bottom.
struct MaxBanner: View {
    /// Flower centres and sizes in points from the banner's top-left (P38-b's pixels halved).
    private static let flowers: [(CGFloat, CGFloat, CGFloat)] = [
        (7, 9, 24), (205, 19, 16), (102, 76, 38), (444, 13, 24), (479, 57, 24), (676, 87, 30),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ArtColor.maxBlue
            GrainOverlay()
            ForEach(Array(Self.flowers.enumerated()), id: \.offset) { _, flower in
                MaxFlower(size: flower.2).position(x: flower.0, y: flower.1)
            }
            HStack(alignment: .center, spacing: A.letterSpacing.value) {
                OutlinedLetter(letter: "M", size: A.letterSize.value).rotationEffect(.degrees(-6))
                OutlinedLetter(letter: "A", size: A.letterSize.value).rotationEffect(.degrees(4)).offset(y: 3)
                OutlinedLetter(letter: "X", size: A.letterSize.value).rotationEffect(.degrees(-5))
            }
            .position(x: A.logoCenter.value.x, y: A.logoCenter.value.y)
            MaxFlower(size: 19).position(x: 289, y: 64)
        }
        .frame(width: Metrics.settings.windowSize.value.width, height: A.maxBannerHeight.value)
        .clipShape(WavyBottom(phase: A.maxWavePhase.value))
    }
}

/// Links' banner (P38-f): a Little window over the pink band, wavy at the bottom.
struct LittleBrkBanner: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            ArtColor.littlePink
            LittleWindowMock()
                .frame(width: A.mockSize.value.width, height: A.mockSize.value.height)
                .offset(x: A.mockOrigin.value.x, y: A.mockOrigin.value.y)
        }
        .frame(width: Metrics.settings.windowSize.value.width, height: A.littleBannerHeight.value)
        .clipShape(WavyBottom(amplitude: A.littleWaveAmplitude.value))
    }
}

/// The Little window drawn in the Links banner: traffic lights, the space pill, the host, "Open in" with its shortcut.
struct LittleWindowMock: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: A.mockGap.value) {
                HStack(spacing: A.mockDotGap.value) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.black.opacity(0.12)).frame(width: A.mockDot.value, height: A.mockDot.value) }
                }
                ZStack {
                    RoundedRectangle(cornerRadius: A.mockRadius.value, style: .continuous).fill(ArtColor.mockField)
                    HStack {
                        HStack(spacing: 3) {
                            Image(systemName: "face.smiling").font(.system(size: 7, weight: .semibold))
                            Text("Work").font(.system(size: 7, weight: .semibold))
                        }
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.55)))
                        .padding(.leading, 5)
                        Spacer()
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill").font(.system(size: 6)).foregroundStyle(.secondary)
                        Text("example.com").font(.system(size: 7.5, weight: .semibold))
                    }
                }
                .frame(height: A.mockField.value)
                HStack(spacing: 4) {
                    Text("Open in").font(.system(size: 7.5)).foregroundStyle(.secondary)
                    + Text(" Work").font(.system(size: 7.5, weight: .semibold)).foregroundColor(ArtColor.rgb(0x3E5A7A))
                    Text("⌘O").font(.system(size: 6.5, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 2).background(RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.07)))
                    Rectangle().fill(Color.black.opacity(0.1)).frame(width: 0.5, height: 10)
                    Image(systemName: "chevron.down").font(.system(size: 6, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 5)
                .frame(height: A.mockField.value)
                .background(RoundedRectangle(cornerRadius: A.mockRadius.value, style: .continuous).fill(Color.white))
            }
            .padding(.horizontal, A.mockPadding.value)
            .frame(height: A.mockChromeHeight.value)
            ZStack {
                ArtColor.littleBody
                GrainOverlay()
            }
            .clipShape(RoundedRectangle(cornerRadius: A.mockRadius.value, style: .continuous))
            .padding(.horizontal, A.mockBodyInset.value)
        }
        .background(RoundedRectangle(cornerRadius: A.mockCorner.value, style: .continuous).fill(ArtColor.mockChrome))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    }
}

// MARK: - Max thumbnails

/// The picture at the left of a Max feature card (P38-b, P38-c), 88 by 56 points.
struct MaxThumbnail: View {
    let feature: MaxFeature
    /// The local tool's name on the command bar card's chip (Arc's reads ChatGPT).
    var provider: String? = nil

    var body: some View {
        ZStack {
            content
        }
        .frame(width: A.thumbSize.value.width, height: A.thumbSize.value.height)
        .clipShape(RoundedRectangle(cornerRadius: A.thumbRadius.value, style: .continuous))
        .padding(A.thumbFrame.value)
        .background(RoundedRectangle(cornerRadius: A.thumbRadius.value + A.thumbFrame.value, style: .continuous).fill(Color.white))
    }

    @ViewBuilder private var content: some View {
        switch feature {
        case .tidyTabs:
            ArtColor.rgb(0xD6D2F2)
            HStack(spacing: 8) {
                WaveLine().stroke(ArtColor.rgb(0x8A84B8), lineWidth: 1.2).frame(width: 44, height: 6)
                Image(nsImage: ArcGlyphs.broom(size: 11)).renderingMode(.template).foregroundStyle(ArtColor.rgb(0x5E5A86))
                Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)).foregroundStyle(ArtColor.rgb(0x5E5A86))
            }
            .offset(x: -2)
        case .instantLinks:
            // P38-c: a 15.5 pt teal band, the line 11 pt below it, two 7.5 pt bars 5.5 pt apart
            ArtColor.rgb(0xD3E9F3)
            VStack(spacing: 0) {
                ArtColor.rgb(0x6CBAD8).frame(height: 15.5)
                HStack(spacing: 4) {
                    Image(systemName: "rays").font(.system(size: 8)).foregroundStyle(.secondary)
                    Text("Searching the web…").font(.system(size: 7, weight: .semibold)).foregroundStyle(ArtColor.rgb(0x2B3A55))
                        .lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5).frame(height: 22)
                VStack(spacing: 5.5) {
                    RoundedRectangle(cornerRadius: 2).fill(ArtColor.rgb(0xBCD0D9)).frame(height: 7.5)
                    RoundedRectangle(cornerRadius: 2).fill(ArtColor.rgb(0xBCD0D9)).frame(height: 7.5)
                }
                .padding(.horizontal, 7)
                Spacer(minLength: 0)
            }
        case .linkPreviews:
            ArtColor.rgb(0xC9CBFD)
            VStack(spacing: 0) {
                LinearGradient(colors: [ArtColor.rgb(0x3A2E25), ArtColor.rgb(0x9B7A4E), ArtColor.rgb(0x5B4632)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(GrainOverlay())
                    .frame(height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 0.5).fill(Color.black.opacity(0.35)).frame(width: index == 3 ? 40 : 60, height: 1.5)
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
            }
            .padding(.horizontal, 10).padding(.top, 8)
        case .tidyTitles:
            ArtColor.rgb(0xA7729D)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1).fill(ArtColor.rgb(0x4A2B5C)).frame(width: 7, height: 5)
                    Text("Interior Design Book").font(.system(size: 6, weight: .semibold)).foregroundStyle(ArtColor.rgb(0x3F4BD8))
                }
                Text("Double-click to rename").font(.system(size: 4.5)).foregroundStyle(ArtColor.rgb(0x3F4BD8)).padding(.leading, 10)
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
        case .tidyDownloads:
            ArtColor.rgb(0x303AFB)
            VStack(alignment: .leading, spacing: 1.5) {
                HStack {
                    Text("Download renamed to:").font(.system(size: 4.5)).foregroundStyle(ArtColor.rgb(0x5960C8))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 4)).foregroundStyle(.secondary)
                    Image(systemName: "xmark").font(.system(size: 4)).foregroundStyle(.secondary)
                }
                Text("Navan Itinerary.pdf").font(.system(size: 6, weight: .medium)).foregroundStyle(.black)
                Text("287494875.pdf").font(.system(size: 4.5)).strikethrough().foregroundStyle(ArtColor.rgb(0x5960C8))
            }
            .padding(5)
            .frame(width: 74)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
        case .askInCommandBar:
            ArtColor.rgb(0x19C27B)
            HStack(spacing: 3) {
                Image(systemName: "magnifyingglass").font(.system(size: 5, weight: .semibold))
                Text(provider ?? "Max").font(.system(size: 5, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1.5).background(Capsule().fill(ArtColor.rgb(0x4CAF5C)))
                Text("Send a message").font(.system(size: 5.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(width: 92, height: 18, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white))
            .offset(x: 12)
        }
    }
}

/// The squiggle in the Tidy Tabs thumbnail.
struct WaveLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        var x = rect.minX
        while x < rect.maxX {
            x += 0.5
            path.addLine(to: CGPoint(x: x, y: rect.midY + rect.height / 2 * sin((x - rect.minX) / 8 * 2 * .pi)))
        }
        return path
    }
}

// MARK: - Shortcuts

/// One of the two blue key caps beside the Shortcuts list (P38-e): ⌘, and a smile of two strokes and a curve. The cap
/// is system blue with a lighter rim at the top and a deeper front at the bottom; the face is pale blue with a white
/// hairline.
struct KeyCapArt: View {
    enum Glyph { case command, smile }
    let glyph: Glyph

    var body: some View {
        let face = RoundedRectangle(cornerRadius: A.keyFaceRadius.value, style: .continuous)
        RoundedRectangle(cornerRadius: A.keyRadius.value, style: .continuous)
            .fill(LinearGradient(colors: [ArtColor.rgb(0x4590FE), ArtColor.rgb(0x3881EE)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: A.keyRadius.value, style: .continuous).strokeBorder(ArtColor.keyBlue, lineWidth: 1))
            .overlay(alignment: .top) {
                face.fill(LinearGradient(colors: [ArtColor.keyFace, ArtColor.rgb(0xD3E1FB)], startPoint: .top, endPoint: .bottom))
                    .overlay(face.strokeBorder(ArtColor.rgb(0xF4F8FF), lineWidth: 0.75))
                    .overlay(mark)
                    .padding(.horizontal, A.keyInset.value).padding(.top, A.keyInset.value).padding(.bottom, A.keyFront.value)
            }
            .frame(width: A.keySize.value.width, height: A.keySize.value.height)
    }

    @ViewBuilder private var mark: some View {
        switch glyph {
        case .command:
            Image(systemName: "command").font(.system(size: A.keyGlyph.value, weight: .bold)).foregroundStyle(ArtColor.keyBlue)
        case .smile:
            ZStack {
                HStack(spacing: 8.5) {
                    ForEach(0..<2, id: \.self) { _ in Capsule().fill(ArtColor.keyBlue).frame(width: 3, height: 10) }
                }
                .offset(y: -6.5)
                SmileCurve().stroke(ArtColor.keyBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(width: 25, height: 6).offset(y: 9)
            }
        }
    }
}

/// The smile under the key cap's two strokes.
struct SmileCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height))
        return path
    }
}

/// Shortcuts' "…" beside Reset All Shortcuts (P38-e): three dots in a white circle with a grey hairline, as an image
/// so the menu button can show it.
enum MoreCircle {
    @MainActor static let image: NSImage = {
        let side = A.moreCircle.value
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            NSColor.white.setFill(); ring.fill()
            NSColor(white: 0xDB / 255.0, alpha: 1).setStroke(); ring.lineWidth = 1; ring.stroke()
            NSColor(white: 0x2C / 255.0, alpha: 1).setFill()
            for index in -1...1 {
                let x = rect.midX + CGFloat(index) * 4.75
                NSBezierPath(ovalIn: CGRect(x: x - 1.15, y: rect.midY - 1.15, width: 2.3, height: 2.3)).fill()
            }
            return true
        }
        return image
    }()
}

// MARK: - Metrics

let ArtMetrics = SettingsArtMetricsTable()

struct SettingsArtMetricsTable: MetricGroup {
    private static let capture = "verify/visual-pairs/run-20261103/P38"
    let wavePeriod = Metric(20.0, .anatomy("\(capture)/P38-b-arc.png: wave crests at x 10, 50, 90 px"))
    let waveAmplitude = Metric(2.5, .anatomy("\(capture)/P38-b-arc.png: the edge runs between y 417 and 427 px"))
    let maxWavePhase = Metric(5.0, .anatomy("\(capture)/P38-b-arc.png: the edge is highest (417 px) at x 10, 50, 90 px and lowest (427 px) at 30, 70 px"))
    let littleWaveAmplitude = Metric(2.0, .anatomy("\(capture)/P38-f-arc.png: the edge runs between y 438 px (x 0, 40 px) and 446 px (x 20 px)"))
    let maxBannerHeight = Metric(125.5, .anatomy("\(capture)/P38-b-arc.png: blue from the toolbar hairline at 176 px to the wave's lowest at 427 px"))
    let littleBannerHeight = Metric(135.0, .anatomy("\(capture)/P38-f-arc.png: pink from 176 px to the wave's lowest at 446 px"))
    let letterSize = Metric(50.0, .guess("the MAX lettering spans x 556 to 792 px in P38-b"))
    let letterStroke = Metric(8.0, .anatomy("\(capture)/P38-b-arc.png: the cream outline is 8 px of 2x, half of it outside the letter"))
    let letterSpacing = Metric(-4.0, .guess("the letters of the lettering overlap a little"))
    let logoCenter = Metric(CGPoint(x: 340, y: 64), .anatomy("\(capture)/P38-b-arc.png: lettering centred near x 680, y 304 px"))
    let mockOrigin = Metric(CGPoint(x: 60, y: 47), .anatomy("\(capture)/P38-f-arc.png: the window drawing starts at x 120, y 270 px"))
    let mockSize = Metric(CGSize(width: 563, height: 120), .anatomy("\(capture)/P38-f-arc.png: the window drawing spans x 120 to 1246 px and runs under the wave"))
    let mockChromeHeight = Metric(27.0, .anatomy("\(capture)/P38-f-arc.png: its title bar spans y 270 to 325 px"))
    let mockField = Metric(18.0, .anatomy("\(capture)/P38-f-arc.png: the address field spans y 280 to 316 px"))
    let mockPadding = Metric(5.0, .guess("the drawing's title bar inset"))
    let mockGap = Metric(6.0, .guess("space between the drawing's dots, field and button"))
    let mockDot = Metric(7.0, .anatomy("\(capture)/P38-f-arc.png: the three dots are 14 px wide, 23 px apart"))
    let mockDotGap = Metric(4.5, .anatomy("\(capture)/P38-f-arc.png: the three dots are 23 px apart"))
    let mockRadius = Metric(4.0, .guess("the drawing's field and body corners"))
    let mockCorner = Metric(7.0, .guess("the drawing's window corner"))
    let mockBodyInset = Metric(3.0, .anatomy("\(capture)/P38-f-arc.png: the page body is inset 6 px from the drawing's sides"))
    let thumbSize = Metric(CGSize(width: 88, height: 56), .anatomy("\(capture)/P38-b-arc.png: thumbnails span x 154 to 330 px, y 832 to 944 px"))
    let thumbRadius = Metric(3.0, .guess("a thumbnail's corner"))
    let thumbFrame = Metric(1.5, .anatomy("\(capture)/P38-b-arc.png: a white rim of about 3 px around each thumbnail"))
    let keySize = Metric(CGSize(width: 66, height: 65), .anatomy("\(capture)/P38-e-arc.png: the first key cap spans x 838 to 970 px, y 347 to 477 px"))
    let keyRadius = Metric(12.0, .guess("the key caps' corner"))
    let keyFaceRadius = Metric(9.0, .guess("the key cap face's corner"))
    let keyInset = Metric(5.0, .anatomy("\(capture)/P38-e-arc.png: the face starts 10 px in from the cap's left, right and top edges"))
    let keyFront = Metric(10.5, .anatomy("\(capture)/P38-e-arc.png: the face ends at y 456 px, the cap at 477 px"))
    let keyGlyph = Metric(26.0, .guess("the ⌘ on the key cap"))
    let moreCircle = Metric(24.0, .anatomy("\(capture)/P38-e-arc.png: the … circle spans x 1127 to 1175 px, y 1198 to 1246 px; dots 9.5 px apart"))
}
