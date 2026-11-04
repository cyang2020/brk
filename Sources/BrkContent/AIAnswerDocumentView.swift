import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

/// Session-only local answer document. Its source buttons open through Brk in the same browsing context.
@MainActor
final class AIAnswerDocumentView: NSView {
    private let dispatch: Dispatch
    private let material = NSVisualEffectView()
    private let heading = NSTextField(labelWithString: "Max · Local CLI")
    private let question = NSTextField(wrappingLabelWithString: "")
    private let scroll = NSScrollView()
    private let text = NSTextView()
    private let close = AIActionButton("Close")
    private let progress = NSProgressIndicator()
    private var sources: [AIActionButton] = []
    private var controls: [AIActionButton] = []
    private var answer: AIAnswerSnapshot?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        setAccessibilityIdentifier("ai-document")
        wantsLayer = true
        layer?.cornerRadius = Metrics.ai.cornerRadius.value
        layer?.masksToBounds = true
        layer?.borderWidth = Metrics.ai.borderWidth.value
        layer?.borderColor = NSColor.separatorColor.cgColor
        material.material = .sidebar; material.blendingMode = .withinWindow; material.state = .active
        heading.font = .systemFont(ofSize: Metrics.ai.headingFont.value, weight: .semibold)
        question.font = .systemFont(ofSize: Metrics.ai.questionFont.value, weight: .medium)
        question.maximumNumberOfLines = 2; question.lineBreakMode = .byTruncatingTail
        text.isEditable = false; text.isSelectable = true; text.isRichText = false
        text.drawsBackground = false; text.textColor = .labelColor
        text.font = .systemFont(ofSize: Metrics.ai.bodyFont.value)
        text.autoresizingMask = [.width]; text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityIdentifier("ai-answer")
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        close.setAccessibilityIdentifier("ai-close")
        close.onPress = { [weak self] in guard let self else { return }; dispatch(.assist(answer?.busy == true ? .cancel : .dismiss)) }
        for view in [material, heading, question, scroll, close, progress] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(_ answer: AIAnswerSnapshot?, in area: CGRect) {
        guard let answer else { self.answer = nil; isHidden = true; progress.stopAnimation(nil); return }
        isHidden = false
        let m = Metrics.ai
        let width = min(m.width.value, max(m.minimumWidth.value, area.width - m.inset.value * 2))
        frame = CGRect(x: area.maxX - width - m.inset.value, y: area.minY + m.inset.value,
                       width: width, height: max(m.minimumHeight.value, area.height - m.inset.value * 2))
        if self.answer != answer {
            self.answer = answer
            question.stringValue = answer.title
            if text.string != answer.text { text.string = answer.text }
            close.title = answer.busy ? "Cancel" : "Close"
            if answer.busy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
            for button in sources + controls { button.removeFromSuperview() }
            sources = answer.sources.enumerated().map { index, source in
                let button = AIActionButton("[\(index + 1)] " + (source.title.isEmpty ? source.url.absoluteString : source.title))
                button.isBordered = false; button.contentTintColor = .linkColor; button.alignment = .left
                button.lineBreakMode = .byTruncatingTail; button.toolTip = source.url.absoluteString
                button.onPress = { [weak self] in self?.dispatch(.commandBar(.submit(source.url.absoluteString))) }
                return button
            }
            controls = []
            func control(_ title: String, _ intent: AIIntent, _ identifier: String) {
                let button = AIActionButton(title); button.setAccessibilityIdentifier(identifier)
                button.onPress = { [weak self] in self?.dispatch(.assist(intent)) }; controls.append(button)
            }
            if answer.canUndo { control("Undo Organize Today", .undoOrganize, "ai-undo") }
            if answer.site != nil { control("Never translate this site", .neverTranslateSite, "ai-never-site") }
            if let language = answer.language, !language.isEmpty { control("Never translate \(language)", .neverTranslateLanguage, "ai-never-language") }
            let settings = AIActionButton("Max Settings…")
            settings.onPress = { [weak self] in self?.dispatch(.settings(.openPane(.max))) }; controls.append(settings)
            for button in sources + controls { addSubview(button) }
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let m = Metrics.ai, pad = m.padding.value, gap = m.gap.value, row = m.buttonHeight.value
        material.frame = bounds
        close.frame = CGRect(x: bounds.width - pad - m.closeWidth.value, y: pad, width: m.closeWidth.value, height: row)
        heading.frame = CGRect(x: pad, y: pad, width: bounds.width - pad * 3 - m.closeWidth.value - row, height: row)
        progress.frame = CGRect(x: close.frame.minX - row - gap, y: pad, width: row, height: row)
        question.frame = CGRect(x: pad, y: pad + row + gap, width: bounds.width - pad * 2, height: m.questionHeight.value)
        var bottom = bounds.height - pad
        for button in (sources + controls).reversed() {
            bottom -= row
            button.frame = CGRect(x: pad, y: bottom, width: bounds.width - pad * 2, height: row)
            bottom -= gap
        }
        let top = question.frame.maxY + gap
        scroll.frame = CGRect(x: pad, y: top, width: bounds.width - pad * 2, height: max(row, bottom - top))
        text.frame.size.width = scroll.contentSize.width
    }
}
@MainActor
private final class AIActionButton: NSButton {
    var onPress: () -> Void = {}
    init(_ title: String) {
        super.init(frame: .zero)
        self.title = title; bezelStyle = .rounded; setButtonType(.momentaryPushIn)
        target = self; action = #selector(pressed)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    @objc private func pressed() { onPress() }
}
