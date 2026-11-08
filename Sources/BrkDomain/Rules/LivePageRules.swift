import BrkBase
import Foundation

// Live AI pages (BrkDomain/LivePages.swift, docs/design/ai-live-pages.md). The reducer owns the schedule: on every
// clock tick it starts the refreshes that are due, once each, and a refresh takes the latest slot, so a page whose slots
// passed while Brk was closed refreshes once at the next launch. The app runs the refresh in a session that can only
// read and write this page's data; whatever comes back is checked again here against the page's shape.

extension Work {
    // MARK: The page's own saves

    /// `window.brk.save` from a page in a window: JSON text that fits the page's save shape, within the size and rate
    /// caps. Anything else changes nothing.
    mutating func pageSave(_ id: AIPageID, _ text: String, in window: WindowID) {
        guard var record = state.doc.aiPages[id], record.profile == state.agentProfile(in: window) else { return }
        let minute = ctx.now.milliseconds / 60_000
        var count = state.session.ai.pageSaves[id] ?? AIPageSaveCount(minute: minute, saves: 0)
        if count.minute != minute { count = AIPageSaveCount(minute: minute, saves: 0) }
        guard count.saves < AIPageLimits.savesPerMinute else { return }
        count.saves += 1
        state.session.ai.pageSaves[id] = count
        guard case .success(let normalized) = AIPageShape.check(text, schema: record.saveShape, limit: AIPageLimits.saved), normalized != record.saved else { return }
        record.saved = normalized
        state.doc.aiPages[id] = record
    }

    // MARK: Schedule, weekdays, model

    /// A change from the page row's menu. Only a kept page of the window's profile.
    mutating func livePage(_ id: AIPageID, _ change: AIPageLiveChange, in window: WindowID) {
        guard let record = state.doc.aiPages[id], record.profile == state.agentProfile(in: window) else { return }
        if case .refreshNow = change {
            _ = startRefresh(id, manual: true)
            return
        }
        _ = applyLive(change, to: id)
    }

    /// Why `change` cannot apply to page `id`, nil when it did.
    @discardableResult
    mutating func applyLive(_ change: AIPageLiveChange, to id: AIPageID) -> String? {
        guard var record = state.doc.aiPages[id] else { return "No such page." }
        var live = record.liveState
        switch change {
        case .schedule(let schedule):
            if let schedule {
                guard schedule.isValid else { return "That schedule is not valid." }
                guard record.dataShape != nil else { return "This page has no data to refresh. Render it with `data` (and a `dataSchema`) first." }
                // The first refresh is at the next slot after now.
                if live.schedule != schedule { live.lastRun = ctx.now }
            }
            live.schedule = schedule
        case .weekdays(let days): live.weekdays = AIPageWeekdays.normalized(days)
        case .model(let model): live.model = model
        case .refreshNow: return startRefresh(id, manual: true) ? nil : "The page could not refresh now."
        }
        record.live = live
        state.doc.aiPages[id] = record
        return nil
    }

    /// A kept page shows in a sidebar row (not the archive): only those refresh.
    func pageIsKept(_ id: AIPageID) -> Bool {
        state.doc.tree.allTabs().contains { AIPageTab.id(of: state.tab($0)?.url) == id }
    }

    /// Every page whose slot has passed starts its refresh. Runs on the clock tick, when the agents say they are ready,
    /// and when the saved pages are loaded at launch.
    mutating func checkLivePages() {
        guard state.doc.settings.max.isOn else { return }
        for (id, record) in state.doc.aiPages.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let schedule = record.live?.schedule, state.session.ai.refreshing[id] == nil,
                  schedule.isDue(lastRun: record.live?.lastRun ?? record.createdAt, now: ctx.now, calendar: ctx.calendar) else { continue }
            _ = startRefresh(id, manual: false)
        }
    }

    /// Starts page `id`'s refresh. Not yet possible (no ready agent, no window of its profile): a scheduled one waits for
    /// the next check without using its slot; Refresh Now says why on the row.
    mutating func startRefresh(_ id: AIPageID, manual: Bool) -> Bool {
        guard var record = state.doc.aiPages[id], state.session.ai.refreshing[id] == nil else { return false }
        func notNow(_ why: String) -> Bool {
            if manual {
                var live = record.liveState
                live.outcome = AIPageRefreshOutcome(kind: .failed, at: ctx.now, detail: why)
                record.live = live
                state.doc.aiPages[id] = record
            }
            return false
        }
        guard pageIsKept(id) else { return false }
        guard state.doc.settings.max.isOn else { return notNow("Max is off. Turn it on in Settings → Max.") }
        guard let conversation = state.doc.conversations[record.conversation], let agent = conversation.agent else {
            return notNow("The conversation that made this page is gone.")
        }
        guard state.session.ai.agents[agent]?.state == .ready else { return notNow("\(agent.displayName) is not ready.") }
        guard let shape = record.dataShape, let schema = AIPageShape.text(shape) else { return notNow("This page has no data to refresh.") }
        guard let window = state.doc.windows.keys.sorted().first(where: {
            state.doc.windows[$0]?.kind == .standard && state.libraryContext(in: $0) == .profile(record.profile)
        }) else { return notNow("Open a window of this page's profile first.") }
        var live = record.liveState
        let options: AIAgentOptions? = live.refreshModel == .basic ? state.doc.settings.max.basic(agent) : AIAgentOptions(model: conversation.model, effort: conversation.effort)
        let run = AIRequestID(ctx.newID())
        state.session.ai.refreshing[id] = run
        state.session.ai.refreshChanged.remove(id)
        live.lastRun = ctx.now
        record.live = live
        state.doc.aiPages[id] = record
        effects.append(.aiRefreshPage(AIPageRefreshRun(run: run, page: id, conversation: conversation.id, profile: record.profile, window: window, agent: agent,
                                                       model: options?.model, effort: options?.effort, title: record.title, data: record.data, saved: record.saved,
                                                       schema: schema, sources: record.sources ?? [], history: conversation.history(limit: 8_000))))
        return true
    }

    // MARK: What a refresh reports

    mutating func aiPageRefresh(_ id: AIPageID, run: AIRequestID, _ event: AIPageRefreshEvent) {
        guard state.session.ai.refreshing[id] == run, var record = state.doc.aiPages[id] else { return }
        switch event {
        case .data(let text):
            guard let shape = record.dataShape, case .success(let normalized) = AIPageShape.check(text, schema: shape, limit: AIPageLimits.data) else { return }
            guard normalized != record.data.flatMap(AIPageShape.normalized) else { return }
            record.data = normalized
            record.revision = (record.revision ?? 0) + 1
            var live = record.liveState
            live.changedAt = ctx.now
            record.live = live
            state.doc.aiPages[id] = record
            state.session.ai.refreshChanged.insert(id)
        case .finished(let kind, let detail):
            state.session.ai.refreshing[id] = nil
            let changed = state.session.ai.refreshChanged.remove(id) != nil
            let outcome: AIPageRefreshOutcome.Kind = kind == .flagged ? .flagged : changed ? .updated : kind == .updated ? .unchanged : kind
            var live = record.liveState
            live.outcome = AIPageRefreshOutcome(kind: outcome, at: ctx.now, detail: detail.map { String($0.prefix(300)) })
            record.live = live
            state.doc.aiPages[id] = record
            // The conversation hears of refreshes that changed something or were stopped; an unchanged one says nothing.
            let words: String? = switch outcome {
            case .updated: "Refreshed “\(record.title)”: new data."
            case .flagged: "Stopped the refresh of “\(record.title)”: \(detail ?? "Brk flagged what it read"). Nothing changed."
            case .failed: "The refresh of “\(record.title)” failed: \(detail ?? "the agent did not finish"). Nothing changed."
            case .unchanged: nil
            }
            if let words { noteInConversation(record.conversation, words) }
        }
    }

    /// A notice at the end of a conversation's transcript, live or saved.
    private mutating func noteInConversation(_ id: AIRequestID, _ text: String) {
        if let host = state.session.ai.host(ofConversation: id), var answer = state.session.ai[host: host], var conversation = answer.conversation {
            conversation.items.append(.notice(text))
            answer.conversation = conversation
            state.session.ai[host: host] = answer
            commitConversation(id)
        } else if var stored = state.doc.conversations[id] {
            stored.items.append(.notice(text))
            stored.updatedAt = ctx.now
            state.doc.conversations[id] = stored
        }
    }

    /// `brk_page_update` in the conversation that made the page, while the user talks to it.
    mutating func aiPageUpdated(_ conversation: AIRequestID, _ id: AIPageID, html: Bool, data: String?, schema: String?, saveSchema: String?, title: String?, height: Int?) {
        guard var record = state.doc.aiPages[id], record.conversation == conversation else { return }
        if let saveSchema {
            guard let shape = AIPageShape.object(saveSchema), AIPageShape.shapeProblem(shape) == nil else { return }
            record.saveSchema = AIPageShape.text(shape)
        }
        if let schema {
            guard let shape = AIPageShape.object(schema), AIPageShape.shapeProblem(shape) == nil else { return }
            record.schema = AIPageShape.text(shape)
        }
        if let data {
            guard let normalized = AIPageShape.normalized(data), normalized.utf8.count <= AIPageLimits.data else { return }
            if let declared = AIPageShape.object(record.schema), AIPageShape.problem(AIPageShape.object(normalized)!, declared) != nil { return }
            record.data = normalized
        }
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { record.title = String(title.prefix(AIPageLimits.titleMax)) }
        if let height { record.height = AIPageLimits.height(height) }
        if html || data != nil { record.revision = (record.revision ?? 0) + 1 }
        state.doc.aiPages[id] = record
        for row in state.doc.tree.allTabs() where AIPageTab.id(of: state.tab(row)?.url) == id {
            state.doc.tree.updateTab(row) { if $0.title != record.title { $0.title = record.title } }
        }
        commitConversation(conversation)
    }

    // MARK: After every input

    /// A page whose card is on screen has been seen; a refresh whose page is gone stops.
    mutating func reconcileLivePages() {
        for window in state.doc.windows.keys {
            for (_, url) in state.shownNativePages(in: window) {
                guard let id = AIPageTab.id(of: url), var record = state.doc.aiPages[id], let live = record.live, live.unseenChange || live.unseenProblem else { continue }
                record.live?.seenAt = ctx.now
                state.doc.aiPages[id] = record
            }
        }
        for (id, run) in state.session.ai.refreshing where state.doc.aiPages[id] == nil {
            state.session.ai.refreshing[id] = nil
            state.session.ai.refreshChanged.remove(id)
            effects.append(.aiStopRefresh(run))
        }
        for id in state.session.ai.pageSaves.keys where state.doc.aiPages[id] == nil { state.session.ai.pageSaves[id] = nil }
    }

    // MARK: Delete for good

    /// The archive's Delete: a conversation with its transcript and every page it made, or one kept page. Their rows go
    /// from the archive and the sidebar without being archived again; their files go with the next write.
    mutating func deleteForGood(_ archive: ArchiveID, in window: WindowID) {
        guard let entry = state.doc.archive.first(where: { $0.id == archive }) else { return }
        let title: String
        var urls: Set<URL> = []
        if let conversation = ConversationPage.id(of: entry.tab.url) {
            let pages = state.doc.aiPages.values.filter { $0.conversation == conversation }.map(\.id)
            title = state.doc.conversations[conversation]?.title ?? entry.tab.displayTitle
            urls = Set([ConversationPage.url(conversation)] + pages.map(AIPageTab.url))
            state.doc.conversations[conversation] = nil
            for page in pages { state.doc.aiPages[page] = nil }
            for (host, answer) in state.session.ai.answers where answer.conversation?.id == conversation {
                state.session.ai.answers[host] = nil
                state.session.ai.answerContexts[host] = nil
            }
            state.session.ai.tabAnswers[conversation] = nil
            state.session.ai.tabWindows[conversation] = nil
        } else if let page = AIPageTab.id(of: entry.tab.url) {
            title = state.doc.aiPages[page]?.title ?? entry.tab.displayTitle
            urls = [AIPageTab.url(page)]
            state.doc.aiPages[page] = nil
        } else { return }
        state.doc.archive.removeAll { record in
            guard let url = record.tab.url, urls.contains(url) else { return false }
            if case .folder? = record.structure { return false }
            if case .split? = record.structure { return false }
            return true
        }
        for row in state.doc.tree.allTabs() where state.tab(row)?.url.map(urls.contains) == true {
            _ = removeItem(row)
            unload(row)
            replaceShown(row)
        }
        toast(ToastCopy.deletedForGood(title), in: window)
    }
}

extension AppState {
    /// The trailing mark and tooltip of a kept page's row.
    func livePageRow(_ url: URL?, now: Instant) -> (mark: LivePageMark?, status: String?, refreshing: Bool)? {
        guard let id = AIPageTab.id(of: url), let record = doc.aiPages[id] else { return nil }
        let refreshing = session.ai.refreshing[id] != nil
        let live = record.liveState
        var parts: [String] = []
        if let schedule = live.schedule { parts.append("Refreshes " + schedule.phrase) }
        if let outcome = live.outcome {
            switch outcome.kind {
            case .updated: parts.append("last refresh brought new data")
            case .unchanged: parts.append("last refresh found nothing new")
            case .failed: parts.append("last refresh failed: " + (outcome.detail ?? "unknown"))
            case .flagged: parts.append("last refresh stopped: " + (outcome.detail ?? "Brk flagged what it read"))
            }
        }
        if refreshing { parts.insert("Refreshing…", at: 0) }
        let mark: LivePageMark? = live.unseenProblem ? .attention : live.unseenChange ? .changed : nil
        return (mark, parts.isEmpty ? nil : parts.joined(separator: " · "), refreshing)
    }

    /// Whether a kept page's row stays out of Today now: it shows on other weekdays only.
    func livePageHiddenToday(_ url: URL?, now: Instant, calendar: Calendar) -> Bool {
        guard let id = AIPageTab.id(of: url), let days = doc.aiPages[id]?.live?.weekdays, !days.isEmpty else { return false }
        let today = calendar.component(.weekday, from: Date(timeIntervalSince1970: Double(now.milliseconds) / 1000))
        return !days.contains(today)
    }

    /// The live page items of a kept page row's menu: Brk's own, after Arc's.
    func livePageMenu(_ url: URL?) -> [MenuEntry] {
        guard let id = AIPageTab.id(of: url), let record = doc.aiPages[id] else { return [] }
        let live = record.liveState
        let canRefresh = record.dataShape != nil
        var schedules: [MenuEntry] = [.choice(title: "Never", command: .assist(.livePage(id, .schedule(nil))), on: live.schedule == nil)]
        var presets = AIPageSchedule.presets
        if let current = live.schedule, !presets.contains(current) { presets.append(current) }
        schedules += presets.map { .choice(title: $0.title, command: .assist(.livePage(id, .schedule($0))), on: live.schedule == $0) }
        let agent = doc.conversations[record.conversation]?.agent
        let small = agent.flatMap { doc.settings.max.basic($0)?.model }.map(AIModelNames.display) ?? "Small Model"
        let own = doc.conversations[record.conversation]?.model.map(AIModelNames.display) ?? "Conversation's Model"
        let days: [MenuEntry] = [
            .choice(title: "Every Day", command: .assist(.livePage(id, .weekdays(nil))), on: live.weekdays == nil),
            .choice(title: "Weekdays", command: .assist(.livePage(id, .weekdays(AIPageWeekdays.weekdays))), on: live.weekdays == AIPageWeekdays.weekdays),
            .choice(title: "Weekends", command: .assist(.livePage(id, .weekdays(AIPageWeekdays.weekend))), on: live.weekdays.map { Set($0) == Set(AIPageWeekdays.weekend) } ?? false),
            .separator,
        ] + AIPageWeekdays.order.map { day in
            var next = Set(live.weekdays ?? AIPageWeekdays.order)
            if next.contains(day) { next.remove(day) } else { next.insert(day) }
            return .choice(title: AIPageWeekdays.name(day), command: .assist(.livePage(id, .weekdays(next.isEmpty ? nil : Array(next)))),
                           on: live.weekdays?.contains(day) ?? true)
        }
        return [
            .submenu(title: "Refresh", entries: canRefresh ? schedules : []),
            .action(title: "Refresh Now", command: .assist(.livePage(id, .refreshNow)), enabled: canRefresh && session.ai.refreshing[id] == nil),
            .submenu(title: "Refresh With", entries: canRefresh ? [
                .choice(title: small, command: .assist(.livePage(id, .model(.basic))), on: live.refreshModel == .basic),
                .choice(title: own, command: .assist(.livePage(id, .model(.conversation))), on: live.refreshModel == .conversation),
            ] : []),
            .submenu(title: "Show in Today", entries: days),
        ]
    }
}

/// Model ids as a menu names them: "claude-haiku-5-5" is "Haiku 5.5", "gpt-6-luna" is "GPT-6 Luna".
public enum AIModelNames {
    public static func display(_ id: String) -> String {
        let parts = id.split(separator: "-").map(String.init)
        if parts.first == "claude", parts.count >= 2 {
            let version = parts.dropFirst(2).joined(separator: ".")
            return parts[1].prefix(1).uppercased() + parts[1].dropFirst() + (version.isEmpty ? "" : " " + version)
        }
        if parts.first == "gpt", parts.count >= 2 {
            return "GPT-" + parts[1] + parts.dropFirst(2).map { " " + $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        }
        return id
    }
}
