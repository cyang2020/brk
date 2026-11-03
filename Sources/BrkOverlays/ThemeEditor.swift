import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

// Owner: W4 (dialogs). Arc's theme panel (Spaces > Edit Theme…, the space menu's Edit Theme Color…, and Choose a
// Theme in the Create a Space flow), matched to the 2026-11-03 Arc 1.170 captures (P24 c, P28 a/b/c/e): from top to
// bottom the appearance buttons (auto ✦, light ☀, dark ☾) inside a dotted color pad with one dot per base color,
// − and + (remove and add a base color), a page of nine preset dots with arrows (Brand, Pastel, Drab, Greyscale),
// and at the bottom the wave-shaped intensity slider and the noise knob. No name, icon, Save or Cancel: every edit
// is reported at once (`onChange`), and Esc or a click outside closes the panel.

/// The panel's numbers, measured on the Arc capture P28-a-arc-editor.png (764 x 1068 px at 2x).
struct ThemePanelMetrics: MetricGroup {
    let window = Metric(CGSize(width: 382, height: 534), .guess("Arc's theme panel window, measured on P28-a-arc-editor.png (764 x 1068 px at 2x)"))
    let card = Metric(CGSize(width: 356, height: 508), .guess("the visible rounded panel inside that window, 13 pt from each edge, measured on P28-a"))
    let margin = Metric(13.0, .guess("transparent shadow margin around the visible panel, measured on P28-a"))
    let cornerRadius = Metric(20.0, .guess("visible panel corner radius, measured on P28-a"))
    let padInset = Metric(8.0, .guess("color pad inset from the panel edge, measured on P28-a"))
    let padSide = Metric(340.0, .guess("the square color pad, measured on P28-a"))
    let padRadius = Metric(12.0, .guess("color pad corner radius, measured on P28-a"))
    let padDotPitch = Metric(4.0, .guess("dot grid pitch inside the pad, measured on P28-a"))
    let appearanceY = Metric(40.0, .guess("appearance buttons' centre below the pad top, measured on P28-a"))
    let appearancePitch = Metric(40.0, .guess("distance between the three appearance buttons, measured on P28-a"))
    let appearanceSide = Metric(32.0, .guess("appearance button square, measured on P28-a"))
    let stepperY = Metric(308.0, .guess("− and + centres below the pad top, measured on P28-a"))
    let stepperPitch = Metric(40.0, .guess("distance between − and +, measured on P28-a"))
    let selectedDot = Metric(45.0, .guess("the selected base color's dot including its 5 pt white ring, measured on P28-a"))
    let otherDot = Metric(26.0, .guess("another base color's dot including its 3 pt white ring, measured on P28-b"))
    let presetY = Metric(380.0, .guess("preset row centre below the panel top, measured on P28-a"))
    let presetDot = Metric(24.0, .guess("preset dot diameter, measured on P28-a"))
    let presetPitch = Metric(29.5, .guess("preset dot pitch, measured on P28-a"))
    let presetFirstX = Metric(60.0, .guess("first preset dot centre from the panel's left edge, measured on P28-a"))
    let arrowInset = Metric(23.0, .guess("page arrows' centres from the panel edges, measured on P28-a"))
    let controlsY = Metric(452.0, .guess("slider and knob centres below the panel top, measured on P28-a"))
    let sliderX = Metric([18.0, 242.0], .guess("intensity slider track from and to, measured on P28-a"))
    let sliderTrack = Metric(16.0, .guess("intensity track height, measured on P28-a"))
    let wavelength = Metric(40.0, .guess("crest to crest on the wave, measured on P28-a"))
    let waveAmplitude = Metric([1.0, 17.0], .guess("wave half height at intensity 0 and 1, measured on P28-e1 and P28-e2"))
    let handle = Metric(CGSize(width: 24, height: 55), .guess("white slider handle, measured on P28-a"))
    let knobX = Metric(298.0, .guess("noise knob centre from the panel's left edge, measured on P28-a"))
    let knobRadius = Metric([20.0, 33.0], .guess("noise knob's inner circle and tick ring radii, measured on P28-a"))
    let knobTicks = Metric(20, .guess("tick dots around the noise knob, counted on P28-a"))
}

let ThemePanel = ThemePanelMetrics()

/// What the panel edits: a space theme in the editor's representation (`ThemeVariants`). Each edit applies to the
/// light and the dark values alike, since Arc's panel shows one set of colors; the legacy fields follow the light
/// values so readers of `colors` see the same primary.
struct ThemeDraft: Equatable {
    var theme: SpaceTheme
    var systemScheme: Scheme = .light

    var variants: ThemeVariants {
        if let variants = theme.variants { return variants }
        var pair = ThemeVariants(legacy: theme)
        pair.selection = theme.appearance
        return pair
    }
    var appearance: AppearanceChoice { variants.selection }
    var scheme: Scheme {
        switch appearance {
        case .auto: systemScheme
        case .light: .light
        case .dark: .dark
        }
    }
    var style: ThemeStyle { (scheme == .dark ? variants.dark : variants.light).normalized }
    var colors: [RGBA] { style.colors.map(\.color) }
    var resolved: ResolvedTheme { resolveTheme(theme, systemScheme: systemScheme) }

    mutating func edit(_ update: (inout ThemeStyle) -> Void) {
        var pair = variants
        var light = pair.light.normalized, dark = pair.dark.normalized
        update(&light); update(&dark)
        pair.light = light.normalized
        pair.dark = dark.normalized
        theme.variants = pair
        theme.colors = pair.light.colors.map(\.color)
        theme.intensity = pair.light.intensity
        theme.noise = pair.light.noise
        theme.appearance = pair.selection
    }

    mutating func setAppearance(_ choice: AppearanceChoice) {
        var pair = variants
        pair.selection = choice
        theme.variants = pair
        theme.appearance = choice
    }

    mutating func setColor(_ color: RGBA, at index: Int) {
        edit { style in if style.colors.indices.contains(index) { style.colors[index].color = color } }
    }

    /// The new base color sits opposite the primary on the pad (Arc adds the complement, P28 b), the third a
    /// quarter turn on. At most three.
    mutating func addColor() {
        edit { style in
            guard style.colors.count < 3, let primary = style.colors.first?.color else { return }
            let hsl = HSL(primary)
            let turn = style.colors.count == 1 ? 180.0 : 90.0
            style.colors.append(ThemeColor(color: HSL(hue: hsl.hue + turn, saturation: hsl.saturation, lightness: hsl.lightness).rgba,
                                           position: ThemePoint.anchors[style.colors.count]))
        }
    }

    /// Removes the given base color, or the last one when the primary is given. Never the only one.
    mutating func removeColor(at index: Int) {
        edit { style in
            guard style.colors.count > 1 else { return }
            style.colors.remove(at: index > 0 && index < style.colors.count ? index : style.colors.count - 1)
        }
    }

    mutating func setIntensity(_ value: Double) { edit { $0.intensity = min(max(value, 0), 1) } }
    mutating func setNoise(_ value: Double) { edit { $0.noise = min(max(value, 0), 1) } }
}

/// The color pad is a hue wheel (read off the Arc captures: the cream preset #F2EAE4, hue 24°, sits 29° below the
/// right-hand axis, and the complement Arc adds sits opposite it at the same distance). Angle, clockwise from the
/// right on screen, is the hue; distance from the centre is the lightness (cream, lightness 0.92, sits at 0.82 of
/// the inscribed radius, so lightness = 0.1 + distance). Saturation is not on the pad: it stays the dot's own.
enum ThemePad {
    /// The dot's place for `color`, both axes 0...1 from the pad's top-left.
    static func point(of color: RGBA) -> CGPoint {
        let hsl = HSL(color)
        let radius = min(max(hsl.lightness - 0.1, 0), 0.9) * 0.5
        let angle = hsl.hue * .pi / 180
        return CGPoint(x: 0.5 + radius * cos(angle), y: 0.5 + radius * sin(angle))
    }

    /// The color at `point` for a dot whose saturation is `saturation`. A grey dot dragged on the pad takes a
    /// middle saturation, so moving it picks a hue.
    static func color(at point: CGPoint, saturation: Double) -> RGBA {
        let dx = point.x - 0.5, dy = point.y - 0.5
        let distance = min(hypot(dx, dy) / 0.5, 0.9)
        var hue = atan2(dy, dx) * 180 / .pi
        if hue < 0 { hue += 360 }
        return HSL(hue: hue, saturation: saturation < 0.05 ? 0.5 : saturation, lightness: 0.1 + distance).rgba
    }
}

/// Hue in degrees 0..<360, saturation and lightness 0...1.
struct HSL: Equatable {
    var hue: Double, saturation: Double, lightness: Double

    init(hue: Double, saturation: Double, lightness: Double) {
        self.hue = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        self.saturation = min(max(saturation, 0), 1)
        self.lightness = min(max(lightness, 0), 1)
    }

    init(_ c: RGBA) {
        let high = max(c.red, c.green, c.blue), low = min(c.red, c.green, c.blue)
        let l = (high + low) / 2, d = high - low
        guard d > 1e-9 else { self.init(hue: 0, saturation: 0, lightness: l); return }
        let s = d / (1 - abs(2 * l - 1))
        let h: Double = if high == c.red { ((c.green - c.blue) / d).truncatingRemainder(dividingBy: 6) }
            else if high == c.green { (c.blue - c.red) / d + 2 }
            else { (c.red - c.green) / d + 4 }
        self.init(hue: h * 60, saturation: s, lightness: l)
    }

    var rgba: RGBA {
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - c / 2
        let (r, g, b): (Double, Double, Double) = switch hue {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        return RGBA(min(max(r + m, 0), 1), min(max(g + m, 0), 1), min(max(b + m, 0), 1))
    }
}

/// The draft as SwiftUI observes it. The host replaces `draft` when the snapshot moves on (each reported edit comes
/// back as the space's stored theme); the panel's own state (selected dot, preset page) survives that.
@MainActor
final class ThemeEditorModel: ObservableObject {
    @Published var draft: ThemeDraft
    /// False in the Create a Space flow until a color is picked: the pad says "Tap to pick a color for this space".
    @Published var chosen: Bool
    var onChange: (ThemeDraft) -> Void

    init(draft: ThemeDraft, chosen: Bool = true, onChange: @escaping (ThemeDraft) -> Void = { _ in }) {
        self.draft = draft
        self.chosen = chosen
        self.onChange = onChange
    }

    func update(_ change: (inout ThemeDraft) -> Void) {
        var next = draft
        change(&next)
        chosen = true
        guard next != draft else { return }
        draft = next
        onChange(next)
    }
}

struct ThemeEditorView: View {
    @ObservedObject var model: ThemeEditorModel
    @State private var selected = 0
    @State private var page: Int
    @Environment(\.colorScheme) private var colorScheme

    init(model: ThemeEditorModel) {
        self.model = model
        let primary = model.draft.colors.first
        _page = State(initialValue: ThemePresets.pages.firstIndex { $0.colors.contains { $0 == primary } } ?? 0)
    }

    private var ink: Color { colorScheme == .dark ? .white : .black }
    private var colors: [RGBA] { model.draft.colors }
    private var current: Int { min(selected, max(colors.count - 1, 0)) }
    private let m = ThemePanel

    var body: some View {
        ZStack(alignment: .topLeading) {
            pad.frame(width: m.padSide.value, height: m.padSide.value).position(x: m.card.value.width / 2, y: m.padInset.value + m.padSide.value / 2)
            presets.frame(width: m.card.value.width, height: m.presetDot.value + 8).position(x: m.card.value.width / 2, y: m.presetY.value)
            WaveSlider(value: model.draft.style.intensity, ink: ink, enabled: model.chosen) { value in model.update { $0.setIntensity(value) } }
                .frame(width: m.sliderX.value[1] - m.sliderX.value[0], height: m.handle.value.height)
                .position(x: (m.sliderX.value[0] + m.sliderX.value[1]) / 2, y: m.controlsY.value)
                .accessibilityLabel("Intensity")
                .spaceToolsID("theme-intensity")
            NoiseKnob(value: model.draft.style.noise, ink: ink, enabled: model.chosen) { value in model.update { $0.setNoise(value) } }
                .frame(width: m.knobRadius.value[1] * 2 + 8, height: m.knobRadius.value[1] * 2 + 8)
                .position(x: m.knobX.value, y: m.controlsY.value)
                .accessibilityLabel("Noise")
                .spaceToolsID("theme-noise")
        }
        .frame(width: m.card.value.width, height: m.card.value.height)
        .spaceToolsID("theme-panel")
    }

    // MARK: Pad

    private var pad: some View {
        let side = m.padSide.value
        return ZStack {
            RoundedRectangle(cornerRadius: m.padRadius.value, style: .continuous).fill(ink.opacity(colorScheme == .dark ? 0.06 : 0.0))
            DotGrid(pitch: m.padDotPitch.value, color: ink.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: m.padRadius.value, style: .continuous))
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { event in
                    // A tap on the pad moves the selected dot there (the primary in a fresh draft).
                    let point = CGPoint(x: event.location.x / side, y: event.location.y / side)
                    let index = model.chosen ? current : 0
                    let saturation = colors.indices.contains(index) ? HSL(colors[index]).saturation : 0.6
                    model.update { $0.setColor(ThemePad.color(at: point, saturation: saturation), at: index) }
                })
                .spaceToolsID("theme-pad")
            if model.chosen {
                ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                    let point = ThemePad.point(of: color)
                    ColorDot(color: color, big: index == current)
                        .position(x: point.x * side, y: point.y * side)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                            selected = index
                            let p = CGPoint(x: event.location.x / side, y: event.location.y / side)
                            model.update { $0.setColor(ThemePad.color(at: p, saturation: HSL(color).saturation), at: index) }
                        })
                        .accessibilityLabel("Color \(index + 1)")
                        .spaceToolsID("theme-point-\(index)")
                }
            } else {
                Text("Tap to pick a color for this space").font(.system(size: 13, weight: .semibold)).foregroundStyle(ink.opacity(0.6))
                    .allowsHitTesting(false)
            }
            appearanceButtons.position(x: side / 2, y: m.appearanceY.value)
            steppers.position(x: side / 2, y: m.stepperY.value)
        }
    }

    private var appearanceButtons: some View {
        HStack(spacing: m.appearancePitch.value - m.appearanceSide.value) {
            ForEach([(AppearanceChoice.auto, "sparkles"), (.light, "sun.max.fill"), (.dark, "moon.stars.fill")], id: \.0) { choice, symbol in
                let on = model.draft.appearance == choice
                Button { model.update { $0.setAppearance(choice) } } label: {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.6))
                        .frame(width: m.appearanceSide.value, height: m.appearanceSide.value)
                        .background(RoundedRectangle(cornerRadius: m.appearanceSide.value / 4, style: .continuous).fill(ink.opacity(on ? 0.08 : 0)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(OverlayCopy.appearanceName(choice))
                .accessibilityLabel(OverlayCopy.appearanceName(choice))
                .accessibilityAddTraits(on ? .isSelected : [])
                .spaceToolsID("theme-appearance-\(choice.rawValue)")
            }
        }
    }

    private var steppers: some View {
        HStack(spacing: m.stepperPitch.value - 24) {
            stepper("minus", id: "theme-remove", enabled: model.chosen && colors.count > 1) {
                model.update { $0.removeColor(at: current) }
                selected = 0
            }
            stepper("plus", id: "theme-add", enabled: model.chosen && colors.count < 3) {
                model.update { $0.addColor() }
                selected = model.draft.colors.count - 1
            }
        }
    }

    private func stepper(_ symbol: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(ink.opacity(enabled ? 0.6 : 0.2))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "Add color" : "Remove color")
        .spaceToolsID(id)
    }

    // MARK: Presets

    private var presets: some View {
        let set = ThemePresets.pages[page]
        let picked = colors.indices.contains(current) && model.chosen ? colors[current] : nil
        return ZStack {
            arrow("chevron.left", id: "theme-presets-previous", enabled: page > 0) { page -= 1 }
                .position(x: m.arrowInset.value, y: (m.presetDot.value + 8) / 2)
            ForEach(Array(set.colors.enumerated()), id: \.offset) { index, color in
                Button { model.update { $0.setColor(color, at: model.chosen ? current : 0) } } label: {
                    Circle().fill(color.swiftUI)
                        .overlay(Circle().strokeBorder(color == picked ? Color.white : ink.opacity(0.1), lineWidth: color == picked ? 3 : 1))
                        .frame(width: m.presetDot.value, height: m.presetDot.value)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(OverlayCopy.setColor(color.hex))
                .accessibilityLabel(OverlayCopy.setColor(color.hex))
                .spaceToolsID("theme-preset-\(index)")
                .position(x: m.presetFirstX.value + Double(index) * m.presetPitch.value, y: (m.presetDot.value + 8) / 2)
            }
            arrow("chevron.right", id: "theme-presets-next", enabled: page < ThemePresets.pages.count - 1) { page += 1 }
                .position(x: m.card.value.width - m.arrowInset.value, y: (m.presetDot.value + 8) / 2)
        }
        .accessibilityLabel(set.name)
    }

    private func arrow(_ symbol: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(ink.opacity(enabled ? 0.6 : 0.2))
                .frame(width: 24, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .spaceToolsID(id)
    }
}

/// One base color on the pad: the selected one large with a 5 pt white ring, the others small with a 3 pt ring.
private struct ColorDot: View {
    let color: RGBA
    let big: Bool
    var body: some View {
        let side = big ? ThemePanel.selectedDot.value : ThemePanel.otherDot.value
        Circle().fill(Color.white)
            .overlay(Circle().fill(color.swiftUI).padding(big ? 5 : 3))
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            .contentShape(Circle())
    }
}

private struct DotGrid: View {
    let pitch: Double
    let color: Color
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var y = pitch / 2
            while y < size.height {
                var x = pitch / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1))
                    x += pitch
                }
                y += pitch
            }
            context.fill(path, with: .color(color))
        }
    }
}

/// Arc's intensity slider: the track is a wave whose height follows the value (flat at 0, tallest at 1), darker left
/// of the white handle than right of it.
private struct WaveSlider: View {
    let value: Double
    let ink: Color
    let enabled: Bool
    let change: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let m = ThemePanel
            let width = geometry.size.width, mid = geometry.size.height / 2
            let handle = m.handle.value
            let x = handle.width / 2 + value * (width - handle.width)
            let amplitude = m.waveAmplitude.value[0] + (m.waveAmplitude.value[1] - m.waveAmplitude.value[0]) * value
            ZStack(alignment: .topLeading) {
                Capsule().fill(ink.opacity(0.07))
                    .frame(width: width, height: m.sliderTrack.value).position(x: width / 2, y: mid)
                wave(from: 6, to: x, mid: mid, amplitude: amplitude).stroke(ink.opacity(0.55), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                wave(from: x, to: width - 6, mid: mid, amplitude: amplitude).stroke(ink.opacity(0.22), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                RoundedRectangle(cornerRadius: handle.width / 2, style: .continuous).fill(Color.white)
                    .frame(width: handle.width, height: handle.height)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .position(x: x, y: mid)
            }
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                change(min(max((event.location.x - handle.width / 2) / max(width - handle.width, 1), 0), 1))
            })
        }
    }

    private func wave(from start: Double, to end: Double, mid: Double, amplitude: Double) -> Path {
        var path = Path()
        guard end > start else { return path }
        let k = 2 * Double.pi / ThemePanel.wavelength.value
        path.move(to: CGPoint(x: start, y: mid - amplitude * sin(k * (start - 6))))
        var x = start
        while x < end {
            x = min(x + 1, end)
            path.addLine(to: CGPoint(x: x, y: mid - amplitude * sin(k * (x - 6))))
        }
        return path
    }
}

/// Arc's noise knob: a ring of tick dots, an inner circle, and a white pointer on the ring; 0 at the lower left,
/// 0.5 straight up, 1 at the lower right. Dragging turns it.
private struct NoiseKnob: View {
    let value: Double
    let ink: Color
    let enabled: Bool
    let change: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let m = ThemePanel
            let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let ring = m.knobRadius.value[1], inner = m.knobRadius.value[0]
            let pointer = (-90 + (value - 0.5) * 270) * Double.pi / 180
            ZStack {
                ForEach(0..<m.knobTicks.value, id: \.self) { tick in
                    let angle = Double(tick) / Double(m.knobTicks.value) * 2 * Double.pi
                    Circle().fill(ink.opacity(0.22)).frame(width: 4, height: 4)
                        .position(x: centre.x + ring * cos(angle), y: centre.y + ring * sin(angle))
                }
                Circle().stroke(ink.opacity(0.22), lineWidth: 1).frame(width: inner * 2, height: inner * 2).position(centre)
                Capsule().fill(Color.white).frame(width: 7, height: 16)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
                    .rotationEffect(.radians(pointer + Double.pi / 2))
                    .position(x: centre.x + ring * cos(pointer), y: centre.y + ring * sin(pointer))
            }
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                var degrees = atan2(event.location.y - centre.y, event.location.x - centre.x) * 180 / Double.pi + 90
                if degrees > 180 { degrees -= 360 }
                change(min(max(degrees / 270 + 0.5, 0), 1))
            })
        }
    }
}

/// The Edit Theme panel: a borderless panel beside the sidebar, its top at the window's middle (where Arc opens it,
/// P28 b), over the window but never key, so Esc still reaches the browser window's menu.
@MainActor
final class ThemePanelWindow {
    private let panel: NSPanel
    private let model: ThemeEditorModel
    private var monitor: Any?
    private var shown = false
    private let close: () -> Void
    var space: SpaceID

    init(space: SpaceID, draft: ThemeDraft, onChange: @escaping (ThemeDraft) -> Void, close: @escaping () -> Void) {
        self.space = space
        self.close = close
        model = ThemeEditorModel(draft: draft, onChange: onChange)
        let m = ThemePanel
        panel = NSPanel(contentRect: CGRect(origin: .zero, size: m.window.value), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        let container = NSView(frame: CGRect(origin: .zero, size: m.window.value))
        let effect = NSVisualEffectView(frame: CGRect(x: m.margin.value, y: m.margin.value, width: m.card.value.width, height: m.card.value.height))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = .roundedMask(radius: m.cornerRadius.value)
        let hosting = FirstClickHostingView(rootView: ThemeEditorView(model: model))
        hosting.frame = effect.bounds
        effect.addSubview(hosting)
        container.addSubview(effect)
        container.identify(.spaceToolsControl("theme-panel-window"))
        panel.contentView = container
    }

    func update(_ draft: ThemeDraft) { if model.draft != draft { model.draft = draft } }

    /// Shows the panel over `window`, its left edge at the sidebar's right edge and its top at the window's middle,
    /// moved up as far as needed to stay on the screen.
    func show(over window: NSWindow, sidebarMaxX: Double, scheme: Scheme) {
        panel.appearance = .of(scheme)
        let size = ThemePanel.window.value
        var origin = CGPoint(x: window.frame.minX + sidebarMaxX, y: window.frame.midY - size.height)
        if let screen = window.screen?.visibleFrame { origin.y = max(origin.y, screen.minY) }
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        if !shown {
            shown = true
            panel.order(.above, relativeTo: window.windowNumber)
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { if let self, event.window !== self.panel { self.close() } }
                return event
            }
        }
    }

    func dismiss() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        shown = false
        panel.orderOut(nil)
    }
}

extension NSImage {
    /// A stretchable rounded-rectangle mask for an NSVisualEffectView.
    static func roundedMask(radius: Double) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// SwiftUI content that takes the first click: Arc's popovers and panel act on it, where a plain hosting view in a
/// window that is not key only makes that window key.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSViewController {
    /// A controller whose view is `FirstClickHostingView(rootView:)`, for an NSPopover.
    @MainActor
    static func firstClick<Content: View>(_ root: Content) -> NSViewController {
        let controller = NSViewController()
        controller.view = FirstClickHostingView(rootView: root)
        return controller
    }
}
