import BrkBase
import BrkDomain
import CoreGraphics

/// Which of Arc's tab list motions a part of a change runs on (Arc 1.170, `TablistOutlineView`, read from the binary and
/// timed on recordings, docs/checks/2026-11-13-sidebar-animations.md):
/// - `list`: every change of the rows (a tab added, closed, restored, pinned, moved, Clear, a section collapsing):
///   `OutlineViewDiffableDataSource` applies it inside an animation group of 0.12 s (bin:0x100969f74).
/// - `folderOpen`: `animator().expandItem` (bin:0x1002a8798): 0.2 s, ease-out.
/// - `folderClose`: `animator().collapseItem` in its own group (bin:0x1002ad290): 0.25 s.
public enum TablistMotionTiming: Sendable, Hashable { case list, folderOpen, folderClose }

/// How the rows of the tab list get from one layout to the next, as Arc's outline view moves them. Offsets are in the
/// list's document points; a slide's `dy` is where the item starts relative to its new place (old y minus new y) and it
/// eases to 0.
public struct TablistMotionPlan: Sendable, Equatable {
    public struct Slide: Sendable, Equatable {
        public var timing: TablistMotionTiming
        public var dy: Double
        public init(_ timing: TablistMotionTiming, _ dy: Double) { self.timing = timing; self.dy = dy }
    }

    /// A row that is new to the list.
    public enum Arrival: Sendable, Equatable {
        /// Fades in at its place (NSTableView's `effectFade`).
        case fade
        /// Comes out from under the folder row whose bottom edge is at document y `clip`, riding its `slides`.
        case underFolder(clip: Double)
    }

    /// A row that leaves the list; it is drawn from its old place.
    public enum Departure: Sendable, Equatable {
        /// Fades out where it was, under the rows that slide over it (one row removed: `effectFade`).
        case fade
        /// Slides up by `by` under the edge at document y `clip` (the row above its block, or its folder's row), its title
        /// gone at once; `fades` as well when several rows went in one change (`effectFade | slideUp`, bin:0x1009688a0).
        case slideUp(by: Double, clip: Double, fades: Bool, timing: TablistMotionTiming)
    }

    /// Items that stay (rows, the divider, New Tab, Live Folder notes) and rows coming out from under a folder.
    public var slides: [RowFrame.Kind: [Slide]] = [:]
    public var arrivals: [RowFrame.Kind: Arrival] = [:]
    public var departures: [RowFrame.Kind: Departure] = [:]
    /// Rows whose order changed (pinned, unpinned, dropped elsewhere): drawn over the others while they move.
    public var moved: Set<RowFrame.Kind> = []
    /// Folders that opened (true) or closed (false): their glyph turns with the rows.
    public var toggled: [ItemID: Bool] = [:]

    public init() {}

    public var isEmpty: Bool { slides.isEmpty && arrivals.isEmpty && departures.isEmpty }
}

public enum TablistMotion {
    /// Arc's rule for removals (bin:0x1009688a0, counting the removals of the change at bin:0x1009689f8): fewer than two
    /// fade where they are; more slide up as well.
    public static let slideUpRemovals = 2

    /// The motion from the layout `old` of `oldSpace` to `new` of `newSpace`, for the same Space at the same width.
    public static func plan(from old: [RowFrame], _ oldSpace: SpaceSnapshot, to new: [RowFrame], _ newSpace: SpaceSnapshot) -> TablistMotionPlan {
        var plan = TablistMotionPlan()
        guard old != new else { return plan }
        let spacing = Metrics.tablist.rowSpacing.value
        let oldRows = old.filter { $0.kind != .topSpacer }, newRows = new.filter { $0.kind != .topSpacer }
        let oldRect = Dictionary(oldRows.map { ($0.kind, $0.rect) }, uniquingKeysWith: { a, _ in a })
        let newRect = Dictionary(newRows.map { ($0.kind, $0.rect) }, uniquingKeysWith: { a, _ in a })
        let oldFolders = folders(oldSpace), newFolders = folders(newSpace)

        /// The height a folder's shown contents take in a layout (0 while closed or absent).
        func block(_ kinds: [RowFrame.Kind], in rects: [RowFrame.Kind: CGRect]) -> Double {
            let shown = kinds.compactMap { rects[$0] }
            guard let first = shown.map(\.minY).min(), let last = shown.map(\.maxY).max() else { return 0 }
            return last + spacing - first
        }

        // Folders that open or close, and open folders that arrive with their rows: their contents slide under their row.
        var opening: [(folder: ItemID, height: Double)] = []
        var closing: [(folder: ItemID, height: Double)] = []
        var handled: Set<RowFrame.Kind> = []
        var cameFrom: [RowFrame.Kind: ItemID] = [:]
        for (id, now) in newFolders.order.compactMap({ id in newFolders.info[id].map { (id, $0) } }) {
            let kind = RowFrame.Kind.item(id)
            guard let rect = newRect[kind] else { continue }
            if let before = oldFolders.info[id], oldRect[kind] != nil {
                guard before.collapsed != now.collapsed else { continue }
                plan.toggled[id] = !now.collapsed
                if now.collapsed {
                    let gone = before.contents.filter { newRect[$0] == nil && oldRect[$0] != nil }
                    let height = block(before.contents, in: oldRect)
                    for k in gone {
                        plan.departures[k] = .slideUp(by: height, clip: rect.maxY, fades: false, timing: .folderClose)
                        handled.insert(k)
                    }
                    if height > 0 { closing.append((id, height)) }
                    continue
                }
            } else if now.collapsed || handled.contains(kind) {
                continue
            }
            // Opened, or arrived open on its own (a section expanding): its new contents come out from under it.
            let coming = now.contents.filter { oldRect[$0] == nil && newRect[$0] != nil && !handled.contains($0) }
            let height = block(now.contents, in: newRect)
            for k in coming {
                plan.arrivals[k] = .underFolder(clip: rect.maxY)
                plan.slides[k, default: []].append(.init(.folderOpen, -height))
                handled.insert(k)
                cameFrom[k] = id
            }
            if height > 0, oldFolders.info[id] != nil || !coming.isEmpty { opening.append((id, height)) }
        }

        // Rows that leave on their own: one fades, several slide up their blocks. The divider, New Tab and a Live Folder's
        // note are not rows of Arc's outline: they fade and do not count.
        let removed = oldRows.map(\.kind).filter { newRect[$0] == nil && !handled.contains($0) }
        let removedRows = removed.filter { if case .item = $0 { true } else { false } }
        for k in removed { if case .item = k {} else { plan.departures[k] = .fade } }
        if removedRows.count >= slideUpRemovals {
            let gone = Set(removedRows)
            var index = 0
            while index < oldRows.count {
                guard gone.contains(oldRows[index].kind) else { index += 1; continue }
                var end = index
                while end + 1 < oldRows.count, gone.contains(oldRows[end + 1].kind) { end += 1 }
                let top = oldRows[index].rect.minY, height = oldRows[end].rect.maxY + spacing - top
                let above = index > 0 ? newRect[oldRows[index - 1].kind].map { $0.maxY + spacing } : nil
                for k in oldRows[index...end].map(\.kind) {
                    plan.departures[k] = .slideUp(by: height, clip: above ?? top, fades: true, timing: .list)
                }
                index = end + 1
            }
        } else {
            for k in removedRows { plan.departures[k] = .fade }
        }
        for row in newRows where oldRect[row.kind] == nil && plan.arrivals[row.kind] == nil {
            plan.arrivals[row.kind] = .fade
        }

        // Items that stay: the part of their shift owed to folders opening or closing above them takes that folder's
        // timing, the rest the list's.
        let contents = { (id: ItemID) in Set((oldFolders.info[id]?.contents ?? []) + (newFolders.info[id]?.contents ?? [])) }
        let openingContents = opening.map { ($0, contents($0.folder)) }, closingContents = closing.map { ($0, contents($0.folder)) }
        for row in newRows {
            guard let before = oldRect[row.kind] else { continue }
            let total = before.minY - row.rect.minY
            func owed(_ list: [((folder: ItemID, height: Double), Set<RowFrame.Kind>)]) -> Double {
                list.reduce(0.0) { sum, entry in
                    guard let folder = newRect[.item(entry.0.folder)], folder.minY < row.rect.minY, !entry.1.contains(row.kind) else { return sum }
                    return sum + entry.0.height
                }
            }
            let opened = -owed(openingContents), closed = owed(closingContents)
            var slides: [TablistMotionPlan.Slide] = []
            if abs(opened) > 0.5 { slides.append(.init(.folderOpen, opened)) }
            if abs(closed) > 0.5 { slides.append(.init(.folderClose, closed)) }
            let rest = total - opened - closed
            if abs(rest) > 0.5 { slides.append(.init(.list, rest)) }
            if !slides.isEmpty { plan.slides[row.kind, default: []].append(contentsOf: slides) }
        }
        // Rows coming out from under a folder also ride whatever moves the folder itself.
        for (kind, folder) in cameFrom {
            guard let ride = plan.slides[.item(folder)] else { continue }
            plan.slides[kind, default: []].append(contentsOf: ride)
        }
        plan.moved = moved(old: oldRows.map(\.kind), new: newRows.map(\.kind), staying: Set(oldRect.keys).intersection(newRect.keys))
        return plan
    }

    /// Each folder's open state and what it shows in the list (its rows, nested open folders' rows, a Live Folder's note).
    struct Folders {
        var info: [ItemID: (collapsed: Bool, contents: [RowFrame.Kind])] = [:]
        /// Folders from the top of the list down, outer before inner.
        var order: [ItemID] = []
    }

    static func folders(_ space: SpaceSnapshot) -> Folders {
        var out = Folders()
        @discardableResult
        func visit(_ rows: [Row]) -> [RowFrame.Kind] {
            var shown: [RowFrame.Kind] = []
            for row in rows {
                shown.append(.item(row.id))
                guard case .folder(let folder) = row else { continue }
                out.order.append(folder.id)
                let inner = visit(folder.children)
                var contents = folder.collapsed ? [] : inner
                if !folder.collapsed, folder.live != nil, folder.children.isEmpty {
                    contents.append(.livePlaceholder(folder.id))
                }
                out.info[folder.id] = (folder.collapsed, contents)
                shown += contents
            }
            return shown
        }
        visit(space.pinned.rows)
        visit(space.today.rows)
        return out
    }

    /// The rows that changed place in the order: those outside the longest run kept in the same order.
    static func moved(old: [RowFrame.Kind], new: [RowFrame.Kind], staying: Set<RowFrame.Kind>) -> Set<RowFrame.Kind> {
        let before = old.filter(staying.contains), after = new.filter(staying.contains)
        let position = Dictionary(before.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let sequence = after.compactMap { position[$0] }
        // Longest increasing subsequence, keeping the indexes that form it.
        var tails: [Int] = [], tailIndex: [Int] = [], previous = [Int](repeating: -1, count: sequence.count)
        for (i, value) in sequence.enumerated() {
            var lo = 0, hi = tails.count
            while lo < hi { let mid = (lo + hi) / 2; if tails[mid] < value { lo = mid + 1 } else { hi = mid } }
            if lo > 0 { previous[i] = tailIndex[lo - 1] }
            if lo == tails.count { tails.append(value); tailIndex.append(i) } else { tails[lo] = value; tailIndex[lo] = i }
        }
        var kept: Set<Int> = []
        var i = tailIndex.last ?? -1
        while i >= 0 { kept.insert(i); i = previous[i] }
        return Set(after.enumerated().filter { !kept.contains($0.offset) }.map(\.element))
    }
}
