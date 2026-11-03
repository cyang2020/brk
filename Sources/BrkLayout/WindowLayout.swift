import BrkBase
import BrkDomain
import CoreGraphics
import Foundation

// Owner: W1 (layout math). The window, its content area, cards, dividers, the command bar box and window placement.
// The sidebar column's internals are in SidebarLayout.swift (read by W3's views); `WindowFrames.swift` is the frozen
// contract both fill. The ported layout cases (BrkLayoutTests) are the spec.

/// The window's geometry as one pure function of (snapshot, content size). Every number comes from `Metrics`:
/// - sidebar shown: the column spans the full height at its width, the resize handle is 8 wide centred on its edge
///   from 11 below the top to 11 above the bottom, and the content area starts at its edge (10 from the other edges);
/// - sidebar hidden: the content area is the window inset 10 on every side; peeking floats the column 5 in from
///   the left, top and bottom over the content (which does not move); otherwise the reveal strip runs from 2 x 10
///   outside the left edge to 1.5 x 10 inside it;
/// - cards: one per pane (`ContentLayout.cards`), radius 6; an empty card fills the area when nothing is shown;
/// - command bar: `CommandBarLayout.frame`; Peek: `PeekLayout.card` (its round buttons: `PeekLayout.controls`);
/// - Library open: its panel replaces the sidebar, shown or hidden (no sidebar, handle or reveal strip), and the
///   content area, still showing the page, starts 10 right of the panel (`LibraryLayout`).
public enum WindowLayout {
    public static func compute(_ snapshot: WindowSnapshot, contentSize: CGSize) -> WindowFrames {
        if snapshot.kind == .little { return LittleLayout.frames(snapshot, contentSize: contentSize) }
        let inset = Metrics.content.inset.value
        let m = Metrics.sidebar
        let toolbarVisible = snapshot.sidebar.toolbarVisible
        var sidebar: SidebarFrames?
        var floats = false
        var handle: CGRect?
        var reveal: CGRect?
        var anchoredWidth = 0.0

        let libraryOpen: Bool = if case .library? = snapshot.overlay { true } else { false }
        if case .library(let library)? = snapshot.overlay {
            anchoredWidth = LibraryLayout.panelWidth(windowWidth: contentSize.width, sidebarWidth: snapshot.sidebar.width,
                                                     page: library.page, spaces: library.spaces.count)
        } else if snapshot.sidebar.visible {
            anchoredWidth = snapshot.sidebar.width
            let frame = CGRect(x: 0, y: 0, width: anchoredWidth, height: contentSize.height)
            sidebar = SidebarLayout.compute(frame: frame, favorites: snapshot.favorites, space: SidebarLayout.space(in: snapshot), dock: snapshot.dock, headerVisible: snapshot.sidebar.spaceHeaderVisible,
                                            thisWindow: SidebarLayout.listsOwnTabs(snapshot.kind), toolbarVisible: toolbarVisible)
            handle = CGRect(x: frame.maxX - m.resizeHitWidth.value / 2, y: m.resizeHitTop.value,
                            width: m.resizeHitWidth.value, height: max(0, contentSize.height - m.resizeHitBottomTrim.value))
        } else if snapshot.sidebar.peek {
            floats = true
            let frame = CGRect(x: m.floatingInset.value, y: m.floatingInset.value, width: snapshot.sidebar.width,
                               height: contentSize.height - 2 * m.floatingInset.value)
            sidebar = SidebarLayout.compute(frame: frame, favorites: snapshot.favorites, space: SidebarLayout.space(in: snapshot), dock: snapshot.dock, headerVisible: snapshot.sidebar.spaceHeaderVisible,
                                            thisWindow: SidebarLayout.listsOwnTabs(snapshot.kind), toolbarVisible: toolbarVisible)
        } else {
            reveal = CGRect(x: -m.revealOutsideFactor.value * inset, y: 0,
                            width: (m.revealOutsideFactor.value + m.revealInsideFactor.value) * inset, height: contentSize.height)
        }

        // The inset is kept when the sidebar is hidden (Arc keeps 10 pt); beside an anchored sidebar the card starts at
        // its edge (Metrics.content.sidebarGap). The toolbar is the top of the card: the cards start under it.
        let left = anchoredWidth + (sidebar != nil && !floats ? Metrics.content.sidebarGap.value : inset)
        let toolbarHeight = toolbarVisible && !libraryOpen ? AddressToolbarLayout.height : 0
        let toolbar = toolbarHeight > 0 ? CGRect(x: left, y: inset, width: max(0, contentSize.width - left - inset), height: toolbarHeight) : nil
        let contentArea = CGRect(x: left, y: inset + toolbarHeight, width: max(0, contentSize.width - left - inset),
                                 height: max(0, contentSize.height - 2 * inset - toolbarHeight))
        let visiblePanes = snapshot.content.panes.enumerated().filter { !snapshot.content.expanded || $0.element.focused }
        let (rects, dividers) = ContentLayout.cards(in: contentArea, fractions: visiblePanes.map { $0.element.fraction },
                                                    orientation: snapshot.content.orientation)
        let radius = Metrics.content.cornerRadius.value
        let cards: [CardFrame] = snapshot.content.panes.isEmpty
            ? [CardFrame(pane: 0, content: .blank, rect: contentArea, cornerRadius: radius)]
            : zip(visiblePanes, rects).map { pane, rect in
                var card = CardFrame(pane: pane.offset, content: pane.element.content, rect: rect, cornerRadius: radius)
                if snapshot.content.split != nil {
                    card.header = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rect.height, Metrics.content.paneHeaderHeight.value))
                }
                return card
            }

        var commandBar: CGRect?
        var library: LibraryFrames?
        var peek: CGRect?
        switch snapshot.overlay {
        case .commandBar(let bar)?: commandBar = CommandBarLayout.frame(placement: bar.placement, contentArea: contentArea, urlPill: toolbar.map(AddressToolbarLayout.address(in:)) ?? sidebar?.urlPill)
        case .library?:
            library = LibraryLayout.frames(panel: CGRect(x: 0, y: 0, width: anchoredWidth, height: contentSize.height))
        case .peek?: peek = PeekLayout.card(in: contentArea)
        case nil: break
        }

        var result = WindowFrames(contentSize: contentSize, sidebar: sidebar, sidebarFloats: floats, resizeHandle: handle, revealStrip: reveal,
                            contentArea: contentArea, cards: cards, dividers: dividers, commandBar: commandBar, library: library, peek: peek)
        if let find = snapshot.find,
           let card = peek ?? cards.first(where: { $0.content == .page(find.page) })?.page {
            result.find = FindLayout.compute(in: card, replacing: find.replacement, notFound: find.notFound, message: !find.message.isEmpty)
        }
        result.toolbar = toolbar
        return result
    }
}

/// The Library (Arc: `HomeButton`). Owner: F5. While it is open its panel replaces the sidebar at the window's left
/// edge, full height, and the content area beside it keeps showing the page. Arc's panel is max(417, min(window
/// width - 56, stored width)) wide (layout-constants.md "Library (\"home\") panel width"; cra L1548 sees a 347 pt
/// sidebar widen to 417); the Spaces page widens it to hold a card per space and the + button, up to the window
/// minus 56. The panel is a 112 pt navigation column (one 78 pt cell per page, spread evenly between 94 from the top
/// and 104 from the bottom, 100 apart in a 776 pt window; the exit and gift buttons at its foot, the exit where the
/// dock's Library button is, so the same spot opens and closes it) and the open page's column.
public enum LibraryLayout {
    /// The panel's width in a window `windowWidth` wide whose sidebar is `sidebarWidth` wide (its stored width,
    /// also while hidden), showing `page`; `spaces` is how many cards the Spaces page shows.
    public static func panelWidth(windowWidth: Double, sidebarWidth: Double, page: LibraryPage = .media, spaces: Int = 0) -> Double {
        let s = Metrics.sidebar, l = Metrics.library
        let base = max(s.libraryMinWidth.value, min(windowWidth - s.libraryWindowMargin.value, sidebarWidth))
        guard page == .spaces else { return base }
        let cards = Double(max(1, spaces))
        let wanted = l.navWidth.value + l.spacesLeading.value + cards * l.spacesCardWidth.value + (cards - 1) * l.spacesCardGap.value
            + l.spacesTrailing.value
        return max(base, min(wanted, windowWidth - s.libraryWindowMargin.value))
    }

    /// `panel` at the window's left edge (WindowLayout.compute): the navigation column, its cells and the page column.
    public static func frames(panel: CGRect) -> LibraryFrames {
        let l = Metrics.library
        let nav = CGRect(x: panel.minX, y: panel.minY, width: min(l.navWidth.value, panel.width), height: panel.height)
        let count = Double(LibraryPage.allCases.count)
        let span = panel.height - l.navTop.value - l.navBottomReserve.value - l.navCellHeight.value
        let pitch = max(l.navCellHeight.value, (span / max(1, count - 1)).rounded())
        var cells: [LibraryPage: CGRect] = [:]
        for (i, libraryPage) in LibraryPage.allCases.enumerated() {
            cells[libraryPage] = CGRect(x: nav.minX + l.navCellLeading.value, y: nav.minY + l.navTop.value + Double(i) * pitch,
                                        width: l.navCellWidth.value, height: l.navCellHeight.value)
        }
        let page = CGRect(x: nav.maxX, y: panel.minY, width: max(0, panel.maxX - nav.maxX), height: panel.height)
        return LibraryFrames(frame: panel, strip: panel, nav: nav, pageCells: cells, page: page)
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

    /// The gift button (Arc's invitation button) at the bottom right of the navigation column, level with the exit.
    public static func giftButton(in nav: CGRect) -> CGRect {
        let d = Metrics.dock, size = d.buttonSize.value
        return CGRect(x: nav.maxX - Metrics.library.giftTrailing.value - size, y: nav.maxY - d.libraryBottom.value - size,
                      width: size, height: size)
    }
}

/// Little Arc (Arc: `LittleBrowserWindow`), as on Arc 1.170 (the 2026-11-03 capture P21a-c). Without a page the
/// window is the command bar alone: the bar fills it (Metrics.littleArc.commandBarSize). With a page, a header strip
/// (Metrics.littleArc.headerHeight) carries the traffic lights, the host pill and "Open in <space>", and the page
/// fills the rest edge to edge (no inset, no rounded card). No sidebar, no reveal strip, no Peek.
public enum LittleLayout {
    public static func frames(_ snapshot: WindowSnapshot, contentSize: CGSize) -> WindowFrames {
        let bounds = CGRect(origin: .zero, size: contentSize)
        let empty = snapshot.content.panes.isEmpty
        let header = empty ? 0 : min(contentSize.height, Metrics.littleArc.headerHeight.value)
        let area = CGRect(x: 0, y: header, width: contentSize.width, height: max(0, contentSize.height - header))
        let cards = empty
            ? [CardFrame(pane: 0, content: .blank, rect: area, cornerRadius: 0)]
            : snapshot.content.panes.enumerated().filter(\.element.focused).prefix(1).map { CardFrame(pane: $0.offset, content: $0.element.content, rect: area, cornerRadius: 0) }
        var commandBar: CGRect?
        if case .commandBar(let bar)? = snapshot.overlay {
            commandBar = empty ? bounds : CommandBarLayout.frame(placement: bar.placement, contentArea: area, urlPill: nil)
        }
        var result = WindowFrames(contentSize: contentSize, sidebar: nil, sidebarFloats: false, resizeHandle: nil, revealStrip: nil,
                                  contentArea: area, cards: cards, dividers: [], commandBar: commandBar, library: nil, peek: nil)
        if let find = snapshot.find, let card = cards.first(where: { $0.content == .page(find.page) })?.rect {
            result.find = FindLayout.compute(in: card, replacing: find.replacement, notFound: find.notFound, message: !find.message.isEmpty)
        }
        return result
    }

    /// The header's parts in window content coordinates (top-left origin): the traffic lights' origin, the host
    /// pill and the "Open in" button for a window `width` wide whose button is `buttonWidth` wide.
    public static func header(width: Double, buttonWidth: Double) -> (lights: CGPoint, pill: CGRect, openIn: CGRect) {
        let m = Metrics.littleArc
        let openIn = CGRect(x: width - m.openInTrailing.value - buttonWidth, y: m.controlTop.value, width: buttonWidth, height: m.openInHeight.value)
        let pill = CGRect(x: m.pillLeading.value, y: m.controlTop.value, width: max(0, openIn.minX - m.pillGap.value - m.pillLeading.value),
                          height: m.pillHeight.value)
        let lights = CGPoint(x: m.lightsLeading.value, y: m.headerHeight.value / 2 - Metrics.window.trafficLightSize.value / 2)
        return (lights, pill, openIn)
    }

    /// The "Open in" space picker, anchored at the window's top right over the button.
    public static func picker(width: Double, rows: Int) -> CGRect {
        let m = Metrics.littleArc
        let height = m.pickerSearchHeight.value + Double(rows) * m.pickerRowHeight.value
        return CGRect(x: width - m.pickerTrailing.value - m.pickerWidth.value, y: m.pickerTop.value, width: m.pickerWidth.value, height: height)
    }
}

/// The Peek card (Arc: `modalV2`) and the column of round buttons beside it (close, open as tab, open in split),
/// as measured on Arc: the card stands in the content area 105 pt from its left edge and 95 pt from its right, 2 pt
/// from its top and bottom; the buttons sit 13 pt right of the card, the first 7 pt below its top, 44 pt apart. In a
/// narrow content area the side insets shrink so the card keeps at least 300 pt.
public enum PeekLayout {
    public static func card(in area: CGRect) -> CGRect {
        let m = Metrics.peek
        let room = max(0, area.width - 300)
        let total = m.leadingInset.value + m.trailingInset.value
        let scale = total > 0 ? min(1, room / total) : 0
        // Whole points, rounded down so the card never drops under its 300 pt.
        let leading = (m.leadingInset.value * scale).rounded(.down), trailing = (m.trailingInset.value * scale).rounded(.down)
        return CGRect(x: area.minX + leading, y: area.minY + m.verticalInset.value, width: max(0, area.width - leading - trailing),
                      height: max(0, area.height - 2 * m.verticalInset.value))
    }

    /// Close, open as tab, open in split, top to bottom, beside `card`.
    public static func controls(beside card: CGRect) -> [CGRect] {
        let m = Metrics.peek, size = m.controlSize.value
        return (0..<3).map { i in
            CGRect(x: card.maxX + m.controlGap.value, y: card.minY + m.controlTop.value + Double(i) * m.controlPitch.value, width: size, height: size)
        }
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
        let gap = Metrics.content.splitGap.value
        let span = max(0, (orientation == .horizontal ? area.width : area.height) - gap * Double(current.count - 1))
        let origin = orientation == .horizontal ? area.minX : area.minY
        let before = shares[0..<divider].reduce(0, +)
        let pair = shares[divider] + shares[divider + 1]
        let wanted = (position - origin - gap * (Double(divider) + 0.5)) / max(span, 1) - before
        let first = min(max(wanted, minimum), pair - minimum)
        shares[divider] = first
        shares[divider + 1] = pair - first
        return shares
    }
}

/// The command bar box.
public enum CommandBarLayout {
    /// Centered: width min(766, area - 160), or area - 20 when the area is narrower than 766; box 338 tall, at least
    /// 24 from top and bottom, centered both ways in the window (Arc's Cmd+T card spans 257...1023 in a 1280 window
    /// whose content area starts at 238: the window's centre, not the content area's), on whole points. Over the pill
    /// (Cmd+L with the sidebar shown): from the pill's left edge, 1.5 above its top, reaching right over the content,
    /// as wide as the window allows while staying 80 from its right edge, within 100...720; as tall as the box but at
    /// least 24 above the bottom (layout-constants.md "Command bar attached to the toolbar", low confidence). The
    /// visible card inside that box is 350 wide until its input row needs more (`Metrics.commandBar.attachedCardWidth`).
    /// The window's right and bottom edges are the content area's plus the card inset.
    public static func frame(placement: CommandBarPlacement, contentArea: CGRect, urlPill: CGRect?) -> CGRect {
        let m = Metrics.commandBar
        let windowRight = contentArea.maxX + Metrics.content.inset.value
        let windowBottom = contentArea.maxY + Metrics.content.inset.value
        switch placement {
        case .overURLPill where urlPill != nil:
            let pill = urlPill!
            let top = pill.minY + m.attachedTopOffset.value
            let width = min(max(windowRight - m.attachedRightMargin.value - pill.minX, m.attachedMinWidth.value), m.attachedMaxWidth.value)
            let height = max(0, min(m.boxHeight.value, windowBottom - m.minVerticalMargin.value - top))
            return CGRect(x: pill.minX, y: top, width: width, height: height)
        case .centered, .overURLPill:
            let width = contentArea.width < m.width.value ? contentArea.width - m.narrowMargin.value : min(m.width.value, contentArea.width - m.sideMargin.value)
            let height = min(m.boxHeight.value, contentArea.height - 2 * m.minVerticalMargin.value)
            return CGRect(x: windowRight / 2 - width / 2, y: windowBottom / 2 - height / 2, width: max(0, width), height: max(0, height)).integral
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
