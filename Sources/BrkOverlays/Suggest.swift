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

    public enum Icon: Equatable, Sendable {
        case file(String)
        case document(name: String, contentType: String?)
        case emoji(String)
        case swatch(RGBA)
    }
}

public enum Suggest {
    /// Per-source caps (electron-v1 `suggest.ts` CAP, our choice there too), so one source cannot push the others
    /// out of the rows. Engine suggestions: three, so history and actions keep a row in Arc's five (a guess; Arc
    /// mixes its sources with a scoring model that was not recovered).
    private static let tabCap = 3, historyCap = 3, actionCap = 3, emptyTabCap = 4, suggestionCap = 3, topDomainCap = 1
    /// With an inline completion the typed text names a site, and Arc lists more sites under it (Q01-b: "wiki" shows
    /// Wikimedia, Fandom and wikiHow).
    private static let completingTopDomainCap = 3
    /// A type-travel result outranks everything when the query is the start of its title or a trigger word,
    /// ending where a word ends, and is at least this long ("Press ⌘T, and type “update”" is Arc's own
    /// instruction for Check for Updates). "swi" is not a top hit for "Switch to Dark Mode"; "night" is.
    private static let topHitMinLength = 3

    /// Ranks results for `query`, at most Metrics.commandBar.maxVisibleRows (Arc shows 5). The page being edited
    /// (`query` is `bar.initialQuery`, the focused tab's URL, untouched): that page, then Arc's own entries (P02-b).
    /// A blank query: the recent tabs without the focused one (at most 4), then Arc's own entries fill the five rows
    /// (Q01-a: four tabs and Contact the Team; P21-a, a Little window with no tabs: all five entries). With `completing` (the domain the input completes the query to, `completion`): that site
    /// first (its tab's switch row when it is open, else its top-domain row), the typed row, then tabs, history, up to
    /// three more top domains, the engine's suggestions and type travel (P02-c, Q01-b). Otherwise, a non-blank query:
    /// 1. the top hit: the best type-travel result when the query is its title or the start of its title or of one
    ///    of its trigger words up to a word's end (an exact title or trigger first), 3 characters at least, and the
    ///    query is not an address;
    /// 2. open tabs whose title or URL matches (`.tab(.focus(id))`), never the focused one; word-start matches
    ///    before mid-word. For an address, only exact URL matches precede the typed row (none while the bar fills an
    ///    empty split pane, `fillsPane`: the typed row opens there); partial matches follow it;
    /// 3. "open what you typed" (`.commandBar(.submit(trimmed))`) when `resolve` accepts it: "Search <q>" when it
    ///    resolves to a search for the text, else "Open <url>"; a typed URL that is also in history shows once;
    /// 4. (site search is offered beside the input, `siteSearchOffer`, not as a row);
    /// 5. one of Arc's top domains whose domain or site name the query begins (`.commandBar(.submit(domain))`);
    /// 6. the engine's suggestions for the query (`bar.suggestions` while `bar.suggestedFor` is the start of what
    ///    is typed; ones that no longer start with the text are dropped), searched on the profile's engine;
    /// 7. history entries (`.commandBar(.submit(url))`), newest first, one row per URL (per title and host on Arc's
    ///    dedup hosts: figma.com, notion.so, github.com...), none that an open tab has;
    /// 8. the rest of the type-travel results: listed actions (their command and resolved shortcut), the settings
    ///    panes (`.settings(.openPane)`), "Focus on <space>" and "Move to <space>" for the other spaces.
    /// In site-search mode (`siteSearch` set) the rows are the query on that engine and the suggestions, each a
    /// `.commandBar(.submitSearch)` on it.
    /// Matching is case- and diacritic-insensitive. `resolve` is the domain's URL policy (default: the bar's engine).
    ///
    /// Brk's own sources beyond Arc, none of which changes a row when it has nothing to say, and none in site search, AI
    /// mode or a bar that fills an empty pane: a quick answer (`QuickAnswers`) leads when the text can only be that
    /// question, else sits right under the typed row so Return still searches; apps and files take the last two rows at
    /// most (never the top hit, never the typed row) while `bar.local` answers exactly this text, in `createsTab` bars only.
    /// A `prefix` (`QuickPrefixes`) has the whole list to itself, like site search, but for Arc's own row that the word and
    /// the text together name ("ask on page", "split view"): `prefixWord` is the word as typed, and that row leads, so no
    /// prefix hides one of Arc's rows.
    public static func rank(query: String, bar: CommandBarSnapshot, appName: String, siteSearch: SearchEngineCandidate? = nil, prefix: QuickPrefix? = nil, prefixWord: String = "",
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
        if let prefix {
            let phrase = fold(prefixWord + " " + text)
            let arcs = text.isEmpty || prefixWord.isEmpty ? [] : typeTravel(phrase, bar: bar, appName: appName).filter { $0.score >= 3 }.prefix(1).map(\.suggestion)
            let own = prefixRows(prefix, text, bar: bar, appName: appName)
            // "translate page" runs the page translation at once; Arc's Translate Page… asks for a language first, so it follows.
            return Array((prefix.action == .translate ? own + arcs : arcs + own).prefix(limit))
        }
        let tabs = bar.tabs.filter { !$0.isFocused }
        var taken = Set(bar.tabs.flatMap { [$0.url.absoluteString, identity($0.url, $0.title)] })
        if text.isEmpty {
            return Array((tabs.prefix(emptyTabCap).map(switchRow) + arcRows).prefix(limit))
        }
        if let current = bar.tabs.first(where: \.isFocused), text == bar.initialQuery.trimmingCharacters(in: .whitespacesAndNewlines),
           current.url.absoluteString == text {
            let row = Suggestion(kind: .current, title: current.title, subtitle: nil, symbol: "globe", favicon: current.favicon, hint: nil,
                                 command: .commandBar(.submit(text)))
            return Array(([row] + arcRows).prefix(limit))
        }

        let selectedEngine = SearchEngine.builtIn(bar.engine.id) ?? bar.engine.template.map {
            SearchEngine(id: bar.engine.id, name: bar.engine.name, keyword: bar.engine.keyword, template: $0, suggestTemplate: nil)
        } ?? .google
        let resolve = resolve ?? { resolveTypedInput($0, engine: selectedEngine) }
        let needle = fold(text)
        if let result = BrowserCalculator.result(text) {
            return [Suggestion(kind: .calculator, title: result, subtitle: text, symbol: "equal", favicon: nil, hint: "Copy Result",
                               command: .commandBar(.calculate(text)))]
        }
        let quick = bar.fillsPane ? nil : QuickAnswers.answer(text, QuickAnswerContext(now: bar.now, timeZone: timeZone, locale: locale, rates: bar.rates)).map(quickRow)
        var typed: Suggestion?
        var isAddress = false
        let resolvedURL = resolve(text)
        if let url = resolvedURL {
            let search = url == selectedEngine.searchURL(text) || isSearch(url, for: text)
            isAddress = !search
            if !search { taken.insert(url.absoluteString) }
            typed = Suggestion(kind: .openTyped, title: search ? text : displayURL(url),
                               subtitle: nil, symbol: search ? "magnifyingglass" : "globe", favicon: nil, hint: nil,
                               command: .commandBar(.submit(text)))
        }
        // The completed site leads: its open tab, else its top-domain row (and neither shows again below).
        let completed = completing.map { domain -> Suggestion in
            if let tab = tabs.first(where: { host($0.url) == domain }) { return switchRow(tab) }
            // The input shows the domain, so the row is the site's name alone (P02-c "Google Docs").
            return domainRow(TopDomains.Site(domain: domain, name: TopDomains.all.first { $0.domain == domain }?.name ?? domain), named: true)
        }
        let matches = matching(tabs, needle) { [$0.title, $0.url.absoluteString] }.filter { completed?.command != .tab(.focus($0.tab)) }
        // A URL is a destination, including its path, query and fragment. Keep fuzzy matches available, but
        // Return must not switch to cookie.html#set when the user typed cookie.html.
        let exact = isAddress ? tabs.filter { $0.url == resolvedURL } : []
        let switches = (isAddress ? exact : matches).prefix(tabCap).map(switchRow)
        let related = isAddress ? matches.filter { $0.url != resolvedURL }.prefix(max(0, tabCap - switches.count)).map(switchRow) : []
        let openHosts = Set(bar.tabs.compactMap { host($0.url) })
        var seenDomains = Set(completing.map { [$0] } ?? [])
        // Arc's table lists some sites twice (wikipedia.org); each shows once.
        var domains: [Suggestion] = []
        if needle.count >= 2, !needle.contains(where: \.isWhitespace) {
            for site in TopDomains.all where domains.count < (completing == nil ? topDomainCap : completingTopDomainCap) {
                guard site.domain.hasPrefix(needle) || fold(site.name).hasPrefix(needle), !openHosts.contains(site.domain),
                      resolve(site.domain).map({ !taken.contains($0.absoluteString) }) != false, seenDomains.insert(site.domain).inserted else { continue }
                domains.append(domainRow(site))
            }
        }
        let suggestions = engineSuggestions(text, bar).prefix(suggestionCap).map { s in
            Suggestion(kind: .searchSuggestion, title: s, subtitle: nil, symbol: "magnifyingglass", favicon: nil, hint: nil,
                       command: .commandBar(.submitSearch(engine: bar.engine.id, query: s)))
        }
        let history = matching(recentHistory(bar.history, excluding: taken), needle) { [$0.title, $0.url.absoluteString] }
            .prefix(historyCap).map(historyRow)

        var travel = typeTravel(needle, bar: bar, appName: appName)
        var top: [Suggestion] = []
        if let best = travel.first, best.score >= 3, needle.count >= topHitMinLength, !isAddress {
            top = [best.suggestion]
            travel.removeFirst()
        }
        let bookmarks = matching(bar.bookmarks.filter { !taken.contains($0.url.absoluteString) }, needle) { [$0.title, $0.url.absoluteString] }.prefix(2).map { entry in
            Suggestion(kind: .bookmark, title: entry.title, subtitle: nil, symbol: "bookmark", favicon: nil, hint: nil,
                       command: .commandBar(.submit(entry.url.absoluteString)))
        }
        let typedRow = typed.map { [$0] } ?? []
        // Filling an empty split pane, a typed address opens in that pane: it leads, the tab showing it follows.
        let (lead, trail) = bar.fillsPane && isAddress ? ([], switches) : (switches, [])
        var rows: [Suggestion]
        if let completed {
            rows = [completed] + typedRow + switches + related + history + domains + bookmarks + suggestions + travel.prefix(actionCap).map(\.suggestion)
        } else {
            rows = top + lead + typedRow + trail + related + domains + bookmarks + suggestions + history + travel.prefix(actionCap).map(\.suggestion)
        }
        // Max's Ask row is the third (P49: the search, one suggestion, then Ask ChatGPT →) for a search of two words or
        // more, or a question.
        if let provider = bar.askProvider, !isAddress, completed == nil, text.split(whereSeparator: \.isWhitespace).count >= 2 || text.hasSuffix("?") {
            rows.insert(askRow(text, provider: provider), at: min(2, rows.count))
        }
        if let quick {
            if QuickAnswers.leads(text) { rows.insert(quick, at: 0) }
            else { rows.insert(quick, at: rows.firstIndex { $0.kind == .openTyped }.map { $0 + 1 } ?? rows.count) }
        }
        if !bar.fillsPane, let color = QuickColors.parse(text) {
            rows.insert(contentsOf: colorRows(color), at: QuickColors.leads(text) ? 0 : rows.firstIndex { $0.kind == .openTyped }.map { $0 + 1 } ?? rows.count)
        }
        rows = withLocalRows(rows, text, isAddress: isAddress, bar: bar, limit: limit)
        // An exact phrase like "left half": its row low down. Nothing else about the window reaches ordinary queries.
        if bar.createsTab, let placement = WindowSnap.exact(text) { rows = withLastRows(rows, [placementRow(placement)], limit: limit) }
        return Array(rows.prefix(limit))
    }

    // MARK: Brk's own sources

    /// The most file and app rows among the others.
    private static let inlineLocalCap = 2

    private static func quickRow(_ answer: QuickAnswer) -> Suggestion {
        let symbol = switch answer.kind { case .math: "equal"; case .date: "clock"; case .currency: "dollarsign.circle" }
        return Suggestion(kind: .calculator, title: answer.answer, subtitle: answer.detail, symbol: symbol, favicon: nil, hint: "Copy Result",
                          command: .commandBar(.copyAnswer(answer.answer)))
    }

    /// A prefix's own rows for the text after its word.
    private static func prefixRows(_ prefix: QuickPrefix, _ text: String, bar: CommandBarSnapshot, appName: String) -> [Suggestion] {
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
            return splitRows(text, bar: bar, appName: appName)
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
    private static func splitRows(_ text: String, bar: CommandBarSnapshot, appName: String) -> [Suggestion] {
        let (edge, rest) = QuickSplit.parse(text)
        let side = edge ?? .right
        let needle = fold(rest)
        var scored: [(score: Int, row: Suggestion)] = []
        for action in splitActions where bar.actions.contains(action) {
            let score = needle.isEmpty ? 0 : score(needle, title: action.barTitle(appName: appName), triggers: action.barTriggers(appName: appName))
            guard needle.isEmpty || score != nil else { continue }
            scored.append((score ?? 0, Suggestion(kind: .action, title: action.barTitle(appName: appName), subtitle: nil, symbol: action.spec.commandBar?.symbol, favicon: nil,
                                                  hint: bar.keys[action]?.glyphs, command: action.spec.command)))
        }
        let named = scored.filter { $0.score >= 3 }.map(\.row), others = scored.filter { $0.score < 3 }.map(\.row)
        guard !rest.isEmpty else {
            let add = Suggestion(kind: .action, title: edge.map(TypeTravelCopy.addSplit) ?? ActionID.addSplitView.barTitle(appName: appName), subtitle: nil, symbol: "square.split.2x1", favicon: nil,
                                 hint: "Return", command: edge.map { .split(.addPaneAt($0)) } ?? .split(.addPane))
            return [add] + others
        }
        let where_ = OverlayCopy.newPane(side)
        let open = Suggestion(kind: .action, title: rest, subtitle: where_, symbol: "square.split.2x1", favicon: nil, hint: "Return", command: .commandBar(.splitOpen(side, rest)))
        let tabs = matching(bar.tabs.filter { !$0.isFocused }, needle) { [$0.title] }.prefix(2).map { tab in
            Suggestion(kind: .action, title: tab.title, subtitle: where_, symbol: "globe", favicon: tab.favicon, hint: "Return", command: .commandBar(.splitOpen(side, tab.url.absoluteString)))
        }
        return named + [open] + tabs + others
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
            Suggestion(kind: .action, title: action.barTitle(appName: appName), subtitle: nil, symbol: action.spec.commandBar?.symbol, favicon: nil, hint: bar.keys[action]?.glyphs, command: action.spec.command)
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

    /// Apps, then files, in the last places: they replace what would be cut last, and the typed row and anything above
    /// it stay.
    private static func withLocalRows(_ rows: [Suggestion], _ text: String, isAddress: Bool, bar: CommandBarSnapshot, limit: Int) -> [Suggestion] {
        guard bar.createsTab, !isAddress, text.count >= LocalSources.inlineMinLength, let local = bar.local, local.query == text, local.scope == .filesAndApps else { return rows }
        let found = Array((local.apps.map(appRow) + local.files.map(fileRow)).prefix(inlineLocalCap))
        return withLastRows(rows, found, limit: limit)
    }

    /// `found` in the last places: they replace what would be cut last, and the typed row and anything above it stay.
    private static func withLastRows(_ rows: [Suggestion], _ found: [Suggestion], limit: Int) -> [Suggestion] {
        guard !found.isEmpty else { return rows }
        let lastKept = rows.lastIndex { $0.kind == .openTyped || $0.kind == .calculator || $0.kind == .color } ?? 0
        let room = max(0, limit - (lastKept + 1))
        let shown = Array(found.prefix(room))
        return Array(rows.prefix(max(lastKept + 1, min(rows.count, limit - shown.count)))) + shown
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

    /// The domain the input completes `typed` to, the completed part selected (Arc: "wiki" shows wikipedia.org, "doc"
    /// docs.google.com): the first open tab's host (not the focused tab's), else the first of Arc's top domains, that
    /// starts with what is typed and is longer. Only for a bare host being typed: two characters or more, a letter
    /// first, then letters, digits, dots and hyphens; and not when a type-travel result is the top hit (Return runs
    /// that). The caller decides whether the user is typing on (a deletion never completes).
    public static func completion(_ typed: String, bar: CommandBarSnapshot, appName: String) -> String? {
        let needle = typed.lowercased()
        guard bar.aiMode == nil, needle.count >= 2, let first = needle.first, first.isASCII, first.isLetter,
              needle.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else { return nil }
        if let best = typeTravel(needle, bar: bar, appName: appName).first, best.score >= 3, needle.count >= topHitMinLength { return nil }
        let hosts = bar.tabs.filter { !$0.isFocused }.compactMap { host($0.url) } + TopDomains.all.map(\.domain)
        return hosts.first { $0.hasPrefix(needle) && $0.count > needle.count }
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
    }

    /// Every type-travel candidate that matches, best first (ties in source order: actions in table order, panes,
    /// spaces). Score: 4 the whole title or a trigger, 3 the start of one up to a word's end, 2 any other start of a
    /// word, 1 mid-word.
    private static func typeTravel(_ needle: String, bar: CommandBarSnapshot, appName: String) -> [Scored] {
        var candidates: [(title: String, triggers: [String], symbol: String, hint: String?, command: Command)] = []
        for action in bar.actions {
            guard let listing = action.spec.commandBar else { continue }
            candidates.append((action.barTitle(appName: appName), action.barTriggers(appName: appName), listing.symbol,
                               bar.keys[action]?.glyphs, action.spec.command))
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
            return (score, index, Scored(score: score, suggestion: Suggestion(kind: .action, title: c.title, subtitle: nil, symbol: c.symbol,
                                                                              favicon: nil, hint: c.hint, command: c.command)))
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

    /// Newest visit first, one entry per page, skipping pages in `excluding` (URLs and identities).
    private static func recentHistory(_ history: [HistoryCandidate], excluding: Set<String>) -> [HistoryCandidate] {
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
