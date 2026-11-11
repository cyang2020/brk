import Foundation

/// The browsers Brk imports from, in the order the picker shows them: Arc first (it stops working on 2026-12-22), then
/// Arc's own order (Chrome, Safari, Firefox, Brave, Edge, Vivaldi, Opera, Opera GX).
public enum BrowserKind: String, CaseIterable, Sendable, Codable, Hashable {
    case arc, chrome, safari, firefox, brave, edge, vivaldi, opera, operaGX

    public var name: String {
        switch self {
        case .arc: "Arc"
        case .chrome: "Chrome"
        case .safari: "Safari"
        case .firefox: "Firefox"
        case .brave: "Brave"
        case .edge: "Edge"
        case .vivaldi: "Vivaldi"
        case .opera: "Opera"
        case .operaGX: "Opera GX"
        }
    }

    /// Chromium-based: bookmarks JSON, History, Login Data and Cookies in each profile folder, keyed by Local State.
    public var isChromium: Bool { ![.safari, .firefox].contains(self) }

    /// The data folder under ~/Library/Application Support (ArcCore's list, report §2.2).
    var dataFolder: String {
        switch self {
        case .arc: "Arc/User Data"
        case .chrome: "Google/Chrome"
        case .brave: "BraveSoftware/Brave-Browser"
        case .edge: "Microsoft Edge"
        case .vivaldi: "Vivaldi"
        case .opera: "com.operasoftware.Opera"
        case .operaGX: "com.operasoftware.OperaGX"
        case .firefox: "Firefox"
        case .safari: ""
        }
    }

    /// The login-keychain item that holds the browser's encryption password ("<Browser> Safe Storage"); reading it is
    /// what makes macOS ask for the computer password.
    public var keychainServices: [String] {
        switch self {
        case .arc: ["Arc Safe Storage"]
        case .chrome: ["Chrome Safe Storage"]
        case .brave: ["Brave Safe Storage", "Brave Browser Safe Storage"]
        case .edge: ["Microsoft Edge Safe Storage"]
        case .vivaldi: ["Vivaldi Safe Storage"]
        case .opera: ["Opera Safe Storage"]
        case .operaGX: ["Opera GX Safe Storage", "Opera Safe Storage"]
        case .safari, .firefox: []
        }
    }

    public var bundleIdentifiers: [String] {
        switch self {
        case .arc: ["company.thebrowser.Browser"]
        case .chrome: ["com.google.Chrome"]
        case .brave: ["com.brave.Browser"]
        case .edge: ["com.microsoft.edgemac"]
        case .vivaldi: ["com.vivaldi.Vivaldi"]
        case .opera: ["com.operasoftware.Opera"]
        case .operaGX: ["com.operasoftware.OperaGX"]
        case .safari: ["com.apple.Safari"]
        case .firefox: ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"]
        }
    }

    /// What Arc's picker says each kind can bring (B1), in Brk's words: open tabs and payment cards are not imported.
    public var importsSentence: String {
        switch self {
        case .safari: "We can import your history, passwords, and bookmarks from Safari."
        case .firefox: "We can import your history and bookmarks from Firefox."
        case .arc: "We can import your Spaces, pinned tabs, Favorites, history, passwords, and cookies from Arc."
        default: "We can import your history, cookies, passwords, and bookmarks from \(name)."
        }
    }
}

/// One profile of a source browser.
public struct SourceProfile: Hashable, Sendable, Codable {
    /// The profile folder's name ("Default", "Profile 1"; Firefox: its folder path relative to the profiles root).
    public let id: String
    public let name: String
    public let path: URL
    public init(id: String, name: String, path: URL) { self.id = id; self.name = name; self.path = path }
}

public struct DiscoveredBrowser: Hashable, Sendable {
    public let kind: BrowserKind
    public let profiles: [SourceProfile]
    public init(kind: BrowserKind, profiles: [SourceProfile]) { self.kind = kind; self.profiles = profiles }
}

public enum BrowserCatalog {
    /// Which browsers have data on this Mac. Reads only Local State and profiles.ini; asks for no permission. Safari is
    /// always listed: its data comes from the export ZIP the user picks.
    public static func discover(applicationSupport: URL) -> [DiscoveredBrowser] {
        BrowserKind.allCases.compactMap { kind in
            switch kind {
            case .safari: return DiscoveredBrowser(kind: .safari, profiles: [SourceProfile(id: "Safari", name: "Safari", path: applicationSupport)])
            case .firefox:
                let profiles = firefoxProfiles(root: applicationSupport.appendingPathComponent("Firefox", isDirectory: true))
                return profiles.isEmpty ? nil : DiscoveredBrowser(kind: kind, profiles: profiles)
            default:
                let profiles = chromiumProfiles(root: applicationSupport.appendingPathComponent(kind.dataFolder, isDirectory: true), kind: kind)
                return profiles.isEmpty ? nil : DiscoveredBrowser(kind: kind, profiles: profiles)
            }
        }
    }

    /// Profiles named in Local State's `profile.info_cache` whose folder holds data, in the order Chromium lists them.
    /// Opera keeps its single profile in the data folder itself.
    static func chromiumProfiles(root: URL, kind: BrowserKind) -> [SourceProfile] {
        let fm = FileManager.default
        func hasData(_ folder: URL) -> Bool {
            ["Bookmarks", "History", "Login Data", "Cookies", "Network/Cookies"].contains { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
        }
        var out: [SourceProfile] = []
        if let data = try? Data(contentsOf: root.appendingPathComponent("Local State")),
           let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cache = (state["profile"] as? [String: Any])?["info_cache"] as? [String: Any] {
            let order = ((state["profile"] as? [String: Any])?["profiles_order"] as? [String]) ?? cache.keys.sorted()
            for id in order + cache.keys.sorted() where !out.contains(where: { $0.id == id }) {
                let folder = root.appendingPathComponent(id, isDirectory: true)
                guard let info = cache[id] as? [String: Any], hasData(folder) else { continue }
                let name = (info["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
                out.append(SourceProfile(id: id, name: name, path: folder))
            }
        }
        if out.isEmpty, hasData(root) { out.append(SourceProfile(id: ".", name: kind.name, path: root)) }
        if out.isEmpty, hasData(root.appendingPathComponent("Default")) {
            out.append(SourceProfile(id: "Default", name: "Default", path: root.appendingPathComponent("Default")))
        }
        return out
    }

    /// Firefox's profiles.ini: every `[Profile…]` section with a places.sqlite.
    static func firefoxProfiles(root: URL) -> [SourceProfile] {
        guard let text = try? String(contentsOf: root.appendingPathComponent("profiles.ini"), encoding: .utf8) else { return [] }
        var sections: [[String: String]] = [], current: [String: String]? = nil
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                if let current { sections.append(current) }
                current = line.hasPrefix("[Profile") ? [:] : nil
            } else if current != nil, let equals = line.firstIndex(of: "=") {
                current?[String(line[..<equals])] = String(line[line.index(after: equals)...])
            }
        }
        if let current { sections.append(current) }
        return sections.compactMap { section in
            guard let path = section["Path"] else { return nil }
            let folder = section["IsRelative"] == "0" ? URL(fileURLWithPath: path, isDirectory: true) : root.appendingPathComponent(path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("places.sqlite").path) else { return nil }
            return SourceProfile(id: path, name: section["Name"] ?? path, path: folder)
        }
    }
}
