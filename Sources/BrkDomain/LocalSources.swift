import BrkBase
import Foundation

/// Brk's own addition beyond Arc, in the manner of Raycast's root search: the command bar finds files by name and apps
/// on this Mac. This file holds the rules that need no system: which texts ask, what is left out and in what
/// order hits come. BrkApp does the looking (`LocalSearch`), BrkOverlays draws the rows (`Suggest`).
public struct LocalHit: Sendable, Hashable, Codable {
    public var path: String
    public var name: String
    /// The kind of file as the index knows it. The row's icon comes from this, not from the file: see `LocalIcons`.
    public var contentType: String?

    public init(path: String, name: String, contentType: String? = nil) {
        self.path = path
        self.name = name
        self.contentType = contentType
    }
}

/// Which source a question is for: inline rows take both, the `file` and `app` prefixes one.
public enum LocalScope: Hashable, Sendable, Codable {
    case filesAndApps, files, apps
}

public struct LocalResults: Sendable, Hashable, Codable {
    /// The typed text these answer; shown only while the bar's text is still exactly this.
    public var query: String
    public var scope: LocalScope
    public var apps: [LocalHit]
    public var files: [LocalHit]

    public init(query: String, scope: LocalScope = .filesAndApps, apps: [LocalHit], files: [LocalHit]) {
        self.query = query
        self.scope = scope
        self.apps = apps
        self.files = files
    }
}

/// What to look for: `name` in file names and app names, as `scope` says, for the typed text `query`.
public struct LocalSearchRequest: Sendable, Hashable, Codable {
    public var query: String
    public var name: String
    public var scope: LocalScope

    public init(query: String, name: String, scope: LocalScope = .filesAndApps) {
        self.query = query
        self.name = name
        self.scope = scope
    }
}

public enum LocalSources {
    /// Inline rows wait for this many characters.
    public static let inlineMinLength = 3
    /// After the `file` or `app` prefix the user has said what they want.
    public static let prefixMinLength = 2
    /// How many hits the bar keeps: all its rows under the file prefix.
    public static let hitLimit = 5

    /// Rows found by meaning a name list keeps at least, when there are that many.
    public static let meaningRows = 2

    /// The `file` mode's rows: the names Spotlight matched first (they hold what was typed), then files found by meaning
    /// that are not among them; at least `meaningRows` of the latter stay, and they fill the rows when no name matched.
    public static func merge(names: [LocalHit], meaning: [LocalHit], limit: Int = hitLimit) -> [LocalHit] {
        let listed = Set(names.map(\.path))
        let extra = meaning.filter { !listed.contains($0.path) }
        let shown = names.prefix(max(0, limit - min(meaningRows, extra.count)))
        return Array(shown) + extra.prefix(limit - shown.count)
    }

    /// What `typed` asks of the file and app sources, nil for nothing: an address, a calculation, a short text.
    public static func request(for typed: String, engine: SearchEngine) -> LocalSearchRequest? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= inlineMinLength, BrowserCalculator.result(text) == nil, !QuickAnswers.leads(text), QuickColors.parse(text) == nil,
              resolveTypedInput(text, engine: engine) == engine.searchURL(text) else { return nil }
        return LocalSearchRequest(query: text, name: text)
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
