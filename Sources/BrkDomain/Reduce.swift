import BrkBase
import Foundation

/// What the reducer may read from outside: the injected clock's time and a source of fresh ids. Nothing else.
public struct Context: Sendable {
    public let now: Instant
    public let newID: @Sendable () -> String

    public init(now: Instant, newID: @escaping @Sendable () -> String) {
        self.now = now
        self.newID = newID
    }
}

public struct Transition: Sendable {
    public let state: AppState
    /// May be non-empty while `changed` is false: back, reload, copying a URL and quitting change nothing in state.
    /// The store runs effects whether or not state changed.
    public let effects: [Effect]
    /// The saved part changed: schedule a write.
    public let docChanged: Bool
    /// Anything changed (rev was bumped): re-project and render. False means `state` is the input value.
    public let changed: Bool
    /// For `Input.key`: the key was an app shortcut and was consumed. CEF's key handler returns this.
    public let keyShortcut: Bool
    public let keyHandled: Bool
    /// For `Input.key`: the table action the key dispatched.
    public var keyAction: ActionID? = nil
    /// This transition must reach the local atomic checkpoint before publication. Failure leaves its state unapplied.
    public var checkpointFailure: SystemEvent? = nil
}

/// The only writer of application state. Pure: same inputs, same output; no clock reads, no I/O, no traps for any
/// `Input` value (unknown ids are no-ops, numbers are clamped).
///
/// Order inside one transition:
/// 1. `.user` and `.key`: if a Ctrl+Tab cycle is pending and the command is not `cycleRecent`, commit it first
///    (robust against a lost Control key-up); apply the overlay rule (`Command.keepsCommandBar`/`keepsArchive`).
///    `.system(.clockTick)` first commits the pending cycle of every window whose Control key is not held (its
///    release went missing); a window still holding Control keeps its switcher open.
/// 2. Run the area's rules (Rules/*.swift), which change state and append effects.
/// 3. `normalize` (every cross-entity invariant; repairs only, never fills an absent active item).
/// 4. Stamp `lastActiveAt = now` on every tab that entered or left the screen (any window) during this input. This
///    is the one place it is stamped, so a focus, a space switch, a dock drop, a close or a Ctrl+Tab commit cannot
///    disagree. While the dispatching window is mid Ctrl+Tab walk nothing is stamped; the commit stamps the net
///    change against the screen as it was when the walk began (`RecentCycle.baseline`).
/// 5. If the result differs from the input, bump `session.rev`.
///
/// Fast path: a key that routing passes to the page (or ignores) without changing its memory returns the input
/// state untouched, with no normalize and no comparison (typing in a page costs one lookup per key-down).
public func reduce(_ state: AppState, _ input: Input, _ ctx: Context) -> Transition {
    var work = Work(state: state, ctx: ctx)
    switch input {
    case .user(let window, let command):
        guard state.doc.windows[window] != nil else { return .unchanged(state) }
        work.run(command, in: window)
    case .key(let window, let key):
        guard work.routeKey(key, in: window) else { return .unchanged(state) }
    case .system(let event):
        work.observe(event)
    }
    var transition = work.finish(from: state)
    if case .system(.sidebarData(.imported)) = input {
        transition.checkpointFailure = .sidebarData(.failed(epoch: nil, "Import could not be saved. No bookmarks or history were changed; the source file was kept."))
    }
    return transition
}

extension Transition {
    /// The input state returned as is: nothing to render, write or run.
    static func unchanged(_ state: AppState) -> Transition {
        Transition(state: state, effects: [], docChanged: false, changed: false, keyShortcut: false, keyHandled: false)
    }
}

/// One transition in progress. Rules are `extension Work` methods grouped by the knowledge they own, one file per
/// area under Rules/ (`routeKey` is Rules/Keys.swift). They mutate `state`, append to `effects`, and never read the
/// clock except through `ctx`.
struct Work {
    var state: AppState
    let ctx: Context
    var effects: [Effect] = []
    var keyShortcut = false
    var keyHandled = false
    var keyAction: ActionID?
    /// Tabs on screen right before the first rule of this input ran (after the cycle commit and the overlay rule).
    /// Nil until a command or event starts; `finish` stamps the difference.
    private var screenBefore: Set<ItemID>?
    /// The dispatching window, whose pending Ctrl+Tab walk suppresses stamping.
    private var dispatchingWindow: WindowID?
    /// The overlay the overlay rule closed for this command (Esc's "Exit" needs to know it already acted).
    private(set) var closedOverlay = false

    init(state: AppState, ctx: Context) {
        self.state = state
        self.ctx = ctx
    }

    /// Dispatches a command to its area. The exhaustive switch is the handler table: a new `Command` area
    /// without rules does not compile.
    mutating func run(_ command: Command, in window: WindowID) {
        guard state.doc.windows[window] != nil else { return }
        if command == .app(.exit), state.session.windows[window]?.recentCycle != nil {
            begin(window: window)
            tabTools(.cancelRecent, in: window)
            return
        }
        // A space dialog opened from the Library (its Spaces card's Edit Space…: the theme panel) sits above it, so
        // Esc closes the dialog and the Library stays.
        if command == .app(.exit), case .library? = state.session.windows[window]?.overlay, state.session.windows[window]?.dialog != nil {
            begin(window: window)
            state.session.windows[window]!.dialog = nil
            return
        }
        if command == .app(.exit), state.session.windows[window]?.capture != nil { captures(.cancel, in: window); return }
        if command == .app(.exit), state.session.windows[window]?.find != nil { closeFind(in: window); return }
        if case .settings(.openPane) = command { closeFind(in: window) }
        if case .tabTools(let intent) = command {
            switch intent {
            case .reveal, .sidebarStep, .chooseIcon: closeFind(in: window)
            default: break
            }
        }
        if case .find = command { state.session.windows[window]?.sidebarFocused = false }
        commitPendingCycle(unless: command, in: window)
        applyOverlayRule(for: command, in: window)
        begin(window: window)
        switch command {
        case .capture(let command): captures(command, in: window)
        case .find(let intent): find(intent, in: window)
        case .sidebarData(let command): sidebarData(command, in: window)
        case .commandBar(let c): commandBar(c, in: window)
        case .archive(let c): archive(c, in: window)
        case .tab(let c):
            state.session.windows[window]?.sidebarFocused = false
            tabs(c, in: window)
        case .tabTools(let c): tabTools(c, in: window)
        case .page(let c): pages(c, in: window)
        case .item(let c): items(c, in: window)
        case .space(let c): spaces(c, in: window)
        case .split(let c): splits(c, in: window)
        case .sidebar(let c): sidebar(c, in: window)
        case .app(let c): app(c, in: window)
        case .settings(let c): settings(c, in: window)
        case .library(let c): library(c, in: window)
        case .boost(let c): boosts(c, in: window)
        case .easel(let c): easels(c, in: window)
        case .window(let c): windows(c, in: window)
        case .peek(let c): peek(c, in: window)
        case .site(let c): sites(c, in: window)
        case .profile(let c): profiles(c, in: window)
        case .assist(let intent): assist(intent, in: window)
        case .later(.aiCommandBar): assist(.open(.question), in: window)
        case .later: break   // a greyed-out row of a later wave: nothing happens yet
        }
    }

    mutating func observe(_ event: SystemEvent) {
        if case .clockTick = event {
            for window in state.doc.windows.keys.sorted() where state.session.windows[window]?.heldModifiers.contains(.control) != true {
                commitCycle(in: window)
            }
        }
        switch event {
        case .exportFinished(let window, _), .window(let window, _), .suggestions(let window, _, _), .localResults(let window, _), .barTranslationDue(let window, _), .definition(let window, _), .spaceExportFinished(let window, _, _): begin(window: window)
        case .easel(let event):
            switch event {
            case .imageImported(let window, _, _, _, _, _), .shared(let window, _, _), .failed(let window, _, _): begin(window: window)
            }
        case .boost, .currencyRates, .profileDataCleared, .capture, .extensionOperationFailed, .websiteRulesLoaded, .globalShortcut, .filterListFetched, .extensionsRead, .siteDataCleared, .output, .sidebarData, .find, .siteResult, .download, .contextDisposed, .page, .clockTick, .externalURL, .aiProvidersDetected, .aiResult, .aiPartial, .aiPageRead, .aiDeadline, .aiHoverReady, .aiTranslated, .aiDownloadRenamed, .aiConversation, .aiAgents, .aiAgentsWanted, .aiFolderChosen, .aiKeys, .aiUsage, .aiBasicTick, .aiDuplicateCandidates, .localModels: begin(window: nil)
        }
        switch event {
        case .find(let update): findUpdated(update)
        case .sidebarData(let event): sidebarDataEvent(event)
        case .page(let page, let e): pageEvent(e, for: page)
        case .siteResult(let id, let outcome): siteResult(id, outcome)
        case .capture(let event): captureEvent(event)
        case .easel(let event): easelEvent(event)
        case .exportFinished(let window, let outcome):
            state.session.windows[window]?.exportOutcome = outcome
            state.session.sidebarDataStatus = outcome.message
        case .output(let update):
            state.session.windows[update.document.browser.page.window]?.exportOutcome = nil
            let window = update.document.browser.page.window
            if state.session.windows[window]?.outputUpdates[update.id] == nil { state.session.windows[window]?.outputOrder.append(update.id) }
            if case .terminal? = state.session.windows[window]?.outputUpdates[update.id]?.stage { break }
            state.session.windows[window]?.outputUpdates[update.id] = update
        case .download(let update): downloadEvent(update)
        case .websiteRulesLoaded(let context, let update): websiteRulesLoaded(context, update)
        case .filterListFetched(let context, let id, let result): filterListFetched(context, id, result)
        case .boost(let event): boostEvent(event)
        case .extensionOperationFailed(let context, let error): extensionOperationFailed(context, error)
        case .extensionsRead(let catalog): extensionsRead(catalog)
        case .siteDataCleared(let result): siteDataCleared(result)
        case .profileDataCleared(let result): profileDataCleared(result)
        case .contextDisposed(let result):
            switch result {
            case .completed(let id, .profile(let profile), _):
                if state.doc.deletingProfiles[profile]?.id == id { state.doc.deletingProfiles[profile] = nil }
            case .failed(let id, .profile(let profile), let reason):
                if state.doc.deletingProfiles[profile]?.id == id { state.doc.deletingProfiles[profile]?.failure = reason }
            default: break
            }
        case .spaceExportFinished(let window, let token, let outcome): spaceExportFinished(window, token: token, outcome: outcome)
        case .clockTick:
            sweepAutoArchive()
            for window in state.session.windows.keys where state.session.windows[window]?.barClock != nil { state.session.windows[window]?.barClock = ctx.now }
            for window in state.session.windows.keys {
                if let toast = state.session.windows[window]?.toast, toast.expiresAt <= ctx.now {
                    state.session.windows[window]?.toast = nil
                    if state.session.windows[window]?.copiedCapture?.action == nil { state.session.windows[window]?.copiedCapture = nil }
                    state.session.windows[window]?.toastUndo = nil
                }
            }
            requestSidebarSync()
            scheduleFilterListUpdates()
        case .window(let window, let e): windowEvent(e, in: window)
        case .externalURL(let url): externalURL(url)
        case .suggestions(let window, let query, let results): suggestions(window, query: query, results)
        case .localResults(let window, let results): localResults(window, results)
        case .barTranslationDue(let window, let text): barTranslationDue(window, text)
        case .definition(let window, let definition):
            if case .commandBar(_, .newTab)? = state.session.windows[window]?.overlay { state.session.windows[window]?.barDefinition = definition }
        case .currencyRates(let rates): state.session.currencyRates = rates
        case .aiProvidersDetected(let kinds): aiProvidersDetected(kinds)
        case .globalShortcut(let status): if state.session.globalShortcut != status { state.session.globalShortcut = status }
        case .aiResult(let id, let outcome): aiResult(id, outcome)
        case .aiPartial(let id, let text): aiPartial(id, text)
        case .aiPageRead(let id, let page, let content): aiReadResult(id, page: page, content: content)
        case .aiDeadline(let id): aiDeadline(id)
        case .aiHoverReady(let window, let url, let link): aiHoverReady(window, url: url, link: link)
        case .aiTranslated(let id, let success): aiTranslated(id, success: success)
        case .aiDownloadRenamed(let id, let original, let new, let error): aiDownloadRenamed(id, original: original, new: new, error: error)
        case .aiConversation(let id, let event): aiConversation(id, event)
        case .aiAgents(let statuses): aiAgents(statuses)
        case .localModels(let snapshot): state.session.localModels = snapshot
        case .aiAgentsWanted:
            let max = state.doc.settings.max
            if max.provider != .off, max.tidyTabs || max.renamePinnedTabs || AIFeature.allCases.contains(where: max.enabled) { effects.append(.aiRefreshAgents) }
        case .aiFolderChosen(let window, let folder): aiFolderChosen(folder, in: window)
        case .aiKeys(let keys, let local):
            state.session.ai.keys = keys
            state.session.ai.localDecisions = local
        case .aiUsage(let key, let count): recordUsage(key, count)
        case .aiBasicTick: aiBasicTick()
        case .aiDuplicateCandidates(let pairs): askDuplicates(pairs)
        }
    }

    /// Remembers the screen before the rules run. Only the first call of a transition counts.
    private mutating func begin(window: WindowID?) {
        guard screenBefore == nil else { return }
        screenBefore = state.onScreenTabs()
        dispatchingWindow = window
    }

    /// Any command other than `.tab(.cycleRecent)` commits a pending Ctrl+Tab cycle first.
    mutating func commitPendingCycle(unless command: Command, in window: WindowID) {
        if case .tab(.cycleRecent) = command { return }
        if case .tabTools(.cancelRecent) = command { return }
        if case .tabTools(.dismissToast) = command { return }
        if case .tabTools(.quoteLinkCopied) = command { return }
        if command == .app(.exit), state.session.windows[window]?.recentCycle != nil { return }
        commitCycle(in: window)
    }

    /// Ends a Ctrl+Tab cycle: the switcher's selection is shown (Arc switches when Control is released), then tabs that
    /// entered or left the screen relative to the cycle's baseline are stamped once.
    mutating func commitCycle(in window: WindowID) {
        guard let cycle = state.session.windows[window]?.recentCycle else { return }
        state.session.windows[window]!.recentCycle = nil
        if cycle.order.indices.contains(cycle.index) { focus(cycle.order[cycle.index], in: window) }
        stamp(state.onScreenTabs().symmetricDifference(cycle.baseline))
    }

    /// An open command bar closes unless the command keeps it; an open Library page or Peek closes unless the
    /// command keeps it or is a command bar command (`.commandBar(.open)` then replaces it, `.dismiss` closes it).
    /// A Peek that closes drops its scratch tab too.
    mutating func applyOverlayRule(for command: Command, in window: WindowID) {
        guard let overlay = state.session.windows[window]?.overlay else { return }
        let keeps = switch overlay {
        case .commandBar: command.keepsCommandBar
        case .library: command.keepsLibrary || command.keepsCommandBar
        case .peek: command.keepsPeek || command.keepsCommandBar
        }
        if !keeps {
            if case .peek = overlay { closePeek(in: window) } else { state.session.windows[window]!.overlay = nil }
            closedOverlay = true
        }
    }

    /// `lastActiveAt = now` for these tabs (any container); other ids are ignored.
    mutating func stamp(_ tabs: Set<ItemID>) {
        let now = ctx.now
        for tab in tabs.sorted() {
            guard let scope = state.locate(tab) else { continue }
            state.withTree(scope) { $0.updateTab(tab) { if $0.lastActiveAt != now { $0.lastActiveAt = now } } }
        }
    }

    mutating func finish(from input: AppState) -> Transition {
        cancelBarTranslationsWithNoBar()
        normalize(&state)
        reconcileFind(from: input)
        reconcileAI(from: input)
        reconcileCaptures(from: input)
        reconcilePictureInPicture(from: input)
        reconcileFullscreen(from: input)
        if let archived = state.doc.archive.first, !input.doc.archive.contains(where: { $0.id == archived.id }) { playSound(.tabsArchived) }
        captureSidebarChanges()
        if input.doc.sidebarData.sync?.document != state.doc.sidebarData.sync?.document { requestSidebarSync() }
        if let before = screenBefore {
            let walking = dispatchingWindow.flatMap { state.session.windows[$0]?.recentCycle } != nil
            if !walking { stamp(before.symmetricDifference(state.onScreenTabs())) }
        }
        let changed = state != input
        if changed { state.session.rev += 1 }
        return Transition(state: state, effects: effects, docChanged: changed && state.doc != input.doc, changed: changed, keyShortcut: keyShortcut, keyHandled: keyHandled,
                          keyAction: keyAction)
    }
}
