import BrkBase
import Foundation

extension Work {
    mutating func sidebarData(_ command: SidebarDataCommand, in window: WindowID) {
        guard state.doc.windows[window]?.kind == .standard else { return }
        switch command {
        case .welcome: effects.append(.sidebarData(.panel(window, .welcome)))
        case .tour: effects.append(.sidebarData(.tour(window)))
        case .importFile: effects.append(.sidebarData(.panel(window, .importFile)))
        case .syncSettings: effects.append(.sidebarData(.panel(window, .syncSettings)))
        case .importSelected(let url, let format):
            guard url.isFileURL, let target = state.sidebarImportTarget(in: window) else { return }
            effects.append(.sidebarData(.importSelected(window, url, format, target)))
        case .connectSelectedFolder(let url):
            guard url.isFileURL, let target = state.sidebarImportTarget(in: window) else { return }
            effects.append(.sidebarData(.connectSelectedFolder(window, url, target)))
        case .exportSelected(let url):
            guard url.isFileURL else { return }
            effects.append(.sidebarData(.exportSelected(window, url)))
        case .cancelFilePanel: effects.append(.sidebarData(.cancelFilePanel(window)))
        case .syncNow: requestSidebarSync()
        case .disconnect:
            state.doc.sidebarData.sync?.folder = nil
            state.doc.sidebarData.sync?.epoch = ctx.newID()
            state.session.sidebarDataStatus = "Disconnected. Local sidebar kept; shared folder files kept."
        case .completeOnboarding(let choices):
            guard !state.doc.sidebarData.onboardingCompleted, let space = state.doc.windows[window]?.space,
                  let model = state.doc.spaces[space] else { return }
            state.doc.sidebarData.onboardingCompleted = true
            let name = String(choices.spaceName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
            state.doc.spaces[space]?.title = name.isEmpty ? "Personal" : name
            if choices.starterTabs {
                insertImported([.link(title: "Wikipedia", url: URL(string: "https://www.wikipedia.org/")!),
                                .link(title: "Mozilla Developer Network", url: URL(string: "https://developer.mozilla.org/")!)],
                               root: model.todayRoot)
            }
            if choices.favorites, let root = state.doc.favorites[model.profile] {
                insertImported([.link(title: "Wikipedia", url: URL(string: "https://www.wikipedia.org/")!)], root: root)
            }
            state.session.sidebarDataStatus = "Setup complete."
            if choices.defaultBrowser { effects.append(.app(.registerAsDefaultBrowser)) }
            if choices.tour { effects.append(.sidebarData(.tour(window))) }
            if choices.importAfter { effects.append(.sidebarData(.panel(window, .importFile))) }
        }
    }

    mutating func sidebarDataEvent(_ event: SidebarDataEvent) {
        switch event {
        case .syncPoll: requestSidebarSync()
        case .imported(let window, let target, let preview, let favorites):
            guard state.sidebarImportTarget(in: window) == target, let space = state.doc.spaces[target.space] else { return }
            // Credential writes have already succeeded (or were cancelled) before this event is dispatched.
            let root = favorites ? state.doc.favorites[space.profile] ?? space.pinnedRoot : space.pinnedRoot
            let imported = insertImported(preview.entries, root: root)
            let existingVisits = state.doc.history.filter { $0.profile == space.profile }
            let previousHistory = Set(existingVisits.map(\.url))
            var known = Dictionary(grouping: existingVisits, by: \.url).mapValues { Set($0.map(\.visitedAt)) }
            for visit in preview.visits.sorted(by: { $0.visitedAt < $1.visitedAt }) where SidebarImport.publicURL(visit.url) && Instant.supported.contains(visit.visitedAt) {
                guard known[visit.url, default: []].insert(visit.visitedAt).inserted else { continue }
                state.doc.history.append(HistoryEntry(id: HistoryVisitID(ctx.newID()), url: visit.url, title: visit.title,
                                                     visitedAt: visit.visitedAt, profile: space.profile))
            }
            state.doc.history.sort { $0.visitedAt == $1.visitedAt ? $0.url.absoluteString < $1.url.absoluteString : $0.visitedAt > $1.visitedAt }
            let addedHistory = Set(state.doc.history.filter { $0.profile == space.profile }.map(\.url)).subtracting(previousHistory).count
            state.session.sidebarDataStatus = "Imported \(imported) bookmarks, \(addedHistory) new history URLs, \(preview.passwords) passwords. Skipped \(preview.rejected) invalid entries and \(preview.bookmarkCount - imported) duplicate or unplaced bookmarks."
        case .connected(let window, let folder):
            guard let w = state.doc.windows[window], w.kind == .standard, let profile = state.doc.spaces[w.space]?.profile,
                  URL(fileURLWithPath: folder).isFileURL, folder.hasPrefix("/") else { return }
            // Mapping is explicitly to this selected local profile. Reconnection preserves its replica identity.
            if var existing = state.doc.sidebarData.sync, existing.profile == profile,
               existing.counter < SidebarDataCodec.revisionLimit - UInt64(SidebarDataCodec.recordLimit) {
                existing.folder = folder; existing.epoch = ctx.newID(); existing.pending = true
                state.doc.sidebarData.sync = existing
            } else {
                state.doc.sidebarData.sync = SidebarSyncLocal(replica: ctx.newID(), profile: profile, folder: folder, epoch: ctx.newID())
            }
            captureSidebarChanges()
            requestSidebarSync()
        case .syncRead(let epoch, let incoming):
            guard var local = state.doc.sidebarData.sync, local.folder != nil, local.epoch == epoch else { return }
            do {
                try SidebarDataCodec.validate(incoming)
                let merged = try SidebarSync.merge(local.document, incoming)
                try SidebarDataCodec.validate(merged)
                try state.validateSidebarSyncMerge(merged, local: local)
                guard merged != local.document else { return }
                local.document = merged
                local.counter = max(local.counter, merged.records.values.map(\.stamp.counter).max() ?? 0)
                local.pending = true
                state.doc.sidebarData.sync = local
                materializeSidebarSync()
                let baseline = state.syncProjection(profile: local.profile).values
                state.doc.sidebarData.sync?.baseline = baseline
                state.session.sidebarDataStatus = "Received sidebar changes. Local browsing data and windows kept."
            } catch { state.session.sidebarDataStatus = "Sync failed: \(error)" }
        case .syncWritten(let epoch, let revision, let published):
            guard state.doc.sidebarData.sync?.epoch == epoch else { return }
            if state.doc.sidebarData.sync?.document == published { state.doc.sidebarData.sync?.pending = false }
            state.session.sidebarDataStatus = "Saved revision \(revision) to the sync folder."
        case .failed(let epoch, let message):
            if let epoch, state.doc.sidebarData.sync?.epoch != epoch { return }
            state.session.sidebarDataStatus = message
        }
    }

    @discardableResult
    mutating func insertImported(_ entries: [ExportEntry], root: ItemID) -> Int {
        var count = 0
        for entry in entries {
            switch entry {
            case .link(let title, let url):
                guard SidebarImport.publicURL(url), !(state.doc.tree[root]?.children ?? []).contains(where: { id in
                    if case .tab(let tab)? = state.doc.tree[id]?.body { return (tab.pinnedURL ?? tab.url) == url }; return false
                }) else { continue }
                let id = ItemID(ctx.newID())
                do {
                    try state.doc.tree.insert(id, .tab(Tab(url: url, title: String(title.prefix(500)), customTitle: String(title.prefix(500)), lastActiveAt: ctx.now)),
                                              at: .into(parent: root, index: Int.max), createdAt: ctx.now)
                    count += 1
                } catch {}
            case .folder(let title, let children):
                // Favorites accepts tabs only. Flatten folders when that destination is selected.
                if state.doc.tree.role(of: root)?.kind == .favorites { count += insertImported(children, root: root); continue }
                let existing = state.doc.tree[root]?.children.first { id in
                    if case .folder(let folder)? = state.doc.tree[id]?.body { return folder.title == title }; return false
                }
                let id = existing ?? ItemID(ctx.newID())
                if existing == nil {
                    do { try state.doc.tree.insert(id, .folder(Folder(title: String(title.prefix(500)), collapsed: false)), at: .into(parent: root, index: Int.max), createdAt: ctx.now) }
                    catch { continue }
                }
                count += insertImported(children, root: id)
            }
        }
        return count
    }

    /// Runs after normalization. Replica metadata and the sidebar edit enter the same StateCodec checkpoint.
    mutating func captureSidebarChanges() {
        guard var local = state.doc.sidebarData.sync, local.folder != nil else { return }
        guard state.doc.profiles[local.profile] != nil else {
            local.folder = nil; local.epoch = ctx.newID(); state.doc.sidebarData.sync = local
            state.session.sidebarDataStatus = "Sync disconnected because its mapped profile was removed."
            return
        }
        var current = state.syncProjection(profile: local.profile).values
        // A tombstoned identity cannot be resurrected by an old archive entry. Reenroll it under a fresh ID.
        for key in current.keys.sorted() where local.document.records[key]?.value == nil && local.document.records[key] != nil {
            let replacement = "i-" + ctx.newID()
            let raw = local.aliases.first(where: { $0.value == key })?.key ?? key
            local.aliases[raw] = replacement
            local.pending = true
        }
        current = state.syncProjection(profile: local.profile, aliases: local.aliases).values
        let changed = Set(current.keys).union(local.baseline.keys).filter { current[$0] != local.baseline[$0] }.sorted()
        let writable = changed.filter { local.document.records[$0]?.value != nil || local.document.records[$0] == nil }
        guard local.counter < SidebarDataCodec.revisionLimit,
              UInt64(writable.count) < SidebarDataCodec.revisionLimit - local.counter else {
            state.session.sidebarDataStatus = "Sync revision exhausted; disconnect and choose a new empty folder. Local edits were kept."
            return
        }
        for key in writable {
            local.counter += 1
            local.document.records[key] = SidebarSyncRecord(stamp: SidebarSyncStamp(counter: local.counter, replica: local.replica), value: current[key])
            local.pending = true
        }
        do { try SidebarDataCodec.validate(local.document) }
        catch { state.session.sidebarDataStatus = "Sync failed: \(error). Local edits were kept."; return }
        local.baseline = current
        state.doc.sidebarData.sync = local
    }

    mutating func requestSidebarSync() {
        guard let local = state.doc.sidebarData.sync, let folder = local.folder else { return }
        effects.append(.sidebarData(.exchange(epoch: local.epoch, folder: folder, replica: local.replica, revision: local.counter, local.document)))
    }
}
