import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// One row of a transcript as the panel draws it (docs/design/ai-panel.md, "对话内容"): what the user said on the right,
/// the agent's answer straight on the background, a run of steps folded into one plain line, a notice as a centred pill,
/// a page as a card, and an answer's sources and actions.
enum AITranscriptRow: Equatable {
    case user(String)
    case answer(String)
    /// Steps in a row with the approvals answered among them; `key` is the run's first step, so its open state stays.
    case steps(key: String, items: [AIConversationItem])
    case notice(String)
    case page(AIPageSnapshot)
    case actions([AIAnswerAction])

    /// The rows for an answer: its conversation's items, else its plain text; then its sources and actions.
    static func rows(_ answer: AIAnswerSnapshot, actions: [AIAnswerAction]) -> [AITranscriptRow] {
        var rows: [AITranscriptRow] = []
        if let conversation = answer.conversation {
            var run: [AIConversationItem] = []
            // A page made in the middle of a run of steps shows after the run: one line for the steps, then the page.
            var held: [AIPageSnapshot] = []
            func flush() {
                if let first = run.first {
                    let key: String = switch first { case .step(let step): step.id; case .approval(let approval): approval.id; default: "run" }
                    rows.append(.steps(key: key, items: run))
                    run = []
                }
                rows += held.map(AITranscriptRow.page)
                held = []
            }
            for item in conversation.items {
                switch item {
                case .step: run.append(item)
                case .approval(let approval):
                    // One still waiting shows as the card over the composer.
                    if approval.answer != nil { run.append(item) }
                case .user(let text): flush(); rows.append(.user(text))
                case .assistant(let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { flush(); rows.append(.answer(trimmed)) }
                case .notice(let text): flush(); rows.append(.notice(text))
                case .page(let ref):
                    guard let page = answer.pages.first(where: { $0.id == ref.id }) else { continue }
                    if run.isEmpty { flush(); rows.append(.page(page)) } else { held.append(page) }
                }
            }
            flush()
        } else if !answer.text.isEmpty {
            rows.append(.answer(answer.text))
        }
        if !actions.isEmpty { rows.append(.actions(actions)) }
        return rows
    }
}

/// A source of a plain answer, or one of its actions (Undo Organize Today, Never translate…).
struct AIAnswerAction: Equatable {
    let id: String
    let title: String
    let tip: String?
    let link: Bool
    let command: Command
}

/// The transcript's rows, top to bottom, `Metrics.ai.itemGap` apart, in a flipped document view of the transcript's
/// scroll view. Rows of the same kind are updated where they are, so text that streams in and the pages keep their views.
@MainActor
final class AITranscriptView: NSView {
    private(set) var rows: [AITranscriptRow] = []
    private var views: [NSView] = []
    let pages: TranscriptPages
    private var expanded: Set<String> = []
    private var style: AIPanelStyle?
    private var copy = AIPanelCopy([])
    private var context: (agent: String?, folder: String?) = (nil, nil)
    var onLink: ((URL) -> Void)?
    var onKeep: ((AIPageID) -> Void)?
    var onAction: ((Command) -> Void)?
    /// A row's height changed by itself (a step run opened, a page reported its height).
    var onResize: (() -> Void)?

    init() {
        pages = TranscriptPages()
        super.init(frame: .zero)
        pages.host = self
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func show(_ rows: [AITranscriptRow], style: AIPanelStyle, copy: AIPanelCopy, agent: String?, folder: String?) {
        let restyled = style != self.style
        self.style = style
        self.copy = copy
        context = (agent, folder)
        var next: [NSView] = []
        var stepRun = 0, userMessage = 0
        for (index, row) in rows.enumerated() {
            let old = index < views.count ? views[index] : nil
            let view: NSView
            switch row {
            case .user(let text):
                let bubble = old as? AIBubbleView ?? AIBubbleView()
                bubble.identify(.aiControl("user-\(userMessage)"))
                userMessage += 1
                bubble.show(text, style: style)
                view = bubble
            case .answer(let text):
                let answer = old as? AIAnswerView ?? AIAnswerView()
                answer.onLink = { [weak self] url in self?.onLink?(url) }
                answer.show(text, style: style)
                view = answer
            case .steps(let key, let items):
                let steps = old as? AIStepsView ?? AIStepsView()
                steps.identify(.aiControl("steps-\(stepRun)"))
                stepRun += 1
                steps.onToggle = { [weak self] in
                    guard let self else { return }
                    if self.expanded.remove(key) == nil { self.expanded.insert(key) }
                    self.show(self.rows, style: style, copy: self.copy, agent: self.context.agent, folder: self.context.folder)
                    self.onResize?()
                }
                steps.show(items, open: expanded.contains(key), style: style, language: copy.language, agent: agent, folder: folder)
                view = steps
            case .notice(let text):
                let notice = old as? AINoticeView ?? AINoticeView()
                notice.show(text, style: style)
                view = notice
            case .page(let page):
                let card = (old as? AIPageRowView).flatMap { $0.page == page.id ? $0 : nil } ?? AIPageRowView(page: page.id)
                card.onKeep = { [weak self] in self?.onKeep?(page.id) }
                card.show(page, view: pages.view(for: page), height: pages.height(page), style: style, copy: copy)
                view = card
            case .actions(let actions):
                let list = old as? AIActionsView ?? AIActionsView()
                list.show(actions, style: style) { [weak self] command in self?.onAction?(command) }
                view = list
            }
            if view !== old {
                old?.removeFromSuperview()
                addSubview(view)
            }
            next.append(view)
        }
        for view in views.dropFirst(rows.count) where !next.contains(where: { $0 === view }) { view.removeFromSuperview() }
        views = next
        self.rows = rows
        pages.keep(only: Set(rows.compactMap { if case .page(let page) = $0 { page.id } else { nil } }))
        if restyled { needsLayout = true }
    }

    /// Lays the rows out `width` wide and returns the height they take.
    @discardableResult
    func place(width: CGFloat) -> CGFloat {
        let m = Metrics.ai, gap = m.itemGap.value
        var y: CGFloat = 0
        for (row, view) in zip(rows, views) {
            if y > 0 { y += gap }
            let height: CGFloat
            switch (row, view) {
            case (.user, let bubble as AIBubbleView):
                let size = bubble.size(maxWidth: (width * m.bubbleMaxShare.value).rounded(.down))
                bubble.frame = CGRect(x: width - size.width, y: y, width: size.width, height: size.height)
                height = size.height
            case (.notice, let notice as AINoticeView):
                let size = notice.size(maxWidth: width)
                notice.frame = CGRect(x: ((width - size.width) / 2).rounded(), y: y, width: size.width, height: size.height)
                height = size.height
            case (_, let part as AITranscriptPart):
                height = part.height(width: width)
                view.frame = CGRect(x: 0, y: y, width: width, height: height)
            default:
                height = 0
            }
            y += height
        }
        return y
    }
}

/// A row whose height follows from its width.
@MainActor
protocol AITranscriptPart: NSView {
    func height(width: CGFloat) -> CGFloat
}

/// What the user said: the sidebar's current row, on the right (on the tab's card, the URL pill's fill).
@MainActor
final class AIBubbleView: NSView {
    private let fill = NSView()
    private let label = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        fill.wantsLayer = true
        fill.layer?.cornerRadius = Metrics.tablist.selectionRadius.value
        fill.layer?.cornerCurve = .continuous
        label.font = .systemFont(ofSize: Metrics.ai.bodyFont.value)
        label.isSelectable = true
        label.drawsBackground = false
        addSubview(fill)
        addSubview(label)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func show(_ text: String, style: AIPanelStyle) {
        if label.stringValue != text { label.stringValue = text }
        label.textColor = style.onCard ? style.cardText : style.text
        fill.layer?.backgroundColor = style.bubble.cgColor
        fill.shadow = style.onCard ? nil : style.shadow
    }

    func size(maxWidth: CGFloat) -> CGSize {
        let pad = Metrics.ai.bubblePadding.value
        let inner = max(20, maxWidth - pad.width * 2)
        let fits = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner, height: 10_000)) ?? .zero
        return CGSize(width: ceil(min(inner, fits.width)) + pad.width * 2, height: ceil(fits.height) + pad.height * 2)
    }

    override func layout() {
        super.layout()
        let pad = Metrics.ai.bubblePadding.value
        fill.frame = bounds
        label.frame = bounds.insetBy(dx: pad.width, dy: pad.height)
    }
}

/// The agent's answer: its Markdown as text, straight on the background, selectable, links in the Space's color.
@MainActor
final class AIAnswerView: NSView, AITranscriptPart, NSTextViewDelegate {
    /// TextKit 1: the answers' tables are text tables.
    private let text = NSTextView(usingTextLayoutManager: false)
    private var shown: (String, AIPanelStyle)?
    var onLink: ((URL) -> Void)?

    init() {
        super.init(frame: .zero)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.drawsBackground = false
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = true
        text.isVerticallyResizable = false
        text.isHorizontallyResizable = false
        text.delegate = self
        addSubview(text)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func show(_ markdown: String, style: AIPanelStyle) {
        guard shown?.0 != markdown || shown?.1 != style else { return }
        shown = (markdown, style)
        let color = style.onCard ? style.cardText : style.text
        text.textStorage?.setAttributedString(AIConversationText.markdown(markdown, size: Metrics.ai.bodyFont.value, color: color, style: style))
        text.linkTextAttributes = [.foregroundColor: style.accent, .cursor: NSCursor.pointingHand]
        needsLayout = true
    }

    func height(width: CGFloat) -> CGFloat {
        text.frame = CGRect(x: 0, y: 0, width: width, height: 10_000)
        text.textContainer?.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        guard let manager = text.layoutManager, let container = text.textContainer else { return 0 }
        manager.ensureLayout(for: container)
        let height = ceil(manager.usedRect(for: container).height)
        text.frame.size.height = height
        return height
    }

    override func layout() {
        super.layout()
        text.frame = bounds
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let address = (link as? URL)?.absoluteString ?? link as? String
        if let address, let url = URL(string: address) { onLink?(url) }
        return true
    }
}

/// A run of steps as one plain line on the URL pill's fill, "✓ 读了 3 个 tab，做了一个页面 ›"; a click opens the list of
/// each step under it.
@MainActor
final class AIStepsView: NSView, AITranscriptPart {
    private let summary = AIControl()
    private let line = aiLabel(Metrics.ai.stepFont.value)
    private var lines: [NSTextField] = []
    private var open = false
    var onToggle: (() -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Metrics.ai.itemRadius.value
        layer?.cornerCurve = .continuous
        summary.layer?.cornerRadius = Metrics.ai.itemRadius.value
        summary.addSubview(line)
        summary.onPress = { [weak self] in self?.onToggle?() }
        addSubview(summary)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func show(_ items: [AIConversationItem], open: Bool, style: AIPanelStyle, language: AILanguage, agent: String?, folder: String?) {
        self.open = open
        let steps = items.compactMap { if case .step(let step) = $0 { step } else { nil } }
        let failed = steps.filter { $0.state == .failed }.count
        let mark = steps.contains { $0.state == .running } ? "⋯" : failed == steps.count && !steps.isEmpty ? "✗" : "✓"
        var words = steps.isEmpty ? answered(items, language: language, agent: agent, folder: folder).first ?? "" : AIStepWords.summary(steps, language)
        if let first = words.first, !steps.isEmpty, language == .en { words = first.uppercased() + words.dropFirst() }
        if failed > 0, failed < steps.count { words += " · " + AIPanelCopy.failed(failed, language) }
        line.stringValue = mark + " " + words + (open ? " ⌄" : " ›")
        line.textColor = style.secondary
        summary.setAccessibilityLabel(line.stringValue)
        layer?.backgroundColor = style.item.cgColor
        summary.hoverFill = style.itemHover
        summary.pressFill = style.itemHover
        let detail: [String] = open ? items.compactMap { item in
            switch item {
            case .step(let step):
                let mark = switch step.state { case .running: "⋯"; case .done: "✓"; case .failed: "✗" }
                return mark + " " + AIStepWords.title(step, language)
            case .approval(let approval):
                guard let answer = approval.answer, let option = approval.options.first(where: { $0.id == answer }) else { return nil }
                return "· " + AIStepWords.answered(approval, option: option, agent: agent, folder: folder, language)
            default: return nil
            }
        } : []
        while lines.count < detail.count {
            let label = aiLabel(Metrics.ai.stepFont.value)
            addSubview(label)
            lines.append(label)
        }
        for (i, label) in lines.enumerated() {
            label.isHidden = i >= detail.count
            if i < detail.count { label.stringValue = detail[i]; label.toolTip = detail[i]; label.textColor = style.secondary }
        }
        needsLayout = true
    }

    private func answered(_ items: [AIConversationItem], language: AILanguage, agent: String?, folder: String?) -> [String] {
        items.compactMap { item in
            guard case .approval(let approval) = item, let answer = approval.answer, let option = approval.options.first(where: { $0.id == answer }) else { return nil }
            return AIStepWords.answered(approval, option: option, agent: agent, folder: folder, language)
        }
    }

    func height(width: CGFloat) -> CGFloat {
        let m = Metrics.ai
        let shown = lines.filter { !$0.isHidden }.count
        return m.stepHeight.value + (shown > 0 ? CGFloat(shown) * m.stepRowHeight.value + m.menuPadding.value * 2 : 0)
    }

    override func layout() {
        super.layout()
        let m = Metrics.ai, pad = m.gap.value + 2
        summary.frame = CGRect(x: 0, y: 0, width: bounds.width, height: m.stepHeight.value)
        let lineHeight = ceil(line.intrinsicContentSize.height)
        line.frame = CGRect(x: pad, y: ((m.stepHeight.value - lineHeight) / 2).rounded(), width: max(0, bounds.width - pad * 2), height: lineHeight)
        var y = m.stepHeight.value + m.menuPadding.value
        for label in lines where !label.isHidden {
            label.frame = CGRect(x: pad + 4, y: y + ((m.stepRowHeight.value - lineHeight) / 2).rounded(), width: max(0, bounds.width - pad * 2 - 4), height: lineHeight)
            y += m.stepRowHeight.value
        }
    }
}

extension AIPanelCopy {
    static func failed(_ n: Int, _ language: AILanguage) -> String { language == .zh ? "\(n) 步没成功" : "\(n) failed" }
}

/// Brk's own notice, centred on the URL pill's fill: "11:32 已更新 · 水壶降了 €4.50".
@MainActor
final class AINoticeView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        label.font = .systemFont(ofSize: Metrics.ai.noticeFont.value)
        label.alignment = .center
        label.isSelectable = true
        label.drawsBackground = false
        addSubview(label)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func show(_ text: String, style: AIPanelStyle) {
        if label.stringValue != text { label.stringValue = text }
        label.textColor = style.secondary
        layer?.backgroundColor = style.item.cgColor
        setAccessibilityLabel(text)
    }

    func size(maxWidth: CGFloat) -> CGSize {
        let pad: CGFloat = 9
        let fits = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(20, maxWidth - pad * 2), height: 10_000)) ?? .zero
        let height = max(Metrics.ai.noticeHeight.value, ceil(fits.height) + 4)
        layer?.cornerRadius = height <= Metrics.ai.noticeHeight.value ? height / 2 : Metrics.ai.itemRadius.value
        return CGSize(width: min(maxWidth, ceil(fits.width) + pad * 2), height: height)
    }

    override func layout() {
        super.layout()
        let height = ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: bounds.width - 18, height: 10_000)).height ?? 14)
        label.frame = CGRect(x: 9, y: ((bounds.height - height) / 2).rounded(), width: bounds.width - 18, height: height)
    }
}

/// A page in an answer, as a web card: a row with its name and how often it updates and an icon that keeps it as a tab
/// (shows its tab once kept), the page under it at the panel's width.
@MainActor
final class AIPageRowView: NSView, AITranscriptPart {
    let page: AIPageID
    private let card = AIFlippedView()
    private let shadowBack = NSView()
    private let title = aiLabel(Metrics.ai.stepFont.value, weight: .semibold)
    private let schedule = aiLabel(Metrics.ai.noticeFont.value)
    private let keep: AIIconButton
    private let rule = NSView()
    private weak var sandbox: PageSandboxView?
    private var pageHeight: CGFloat = 0
    var onKeep: (() -> Void)?

    init(page: AIPageID) {
        self.page = page
        keep = AIIconButton(symbol: "arrow.up.right.square", tip: "")
        super.init(frame: .zero)
        identify(.aiControl("page-row-" + page.rawValue))
        shadowBack.wantsLayer = true
        shadowBack.layer?.cornerRadius = Metrics.content.cornerRadius.value
        shadowBack.layer?.cornerCurve = .continuous
        card.wantsLayer = true
        card.layer?.cornerRadius = Metrics.content.cornerRadius.value
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        rule.wantsLayer = true
        keep.identify(.aiControl("keep-" + page.rawValue))
        keep.layer?.cornerRadius = Metrics.ai.iconRadius.value
        keep.onPress = { [weak self] in self?.onKeep?() }
        addSubview(shadowBack)
        addSubview(card)
        for view in [title, schedule, rule, keep] as [NSView] { card.addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func show(_ snapshot: AIPageSnapshot, view: PageSandboxView, height: Int, style: AIPanelStyle, copy: AIPanelCopy) {
        if view.superview !== card { card.addSubview(view, positioned: .below, relativeTo: rule) }
        sandbox = view
        pageHeight = CGFloat(height)
        title.stringValue = snapshot.title
        title.textColor = style.cardText
        title.toolTip = snapshot.title
        schedule.stringValue = snapshot.schedule.map { "· " + copy.schedule($0) } ?? ""
        schedule.textColor = style.cardText.withAlphaComponent(0.5)
        keep.tooltip(snapshot.kept ? copy.showTab : copy.keepTip)
        keep.tint = style.cardText.withAlphaComponent(0.55)
        keep.hoverFill = style.scheme == .light ? NSColor(white: 0, alpha: 0.06) : NSColor(white: 1, alpha: 0.1)
        card.layer?.backgroundColor = style.card.cgColor
        shadowBack.layer?.backgroundColor = style.card.cgColor
        shadowBack.shadow = Self.cardShadow
        shadowBack.isHidden = !Metrics.content.showsShadow.value || style.onCard
        if style.onCard { card.layer?.borderWidth = 1; card.layer?.borderColor = style.separator.cgColor } else { card.layer?.borderWidth = 0 }
        rule.layer?.backgroundColor = style.separator.cgColor
        needsLayout = true
    }

    /// The web card's shadow (ShadowView's numbers).
    private static var cardShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(Metrics.content.shadowOpacity.value)
        shadow.shadowBlurRadius = Metrics.content.shadowRadius.value
        shadow.shadowOffset = NSSize(width: 0, height: -Metrics.content.shadowOffset.value)
        return shadow
    }

    func height(width: CGFloat) -> CGFloat { Metrics.ai.pageHeaderHeight.value + pageHeight + Metrics.ai.pageInset.value.height * 2 }

    override func layout() {
        super.layout()
        let m = Metrics.ai, header = m.pageHeaderHeight.value, pad: CGFloat = 10
        shadowBack.frame = bounds
        card.frame = bounds
        keep.frame = CGRect(x: bounds.width - 4 - m.iconSize.value, y: (header - m.iconSize.value) / 2, width: m.iconSize.value, height: m.iconSize.value)
        let lineHeight = ceil(title.intrinsicContentSize.height)
        let y = ((header - lineHeight) / 2).rounded()
        let room = keep.frame.minX - pad - 4
        let titleWidth = min(CGFloat(title.cellWidth), room * 0.7)
        title.frame = CGRect(x: pad, y: y, width: titleWidth, height: lineHeight)
        schedule.frame = CGRect(x: title.frame.maxX + 4, y: y + 1, width: max(0, room - titleWidth - 4), height: lineHeight)
        rule.frame = CGRect(x: 0, y: header - 1, width: bounds.width, height: 1)
        let inset = m.pageInset.value
        sandbox?.frame = CGRect(x: inset.width, y: header + inset.height, width: max(0, bounds.width - inset.width * 2), height: max(0, bounds.height - header - inset.height * 2))
    }
}

/// A plain answer's sources and actions, one row each.
@MainActor
final class AIActionsView: NSView, AITranscriptPart {
    private var buttons: [AITextButton] = []

    override var isFlipped: Bool { true }

    func show(_ actions: [AIAnswerAction], style: AIPanelStyle, run: @escaping (Command) -> Void) {
        for button in buttons { button.removeFromSuperview() }
        buttons = actions.map { action in
            let button = AITextButton(action.title, kind: action.link ? .link : .item)
            button.alignment = .left
            button.setAccessibilityIdentifier(action.id)
            button.toolTip = action.tip
            button.layer?.cornerRadius = Metrics.ai.itemRadius.value
            button.apply(style)
            button.onPress = { run(action.command) }
            addSubview(button)
            return button
        }
    }

    func height(width: CGFloat) -> CGFloat {
        let m = Metrics.ai
        return buttons.isEmpty ? 0 : CGFloat(buttons.count) * m.buttonHeight.value + CGFloat(buttons.count - 1) * m.gap.value / 2
    }

    override func layout() {
        super.layout()
        let m = Metrics.ai
        for (i, button) in buttons.enumerated() {
            button.frame = CGRect(x: 0, y: CGFloat(i) * (m.buttonHeight.value + m.gap.value / 2), width: bounds.width, height: m.buttonHeight.value)
        }
    }
}

/// A plain container with its origin at the top left, like every BrkUI container.
final class AIFlippedView: NSView {
    override var isFlipped: Bool { true }
}
