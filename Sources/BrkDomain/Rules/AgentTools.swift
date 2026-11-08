import BrkBase
import Foundation

// The reducer's side of Brk's agent tools: reading a tab's text and the typed changes an agent may ask for. BrkApp's
// tool service checks who may ask (the conversation's profile, approvals) and sends these as system events; the
// reducer checks again against the state it owns and answers with `Effect.agentReadDone` or `Effect.agentActDone`.
// Each change is the same rule a click runs, so an agent can do nothing a person could not do in the sidebar.

public enum AgentReadPart: String, Hashable, Sendable, Codable { case text, selection }

public struct AgentReadRequest: Hashable, Sendable {
    /// The tool call this answers.
    public let call: String
    /// The conversation's window.
    public let window: WindowID
    /// An id from `AgentTabFacts`.
    public let tab: String
    public let part: AgentReadPart
    public init(call: String, window: WindowID, tab: String, part: AgentReadPart) {
        self.call = call; self.window = window; self.tab = tab; self.part = part
    }
}

public enum AgentReadOutcome: Hashable, Sendable {
    case content(AIPageContent)
    /// The live page whose selection the app reads (`WebEngine.selectedText`).
    case selection(PageID)
    case failed(String)
}

/// Where tabs go. With neither `folder` nor `newFolder` they go to the top of the section; `section` defaults to Today.
public struct AgentDestination: Hashable, Sendable {
    public enum Section: String, Hashable, Sendable, Codable { case pinned, today }
    public let space: SpaceID
    public let section: Section
    public let folder: ItemID?
    public let newFolder: String?
    public init(space: SpaceID, section: Section = .today, folder: ItemID? = nil, newFolder: String? = nil) {
        self.space = space; self.section = section; self.folder = folder; self.newFolder = newFolder
    }
}

/// One folder of a grouping plan: an existing folder, or a new one with this name.
public struct AgentGroup: Hashable, Sendable {
    public let folder: ItemID?
    public let name: String?
    public let tabs: [ItemID]
    public init(folder: ItemID? = nil, name: String? = nil, tabs: [ItemID]) { self.folder = folder; self.name = name; self.tabs = tabs }
}

public enum AgentAct: Hashable, Sendable {
    case open(URL, space: SpaceID?, background: Bool)
    case focus(ItemID)
    case close([ItemID])
    case move([ItemID], to: AgentDestination)
    /// Tidy's typed result: every group in one step, with Tidy's undo when it regroups the shown Space's Today.
    case group(space: SpaceID, section: AgentDestination.Section, [AgentGroup])
    case split([ItemID])
}

public struct AgentActRequest: Hashable, Sendable {
    public let call: String
    public let window: WindowID
    public let act: AgentAct
    public init(call: String, window: WindowID, act: AgentAct) { self.call = call; self.window = window; self.act = act }
}

public enum AgentActOutcome: Hashable, Sendable {
    /// What happened in words for the agent, and the ids of tabs or folders it made.
    case done(String, ids: [String])
    case refused(String)
}

extension Work {
    mutating func agentRead(_ request: AgentReadRequest) {
        func fail(_ text: String) { effects.append(.agentReadDone(request.call, .failed(text))) }
        guard state.doc.windows[request.window] != nil, state.agentProfile(in: request.window) != nil else { return fail("This conversation's window is gone.") }
        guard let facts = state.agentTab(request.tab, window: request.window) else { return fail("No tab has this id. List or search tabs for current ids.") }
        // A live page of this tab that is on screen, the conversation's window first. A page loaded out of sight does
        // not answer the reader in time (Chromium's DevTools timed out on every one in the real run of 2026-11-08), so
        // such a tab is read like one that is not loaded.
        let onScreen = state.onScreenTabs()
        let live = state.session.live.filter { page, value in
            guard page.item.rawValue == facts.id, request.part == .selection || onScreen.contains(page.item), case .ready = value.document else { return false }
            return value.requestContext == state.libraryContext(in: page.window)
        }.sorted { ($0.key.window == request.window ? 0 : 1, $0.key.window.rawValue) < ($1.key.window == request.window ? 0 : 1, $1.key.window.rawValue) }.first
        if request.part == .selection {
            guard let live else { return fail("This tab is not open in a window, so it has no selection.") }
            effects.append(.agentReadDone(request.call, .selection(live.key)))
            return
        }
        let id = AIRequestID(ctx.newID())
        if let live, case .ready(let document) = live.value.document {
            var reader = AIRequest(window: live.key.window, context: state.libraryContext(in: live.key.window), task: .ask(""),
                                   document: document, purpose: .agentRead(request.call))
            // The page need not be the one the window shows (the request sweep keeps a request with a page of its own).
            reader.page = live.key
            state.session.ai.requests[id] = reader
            effects.append(.aiRead(id, document))
            effects.append(.aiWatch(id, seconds: 30))
            return
        }
        // Not loaded: a hidden reader loads the address in the tab's own profile, as Browse for Me does.
        guard let url = facts.url, AIValidation.destination(url.absoluteString) != nil else { return fail("This tab has no web address to read.") }
        guard let window = readerWindow(for: facts.profile, preferring: request.window) else {
            return fail("No window shows this tab's profile. Open one of its Spaces, then read it again.")
        }
        state.session.ai.requests[id] = AIRequest(window: window, context: .profile(facts.profile), task: .ask(""), purpose: .agentRead(request.call))
        makeAIHidden(id, urls: [url])
    }

    /// A standard window showing a Space of `profile`.
    private func readerWindow(for profile: ProfileID, preferring window: WindowID) -> WindowID? {
        if state.libraryContext(in: window) == .profile(profile), state.doc.windows[window]?.kind == .standard { return window }
        return state.doc.windows.keys.sorted().first { state.doc.windows[$0]?.kind == .standard && state.libraryContext(in: $0) == .profile(profile) }
    }

    mutating func agentAct(_ request: AgentActRequest) {
        let window = request.window
        func refuse(_ text: String) { effects.append(.agentActDone(request.call, .refused(text))) }
        func done(_ text: String, _ ids: [String] = []) { effects.append(.agentActDone(request.call, .done(text, ids: ids))) }
        guard let profile = state.agentProfile(in: window) else { return refuse("Agents cannot change a private window.") }
        /// A tab of this profile's saved sidebar.
        func ownTab(_ id: ItemID) -> Bool {
            guard state.locate(id) == .global, state.doc.tree[id]?.kind == .tab else { return false }
            return state.browsingContext(of: id) == .profile(profile)
        }
        func ownSpace(_ id: SpaceID) -> Bool { state.doc.spaces[id]?.profile == profile }
        switch request.act {
        case .open(let url, let space, let background):
            guard AIValidation.destination(url.absoluteString) != nil else { return refuse("Only http and https addresses open.") }
            let target = space ?? state.doc.windows[window]!.space
            guard ownSpace(target) else { return refuse("That Space is not in this profile.") }
            if !background, state.doc.windows[window]?.space != target { run(.space(.focus(target)), in: window) }
            guard let id = openTab(url, inSpace: target, window: window, focus: !background) else { return refuse("The tab could not be opened.") }
            done("Opened in \(state.displayTitle(of: target)).", [id.rawValue])
        case .focus(let id):
            guard ownTab(id) else { return refuse("No open tab of this profile has that id.") }
            if let space = state.role(of: id)?.space, state.doc.windows[window]?.space != space { run(.space(.focus(space)), in: window) }
            run(.tab(.focus(id)), in: window)
            done("Showing it now.", [id.rawValue])
        case .close(let ids):
            guard !ids.isEmpty, ids.allSatisfy(ownTab) else { return refuse("Every id must be an open tab of this profile.") }
            for id in ids { run(.tab(.close(.item(id))), in: window) }
            done("Closed \(ids.count) \(ids.count == 1 ? "tab" : "tabs"). Today tabs went to the archive.")
        case .move(let ids, let destination):
            guard !ids.isEmpty, ids.allSatisfy(ownTab) else { return refuse("Every id must be an open tab of this profile.") }
            guard ownSpace(destination.space), let space = state.doc.spaces[destination.space] else { return refuse("That Space is not in this profile.") }
            let root = destination.section == .pinned ? space.pinnedRoot : space.todayRoot
            var tree = state.doc.tree
            var made: [String] = []
            let parent: ItemID
            do {
                if let name = destination.newFolder {
                    let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty, title.count <= 60 else { return refuse("A folder name has 1 to 60 characters.") }
                    let folder = ItemID(ctx.newID())
                    try tree.insert(folder, .folder(Folder(title: title, collapsed: false)), at: .into(parent: root, index: 0), createdAt: ctx.now)
                    parent = folder
                    made.append(folder.rawValue)
                } else if let folder = destination.folder {
                    guard case .folder? = tree[folder]?.body, tree.isDescendant(folder, of: root) else { return refuse("That folder is not in this Space's \(destination.section.rawValue) section.") }
                    parent = folder
                } else {
                    parent = root
                }
                for id in ids.reversed() { _ = try tree.move(tree.splitContaining(id) ?? id, to: .into(parent: parent, index: 0)) }
            } catch { return refuse("Those tabs cannot go there.") }
            state.doc.tree = tree
            done("Moved \(ids.count) \(ids.count == 1 ? "tab" : "tabs").", made)
        case .group(let spaceID, let section, let groups):
            guard !groups.isEmpty, groups.count <= 12, ownSpace(spaceID), let space = state.doc.spaces[spaceID] else { return refuse("A plan has 1 to 12 groups in a Space of this profile.") }
            let all = groups.flatMap(\.tabs)
            guard !all.isEmpty, Set(all).count == all.count, all.allSatisfy(ownTab) else { return refuse("Each tab appears once, and every id is an open tab of this profile.") }
            let root = section == .pinned ? space.pinnedRoot : space.todayRoot
            var tree = state.doc.tree
            let original = tree[root]?.children ?? []
            var folders: [ItemID: [ItemID]] = [:]
            var made: [String] = []
            do {
                for group in groups {
                    let folder: ItemID
                    if let existing = group.folder {
                        guard case .folder? = tree[existing]?.body, tree.isDescendant(existing, of: root) else { return refuse("Folder \(existing.rawValue) is not in that section.") }
                        folder = existing
                    } else {
                        let title = (group.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty, title.count <= 60 else { return refuse("Each new group needs a name of 1 to 60 characters.") }
                        folder = ItemID(ctx.newID())
                        var payload = Folder(title: title, collapsed: false)
                        payload.isGroup = section == .today
                        try tree.insert(folder, .folder(payload), at: .into(parent: root, index: Int.max), createdAt: ctx.now)
                        made.append(folder.rawValue)
                    }
                    for tab in group.tabs { _ = try tree.move(tree.splitContaining(tab) ?? tab, to: .into(parent: folder, index: Int.max)) }
                    folders[folder] = group.tabs
                }
            } catch { return refuse("The plan could not be applied. No tabs were moved.") }
            state.doc.tree = tree
            // Grouping the shown Space's Today is Tidy's result: the same undo, the same toast.
            if section == .today, state.doc.windows[window]?.space == spaceID, made.count == groups.count {
                state.session.ai.undo[window] = AIOrganizeUndo(space: spaceID, original: original, folders: folders)
                undoToast("Tidied Tabs! Use", undo: .tidy, in: window)
            }
            done("Grouped \(all.count) tabs into \(groups.count) \(groups.count == 1 ? "folder" : "folders").", made)
        case .split(let ids):
            guard (2...Metrics.content.maxPanes.value).contains(ids.count), Set(ids).count == ids.count, ids.allSatisfy(ownTab) else {
                return refuse("A split takes 2 to \(Metrics.content.maxPanes.value) different open tabs of this profile.")
            }
            run(.tabTools(.openInSplit(.items(ids))), in: window)
            let split = state.doc.tree.splitContaining(ids[0])
            guard let split, ids.allSatisfy({ state.doc.tree.splitContaining($0) == split }) else { return refuse("Those tabs could not go into one split.") }
            done("Showing them side by side.", [split.rawValue])
        }
    }
}
