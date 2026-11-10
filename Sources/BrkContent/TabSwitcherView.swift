import AppKit
import BrkBase
import BrkDomain
import BrkOverlays
import BrkUIKit

/// Sizes of Arc 1.170's Ctrl+Tab switcher, measured on 2a96a9d7f0:verify/visual-pairs/run-20261103 P09-a/b (2x captures).
let SwitcherMetrics = SwitcherMetricsTable()

struct SwitcherMetricsTable: MetricGroup {
    private static let measured = "7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, Arc captures P09-a/b"
    let maxCards = Metric(5, .anatomy("\(measured): five cards for a longer recent list"))
    let padding = Metric(16.0, .anatomy("\(measured): 16 between the strip's edge and the cards"))
    let slotWidth = Metric(182.0, .anatomy("\(measured): the selection spans x 733 to 1097 px, cards on the same 182 pitch"))
    let slotHeight = Metric(158.0, .anatomy("\(measured): the selection is 158 tall"))
    let stripRadius = Metric(22.0, .anatomy("\(measured): the strip's corners, continuous"))
    let slotRadius = Metric(12.0, .anatomy("\(measured): the selection's corners"))
    let thumbnailInset = Metric(12.0, .anatomy("\(measured): the page image 12 in from the selection"))
    let thumbnailHeight = Metric(105.0, .anatomy("\(measured): page images 157.5 x 105"))
    let thumbnailRadius = Metric(6.0, .anatomy("\(measured): the page image's corners"))
    let titleFromBottom = Metric(21.0, .anatomy("\(measured): the title's capitals end 31.5 above the selection's bottom"))
    let iconInset = Metric(3.0, .anatomy("\(measured): the icon 3 in from the page image's left edge"))
    let iconSize = Metric(14.0, .anatomy("\(measured): 14 pt icons before the titles"))
    let textInset = Metric(23.0, .anatomy("\(measured): titles start 27 in from the page image's left edge (a label draws 2 in)"))
    let titleFontSize = Metric(14.0, .anatomy("\(measured): titles have a 10 pt cap height"))
    let titleRightInset = Metric(7.0, .anatomy("\(measured): \"Long title for tru…\" ends about 10 before the page image's right edge"))
    let windowMargin = Metric(24.0, .guess("the strip keeps 24 from the window's sides, dropping cards in a narrow window"))
    let placeholderRadius = Metric(3.0, .guess("the grey square for a tab without a favicon, a sidebar row's placeholder at 14 pt"))
    /// A page not drawn yet in this session: a grey card with the site's icon in the middle, never a blank card.
    let pagePlaceholderIcon = Metric(28.0, .guess("the icon centred on a card whose page was not drawn yet, twice the title's"))
}

/// The top-right notice (P43-a, Arc's "ChatGPT in the Command Bar not enabled").
let NoticeMetrics = NoticeMetricsTable()

struct NoticeMetricsTable: MetricGroup {
    private static let measured = "7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, Arc capture P43-a"
    let height = Metric(42.0, .anatomy("\(measured): the banner is about 42 tall"))
    let radius = Metric(12.0, .anatomy("\(measured): the banner's corners"))
    let padding = Metric(16.0, .anatomy("\(measured): the message starts about 18 in, a label drawing 2 in"))
    let fontSize = Metric(15.0, .anatomy("\(measured): the message's 11 pt capitals"))
    let linkHeight = Metric(20.0, .anatomy("\(measured): the Preferences link's pill"))
    let linkRadius = Metric(6.0, .guess("the link pill's corners, the size of the command bar's key caps"))
    let linkFontSize = Metric(12.0, .anatomy("\(measured): \"Arc Max Preferences ↗\" is smaller than the message"))
}

/// Owner: tab tools. The Ctrl+Tab switcher as Arc draws it (P09-a/b): a white strip with rounded corners and a shadow,
/// centred in the window, one card per recent tab or split (at most five, the order frozen when the walk began)
/// showing its page and its icon and title; the chosen one sits on a theme-tinted rounded selection and its title is
/// bold. Each Tab press moves the selection right (`.tab(.cycleRecent)`) while the window keeps showing the page the
/// walk started from; releasing Control shows the selected one. The strip slides when the selection passes its last
/// card. Page images come from `PageThumbnails`; a tab not drawn yet in this session shows a grey card with its
/// icon (or a grey square) in the middle.
@MainActor
final class TabSwitcherView: NSView {
    private var cards: [SwitcherCard] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = SwitcherMetrics.stripRadius.value
        layer?.borderWidth = 0.5
        // P09-a: 17% black just under the strip, 9% 37 pt lower, next to nothing above it. The view is flipped, so a
        // positive height drops the shadow.
        shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = 25
            shadow.shadowOffset = NSSize(width: 0, height: 35)
            return shadow
        }()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func render(_ switcher: RecentTabsSnapshot, in bounds: CGRect, palette: Palette, thumbnails: [ItemID: NSImage]) {
        let m = SwitcherMetrics
        let fit = Int((bounds.width - 2 * m.windowMargin.value - 2 * m.padding.value) / m.slotWidth.value)
        let count = max(1, min(m.maxCards.value, switcher.items.count, fit))
        let at = switcher.items.firstIndex { $0.id == switcher.selected } ?? 0
        let start = max(0, min(at - count + 1, switcher.items.count - count))
        let shown = Array(switcher.items[start..<min(switcher.items.count, start + count)])
        let size = CGSize(width: 2 * m.padding.value + Double(shown.count) * m.slotWidth.value, height: 2 * m.padding.value + m.slotHeight.value)
        frame = CGRect(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
        let dark = palette.scheme == .dark
        layer?.backgroundColor = (dark ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1) : NSColor(srgbRed: 0xF9 / 255.0, green: 0xF9 / 255.0, blue: 0xFA / 255.0, alpha: 1)).cgColor
        // P09-a: the strip's 0.5 pt edge reads #AEAEAE on its #F9F9FA, as the command bar's does
        layer?.borderColor = NSColor.black.withAlphaComponent(dark ? 0.5 : 0.3).cgColor
        while cards.count < shown.count {
            let card = SwitcherCard()
            cards.append(card)
            addSubview(card)
        }
        while cards.count > shown.count { cards.removeLast().removeFromSuperview() }
        // P09-a: the selection is the theme's primary color 10% darker (#F2EAE4 -> #DAD1CC).
        let p = palette.accent
        let selection = dark ? NSColor.white.withAlphaComponent(0.14) : NSColor(srgbRed: p.red * 0.9, green: p.green * 0.9, blue: p.blue * 0.9, alpha: 1)
        for (i, (card, item)) in zip(cards, shown).enumerated() {
            card.frame = CGRect(x: m.padding.value + Double(i) * m.slotWidth.value, y: m.padding.value, width: m.slotWidth.value, height: m.slotHeight.value)
            card.show(item, selected: item.id == switcher.selected, image: thumbnails[item.id], selection: selection, dark: dark)
        }
    }
}

/// One card of the switcher: the page image over the icon and title.
@MainActor
private final class SwitcherCard: NSView {
    private let page = NSImageView()
    private let pageShadow = NSView()
    private let pageIcon = NSImageView()
    private let pageSquare = NSView()
    private let icon = NSImageView()
    private let placeholder = NSView()
    private let title = NSTextField(labelWithString: "")
    private var favicon: URL?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = SwitcherMetrics.slotRadius.value
        pageShadow.wantsLayer = true
        pageShadow.layer?.cornerRadius = SwitcherMetrics.thumbnailRadius.value
        pageShadow.layer?.backgroundColor = NSColor.white.cgColor
        pageShadow.layer?.shadowColor = NSColor.black.cgColor
        pageShadow.layer?.shadowOpacity = 0.18
        pageShadow.layer?.shadowRadius = 3
        pageShadow.layer?.shadowOffset = CGSize(width: 0, height: -1)
        page.wantsLayer = true
        page.layer?.cornerCurve = .continuous
        page.layer?.cornerRadius = SwitcherMetrics.thumbnailRadius.value
        page.layer?.masksToBounds = true
        page.layer?.backgroundColor = NSColor.white.cgColor
        page.imageScaling = .scaleAxesIndependently
        icon.imageScaling = .scaleProportionallyUpOrDown
        pageIcon.imageScaling = .scaleProportionallyUpOrDown
        pageSquare.wantsLayer = true
        pageSquare.layer?.cornerCurve = .continuous
        pageSquare.layer?.cornerRadius = SwitcherMetrics.thumbnailRadius.value
        placeholder.wantsLayer = true
        placeholder.layer?.cornerRadius = SwitcherMetrics.placeholderRadius.value
        title.lineBreakMode = .byTruncatingTail
        title.cell?.truncatesLastVisibleLine = true
        for view in [pageShadow, page, pageSquare, pageIcon, placeholder, icon, title] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func show(_ item: RecentTabRow, selected: Bool, image: NSImage?, selection: NSColor, dark: Bool) {
        let m = SwitcherMetrics
        layer?.backgroundColor = selected ? selection.cgColor : nil
        page.image = image
        let ink: NSColor = dark ? .white : .black
        page.layer?.backgroundColor = (image == nil ? ink.withAlphaComponent(0.06) : .white).cgColor
        let inset = m.thumbnailInset.value
        let pageRect = CGRect(x: inset, y: inset, width: bounds.width - 2 * inset, height: m.thumbnailHeight.value)
        page.frame = pageRect
        pageShadow.frame = pageRect
        let big = m.pagePlaceholderIcon.value
        let middle = CGRect(x: (pageRect.midX - big / 2).rounded(), y: (pageRect.midY - big / 2).rounded(), width: big, height: big)
        pageIcon.frame = middle
        pageSquare.frame = middle
        pageSquare.layer?.backgroundColor = ink.withAlphaComponent(0.12).cgColor
        title.font = .systemFont(ofSize: m.titleFontSize.value, weight: selected ? .semibold : .medium)
        title.textColor = ink.withAlphaComponent(selected ? 0.9 : 0.72)
        title.stringValue = item.title
        let centreY = bounds.height - m.titleFromBottom.value
        let side = m.iconSize.value
        icon.frame = CGRect(x: pageRect.minX + m.iconInset.value, y: (centreY - side / 2).rounded(), width: side, height: side)
        placeholder.frame = icon.frame
        placeholder.layer?.backgroundColor = ink.withAlphaComponent(0.12).cgColor
        favicon = item.favicon
        icon.image = nil
        pageIcon.image = nil
        placeholder.isHidden = false
        let drawn = image != nil
        pageSquare.isHidden = drawn
        if let url = item.favicon, let cached = FaviconCache.shared.image(for: url, then: { [weak self] loaded in
            guard let self, self.favicon == url else { return }
            self.icon.image = loaded
            self.placeholder.isHidden = true
            if !drawn { self.pageIcon.image = loaded; self.pageSquare.isHidden = true }
        }) {
            icon.image = cached
            placeholder.isHidden = true
            if !drawn { pageIcon.image = cached; pageSquare.isHidden = true }
        }
        let x = pageRect.minX + m.textInset.value
        let height = title.intrinsicContentSize.height
        title.frame = CGRect(x: x, y: (centreY - height / 2).rounded(), width: max(0, pageRect.maxX - m.titleRightInset.value - x), height: height)
        setAccessibilityElement(true)
        setAccessibilityLabel(item.title)
        setAccessibilitySelected(selected)
    }
}
