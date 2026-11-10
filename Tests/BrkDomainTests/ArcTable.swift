import BrkBase
import Foundation
@testable import BrkDomain

/// Arc's menu as the anatomy recorded it, read from the repository at test time so the tests compare the table with
/// the source, not with a copy: `docs/arc-anatomy/model-and-shortcuts.md` section 2.3 (rows, keys, ids, priorities,
/// flags) and `Tests/Fixtures/arc-menu/mainmenu-items.tsv` (the nib's type-travel runtime attributes, one line per row).
enum ArcTable {
    struct Row {
        let number: Int
        let path: String
        let item: String
        let shortcut: String
        let bindingID: String
        let priority: KeyPriority
        let flags: [String]
        var menu: MenuName? { ArcTable.menu(path.components(separatedBy: " > ").first ?? "") }
        var submenu: Submenu? {
            let parts = path.components(separatedBy: " > ")
            return parts.count > 1 ? ArcTable.submenu(parts[1]) : nil
        }
        var chord: KeyChord? { ArcTable.chord(shortcut) }
    }

    struct TypeTravel {
        let icon: String?
        let triggers: [String]
        let title: String?
    }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Rows 1 to 189 of the table in section 2.3.
    static func rows() throws -> [Row] {
        let text = try String(contentsOf: root.appendingPathComponent("docs/arc-anatomy/model-and-shortcuts.md"), encoding: .utf8)
        guard let start = text.range(of: "### 2.3 Full menu and shortcut table"), let end = text.range(of: "### 2.4", range: start.upperBound..<text.endIndex)
        else { throw CocoaError(.fileReadCorruptFile) }
        return text[start.upperBound..<end.lowerBound].split(separator: "\n").compactMap { line -> Row? in
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 11, let number = Int(cells[1]) else { return nil }
            let priority: KeyPriority = switch cells[8] {
            case "overrideWebView": .app
            case "promptAfterConsumedByWebView": .pageThenApp
            default: .page
            }
            return Row(number: number, path: cells[2], item: cells[3], shortcut: cells[4], bindingID: cells[7].replacingOccurrences(of: "`", with: ""),
                       priority: priority, flags: cells[9].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        }
    }

    /// Row number -> the nib's `arcTypeTravelIcon`, `arcTypeTravelTriggers` (split at ";" and ",") and `arcTypeTravelTitle`.
    static func typeTravel() throws -> [Int: TypeTravel] {
        let text = try String(contentsOf: root.appendingPathComponent("Tests/Fixtures/arc-menu/mainmenu-items.tsv"), encoding: .utf8)
        var out: [Int: TypeTravel] = [:]
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count > 6 else { continue }
            // "key=value;key=value", where a trigger list's own ";" separators continue the previous value.
            var attributes: [String: String] = [:], last: String?
            for token in columns[6].split(separator: ";", omittingEmptySubsequences: false).map(String.init) {
                if let eq = token.firstIndex(of: "="), token[..<eq].allSatisfy({ $0.isLetter }), token.hasPrefix("arc") || token.hasPrefix("KeyEquivalent") {
                    last = String(token[..<eq])
                    attributes[last!] = String(token[token.index(after: eq)...])
                } else if let key = last {
                    attributes[key, default: ""] += ";" + token
                }
            }
            let triggers = (attributes["arcTypeTravelTriggers"] ?? "").replacingOccurrences(of: "\"", with: "")
                .split(whereSeparator: { $0 == ";" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            out[index + 1] = TypeTravel(icon: attributes["arcTypeTravelIcon"], triggers: triggers, title: attributes["arcTypeTravelTitle"])
        }
        return out
    }

    static func menu(_ name: String) -> MenuName? {
        switch name {
        case "Arc": .app
        case "File": .file
        case "Edit": .edit
        case "View": .view
        case "Spaces": .spaces
        case "Tabs": .tabs
        case "Archive": .archive
        case "Extensions": .extensions
        case "Window": .window
        case "Help": .help
        default: nil
        }
    }

    static func submenu(_ name: String) -> Submenu? {
        switch name {
        case "Find": .find
        case "Appearance": .appearance
        case "Developer": .developer
        case "Troubleshooting": .troubleshooting
        default: nil
        }
    }

    /// "Shift+Cmd+N (Shift from uppercase key)", "Ctrl+Shift+Equals", "Cmd+Plus", "Ctrl+Shift+Backtab", "F12", "Esc".
    static func chord(_ text: String) -> KeyChord? {
        var text = text
        var modifiers = Modifiers()
        if let note = text.range(of: " (Shift from uppercase key)") {
            text.removeSubrange(note)
            modifiers.insert(.shift)
        }
        guard !text.isEmpty else { return nil }
        var parts = text.components(separatedBy: "+")
        let name = parts.removeLast()
        for part in parts {
            switch part {
            case "Cmd": modifiers.insert(.command)
            case "Shift": modifiers.insert(.shift)
            case "Opt": modifiers.insert(.option)
            case "Ctrl": modifiers.insert(.control)
            default: return nil
            }
        }
        let key: Key?
        switch name {
        case "Equals": key = .equals
        case "Plus": key = .equals; modifiers.insert(.shift)
        case "Minus": key = .minus
        case "Comma": key = .comma
        case "Period": key = .period
        case "Left": key = .leftArrow
        case "Right": key = .rightArrow
        case "Up": key = .upArrow
        case "Down": key = .downArrow
        case "Esc": key = .escape
        case "F12": key = .f12
        case "Space": key = .space
        case "Backtab": key = .tab; modifiers.insert(.shift)
        case "[": key = .leftBracket
        case "]": key = .rightBracket
        default: key = Key.byName(name.lowercased())
        }
        return key.map { KeyChord(modifiers, $0) }
    }
}
