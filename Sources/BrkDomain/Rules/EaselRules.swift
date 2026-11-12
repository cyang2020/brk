import BrkBase
import CoreGraphics
import Foundation

// Easels (Easels.swift). An Easel's board is saved in `Doc.easels`; its rows are tabs at `EaselPage.url(id)`, so the
// sidebar, the archive and the codec treat them like any tab. Only standard windows make or open Easels (an incognito
// window keeps nothing). Every edit stamps `modifiedAt`, which orders the Library's cards.

extension Work {
    mutating func easels(_ command: EaselCommand, in window: WindowID) {
        switch command {
        case .create:
            guard let doc = state.doc.windows[window], doc.kind == .standard, let space = state.doc.spaces[doc.space] else { return }
            let id = EaselID(ctx.newID())
            state.doc.easels[id] = Easel(id: id, title: EaselPage.defaultTitle, titleSize: EaselTitleSizes.default, createdAt: ctx.now,
                                         modifiedAt: ctx.now, profile: space.profile, elements: [])
            guard let row = addRow(for: id, in: space) else { state.doc.easels[id] = nil; return }
            state.session.windows[window]?.easelTitleEditing = id
            state.session.windows[window]?.easelMessage = nil
            request(EaselPage.url(id), for: PageID(window: window, item: row))
            focus(row, in: window)
        case .open(let id):
            guard let doc = state.doc.windows[window], doc.kind == .standard, state.doc.easels[id] != nil,
                  let space = state.doc.spaces[doc.space] else { return }
            let tree = state.doc.tree
            let rows = (tree.tabs(under: space.pinnedRoot) + tree.tabs(under: space.todayRoot) + (state.favoritesRoot(for: space).map(tree.tabs(under:)) ?? []))
            let row = rows.first { EaselPage.id(of: state.address(of: $0, in: window, for: .visible)) == id } ?? addRow(for: id, in: space)
            guard let row else { return }
            request(EaselPage.url(id), for: PageID(window: window, item: row))
            focus(row, in: window)
        case .rename(let id, let title):
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            edit(id, in: window) { $0.title = trimmed }
        case .stepTitleSize(let id, let delta):
            edit(id, in: window) { $0.titleSize = EaselTitleSizes.step($0.titleSize, by: delta) }
        case .add(let id, let element):
            guard let element = valid(element) else { return }
            edit(id, in: window) { easel in
                guard !easel.elements.contains(where: { $0.id == element.id }) else { return }
                easel.elements.append(element)
            }
        case .update(let id, let changed):
            let checked = changed.map { ($0, valid($0)) }
            edit(id, in: window) { easel in
                for (element, valid) in checked {
                    guard let index = easel.elements.firstIndex(where: { $0.id == element.id }) else { continue }
                    if easel.elements[index].shape == .text, element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        easel.elements.remove(at: index)
                    } else if var fixed = valid {
                        // An update moves, resizes or retypes; it never turns a shape into another or swaps a picture.
                        fixed.shape = easel.elements[index].shape
                        fixed.image = easel.elements[index].image
                        easel.elements[index] = fixed
                    }
                }
            }
        case .remove(let id, let elements):
            let gone = Set(elements)
            edit(id, in: window) { $0.elements.removeAll { gone.contains($0.id) } }
        case .duplicate(let id, let elements):
            guard let originals = state.doc.easels[id]?.elements.filter({ elements.contains($0.id) }), !originals.isEmpty else { return }
            let copies = originals.map { original in
                var copy = original.moved(by: EaselDefaults.duplicateOffset)
                copy.id = ctx.newID()
                return copy
            }
            edit(id, in: window) { $0.elements += copies }
        case .chooseImage(let id, let point):
            guard state.doc.easels[id] != nil, state.doc.windows[window]?.kind == .standard else { return }
            effects.append(.easel(.chooseImage(window, id, at: point)))
        case .importImage(let id, let source, let point):
            guard state.doc.easels[id] != nil, state.doc.windows[window]?.kind == .standard, source.isFileURL else { return }
            effects.append(.easel(.importImage(window, id, from: source, at: point, element: ctx.newID())))
        case .share(let id):
            guard let easel = state.doc.easels[id], state.doc.windows[window]?.kind == .standard else { return }
            effects.append(.easel(.share(window, EaselCard(id: id, title: easel.title, titleSize: easel.titleSize, elements: easel.elements,
                                                           modifiedAt: easel.modifiedAt))))
        case .requestDelete(let id):
            guard let easel = state.doc.easels[id] else { return }
            state.session.windows[window]?.pendingEaselDeletion = EaselDeletionRequest(id: id, title: easel.title, token: ctx.newID())
        case .confirmDelete(let id, let token, let confirmed):
            guard let request = state.session.windows[window]?.pendingEaselDeletion, request.id == id, request.token == token else { return }
            state.session.windows[window]?.pendingEaselDeletion = nil
            if confirmed { deleteEasel(id) }
        }
    }

    mutating func easelEvent(_ event: EaselEvent) {
        switch event {
        case .imageImported(let window, let id, let element, let file, let size, let point):
            guard size.width > 0, size.height > 0 else { return }
            // Placed at its own size, scaled down to fit Metrics-free defaults (Arc drops a picture at a readable size).
            let scale = min(1, EaselDefaults.imageMaxSide / max(size.width, size.height))
            let box = CGSize(width: size.width * scale, height: size.height * scale)
            let frame = CGRect(x: point.x - box.width / 2, y: point.y - box.height / 2, width: box.width, height: box.height)
            edit(id, in: window) { easel in
                guard !easel.elements.contains(where: { $0.id == element }) else { return }
                easel.elements.append(EaselElement(id: element, shape: .image, frame: frame, image: file))
            }
        case .shared(let window, _, let url):
            state.session.windows[window]?.easelMessage = nil
            toast("Saved \(url.lastPathComponent)", in: window)
        case .failed(let window, _, let message):
            state.session.windows[window]?.easelMessage = message
            toast(message, in: window)
        }
    }

    /// A new row for `id` at the end of the space's Pinned (where Arc's File > New Easel puts it, Q09 a).
    private mutating func addRow(for id: EaselID, in space: Space) -> ItemID? {
        guard let easel = state.doc.easels[id] else { return nil }
        let row = ItemID(ctx.newID())
        let count = state.doc.tree[space.pinnedRoot]?.children.count ?? 0
        do {
            try state.doc.tree.insert(row, .tab(Tab(url: EaselPage.url(id), title: easel.title, favicon: EaselPage.favicon, lastActiveAt: ctx.now)),
                                      at: .into(parent: space.pinnedRoot, index: count), createdAt: ctx.now)
        } catch { return nil }
        return row
    }

    /// Applies one edit to a saved Easel and stamps it. The first edit ends the new Easel's selected title.
    private mutating func edit(_ id: EaselID, in window: WindowID, _ change: (inout Easel) -> Void) {
        guard var easel = state.doc.easels[id] else { return }
        let before = easel
        change(&easel)
        if state.session.windows[window]?.easelTitleEditing == id { state.session.windows[window]?.easelTitleEditing = nil }
        guard easel != before else { return }
        easel.modifiedAt = ctx.now
        state.doc.easels[id] = easel
        if easel.title != before.title { retitleRows(of: id, easel.title) }
    }

    /// Rows keep the Easel's title as their page title, so the sidebar, the command bar and the archive name it.
    private mutating func retitleRows(of id: EaselID, _ title: String) {
        for tab in state.doc.tree.allTabs() where EaselPage.id(of: state.tab(tab)?.url) == id {
            state.doc.tree.updateTab(tab) { $0.title = title }
        }
        for window in state.doc.windows.keys {
            for (item, slot) in state.doc.windows[window]?.slots ?? [:] where EaselPage.id(of: slot.committedURL) == id {
                state.doc.windows[window]?.slots[item]?.observedTitle = title
            }
        }
    }

    /// Deletes the board, its pictures, every row that shows it and archive entries that would bring a row back.
    mutating func deleteEasel(_ id: EaselID) {
        guard state.doc.easels.removeValue(forKey: id) != nil else { return }
        for row in state.easelRows(id) {
            _ = removeItem(row)
            unload(row)
            replaceShown(row)
        }
        state.doc.archive.removeAll { EaselPage.id(of: $0.tab.url) == id }
        for window in state.session.windows.keys where state.session.windows[window]?.easelTitleEditing == id {
            state.session.windows[window]?.easelTitleEditing = nil
        }
        effects.append(.easel(.deleteFiles(id)))
    }

    /// Finite numbers, a box no larger than the board allows, at most a stroke's worth of points.
    private func valid(_ element: EaselElement) -> EaselElement? {
        let limit = EaselDefaults.boardLimit
        func finite(_ v: CGFloat) -> Bool { v.isFinite && abs(v) <= limit }
        guard !element.id.isEmpty, element.id.count <= 200,
              [element.frame.minX, element.frame.minY, element.frame.width, element.frame.height].allSatisfy(finite),
              element.points.count <= EaselDefaults.maxPoints, element.points.allSatisfy({ finite($0.x) && finite($0.y) }),
              element.text.count <= EaselDefaults.maxText, element.fontSize.isFinite else { return nil }
        var fixed = element
        fixed.frame = element.frame.standardized
        fixed.fontSize = min(200, max(6, element.fontSize))
        if element.shape == .arrow, element.points.count != 2 { return nil }
        if element.shape == .ink, element.points.isEmpty { return nil }
        if element.shape == .image, element.image?.isFileURL != true { return nil }
        if element.shape == .arrow || element.shape == .ink { fixed.frame = EaselElement.bounds(of: element.points) }
        return fixed
    }
}

/// Defaults the rules apply (not layout: the board's look is BrkLibrary's EaselStyle).
enum EaselDefaults {
    /// Duplicate puts the copy down and to the right of the original.
    static let duplicateOffset = CGSize(width: 24, height: 24)
    /// A picture is placed no larger than this on its longer side (points).
    static let imageMaxSide: CGFloat = 360
    /// Coordinates beyond this many points from the board's origin are refused.
    static let boardLimit: CGFloat = 100_000
    static let maxPoints = 20_000
    static let maxText = 20_000
}

extension AppState {
    /// The sidebar rows that show Easel `id`: tabs at its address, or whose page in some window committed it.
    func easelRows(_ id: EaselID) -> [ItemID] {
        doc.tree.allTabs().filter { tab in
            EaselPage.id(of: self.tab(tab)?.url) == id
                || doc.windows.keys.contains { EaselPage.id(of: doc.windows[$0]?.slots[tab]?.committedURL) == id }
        }
    }

    /// Where an Easel of the profile `gone` (being deleted) is still in use: the profile of the first Space, in dock order,
    /// with a row showing it, else of the Favorites holding one, else of a remaining Space it was archived from. An Easel's
    /// profile is set when it is made and does not follow its Space's Change Profile, so such a row sits in another profile's
    /// Space. Nil when nothing outside `gone` shows it (its Space was deleted): the Easel goes with the profile.
    func easelHome(_ id: EaselID, besides gone: ProfileID) -> ProfileID? {
        let roles = easelRows(id).compactMap { role(of: $0) }
        for space in doc.spaceOrder where roles.contains(.pinned(space)) || roles.contains(.today(space)) {
            if let profile = doc.spaces[space]?.profile, profile != gone { return profile }
        }
        for case .favorites(let profile) in roles where profile != gone && doc.profiles[profile] != nil { return profile }
        for entry in doc.archive where EaselPage.id(of: entry.tab.url) == id {
            if let profile = entry.fromSpace.flatMap({ doc.spaces[$0]?.profile }), profile != gone { return profile }
        }
        return nil
    }

    /// The cards of `window` that show an Easel, with the Easel each shows.
    func shownEaselPages(in window: WindowID) -> [(PageID, EaselID)] {
        guard let shown = shownItem(in: window) else { return [] }
        return panes(of: shown).compactMap { pane in
            let page = PageID(window: window, item: pane)
            guard session.loaded.contains(page), let id = EaselPage.id(of: address(of: pane, in: window, for: .visible)), doc.easels[id] != nil else { return nil }
            return (page, id)
        }
    }

    func easelSnapshot(_ page: PageID, _ id: EaselID) -> EaselSnapshot? {
        guard let easel = doc.easels[id] else { return nil }
        return EaselSnapshot(id: id, page: page, title: easel.title, titleSize: easel.titleSize, elements: easel.elements,
                             editingTitle: session.windows[page.window]?.easelTitleEditing == id, message: session.windows[page.window]?.easelMessage)
    }

    /// The Library's Easels page: the profile's Easels, most recently edited first.
    func easelCards(in window: WindowID) -> [EaselCard] {
        guard case .profile(let profile) = libraryContext(in: window) else { return [] }
        return doc.easels.values.filter { $0.profile == profile }
            .sorted { $0.modifiedAt != $1.modifiedAt ? $0.modifiedAt > $1.modifiedAt : $0.id < $1.id }
            .map { EaselCard(id: $0.id, title: $0.title, titleSize: $0.titleSize, elements: $0.elements, modifiedAt: $0.modifiedAt) }
    }
}
