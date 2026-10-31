import BrkBase
import BrkDomain
import BrkLayout
import SwiftUI

struct ThemeToolsEditor: View {
    @Binding var theme: SpaceTheme
    @State private var scheme: Scheme = .light
    @State private var selected = 0
    @State private var presetPage = 0
    @State private var undo: [SpaceTheme] = []

    private var variants: ThemeVariants { theme.variants ?? ThemeVariants(legacy: theme) }
    private var style: ThemeStyle { (scheme == .dark ? variants.dark : variants.light).normalized }
    private var preview: ResolvedTheme {
        var value = theme
        var pair = variants; pair.selection = scheme == .dark ? .dark : .light
        value.variants = pair
        return resolveTheme(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SpaceToolsSchemePicker(scheme: $scheme).onChange(of: scheme) { selected = 0 }
                SpaceToolsButton(title: "Undo", id: "theme-undo") {
                    if let old = undo.popLast() { theme = old; selected = 0 }
                }.disabled(undo.isEmpty)

            }
            Text("Drag a color to place it. Select a dot to change its color.").font(.caption).foregroundStyle(.secondary)
            GeometryReader { geometry in
                ThemePadPreview(theme: preview)
                    .overlay {
                        ForEach(Array(style.colors.enumerated()), id: \.offset) { index, stop in
                            Circle().fill(stop.color.swiftUI)
                                .overlay(Circle().stroke(index == selected ? Color.primary : .white, lineWidth: 3))
                                .frame(width: 22, height: 22)
                                .position(x: stop.position.x * geometry.size.width, y: stop.position.y * geometry.size.height)
                                .onTapGesture { selected = index }
                                .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                                    selected = index
                                    change { $0.colors[index].position = ThemePoint(x: event.location.x / geometry.size.width, y: event.location.y / geometry.size.height) }
                                })
                                .accessibilityLabel("Color \(index + 1) position")
                                .spaceToolsID("theme-point-\(index)")
                        }
                    }
            }.frame(height: Metrics.spaceTools.editorPadHeight.value).clipped().cornerRadius(Metrics.spaceTools.toolbarRadius.value)
            HStack {
                ColorPicker("Selected color", selection: Binding(get: {
                    style.colors[min(selected, style.colors.count - 1)].color.swiftUI
                }, set: { value in
                    let color = NSColor(value).usingColorSpace(.sRGB) ?? .black
                    change { $0.colors[min(selected, $0.colors.count - 1)].color = RGBA(color.redComponent, color.greenComponent, color.blueComponent) }
                }), supportsOpacity: false)
                SpaceToolsButton(title: "Add color", id: "theme-add") {
                    change { $0.colors.append(ThemeColor(color: ThemePresets.brand[($0.colors.count * 3) % 9], position: ThemePoint.anchors[$0.colors.count])) }
                    selected = style.colors.count - 1
                }.disabled(style.colors.count >= 3).spaceToolsID("theme-add")
                SpaceToolsButton(title: "Remove color", id: "theme-remove") { change { $0.colors.remove(at: min(selected, $0.colors.count - 1)) }; selected = 0 }
                    .disabled(style.colors.count <= 1).spaceToolsID("theme-remove")
            }
            HStack {
                SpaceToolsButton(title: "←", id: "theme-presets-previous") { presetPage = (presetPage + 3) % 4 }
                Text(presetSets[presetPage].name).frame(maxWidth: .infinity)
                SpaceToolsButton(title: "→", id: "theme-presets-next") { presetPage = (presetPage + 1) % 4 }
            }
            HStack {
                ForEach(Array(presetSets[presetPage].colors.enumerated()), id: \.offset) { index, color in
                    SpaceToolsButton(title: "Preset \(color.hex)", id: "theme-preset-\(index)", color: color) {
                        change { $0.colors[min(selected, $0.colors.count - 1)].color = color }
                    }

                }
            }
            control("Saturation", \.saturation, range: 0...2)
            control("Lightness", \.lightness, range: -1...1)
            control("Dark bias", \.darkBias, range: 0...1, enabled: scheme == .dark)
            control("Noise", \.noise, range: 0...1)
            control("Intensity", \.intensity, range: 0...1)
            Picker("Color wheel", selection: binding(\.wheel)) {
                ForEach(ColorWheel.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("Texture", selection: binding(\.texture)) {
                ForEach(Texture.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("Display appearance", selection: Binding(get: { variants.selection }, set: { selection in
                remember(); var pair = variants; pair.selection = selection; theme.variants = pair
            })) {
                Text("System").tag(AppearanceChoice.auto); Text("Light").tag(AppearanceChoice.light); Text("Dark").tag(AppearanceChoice.dark)
            }.spaceToolsID("theme-appearance")
        }
    }

    private func control(_ title: String, _ key: WritableKeyPath<ThemeStyle, Double>, range: ClosedRange<Double>, enabled: Bool = true) -> some View {
        HStack {
            Text(title).frame(width: 76, alignment: .leading)
            Slider(value: binding(key), in: range).disabled(!enabled)
                .accessibilityLabel(title).spaceToolsID("theme-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
        }
    }
    private func binding<T>(_ key: WritableKeyPath<ThemeStyle, T>) -> Binding<T> {
        Binding(get: { style[keyPath: key] }, set: { value in change { $0[keyPath: key] = value } })
    }
    private func remember() { undo.append(theme); if undo.count > 80 { undo.removeFirst() } }
    private func change(_ update: (inout ThemeStyle) -> Void) {
        remember()
        var pair = variants
        var value = style; update(&value); value = value.normalized
        if scheme == .dark { pair.dark = value } else { pair.light = value }
        theme.variants = pair
    }
}

struct ThemePadPreview: View {
    let theme: ResolvedTheme
    var body: some View {
        Canvas { context, size in
            let cells = 80
            for y in 0..<cells {
                for x in 0..<cells {
                    let color = themePreviewSample(theme, at: ThemePoint(x: (Double(x) + 0.5) / Double(cells), y: (Double(y) + 0.5) / Double(cells)))
                    context.fill(Path(CGRect(x: Double(x) / Double(cells) * size.width, y: Double(y) / Double(cells) * size.height,
                                             width: size.width / Double(cells) + 1, height: size.height / Double(cells) + 1)), with: .color(color.swiftUI))
                }
            }
        }
    }
}
