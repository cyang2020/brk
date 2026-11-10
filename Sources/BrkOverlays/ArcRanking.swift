import Foundation

/// Arc 1.170's command bar scorer (its Swift module `ASE2`), ported with Arc's built-in configuration. The research note
/// docs/research/arc-command-bar-ranking/README.md says where each number was read; the comments here name the binary
/// addresses (arm64 slice of Arc 1.170.0, build 89123) for the parts that note did not cover.
///
/// Three steps, each testable alone: the caller builds `Candidate`s (Suggest.swift), `scores` turns them into one number
/// each, and `order` sorts, merges duplicates and cuts the list.
public enum ArcRanking {
    // MARK: Arc's constants

    /// `ASE2.Feature`, in Arc's order.
    public enum Feature: Int, CaseIterable, Sendable {
        case archetype, urlMatchScore, urlMatchPosition, urlMatchPercentage, titleMatchScore, titleMatchPosition, titleMatchPercentage,
             hotWordsMatchScore, hotWordsMatchPosition, hotWordsMatchPercentage, fuzzySearchConfidence, lastNavigated, frequencyEver,
             typedCountEver, mostVisitedRank, siteEngagementScore, globalSiteRank, typeTravelCandidateBump, chromiumRank,
             chromiumRelevanceScore, saveLevel

        /// The value a candidate without this feature gets (table 0x10378e6b0).
        public var valueWhenMissing: Double {
            switch self {
            case .urlMatchPosition, .titleMatchPosition, .hotWordsMatchPosition: 30
            case .lastNavigated: 5_184_000
            case .mostVisitedRank: 20
            case .globalSiteRank: 505
            case .chromiumRank: 11
            case .saveLevel: 8
            default: 0
            }
        }

        /// Lower raw values are better: the z-score is negated (mask 0x54924).
        public var lowerIsBetter: Bool {
            switch self {
            case .urlMatchPosition, .titleMatchPosition, .hotWordsMatchPosition, .lastNavigated, .mostVisitedRank, .globalSiteRank,
                 .chromiumRank, .saveLevel: true
            default: false
            }
        }

        public var category: Category {
            switch self {
            case .archetype: .archetype
            case .urlMatchScore, .urlMatchPosition, .urlMatchPercentage, .titleMatchScore, .titleMatchPosition, .titleMatchPercentage,
                 .hotWordsMatchScore, .hotWordsMatchPosition, .hotWordsMatchPercentage, .fuzzySearchConfidence: .match
            case .frequencyEver, .typedCountEver, .mostVisitedRank, .siteEngagementScore, .globalSiteRank, .typeTravelCandidateBump: .importance
            case .lastNavigated: .recency
            case .chromiumRank, .chromiumRelevanceScore: .chromium
            case .saveLevel: .save
            }
        }

        /// The item's weight inside its category (Arc's default configuration).
        public var weight: Double {
            switch self {
            case .archetype: 1
            case .urlMatchScore, .urlMatchPosition, .urlMatchPercentage: 1
            case .titleMatchScore, .titleMatchPosition, .titleMatchPercentage: 0.5
            case .hotWordsMatchScore, .hotWordsMatchPosition, .hotWordsMatchPercentage: 1.5
            case .fuzzySearchConfidence: 20
            case .frequencyEver: 3
            case .typedCountEver: 4
            case .mostVisitedRank, .siteEngagementScore: 2
            case .globalSiteRank, .typeTravelCandidateBump: 1
            case .lastNavigated: 3
            case .chromiumRank: 5
            case .chromiumRelevanceScore: 3
            case .saveLevel: 3
            }
        }
    }

    /// `ASE2.Category` and its weight in the final mean.
    public enum Category: Int, CaseIterable, Sendable {
        case archetype, match, importance, recency, chromium, save

        public var weight: Double {
            switch self {
            case .archetype: 35
            case .match: 2
            case .importance: 10
            case .recency: 15
            case .chromium: 25
            case .save: 15
            }
        }
    }

    /// The archetypes Brk's rows use, with Arc's base values. The base value is the `archetype` feature.
    public enum Archetype: String, CaseIterable, Sendable {
        case tab, typeTravel, topDomain, memoryStore, askAssistant, assistantHistory
        case chromiumSearchWhatYouTyped, chromiumNavigateWhatYouTyped, chromiumHistory, chromiumSearchHistory, chromiumNavigateSuggestion,
             chromiumSearchOtherEngine, chromiumSearchSuggestion, chromiumSearchCalculatorAnswer
        case askGPTWhatYouTyped

        public var base: Double {
            switch self {
            case .tab: 101
            case .typeTravel: 104
            case .topDomain: 96.1
            case .memoryStore: 105
            case .askAssistant: 106
            case .assistantHistory: 107
            case .chromiumSearchWhatYouTyped, .chromiumNavigateWhatYouTyped, .chromiumHistory: 100
            case .chromiumSearchHistory: 99
            case .chromiumNavigateSuggestion: 96
            case .chromiumSearchOtherEngine: 96.2
            case .chromiumSearchSuggestion: 95
            case .chromiumSearchCalculatorAnswer: 1
            case .askGPTWhatYouTyped: 2
            }
        }

        /// Search kinds, which the domain and default boosts treat apart from rows that open a page (the 0xcd and 0x20c
        /// masks of 0x101d65bd8).
        public var isSearch: Bool {
            switch self {
            case .chromiumSearchWhatYouTyped, .chromiumSearchSuggestion, .chromiumSearchHistory, .chromiumSearchOtherEngine,
                 .chromiumSearchCalculatorAnswer, .askGPTWhatYouTyped: true
            default: false
            }
        }

        /// Arc gives no boost at all to its own as-typed rows, the Ask row and the assistant rows (mask 0x3f1 at the top
        /// of 0x101d65bd8: only Chromium rows, tabs, documents, Easels, commands, top domains and instant links).
        public var takesBoosts: Bool {
            switch self {
            case .askGPTWhatYouTyped, .askAssistant, .assistantHistory, .memoryStore: false
            default: true
            }
        }

        /// The highest row this archetype is lifted to when its score puts it lower (`ASE2.PreferredMaxRankConfig`, an
        /// optional row per archetype). Arc's defaults were not found in the binary; the one value here is fitted to the
        /// real Arc: the Ask row is third (P49).
        public var preferredMaxRank: Int? {
            self == .askGPTWhatYouTyped ? 2 : nil
        }
    }

    /// `ASE2.Boost` with its weight and score (tables 0x10378e130 and 0x10378e0c0).
    public enum Boost: Int, CaseIterable, Sendable {
        case exactBaseDomain, exactURL, exactHotWord, baseDomain, autocompleteDefault, autocompleteSearchOnly, chromiumSpecialSearchFunction,
             customTitlePrefix, veryRecentTabOrDocumentBoost, topApp, recentlyUseTypeTravel, typeTravelPrefixForLongQuery,
             unboxingPromotedAction, highFuzzySearchConfidence

        public var weight: Double {
            switch self {
            case .exactBaseDomain, .exactHotWord, .highFuzzySearchConfidence: 100
            case .exactURL, .baseDomain, .chromiumSpecialSearchFunction, .typeTravelPrefixForLongQuery, .unboxingPromotedAction: 40
            default: 15
            }
        }

        public var score: Double {
            switch self {
            case .exactBaseDomain, .exactHotWord, .highFuzzySearchConfidence: 15
            case .autocompleteSearchOnly: 2
            default: 3
            }
        }
    }

    // MARK: Step 1: what a candidate is

    /// One row before scoring: what Arc's boosts look at, and its raw features (an absent feature is missing).
    public struct Candidate: Equatable, Sendable {
        public var archetype: Archetype
        public var features: [Feature: Double]
        /// The address the row opens, for the domain boosts and the duplicate key.
        public var url: URL?
        /// What the default boosts compare with the query: the readable address of a row that opens a page, a search's
        /// text, a command's title (the jump table at 0x101d574dc).
        public var autocompleteText: String
        /// A tab's title words, a command's title and trigger phrases.
        public var hotWords: [String]
        /// A tab's own title, a command's title (customTitlePrefix, typeTravelPrefixForLongQuery).
        public var customTitle: String?
        public var isFavorite: Bool
        /// How often a command was run from the bar (`typeTravelUsage.frequency`).
        public var runs: Int
        /// Rows that are the same thing show once (`order`).
        public var dedupKey: String
        /// The highest row this candidate is lifted to when it scores lower (its archetype's).
        public var preferredRow: Int?

        public init(archetype: Archetype, features: [Feature: Double] = [:], url: URL? = nil, autocompleteText: String = "", hotWords: [String] = [],
                    customTitle: String? = nil, isFavorite: Bool = false, runs: Int = 0, dedupKey: String, preferredRow: Int? = nil) {
            self.archetype = archetype; self.features = features; self.url = url; self.autocompleteText = autocompleteText
            self.hotWords = hotWords; self.customTitle = customTitle; self.isFavorite = isFavorite; self.runs = runs; self.dedupKey = dedupKey
            self.preferredRow = preferredRow ?? archetype.preferredMaxRank
        }
    }

    // MARK: Match measures (0x101d393b0 and the ARCFoundationBase functions it calls)

    /// The three match measures of one text: the fuzzy score (urlMatchScore, titleMatchScore, hotWordsMatchScore), where
    /// the query first matches (nil: nowhere) and the share of the text the query's words cover.
    public struct Match: Equatable, Sendable {
        public var score: Double
        public var position: Int?
        public var percentage: Double
    }

    /// Arc reads at most this many characters of a text.
    static let textLimit = 512

    public static func match(_ query: String, in text: String) -> Match {
        let text = String(text.prefix(textLimit))
        let covered = coverage(query, text)
        return Match(score: Double(fuzzyScore(query, text)), position: covered.position, percentage: covered.percentage)
    }

    /// The characters before a word start in the fuzzy score (the set built at 0x100811d68).
    static let wordStarts: Set<Character> = [" ", "/", "-", "_"]

    /// 0x100813450: for each space-separated word of the lowercased query, the longest run of the word's start found
    /// anywhere in the lowercased text (m) and the longest found where a word starts (p), each counted as 1² + 2² + … + n².
    /// The search is Knuth-Morris-Pratt with Arc's run counter, which keeps growing past a whole match (0x100811ad0).
    public static func fuzzyScore(_ query: String, _ text: String) -> Int {
        let hay = Array(text.lowercased())
        func squares(_ n: Int) -> Int { n * (n + 1) * (2 * n + 1) / 6 }
        return query.lowercased().split(separator: " ").reduce(0) { total, word in
            let (anywhere, atWordStart) = longestRuns(Array(word), in: hay)
            return total + squares(anywhere) + squares(atWordStart)
        }
    }

    static func longestRuns(_ word: [Character], in hay: [Character]) -> (Int, Int) {
        guard !word.isEmpty else { return (0, 0) }
        let fallback = failureTable(word)
        var i = 0, j = 0, run = 0, best = 0, bestAtStart = 0, atStart = true
        while i < hay.count, j < word.count {
            if hay[i] == word[j] {
                run += 1
                best = max(best, run)
                if atStart { bestAtStart = max(bestAtStart, run) }
                j += 1
                if j == word.count { j = fallback[word.count] }
                i += 1
            } else {
                let f = fallback[j]
                let step = f < 0 ? 1 : 0
                i += step
                j = f + step
                run = j
                let before = i - j - 1
                atStart = before >= 0 && before < hay.count && wordStarts.contains(hay[before])
            }
        }
        return (best, bestAtStart)
    }

    /// 0x100811ee0: the optimised KMP table, -1 first and one entry past the word's end.
    static func failureTable(_ word: [Character]) -> [Int] {
        var table = Array(repeating: 0, count: word.count + 1)
        table[0] = -1
        var candidate = 0
        if word.count > 1 {
            for position in 1..<word.count {
                if word[position] == word[candidate] {
                    table[position] = table[candidate]
                } else {
                    table[position] = candidate
                    while candidate >= 0, word[position] != word[candidate] { candidate = table[candidate] }
                }
                candidate += 1
            }
        }
        table[word.count] = candidate
        return table
    }

    /// 0x100817a8c: every case-insensitive occurrence of each space-separated query word marks its characters; the first
    /// marked character is the position, the marked share of the text the percentage.
    static func coverage(_ query: String, _ text: String) -> (position: Int?, percentage: Double) {
        let count = text.count
        guard count > 0, !query.isEmpty else { return (nil, 0) }
        var marked = Array(repeating: false, count: count)
        for word in query.split(separator: " ") {
            var from = text.startIndex
            while from < text.endIndex, let found = text.range(of: word, options: .caseInsensitive, range: from..<text.endIndex) {
                if !found.isEmpty {
                    let start = text.distance(from: text.startIndex, to: found.lowerBound)
                    let length = text.distance(from: found.lowerBound, to: found.upperBound)
                    for k in start..<min(count, start + length) { marked[k] = true }
                }
                from = found.upperBound > from ? found.upperBound : text.index(after: from)
            }
        }
        let total = marked.filter { $0 }.count
        return (marked.firstIndex(of: true), Double(total) / Double(count))
    }

    /// Sets the URL, title and hot-word measures (features 1 to 9) the way 0x101d393b0 does: a missing position stays
    /// missing; of the hot words, the best by score, then position, gives the score and position, and the
    /// percentage is the highest of all.
    public static func matchFeatures(_ query: String, url: String?, title: String?, hotWords: [String]) -> [Feature: Double] {
        var out: [Feature: Double] = [:]
        if let url {
            let m = match(query, in: url)
            out[.urlMatchScore] = m.score; out[.urlMatchPercentage] = m.percentage
            if let p = m.position { out[.urlMatchPosition] = Double(p) }
        }
        if let title {
            let m = match(query, in: title)
            out[.titleMatchScore] = m.score; out[.titleMatchPercentage] = m.percentage
            if let p = m.position { out[.titleMatchPosition] = Double(p) }
        }
        if !hotWords.isEmpty {
            out[.hotWordsMatchScore] = 0; out[.hotWordsMatchPercentage] = 0
            var best: Match?
            for word in hotWords {
                let m = match(query, in: word)
                out[.hotWordsMatchPercentage] = max(out[.hotWordsMatchPercentage] ?? 0, m.percentage)
                let better: Bool = {
                    guard let best else { return true }
                    if m.score != best.score { return m.score > best.score }
                    return (m.position ?? Int.max) < (best.position ?? Int.max)
                }()
                if better {
                    best = m
                    out[.hotWordsMatchScore] = m.score
                    if let p = m.position { out[.hotWordsMatchPosition] = Double(p) } else { out[.hotWordsMatchPosition] = nil }
                }
            }
        }
        return out
    }

    // MARK: Boosts (0x101d65bd8)

    /// The address as Arc reads it for matching and the domain boosts: no scheme, no "www.", no trailing slash.
    public static func readable(_ url: URL) -> String {
        var text = url.absoluteString
        if let scheme = url.scheme, text.lowercased().hasPrefix(scheme.lowercased() + "://") { text = String(text.dropFirst(scheme.count + 3)) }
        if text.lowercased().hasPrefix("www.") { text = String(text.dropFirst(4)) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    static func host(_ url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The query as an address: lowercased, no scheme, no "www.", no trailing slash (0x100823cec).
    static func readableQuery(_ query: String) -> String {
        var text = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        if text.hasPrefix("www.") { text = String(text.dropFirst(4)) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// The query is the address (0x101d67684): the readable address or the host, exactly. Never for arc:// (Brk: brk://).
    static func isExact(_ query: String, _ url: URL) -> Bool {
        let q = readableQuery(query)
        guard !q.isEmpty, !q.hasPrefix("brk:"), !q.hasPrefix("arc:") else { return false }
        return q == readable(url).lowercased() || q == host(url)
    }

    /// The address starts with the query (0x101d679c4): only a query made of host characters.
    static func isPrefix(_ query: String, _ url: URL) -> Bool {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !q.hasPrefix("brk:"), !q.hasPrefix("arc:"),
              q.unicodeScalars.allSatisfy({ CharacterSet.urlHostAllowed.contains($0) }) else { return false }
        return (host(url) ?? "").hasPrefix(q) || readable(url).lowercased().hasPrefix(q)
    }

    /// `word:word` that is not a URL scheme Arc knows (the regex built at 0x101d67f20), for chromiumSpecialSearchFunction.
    static func isSpecialSearch(_ query: String) -> Bool {
        let parts = query.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } }) else { return false }
        return !knownSchemes.contains(parts[0].lowercased())
    }

    /// The common part of the scheme list in Arc's regex (it lists every IANA scheme).
    static let knownSchemes: Set<String> = ["about", "chrome", "data", "file", "ftp", "http", "https", "javascript", "mailto", "news", "tel", "sms", "ws", "wss",
                                           "blob", "view-source", "arc", "brk", "facetime", "maps", "localhost"]

    /// Which boosts apply to `candidate` for `query`. Read from the switch at 0x101d65bd8:
    /// - exactBaseDomain: not a tab, and the query is the address and starts it; exactURL: the query is the address, and
    ///   for a row that is not a tab the address does not start with it (an address with a path); baseDomain: the
    ///   address starts with the query, and for a row that is not a tab it is not the whole address. A tab gets
    ///   exactURL and baseDomain, never exactBaseDomain.
    /// - exactHotWord: the lowercased query is one of the hot words.
    /// - autocompleteDefault (rows that open a page or run a command) and autocompleteSearchOnly (searches): the input, as
    ///   Chromium's inline completion leaves it (`input`: "time" completed to "time.com"), is the row's text or starts
    ///   with it. So the completed site, or else the text as typed, gets it; a suggestion that merely starts with the
    ///   query does not (Arc keeps "visual field" above "visual fixation" for "visual fix").
    /// - chromiumSpecialSearchFunction: Chromium's second row, for a `word:word` query.
    /// - customTitlePrefix: a tab's own title starts with the query.
    /// - veryRecentTabOrDocumentBoost: a tab used in the last hour. topApp: a Favorite.
    /// - recentlyUseTypeTravel: a command run more than once. typeTravelPrefixForLongQuery: a command whose title or a
    ///   trigger starts with the query. The binary checks a query of three characters or more against the command's
    ///   phrases, but the real Arc lifts only a start of two words or more ("switch to d" puts Switch to Dark Mode first;
    ///   "swi", "dark" and "nigh" leave the search first, though the trigger list "Switch to Dark Mode; Switch Dark Mode;
    ///   Dark Mode; Night Mode" starts with each), so Brk applies it from two words.
    /// - highFuzzySearchConfidence: fuzzySearchConfidence above 0.8. No code in Arc 1.170 sets that feature, so it never
    ///   applies; Brk keeps the rule. unboxingPromotedAction: Arc's onboarding list, which Brk does not have.
    public static func boosts(_ candidate: Candidate, query: String, input: String? = nil) -> [Boost] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = (input ?? query).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, candidate.archetype.takesBoosts else { return [] }
        var out: [Boost] = []
        let isTab = candidate.archetype == .tab
        if let url = candidate.url, !candidate.archetype.isSearch {
            let exact = isExact(q, url), prefix = isPrefix(q, url)
            if !isTab, exact, prefix { out.append(.exactBaseDomain) }
            if exact, isTab || !prefix { out.append(.exactURL) }
            if prefix, isTab || !exact { out.append(.baseDomain) }
        }
        if candidate.hotWords.contains(where: { $0.lowercased() == q }) { out.append(.exactHotWord) }
        let text = candidate.autocompleteText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, shown == text || shown.hasPrefix(text) { out.append(candidate.archetype.isSearch ? .autocompleteSearchOnly : .autocompleteDefault) }
        if candidate.features[.chromiumRank] == 1, isSpecialSearch(q) { out.append(.chromiumSpecialSearchFunction) }
        if isTab, let title = candidate.customTitle?.lowercased(), title.hasPrefix(q) { out.append(.customTitlePrefix) }
        if isTab, let seconds = candidate.features[.lastNavigated], seconds < 3600 { out.append(.veryRecentTabOrDocumentBoost) }
        if isTab, candidate.isFavorite { out.append(.topApp) }
        if candidate.archetype == .typeTravel {
            if candidate.runs > 1 { out.append(.recentlyUseTypeTravel) }
            if q.count > 2, q.contains(" "), ([candidate.customTitle].compactMap { $0 } + candidate.hotWords).contains(where: { $0.lowercased().hasPrefix(q) }) {
                out.append(.typeTravelPrefixForLongQuery)
            }
        }
        if let fuzzy = candidate.features[.fuzzySearchConfidence], fuzzy > 0.8 { out.append(.highFuzzySearchConfidence) }
        return out
    }

    // MARK: Step 2: the score

    /// z = (x − mean) / standard deviation over this query's candidates (population deviation: Arc averages the squared
    /// differences), negated for a "lower is better" feature, 0 when every candidate has the same value.
    public static func zScores(_ values: [Double], lowerIsBetter: Bool) -> [Double] {
        guard !values.isEmpty else { return [] }
        let mean = values.reduce(0, +) / Double(values.count)
        let deviation = (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
        guard deviation > 0, deviation.isFinite else { return values.map { _ in 0 } }
        return values.map { (($0 - mean) / deviation) * (lowerIsBetter ? -1 : 1) }
    }

    /// Σ score·weight / Σ weight (`ASE2/ScoreAndWeights.swift`); 0 for no weight.
    public static func weightedMean(_ parts: [(score: Double, weight: Double)]) -> Double {
        let total = parts.reduce(0) { $0 + $1.weight }
        guard total != 0 else { return 0 }
        return parts.reduce(0) { $0 + $1.score * $1.weight } / total
    }

    /// One score per candidate: missing features filled, z-scored over the candidates, averaged inside each category,
    /// then one weighted mean of the archetype, the five categories and every boost that applies. NaN becomes 0.
    public static func scores(_ candidates: [Candidate], query: String, input: String? = nil) -> [Double] {
        var z: [Feature: [Double]] = [:]
        for feature in Feature.allCases {
            let values = candidates.map { feature == .archetype ? $0.archetype.base : $0.features[feature] ?? feature.valueWhenMissing }
            z[feature] = zScores(values, lowerIsBetter: feature.lowerIsBetter)
        }
        return candidates.indices.map { i in
            var parts: [(score: Double, weight: Double)] = []
            for category in Category.allCases {
                let items = Feature.allCases.filter { $0.category == category }
                let score = weightedMean(items.map { (z[$0]![i], $0.weight) })
                parts.append((score, category.weight))
            }
            for boost in boosts(candidates[i], query: query, input: input) { parts.append((boost.score, boost.weight)) }
            let score = weightedMean(parts)
            return score.isNaN ? 0 : score
        }
    }

    // MARK: Step 3: the rows shown

    /// Indices of the rows to show, best first: sorted by score (ties keep the given order), one row per duplicate key at
    /// the best one's place, a candidate lifted to its preferred row, at most `limit`. Which duplicate Arc shows was not
    /// read; fitted to what the real Arc showed: a tab's row takes the place of the same site as a popular site (the
    /// Favorites GitHub and Wikipedia), and an address typed in full takes the place of a visited page at that address
    /// but stays beside the open tab that shows it (the typed address first, Switch to Tab second).
    public static func order(_ candidates: [Candidate], scores: [Double], limit: Int) -> [Int] {
        let sorted = candidates.indices.sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
        var place: [String: Int] = [:], typedPlace: [String: Int] = [:], rows: [Int] = []
        for i in sorted {
            let key = candidates[i].dedupKey, archetype = candidates[i].archetype
            if archetype == .chromiumNavigateWhatYouTyped {
                if let at = place[key], candidates[rows[at]].archetype != .tab { rows[at] = i; typedPlace[key] = at; continue }
                typedPlace[key] = rows.count
                if place[key] == nil { place[key] = rows.count }
                rows.append(i)
                continue
            }
            if archetype == .tab, place[key] != nil, place[key] == typedPlace[key] {
                place[key] = rows.count
                rows.append(i)
                continue
            }
            if let at = place[key] {
                if archetype == .tab, candidates[rows[at]].archetype != .tab, candidates[rows[at]].archetype != .chromiumNavigateWhatYouTyped { rows[at] = i }
                continue
            }
            place[key] = rows.count
            rows.append(i)
        }
        let lifted = rows.filter { candidates[$0].preferredRow != nil }.sorted { candidates[$0].preferredRow! < candidates[$1].preferredRow! }
        for i in lifted {
            guard let preferred = candidates[i].preferredRow, let at = rows.firstIndex(of: i), at > preferred else { continue }
            rows.remove(at: at)
            rows.insert(i, at: min(preferred, rows.count))
        }
        return Array(rows.prefix(limit))
    }
}
