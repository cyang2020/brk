import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// A conversation with the user's local agent (docs/design/ai-panel.md, ai-right-panel.md): the panel's conversation page,
/// a column at the window's right edge (`WindowFrames.aiPanel`) drawn straight on the Space's background, with no fill,
/// border or shadow of its own. Every part copies a part of the sidebar (`AIPanelStyle`), and Brk's own words follow the
/// language the user writes in (`AIPanelCopy`). Arc has no such view. A conversation is never drawn anywhere else.
///
/// Top to bottom: the header (the conversation's name, a spinner while the agent works, New Conversation, the list icon
/// and Close), the transcript (`AITranscriptView`), the approval the agent waits for, and the composer (`AIComposerView`)
/// with its + menu and @ list over the transcript just above it.
@MainActor
final class AIAnswerDocumentView: NSView {
    private let dispatch: Dispatch
    private let heading = aiLabel(Metrics.ai.titleFont.value, weight: .semibold)
    private let progress = NSProgressIndicator()
    /// The panel's list icon (docs/design/ai-threads.md): to this Space's conversation list, with the count of what waits
    /// for the user in the profile. The chat bubbles, as on the sidebar title row's button and the command bar's row
    /// (docs/design/ai-right-panel.md).
    private let listButton = AIIconButton(symbol: "bubble.left.and.bubble.right", tip: "")
    private let badge = aiLabel(9, weight: .semibold)
    private let badgeBack = NSView()
    private var listShown = false
    var onList: (() -> Void)?
    /// Space at the bottom for the panel's page dots.
    var bottomReserve: CGFloat = 0 { didSet { if bottomReserve != oldValue { needsLayout = true } } }
    private let newConversation = AIIconButton(symbol: "square.and.pencil", tip: "")
    private let close = AIIconButton(symbol: "xmark", tip: "")
    private let scroll = AIPanelScrollView()
    private let transcript = AITranscriptView()
    private let approval = AIApprovalView()
    private let composer = AIComposerView()
    private let plusMenu = AIMenuView()
    private let mentions = AIMenuView()
    private var answer: AIAnswerSnapshot?
    private var theme: ResolvedTheme?
    private var panelStyle: AIPanelStyle?
    private var copy = AIPanelCopy([])
    private var pageTheme: PageTheme?
    private var shownConversation: AIRequestID?
    private var menuOpen = false
    /// The + menu shows its main rows, or the agents and their models ("换 agent 和模型").
    private var menuAgents = false
    /// The agents ready on this Mac and their models (`WindowSnapshot.aiAgents`), for the + menu's agent list.
    var agents: AIAgentMenu? { didSet { if agents != oldValue, menuOpen { showMenu() } } }
    private var menuMonitor: Any?
    private var mentionIndex = 0
    private var mention: AIMentionSnapshot?
    /// The query whose list Esc closed: it stays closed until the text after @ changes.
    private var dismissedMention: String?
    private var placedWidth: CGFloat = 0

    /// Its pages commit their edits in progress (the view is about to go).
    func commitPageEdits() async { await transcript.pages.commitEdits() }

    /// A page in the transcript under the pointer scrolls sideways: the panel's swipe leaves the gesture to it.
    func scrollsSideways(atWindowPoint point: CGPoint) -> Bool { !isHidden && transcript.pages.scrollsSideways(atWindowPoint: point) }

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        setAccessibilityIdentifier("ai-document")
        wantsLayer = true
        heading.setAccessibilityIdentifier("ai-heading")
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        newConversation.identify(.aiControl("new"))
        newConversation.onPress = { dispatch(.assist(.newConversation)) }
        close.setAccessibilityIdentifier("ai-close")
        close.onPress = { [weak self] in
            guard let self else { return }
            dispatch(.assist(self.answer?.busy == true && self.answer?.conversation == nil ? .cancel : .dismiss))
        }
        for button in [newConversation, close, listButton] {
            button.layer?.cornerRadius = Metrics.ai.iconRadius.value
        }
        listButton.identify(.aiControl("list"))
        listButton.onPress = { [weak self] in self?.onList?() }
        listButton.isHidden = true
        badgeBack.wantsLayer = true
        badgeBack.isHidden = true
        badge.alignment = .center
        badge.setAccessibilityIdentifier("ai-list-badge")
        badge.isHidden = true
        scroll.identify(.aiControl("transcript"))
        scroll.documentView = transcript
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        transcript.onLink = { [weak self] url in self?.openLink(url) }
        transcript.onKeep = { [weak self] page in self?.send(.keepPage(page)) }
        transcript.onAction = { dispatch($0) }
        transcript.onResize = { [weak self] in self?.relayTranscript() }
        let pages = transcript.pages
        pages.onEvent = { [weak self] page, event in
            if case .link(let url) = event { self?.send(.pageLink(page, url)) }
        }
        pages.onSave = { [weak self] page, text in self?.send(.pageSave(page, text)) }
        pages.onHeight = { [weak self] in
            guard let self, let answer = self.answer else { return }
            self.showTranscript(answer)
        }
        pages.menu = { [weak self] page in
            guard let self else { return [] }
            let kept = self.answer?.pages.first { $0.id == page }?.kept == true
            return [ClosureMenuItem(kept ? "Show Tab" : "Keep as Tab") { [weak self] in self?.send(.keepPage(page)) }]
        }
        approval.onAnswer = { [weak self] approval, option in self?.send(.approve(approval: approval, option: option)) }
        approval.onResize = { [weak self] in self?.needsLayout = true }
        composer.onSend = { [weak self] message in
            guard let self, self.answer?.busy != true else { return }
            // A message over the limit is refused with a toast and stays here to shorten.
            if message.count <= AIValidation.messageLimit { self.composer.text = "" }
            self.send(.followUp(message))
        }
        composer.onStop = { [weak self] in self?.send(.stop) }
        composer.onPlus = { [weak self] in self?.toggleMenu() }
        composer.onRemoveChip = { [weak self] id in self?.send(.detach(id)) }
        composer.onHoverChip = { [weak self] id in self?.send(.hoverChip(id)) }
        composer.onChange = { [weak self] text in self?.textChanged(text) }
        composer.onCommand = { [weak self] selector in self?.command(selector) ?? false }
        composer.onResize = { [weak self] in self?.needsLayout = true }
        mentions.setAccessibilityIdentifier("ai-mentions")
        plusMenu.identify(.aiControl("menu"))
        for view in [heading, progress, listButton, badgeBack, badge, newConversation, close, scroll, approval, composer, mentions, plusMenu] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    /// The conversation this view shows.
    var conversationID: AIRequestID? { answer?.conversation?.id }

    /// The list icon in the header: shown while the panel has a list (a standard window), with the count of what waits.
    func showList(_ panel: AIPanelSnapshot?) {
        listShown = panel != nil
        listButton.isHidden = !listShown
        let waiting = panel?.waiting ?? 0
        badge.stringValue = waiting > 99 ? "99+" : "\(waiting)"
        badge.isHidden = !listShown || waiting == 0
        badgeBack.isHidden = badge.isHidden
        let language = panel?.language ?? copy.language
        listButton.tooltip(AIThreadWords.listTip(waiting: waiting, language))
        if let panelStyle {
            listButton.tint = panelStyle.secondary
            listButton.hoverFill = panelStyle.itemHover
            listButton.pressFill = panelStyle.itemHover
            badgeBack.layer?.backgroundColor = panelStyle.accent.cgColor
            badge.textColor = panelStyle.onAccent
        }
        needsLayout = true
    }

    private func send(_ intent: AIIntent) { dispatch(.assist(intent)) }

    private func openLink(_ url: URL) {
        if let tab = AgentTabLink.id(url) { send(.openTabLink(tab)) }
        else if let conversation = ConversationPage.id(of: url) { send(.showConversation(conversation)) }
        else if ["http", "https"].contains(url.scheme?.lowercased()) { dispatch(.commandBar(.submit(url.absoluteString))) }
    }

    // MARK: Render

    func render(_ answer: AIAnswerSnapshot?, in area: CGRect, theme: ResolvedTheme? = nil) {
        guard let answer else {
            self.answer = nil; shownConversation = nil; isHidden = true; progress.stopAnimation(nil)
            closeMenu()
            transcript.show([], style: panelStyle ?? AIPanelStyle(.fallbackLight), copy: copy, agent: nil, folder: nil)
            transcript.pages.removeAll()
            return
        }
        isHidden = false
        if frame != area { frame = area }
        let theme = theme ?? self.theme ?? .fallbackLight
        let styleChanged = theme != self.theme
        if styleChanged {
            self.theme = theme
            panelStyle = AIPanelStyle(theme)
            appearance = NSAppearance(named: theme.scheme == .light ? .aqua : .darkAqua)
            let next = PageTheme(theme, background: AIPanelStyle.cardRGBA(theme.scheme))
            if next != pageTheme { pageTheme = next; transcript.pages.apply(next) }
        }
        guard self.answer != answer || styleChanged, let panelStyle else { needsLayout = true; return }
        self.answer = answer
        copy = AIPanelCopy(answer.conversation?.items ?? [])
        let conversation = answer.conversation
        heading.stringValue = title(answer)
        heading.textColor = panelStyle.text
        heading.toolTip = heading.stringValue
        if answer.busy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        progress.toolTip = copy.working
        for button in [newConversation, close] {
            button.tint = panelStyle.secondary
            button.hoverFill = panelStyle.itemHover
            button.pressFill = panelStyle.itemHover
        }
        newConversation.tooltip(copy.newConversation)
        close.tooltip(answer.busy && conversation == nil ? copy.cancel : copy.close)
        newConversation.isHidden = conversation == nil || conversation?.fresh == true && conversation?.items.isEmpty == true
        showTranscript(answer)
        showComposer(answer)
        approval.show(pending(answer), agent: conversation?.agentName, folder: conversation?.folder, style: panelStyle, copy: copy)
        showMention(conversation?.mention)
        if menuOpen { showMenu() }
        needsLayout = true
    }

    /// The conversation's name; a new one's first words while it has none.
    private func title(_ answer: AIAnswerSnapshot) -> String {
        guard let conversation = answer.conversation else { return answer.title }
        if let name = answer.name, !name.isEmpty { return AgentLine.oneLine(name, limit: 120) }
        if let first = conversation.items.lazy.compactMap({ if case .user(let text) = $0 { text } else { nil } }).first { return AgentLine.oneLine(first, limit: 120) }
        if conversation.folder != nil { return answer.title }
        return copy.language == .zh ? "问问你的 tab" : answer.title
    }

    private func pending(_ answer: AIAnswerSnapshot) -> AIAgentApproval? {
        answer.conversation?.items.lazy.compactMap { item -> AIAgentApproval? in
            if case .approval(let value) = item, value.answer == nil { value } else { nil }
        }.first
    }

    private func actions(_ answer: AIAnswerSnapshot) -> [AIAnswerAction] {
        var out = answer.sources.enumerated().map { index, source in
            AIAnswerAction(id: "ai-source-\(index)", title: "[\(index + 1)] " + (source.title.isEmpty ? source.url.absoluteString : source.title),
                           tip: source.url.absoluteString, link: true, command: .commandBar(.submit(source.url.absoluteString)))
        }
        // Arc's own actions keep Arc's words.
        if answer.canUndo { out.append(AIAnswerAction(id: "ai-undo", title: "Undo Organize Today", tip: nil, link: false, command: .assist(.undoOrganize))) }
        if answer.site != nil { out.append(AIAnswerAction(id: "ai-never-site", title: "Never translate this site", tip: nil, link: false, command: .assist(.neverTranslateSite))) }
        if let language = answer.language, !language.isEmpty {
            out.append(AIAnswerAction(id: "ai-never-language", title: "Never translate \(language)", tip: nil, link: false, command: .assist(.neverTranslateLanguage)))
        }
        return out
    }

    private func showTranscript(_ answer: AIAnswerSnapshot) {
        guard let panelStyle else { return }
        let wasAtBottom = scroll.documentVisibleRect.maxY >= transcript.frame.height - Metrics.ai.itemGap.value
        transcript.show(AITranscriptRow.rows(answer, actions: actions(answer)), style: panelStyle, copy: copy,
                        agent: answer.conversation?.agentName, folder: answer.conversation?.folder)
        relayTranscript(stickToBottom: wasAtBottom)
    }

    /// The transcript laid out again at the scroll view's width; it keeps to the bottom when it was there.
    private func relayTranscript(stickToBottom: Bool? = nil) {
        let atBottom = stickToBottom ?? (scroll.documentVisibleRect.maxY >= transcript.frame.height - Metrics.ai.itemGap.value)
        let width = scroll.contentSize.width
        guard width > 0 else { return }
        let height = transcript.place(width: width)
        transcript.frame = CGRect(x: 0, y: 0, width: width, height: max(height, scroll.contentSize.height))
        if atBottom { transcript.scroll(CGPoint(x: 0, y: max(0, transcript.frame.height - scroll.contentSize.height))) }
    }

    private func showComposer(_ answer: AIAnswerSnapshot) {
        guard let panelStyle else { return }
        let conversation = answer.conversation
        let open = conversation?.ended == false
        composer.isHidden = !open
        guard open, let conversation else { return }
        let placeholder: String
        if conversation.folder != nil, !conversation.items.contains(where: { if case .user = $0 { true } else { false } }) { placeholder = copy.placeholderFolder }
        else if conversation.fresh { placeholder = copy.placeholderFresh }
        else if conversation.tabs { placeholder = copy.placeholderTabs }
        else { placeholder = copy.placeholderPlain }
        composer.render(style: panelStyle, copy: copy, placeholder: placeholder, busy: answer.busy, attached: conversation.attached)
        // A new conversation takes the keyboard, once the window has finished applying its own focus for this pass.
        if conversation.id != shownConversation {
            shownConversation = conversation.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, !self.isHidden, !self.composer.isHidden else { return }
                self.window?.makeFirstResponder(self.composer.input)
            }
        }
    }

    /// Tabs dragged from the sidebar are over the panel: the composer's outline says it takes them.
    func showDropTarget(_ on: Bool) { composer.showDropTarget(on) }

    // MARK: The + menu

    private func toggleMenu() {
        if menuOpen { closeMenu() } else { menuOpen = true; showMenu() }
    }

    private func showMenu() {
        guard let answer, let conversation = answer.conversation, let panelStyle, let theme else { closeMenu(); return }
        let open = !conversation.ended
        var rows: [AIMenuView.Row] = []
        if menuAgents, open, let agents, !agents.agents.isEmpty {
            rows = agentRows(conversation, agents)
            mentions.hide()
            plusMenu.show(rows, style: panelStyle, fill: Self.opaque(panelStyle.composer, over: theme))
            for control in plusMenu.controls where control.accessibilityIdentifier().hasPrefix(ViewID.aiControl("agent-header").identifier) { control.hoverFill = nil }
            needsLayout = true
            return
        }
        menuAgents = false
        if open, conversation.folder == nil {
            rows.append(.init(id: "folder", title: copy.workInFolder, tip: copy.workInFolderTip) { [weak self] in self?.closeMenu(); self?.send(.chooseFolder) })
        }
        let agent = pickedLine(conversation) ?? ([conversation.agentName ?? copy.localAgent] + [conversation.model, conversation.effort].compactMap { $0 }).joined(separator: " · ")
        // The agents and their models, one level in; without a list yet (nothing has reported), Settings → Max.
        let canPick = open && agents?.agents.isEmpty == false
        rows.append(.init(id: "agent", title: (copy.language == .zh ? "换 agent 和模型" : "Agent and Model") + (canPick ? " ›" : ""), detail: agent,
                          tip: canPick ? copy.pickAgentTip : copy.chooseAgentTip) { [weak self] in
            guard let self else { return }
            if canPick { self.menuAgents = true; self.showMenu() } else { self.closeMenu(); self.dispatch(.settings(.openPane(.max))) }
        })
        rows.append(.init(id: "permissions", title: copy.language == .zh ? "权限" : "Permissions",
                          detail: copy.permissions(folder: conversation.folder, tabs: conversation.tabs),
                          tip: copy.permissionsTip(folder: conversation.folder, tabs: conversation.tabs)) {})
        rows.append(.init(id: "agent-settings", title: copy.agentSettings, tip: copy.agentSettingsTip) { [weak self] in
            self?.closeMenu(); self?.dispatch(.settings(.openPane(.max)))
        })
        mentions.hide()
        plusMenu.show(rows, style: panelStyle, fill: Self.opaque(panelStyle.composer, over: theme))
        plusMenu.controls.first { $0.accessibilityIdentifier() == ViewID.aiControl("permissions").identifier }?.hoverFill = nil
        if menuMonitor == nil {
            menuMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                // A click anywhere but the menu and its + button closes it (the + button toggles it itself).
                let point = self.convert(event.locationInWindow, from: nil)
                let plus = self.composer.convert(self.composer.plus.frame, to: self)
                if !self.plusMenu.frame.contains(point), !plus.contains(point) { self.closeMenu() }
                return event
            }
        }
        needsLayout = true
    }

    /// "Codex · GPT-6 Sol" for a choice the + menu made; nil without one.
    private func pickedLine(_ conversation: AIConversationSnapshot) -> String? {
        guard let pick = conversation.pick else { return nil }
        let status = agents?.agents.first { $0.kind == pick.kind }
        let model = pick.model.flatMap { id in status?.models.first { $0.id == id }?.name ?? id }
        return ([pick.kind.displayName] + [model].compactMap { $0 }).joined(separator: " · ")
    }

    /// The agent list: a way back, then each ready agent with its models, the one the next message goes to checked.
    private func agentRows(_ conversation: AIConversationSnapshot, _ agents: AIAgentMenu) -> [AIMenuView.Row] {
        let zh = copy.language == .zh
        var rows: [AIMenuView.Row] = [.init(id: "agents-back", title: "‹ " + (zh ? "换 agent 和模型" : "Agent and Model")) { [weak self] in
            self?.menuAgents = false; self?.showMenu()
        }]
        // What the next message goes to: the choice made here, else the agent talked to with Settings → Max's model.
        let kind = conversation.pick?.kind ?? conversation.agent ?? agents.active
        let current: (AIProviderKind?, String?) = conversation.pick.map { ($0.kind, $0.model) }
            ?? (kind, kind.flatMap { k in agents.models[k] ?? agents.agents.first { $0.kind == k }?.models.first { $0.isDefault }?.id })
        for status in agents.agents {
            rows.append(.init(id: "agent-header-" + status.kind.rawValue, title: status.kind.displayName, enabled: false) {})
            let models = status.models.isEmpty ? [AIAgentModel(id: "", name: zh ? "默认模型" : "Default Model", isDefault: true)] : status.models
            for model in models {
                let id = model.id.isEmpty ? nil : model.id
                let on = current.0 == status.kind && (current.1 == id || (current.1 == nil && model.isDefault))
                rows.append(.init(id: "agent-pick-\(status.kind.rawValue)-\(model.id.isEmpty ? "default" : model.id)", title: "   " + model.name,
                                  detail: on ? "✓" : nil, tip: model.id.isEmpty ? nil : model.id) { [weak self] in
                    self?.closeMenu()
                    self?.send(.pickAgent(status.kind, model: id))
                })
            }
        }
        return rows
    }

    private func closeMenu() {
        menuAgents = false
        menuOpen = false
        plusMenu.hide()
        if let menuMonitor { NSEvent.removeMonitor(menuMonitor) }
        menuMonitor = nil
    }

    /// A translucent fill made solid over the window's own color, for lists that cover the transcript.
    private static func opaque(_ color: NSColor, over theme: ResolvedTheme) -> NSColor {
        let base = NSColor(srgbRed: theme.windowColor.red, green: theme.windowColor.green, blue: theme.windowColor.blue, alpha: 1)
        guard let fill = color.usingColorSpace(.sRGB) else { return base }
        return base.blended(withFraction: fill.alphaComponent, of: fill.withAlphaComponent(1)) ?? base
    }

    // MARK: @

    /// The text after the @ that starts a word, up to the end of the input; nil when there is none.
    static func mentionQuery(_ text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at > text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        let query = String(text[text.index(after: at)...])
        guard query.count <= 60, !query.contains(where: \.isNewline) else { return nil }
        return query
    }

    private func textChanged(_ text: String) {
        let query = Self.mentionQuery(text)
        if query != dismissedMention { dismissedMention = nil }
        guard answer?.conversation?.tabs == true else { return }
        if query != answer?.conversation?.mention?.query || (query == nil) != (answer?.conversation?.mention == nil) { send(.mention(query)) }
    }

    private func showMention(_ next: AIMentionSnapshot?) {
        let shown = next.flatMap { $0.query == dismissedMention || $0.matches.isEmpty ? nil : $0 }
        if shown?.query != mention?.query { mentionIndex = 0 }
        mention = shown
        guard let shown, let panelStyle, let theme else { mentions.hide(); return }
        if menuOpen { closeMenu() }
        let rows = shown.matches.enumerated().map { index, tab in
            AIMenuView.Row(id: "mention-\(index)", title: AgentLine.oneLine(tab.title, limit: 60), detail: tab.url?.host, tip: tab.url?.absoluteString) { [weak self] in self?.pickMention(index) }
        }
        mentionIndex = min(mentionIndex, max(0, rows.count - 1))
        mentions.show(rows, style: panelStyle, fill: Self.opaque(panelStyle.composer, over: theme))
        mentions.highlighted = mentionIndex
        needsLayout = true
    }

    /// The composer's keys before its own: the @ list's ↑ ↓ Return Tab and Esc, and Esc for the + menu.
    private func command(_ selector: Selector) -> Bool {
        if menuOpen, selector == #selector(NSResponder.cancelOperation(_:)) { closeMenu(); return true }
        guard let mention, !mention.matches.isEmpty, !mentions.isHidden else { return false }
        let count = mention.matches.count
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            mentionIndex = (mentionIndex + 1) % count; mentions.highlighted = mentionIndex; return true
        case #selector(NSResponder.moveUp(_:)):
            mentionIndex = (mentionIndex + count - 1) % count; mentions.highlighted = mentionIndex; return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            pickMention(mentionIndex); return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismissedMention = mention.query
            showMention(nil)
            return true
        default: return false
        }
    }

    /// The tab under @ becomes a chip, and the @ and what followed it leave the text.
    private func pickMention(_ index: Int) {
        guard let mention, mention.matches.indices.contains(index) else { return }
        let text = composer.text
        if let at = text.lastIndex(of: "@") { composer.text = String(text[..<at]) }
        send(.attach([.tab(mention.matches[index].id)]))
        send(.mention(nil))
        window?.makeFirstResponder(composer.input)
        composer.input.setSelectedRange(NSRange(location: (composer.text as NSString).length, length: 0))
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let m = Metrics.ai, gap = m.gap.value
        // The panel keeps the sidebar's inset.
        let column = CGRect(x: m.columnInset.value, y: 0, width: bounds.width - m.columnInset.value * 2, height: bounds.height - max(m.bottomInset.value, bottomReserve))
        let headerY = column.minY + m.headerTop.value, headerHeight = m.headerHeight.value, icon = m.iconSize.value
        var right = column.maxX
        for button in [close, newConversation, listButton] where !button.isHidden {
            button.frame = CGRect(x: right - icon, y: headerY + (headerHeight - icon) / 2, width: icon, height: icon)
            right -= icon + 2
        }
        if !badge.isHidden {
            let height: CGFloat = 12, width = max(height, ceil(badge.intrinsicContentSize.width) + 6)
            badgeBack.frame = CGRect(x: listButton.frame.maxX - width + 3, y: listButton.frame.minY - 2, width: width, height: height)
            badgeBack.layer?.cornerRadius = height / 2
            let lh = ceil(badge.intrinsicContentSize.height)
            badge.frame = CGRect(x: badgeBack.frame.minX, y: badgeBack.frame.minY + ((height - lh) / 2).rounded(), width: width, height: lh)
        }
        let spinner: CGFloat = 16
        progress.frame = CGRect(x: right - spinner - 2, y: headerY + (headerHeight - spinner) / 2, width: spinner, height: spinner)
        let lineHeight = ceil(heading.intrinsicContentSize.height)
        heading.frame = CGRect(x: column.minX + 4, y: headerY + ((headerHeight - lineHeight) / 2).rounded(), width: max(0, progress.frame.minX - gap - column.minX - 4), height: lineHeight)
        var bottom = column.maxY
        if !composer.isHidden {
            let height = composer.preferredHeight(width: column.width)
            composer.frame = CGRect(x: column.minX, y: bottom - height, width: column.width, height: height)
            bottom = composer.frame.minY - gap
        }
        if !approval.isHidden {
            let height = approval.height(width: column.width)
            approval.frame = CGRect(x: column.minX, y: bottom - height, width: column.width, height: height)
            bottom = approval.frame.minY - gap
        }
        let top = headerY + headerHeight
        scroll.frame = CGRect(x: column.minX, y: top, width: column.width, height: max(0, bottom - top))
        if abs(placedWidth - scroll.contentSize.width) > 0.5 || transcript.frame.width != scroll.contentSize.width {
            placedWidth = scroll.contentSize.width
            relayTranscript()
        }
        // The + menu and the @ list over the transcript, just above the composer.
        let anchor = composer.isHidden ? bottom : composer.frame.minY - 6
        for list in [plusMenu, mentions] where !list.isHidden {
            let height = min(list.preferredHeight, max(0, anchor - top))
            list.frame = CGRect(x: column.minX, y: anchor - height, width: column.width, height: height)
        }
    }
}

/// The approval the agent waits for, over the composer: one plain sentence ("Claude 想在 ~/Desktop 里运行一条命令"), the
/// command itself behind Show Command, and the agent's options, Allow in the Space's color, the rest on the URL pill's
/// fill. The card is that fill too.
@MainActor
final class AIApprovalView: NSView {
    private let sentence = NSTextField(wrappingLabelWithString: "")
    private let toggle = AITextButton("", kind: .quiet)
    private let detail = NSTextField(wrappingLabelWithString: "")
    private var buttons: [AITextButton] = []
    private var shown: AIAgentApproval?
    private var expanded = false
    private var copy = AIPanelCopy([])
    var onAnswer: ((String, String) -> Void)?
    var onResize: (() -> Void)?

    init() {
        super.init(frame: .zero)
        isHidden = true
        wantsLayer = true
        layer?.cornerRadius = Metrics.ai.itemRadius.value
        layer?.cornerCurve = .continuous
        setAccessibilityIdentifier("ai-approval")
        sentence.font = .systemFont(ofSize: Metrics.ai.bodyFont.value, weight: .medium)
        sentence.maximumNumberOfLines = 3
        // Wrapping (a truncating break would keep it to one line), the third line cut if it must be.
        sentence.lineBreakMode = .byCharWrapping
        sentence.cell?.truncatesLastVisibleLine = true
        sentence.drawsBackground = false
        detail.font = .monospacedSystemFont(ofSize: Metrics.ai.stepFont.value - 1, weight: .regular)
        detail.maximumNumberOfLines = 10
        detail.lineBreakMode = .byCharWrapping
        detail.cell?.truncatesLastVisibleLine = true
        detail.isSelectable = true
        detail.drawsBackground = false
        toggle.identify(.aiControl("approval-command"))
        toggle.alignment = .left
        toggle.layer?.cornerRadius = Metrics.ai.smallRadius.value
        toggle.onPress = { [weak self] in
            guard let self else { return }
            self.expanded.toggle()
            self.showToggle()
            self.needsLayout = true
            self.onResize?()
        }
        for view in [sentence, toggle, detail] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func show(_ approval: AIAgentApproval?, agent: String?, folder: String?, style: AIPanelStyle, copy: AIPanelCopy) {
        self.copy = copy
        isHidden = approval == nil
        guard let approval else { shown = nil; return }
        if approval.id != shown?.id { expanded = false }
        shown = approval
        layer?.backgroundColor = style.item.cgColor
        sentence.stringValue = AIStepWords.approval(approval, agent: agent, folder: folder, copy.language)
        sentence.toolTip = [folder, approval.title].compactMap { $0 }.joined(separator: "\n")
        sentence.textColor = style.onCard ? style.cardText : style.text
        detail.stringValue = approval.detail
        detail.textColor = style.secondary
        toggle.isHidden = approval.detail.isEmpty
        toggle.apply(style)
        showToggle()
        for button in buttons { button.removeFromSuperview() }
        // Allow last, in the Space's color; Deny and the rest on the item fill.
        let options = approval.options.filter { $0.kind == .deny } + approval.options.filter { $0.kind == .allowSession } + approval.options.filter { $0.kind == .allowOnce }
        buttons = options.map { option in
            let button = AITextButton(copy.option(option), kind: option.kind == .allowOnce ? .accent : .item)
            button.identify(.aiControl("approval-" + option.kind.rawValue))
            button.toolTip = option.title
            button.layer?.cornerRadius = Metrics.ai.chipRadius.value
            button.apply(style)
            button.onPress = { [weak self] in self?.onAnswer?(approval.id, option.id) }
            addSubview(button)
            return button
        }
        needsLayout = true
    }

    private func showToggle() {
        let command = shown?.kind == .command
        toggle.title = expanded ? (command ? copy.hideCommand : copy.hideDetail) : (command ? copy.showCommand : copy.showDetail)
        detail.isHidden = !expanded || shown?.detail.isEmpty != false
    }

    private var pad: CGFloat { Metrics.ai.gap.value + 2 }

    func height(width: CGFloat) -> CGFloat {
        let m = Metrics.ai, inner = width - pad * 2
        var height = pad + textHeight(sentence, width: inner)
        if !toggle.isHidden { height += 2 + 20 }
        if !detail.isHidden { height += 4 + textHeight(detail, width: inner) }
        return height + m.gap.value + m.buttonHeight.value + pad
    }

    private func textHeight(_ label: NSTextField, width: CGFloat) -> CGFloat {
        ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(20, width), height: 10_000)).height ?? 16)
    }

    override func layout() {
        super.layout()
        let m = Metrics.ai, inner = bounds.width - pad * 2
        var y = pad
        let sentenceHeight = textHeight(sentence, width: inner)
        sentence.frame = CGRect(x: pad, y: y, width: inner, height: sentenceHeight)
        y += sentenceHeight
        if !toggle.isHidden {
            y += 2
            toggle.frame = CGRect(x: pad - m.gap.value, y: y, width: min(inner, toggle.fittingWidth), height: 20)
            y += 20
        }
        if !detail.isHidden {
            y += 4
            let height = textHeight(detail, width: inner)
            detail.frame = CGRect(x: pad, y: y, width: inner, height: height)
            y += height
        }
        var x = bounds.width - pad
        for button in buttons.reversed() {
            let width = max(64, button.fittingWidth)
            x -= width
            button.frame = CGRect(x: x, y: bounds.height - pad - m.buttonHeight.value, width: width, height: m.buttonHeight.value)
            x -= m.gap.value
        }
    }
}

/// A conversation's text: the agent's Markdown shown, in the panel's colors.
enum AIConversationText {
    /// Agents answer in Markdown. Code blocks and headings by line, the rest through Foundation's inline parser.
    @MainActor static func markdown(_ text: String, size: CGFloat, color: NSColor, style: AIPanelStyle) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let plain: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: paragraph]
        let code: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular), .foregroundColor: color]
        var inCode = false, first = true
        let lines = text.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inCode.toggle(); continue }
            if !first { out.append(NSAttributedString(string: "\n", attributes: plain)) }
            first = false
            if inCode { out.append(NSAttributedString(string: line, attributes: code)); continue }
            // A Markdown table: a header row, a |---| row, then rows while lines start with |.
            if index < lines.count, let header = tableCells(line), let rule = tableCells(lines[index]), rule.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } && $0.contains("-") }) {
                var rows = [header]
                index += 1
                while index < lines.count, let cells = tableCells(lines[index]) { rows.append(cells); index += 1 }
                out.append(table(rows, size: size, color: color, style: style))
                continue
            }
            let hashes = line.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                out.append(inline(String(line.dropFirst(hashes + 1)), size: size, weight: .semibold, color: color, paragraph: paragraph))
            } else {
                out.append(inline(line, size: size, weight: .regular, color: color, paragraph: paragraph))
            }
        }
        return out
    }

    /// The cells of a `| a | b |` line, nil for any other line.
    static func tableCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.count > 1 else { return nil }
        var body = trimmed.dropFirst()
        if body.hasSuffix("|") { body = body.dropLast() }
        return body.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Rows as an AppKit text table: the sidebar's separator for lines, the header row on the item fill.
    @MainActor private static func table(_ rows: [[String]], size: CGFloat, color: NSColor, style: AIPanelStyle) -> NSAttributedString {
        let columns = rows.map(\.count).max() ?? 1
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.collapsesBorders = true
        let out = NSMutableAttributedString()
        for (row, cells) in rows.enumerated() {
            for column in 0..<columns {
                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setWidth(4, type: .absoluteValueType, for: .padding)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setBorderColor(style.separator)
                if row == 0 { block.backgroundColor = style.item }
                let paragraph = NSMutableParagraphStyle()
                paragraph.textBlocks = [block]
                let cell = NSMutableAttributedString(attributedString: inline(column < cells.count ? cells[column] : "", size: size - 1, weight: row == 0 ? .semibold : .regular, color: color, paragraph: nil))
                cell.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: size - 1)]))
                cell.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: cell.length))
                out.append(cell)
            }
        }
        return out
    }

    private static func inline(_ line: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, paragraph: NSParagraphStyle?) -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        var common: [NSAttributedString.Key: Any] = [.foregroundColor: color]
        if let paragraph { common[.paragraphStyle] = paragraph }
        guard let parsed = try? AttributedString(markdown: line, options: .init(allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: line, attributes: common.merging([.font: base]) { $1 })
        }
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            var font = base
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) { font = NSFont.systemFont(ofSize: size, weight: .semibold) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            if intent.contains(.code) { font = NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular) }
            var attributes = common
            attributes[.font] = font
            if let link = run.link, ["http", "https", AgentTabLink.scheme].contains(link.scheme?.lowercased()) { attributes[.link] = link }
            out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return out
    }
}

enum AgentCopyText {
    static func oneLine(_ text: String, limit: Int) -> String { AgentLine.oneLine(text, limit: limit) }
}
