import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The capsule naming the link under the pointer, at the bottom left of the page's card (P45-a). Chromium's own status
/// bubble is kept from showing (`ChromePage`). Purely informative: it takes no clicks.
@MainActor
final class LinkStatusCapsule: NSView {
    private let label = NSTextField(labelWithString: "")
    private typealias M = LinkStatusMetrics

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.borderWidth = M.edge.value
        layer?.borderColor = NSColor(white: 0xD8 / 255.0, alpha: 1).cgColor
        layer?.backgroundColor = NSColor(white: 0xF0 / 255.0, alpha: 1).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.08
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        label.font = .systemFont(ofSize: M.font.value)
        label.textColor = NSColor(white: 0x4A / 255.0, alpha: 1)
        label.lineBreakMode = .byTruncatingMiddle
        label.isSelectable = false
        addSubview(label)
        setAccessibilityIdentifier("link-status")
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func render(_ status: LinkStatusSnapshot?, frames: WindowFrames) {
        guard let status, let card = frames.cards.first(where: { if case .page(let id) = $0.content { id == status.page } else { false } })?.page else {
            isHidden = true; return
        }
        isHidden = false
        if label.stringValue != status.text { label.stringValue = status.text }
        let height = M.height.value, padding = M.padding.value
        // The label draws its text 2 points inside its frame; the frame keeps a point spare, or a text that just fits gets cut.
        let text = ceil(label.attributedStringValue.size().width)
        let width = min(text + 2 * (padding + 2), max(height, card.width * M.maxWidthShare.value))
        frame = CGRect(x: card.minX + M.inset.value, y: card.maxY - M.bottom.value - height, width: width, height: height)
        layer?.cornerRadius = height / 2
        label.frame = CGRect(x: padding, y: (height - label.intrinsicContentSize.height) / 2, width: width - 2 * padding + 1, height: label.intrinsicContentSize.height)
    }
}

enum LinkStatusMetrics {
    private static let capture = "~/brk-arc-reference/P45/P45-a-arc.png"
    static let inset = Metric(10.0, .anatomy("\(capture): the capsule starts at x 238 pt, the card at 228"))
    static let bottom = Metric(10.5, .anatomy("\(capture): the capsule ends at y 755.5 pt, the card at 766"))
    static let height = Metric(23.5, .anatomy("\(capture): the capsule spans y 732 to 755.5 pt"))
    static let padding = Metric(7.25, .anatomy("\(capture): the words start 9.25 points into the capsule (the label's cell adds 2), which is 233 points wide"))
    static let font = Metric(13.0, .anatomy("\(capture): '127.0.0.1:8764/visual.html?preview=1' is 214 points wide"))
    static let edge = Metric(1.0, .anatomy("\(capture): a 2 px #D8D8D8 edge"))
    static let maxWidthShare = Metric(0.6, .guess("a long address is cut in the middle at this share of the card's width"))
}
