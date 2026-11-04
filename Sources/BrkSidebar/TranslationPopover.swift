import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

/// The URL pill's second line (Arc's affordances below the URL, P01-a, P50-b/c): "Share Quote" while text is
/// highlighted (a click copies the link to the highlight); otherwise "Translation Available", which takes no click of
/// its own (a click edits the address, as on the rest of the pill), or "Translated", which underlines under the
/// pointer and opens the translation popover.
@MainActor
final class PillTranslationLine: HoverView {
    private let label = NSTextField(labelWithString: "")
    private let dispatch: Dispatch
    private var state: PillTranslation?
    private var shareQuote = false
    private var palette: Palette?
    private lazy var popover = TranslationPopover(dispatch: dispatch)

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: Draw.pillSubtitleFont.value)
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        addSubview(label)
        identify(.aiControl("pill-translation"))
    }

    func render(_ state: PillTranslation?, shareQuote: Bool = false, palette: Palette) {
        self.state = state
        self.shareQuote = shareQuote
        self.palette = palette
        isHidden = state == nil && !shareQuote
        if state == nil || shareQuote { popover.close() }
        stateChanged()
    }

    private var clickable: Bool {
        if shareQuote { return true }
        if case .translated? = state { return true }
        return false
    }

    /// The width the text needs, so the line's hover area is the word, not the whole pill.
    var textWidth: CGFloat { ceil(label.intrinsicContentSize.width) }

    override func layout() {
        super.layout()
        label.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard clickable else { return nil }
        return super.hitTest(point)
    }

    override func stateChanged() {
        guard let palette, state != nil || shareQuote else { return }
        let text: String = switch (shareQuote, state) {
        case (true, _): AICopy.shareQuote
        case (false, .available?): AICopy.translationAvailable
        case (false, .translating?): AICopy.translating
        case (false, .translated?): AICopy.translated
        case (false, nil): ""
        }
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: Draw.pillSubtitleFont.value), .foregroundColor: palette.ink.text]
        if clickable, isHovered { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        label.attributedStringValue = NSAttributedString(string: text, attributes: attributes)
        setAccessibilityValue(text)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        if shareQuote { dispatch(.page(.shareQuote)); return }
        guard case .translated(let source)? = state else { return }
        popover.show(from: label, source: source)
    }
}

/// Arc's TranslateBubblePopoverView (P50-d): an Aa disc, "Translated from French.", then Options (a grey button with
/// Choose Another Language ›, Never Translate This Site | Language Settings, P50-f) and Use Original (a white,
/// bordered one, P50-e).
@MainActor
final class TranslationPopover: NSObject, NSPopoverDelegate {
    private let dispatch: Dispatch
    private var popover: NSPopover?
    init(dispatch: @escaping Dispatch) { self.dispatch = dispatch }

    func show(from anchor: NSView, source: String) {
        close()
        let content = TranslationPopoverView(source: source, dispatch: { [weak self] command in
            self?.close()
            self?.dispatch(command)
        })
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: Draw.translationPopover.value[0], height: Draw.translationPopover.value[1])
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .aqua)
        popover.delegate = self
        self.popover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    func close() {
        popover?.close()
        popover = nil
    }

    func popoverDidClose(_ notification: Notification) { popover = nil }
}

@MainActor
private final class TranslationPopoverView: NSView {
    private let disc = NSTextField(labelWithString: "Aa")
    private let discFill = NSView()
    private let sentence: NSTextField
    private let options = NSButton(title: AICopy.options, target: nil, action: nil)
    private let original = NSButton(title: AICopy.useOriginal, target: nil, action: nil)
    private let dispatch: Dispatch

    init(source: String, dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        sentence = NSTextField(labelWithString: AICopy.translatedFrom(source))
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: Draw.translationPopover.value[0], height: Draw.translationPopover.value[1])))
        identify(.aiControl("translation-popover"))
        let d = Draw.translationDisc.value
        discFill.wantsLayer = true
        discFill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
        discFill.layer?.cornerRadius = d[2] / 2
        disc.font = .systemFont(ofSize: Draw.rowTitleFont.value, weight: .semibold)
        disc.textColor = NSColor(srgbRed: 0x40 / 255.0, green: 0x4F / 255.0, blue: 0x5B / 255.0, alpha: 1)
        disc.alignment = .center
        sentence.font = .systemFont(ofSize: NSFont.systemFontSize)
        sentence.textColor = NSColor(srgbRed: 0x5C / 255.0, green: 0x5F / 255.0, blue: 0x61 / 255.0, alpha: 1)
        sentence.lineBreakMode = .byTruncatingTail
        for (button, name, filled) in [(options, "translation-options", true), (original, "translation-use-original", false)] {
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = Metrics.urlPill.accessoryRadius.value
            button.layer?.backgroundColor = filled ? NSColor.black.withAlphaComponent(0.08).cgColor : NSColor.white.cgColor
            button.layer?.borderWidth = filled ? 0 : Draw.hairline.value
            button.layer?.borderColor = NSColor(srgbRed: 0xAC / 255.0, green: 0xB3 / 255.0, blue: 0xB8 / 255.0, alpha: 1).cgColor
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
                .foregroundColor: NSColor(srgbRed: 0x5C / 255.0, green: 0x5F / 255.0, blue: 0x61 / 255.0, alpha: 1)])
            button.identify(.aiControl(name))
            button.target = self
        }
        options.action = #selector(showOptions)
        original.action = #selector(useOriginal)
        for view in [discFill, disc, sentence, options, original] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let d = Draw.translationDisc.value, b = Draw.translationButtons.value
        discFill.frame = CGRect(x: d[0], y: d[1], width: d[2], height: d[2])
        let discText = disc.intrinsicContentSize.height
        disc.frame = CGRect(x: d[0], y: d[1] + (d[2] - discText) / 2, width: d[2], height: discText)
        let line = sentence.intrinsicContentSize.height, leading = Draw.translationTextLeading.value
        sentence.frame = CGRect(x: leading, y: d[1] + (d[2] - line) / 2, width: bounds.width - leading - d[0], height: line)
        options.frame = CGRect(x: b[0], y: b[1], width: b[2], height: b[3])
        original.frame = CGRect(x: b[0] + b[2] + b[4], y: b[1], width: b[2], height: b[3])
    }

    @objc private func useOriginal() { dispatch(.assist(.useOriginal)) }

    @objc private func showOptions() {
        let menu = NSMenu()
        let languages = NSMenu()
        for name in AILanguages.targets {
            let item = NSMenuItem(title: name, action: #selector(chooseLanguage(_:)), keyEquivalent: "")
            item.target = self
            languages.addItem(item)
        }
        let another = NSMenuItem(title: AICopy.chooseAnotherLanguage, action: nil, keyEquivalent: "")
        another.submenu = languages
        menu.addItem(another)
        let never = NSMenuItem(title: AICopy.neverTranslateSite, action: #selector(neverTranslate), keyEquivalent: "")
        never.target = self
        menu.addItem(never)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: AICopy.languageSettings, action: #selector(languageSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        // Arc pops it with its first row over the button, from the button's middle (P50-f).
        menu.popUp(positioning: another, at: CGPoint(x: options.frame.midX, y: options.frame.midY - Draw.translationButtons.value[3] / 2), in: self)
    }
    @objc private func chooseLanguage(_ item: NSMenuItem) { dispatch(.assist(.translate(item.title))) }
    @objc private func neverTranslate() { dispatch(.assist(.neverTranslateSite)) }
    @objc private func languageSettings() { dispatch(.assist(.languageSettings)) }
}
