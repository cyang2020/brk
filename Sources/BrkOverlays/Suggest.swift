import BrkBase
import BrkDomain
import Foundation

/// Owner: W4 / F4. One command bar result and the command it dispatches when chosen. Choosing a result is just
/// dispatching that command, so the bar has no behavior of its own. Site search is not a row: the bar offers it
/// beside the input (`Suggest.siteSearchOffer`) and enters it on Tab, or on Space after an engine's name.
public struct Suggestion: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case openTyped, switchToTab, history, action, calculator, bookmark
        /// The page being edited (Cmd+L before anything is typed): choosing it opens its address again.
        case current
        /// One of Arc's own entries under the page being edited and after the recent tabs ("Contact the Team").
        case suggested
        /// One of the default engine's suggestions for the query (Arc: `chromium` "Search Suggestion").
        case searchSuggestion
        /// A site from Arc's top domains list (Arc: `topDomains`).
        case topDomain
        /// Max's Ask row (Arc's "Ask ChatGPT →", P49): the query, the local tool's name and the arrow square.
        case ask
        /// Brk's own, beyond Arc (`LocalSources`): a file by name, an app, an emoji, one form of a colour.
        case file, app, emoji, color
        /// Brk's own: a tab, an archived tab or a visited page the local search model found by meaning
        /// (`CommandBarSnapshot.meaning`).
        case meaning
        /// Brk's own: a saved conversation found by its title or by what was said in it.
        case conversation
    }
    public let kind: Kind
    public let title: String
    /// Dimmed text after the title, after an em dash: a top domain's domain ("Wikimedia — wikimedia.org"), the address
    /// of one of Arc's own entries (P21-a). Tabs and history show their title only (P02-c, Q01-a, Q01-b). The card over
    /// the URL pill shows titles only (P02-b).
    public let subtitle: String?
    /// SF Symbol drawn when there is no favicon.
    public let symbol: String?
    public let favicon: URL?
    /// Right-hand caption: "Switch to Tab" on open tabs, an action's shortcut ("⌃⇧="), else nil.
    public let hint: String?
    public let command: Command
    /// The icon sits on a rounded tile (Arc's "Contact the Team" bubble).
    public var tile = false
    /// The symbol's own color instead of the row's text color (the YouTube mark).
    public var accent: RGBA? = nil
    /// Instead of a symbol: the system's icon for this path (an app), for this kind of file, or this emoji.
    public var icon: Icon? = nil
    /// What ⌘Return and ⌥Return do on this row; nil keeps those keys' usual behaviour.
    public var commandReturn: Command? = nil
    public var optionReturn: Command? = nil
    /// A command row: choosing it records a run under this key (`Suggest.usageKey`), which the ranking reads next time.
    public var usageKey: String? = nil

    public enum Icon: Equatable, Sendable {
        case file(String)
        case document(name: String, contentType: String?)
        case emoji(String)
        case swatch(RGBA)
    }
}

public enum Suggest {
    /// The split prefix lists at most this many tabs, site search this many suggestions, and a blank query this many
    /// recent tabs (Q01-a).
    private static let tabCap = 3, emptyTabCap = 4, suggestionCap = 3

    /// Ranks results for `query`, at most Metrics.commandBar.maxVisibleRows (Arc shows 5).
    ///
    /// Lists of their own, not rankings: AI mode (the one row it asks), site search (the query on that engine, then its
    /// suggestions), a `prefix` (`QuickPrefixes`: the user asked for that list with Tab), a blank query (the recent tabs
    /// without the focused one, at most 4, then Arc's own entries fill the five rows: Q01-a, P21-a) and the page being
    /// edited (`query` is `bar.initialQuery`, the focused tab's URL, untouched: that page, then Arc's own entries, P02-b).
    ///
    /// Any other text is ranked the way Arc 1.170 ranks it (`ArcRanking`): every source gives candidates (`candidates`),
    /// Arc's scorer gives each one score, and the best five show, one per page or search. Rules of Brk's own stay on top
    /// of that: an answer that is not the only reading of the text sits right under the typed row; a bar filling an empty
    /// split pane puts a typed address first (it opens in that pane); and with `completing` (the domain the input
    /// completes the query to, `completion`) a top-domain first row shows the site's name alone. Matching is case- and
    /// diacritic-insensitive. `resolve` is the domain's URL policy (default: the bar's engine).
    public static func rank(query: String, bar: CommandBarSnapshot, appName: String, siteSearch: SearchEngineCandidate? = nil, prefix: QuickPrefix? = nil,
                            resolve: ((String) -> URL?)? = nil, completing: String? = nil,
                            timeZone: TimeZone = .current, locale: Locale = .current) -> [Suggestion] {
        let limit = Metrics.commandBar.maxVisibleRows.value
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mode = bar.aiMode {
            guard !text.isEmpty else { return [] }
            let intent: AIIntent
            switch mode {
            case .question: intent = .ask(text)
            case .page: intent = .askPage(text)
            case .instant: intent = .instant(text)
            case .translate: intent = .translate(text)
            case .browse:
                let parts = text.split(separator: "|", maxSplits: 1).map(String.init)
                let sources = parts.count == 2 ? parts[1].split(separator: ",").compactMap { AIValidation.destination(String($0)) } : []
                intent = .browse(question: parts[0], sources: sources)
            }
            return [Suggestion(kind: .action, title: mode == .translate ? "Translate to \(text)" : text,
                               subtitle: mode == .browse ? "Read selected sources · local AI" : "Ask the local AI tool", symbol: "sparkles", favicon: nil, hint: "Return", command: .assist(intent))]
        }
        if let siteSearch { return Array(siteSearchRows(text, on: siteSearch, bar: bar).prefix(limit)) }
        if let prefix { return Array(prefixRows(prefix, text, bar: bar, appName: appName, resolve: resolve).prefix(limit)) }
        let tabs = bar.tabs.filter { !$0.isFocused }
        if text.isEmpty {
            return Array((tabs.prefix(emptyTabCap).map(switchRow) + arcRows).prefix(limit))
        }
        if let current = bar.tabs.first(where: \.isFocused), text == bar.initialQuery.trimmingCharacters(in: .whitespacesAndNewlines),
           current.url.absoluteString == text {
            let row = Suggestion(kind: .current, title: current.title, subtitle: nil, symbol: "globe", favicon: current.favicon, hint: nil,
                                 command: .commandBar(.submit(text)))
            return Array(([row] + arcRows).prefix(limit))
        }

        let built = candidates(text, bar: bar, appName: appName, resolve: resolve, completing: completing, timeZone: timeZone, locale: locale)
        let scores = ArcRanking.scores(built.map(\.candidate), query: text)
        var rows = ArcRanking.order(built.map(\.candidate), scores: scores, limit: Int.max).map { built[$0].row }
        // Answers worked out from the text are Brk's own and take no part in Arc's scoring (their scores would change every
        // other row's): one the text can only be leads, otherwise it sits right under the typed row.
        let (leading, below) = answers(text, bar: bar, timeZone: timeZone, locale: locale)
        rows.insert(contentsOf: below, at: rows.firstIndex { $0.kind == .openTyped }.map { $0 + 1 } ?? rows.count)
        rows.insert(contentsOf: leading, at: 0)
        // Filling an empty split pane, a typed address opens in that pane: it leads (Brk's rule for that bar).
        if bar.fillsPane, let i = rows.firstIndex(where: { $0.kind == .openTyped && $0.symbol == "globe" }), i > 0 { rows.insert(rows.remove(at: i), at: 0) }
        // The completed site's row is the site's name alone: the input already shows its domain (P02-c "Google Docs").
        if let completing, let first = rows.first, first.kind == .topDomain, first.command == .commandBar(.submit(completing)) {
            rows[0] = domainRow(TopDomains.Site(domain: completing, name: TopDomains.all.first { $0.domain == completing }?.name ?? completing), named: true)
        }
        return Array(rows.prefix(limit))
    }

    // MARK: Brk's own sources

    private static func quickRow(_ answer: QuickAnswer) -> Suggestion {
        let symbol = switch answer.kind { case .math: "equal"; case .date: "clock"; case .currency: "dollarsign.circle" }
        return Suggestion(kind: .calculator, title: answer.answer, subtitle: answer.detail, symbol: symbol, favicon: nil, hint: "Copy Result",
                          command: .commandBar(.copyAnswer(answer.answer)))
    }

    /// A prefix's own rows for the text after its word.
    private static func selectedEngine(_ bar: CommandBarSnapshot) -> SearchEngine {
        SearchEngine.builtIn(bar.engine.id) ?? bar.engine.template.map {
            SearchEngine(id: bar.engine.id, name: bar.engine.name, keyword: bar.engine.keyword, template: $0, suggestTemplate: nil)
        } ?? .google
    }

    private static func prefixRows(_ prefix: QuickPrefix, _ text: String, bar: CommandBarSnapshot, appName: String, resolve: ((String) -> URL?)?) -> [Suggestion] {
        switch prefix.action {
        case .files:
            guard let local = bar.local, local.query == text, local.scope == .files else { return [] }
            return local.files.map(fileRow)
        case .apps:
            guard let local = bar.local, local.query == text, local.scope == .apps else { return [] }
            return local.apps.map(appRow)
        case .emoji:
            return EmojiIndex.matches(text, limit: Metrics.commandBar.maxVisibleRows.value).map { entry in
                Suggestion(kind: .emoji, title: entry.name, subtitle: nil, symbol: nil, favicon: nil, hint: OverlayCopy.copyEmoji,
                           command: .commandBar(.copyAnswer(entry.emoji)), icon: .emoji(entry.emoji))
            }
        case .calculate:
            guard !text.isEmpty, let result = BrowserCalculator.forced(text) ?? QuickAnswers.answer(text, QuickAnswerContext(now: bar.now, timeZone: .current, locale: .current, rates: bar.rates))?.answer else { return [] }
            return [Suggestion(kind: .calculator, title: result, subtitle: text, symbol: "equal", favicon: nil, hint: "Copy Result", command: .commandBar(.copyAnswer(result)))]
        case .ask:
            guard !text.isEmpty else { return [] }
            return [aiRow(text, subtitle: OverlayCopy.ask(bar.askProvider ?? prefix.title), .assist(.ask(text)))]
        case .askAgent(let name):
            guard !text.isEmpty, let agent = AIProviderChoice(rawValue: name) else { return [] }
            return [aiRow(text, subtitle: OverlayCopy.ask(prefix.title), .assist(.askAgent(text, agent: agent)))]
        case .askPage:
            guard !text.isEmpty else { return [] }
            return [aiRow(text, subtitle: OverlayCopy.askThisPage, .assist(.askPage(text)))]
        case .summarize:
            // Return with no text summarises; a text says what to look for. The route is Ask on Page's.
            let question = text.isEmpty ? OverlayCopy.summarizeThisPage : "\(OverlayCopy.summarizeThisPage): \(text)"
            return [aiRow(question, subtitle: OverlayCopy.askThisPage, .assist(.askPage(question)))]
        case .split:
            return splitRows(text, bar: bar, appName: appName, resolve: resolve)
        case .window:
            return windowRows(text, bar: bar, appName: appName)
        case .translate:
            return translateRows(text, bar: bar)
        case .color:
            return QuickColors.parse(text, names: true).map(colorRows) ?? []
        case .define:
            guard let found = bar.definition, found.word == text else { return [] }
            guard let definition = found.text else {
                return [Suggestion(kind: .action, title: OverlayCopy.noDefinition(text), subtitle: nil, symbol: "character.book.closed", favicon: nil, hint: nil, command: .commandBar(.copyAnswer("")))]
            }
            return [Suggestion(kind: .action, title: definition, subtitle: nil, symbol: "character.book.closed", favicon: nil, hint: OverlayCopy.openDictionary, command: .commandBar(.openDictionary(text)))]
        }
    }

    /// The existing split commands this mode also lists, where the menu would enable them (`bar.actions`).
    private static let splitActions: [ActionID] = [.separateTabFromSplitView, .maximizeSplitPane, .splitHorizontal, .splitVertical, .removeSplitView, .separateAllSplit]

    /// The new pane's row (no text: Add Split View or the named side's), open tabs by title, and the split commands. A
    /// command the text names outright ("expand") leads, so Return runs it rather than searching for the word.
    /// What the `split` prefix can bring beside the page: first what is already open, then what was visited, and only then a
    /// web search for the text. An address leads, unless a tab already has it. No text: the recent tabs and an empty pane.
    private static func splitRows(_ text: String, bar: CommandBarSnapshot, appName: String, resolve: ((String) -> URL?)?) -> [Suggestion] {
        let (edge, rest) = QuickSplit.parse(text)
        let side = edge ?? .right
        let needle = fold(rest)
        var scored: [(score: Int, row: Suggestion)] = []
        for action in splitActions where bar.actions.contains(action) {
            let score = needle.isEmpty ? 0 : score(needle, title: action.barTitle(appName: appName), triggers: action.barTriggers(appName: appName))
            guard needle.isEmpty || score != nil else { continue }
            scored.append((score ?? 0, Suggestion(kind: .action, title: action.barTitle(appName: appName), subtitle: nil, symbol: action.spec.commandBar?.symbol, favicon: nil,
                                                  hint: bar.keys[action]?.glyphs, command: action.spec.barCommand)))
        }
        let named = scored.filter { $0.score >= 3 }.map(\.row), others = scored.filter { $0.score < 3 }.map(\.row)
        let where_ = OverlayCopy.newPane(side)
        let tabs = bar.tabs.filter { !$0.isFocused }
        func tabRow(_ tab: SwitchCandidate) -> Suggestion {
            Suggestion(kind: .action, title: tab.title, subtitle: where_, symbol: "globe", favicon: tab.favicon, hint: "Return", command: .commandBar(.splitTab(side, tab.tab)))
        }
        guard !rest.isEmpty else {
            let add = Suggestion(kind: .action, title: edge.map(TypeTravelCopy.addSplit) ?? ActionID.addSplitView.barTitle(appName: appName), subtitle: nil, symbol: "square.split.2x1", favicon: nil,
                                 hint: "Return", command: edge.map { .split(.addPaneAt($0)) } ?? .split(.addPane))
            return tabs.prefix(emptyTabCap).map(tabRow) + [add] + others
        }
        let engine = selectedEngine(bar)
        let url = (resolve ?? { resolveTypedInput($0, engine: engine) })(rest)
        let isAddress = url.map { $0 != engine.searchURL(rest) && !isSearch($0, for: rest) } ?? false
        let open = Suggestion(kind: .action, title: rest, subtitle: where_, symbol: isAddress ? "globe" : "magnifyingglass", favicon: nil, hint: "Return", command: .commandBar(.splitOpen(side, rest)))
        let matches = matching(tabs, needle) { [$0.title, $0.url.absoluteString] }
        let taken = Set(bar.tabs.flatMap { [$0.url.absoluteString, identity($0.url, $0.title)] })
        let visited = matching(recentHistory(bar.history, excluding: taken), needle) { [$0.title, $0.url.absoluteString] }.prefix(2).map { entry in
            Suggestion(kind: .action, title: entry.title.isEmpty ? displayURL(entry.url) : entry.title, subtitle: where_, symbol: "clock", favicon: nil, hint: "Return", command: .commandBar(.splitOpen(side, entry.url.absoluteString)))
        }
        if isAddress {
            let exact = matches.filter { $0.url == url }, partial = matches.filter { $0.url != url }
            return named + exact.map(tabRow) + [open] + partial.prefix(tabCap).map(tabRow) + visited + others
        }
        return named + matches.prefix(tabCap).map(tabRow) + visited + [open] + others
    }

    private static func placementRow(_ placement: WindowSnap) -> Suggestion {
        let symbol = switch placement {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .maximize: "macwindow"
        case .center: "macwindow.on.rectangle"
        case .nextDisplay: "display.2"
        }
        return Suggestion(kind: .action, title: placement.title, subtitle: nil, symbol: symbol, favicon: nil, hint: nil, command: .window(.place(placement)))
    }

    /// The window's places, then its existing commands; the text narrows them. Not in type travel, so ordinary queries do
    /// not meet these rows.
    private static func windowRows(_ text: String, bar: CommandBarSnapshot, appName: String) -> [Suggestion] {
        let needle = fold(text)
        let places = WindowSnap.allCases.filter { needle.isEmpty || score(needle, title: $0.title, triggers: $0.triggers) != nil }.map(placementRow)
        let existing = [ActionID.fullscreen, .minimize, .toggleStayOnTop].filter { action in
            bar.actions.contains(action) && (needle.isEmpty || score(needle, title: action.barTitle(appName: appName), triggers: action.barTriggers(appName: appName)) != nil)
        }.map { action in
            Suggestion(kind: .action, title: action.barTitle(appName: appName), subtitle: nil, symbol: action.spec.commandBar?.symbol, favicon: nil, hint: bar.keys[action]?.glyphs, command: action.spec.barCommand)
        }
        return places + existing
    }

    /// The page translation's row, or the text's: waiting, its answer (Return copies), or why not.
    private static func translateRows(_ text: String, bar: CommandBarSnapshot) -> [Suggestion] {
        switch QuickTranslation.parse(text) {
        case nil:
            return []
        case .page(let target)?:
            return [aiRow(OverlayCopy.translatePage(target), subtitle: nil, .assist(.translate(target)))]
        case .text(let source, let target)?:
            let current = bar.translation?.text == text ? bar.translation : nil
            if let answer = current?.answer {
                let shown = answer.split(whereSeparator: \.isNewline).joined(separator: " ")
                return [Suggestion(kind: .calculator, title: shown, subtitle: target, symbol: "character.bubble", favicon: nil, hint: "Copy Result", command: .commandBar(.copyAnswer(answer)))]
            }
            if let failure = current?.failure {
                return [Suggestion(kind: .action, title: failure, subtitle: nil, symbol: "exclamationmark.triangle", favicon: nil, hint: nil, command: .commandBar(.copyAnswer("")))]
            }
            return [Suggestion(kind: .action, title: OverlayCopy.translating(target), subtitle: source, symbol: "character.bubble", favicon: nil, hint: nil, command: .commandBar(.copyAnswer("")))]
        }
    }

    /// The colour's three forms, each row with its swatch; Return copies that row's form.
    private static func colorRows(_ color: QuickColor) -> [Suggestion] {
        [color.hex, color.rgb, color.hsl].map { value in
            Suggestion(kind: .color, title: value, subtitle: nil, symbol: nil, favicon: nil, hint: OverlayCopy.copyColor, command: .commandBar(.copyAnswer(value)), icon: .swatch(color.rgba))
        }
    }

    private static func aiRow(_ title: String, subtitle: String?, _ command: Command) -> Suggestion {
        Suggestion(kind: .action, title: title, subtitle: subtitle, symbol: "sparkles", favicon: nil, hint: "Return", command: command)
    }

    // MARK: Candidates for Arc's ranking

    /// One row and what Arc's scorer knows about it.
    struct Built {
        var candidate: ArcRanking.Candidate
        var row: Suggestion
    }

    /// Chromium's relevance numbers are not visible through CEF; a fixed one per kind stands in (Chromium's usual values:
    /// 1300 for the text as typed, more for a visited page the text inline-completes, about 900 for other visited pages,
    /// the engine's suggestions below). Chromium's rows are ordered the way its dropdown groups them: the default row (a
    /// page the text completes, else the text as typed), then the text as typed, then the engine's suggestions, then the
    /// other visited pages.
    enum Relevance {
        static let whatYouTyped = 1300.0, historyAutocompletes = 1400.0, history = 900.0, suggestion = 800.0, demotedWhatYouTyped = 801.0

        /// A visited page that the text does not inline-complete: more for typed visits, then for visits.
        static func history(_ page: HistoryCandidate) -> Double {
            history + min(250, 20 * Double(page.typedCount) + 5 * Double(page.visitCount))
        }

        /// The dropdown group a Chromium row belongs to, top first.
        static func group(_ relevance: Double, isHistory: Bool) -> Int {
            if relevance >= whatYouTyped { return 0 }
            return isHistory ? 2 : 1
        }
    }

    /// Every source's candidates for `text`, each with its row. Archetypes: open tabs and saved Pinned and Favorites
    /// (Brk's bookmarks, which are tabs in Arc) are `tab`; the typed row is Chromium's search or address as typed;
    /// visited pages are `chromiumHistory`; the engine's suggestions `chromiumSearchSuggestion`; Arc's popular sites
    /// `topDomain`; commands, settings panes, Spaces, folders, apps, files and the window places `typeTravel`; saved
    /// conversations `assistantHistory`; Max's Ask row Arc's `askGPTWhatYouTyped`. A page the search model found by meaning
    /// ranks as what it is (a tab, a visited page, a conversation). Answers are not candidates (`answers`).
    static func candidates(_ text: String, bar: CommandBarSnapshot, appName: String, resolve: ((String) -> URL?)?, completing: String?,
                           timeZone: TimeZone, locale: Locale) -> [Built] {
        let engine = selectedEngine(bar)
        let resolve = resolve ?? { resolveTypedInput($0, engine: engine) }
        let needle = fold(text)
        let now = bar.now
        var out: [Built] = []
        func since(_ instant: Instant?) -> Double? {
            instant.map { max(0, Double(now.milliseconds - $0.milliseconds) / 1000) }
        }
        func siteFeatures(_ url: URL) -> [ArcRanking.Feature: Double] {
            var features: [ArcRanking.Feature: Double] = [:]
            if let rank = bar.mostVisited.firstIndex(of: url) { features[.mostVisitedRank] = Double(rank) }
            if let site = SiteEngagement.site(url), let score = bar.siteEngagement[site] { features[.siteEngagementScore] = score }
            return features
        }
        func page(_ archetype: ArcRanking.Archetype, url: URL, title: String, hotWords: [String] = []) -> ArcRanking.Candidate {
            var candidate = ArcRanking.Candidate(archetype: archetype, url: url, autocompleteText: ArcRanking.readable(url), hotWords: hotWords,
                                                 dedupKey: pageKey(url, title))
            candidate.features = ArcRanking.matchFeatures(text, url: ArcRanking.readable(url), title: title, hotWords: hotWords)
                .merging(siteFeatures(url)) { $1 }
            return candidate
        }

        // Chromium's result: the text as typed, visited pages and the engine's suggestions, ranked among themselves.
        var chromium: [(built: Built, relevance: Double, group: Int)] = []
        var isAddress = false
        if let url = resolve(text) {
            let search = url == engine.searchURL(text) || isSearch(url, for: text)
            isAddress = !search
            let row = Suggestion(kind: .openTyped, title: search ? text : displayURL(url), subtitle: nil, symbol: search ? "magnifyingglass" : "globe",
                                 favicon: nil, hint: nil, command: .commandBar(.submit(text)))
            var candidate: ArcRanking.Candidate
            if search {
                candidate = ArcRanking.Candidate(archetype: .chromiumSearchWhatYouTyped, autocompleteText: text, dedupKey: searchKey(text))
                candidate.features = ArcRanking.matchFeatures(text, url: nil, title: text, hotWords: [])
            } else {
                candidate = page(.chromiumNavigateWhatYouTyped, url: url, title: text)
                candidate.autocompleteText = text
            }
            chromium.append((Built(candidate: candidate, row: row), Relevance.whatYouTyped, 0))
        }
        // Chromium matches visited pages where a word of the title or the address starts with the text, and scores them by
        // typed visits, then visits, then the newest visit. Arc gives these rows their visit and typed counts but no
        // last-visit feature (Arc sets that one only for tabs and commands, 0x101d4fc34 and 0x101d38610).
        let visited = recentHistory(bar.history).filter { matchRank(needle, in: [$0.title, $0.url.absoluteString]) == 0 }
            .prefix(historyCandidates).enumerated()
            .sorted { a, b in
                let x = Relevance.history(a.element), y = Relevance.history(b.element)
                return x != y ? x > y : a.offset < b.offset
            }.map(\.element)
        for entry in visited {
            var candidate = page(.chromiumHistory, url: entry.url, title: entry.title)
            candidate.features[.frequencyEver] = Double(entry.visitCount)
            candidate.features[.typedCountEver] = Double(entry.typedCount)
            let relevance = ArcRanking.isPrefix(text, entry.url) ? Relevance.historyAutocompletes : Relevance.history(entry)
            chromium.append((Built(candidate: candidate, row: historyRow(entry)), relevance, Relevance.group(relevance, isHistory: true)))
        }
        // Google's navigational suggestion for a site (Arc's "etsy.com" row, the input completing to it) is not in the
        // suggestion answer Brk asks for; Arc's own popular-sites list stands in: the first site whose domain the text
        // starts (three letters at least) is Chromium's default row.
        var topDomains: [(site: TopDomains.Site, rank: Int)] = []
        if needle.count >= 2, !needle.contains(where: \.isWhitespace) {
            var seen = Set<String>()
            for (rank, site) in TopDomains.all.enumerated() where topDomains.count < topDomainCandidates {
                guard site.domain.hasPrefix(needle) || fold(site.name).hasPrefix(needle), seen.insert(site.domain).inserted else { continue }
                topDomains.append((site, rank))
            }
        }
        func topDomain(_ site: TopDomains.Site, rank: Int) -> Built? {
            guard let url = URL(string: "https://\(site.domain)") else { return nil }
            var candidate = page(.topDomain, url: url, title: site.name)
            candidate.features[.globalSiteRank] = Double(rank)
            return Built(candidate: candidate, row: domainRow(site))
        }
        let completedSite = needle.count < 3 ? nil : topDomains.firstIndex { $0.site.domain.hasPrefix(needle) && $0.site.domain.count > needle.count }
        if let at = completedSite, let built = topDomain(topDomains[at].site, rank: topDomains[at].rank) {
            chromium.append((built, Relevance.historyAutocompletes, 0))
            // With a site it is sure of, Google's answer lowers the as-typed search ("google:verbatimrelevance"), which
            // Chromium then ranks among the suggestions.
            if let typed = chromium.firstIndex(where: { $0.built.row.kind == .openTyped }), chromium[typed].built.candidate.archetype == .chromiumSearchWhatYouTyped {
                chromium[typed].relevance = Relevance.demotedWhatYouTyped
                chromium[typed].group = 1
            }
        }
        for (index, suggestion) in engineSuggestions(text, bar).prefix(suggestionCandidates).enumerated() {
            var candidate = ArcRanking.Candidate(archetype: .chromiumSearchSuggestion, autocompleteText: suggestion, dedupKey: searchKey(suggestion))
            candidate.features = ArcRanking.matchFeatures(text, url: nil, title: suggestion, hotWords: [])
            let row = Suggestion(kind: .searchSuggestion, title: suggestion, subtitle: nil, symbol: "magnifyingglass", favicon: nil, hint: nil,
                                 command: .commandBar(.submitSearch(engine: bar.engine.id, query: suggestion)))
            chromium.append((Built(candidate: candidate, row: row), Relevance.suggestion - Double(index), 1))
        }
        let ordered = chromium.enumerated().sorted { a, b in
            if a.element.group != b.element.group { return a.element.group < b.element.group }
            if a.element.relevance != b.element.relevance { return a.element.relevance > b.element.relevance }
            return a.offset < b.offset
        }.map(\.element)
        for (rank, entry) in ordered.enumerated() {
            var built = entry.built
            built.candidate.features[.chromiumRank] = Double(rank)
            built.candidate.features[.chromiumRelevanceScore] = entry.relevance
            out.append(built)
        }

        // Open tabs, never the focused one, then saved Pinned and Favorites without a page. A tab's last visit is when it
        // was last switched to from this bar (Arc's `recentlySwitchedToTabs`), so the bar learns which tabs it is used for.
        for tab in matching(bar.tabs.filter { !$0.isFocused }, needle, texts: { [$0.title, $0.url.absoluteString] }).prefix(tabCandidates) {
            var candidate = page(.tab, url: tab.url, title: tab.title, hotWords: words(tab.title))
            candidate.customTitle = tab.customTitle
            candidate.isFavorite = tab.isFavorite
            candidate.features[.lastNavigated] = since(bar.commandUsage[switchKey(tab.tab)]?.lastRun)
            candidate.features[.saveLevel] = tab.saveLevel.map(Double.init)
            var row = switchRow(tab)
            row.usageKey = switchKey(tab.tab)
            out.append(Built(candidate: candidate, row: row))
        }
        for saved in matching(bar.bookmarks, needle, texts: { [$0.title, $0.url.absoluteString] }).prefix(tabCandidates) {
            var candidate = page(.tab, url: saved.url, title: saved.title, hotWords: words(saved.title))
            candidate.isFavorite = saved.isFavorite
            candidate.features[.lastNavigated] = since(saved.visitedAt)
            candidate.features[.saveLevel] = saved.saveLevel.map(Double.init)
            let row = Suggestion(kind: .bookmark, title: saved.title, subtitle: nil, symbol: "bookmark", favicon: nil, hint: nil,
                                 command: .commandBar(.submit(saved.url.absoluteString)))
            out.append(Built(candidate: candidate, row: row))
        }

        // Arc's popular sites whose domain or name the text starts (one word, two letters at least).
        for (index, entry) in topDomains.enumerated() where index != completedSite {
            if let built = topDomain(entry.site, rank: entry.rank) { out.append(built) }
        }

        // Commands. A command chosen before carries its runs: their count is the typed count, the newest one the last
        // visit (0x101d38610), and more than one run is Arc's recentlyUseTypeTravel boost.
        func command(_ row: Suggestion, title: String, triggers: [String]) -> Built {
            let key = usageKey(row.command)
            var row = row
            row.usageKey = key
            let usage = bar.commandUsage[key]
            var candidate = ArcRanking.Candidate(archetype: .typeTravel, autocompleteText: title,
                                                 hotWords: ([title] + triggers).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "…")) },
                                                 customTitle: title, runs: usage?.count ?? 0, dedupKey: "command:" + key)
            candidate.features = ArcRanking.matchFeatures(text, url: nil, title: title, hotWords: triggers)
            if let usage {
                candidate.features[.typedCountEver] = Double(usage.count)
                candidate.features[.lastNavigated] = since(usage.lastRun)
            }
            return Built(candidate: candidate, row: row)
        }
        for entry in typeTravel(needle, bar: bar, appName: appName).filter(\.startsAWord).prefix(commandCandidates) {
            out.append(command(entry.suggestion, title: entry.suggestion.title, triggers: entry.triggers))
        }
        if bar.createsTab, !isAddress, text.count >= LocalSources.inlineMinLength, let local = bar.local, local.query == text, local.scope == .filesAndApps {
            for hit in local.apps.prefix(localCandidates) { out.append(command(appRow(hit), title: hit.name, triggers: [])) }
            for hit in local.files.prefix(localCandidates) { out.append(command(fileRow(hit), title: hit.name, triggers: [])) }
        }
        if bar.createsTab, let placement = WindowSnap.exact(text) {
            out.append(command(placementRow(placement), title: placement.title, triggers: placement.triggers))
        }

        // Saved conversations, then what the search model found by meaning.
        if !isAddress, !bar.fillsPane, !needle.isEmpty {
            for (conversation, found) in ConversationSearch.search(needle, in: bar.conversations).prefix(conversationCandidates) {
                let snippet: String? = if case .text(let snippet) = found { snippet } else { nil }
                let subtitle = [conversation.space, snippet].compactMap { $0 }.joined(separator: " · ")
                var candidate = ArcRanking.Candidate(archetype: .assistantHistory, autocompleteText: conversation.title, dedupKey: "conversation:\(conversation.id)")
                candidate.features = ArcRanking.matchFeatures(text, url: nil, title: conversation.title, hotWords: [])
                let row = Suggestion(kind: .conversation, title: conversation.title, subtitle: subtitle.isEmpty ? nil : subtitle, symbol: "bubble.left.and.bubble.right",
                                     favicon: ConversationPage.favicon, hint: OverlayCopy.conversation, command: .assist(.showConversation(conversation.id)))
                out.append(Built(candidate: candidate, row: row))
            }
        }
        if !isAddress, !bar.fillsPane, let meaning = bar.meaning, meaning.text == text {
            let focused = bar.tabs.first(where: \.isFocused)?.url
            for found in meaning.rows.filter({ $0.url != focused }).prefix(meaningCandidates) {
                let title = found.title.isEmpty ? displayURL(found.url) : found.title
                if found.place == .conversation, let id = ConversationPage.id(of: found.url) {
                    var candidate = ArcRanking.Candidate(archetype: .assistantHistory, autocompleteText: title, dedupKey: "conversation:\(id)")
                    candidate.features = ArcRanking.matchFeatures(text, url: nil, title: title, hotWords: [])
                    out.append(Built(candidate: candidate, row: Suggestion(kind: .meaning, title: title, subtitle: nil, symbol: "sparkle.magnifyingglass", favicon: nil,
                                                                           hint: OverlayCopy.conversation, command: .assist(.showConversation(id)))))
                    continue
                }
                let open = found.tab.flatMap { id in bar.tabs.first { $0.tab == id } }
                let candidate = page(open != nil ? .tab : .chromiumHistory, url: found.url, title: title)
                out.append(Built(candidate: candidate, row: Suggestion(kind: .meaning, title: title, subtitle: nil, symbol: "sparkle.magnifyingglass", favicon: nil,
                                                                       hint: open != nil ? OverlayCopy.switchToTab : found.place == .archive ? OverlayCopy.archived : nil,
                                                                       command: open.map { .tab(.focus($0.tab)) } ?? .commandBar(.submit(found.url.absoluteString)))))
            }
        }

        // Max's Ask row (Arc's "Ask ChatGPT →", P49) for a search of two words or more, or a question.
        if let provider = bar.askProvider, !isAddress, completing == nil, text.split(whereSeparator: \.isWhitespace).count >= 2 || text.hasSuffix("?") {
            out.append(Built(candidate: ArcRanking.Candidate(archetype: .askGPTWhatYouTyped, autocompleteText: text, dedupKey: "ask"), row: askRow(text, provider: provider)))
        }

        return out
    }

    /// Answers worked out from the text itself (Brk's own): the calculator, a quick answer, a colour's three forms. Arc 1.170
    /// lists no calculator answer (for "2+2" it shows the search and the engine's suggestions), so these keep the places Brk
    /// gave them: the rows that lead when the text can only be that question, and the rows for under the typed row.
    static func answers(_ text: String, bar: CommandBarSnapshot, timeZone: TimeZone, locale: Locale) -> (leading: [Suggestion], below: [Suggestion]) {
        var leading: [Suggestion] = [], below: [Suggestion] = []
        if let result = BrowserCalculator.result(text) {
            leading.append(Suggestion(kind: .calculator, title: result, subtitle: text, symbol: "equal", favicon: nil, hint: "Copy Result",
                                      command: .commandBar(.calculate(text))))
        } else if !bar.fillsPane, let quick = QuickAnswers.answer(text, QuickAnswerContext(now: bar.now, timeZone: timeZone, locale: locale, rates: bar.rates)) {
            if QuickAnswers.leads(text) { leading.append(quickRow(quick)) } else { below.append(quickRow(quick)) }
        }
        if !bar.fillsPane, let color = QuickColors.parse(text) {
            if QuickColors.leads(text) { leading.append(contentsOf: colorRows(color)) } else { below.append(contentsOf: colorRows(color)) }
        }
        return (leading, below)
    }

    /// How many candidates each source gives the ranking. Arc's providers' own limits were not read; Chromium's result
    /// holds about ten rows.
    private static let tabCandidates = 8, historyCandidates = 10, suggestionCandidates = 10, topDomainCandidates = 5, commandCandidates = 5,
                       localCandidates = 2, conversationCandidates = 2, meaningCandidates = 2

    /// A tab's title words, its hot words in Arc's ranking ("fixture" is a whole word of "Visual fixture").
    static func words(_ title: String) -> [String] {
        title.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// One row per page: the readable address, or the title and host on Arc's dedup hosts.
    static func pageKey(_ url: URL, _ title: String) -> String {
        if let host = host(url), dedupByTitleAndHost.contains(host), !title.isEmpty { return "page:\(host)\u{0}\(title)" }
        return "page:" + ArcRanking.readable(url)
    }

    /// Where a tab's switches from the bar are saved, beside the commands' runs.
    static func switchKey(_ tab: ItemID) -> String { "tab:\(tab.rawValue)" }

    static func searchKey(_ text: String) -> String { "search:" + fold(text.trimmingCharacters(in: .whitespacesAndNewlines)) }

    /// What a command row's runs are saved under: its command, as stable JSON.
    public static func usageKey(_ command: Command) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(command)).flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: command)
    }

    private static func fileRow(_ hit: LocalHit) -> Suggestion {
        let folder = ((hit.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        return Suggestion(kind: .file, title: hit.name, subtitle: folder, symbol: nil, favicon: nil, hint: OverlayCopy.fileRowKeys,
                          command: .commandBar(.local(.open, path: hit.path)), icon: .document(name: hit.name, contentType: hit.contentType),
                          commandReturn: .commandBar(.local(.reveal, path: hit.path)), optionReturn: .commandBar(.local(.copyPath, path: hit.path)))
    }

    private static func appRow(_ hit: LocalHit) -> Suggestion {
        Suggestion(kind: .app, title: hit.name, subtitle: nil, symbol: nil, favicon: nil, hint: OverlayCopy.openApp,
                   command: .commandBar(.local(.open, path: hit.path)), icon: .file(hit.path))
    }

    /// Tab sends the typed text to the local AI: a text in a new-tab bar with Max's tool on and found, not an address and not
    /// a site being completed. Nil keeps Tab as it was. Site search's offer, a prefix word and the tool's name go first (the
    /// view).
    public static func tabQuestion(_ typed: String, completing: String?, bar: CommandBarSnapshot, resolve: ((String) -> URL?)? = nil) -> String? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, completing == nil, bar.createsTab, bar.aiMode == nil, bar.askProvider != nil, bar.askAgentFound else { return nil }
        let engine = SearchEngine.builtIn(bar.engine.id) ?? bar.engine.template.map {
            SearchEngine(id: bar.engine.id, name: bar.engine.name, keyword: bar.engine.keyword, template: $0, suggestTemplate: nil)
        } ?? .google
        guard let url = (resolve ?? { resolveTypedInput($0, engine: engine) })(text), url == engine.searchURL(text) || isSearch(url, for: text) else { return nil }
        return text
    }

    /// The Ask row: the query after Max's flower, "Ask <tool>" and the arrow square on the right.
    static func askRow(_ text: String, provider: String) -> Suggestion {
        Suggestion(kind: .ask, title: text, subtitle: nil, symbol: nil, favicon: nil, hint: OverlayCopy.ask(provider), command: .assist(.ask(text)))
    }

    /// Instant Links (Shift+Return, P48-a): the query when the typed text is a web search on the bar's engine, nil for
    /// an address, a calculation or nothing.
    public static func instantQuery(_ typed: String, bar: CommandBarSnapshot, resolve: ((String) -> URL?)? = nil) -> String? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard bar.instantLinks, bar.aiMode == nil, !text.isEmpty, BrowserCalculator.result(text) == nil else { return nil }
        let engine = SearchEngine.builtIn(bar.engine.id) ?? bar.engine.template.map {
            SearchEngine(id: bar.engine.id, name: bar.engine.name, keyword: bar.engine.keyword, template: $0, suggestTemplate: nil)
        } ?? .google
        guard let url = (resolve ?? { resolveTypedInput($0, engine: engine) })(text) else { return nil }
        return url == engine.searchURL(text) || isSearch(url, for: text) ? text : nil
    }

    /// Typing the local tool's name (three letters at least) and Tab asks it (Arc: start typing "ChatGPT", hit Tab).
    public static func asksProvider(_ typed: String, bar: CommandBarSnapshot) -> Bool {
        guard let provider = bar.askProvider?.lowercased(), bar.aiMode == nil else { return false }
        let text = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return text.count >= 3 && provider.hasPrefix(text)
    }

    // MARK: Inline completion and site search beside the input

    /// The domain the input completes `typed` to, the completed part selected (Arc: "githu" shows github.com, "wiki"
    /// wikipedia.org). Arc completes only to its first row: when that row opens a site (an open or saved tab, a visited
    /// page, a popular site) whose host starts with what is typed and is longer, the input shows that host; a search, a
    /// command or a tab found by a word of its title completes nothing. Only for a bare host being typed: two characters
    /// or more, a letter first, then letters, digits, dots and hyphens. The caller decides whether the user is typing on
    /// (a deletion never completes).
    public static func completion(_ typed: String, bar: CommandBarSnapshot, appName: String) -> String? {
        let needle = typed.lowercased()
        guard bar.aiMode == nil, needle.count >= 2, let first = needle.first, first.isASCII, first.isLetter,
              needle.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }),
              let row = rank(query: typed, bar: bar, appName: appName).first else { return nil }
        let url: URL?
        switch (row.kind, row.command) {
        case (.switchToTab, .tab(.focus(let id))): url = bar.tabs.first { $0.tab == id }?.url
        case (.topDomain, .commandBar(.submit(let domain))): url = URL(string: "https://\(domain)")
        case (.history, .commandBar(.submit(let address))), (.bookmark, .commandBar(.submit(let address))): url = URL(string: address)
        default: url = nil
        }
        guard let host = url.flatMap(host), host.hasPrefix(needle), host.count > needle.count else { return nil }
        return host
    }

    /// The engine Tab searches, shown beside the input as "Search Wikipedia" and a Tab key: the one for the completed
    /// site (its keyword is that domain, or its name is the site's name), else the first one whose name or keyword
    /// the typed text begins (two letters at least, one word).
    public static func siteSearchOffer(_ typed: String, completing: String?, bar: CommandBarSnapshot) -> SearchEngineCandidate? {
        guard bar.aiMode == nil else { return nil }
        if let completing {
            let name = TopDomains.all.first { $0.domain == completing }?.name
            if let engine = bar.siteSearch.first(where: { $0.keyword == completing || $0.name == name }) { return engine }
        }
        return siteSearchCandidate(fold(typed.trimmingCharacters(in: .whitespacesAndNewlines)), bar)
    }

    // MARK: Sources

    private static func switchRow(_ tab: SwitchCandidate) -> Suggestion {
        Suggestion(kind: .switchToTab, title: tab.title, subtitle: nil, symbol: "globe", favicon: tab.favicon,
                   hint: OverlayCopy.switchToTab, command: .tab(.focus(tab.tab)))
    }

    private static func historyRow(_ entry: HistoryCandidate) -> Suggestion {
        Suggestion(kind: .history, title: entry.title.isEmpty ? displayURL(entry.url) : entry.title, subtitle: nil,
                   symbol: "clock", favicon: nil, hint: nil, command: .commandBar(.submit(entry.url.absoluteString)))
    }

    /// "Wikimedia — wikimedia.org" (Q01-b); `named`: the name alone.
    private static func domainRow(_ site: TopDomains.Site, named: Bool = false) -> Suggestion {
        Suggestion(kind: .topDomain, title: site.name, subtitle: named || site.name == site.domain ? nil : site.domain, symbol: "globe", favicon: nil,
                   hint: nil, command: .commandBar(.submit(site.domain)))
    }

    /// Arc's "Contact the Team" row: the Help menu's item (`ActionID.contactTheTeam`), its bubble on a tile.
    static let contactRow = Suggestion(kind: .suggested, title: ActionID.contactTheTeam.spec.title, subtitle: nil, symbol: "ellipsis.message",
                                       favicon: nil, hint: nil, command: ActionID.contactTheTeam.spec.command, tile: true)

    /// Arc's own entries, which fill an empty list after the recent tabs and follow the page being edited: Contact
    /// the Team, The Browser Company (its YouTube channel, from Arc's starter content), Air Traffic Control, Tips for
    /// Organizing and Help Center, each with its address (P02-b, Q01-a, P20-a, P21-a). The channel and the help center
    /// open what Arc's rows open. Arc's Air Traffic Control and Tips for Organizing open two help articles whose
    /// addresses the captures show only in part (resources.arc.net/…stinct-browsing-areas, …5255982103-features);
    /// ours open the Links preferences (Air Traffic Control's pane, also its type-travel trigger) and Getting Started,
    /// and say so where Arc shows the address.
    static let arcRows: [Suggestion] = [
        contactRow,
        Suggestion(kind: .suggested, title: "The Browser Company", subtitle: "youtube.com/c/thebrowsercompany", symbol: "play.rectangle.fill",
                   favicon: nil, hint: nil, command: .commandBar(.submit("https://www.youtube.com/c/thebrowsercompany")), accent: RGBA(hex: "#FF0033")),
        Suggestion(kind: .suggested, title: "Air Traffic Control", subtitle: OverlayCopy.preferencesTitle(.links), symbol: "globe", favicon: nil, hint: nil,
                   command: .settings(.openPane(.links))),
        Suggestion(kind: .suggested, title: "Tips for Organizing", subtitle: ActionID.gettingStarted.spec.title, symbol: "globe", favicon: nil, hint: nil,
                   command: ActionID.gettingStarted.spec.command),
        Suggestion(kind: .suggested, title: "Help Center", subtitle: "resources.arc.net", symbol: "globe", favicon: nil, hint: nil,
                   command: .commandBar(.submit("https://resources.arc.net/hc/en-us"))),
    ]

    /// The engine's suggestions that still answer `text`: all of them while they were asked for exactly this text,
    /// else (the user typed on) only those that start with it; none once the text no longer starts with what was
    /// asked. The typed text itself is the typed row, not a suggestion.
    private static func engineSuggestions(_ text: String, _ bar: CommandBarSnapshot) -> [String] {
        guard let asked = bar.suggestedFor.map(fold) else { return [] }
        let now = fold(text)
        guard now.hasPrefix(asked) else { return [] }
        return bar.suggestions.filter { s in
            let folded = fold(s)
            return folded != now && (asked == now || folded.hasPrefix(now))
        }
    }

    /// The first site-search engine whose name or keyword the query begins (two letters at least, one word).
    static func siteSearchCandidate(_ needle: String, _ bar: CommandBarSnapshot) -> SearchEngineCandidate? {
        guard needle.count >= 2, !needle.contains(where: \.isWhitespace) else { return nil }
        return bar.siteSearch.first { fold($0.name).hasPrefix(needle) || fold($0.keyword).hasPrefix(needle) }
    }

    /// The engine whose whole name or keyword `word` is: Space after it enters site search.
    static func siteSearchEngine(named word: String, _ bar: CommandBarSnapshot) -> SearchEngineCandidate? {
        let needle = fold(word.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else { return nil }
        return bar.siteSearch.first { fold($0.name) == needle || fold($0.keyword) == needle }
    }

    private static func siteSearchRows(_ text: String, on engine: SearchEngineCandidate, bar: CommandBarSnapshot) -> [Suggestion] {
        guard !text.isEmpty else { return [] }
        // The engine's pill before the input says where these search.
        let search = Suggestion(kind: .openTyped, title: text, subtitle: nil, symbol: "magnifyingglass",
                                favicon: nil, hint: nil, command: .commandBar(.submitSearch(engine: engine.id, query: text)))
        return [search] + engineSuggestions(text, bar).prefix(suggestionCap).map { s in
            Suggestion(kind: .searchSuggestion, title: s, subtitle: nil, symbol: "magnifyingglass", favicon: nil, hint: nil,
                       command: .commandBar(.submitSearch(engine: engine.id, query: s)))
        }
    }

    // MARK: Type travel

    private struct Scored {
        let score: Int
        let suggestion: Suggestion
        let triggers: [String]
        /// The text starts a word of the title or of a trigger (what a command candidate needs).
        let startsAWord: Bool
    }

    /// Every type-travel candidate that matches, best first (ties in source order: actions in table order, panes,
    /// spaces). Score: 4 the whole title or a trigger, 3 the start of one up to a word's end, 2 any other start of a
    /// word, 1 mid-word.
    private static func typeTravel(_ needle: String, bar: CommandBarSnapshot, appName: String) -> [Scored] {
        var candidates: [(title: String, triggers: [String], symbol: String, hint: String?, command: Command)] = []
        for action in bar.actions {
            guard let listing = action.spec.commandBar else { continue }
            candidates.append((action.barTitle(appName: appName), action.barTriggers(appName: appName), listing.symbol,
                               bar.keys[action]?.glyphs, action.spec.barCommand))
        }
        if let app = bar.newDocument {
            candidates.append((app.newDocumentTitle, ["New Document", "New Doc", "New " + app.title], "doc.badge.plus", nil, .tab(.newDocument)))
        }
        for pane in SettingsPane.allCases {
            candidates.append((OverlayCopy.preferencesTitle(pane), OverlayCopy.preferencesTriggers(pane), "gearshape", nil, .settings(.openPane(pane))))
        }
        let focused = bar.tabs.first(where: \.isFocused)?.tab
        for space in bar.spaces where !space.isCurrent {
            candidates.append(("\(OverlayCopy.focusSpace) \(space.title)", [], "square.on.square", nil, .space(.focus(space.id))))
            if let focused {
                candidates.append(("\(OverlayCopy.moveToSpace) \(space.title)", [], "arrow.right.square", nil, .item(.move(focused, to: .space(space.id)))))
            }
        }
        if let focused {
            for folder in bar.folders {
                candidates.append(("Move to \(folder.title)", [], "folder", nil, .item(.move(focused, to: .into(parent: folder.id, index: Int.max)))))
            }
        }
        for travel in bar.travel {
            candidates.append((travel.title, travel.triggers, travel.symbol, nil, travel.command))
        }
        let scored = candidates.enumerated().compactMap { index, c -> (Int, Int, Scored)? in
            guard let score = score(needle, title: c.title, triggers: c.triggers) else { return nil }
            let startsAWord = matchRank(needle, in: [c.title] + c.triggers) == 0
            return (score, index, Scored(score: score, suggestion: Suggestion(kind: .action, title: c.title, subtitle: nil, symbol: c.symbol,
                                                                              favicon: nil, hint: c.hint, command: c.command),
                                         triggers: c.triggers, startsAWord: startsAWord))
        }
        return scored.sorted {
            if $0.0 != $1.0 { return $0.0 > $1.0 }
            let a = $0.2.suggestion.hint?.count ?? Int.max, b = $1.2.suggestion.hint?.count ?? Int.max
            return a != b ? a < b : $0.1 < $1.1
        }.map(\.2)
    }

    private static func score(_ needle: String, title: String, triggers: [String]) -> Int? {
        let texts = [title] + triggers
        let folded = texts.map { fold($0).trimmingCharacters(in: CharacterSet(charactersIn: "…")) }
        if folded.contains(needle) { return 4 }
        if folded.contains(where: { text in
            guard text.hasPrefix(needle) else { return false }
            let next = text.dropFirst(needle.count).first
            return next.map { !($0.isLetter || $0.isNumber) } ?? true
        }) { return 3 }
        if let rank = matchRank(needle, in: [title]) { return 2 - rank }
        return matchRank(needle, in: triggers).map { 1 - $0 }
    }

    // MARK: Matching

    /// Whether `url` is a search for exactly `text`: the URL policy put the typed text into a query value.
    private static func isSearch(_ url: URL, for text: String) -> Bool {
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.compactMap(\.value) ?? []
        return values.contains { $0 == text || $0.replacingOccurrences(of: "+", with: " ") == text }
    }

    /// Arc's `command_bar_behavior.json` `dedupByTitleAndHostList`: on these hosts two pages with one title are one
    /// result (a Figma file or a Notion page reached through different URLs).
    private static let dedupByTitleAndHost: Set<String> = [
        "figma.com", "maps.google.com", "notion.so", "app.notion.com", "zoom.us", "opentable.com", "zillow.com", "github.com", "app.mode.com",
        "console.cloud.google.com",
    ]

    private static func host(_ url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// What makes two results the same page: the URL, or the title and host on Arc's dedup hosts.
    private static func identity(_ url: URL, _ title: String) -> String {
        if let host = host(url), dedupByTitleAndHost.contains(host), !title.isEmpty { return "\(host)\u{0}\(title)" }
        return url.absoluteString
    }

    /// Newest visit first, one entry per page (per title and host on Arc's dedup hosts), skipping pages in `excluding`
    /// (URLs and identities).
    private static func recentHistory(_ history: [HistoryCandidate], excluding: Set<String> = []) -> [HistoryCandidate] {
        var seen = excluding
        return history.sorted { $0.visitedAt > $1.visitedAt }.filter { entry in
            guard !seen.contains(entry.url.absoluteString), seen.insert(identity(entry.url, entry.title)).inserted else { return false }
            seen.insert(entry.url.absoluteString)
            return true
        }
    }

    /// Items matching `needle` in their texts: word-start matches first, then mid-word ones, each in given order.
    private static func matching<T>(_ items: [T], _ needle: String, texts: (T) -> [String]) -> [T] {
        let ranked = items.map { ($0, matchRank(needle, in: texts($0))) }
        return ranked.filter { $0.1 == 0 }.map(\.0) + ranked.filter { $0.1 == 1 }.map(\.0)
    }

    /// 0 when `needle` starts a word in one of `texts`, 1 when it appears only mid-word, nil when it is absent.
    private static func matchRank(_ needle: String, in texts: [String]) -> Int? {
        var rank: Int?
        for text in texts {
            let hay = fold(text)
            var from = hay.startIndex
            while let found = hay.range(of: needle, range: from..<hay.endIndex) {
                if found.lowerBound == hay.startIndex { return 0 }
                let before = hay[hay.index(before: found.lowerBound)]
                if !(before.isLetter || before.isNumber) { return 0 }
                rank = 1
                from = hay.index(after: found.lowerBound)
            }
        }
        return rank
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// The command bar's wave 2 copy (visual-and-copy.md "Command bar and URL inputter", "Settings page labels").
extension OverlayCopy {
    /// The key shown beside "Search Wikipedia" (P02-c, Q01-b); Space after an engine's whole name also enters site
    /// search, as the comments "Hint for using the Space key…" and "…the Tab key…" say.
    static let siteSearchKey = "Tab"
    /// Brk's own rows' captions (beyond Arc).
    static let fileRowKeys = "⌘↩ Reveal  ⌥↩ Copy Path"
    static let openApp = "Open App"
    static let copyEmoji = "Copy Emoji"
    static let copyColor = "Copy Color"
    static let openDictionary = "Open Dictionary"
    static let archived = "Archived"
    static let conversation = "Conversation"
    static func noDefinition(_ word: String) -> String { "No definition for \(word)" }
    static func translatePage(_ target: String) -> String { "Translate this page to \(target)" }
    static func translating(_ target: String) -> String { "Translating to \(target)…" }
    static func newPane(_ edge: SplitEdge) -> String { "New pane on the \(edge.rawValue)" }
    static let askThisPage = "Ask about this page"
    static let summarizeThisPage = "Summarize this page"
    /// GUESS: "Site Search placeholder where the wildcard is the name of the site."
    static func siteSearchPlaceholder(_ engine: String) -> String { "\(searchVerb) \(engine)…" }
    /// Observed: "Focus on <space>" (`TypeTravelCandidate.focusSpace`).
    static let focusSpace = "Focus on"
    /// Arc writes "Move to Today in <space>" or "Move to Pinned in <space>"; Brk's move keeps the tab's section
    /// (Today, or Pinned when it came from Pinned), so the section is left out.
    static let moveToSpace = "Move to"

    /// Observed window titles ("General Preferences", "Profile Preferences", "Link Preferences", "Shortcuts
    /// Preferences", "Advanced Preferences"); Max is ours ("Arc Max Preferences" in Arc).
    static func preferencesTitle(_ pane: SettingsPane) -> String {
        switch pane {
        case .general: "General Preferences"
        case .max: "Max Preferences"
        case .profiles: "Profile Preferences"
        case .shortcuts: "Shortcuts Preferences"
        case .links: "Link Preferences"
        case .icon: "Icon Preferences"
        case .advanced: "Advanced Preferences"
        }
    }

    /// Arc's trigger phrases for the panes it reaches by name ("link preferences", "air traffic control", "Action to
    /// manage search settings").
    static func preferencesTriggers(_ pane: SettingsPane) -> [String] {
        switch pane {
        case .links: ["Air Traffic Control", "Air Traffic Controller"]
        case .profiles: ["Search Settings"]
        case .icon: ["App Icon"]
        case .general, .max, .shortcuts, .advanced: []
        }
    }
}
