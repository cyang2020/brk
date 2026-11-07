import Foundation

/// Emoji by name for the command bar's "emoji <name>" (Brk's own, as Raycast's Emoji Search). The names are the system's,
/// no table ships with Brk: the Character Viewer's English names when their file is where macOS keeps it, else Unicode's
/// names through the standard library. Both are searched when both exist. Built once, on the first emoji question.
enum EmojiIndex {
    struct Entry: Equatable, Sendable {
        let emoji: String
        let name: String
        /// Every word that finds it, lowercased.
        let words: [String]
    }

    private static let appleNames = "/System/Library/PrivateFrameworks/CoreEmoji.framework/Versions/A/Resources/en.lproj/AppleName.strings"

    static let entries: [Entry] = build(systemNames: NSDictionary(contentsOfFile: appleNames) as? [String: String] ?? [:])

    static func build(systemNames: [String: String]) -> [Entry] {
        var entries: [Entry] = []
        for (emoji, name) in systemNames {
            entries.append(entry(emoji, name: name.lowercased()))
        }
        if systemNames.isEmpty {
            let ranges: [ClosedRange<UInt32>] = [0x2600...0x27BF, 0x2B00...0x2BFF, 0x1F000...0x1FAFF]
            for scalar in ranges.joined().compactMap(Unicode.Scalar.init) where scalar.properties.isEmojiPresentation {
                guard let name = scalar.properties.name else { continue }
                entries.append(entry(String(Character(scalar)), name: name.lowercased()))
            }
        }
        return entries.sorted { $0.emoji.unicodeScalars.map(\.value).lexicographicallyPrecedes($1.emoji.unicodeScalars.map(\.value)) }
    }

    private static func entry(_ emoji: String, name: String) -> Entry {
        var words = wordList(name)
        if emoji.unicodeScalars.count <= 2, let unicode = emoji.unicodeScalars.first?.properties.name?.lowercased() { words += wordList(unicode) }
        return Entry(emoji: emoji, name: name, words: words)
    }

    private static func wordList(_ text: String) -> [String] {
        text.split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    /// Every word of `query` starts a word of the name; a word also finds its other forms by its stem, so "smile" finds
    /// "smiling". Whole-word hits first, then the shortest names.
    static func matches(_ query: String, limit: Int, in entries: [Entry] = entries) -> [Entry] {
        let needles = wordList(query.lowercased())
        guard !needles.isEmpty else { return [] }
        func rank(_ entry: Entry) -> Int? {
            var worst = 0
            for needle in needles {
                if entry.words.contains(needle) { continue }
                if entry.words.contains(where: { $0.hasPrefix(needle) }) { worst = max(worst, 1); continue }
                let stem = self.stem(needle)
                guard stem != needle, entry.words.contains(where: { $0.hasPrefix(stem) }) else { return nil }
                worst = max(worst, 2)
            }
            return worst
        }
        let ranked = entries.compactMap { entry in rank(entry).map { (rank: $0, entry: entry) } }
        return ranked.sorted { ($0.rank, $0.entry.name.count, $0.entry.name) < ($1.rank, $1.entry.name.count, $1.entry.name) }.prefix(limit).map(\.entry)
    }

    /// "smile" -> "smil", "hearts" -> "heart"; short words stay whole.
    private static func stem(_ word: String) -> String {
        var stem = word
        if stem.count > 3, stem.hasSuffix("s") { stem.removeLast() }
        if stem.count > 3, stem.hasSuffix("e") { stem.removeLast() }
        return stem
    }
}
