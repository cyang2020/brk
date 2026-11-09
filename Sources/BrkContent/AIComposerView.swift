import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The text the user types in the composer, with its placeholder drawn while it is empty.
@MainActor
final class AIInputTextView: NSTextView {
    var placeholder = "" { didSet { if placeholder != oldValue { needsDisplay = true } } }
    var placeholderColor: NSColor = .placeholderTextColor { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), !placeholder.isEmpty else { return }
        let origin = textContainerOrigin
        let padding = textContainer?.lineFragmentPadding ?? 0
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? .systemFont(ofSize: Metrics.ai.bodyFont.value), .foregroundColor: placeholderColor]
        let width = bounds.width - origin.x * 2 - padding * 2
        (placeholder as NSString).draw(with: CGRect(x: origin.x + padding, y: origin.y, width: max(0, width), height: bounds.height),
                                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}

/// The panel's composer (docs/design/ai-panel.md, "输入框"): one block in the current tab's row style, radius 12, with the
/// chips of the tabs given to the next message at its top, the + menu's button on the left, the text in the middle
/// (growing to about six lines; Return sends, Shift-Return adds a line) and the round send button on the right, the
/// Space's color, which turns into Stop while the agent works. Tabs dragged over the panel outline it in that color.
@MainActor
final class AIComposerView: NSView, NSTextViewDelegate {
    private let back = NSView()
    let input = AIInputTextView(usingTextLayoutManager: false)
    private let scroll = AIPanelScrollView()
    let plus = AIIconButton(symbol: "plus", tip: "", glyph: 13)
    let send = AIIconButton(symbol: "arrow.up", tip: "", glyph: 11)
    private(set) var chips: [AIChipView] = []
    private var style: AIPanelStyle?
    private var busy = false
    private var dropping = false

    /// The text to send, trimmed; the composer is emptied by its owner once sent.
    var onSend: ((String) -> Void)?
    var onStop: (() -> Void)?
    var onPlus: (() -> Void)?
    var onRemoveChip: ((String) -> Void)?
    /// The text changed (the @ list follows it).
    var onChange: ((String) -> Void)?
    /// A key command before the composer's own: the @ list's ↑ ↓ Return Tab Esc. True when it was taken.
    var onCommand: ((Selector) -> Bool)?
    /// The composer's height changed (more lines, chips).
    var onResize: (() -> Void)?
    private var lastHeight: CGFloat = 0

    /// Put before every control's name: a second composer (the conversation list's, "list-") keeps its own names.
    let prefix: String

    init(prefix: String = "") {
        self.prefix = prefix
        super.init(frame: .zero)
        identify(.aiControl(prefix + "composer"))
        back.wantsLayer = true
        back.layer?.cornerRadius = Metrics.tablist.selectionRadius.value
        back.layer?.cornerCurve = .continuous
        input.isRichText = false
        input.importsGraphics = false
        input.allowsUndo = true
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.isAutomaticDashSubstitutionEnabled = false
        input.isAutomaticTextReplacementEnabled = false
        input.font = .systemFont(ofSize: Metrics.ai.bodyFont.value)
        input.drawsBackground = false
        input.textContainerInset = NSSize(width: 0, height: 3)
        input.textContainer?.lineFragmentPadding = 2
        input.textContainer?.widthTracksTextView = true
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]
        input.delegate = self
        input.identify(.aiControl(prefix + "input"))
        scroll.documentView = input
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        plus.identify(.aiControl(prefix + "plus"))
        plus.layer?.cornerRadius = Metrics.ai.plusSize.value / 2
        plus.onPress = { [weak self] in self?.onPlus?() }
        send.weight = .bold
        send.layer?.cornerRadius = Metrics.ai.sendSize.value / 2
        send.onPress = { [weak self] in self?.sendOrStop() }
        for view in [back, scroll, plus, send] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    var text: String {
        get { input.string }
        set { input.string = newValue; input.didChangeText(); needsLayout = true }
    }

    func render(style: AIPanelStyle, copy: AIPanelCopy, placeholder: String, busy: Bool, attached: [AIAttachment]) {
        self.style = style
        self.busy = busy
        input.placeholder = placeholder
        input.placeholderColor = style.color(style.tokens.foreground)
        input.textColor = style.onCard ? style.cardText : style.text
        input.insertionPointColor = style.accent
        input.isEditable = !busy
        back.layer?.backgroundColor = style.composer.cgColor
        back.shadow = style.shadow
        showOutline()
        plus.tint = style.secondary
        plus.hoverFill = style.itemHover
        plus.pressFill = style.itemHover
        plus.tooltip(copy.more)
        send.show(symbol: busy ? "stop.fill" : "arrow.up")
        send.identify(.aiControl(prefix + (busy ? "stop" : "send")))
        send.tooltip(busy ? copy.stop : copy.send)
        send.restFill = style.accent
        send.hoverFill = style.accent.blended(withFraction: 0.12, of: style.scheme == .light ? .black : .white)
        send.tint = style.onAccent
        showChips(attached, style: style, copy: copy)
        needsLayout = true
    }

    private func showOutline() {
        guard let style else { return }
        if dropping {
            back.layer?.borderWidth = Metrics.ai.dropBorderWidth.value
            back.layer?.borderColor = style.accent.cgColor
        } else {
            back.layer?.borderWidth = style.onCard ? 1 : 0
            back.layer?.borderColor = style.separator.cgColor
        }
    }

    /// Tabs are dragged over the panel: the outline says the composer takes them.
    func showDropTarget(_ on: Bool) {
        guard on != dropping else { return }
        dropping = on
        showOutline()
    }

    private func showChips(_ attached: [AIAttachment], style: AIPanelStyle, copy: AIPanelCopy) {
        let titles = attached.map { $0.kind == .tab ? $0.title : "\($0.title) · \($0.tabs.count)" }
        if attached.map(\.id) != chips.map(\.chipID) || titles != chips.map(\.chipTitle) {
            for chip in chips { chip.removeFromSuperview() }
            chips = zip(attached, titles).map { attachment, title in
                let chip = AIChipView(id: attachment.id, title: title, removeTip: copy.removeChip)
                chip.toolTip = attachment.tabs.prefix(12).map { $0.title + ($0.url.map { " — " + $0.absoluteString } ?? "") }.joined(separator: "\n")
                chip.setAccessibilityIdentifier("ai-chip-" + attachment.id)
                chip.remove.identify(.aiControl("chip-remove-" + attachment.id))
                chip.remove.onPress = { [weak self] in self?.onRemoveChip?(attachment.id) }
                addSubview(chip)
                return chip
            }
        }
        for chip in chips { chip.apply(style) }
    }

    private func sendOrStop() {
        if busy { onStop?(); return }
        let message = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        onSend?(message)
    }

    // MARK: Size

    private var lineHeight: CGFloat {
        let font = input.font ?? .systemFont(ofSize: Metrics.ai.bodyFont.value)
        return ceil(input.layoutManager?.defaultLineHeight(for: font) ?? 16)
    }

    private func textHeight(width: CGFloat) -> CGFloat {
        guard let manager = input.layoutManager, let container = input.textContainer else { return lineHeight }
        container.size = NSSize(width: max(20, width), height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let used = max(lineHeight, ceil(manager.usedRect(for: container).height))
        let most = lineHeight * CGFloat(Metrics.ai.composerMaxLines.value)
        return min(used, most) + input.textContainerInset.height * 2
    }

    private func chipLines(width: CGFloat) -> [[(AIChipView, CGFloat)]] {
        guard !chips.isEmpty else { return [] }
        let gap = Metrics.ai.gap.value / 2
        var lines: [[(AIChipView, CGFloat)]] = [[]]
        var x: CGFloat = 0
        for chip in chips {
            let w = min(width, chip.fittingWidth)
            if x > 0, x + w > width { lines.append([]); x = 0 }
            lines[lines.count - 1].append((chip, w))
            x += w + gap
        }
        return lines
    }

    private func textWidth(_ width: CGFloat) -> CGFloat {
        let m = Metrics.ai
        return width - m.composerPadding.value * 2 - m.plusSize.value - m.sendSize.value - m.gap.value
    }

    func preferredHeight(width: CGFloat) -> CGFloat {
        let m = Metrics.ai, pad = m.composerPadding.value
        let lines = chipLines(width: width - pad * 2)
        let chipsHeight = lines.isEmpty ? 0 : CGFloat(lines.count) * m.chipHeight.value + CGFloat(lines.count - 1) * m.gap.value / 2 + m.gap.value / 2
        return pad * 2 + chipsHeight + max(m.sendSize.value, textHeight(width: textWidth(width)))
    }

    override func layout() {
        super.layout()
        let m = Metrics.ai, pad = m.composerPadding.value, gap = m.gap.value
        back.frame = bounds
        var y = pad
        for line in chipLines(width: bounds.width - pad * 2) {
            var x = pad
            for (chip, w) in line {
                chip.frame = CGRect(x: x, y: y, width: w, height: m.chipHeight.value)
                x += w + gap / 2
            }
            y += m.chipHeight.value + gap / 2
        }
        let width = textWidth(bounds.width)
        let height = textHeight(width: width)
        let row = max(m.sendSize.value, height)
        let bottom = bounds.height - pad
        plus.frame = CGRect(x: pad - 3, y: bottom - m.plusSize.value, width: m.plusSize.value, height: m.plusSize.value)
        send.frame = CGRect(x: bounds.width - pad - m.sendSize.value, y: bottom - m.sendSize.value, width: m.sendSize.value, height: m.sendSize.value)
        scroll.frame = CGRect(x: plus.frame.maxX + gap / 2, y: bottom - row + (row - height) / 2, width: max(20, width + 3 - gap / 2), height: height)
        input.frame.size.width = scroll.contentSize.width
        input.minSize = NSSize(width: 0, height: height)
        input.maxSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        input.sizeToFit()
    }

    // MARK: Keys

    func textDidChange(_ notification: Notification) {
        onChange?(input.string)
        let height = preferredHeight(width: bounds.width)
        if abs(height - lastHeight) > 0.5 { lastHeight = height; onResize?() }
        input.scrollRangeToVisible(input.selectedRange())
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // While an input method composes, its keys are its own.
        if textView.hasMarkedText() { return false }
        if onCommand?(selector) == true { return true }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if busy { return true }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            sendOrStop()
            return true
        default:
            return false
        }
    }
}
