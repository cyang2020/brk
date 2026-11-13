import BrkBase
import BrkDomain
import Foundation

/// Arc's sidebar (~/Library/Application Support/Arc/StorableSidebar.json) as Brk Spaces. Brk's sidebar is rebuilt from
/// Arc's, so the mapping is one to one: each Space keeps its name, icon and theme; its "pinned" container becomes
/// Pinned and its "unpinned" container Today; lists become folders, split views splits; each Arc profile's top-apps
/// container becomes that profile's Favorites. Arc writes its lists as alternating id, value pairs.
public enum ArcSidebar {
    public struct Result: Sendable {
        public var spaces: [ImportedSpace] = []
        /// Favorites by Arc profile folder ("Default" for Arc's default profile).
        public var favorites: [String: [ImportNode]] = [:]
        /// Arc profile folder of each Space, by `ImportedSpace.key`.
        public var spaceProfiles: [String: String] = [:]
    }

    /// `profileNames`: Arc profile folder to its name (Local State); a Space of a profile other than Arc's default lands
    /// in the Brk profile of that name.
    public static func read(_ data: Data, profileNames: [String: String] = [:]) throws -> Result {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let containers = (root["sidebar"] as? [String: Any])?["containers"] as? [Any],
              let container = containers.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] != nil }) else {
            throw SidebarDataError.invalid("Arc's sidebar file has no Spaces")
        }
        let items = Dictionary(pairs(container["items"]).compactMap { value -> (String, [String: Any])? in
            guard let item = value as? [String: Any], let id = item["id"] as? String else { return nil }
            return (id, item)
        }, uniquingKeysWith: { first, _ in first })

        // Each item once: Arc gives an item one parent, and a file that lists a child twice (or under itself) would
        // otherwise build the subtree again at every level, 2^32 times.
        var placed: Set<String> = []
        func node(_ id: String, depth: Int) -> ImportNode? {
            guard depth < 32, placed.insert(id).inserted, let item = items[id], let data = item["data"] as? [String: Any] else { return nil }
            let custom = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if let tab = data["tab"] as? [String: Any] {
                guard let raw = tab["savedURL"] as? String, let url = URL(string: raw), SidebarImport.publicURL(url) else { return nil }
                return .tab(title: custom ?? (tab["savedTitle"] as? String ?? ""), url: url)
            }
            let children = (item["childrenIds"] as? [String] ?? []).compactMap { node($0, depth: depth + 1) }
            if data["list"] != nil { return .folder(title: custom ?? "Folder", children: children) }
            if let split = data["splitView"] as? [String: Any] {
                let panes = children.filter { if case .tab = $0 { true } else { false } }
                guard panes.count >= 2 else { return panes.first }
                return .split(orientation: (split["layoutOrientation"] as? String) == "vertical" ? .vertical : .horizontal, panes: panes)
            }
            return nil   // welcome page, easels, notes and other Arc-only rows
        }
        func contents(_ container: String?) -> [ImportNode] {
            guard let container, let item = items[container] else { return [] }
            return (item["childrenIds"] as? [String] ?? []).compactMap { node($0, depth: 0) }
        }

        var result = Result()
        var untitled = 0
        for value in pairs(container["spaces"]) {
            guard let space = value as? [String: Any], let id = space["id"] as? String else { continue }
            var ids: [String: String] = [:]
            let list = space["containerIDs"] as? [Any] ?? []
            var index = 0
            while index + 1 < list.count {
                if let kind = list[index] as? String, let container = list[index + 1] as? String { ids[kind] = container }
                index += 2
            }
            let folder = profileFolder(space["profile"])
            let info = space["customInfo"] as? [String: Any]
            var title = (space["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                untitled += 1
                title = id == "thebrowser.company.defaultPersonalSpaceID" ? "Personal" : "Space \(untitled)"
            }
            let key = "arc:" + id
            result.spaces.append(ImportedSpace(key: key, title: title, icon: icon(info?["iconType"]), theme: theme(info?["windowTheme"]),
                                               profileName: folder == "Default" ? nil : (profileNames[folder] ?? folder),
                                               pinned: contents(ids["pinned"]), today: contents(ids["unpinned"])))
            result.spaceProfiles[key] = folder
        }
        let topApps = container["topAppsContainerIDs"] as? [Any] ?? []
        var index = 0
        while index + 1 < topApps.count {
            if let containerID = topApps[index + 1] as? String { result.favorites[profileFolder(topApps[index]), default: []] += contents(containerID) }
            index += 2
        }
        return result
    }

    /// The values of Arc's alternating [id, value, id, value] lists (a plain list of values is read as it is).
    static func pairs(_ value: Any?) -> [Any] {
        guard let list = value as? [Any] else { return [] }
        return list.filter { !($0 is String) }
    }

    /// `{"default": true}` is Arc's default profile, "Default"; `{"custom": {"_0": {"directoryBasename": "Profile 1"}}}` another.
    static func profileFolder(_ value: Any?) -> String {
        guard let profile = value as? [String: Any], let custom = profile["custom"] as? [String: Any] else { return "Default" }
        let inner = (custom["_0"] as? [String: Any]) ?? custom
        return inner["directoryBasename"] as? String ?? "Default"
    }

    /// `{"icon": "planet"}` (one of Arc's named icons) or `{"emoji_v2": "🌀", "emoji": 127744}`.
    static func icon(_ value: Any?) -> SpaceIcon {
        guard let type = value as? [String: Any] else { return .none }
        if let emoji = type["emoji_v2"] as? String, !emoji.isEmpty { return .custom(.emoji(emoji)) }
        if let scalar = (type["emoji"] as? Int).flatMap(Unicode.Scalar.init) { return .custom(.emoji(String(Character(scalar)))) }
        if let name = type["icon"] as? String, let named = NamedIcon(rawValue: name) { return .custom(.named(named)) }
        return .none
    }

    /// Arc's window theme (`WindowTheme`). Its background is `single` (one style) or `appearanceBased` (a light and a
    /// dark style, shown by macOS's mode), each style holding its colors (one for `blendedSingleColor`; base and overlay
    /// colors for `blendedGradient`), intensity, noise, texture and translucency. A pair becomes a light/dark pair that follows
    /// the system. A style without colors to read (Arc's old named `basicColor`s) takes the theme's own palette color
    /// instead of Brk's default beige. Nil when there is no background at all.
    static func theme(_ value: Any?) -> SpaceTheme? {
        guard let window = value as? [String: Any], let background = window["background"] else { return nil }
        let paletteColor = color((window["primaryColorPalette"] as? [String: Any])?["shaded"])
        if let pair = (background as? [String: Any])?["appearanceBased"] as? [String: Any] {
            let light = pair["light"].flatMap { style($0, paletteColor: paletteColor) }
            let dark = pair["dark"].flatMap { style($0, paletteColor: paletteColor) }
            guard var theme = light ?? dark else { return nil }
            if let light, let dark {
                var variants = ThemeVariants(legacy: light)
                variants.dark = ThemeStyle(legacy: dark)
                variants.selection = .auto
                theme.variants = variants
            }
            return theme
        }
        return style(background, paletteColor: paletteColor)
    }

    /// One background style. Arc's slider (`intensityFactor`) shows more of the color the further right it is; Brk's
    /// intensity is the strength of the wash over the color, so it is stored as 1 - intensityFactor (a navy Space at
    /// 0.73 came in nearly white). `translucencyStyle` is "light" for Arc's automatic button too (Arc does not save the
    /// sun button, and a saved "light" theme follows macOS's dark mode), so only "dark" is kept.
    static func style(_ background: Any, paletteColor: RGBA?) -> SpaceTheme? {
        guard let style = firstDictionary(in: background, containing: "modifiers") else {
            return paletteColor.map { SpaceTheme(colors: [$0], texture: .grain, intensity: SpaceTheme.default.intensity, appearance: .auto) }
        }
        var colors: [RGBA] = []
        // A gradient is up to two base colors (the diagonal ramp) and the overlay's visible color (the ramp from the top),
        // which Brk keeps as the third color; the overlay's first stop is Arc's clear.
        if let base = style["baseColors"] as? [Any] { colors = Array(base.compactMap(color).prefix(2)) }
        if !colors.isEmpty, let overlay = (style["overlayColors"] as? [Any])?.compactMap(color).last(where: { $0.alpha > 0 }) {
            if colors.count == 1 { colors.append(colors[0]) }
            colors.append(RGBA(overlay.red, overlay.green, overlay.blue, 1))
        }
        if colors.isEmpty, let single = color(style["color"]) { colors = [single] }
        if colors.isEmpty, let paletteColor { colors = [paletteColor] }
        guard !colors.isEmpty else { return nil }
        let modifiers = style["modifiers"] as? [String: Any] ?? [:]
        let texture = Texture(rawValue: modifiers["overlay"] as? String ?? "") ?? .grain
        let appearance: AppearanceChoice = style["translucencyStyle"] as? String == "dark" ? .dark : .auto
        let intensity = (modifiers["intensityFactor"] as? Double).map { 1 - $0 } ?? SpaceTheme.default.intensity
        return SpaceTheme(colors: Array(colors.prefix(3)), wheel: (style["wheel"] as? String)?.contains("compl") == true ? .complementary : .analogous,
                          texture: texture, noise: min(1, max(0, modifiers["noiseFactor"] as? Double ?? 0.5)),
                          intensity: min(1, max(0, intensity)), appearance: appearance)
    }

    /// `{"red", "green", "blue", "alpha", "colorSpace"}`: extended sRGB, or Display P3 converted to sRGB.
    static func color(_ value: Any?) -> RGBA? {
        guard let c = value as? [String: Any], var r = c["red"] as? Double, var g = c["green"] as? Double, var b = c["blue"] as? Double else { return nil }
        if (c["colorSpace"] as? String)?.lowercased().contains("p3") == true {
            func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            func gamma(_ v: Double) -> Double { v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }
            let (lr, lg, lb) = (lin(max(0, r)), lin(max(0, g)), lin(max(0, b)))
            r = gamma(max(0, 1.2249 * lr - 0.2247 * lg))
            g = gamma(max(0, -0.0420 * lr + 1.0419 * lg))
            b = gamma(max(0, -0.0197 * lr - 0.0786 * lg + 1.0979 * lb))
        }
        func unit(_ x: Double) -> Double { min(1, max(0, x)) }
        return RGBA(unit(r), unit(g), unit(b), unit(c["alpha"] as? Double ?? 1))
    }

    static func firstDictionary(in value: Any, containing key: String, depth: Int = 0) -> [String: Any]? {
        guard depth < 16 else { return nil }
        if let dict = value as? [String: Any] {
            if dict[key] != nil { return dict }
            for child in dict.keys.sorted() { if let found = firstDictionary(in: dict[child]!, containing: key, depth: depth + 1) { return found } }
        } else if let list = value as? [Any] {
            for child in list { if let found = firstDictionary(in: child, containing: key, depth: depth + 1) { return found } }
        }
        return nil
    }
}
