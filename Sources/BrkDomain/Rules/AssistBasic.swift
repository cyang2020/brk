import BrkBase
import Foundation

// The basic AI layer (docs/design/ai-native.md, 基础 AI 功能): Name Tabs, folder names, Place New Tabs and the cleanup
// list beside Tidy. Brk does these in the background; the person sees only the result. Every request is one-shot work
// for the basic-features model, answered in a schema (`AITask.isBasic`), and decisions go through the decision
// interface (BrkBase/Decisions.swift).

/// Name Tabs: tabs wait `pause` after their page settles, then go out several to a request, at most `inFlight`
/// requests at once, so a restored window of a hundred tabs starts a handful of requests, not a hundred.
enum AINaming {
    static let pause: Duration = .milliseconds(1500)
    static let batch = 8
    static let inFlight = 2
    /// After a failure nothing is asked for this long (a signed-out agent would fail every batch).
    static let backoff: Duration = .seconds(300)
    static let maxLength = 40
}

/// Place New Tabs: what was asked about one new tab.
struct AIPlacementAsk: Equatable, Sendable {
    let tab: ItemID
    let window: WindowID
    let space: SpaceID
    let url: URL
    /// Option names to the groups and folders of the current space.
    var groups: [String: ItemID] = [:]
    /// Option names to the spaces of the profile.
    var spaces: [String: SpaceID] = [:]
}

/// Two tabs that may be the same page under different addresses.
public struct AIDuplicatePair: Hashable, Sendable, Codable {
    public let a: ItemID
    public let b: ItemID
    public let similarity: Double
    public init(a: ItemID, b: ItemID, similarity: Double) { self.a = a; self.b = b; self.similarity = similarity }
}

/// A one-click suggestion on a tab's row. Never applied by itself.
public struct AISuggestion: Hashable, Sendable, Codable {
    public enum Target: Hashable, Sendable, Codable { case folder(ItemID), space(SpaceID) }
    public let target: Target
    public let label: AISuggestionLabel
    let at: Instant
}

struct AIBasicSession: Equatable, Sendable {
    /// Tabs waiting for the pause after their page settled, and when it ends.
    var namingDue: [ItemID: Instant] = [:]
    /// Name Tabs requests in flight: each tab and the address it was asked about.
    var naming: [AIRequestID: [ItemID: URL]] = [:]
    /// Names made this session, by address: another tab on the same address takes the name without asking.
    var names: [URL: String] = [:]
    /// Tab and address pairs already asked once (answered or not).
    var asked: Set<String> = []
    var timerArmed = false
    var pausedUntil: Instant? = nil
    /// New Today tabs waiting for their first page, by the window they opened in.
    var placing: [ItemID: WindowID] = [:]
    var placements: [AIRequestID: AIPlacementAsk] = [:]
    var suggestions: [ItemID: AISuggestion] = [:]
    /// Folder names in flight: the folder and the window that asked.
    var folderNaming: [AIRequestID: ItemID] = [:]
    /// The reasons already told this session, so a failing agent says so once.
    var told: Set<String> = []
    /// Yes/no requests about candidate pairs: each question's key to the copy and the tab that stays.
    var duplicateAsks: [AIRequestID: [String: AIDuplicatePair]] = [:]
    /// Copies confirmed as the same page as another tab, offered in the cleanup list with the address duplicates.
    var nearDuplicates: Set<ItemID> = []
}

extension Work {
    // MARK: Reconcile

    /// Runs after every transition (`reconcileAI`): finds tabs to name and new tabs to place, drops what went away.
    mutating func reconcileBasic(from previous: AppState) {
        let max = state.doc.settings.max
        let wasNaming = previous.doc.settings.max.enabled(.tabNames)
        if wasNaming && !max.enabled(.tabNames) { forgetTabNames() }
        // Requests the general reconcile cancelled (another agent chosen, Max off) leave no bookkeeping behind.
        for id in state.session.ai.basic.naming.keys where state.session.pendingAI[id] == nil { state.session.ai.basic.naming[id] = nil }
        for id in state.session.ai.basic.placements.keys where state.session.pendingAI[id] == nil { state.session.ai.basic.placements[id] = nil }
        for id in state.session.ai.basic.folderNaming.keys where state.session.pendingAI[id] == nil { state.session.ai.basic.folderNaming[id] = nil }
        for id in state.session.ai.basic.duplicateAsks.keys where state.session.pendingAI[id] == nil { state.session.ai.basic.duplicateAsks[id] = nil }
        state.session.ai.basic.nearDuplicates = state.session.ai.basic.nearDuplicates.filter { state.tab($0) != nil }

        if max.enabled(.tabNames) {
            // Pages that changed, and named tabs whose address left the site they were named for (a commit changes the
            // tab, not its live page).
            let changed = state.session.live.filter { previous.session.live[$0.key] != $0.value }.map(\.key.item)
            var moved: [ItemID] = []
            for (window, doc) in state.doc.windows {
                let before = previous.doc.windows[window]?.slots ?? [:]
                for (item, slot) in doc.slots where before[item]?.committedURL != slot.committedURL { moved.append(item) }
            }
            let candidates = !wasNaming ? Array(Set(state.session.live.keys.map(\.item))) : changed + moved
            for tab in Set(candidates).sorted() { considerNaming(tab) }
            for tab in state.session.ai.basic.namingDue.keys where state.tab(tab) == nil { state.session.ai.basic.namingDue[tab] = nil }
            armNamingTimer()
        }

        // Place New Tabs: a tab that appeared directly in the Today of a window's current space.
        if max.enabled(.tabPlacement) {
            for (window, doc) in state.doc.windows where doc.kind == .standard {
                guard let root = state.doc.spaces[doc.space]?.todayRoot else { continue }
                for id in state.doc.tree[root]?.children ?? [] where state.doc.tree[id]?.kind == .tab && previous.doc.tree[id] == nil && previous.doc.archive.allSatisfy({ $0.tabID != id }) {
                    state.session.ai.basic.placing[id] = window
                }
            }
            for (tab, window) in state.session.ai.basic.placing { considerPlacing(tab, in: window) }
        } else {
            state.session.ai.basic.placing = [:]
        }
        // A suggestion goes when its tab left Today, closed, or was moved by hand.
        for (tab, suggestion) in state.session.ai.basic.suggestions {
            let inToday = state.role(of: tab)?.kind == .today && state.tab(tab) != nil
            let targetGone: Bool = switch suggestion.target {
            case .folder(let folder): state.doc.tree[folder] == nil
            case .space(let space): state.doc.spaces[space] == nil
            }
            if !inToday || targetGone || !max.enabled(.tabPlacement) { state.session.ai.basic.suggestions[tab] = nil }
        }
    }

    // MARK: Name Tabs

    /// The tab's page, when it has settled in some window: its address and the title it shows.
    private func settledPage(_ tab: ItemID) -> (url: URL, title: String)? {
        for (window, doc) in state.doc.windows where doc.kind == .standard {
            let page = PageID(window: window, item: tab)
            guard let live = state.session.live[page], !live.loading, case .ready = live.document,
                  let shown = state.displayedTab(tab, in: window), let url = shown.url,
                  ["http", "https"].contains(url.scheme?.lowercased()), url.host?.isEmpty == false else { continue }
            let title = (live.observedTitle ?? shown.title).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            return (url, title)
        }
        return nil
    }

    /// Where the tab is now: its address in the first window that shows it (a commit changes the window's slot, not
    /// the tree's first address).
    private func currentURL(_ tab: ItemID) -> URL? {
        for window in state.doc.windows.keys.sorted() where state.doc.windows[window]?.slots[tab] != nil || state.session.live[PageID(window: window, item: tab)] != nil {
            if let url = state.displayedTab(tab, in: window)?.url { return url }
        }
        return state.tab(tab)?.url
    }

    /// Named once after its page loads and again when it moves to another site; never a title the user set.
    private mutating func considerNaming(_ tab: ItemID) {
        guard let value = state.tab(tab), let scope = state.locate(tab) else { return }
        let kind = state.role(of: tab)?.kind
        guard kind == .today || kind == .pinned, value.customTitle == nil, !value.userNamed,
              case .profile = state.browsingContext(of: tab) else { return }
        // A name made for another site goes at once; the new site's comes after the pause.
        if let name = value.aiName, let host = currentURL(tab)?.host?.lowercased(), name.host != host {
            state.withTree(scope) { $0.updateTab(tab) { $0.aiName = nil } }
        }
        guard let page = settledPage(tab), let host = page.url.host?.lowercased() else { return }
        if state.tab(tab)?.aiName?.host == host { return }
        let key = tab.rawValue + "|" + page.url.absoluteString
        if let known = state.session.ai.basic.names[page.url] {
            state.withTree(scope) { $0.updateTab(tab) { $0.aiName = AITabName(title: known, host: host) } }
            return
        }
        guard !state.session.ai.basic.asked.contains(key), state.session.ai.basic.naming.values.allSatisfy({ $0[tab] == nil }) else { return }
        state.session.ai.basic.namingDue[tab] = ctx.now.advanced(by: AINaming.pause)
    }

    private mutating func armNamingTimer() {
        guard !state.session.ai.basic.timerArmed, let next = state.session.ai.basic.namingDue.values.min(),
              state.session.ai.basic.naming.count < AINaming.inFlight else { return }
        state.session.ai.basic.timerArmed = true
        let wait = max(next.since(ctx.now), .milliseconds(100))
        effects.append(.aiBasicTimer(milliseconds: Int(wait.components.seconds * 1000 + wait.components.attoseconds / 1_000_000_000_000_000)))
    }

    /// The pause is over: tabs still waiting and still nameable go out, a batch per request.
    mutating func aiBasicTick() {
        state.session.ai.basic.timerArmed = false
        guard state.doc.settings.max.enabled(.tabNames) else { state.session.ai.basic.namingDue = [:]; return }
        if let paused = state.session.ai.basic.pausedUntil, paused > ctx.now { armNamingTimer(); return }
        while state.session.ai.basic.naming.count < AINaming.inFlight {
            let due = state.session.ai.basic.namingDue.filter { $0.value <= ctx.now }.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.map(\.key)
            guard !due.isEmpty else { break }
            var batch: [AITab] = [], asked: [ItemID: URL] = [:]
            for tab in due {
                guard batch.count < AINaming.batch else { break }
                state.session.ai.basic.namingDue[tab] = nil
                guard let value = state.tab(tab), value.customTitle == nil, !value.userNamed,
                      let page = settledPage(tab) else { continue }
                batch.append(AITab(id: tab, title: page.title, url: page.url))
                asked[tab] = page.url
                state.session.ai.basic.asked.insert(tab.rawValue + "|" + page.url.absoluteString)
            }
            guard !batch.isEmpty else { continue }
            let window = state.doc.windows.keys.sorted().first { window in batch.contains { state.displayedTab($0.id, in: window) != nil } }
            let id = requestAI(.nameTabs(batch), from: window)
            state.session.ai.basic.naming[id] = asked
        }
        armNamingTimer()
    }

    mutating func applyTabNames(_ id: AIRequestID, _ names: [String: String]) {
        guard let asked = state.session.ai.basic.naming.removeValue(forKey: id) else { return }
        for (tab, url) in asked {
            guard let raw = names[tab.rawValue], let name = AIValidation.name(raw, limit: AINaming.maxLength),
                  let value = state.tab(tab), value.customTitle == nil, !value.userNamed, currentURL(tab) == url,
                  let host = url.host?.lowercased(), let scope = state.locate(tab) else { continue }
            state.session.ai.basic.names[url] = name
            state.withTree(scope) { $0.updateTab(tab) { $0.aiName = AITabName(title: name, host: host) } }
        }
        armNamingTimer()
        aiBasicTickIfDue()
    }

    private mutating func aiBasicTickIfDue() {
        if state.session.ai.basic.namingDue.values.contains(where: { $0 <= ctx.now }) { aiBasicTick() }
    }

    /// Name Tabs turned off: the names go and the tabs show their pages' titles again.
    private mutating func forgetTabNames() {
        state.session.ai.basic.namingDue = [:]
        state.session.ai.basic.names = [:]
        state.session.ai.basic.asked = []
        for tab in state.doc.tree.allTabs() where state.tab(tab)?.aiName != nil {
            guard let scope = state.locate(tab) else { continue }
            state.withTree(scope) { $0.updateTab(tab) { $0.aiName = nil } }
        }
    }

    /// A basic request failed: the person hears it once per reason, and background work waits before trying again.
    mutating func basicFailed(_ id: AIRequestID, _ task: AITask, _ reason: String, in window: WindowID?) {
        let feature: AIFeature?
        switch task {
        case .nameTabs:
            state.session.ai.basic.naming[id] = nil
            state.session.ai.basic.pausedUntil = ctx.now.advanced(by: AINaming.backoff)
            feature = .tabNames
        case .decide(_, let asked, _):
            state.session.ai.basic.placements[id] = nil
            feature = asked
        case .nameConversation:
            state.session.ai.conversationNaming[id] = nil
            state.session.ai.basic.pausedUntil = ctx.now.advanced(by: AINaming.backoff)
            feature = .tabNames
        case .nameFolder:
            // Asked for by a click: always said.
            state.session.ai.basic.folderNaming[id] = nil
            if let window, state.doc.windows[window] != nil { toast("\(AIFeature.folderNames.title): \(reason)", in: window) }
            return
        default: return
        }
        guard let feature, let window, state.doc.windows[window] != nil, state.session.ai.basic.told.insert(feature.rawValue + reason).inserted else { return }
        toast("\(feature.title): \(reason)", in: window)
    }

    // MARK: Folder names

    /// "Name with AI" on a folder or group: its tabs' titles and addresses go to the basic model; the name comes back
    /// with an undo toast.
    mutating func nameFolder(_ folder: ItemID, in window: WindowID) {
        guard state.doc.settings.max.enabled(.folderNames), state.doc.windows[window]?.kind != .incognito,
              case .folder? = state.doc.tree[folder]?.body else { return }
        let tabs = state.doc.tree.tabs(under: folder).prefix(30).compactMap { id -> AITab? in
            guard let tab = state.displayedTab(id, in: window), let url = tab.url else { return nil }
            return AITab(id: id, title: tab.displayTitle, url: url)
        }
        guard !tabs.isEmpty else { toast("This folder has no tabs to name it after.", in: window); return }
        let id = requestAI(.nameFolder(folder, tabs: tabs), from: window)
        state.session.ai.basic.folderNaming[id] = folder
    }

    mutating func applyFolderName(_ id: AIRequestID, _ raw: String, in window: WindowID?) {
        guard let folder = state.session.ai.basic.folderNaming.removeValue(forKey: id), let name = AIValidation.name(raw, limit: 60),
              case .folder(let value)? = state.doc.tree[folder]?.body else { return }
        let before = value.title
        state.doc.tree.updateFolder(folder) { $0.title = name }
        if let window, state.doc.windows[window] != nil {
            undoToast("Named “\(name)”! Use", undo: .folderName(folder, before), in: window)
        }
    }

    /// AI-made groups (Tidy) are named in their plan; a group whose name came back empty gets Tidy's word for it.
    static let unnamedGroup = "Tabs"

    // MARK: Place New Tabs

    /// A new tab's first page settled: one decision request, the groups of this space and the spaces of its profile.
    private mutating func considerPlacing(_ tab: ItemID, in window: WindowID) {
        guard let doc = state.doc.windows[window], let space = state.doc.spaces[doc.space],
              state.doc.tree[tab]?.parent == space.todayRoot else { state.session.ai.basic.placing[tab] = nil; return }
        guard let page = settledPage(tab) else { return }
        state.session.ai.basic.placing[tab] = nil
        var ask = AIPlacementAsk(tab: tab, window: window, space: doc.space, url: page.url)
        var questions: [String: DecisionQuestion] = [:]
        var options: [DecisionOption] = []
        var used = Set<String>()
        func unique(_ title: String) -> String {
            var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { name = "Untitled" }
            var candidate = name, n = 2
            while used.contains(candidate) || candidate == DecisionQuestion.noneName { candidate = "\(name) (\(n))"; n += 1 }
            used.insert(candidate)
            return candidate
        }
        func contents(_ folder: ItemID) -> String {
            state.doc.tree.tabs(under: folder).prefix(6).compactMap { state.displayedTab($0, in: window)?.displayTitle }.joined(separator: "; ")
        }
        var members: [String: [AITab]] = [:]
        for root in [space.todayRoot, space.pinnedRoot] {
            for id in state.doc.tree[root]?.children ?? [] where options.count < DecisionQuestion.maxChoices - 1 {
                guard case .folder(let folder)? = state.doc.tree[id]?.body else { continue }
                let name = unique(folder.title)
                ask.groups[name] = id
                members[name] = state.doc.tree.tabs(under: id).prefix(12).compactMap { member in
                    guard let shown = state.displayedTab(member, in: window), let url = shown.url else { return nil }
                    return AITab(id: member, title: shown.displayTitle, url: url)
                }
                let place = root == space.todayRoot ? "a group in Today" : "a pinned folder"
                options.append(DecisionOption(name, "\(place); tabs: \(contents(id))"))
            }
        }
        if !options.isEmpty {
            questions["group"] = .choice("Which group of the current Space does this new tab belong in?", options: options, none: "None of these groups fits the tab")
        }
        used = []
        let spaces = state.doc.spaceOrder.filter { state.doc.spaces[$0]?.profile == space.profile }
        if spaces.count > 1 {
            let spaceOptions = spaces.prefix(DecisionQuestion.maxChoices).map { sid -> DecisionOption in
                let name = unique(state.displayTitle(of: sid))
                ask.spaces[name] = sid
                let roots = [state.doc.spaces[sid]?.pinnedRoot, state.doc.spaces[sid]?.todayRoot].compactMap { $0 }
                let titles = roots.flatMap { state.doc.tree.tabs(under: $0) }.filter { $0 != tab }.prefix(8).compactMap { state.tab($0)?.displayTitle }
                return DecisionOption(name, "Space; tabs: \(titles.joined(separator: "; "))")
            }
            questions["space"] = .choice("Which Space does this new tab fit best?", options: Array(spaceOptions))
        }
        guard !questions.isEmpty else { return }
        let request = DecisionRequest(state: .object(["title": .string(page.title), "url": .string(page.url.absoluteString)]), questions: questions)
        guard request.problem == nil else { return }
        let hint: AIDecisionHint? = questions["group"] == nil ? nil : .placement(question: "group", subject: AITab(id: tab, title: page.title, url: page.url), members: members, profile: space.profile)
        let id = requestAI(.decide(request, feature: .tabPlacement, hint: hint), from: window)
        state.session.ai.basic.placements[id] = ask
    }

    mutating func applyDecision(_ id: AIRequestID, _ answers: DecisionAnswers) {
        if let pairs = state.session.ai.basic.duplicateAsks.removeValue(forKey: id) {
            // Only a suggestion follows, so a yes is enough, with or without a probability.
            for (key, pair) in pairs { if case .noul(true, _)? = answers[key] { state.session.ai.basic.nearDuplicates.insert(pair.a) } }
            return
        }
        guard let ask = state.session.ai.basic.placements.removeValue(forKey: id) else { return }
        // The tab must still be where it opened, on the page that was asked about.
        guard let space = state.doc.spaces[ask.space], state.doc.tree[ask.tab]?.parent == space.todayRoot,
              currentURL(ask.tab)?.host == ask.url.host, state.doc.windows[ask.window] != nil else { return }
        if case .choice(let name, _)? = answers["space"], let target = ask.spaces[name], target != ask.space,
           DecisionBand(answers["space"]?.probability) != .ignore {
            // Another space is only ever suggested.
            state.session.ai.basic.suggestions[ask.tab] = AISuggestion(target: .space(target), label: AISuggestionLabel(action: AICopy.moveTo, name: state.displayTitle(of: target)), at: ctx.now)
            return
        }
        guard case .choice(let name, _)? = answers["group"], let folder = ask.groups[name], case .folder(let value)? = state.doc.tree[folder]?.body else { return }
        let inToday = state.doc.tree[folder]?.parent == space.todayRoot
        switch DecisionBand(answers["group"]?.probability) {
        case .act where inToday:
            let index = state.doc.tree[space.todayRoot]?.children.firstIndex(of: ask.tab) ?? 0
            _ = moveItem(ask.tab, to: .into(parent: folder, index: Int.max))
            undoToast("Moved to “\(value.title)”! Use", undo: .placement(ask.tab, parent: space.todayRoot, index: index), in: ask.window)
        case .act, .suggest:
            // A pinned folder pins the tab: that is the person's call, however sure the answer is.
            state.session.ai.basic.suggestions[ask.tab] = AISuggestion(target: .folder(folder), label: AISuggestionLabel(action: AICopy.moveTo, name: value.title), at: ctx.now)
        case .ignore: break
        }
    }

    /// The suggestion's click: the move it offered, through the same command a drag makes.
    mutating func acceptSuggestion(_ tab: ItemID, in window: WindowID) {
        guard let suggestion = state.session.ai.basic.suggestions.removeValue(forKey: tab) else { return }
        switch suggestion.target {
        case .folder(let folder): items(.move(tab, to: .into(parent: folder, index: Int.max)), in: window)
        case .space(let space): items(.move(tab, to: .space(space)), in: window)
        }
    }

    // MARK: Usage

    /// A basic request's tokens and cost go into this month's table; a new month starts it again.
    mutating func recordUsage(_ key: AIUsageKey, _ count: AIUsageCount) {
        let month = AIUsageLedger.month(of: ctx.now)
        var ledger = state.doc.settings.max.usage ?? AIUsageLedger(month: month)
        if ledger.month != month { ledger = AIUsageLedger(month: month) }
        ledger.rows[key] = (ledger.rows[key] ?? AIUsageCount(requests: 0)) + count
        state.doc.settings.max.usage = ledger
    }

    // MARK: The cleanup list

    /// Slice B's candidates (embeddings at 0.92 or more): each pair the address rule did not already settle is one
    /// yes/no request (at most eight pairs per event), worded as slice B measured it (JevK5 Q4 28 of 30 with the rule
    /// first); `a` is the copy offered for closing, `b` the tab that stays.
    mutating func askDuplicates(_ pairs: [AIDuplicatePair]) {
        guard state.doc.settings.max.enabled(.tabCleanup), state.canAnswerYesNo else { return }
        var asked = 0
        for pair in pairs where pair.a != pair.b {
            // The titles the sidebar shows: a tab's own record holds none for most open pages, and JevK5 read two bare
            // addresses as a coin toss (0.47 and 0.52 on the real route, 0.89 with the titles).
            guard asked < 8, let a = state.tab(pair.a), let b = state.tab(pair.b), !state.session.ai.basic.nearDuplicates.contains(pair.a) else { continue }
            let shownA = state.shownPage(of: pair.a, a), shownB = state.shownPage(of: pair.b, b)
            guard let ua = shownA.url, let ub = shownB.url, AICleanup.addressKey(ua) != AICleanup.addressKey(ub) else { continue }
            let text = "Tab 1: \(shownA.title)\nAddress 1: \(ua.absoluteString)\nTab 2: \(shownB.title)\nAddress 2: \(ub.absoluteString)"
            let request = DecisionRequest(state: .string(text), questions: [AICleanup.sameQuestionKey: .noul(AICleanup.sameQuestion)])
            let id = requestAI(.decide(request, feature: .tabCleanup))
            state.session.ai.basic.duplicateAsks[id] = [AICleanup.sameQuestionKey: pair]
            asked += 1
        }
    }

    /// The list behind the cleanup button: each tab with its own Close or Archive, then all of a kind at once.
    /// Only suggestions; nothing closes until the person picks a row.
    func cleanupMenu(_ space: SpaceID, in window: WindowID) -> [MenuEntry] {
        guard state.doc.settings.max.enabled(.tabCleanup), state.doc.windows[window]?.space == space else { return [] }
        let found = cleanupCandidates(space)
        func title(_ id: ItemID) -> String { String((state.displayedTab(id, in: window)?.displayTitle ?? "Tab").prefix(60)) }
        var entries: [MenuEntry] = []
        if !found.duplicates.isEmpty {
            entries.append(.header(AICopy.cleanupDuplicates))
            entries += found.duplicates.map { .action(title: "Close “\(title($0))”", command: .tabTools(.bulk(.items([$0]), .archive)), enabled: true) }
        }
        if !found.stale.isEmpty {
            if !entries.isEmpty { entries.append(.separator) }
            entries.append(.header(AICopy.cleanupStale))
            entries += found.stale.map { .action(title: "Archive “\(title($0))”", command: .tabTools(.bulk(.items([$0]), .archive)), enabled: true) }
        }
        guard !entries.isEmpty else { return [] }
        entries.append(.separator)
        if found.duplicates.count > 1 { entries.append(.action(title: "Close All \(found.duplicates.count) Duplicates", command: .tabTools(.bulk(.items(found.duplicates), .archive)), enabled: true)) }
        if found.stale.count > 1 { entries.append(.action(title: "Archive All \(found.stale.count) Unvisited", command: .tabTools(.bulk(.items(found.stale), .archive)), enabled: true)) }
        if entries.last == .separator { entries.removeLast() }
        return entries
    }

    /// Today tabs that repeat another tab of the space, and Today tabs not shown for a long time.
    func cleanupCandidates(_ space: SpaceID) -> (duplicates: [ItemID], stale: [ItemID]) {
        guard let value = state.doc.spaces[space] else { return ([], []) }
        return AICleanup.candidates(tree: state.doc.tree, space: value, now: ctx.now, threshold: state.doc.settings.profiles[value.profile]?.autoArchive ?? .default,
                                    near: state.session.ai.basic.nearDuplicates)
    }
}

/// Which Today tabs the cleanup list offers. A duplicate is a Today tab whose address another tab of the space has
/// (the pinned one, or the most recently shown copy, stays). Stale is not shown for half the space's archive time,
/// at least two hours and at most three days.
public enum AICleanup {
    public static let sameQuestionKey = "same_page"
    /// Slice B's wording (bench/run.py `duplicates`).
    public static let sameQuestion = "Are these two browser tabs the same web page (the same document or item, perhaps with a different address form), rather than two different pages on the same site or topic?"
    static func candidates(tree: SidebarTree, space: Space, now: Instant, threshold: AutoArchiveThreshold, near: Set<ItemID> = []) -> (duplicates: [ItemID], stale: [ItemID]) {
        func tab(_ id: ItemID) -> Tab? { if case .tab(let value)? = tree[id]?.body { value } else { nil } }
        func key(_ url: URL?) -> String? { url.flatMap(addressKey) }
        // Today's tabs, groups included; a copy in Pinned is the one that stays.
        let today = tree.tabs(under: space.todayRoot)
        let pinned = Set(tree.tabs(under: space.pinnedRoot).compactMap { tab($0).flatMap { key($0.url) } })
        var keep: [String: ItemID] = [:]
        for id in today.sorted(by: { (tab($0)?.lastActiveAt ?? Instant(milliseconds: 0)) > (tab($1)?.lastActiveAt ?? Instant(milliseconds: 0)) }) {
            guard let k = key(tab(id)?.url), !pinned.contains(k), keep[k] == nil else { continue }
            keep[k] = id
        }
        let duplicates = today.filter { id in
            if near.contains(id) { return true }
            guard let k = key(tab(id)?.url) else { return false }
            return pinned.contains(k) || keep[k] != id
        }
        let window: Duration = min(max((threshold.interval ?? .seconds(259_200)) / 2, .seconds(7_200)), .seconds(259_200))
        let stale = today.filter { id in
            !duplicates.contains(id) && (tab(id).map { now.since($0.lastActiveAt) >= window } ?? false)
        }
        return (duplicates, stale)
    }

    /// Slice B's address rule (a75547183a:verify/ai-native/b-local-models/bench/dup_rule.py; 26 of 30 pairs alone, no false
    /// duplicate): two addresses are the same page when they match without the fragment, tracking parameters, a
    /// leading www. or m., and a trailing index.html. Nil for anything but http(s).
    public static func addressKey(_ url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), ["http", "https"].contains(parts.scheme?.lowercased()),
              var host = parts.host?.lowercased(), !host.isEmpty else { return nil }
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) { host.removeFirst(prefix.count); break }
        host = host.replacingOccurrences(of: ".m.wikipedia.org", with: ".wikipedia.org")
        var path = parts.path
        for suffix in ["/index.html", "/index.htm", "/"] where path.hasSuffix(suffix) { path.removeLast(suffix.count); break }
        if path.isEmpty { path = "/" }
        let query = (parts.queryItems ?? []).filter { !isTracking($0.name) }.map { $0.name + "=" + ($0.value ?? "") }.joined(separator: "&")
        return host + (parts.port.map { ":\($0)" } ?? "") + path + "?" + query
    }

    static func isTracking(_ name: String) -> Bool {
        name.hasPrefix("utm_") || ["from", "spm", "share_source", "share_medium", "isLoggingIn", "ref", "fbclid", "gclid"].contains(name)
    }
}

extension AIUsageLedger {
    /// "2026-11" in UTC.
    public static func month(of instant: Instant) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: Double(instant.milliseconds) / 1000))
        return String(format: "%04d-%02d", parts.year ?? 1970, parts.month ?? 1)
    }
}

extension AIValidation {
    /// A name from the basic model: one line, no quotes or trailing full stop, at most `limit` characters.
    public static func name(_ text: String, limit: Int) -> String? {
        var line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        line = line.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`"))
        while line.hasSuffix(".") || line.hasSuffix("。") { line.removeLast() }
        line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.contains(where: { $0.isASCII && $0.asciiValue! < 32 }) else { return nil }
        return String(line.prefix(limit))
    }
}
