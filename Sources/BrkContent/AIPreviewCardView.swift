import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Arc's 5-Second Preview (HoverCardPopover, P45-a): Shift held over a link for about two seconds puts a light grey box
/// on the link and a white rounded card under it: the summary's bold title, two to four details (an SF Symbol, a bold
/// label and a short line) and a round share button in the bottom right corner. While Max reads the page the card
/// shows the link's host and a spinner; "No preview available" or an actionable failure replaces the details. The
/// pointer may move onto the card (it stays); leaving both closes it.
@MainActor
final class AIPreviewCardView: NSView {
    private let dispatch: Dispatch
    private let highlight = NSView()
    private let card = PreviewCard()
    private var preview: AIPreviewSnapshot?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = NSColor.black.withAlphaComponent(PreviewCardMetrics.highlightAlpha.value).cgColor
        highlight.layer?.cornerRadius = PreviewCardMetrics.highlightRadius.value
        addSubview(highlight)
        addSubview(card)
        card.onHover = { inside in dispatch(.assist(.previewHover(inside))) }
        card.onShare = { dispatch(.assist(.sharePreview)) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    /// Only the card takes the pointer; the page under the highlight and around the card keeps it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return card.frame.contains(local) ? card.hitTest(convert(local, to: card.superview)) ?? card : nil
    }

    func render(_ preview: AIPreviewSnapshot?, frames: WindowFrames) {
        guard let preview, let page = frames.cards.first(where: { if case .page(let id) = $0.content { id == preview.page } else { false } })?.page else {
            self.preview = nil; isHidden = true; return
        }
        isHidden = false
        frame = superview?.bounds ?? .zero
        if self.preview != preview { card.render(preview) }
        self.preview = preview
        let m = PreviewCardMetrics.self
        let link = preview.link.map { $0.offsetBy(dx: page.minX, dy: page.minY) }
        highlight.isHidden = link == nil
        if let link { highlight.frame = link }
        let size = card.fittingSize
        var origin = link.map { CGPoint(x: $0.minX - m.offset.value[0], y: $0.maxY + m.offset.value[1]) }
            ?? CGPoint(x: page.minX + m.offset.value[1] * 3, y: page.minY + m.offset.value[1] * 3)
        // Kept inside the page: a link near the right or bottom edge gets the card to its left or above it.
        origin.x = min(max(page.minX, origin.x), page.maxX - size.width)
        if origin.y + size.height > page.maxY, let link { origin.y = max(page.minY, link.minY - m.offset.value[1] - size.height) }
        card.frame = CGRect(origin: origin, size: size)
    }
}

/// The card itself. Its geometry comes from P45-a (2x pixels halved): 299 points wide, the title at 15.5, the details'
/// icons centred at 21 and their text at 39.5, 19 point lines, 5 points between details, the share button 32 points
/// across, 7 from the right edge and 2.5 from the bottom.
@MainActor
private final class PreviewCard: NSView {
    var onHover: (Bool) -> Void = { _ in }
    var onShare: () -> Void = {}
    private let title = NSTextField(wrappingLabelWithString: "")
    private var rows: [(icon: NSImageView, text: NSTextField)] = []
    private let spinner = NSProgressIndicator()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let share = PreviewShareButton()
    private var tracking: NSTrackingArea?
    private var busy = false

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        let m = PreviewCardMetrics.self
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = m.radius.value
        layer?.backgroundColor = NSColor.white.withAlphaComponent(m.fillAlpha.value).cgColor
        layer?.borderColor = NSColor(srgbRed: 0xE8 / 255.0, green: 0xE8 / 255.0, blue: 0xE8 / 255.0, alpha: 1).cgColor
        layer?.borderWidth = m.edge.value
        shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(m.shadow.value[0])
            shadow.shadowBlurRadius = m.shadow.value[1]
            shadow.shadowOffset = CGSize(width: 0, height: -m.shadow.value[2])
            return shadow
        }()
        title.font = .systemFont(ofSize: m.titleFont.value, weight: .bold)
        title.textColor = PreviewCard.ink
        title.maximumNumberOfLines = 2
        message.font = .systemFont(ofSize: m.textFont.value)
        message.textColor = .secondaryLabelColor
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        for view in [title, spinner, message, share] as [NSView] { addSubview(view) }
        share.onPress = { [weak self] in self?.onShare() }
        identify(.aiControl("preview-card"))
        share.identify(.aiControl("preview-share"))
        title.setAccessibilityIdentifier("ai-preview-title")
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    static let ink = NSColor(srgbRed: 0x1D / 255.0, green: 0x1F / 255.0, blue: 0x1F / 255.0, alpha: 1)

    func render(_ preview: AIPreviewSnapshot) {
        let m = PreviewCardMetrics.self
        title.stringValue = preview.title
        for row in rows { row.icon.removeFromSuperview(); row.text.removeFromSuperview() }
        rows = preview.details.map { detail in
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: detail.icon, accessibilityDescription: nil) ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
            icon.symbolConfiguration = .init(pointSize: m.iconSize.value, weight: .regular)
            icon.contentTintColor = NSColor(srgbRed: 0x9A / 255.0, green: 0xA0 / 255.0, blue: 0xA3 / 255.0, alpha: 1)
            let text = NSTextField(wrappingLabelWithString: "")
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = m.lineHeight.value; style.maximumLineHeight = m.lineHeight.value
            let body = NSMutableAttributedString(string: detail.label + " ", attributes: [.font: NSFont.systemFont(ofSize: m.textFont.value, weight: .bold), .foregroundColor: PreviewCard.ink, .paragraphStyle: style])
            body.append(NSAttributedString(string: detail.info, attributes: [.font: NSFont.systemFont(ofSize: m.textFont.value), .foregroundColor: PreviewCard.ink, .paragraphStyle: style]))
            text.attributedStringValue = body
            text.setAccessibilityIdentifier("ai-preview-detail")
            addSubview(icon); addSubview(text)
            return (icon, text)
        }
        message.stringValue = preview.failure ?? ""
        message.isHidden = preview.failure == nil
        busy = preview.busy
        spinner.isHidden = !busy
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        needsLayout = true
    }

    override var fittingSize: NSSize {
        let m = PreviewCardMetrics.self
        return NSSize(width: m.width.value, height: contentBottom(layingOut: false) + m.footer.value)
    }

    /// Lays out the title and the details top to bottom; the bottom of the last one.
    @discardableResult
    private func contentBottom(layingOut: Bool) -> CGFloat {
        let m = PreviewCardMetrics.self, width = m.width.value
        let titleWidth = width - m.titleInset.value * 2
        let titleHeight = title.sizeThatFits(NSSize(width: titleWidth, height: .greatestFiniteMagnitude)).height
        if layingOut { title.frame = CGRect(x: m.titleInset.value, y: m.top.value, width: titleWidth, height: titleHeight) }
        var y = m.top.value + titleHeight + m.titleGap.value
        let textWidth = width - m.textLeading.value - m.textTrailing.value
        if busy {
            if layingOut { spinner.frame = CGRect(x: m.titleInset.value, y: y, width: m.iconSize.value, height: m.iconSize.value) }
            y += m.lineHeight.value
        }
        for row in rows {
            let height = row.text.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height
            if layingOut {
                row.text.frame = CGRect(x: m.textLeading.value, y: y, width: textWidth, height: height)
                row.icon.frame = CGRect(x: m.iconCenter.value - m.iconBox.value / 2, y: y + (m.lineHeight.value - m.iconBox.value) / 2, width: m.iconBox.value, height: m.iconBox.value)
            }
            y += height + m.detailGap.value
        }
        if !message.isHidden {
            let height = message.sizeThatFits(NSSize(width: titleWidth, height: .greatestFiniteMagnitude)).height
            if layingOut { message.frame = CGRect(x: m.titleInset.value, y: y, width: titleWidth, height: height) }
            y += height + m.detailGap.value
        }
        return y
    }

    override func layout() {
        super.layout()
        contentBottom(layingOut: true)
        let m = PreviewCardMetrics.self, button = m.share.value
        share.frame = CGRect(x: bounds.width - button[1] - button[0], y: bounds.height - button[2] - button[0], width: button[0], height: button[0])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { onHover(false) } }
}

/// The card's round share button: a grey edge around Arc's share glyph.
@MainActor
private final class PreviewShareButton: NSView {
    var onPress: () -> Void = {}
    private let glyph = NSImageView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.borderWidth = PreviewCardMetrics.edge.value
        layer?.borderColor = NSColor(srgbRed: 0xC8 / 255.0, green: 0xC8 / 255.0, blue: 0xC8 / 255.0, alpha: 1).cgColor
        layer?.backgroundColor = NSColor(srgbRed: 0xF7 / 255.0, green: 0xF7 / 255.0, blue: 0xF7 / 255.0, alpha: 1).cgColor
        glyph.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
        glyph.symbolConfiguration = .init(pointSize: PreviewCardMetrics.iconSize.value, weight: .regular)
        glyph.contentTintColor = NSColor(srgbRed: 0x8E / 255.0, green: 0x8E / 255.0, blue: 0x8E / 255.0, alpha: 1)
        addSubview(glyph)
        toolTip = "Copy Link"
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
        glyph.frame = bounds
    }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress() } }
}

/// P45-a in points (the 2x pixels halved): the card at x 373 under the link box ending at y 99.5, the card 299 wide.
enum PreviewCardMetrics {
    private static let capture = "verify/visual-pairs/run-20261103/P45/P45-a-arc.png"
    static let width = Metric(299.0, .anatomy("\(capture): the card spans x 746 to 1344 px"))
    static let offset = Metric([6.0, 6.5], .anatomy("\(capture): the link box starts at x 758 px and ends at y 199 px; the card starts at x 746 px, y 212 px"))
    static let radius = Metric(12.0, .anatomy("\(capture): the card's corners round over about 24 px"))
    static let edge = Metric(1.0, .anatomy("\(capture): a 1 pt #E8E8E8 edge"))
    static let fillAlpha = Metric(0.94, .anatomy("\(capture): the page's heading shows faintly through the card"))
    static let shadow = Metric([0.12, 14.0, 3.0], .guess("a soft popover shadow; the capture shows a faint halo"))
    static let top = Metric(15.0, .anatomy("\(capture): the title's capitals span y 246 to 270 px in the card at 212 px"))
    static let titleInset = Metric(15.5, .anatomy("\(capture): the title starts at x 777 px"))
    static let titleFont = Metric(13.0, .anatomy("\(capture): bold capitals 19 px tall"))
    static let titleGap = Metric(7.0, .anatomy("\(capture): the first detail's line is centred at y 307 px, the title at 259 px"))
    static let textFont = Metric(13.0, .anatomy("\(capture): the details' capitals are 19 px tall"))
    static let lineHeight = Metric(19.0, .anatomy("\(capture): a detail's two lines are centred 38 px apart"))
    static let detailGap = Metric(5.0, .anatomy("\(capture): details start 86 px apart with two 38 px lines each"))
    static let textLeading = Metric(39.5, .anatomy("\(capture): the details' text starts at x 825 px"))
    static let textTrailing = Metric(28.0, .anatomy("\(capture): the longest line ends at x 1260 px"))
    static let iconCenter = Metric(21.0, .anatomy("\(capture): the icons are centred at x 788 px"))
    static let iconBox = Metric(17.0, .anatomy("\(capture): the eye spans x 772 to 804 px"))
    static let iconSize = Metric(13.0, .guess("the icons' symbol size"))
    static let footer = Metric(44.5, .anatomy("\(capture): the last line ends at y 410 px, the card at 711 px with the share button in between"))
    static let share = Metric([32.0, 7.0, 2.5], .anatomy("\(capture): the share button spans x 1266 to 1330 px and y 644 to 706 px"))
    static let highlightAlpha = Metric(0.07, .anatomy("\(capture): the hovered link's box is #ECF0EF on white"))
    static let highlightRadius = Metric(3.0, .guess("the link box's slightly rounded corners"))
}
