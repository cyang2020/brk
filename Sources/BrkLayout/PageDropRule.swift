import BrkBase
import BrkDomain
import CoreGraphics

/// What the page shows for a drag held over it.
public enum PageDropPreview: Equatable, Sendable {
    /// The page stays whole, with nothing on it.
    case none
    /// A 3 pt frame around the pane: a release makes the dragged tab what that pane shows.
    case frame(pane: Int)
    /// The panes make room for an empty slot before pane `before` (at the end when it is the pane count).
    case slot(before: Int, orientation: SplitOrientation)
}

/// What a release does.
public enum PageDropTarget: Equatable, Sendable {
    /// Arc's `replaceContent`.
    case replace(pane: Int)
    /// Arc's `insertContent`: the tab becomes pane `index`.
    case insert(index: Int)
}

/// The rule Arc 1.170 runs for a drag over the page, read from `ARCUI.SplitViewController`
/// (verify/visual-pairs/run-20261103/r5-4/REPORT.md has the addresses and the pseudocode). Two things make the preview
/// depend on the path:
/// - the rule looks at the panes as they are now, and a slot is a pane: once a slot shows, the pointer is over the slot or
///   over the narrower page, and each has its own zones;
/// - positions are read at most once per `throttle`, and only when the pointer moves, so a quick pass can skip a zone.
public enum PageDropRule {
    /// Combine's `throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)` on the drag's positions (Arc 0x100b199e0).
    public static let throttle = 0.1
    /// A slot that goes away is removed when its 0.2 s animation ends (Arc 0x100a51598).
    public static let collapse = 0.2
    /// The end of an animation arrives after a frame or so. Arc's value comes from Core Animation and has no constant; this
    /// only decides which side of the 0.2 s mark a read exactly on it falls, so 20 ms is a judgement, not a measurement.
    static let collapseLatency = 0.02

    /// What the window offers the rule. `replaceable` and `insertable` are Arc's two delegate questions.
    public struct Input: Equatable, Sendable {
        public var area: CGRect
        /// The shown panes' shares.
        public var fractions: [Double]
        /// Whether pane i may be replaced: not when it already shows the dragged tab (Arc 0x1004a338c).
        public var replaceable: [Bool]
        /// Whether the dragged tab may get a slot at all (Arc 0x1004a2a00 also limits the panes and the index, below).
        public var insertable: Bool

        public init(area: CGRect, fractions: [Double], replaceable: [Bool], insertable: Bool) {
            self.area = area
            self.fractions = fractions
            self.replaceable = replaceable
            self.insertable = insertable
        }

        func canReplace(_ pane: Int) -> Bool { replaceable.indices.contains(pane) && replaceable[pane] }
        func canInsert(_ index: Int) -> Bool { insertable && fractions.count < Metrics.content.maxPanes.value && index <= fractions.count }
    }

    /// The last read's outcome and the panes as Arc would have them. A slot that went away stays in the list until its
    /// animation ends, and in that time it still counts as the neighbour of the page.
    public struct State: Equatable, Sendable {
        enum Pane: Equatable, Sendable {
            case page(Int)
            case slot(id: Int, expanded: Bool, removeAt: Double?)

            var isExpanded: Bool {
                switch self {
                case .page: true
                case .slot(_, let expanded, _): expanded
                }
            }
        }

        public internal(set) var target: PageDropTarget?
        public internal(set) var orientation: SplitOrientation
        var panes: [Pane]
        private var slots = 0
        private var pending: CGPoint?
        /// When the throttle's interval ends; nil when it is idle, and then the next position is read at once.
        public internal(set) var nextRead: Double?

        public init(paneCount: Int, orientation: SplitOrientation) {
            panes = (0..<max(paneCount, 1)).map { .page($0) }
            self.orientation = orientation
        }

        /// The panes shown changed under the drag: start again from them.
        public mutating func sync(paneCount: Int, orientation: SplitOrientation) {
            guard pageCount != max(paneCount, 1) else { return }
            self = State(paneCount: paneCount, orientation: orientation)
        }

        var pageCount: Int { panes.reduce(0) { if case .page = $1 { $0 + 1 } else { $0 } } }

        /// True when a read is waiting for `nextRead`.
        public var hasPending: Bool { pending != nil }

        /// The pointer moved to `point` over the page at `now`.
        public mutating func move(to point: CGPoint, at now: Double, _ input: Input) {
            advance(to: now, input)
            if nextRead == nil {
                read(point, at: now, input)
                nextRead = now + PageDropRule.throttle
            } else {
                pending = point
            }
        }

        /// The pointer left the page: every slot goes and nothing is the target (Arc's draggingExited, 0x100a55e80).
        public mutating func leave(at now: Double) {
            pending = nil
            apply(nil, at: now)
        }

        /// Runs what the throttle's timer would have by `now`.
        public mutating func advance(to now: Double, _ input: Input) {
            while let due = nextRead, due <= now {
                if let point = pending {
                    pending = nil
                    read(point, at: due, input)
                    nextRead = due + PageDropRule.throttle
                } else {
                    nextRead = nil
                }
            }
        }

        private mutating func read(_ point: CGPoint, at now: Double, _ input: Input) {
            sweep(at: now)
            apply(PageDropRule.propose(point, in: self, input), at: now)
        }

        private mutating func sweep(at now: Double) {
            panes.removeAll {
                if case .slot(_, _, let removeAt?) = $0 { return removeAt <= now }
                return false
            }
        }

        /// Arc's sink (0x100a4b180): the slot asked for shows and every other one goes.
        mutating func apply(_ proposal: Proposal?, at now: Double) {
            target = proposal?.target
            guard let proposal, let index = proposal.slotIndex else {
                collapseSlots(except: nil, at: now)
                return
            }
            orientation = proposal.orientation
            let id: Int
            if let existing = proposal.existing, case .slot(let existingID, _, _) = existing, let at = panes.firstIndex(of: existing) {
                // A slot already in the list moves there (0x100a55454).
                id = existingID
                panes.remove(at: at)
                panes.insert(existing, at: min(at < index ? index - 1 : index, panes.count))
            } else {
                slots += 1
                id = slots
                panes.insert(.slot(id: id, expanded: true, removeAt: nil), at: min(index, panes.count))
            }
            collapseSlots(except: id, at: now)
            if let at = panes.firstIndex(where: { if case .slot(id, _, _) = $0 { true } else { false } }) { panes[at] = .slot(id: id, expanded: true, removeAt: nil) }
        }

        private mutating func collapseSlots(except kept: Int?, at now: Double) {
            for i in panes.indices {
                guard case .slot(let id, true, _) = panes[i], id != kept else { continue }
                panes[i] = .slot(id: id, expanded: false, removeAt: now + PageDropRule.collapse + PageDropRule.collapseLatency)
            }
        }
    }

    /// One read's outcome: Arc's `ProposedDropTargetInfo { target, dropRegionInsertionIndex, existingDropRegion, layoutOrientation }`.
    struct Proposal: Equatable {
        var target: PageDropTarget
        var slotIndex: Int?
        var existing: State.Pane?
        var orientation: SplitOrientation
    }

    enum Zone: Equatable { case middle, left, right, top, bottom }

    /// The zones of a page pane (Arc 0x100a46638, 0x100a469e0, 0x100a46a88). One page: top and bottom are at most 50 pt
    /// (a quarter of the height when that is less) and are checked first, then 40 percent of the width on each side.
    /// More pages: only the axis they are laid out on, at most 80 pt (a third) across and 50 pt (a third) down.
    /// `y` runs from the top of the pane.
    static func pageZone(x: Double, y: Double, width w: Double, height h: Double, pages: Int, orientation: SplitOrientation) -> Zone {
        if pages <= 1 {
            let margin = min(h * 0.25, 50)
            if y < margin { return .top }
            if h - margin < y { return .bottom }
            let side = w * 0.4
            if x < side { return .left }
            return w - side < x ? .right : .middle
        }
        switch orientation {
        case .vertical:
            let margin = min(h / 3, 50)
            if y < margin { return .top }
            return h - margin < y ? .bottom : .middle
        case .horizontal:
            let side = min(w / 3, 80)
            if x < side { return .left }
            return w - side < x ? .right : .middle
        }
    }

    /// The zones of a slot (Arc 0x100a46af8), only with one page: `.middle` keeps the slot; past 100 pt plus a tenth from its
    /// outer edge the bands along the page turn it into the other axis. `y` runs from the top of the slot.
    static func slotZone(x: Double, y: Double, width w: Double, height h: Double, leading: Bool, orientation: SplitOrientation) -> Zone {
        let band = min(h / 10, 100), sideBand = min(w / 10, 100)
        switch orientation {
        case .vertical:
            // A slot above the page: past `band + 100` from its top; below it: past that from its bottom.
            let fromFar = leading ? y : h - y
            guard band + 100 < fromFar else { return .middle }
            if x < sideBand { return .left }
            return w - sideBand < x ? .right : .middle
        case .horizontal:
            let fromFar = leading ? x : w - x
            guard sideBand + 100 < fromFar else { return .middle }
            if y < band { return .top }
            return h - band < y ? .bottom : .middle
        }
    }

    /// The panes' frames as the list stands: visible ones only, a slot with the mean share of the pages.
    static func frames(_ state: State, _ input: Input) -> [(pane: State.Pane, rect: CGRect)] {
        let shares = input.fractions.isEmpty ? [1.0] : input.fractions
        let mean = shares.reduce(0) { $0 + $1 / Double(shares.count) }
        let visible = state.panes.filter(\.isExpanded)
        let fractions = visible.map { pane -> Double in
            if case .page(let i) = pane, shares.indices.contains(i) { return shares[i] }
            return mean
        }
        let cards = ContentLayout.cards(in: input.area, fractions: fractions, orientation: state.orientation).cards
        return Array(zip(visible, cards)).map { (pane: $0, rect: $1) }
    }

    /// Arc's loop in 0x100a53b60: the pane under the pointer, by its frame with the handle after it (the gap counts as the
    /// leading pane's: at x=752 of Q17 a slot on the left holds and a page on the left does not).
    static func propose(_ point: CGPoint, in state: State, _ input: Input) -> Proposal? {
        let shown = frames(state, input)
        for (position, entry) in shown.enumerated() {
            let last = position == shown.count - 1
            let gap = last ? 0 : Metrics.content.splitGap.value
            var hit = entry.rect
            if state.orientation == .horizontal { hit.size.width += gap } else { hit.size.height += gap }
            guard hit.contains(point) else { continue }
            let x = Double(point.x - hit.minX), y = Double(point.y - hit.minY)
            guard let listIndex = state.panes.firstIndex(of: entry.pane) else { return nil }
            switch entry.pane {
            case .page(let page):
                if let proposal = pageProposal(x: x, y: y, rect: entry.rect, page: page, listIndex: listIndex, state: state, input) { return proposal }
                continue
            case .slot:
                return slotProposal(x: x, y: y, rect: entry.rect, listIndex: listIndex, state: state, input)
            }
        }
        return nil
    }

    private static func pageProposal(x: Double, y: Double, rect: CGRect, page: Int, listIndex: Int, state: State, _ input: Input) -> Proposal? {
        /// The slot next to the page on that side, shown or still collapsing.
        func neighbour(_ step: Int) -> State.Pane? {
            let i = listIndex + step
            guard state.panes.indices.contains(i), case .slot = state.panes[i] else { return nil }
            return state.panes[i]
        }
        let before = neighbour(-1), after = neighbour(1)
        let replacing = input.canReplace(page) ? Proposal(target: .replace(pane: page), slotIndex: nil, existing: nil, orientation: state.orientation) : nil
        let zone = pageZone(x: x, y: y, width: Double(rect.width), height: Double(rect.height), pages: state.pageCount, orientation: state.orientation)
        switch zone {
        case .middle:
            if let replacing { return replacing }
            // The tab already in the pane: the slot before the page, or none once a slot sits there (the index then passes
            // the end). So over its own page the middle flips between a left slot and nothing as the pointer moves (Q17 C, D).
            let index = before == nil ? listIndex : listIndex + 1
            if input.canInsert(index) { return Proposal(target: .insert(index: page), slotIndex: index, existing: nil, orientation: state.orientation) }
            return nil
        case .left, .top, .right, .bottom:
            let leading = zone == .left || zone == .top
            let neighbouring = leading ? before : after
            let insert = leading ? page : page + 1
            let orientation: SplitOrientation = zone == .left || zone == .right ? .horizontal : .vertical
            // A slot already showing on that side: back to the whole page.
            if neighbouring?.isExpanded == true || !input.canInsert(insert) { return replacing }
            return Proposal(target: .insert(index: insert), slotIndex: leading ? listIndex : listIndex + 1, existing: neighbouring, orientation: orientation)
        }
    }

    private static func slotProposal(x: Double, y: Double, rect: CGRect, listIndex: Int, state: State, _ input: Input) -> Proposal? {
        let pages = state.pageCount
        let this = state.panes[listIndex]
        let zone: Zone
        if pages == 1, let page = state.panes.firstIndex(where: { if case .page = $0 { true } else { false } }) {
            zone = slotZone(x: x, y: y, width: Double(rect.width), height: Double(rect.height), leading: listIndex < page, orientation: state.orientation)
        } else {
            zone = .middle
        }
        switch zone {
        case .middle:
            if listIndex == 0 { return Proposal(target: .insert(index: 0), slotIndex: 0, existing: this, orientation: state.orientation) }
            guard case .page(let page) = state.panes[listIndex - 1] else { return nil }
            return Proposal(target: .insert(index: page + 1), slotIndex: listIndex, existing: this, orientation: state.orientation)
        case .left: return Proposal(target: .insert(index: 0), slotIndex: 0, existing: this, orientation: .horizontal)
        case .right: return Proposal(target: .insert(index: 1), slotIndex: state.panes.count, existing: this, orientation: .horizontal)
        case .top: return Proposal(target: .insert(index: 0), slotIndex: 0, existing: this, orientation: .vertical)
        case .bottom: return Proposal(target: .insert(index: 1), slotIndex: state.panes.count, existing: this, orientation: .vertical)
        }
    }

    // MARK: What to draw and what a release does

    public static func preview(_ state: State) -> PageDropPreview {
        guard let target = state.target else { return .none }
        switch target {
        case .replace(let pane): return .frame(pane: pane)
        case .insert:
            var pagesBefore = 0
            for pane in state.panes {
                switch pane {
                case .page: pagesBefore += 1
                case .slot(_, let expanded, _): if expanded { return .slot(before: pagesBefore, orientation: state.orientation) }
                }
            }
            return .none
        }
    }

    /// The shown panes' rectangles and the slot's for the state, in pane order.
    public static func layout(_ state: State, _ input: Input) -> (panes: [CGRect], slot: CGRect?) {
        var panes: [CGRect] = [], slot: CGRect?
        for entry in frames(state, input) {
            if case .page = entry.pane { panes.append(entry.rect) } else { slot = entry.rect }
        }
        return (panes, slot)
    }

    /// The command a release gives: the slot makes a split (`Command.split(.dropTab)`, nil for a tab already shown, which
    /// stays where it is); the frame shows the tab, or in a split it takes that pane (`.split(.replacePane)`, Q17); nothing
    /// shown does nothing.
    public static func releaseCommand(_ state: State, source: ItemID, offer: SplitDropOffer?, paneCount: Int) -> Command? {
        guard let target = state.target else { return nil }
        switch target {
        case .replace(let pane):
            if paneCount > 1, let offer { return .split(.replacePane(offer, pane: pane)) }
            return .tab(.focus(source))
        case .insert(let index):
            guard let offer, case .slot(_, let orientation) = preview(state) else { return nil }
            let leading = index == 0
            let edge: SplitEdge = orientation == .vertical ? (leading ? .top : .bottom) : (leading ? .left : .right)
            let inside = index > 0 && index < paneCount
            return .split(.dropTab(offer, edge: edge, at: inside ? index : nil))
        }
    }
}
