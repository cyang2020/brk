import AppKit
import BrkBase

/// Arc's menu nib as `.audit/arc-evidence/a/mainmenu-tree.txt` dumps it (every item with its key, separators,
/// submenus), turned into the lines Brk's menu must show: "Title [Cmd+Shift+N]" per item, "-" per separator, two
/// spaces of indent per submenu level. The rows the user dropped (Share Arc, Privacy Policy, Sign Out, Send to Dia)
/// are left out, Arc's empty placeholder submenu in Tabs is the separator it is drawn as, separators that end up
/// next to each other collapse into one, and "Arc" in a title is the product name.
enum ArcMenuTree {
    static let dropped: Set<String> = ["Share Arc", "Privacy Policy", "Sign Out", "Send to Dia"]

    static func lines(productName: String) throws -> [String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(".audit/arc-evidence/a/mainmenu-tree.txt"), encoding: .utf8)
        var out: [String] = []
        var skipBelow: Int?
        for raw in text.split(separator: "\n") {
            if raw.hasPrefix("#") { break }
            let indent = raw.prefix { $0 == " " }.count
            let line = raw.dropFirst(indent)
            if let skip = skipBelow { if indent > skip { continue } else { skipBelow = nil } }
            let pad = String(repeating: " ", count: indent)
            if line.hasPrefix("---") {
                out.append(pad + "-")
            } else if line.hasPrefix("- ["), let close = line.firstIndex(of: "]"), let bar = line.range(of: " | key=") {
                let title = line[line.index(close, offsetBy: 2)..<bar.lowerBound].trimmingCharacters(in: .whitespaces)
                let keyEnd = line[bar.upperBound...].firstIndex(of: " ") ?? line.endIndex
                let key = String(line[bar.upperBound..<keyEnd])
                if dropped.contains(title) { continue }
                if title.isEmpty {   // the placeholder submenu under Tabs: drawn as a separator
                    out.append(pad + "-")
                    skipBelow = indent
                    continue
                }
                let shown = title.replacingOccurrences(of: #"\bArc\b"#, with: productName, options: .regularExpression)
                out.append(pad + shown + (key == "-" ? "" : " [\(key)]"))
            }
        }
        return collapse(out)
    }

    /// The same lines for a built menu bar.
    @MainActor
    static func lines(of main: NSMenu) -> [String] {
        func walk(_ menu: NSMenu, _ depth: Int) -> [String] {
            let pad = String(repeating: " ", count: depth * 2)
            return menu.items.flatMap { item -> [String] in
                if item.isSeparatorItem { return [pad + "-"] }
                let key = describe(item)
                return [pad + item.title + (key.isEmpty ? "" : " [\(key)]")] + (item.submenu.map { walk($0, depth + 1) } ?? [])
            }
        }
        return collapse(walk(main, 0))
    }

    /// Arc's key notation: Cmd, Shift, Opt, Ctrl, then the key ("Cmd+Shift+N", "Shift+Ctrl+=", "Cmd+Left", "Esc").
    @MainActor
    static func describe(_ item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let mask = item.keyEquivalentModifierMask
        var parts: [String] = []
        if mask.contains(.command) { parts.append("Cmd") }
        if mask.contains(.shift) { parts.append("Shift") }
        if mask.contains(.option) { parts.append("Opt") }
        if mask.contains(.control) { parts.append("Ctrl") }
        let names: [String: String] = ["\u{F702}": "Left", "\u{F703}": "Right", "\u{F700}": "Up", "\u{F701}": "Down", "\u{1b}": "Esc",
                                       "\u{F70F}": "F12", " ": "Space", "\t": "Tab", "\u{19}": "Backtab"]
        parts.append(names[item.keyEquivalent] ?? item.keyEquivalent.uppercased())
        return parts.joined(separator: "+")
    }

    /// Adjacent separators at one level become one; a separator first or last in its menu goes.
    private static func collapse(_ lines: [String]) -> [String] {
        var out: [String] = []
        for (i, line) in lines.enumerated() {
            let isSeparator = line.trimmingCharacters(in: .whitespaces) == "-"
            let indent = line.prefix { $0 == " " }.count
            if isSeparator {
                // The line before it at its level or above must be an item of the same menu.
                guard let previous = out.last(where: { $0.prefix { $0 == " " }.count <= indent }),
                      previous.prefix(while: { $0 == " " }).count == indent, previous.trimmingCharacters(in: .whitespaces) != "-"
                else { continue }
                let next = lines[(i + 1)...].first { $0.trimmingCharacters(in: .whitespaces) != "-" || $0.prefix { $0 == " " }.count != indent }
                guard let next, next.prefix(while: { $0 == " " }).count == indent else { continue }
            }
            out.append(line)
        }
        return out
    }
}
