import BrkBase
import BrkDomain
import CoreGraphics
import Foundation

// Owner: W1 (layout math). The window, its content area, cards, dividers, the command bar box and window placement.
// The sidebar column's internals are in SidebarLayout.swift (read by W3's views); `WindowFrames.swift` is the frozen
// contract both fill. The ported layout cases (BrkLayoutTests) are the spec.

/// The window's geometry as one pure function of (snapshot, content size). Every number comes from `Metrics`:
/// - sidebar shown: the column spans the full height at its width, the resize handle is 8 wide centred on its edge
///   from 11 below the top to 11 above the bottom, and the content area starts 10 right of it;
/// - sidebar hidden: the content area is the window inset 10 on every side; peeking floats the column 5 in from
///   the left, top and bottom over the content (which does not move); otherwise the reveal strip runs from 2 x 10
///   outside the left edge to 1.5 x 10 inside it;
/// - cards: one per pane (`ContentLayout.cards`), radius 6; an empty card fills the area when nothing is shown;
/// - command bar: `CommandBarLayout.frame`; Peek: the content area inset by Metrics.peek.inset;
/// - Library open: its panel replaces the sidebar, shown or hidden (no sidebar, handle or reveal strip), and the
///   content area starts 10 right of the panel (`LibraryLayout`).
public enum WindowLayout {
    public static func compute(_ snapshot: WindowSnapshot, contentSize: CGSize) -> WindowFrames {
        let inset = Metrics.content.inset.value
        let m = Metrics.sidebar
        var sidebar: SidebarFrames?
        var floats = false
        var handle: CGRect?
        var reveal: CGRect?
        var anchoredWidth = 0.0

        let libraryOpen: Bool = if case .library? = snapshot.overlay { true } else { false }
        if libraryOpen {
            anchoredWidth = LibraryLayout.panelWidth(windowWidth: contentSize.width, sidebarWidth: snapshot.sidebar.width)
        } else if snapshot.sidebar.visible {
            anchoredWidth = snapshot.sidebar.width
            let frame = CGRect(x: 0, y: 0, width: anchoredWidth, height: contentSize.height)
            sidebar = SidebarLayout.compute(frame: frame, favorites: snapshot.favorites, space: SidebarLayout.space(in: snapshot), dock: snapshot.dock)
            handle = CGRect(x: frame.maxX - m.resizeHitWidth.value / 2, y: m.resizeHitTop.value,
                            width: m.resizeHitWidth.value, height: max(0, contentSize.height - m.resizeHitBottomTrim.value))
        } else if snapshot.sidebar.peek {
            floats = true
            let frame = CGRect(x: m.floatingInset.value, y: m.floatingInset.value, width: snapshot.sidebar.width,
                               height: contentSize.height - 2 * m.floatingInset.value)
            sidebar = SidebarLayout.compute(frame: frame, favorites: snapshot.favorites, space: SidebarLayout.space(in: snapshot), dock: snapshot.dock)
        } else {
            reveal = CGRect(x: -m.revealOutsideFactor.value * inset, y: 0,
                            width: (m.revealOutsideFactor.value + m.revealInsideFactor.value) * inset, height: contentSize.height)
        }

        // The inset is kept when the sidebar is hidden (Arc keeps 10 pt).
        let contentArea = CGRect(x: anchoredWidth + inset, y: inset, width: max(0, contentSize.width - anchoredWidth - 2 * inset),
                                 height: max(0, contentSize.height - 2 * inset))
        let (rects, dividers) = ContentLayout.cards(in: contentArea, fractions: snapshot.content.panes.map(\.fraction),
                                                    orientation: snapshot.content.orientation)
        let radius = Metrics.content.cornerRadius.value
        let cards: [CardFrame] = snapshot.content.panes.isEmpty
            ? [CardFrame(pane: 0, content: .blank, rect: contentArea, cornerRadius: radius)]
            : zip(snapshot.content.panes, rects).enumerated().map { i, pair in
                CardFrame(pane: i, content: pair.0.content, rect: pair.1, cornerRadius: radius)
            }

        var commandBar: CGRect?
        var library: LibraryFrames?
        var peek: CGRect?
        switch snapshot.overlay {
        case .commandBar(let bar)?: commandBar = CommandBarLayout.frame(placement: bar.placement, contentArea: contentArea, urlPill: sidebar?.urlPill)
        case .library?:
            library = LibraryLayout.frames(panel: CGRect(x: 0, y: 0, width: anchoredWidth, height: contentSize.height), page: contentArea,
                                           contentSize: contentSize)
        case .peek?: peek = contentArea.insetBy(dx: Metrics.peek.inset.value, dy: Metrics.peek.inset.value)
        case nil: break
        }

        var result = WindowFrames(contentSize: contentSize, sidebar: sidebar, sidebarFloats: floats, resizeHandle: handle, revealStrip: reveal,
                            contentArea: contentArea, cards: cards, dividers: dividers, commandBar: commandBar, library: library, peek: peek)
        if let find = snapshot.find,
           let card = peek ?? cards.first(where: { $0.content == .page(find.page) })?.rect {
            result.find = FindLayout.compute(in: card, replacing: find.replacement)
        }
        return result
    }
}

/// The Library (Arc: `HomeButton`). Owner: F5. While it is open its panel replaces the sidebar at the window's left
/// edge, full height, and the open page fills the content area beside it, where the web page was: Arc's panel is
/// max(417, min(window width - 56, stored width)) wide (layout-constants.md "Library (\"home\") panel width"; cra
/// L1548 sees a 347 pt sidebar widen to 417). The panel lists the pages from under the title row, one sidebar row
/// per page in `LibraryPage.allCases` order; its exit button is where the dock's Library button is, so the same
/// spot opens and closes it. `LibraryFrames.frame` is the whole window (the Library takes it over), `strip` the
/// panel, `page` the content area.
public enum LibraryLayout {
    /// The panel's width in a window `windowWidth` wide whose sidebar is `sidebarWidth` wide (its stored width,
    /// also while hidden).
    public static func panelWidth(windowWidth: Double, sidebarWidth: Double) -> Double {
        let s = Metrics.sidebar
        return max(s.libraryMinWidth.value, min(windowWidth - s.libraryWindowMargin.value, sidebarWidth))
    }

    /// `panel` at the window's left edge and `page` the content area right of it (WindowLayout.compute).
    public static func frames(panel: CGRect, page: CGRect, contentSize: CGSize) -> LibraryFrames {
        let m = Metrics.library, inset = Metrics.tablist.selectionInset.value
        let pitch = m.rowHeight.value + Metrics.tablist.rowSpacing.value
        var cells: [LibraryPage: CGRect] = [:]
        for (i, libraryPage) in LibraryPage.allCases.enumerated() {
            cells[libraryPage] = CGRect(x: panel.minX + inset, y: panel.minY + m.listTop.value + Double(i) * pitch,
                                        width: max(0, panel.width - 2 * inset), height: m.rowHeight.value)
        }
        return LibraryFrames(frame: CGRect(origin: .zero, size: contentSize), strip: panel, pageCells: cells, page: page)
    }

    /// The traffic lights over the panel: where the sidebar puts them (`SidebarLayout`), so they do not move when the
    /// Library opens.
    public static func trafficLightsOrigin(in panel: CGRect) -> CGPoint {
        let w = Metrics.window
        return CGPoint(x: panel.minX + w.trafficLightLeft.value, y: panel.minY + w.trafficLightCenterY.value - w.trafficLightSize.value / 2)
    }

    /// The exit button at the bottom left of the panel: the dock's Library button frame (`SidebarLayout`).
    public static func closeButton(in panel: CGRect) -> CGRect {
        let d = Metrics.dock, size = d.buttonSize.value
        return CGRect(x: panel.minX + d.buttonInset.value, y: panel.maxY - d.libraryBottom.value - size, width: size, height: size)
    }
}

/// Cards and dividers inside the content area.
public enum ContentLayout {
    /// Panes side by side (or stacked for `.vertical`): sizes proportional to `fractions` after removing (n-1) x
    /// splitGap, each rounded to whole points except the last, which takes what is left, so the cards exactly fill
    /// the area. Dividers are the gaps.
    public static func cards(in area: CGRect, fractions: [Double], orientation: SplitOrientation = .horizontal) -> (cards: [CGRect], dividers: [CGRect]) {
        guard !fractions.isEmpty else { return ([], []) }
        let gap = Metrics.content.splitGap.value
        let total = fractions.reduce(0, +)
        let shares = fractions.map { total > 0 ? $0 / total : 1.0 / Double(fractions.count) }
        let span = (orientation == .horizontal ? area.width : area.height) - gap * Double(fractions.count - 1)
        var sizes = shares.map { (span * $0).rounded() }
        sizes[sizes.count - 1] = span - sizes.dropLast().reduce(0, +)
        var cards: [CGRect] = [], dividers: [CGRect] = []
        var cursor = orientation == .horizontal ? area.minX : area.minY
        for (i, size) in sizes.enumerated() {
            if orientation == .horizontal {
                cards.append(CGRect(x: cursor, y: area.minY, width: size, height: area.height))
                if i < sizes.count - 1 { dividers.append(CGRect(x: cursor + size, y: area.minY, width: gap, height: area.height)) }
            } else {
                cards.append(CGRect(x: area.minX, y: cursor, width: area.width, height: size))
                if i < sizes.count - 1 { dividers.append(CGRect(x: area.minX, y: cursor + size, width: area.width, height: gap)) }
            }
            cursor += size + gap
        }
        return (cards, dividers)
    }

    /// Divider drag -> new fractions for `.split(.resize)`, clamped to Metrics.content.minPaneFraction.
    public static func fractions(afterDragging divider: Int, to position: Double, in area: CGRect, current: [Double],
                                 orientation: SplitOrientation = .horizontal) -> [Double] {
        guard current.count >= 2, divider >= 0, divider < current.count - 1 else { return current }
        let minimum = Metrics.content.minPaneFraction.value
        let total = current.reduce(0, +)
        var shares = current.map { total > 0 ? $0 / total : 1.0 / Double(current.count) }
        let span = orientation == .horizontal ? area.width : area.height
        let origin = orientation == .horizontal ? area.minX : area.minY
        let before = shares[0..<divider].reduce(0, +)
        let pair = shares[divider] + shares[divider + 1]
        let wanted = (position - origin) / max(span, 1) - before
        let first = min(max(wanted, minimum), pair - minimum)
        shares[divider] = first
        shares[divider + 1] = pair - first
        return shares
    }
}

/// The command bar box.
public enum CommandBarLayout {
    /// Centered: width min(766, area - 160), or area - 20 when the area is narrower than 766; box 338 tall, at least
    /// 24 from top and bottom, centered both ways in the content area, on whole points. Over the pill (Cmd+L with the
    /// sidebar shown): anchored at the pill's top-left and reaching right over the content, as wide as the window
    /// allows while staying 80 from its right edge, within 100...720; as tall as the box but at least 24 above the
    /// bottom (layout-constants.md "Command bar attached to the toolbar", low confidence). The window's right edge is
    /// the content area's plus the card inset.
    public static func frame(placement: CommandBarPlacement, contentArea: CGRect, urlPill: CGRect?) -> CGRect {
        let m = Metrics.commandBar
        switch placement {
        case .overURLPill where urlPill != nil:
            let pill = urlPill!
            let windowRight = contentArea.maxX + Metrics.content.inset.value
            let windowBottom = contentArea.maxY + Metrics.content.inset.value
            let width = min(max(windowRight - m.attachedRightMargin.value - pill.minX, m.attachedMinWidth.value), m.attachedMaxWidth.value)
            let height = max(0, min(m.boxHeight.value, windowBottom - m.minVerticalMargin.value - pill.minY))
            return CGRect(x: pill.minX, y: pill.minY, width: width, height: height)
        case .centered, .overURLPill:
            let width = contentArea.width < m.width.value ? contentArea.width - m.narrowMargin.value : min(m.width.value, contentArea.width - m.sideMargin.value)
            let height = min(m.boxHeight.value, contentArea.height - 2 * m.minVerticalMargin.value)
            return CGRect(x: contentArea.midX - width / 2, y: contentArea.midY - height / 2, width: max(0, width), height: max(0, height)).integral
        }
    }
}

/// Window frames saved on another display must reopen on screen (regression finding 8).
public enum WindowPlacement {
    /// `saved` and `screens` in AppKit screen coordinates (bottom-left origin). Returns `saved` if it overlaps a
    /// screen's visible frame by at least 100 x 100, else a frame of the same size (clamped to the main screen)
    /// centered on the main screen; nil `saved` -> Metrics.window.defaultSize centered.
    public static func fit(_ saved: CGRect?, screens: [CGRect], main: CGRect) -> CGRect {
        if let saved, screens.contains(where: { screen in
            let overlap = screen.intersection(saved)
            return overlap.width >= 100 && overlap.height >= 100
        }) { return saved }
        let size = saved?.size ?? Metrics.window.defaultSize.value
        let width = min(size.width, main.width), height = min(size.height, main.height)
        return CGRect(x: main.midX - width / 2, y: main.midY - height / 2, width: width, height: height).integral
    }
}
