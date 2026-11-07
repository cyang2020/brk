import BrkBase
import Foundation

/// Brk's own addition beyond Arc, in the manner of Raycast's root search: the command bar finds files by name and apps
/// on this Mac, and emoji. This file holds the rules that need no system: which texts ask, what is left out and in what
/// order hits come. BrkApp does the looking (`LocalSearch`), BrkOverlays draws the rows (`Suggest`).
public struct LocalHit: Sendable, Hashable, Codable {
    public var path: String
    public var name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

public struct LocalResults: Sendable, Hashable, Codable {
    /// The typed text these answer; shown only while the bar's text is still exactly this.
    public var query: String
    public var apps: [LocalHit]
    public var files: [LocalHit]

    public init(query: String, apps: [LocalHit], files: [LocalHit]) {
        self.query = query
        self.apps = apps
        self.files = files
    }
}

/// What to look for: `name` in file names (and app names when `includesApps`) for the typed text `query`.
public struct LocalSearchRequest: Sendable, Hashable, Codable {
    public var query: String
    public var name: String
    public var includesApps: Bool

    public init(query: String, name: String, includesApps: Bool) {
        self.query = query
        self.name = name
        self.includesApps = includesApps
    }
}

public enum LocalSources {
    /// A typed word that lists one source only: "file budget", "emoji smile".
    public enum Mode: Equatable, Sendable {
        case files(String)
        case emoji(String)
    }

    /// Inline rows wait for this many characters.
    public static let inlineMinLength = 3
    /// How many hits the bar keeps: all its rows in the file mode.
    public static let hitLimit = 5

    public static func mode(_ typed: String) -> Mode? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        func after(_ word: String) -> String? {
            guard text.lowercased().hasPrefix(word + " ") else { return nil }
            let rest = text.dropFirst(word.count + 1).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        if let name = after("file"), name.count >= 2 { return .files(name) }
        if let name = after("emoji") { return .emoji(name) }
        return nil
    }

    /// What `typed` asks of the file and app sources, nil for nothing: an address, a calculation, a short text.
    public static func request(for typed: String, engine: SearchEngine) -> LocalSearchRequest? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode(text) {
        case .files(let name)?: return LocalSearchRequest(query: text, name: name, includesApps: false)
        case .emoji?: return nil
        case nil: break
        }
        guard text.count >= inlineMinLength, BrowserCalculator.result(text) == nil, !QuickAnswers.leads(text),
              resolveTypedInput(text, engine: engine) == engine.searchURL(text) else { return nil }
        return LocalSearchRequest(query: text, name: text, includesApps: true)
    }

    /// Hidden files, the home folder's Library (browser profiles live there), and what is inside or is an app bundle
    /// (apps have their own rows) never show. `home` is the real home folder, or the test's fixture folder.
    public static func isExcluded(_ path: String, home: String) -> Bool {
        let inside = path.hasPrefix(home + "/") ? String(path.dropFirst(home.count + 1)) : path
        let parts = inside.split(separator: "/")
        if path.hasPrefix(home + "/"), parts.first == "Library" { return true }
        if parts.contains(where: { $0.hasPrefix(".") }) { return true }
        return parts.contains { $0.hasSuffix(".app") }
    }

    /// How well `needle`'s words fit `name`, best 0, nil when one is missing: the whole name (its extension aside),
    /// then its start, then the start of a word, then anywhere.
    public static func match(_ name: String, needle: String) -> Int? {
        let hay = fold(name), words = fold(needle).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        var worst = 0
        for word in words {
            guard let found = hay.range(of: word) else { return nil }
            var rank = found.lowerBound == hay.startIndex ? 1 : 3
            if rank == 3, hay[hay.index(before: found.lowerBound)].isLetter == false, hay[hay.index(before: found.lowerBound)].isNumber == false { rank = 2 }
            worst = max(worst, rank)
        }
        let stem = (hay as NSString).deletingPathExtension
        return stem == fold(needle) || hay == fold(needle) ? 0 : worst
    }

    /// The best `limit` of `hits`; hits equally good keep their order (the source's newest first).
    public static func rank(_ hits: [LocalHit], needle: String, limit: Int = hitLimit) -> [LocalHit] {
        let scored = hits.enumerated().compactMap { index, hit in match(hit.name, needle: needle).map { (rank: $0, index: index, hit: hit) } }
        return scored.sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.prefix(limit).map(\.hit)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
