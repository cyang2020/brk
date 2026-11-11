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

        func node(_ id: String, depth: Int) -> ImportNode? {
            guard depth < 32, let item = items[id], let data = item["data"] as? [String: Any] else { return nil }
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

    /// Arc's window theme: the background's base colors (one for `blendedSingleColor`, up to three for a gradient),
    /// its intensity, noise, texture overlay and translucency style. Nil when there is no background to read.
    static func theme(_ value: Any?) -> SpaceTheme? {
        guard let window = value as? [String: Any], let background = window["background"] else { return nil }
        guard let style = firstDictionary(in: background, containing: "modifiers") else { return nil }
        var colors: [RGBA] = []
        if let base = style["baseColors"] as? [Any] { colors = base.compactMap(color) }
        if colors.isEmpty, let single = color(style["color"]) { colors = [single] }
        guard !colors.isEmpty else { return nil }
        let modifiers = style["modifiers"] as? [String: Any] ?? [:]
        let texture = Texture(rawValue: modifiers["overlay"] as? String ?? "") ?? .grain
        let appearance: AppearanceChoice = switch style["translucencyStyle"] as? String {
        case "light": .light
        case "dark": .dark
        default: .auto
        }
        var theme = SpaceTheme(colors: Array(colors.prefix(3)), wheel: (style["wheel"] as? String)?.contains("compl") == true ? .complementary : .analogous,
                               texture: texture, noise: min(1, max(0, modifiers["noiseFactor"] as? Double ?? 0.5)),
                               intensity: min(1, max(0, modifiers["intensityFactor"] as? Double ?? 0.25)), appearance: appearance)
        theme.variants = nil
        return theme
    }

    static func color(_ value: Any?) -> RGBA? {
        guard let c = value as? [String: Any], let r = c["red"] as? Double, let g = c["green"] as? Double, let b = c["blue"] as? Double else { return nil }
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
