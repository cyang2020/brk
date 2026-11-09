import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The right side of the Library's "AI 对话" page (docs/design/ai-threads.md): the selected conversation in full over the
/// content card, as Media's preview shows a capture there. Its name and "Space · agent · model" on top, the transcript
/// with the pages it drew (the same rows as the panel, on the card's color), and three buttons: Continue (its Space, in
/// the panel), Move to Another Space… and Delete for Good…, which asks first. A conversation has no tab to open
/// (docs/design/ai-right-panel.md).
@MainActor
final class LibraryConversationPreview: NSView {
    private let dispatch: Dispatch
    private let title = aiLabel(Metrics.ai.libraryTitleFont.value, weight: .semibold)
    private let meta = aiLabel(Metrics.ai.noticeFont.value)
    private let scroll = NSScrollView()
    private let transcript = AITranscriptView()
    private let continueButton = AITextButton("", kind: .accent)
    private let moveButton = AITextButton("", kind: .item)
    private let deleteButton = AITextButton("", kind: .item)
    private let separator = NSView()
    private var snapshot: LibraryConversationsSnapshot?
    private var theme: ResolvedTheme?
    private var style: AIPanelStyle?
    private var pageTheme: PageTheme?
    private var placedWidth: CGFloat = 0

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        identify(.aiControl("library-preview"))
        title.setAccessibilityIdentifier("ai-library-preview-title")
        scroll.documentView = transcript
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.identify(.aiControl("library-preview-transcript"))
        transcript.onResize = { [weak self] in self?.relay() }
        transcript.pages.onHeight = { [weak self] in self?.relay() }
        transcript.onLink = { [weak self] url in
            if ["http", "https"].contains(url.scheme?.lowercased()) { self?.dispatch(.commandBar(.submit(url.absoluteString))) }
        }
        separator.wantsLayer = true
        continueButton.identify(.aiControl("library-continue"))
        moveButton.identify(.aiControl("library-move"))
        deleteButton.identify(.aiControl("library-delete"))
        continueButton.onPress = { [weak self] in self?.act { .assist(.showConversation($0)) } }
        deleteButton.onPress = { [weak self] in self?.act { .library(.requestDeleteConversation($0)) } }
        moveButton.onPress = { [weak self] in self?.showMoveMenu() }
        for view in [title, meta, scroll, separator, continueButton, moveButton, deleteButton] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    private func act(_ command: (AIRequestID) -> Command) {
        guard let id = snapshot?.selected?.id else { return }
        dispatch(command(id))
    }

    /// The profile's other Spaces under the button.
    private func showMoveMenu() {
        guard let snapshot, let detail = snapshot.selected else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let others = snapshot.spaces.filter { $0.id != detail.space }
        if others.isEmpty {
            let item = NSMenuItem(title: AIThreadWords.noOtherSpace(snapshot.language), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        for space in others {
            let id = detail.id, target = space.id
            menu.addItem(ClosureMenuItem(space.title) { [weak self] in self?.dispatch(.library(.moveConversation(id, target))) })
        }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: moveButton.bounds.maxY + 4), in: moveButton)
    }

    /// The selected conversation over `card` (the content card's part in sight), or nothing.
    func render(_ snapshot: LibraryConversationsSnapshot?, card: CGRect, cornerRadius: CGFloat, theme: ResolvedTheme) {
        guard let snapshot, let detail = snapshot.selected else {
            if !isHidden { isHidden = true; transcript.pages.removeAll(); transcript.show([], style: style ?? AIPanelStyle(theme, onCard: true), copy: AIPanelCopy([]), agent: nil, folder: nil) }
            self.snapshot = nil
            return
        }
        isHidden = false
        if frame != card { frame = card }
        layer?.cornerRadius = cornerRadius
        if theme != self.theme {
            self.theme = theme
            style = AIPanelStyle(theme, onCard: true)
            appearance = NSAppearance(named: theme.scheme == .light ? .aqua : .darkAqua)
            layer?.backgroundColor = AIPanelStyle.cardColor(theme.scheme).cgColor
            let next = PageTheme(theme, background: AIPanelStyle.cardRGBA(theme.scheme))
            if next != pageTheme { pageTheme = next; transcript.pages.apply(next) }
        }
        guard snapshot != self.snapshot, let style else { needsLayout = true; return }
        self.snapshot = snapshot
        let language = AILanguage.of(detail.answer.conversation?.items ?? [], system: Locale.preferredLanguages.first ?? "en")
        let copy = AIPanelCopy(detail.answer.conversation?.items ?? [])
        title.stringValue = AgentLine.oneLine(detail.title, limit: 120)
        title.textColor = style.cardText
        title.toolTip = detail.title
        meta.stringValue = detail.meta
        meta.textColor = style.secondary
        separator.layer?.backgroundColor = style.separator.cgColor
        continueButton.title = AIThreadWords.continueConversation(language)
        moveButton.title = AIThreadWords.moveEllipsis(language)
        deleteButton.title = AIThreadWords.deleteEllipsis(language)
        for button in [continueButton, moveButton, deleteButton] {
            button.apply(style)
            button.layer?.cornerRadius = Metrics.ai.chipRadius.value
        }
        deleteButton.label.textColor = .systemRed
        transcript.show(AITranscriptRow.rows(detail.answer, actions: []), style: style, copy: copy,
                        agent: detail.answer.conversation?.agentName, folder: detail.answer.conversation?.folder)
        placedWidth = 0
        needsLayout = true
    }

    private func relay() {
        let width = scroll.contentSize.width
        guard width > 0 else { return }
        let height = transcript.place(width: width)
        transcript.frame = CGRect(x: 0, y: 0, width: width, height: max(height, scroll.contentSize.height))
    }

    override func layout() {
        super.layout()
        let m = Metrics.ai
        let width = min(m.libraryColumnWidth.value, bounds.width - m.libraryColumnInset.value * 2)
        let x = ((bounds.width - width) / 2).rounded()
        var y = m.libraryColumnInset.value / 2 + 6
        let th = ceil(title.intrinsicContentSize.height), mh = ceil(meta.intrinsicContentSize.height)
        title.frame = CGRect(x: x, y: y, width: width, height: th)
        y += th + 2
        meta.frame = CGRect(x: x, y: y, width: width, height: mh)
        y += mh + 10
        let buttonHeight = m.buttonHeight.value
        let bottom = bounds.height - m.libraryColumnInset.value / 2 - buttonHeight
        var left = x
        for button in [continueButton, moveButton] {
            let w = max(64, button.fittingWidth)
            button.frame = CGRect(x: left, y: bottom, width: w, height: buttonHeight)
            left += w + m.gap.value
        }
        let deleteWidth = max(64, deleteButton.fittingWidth)
        deleteButton.frame = CGRect(x: x + width - deleteWidth, y: bottom, width: deleteWidth, height: buttonHeight)
        separator.frame = CGRect(x: x, y: bottom - m.gap.value - 1, width: width, height: 1)
        scroll.frame = CGRect(x: x, y: y, width: width, height: max(0, separator.frame.minY - m.gap.value - y))
        if abs(placedWidth - scroll.contentSize.width) > 0.5 {
            placedWidth = scroll.contentSize.width
            relay()
        }
    }
}
