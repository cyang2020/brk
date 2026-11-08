import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

/// The Max panel: a session-only conversation with the user's local agent beside the page. Live text, the steps the agent
/// takes, the approvals it asks for, follow-ups and Stop. Arc has no such panel; it follows Brk's own panel style and T3
/// Code's behaviour. Source buttons open through Brk in the same browsing context.
@MainActor
final class AIAnswerDocumentView: NSView, NSTextViewDelegate, NSTextFieldDelegate {
    private let dispatch: Dispatch
    private let material = NSVisualEffectView()
    private let heading = NSTextField(labelWithString: "Max · Local agent")
    private let question = NSTextField(wrappingLabelWithString: "")
    private let scroll = NSScrollView()
    private let text = NSTextView()
    private let close = AIActionButton("Close")
    private let progress = NSProgressIndicator()
    private let input = NSTextField()
    private let send = AIActionButton("Send")
    private let folderStatus = NSTextField(labelWithString: "")
    private let folder = AIActionButton("Work in a Folder…")
    private let settings = AIActionButton("Agent…")
    private let approvalTitle = NSTextField(wrappingLabelWithString: "")
    private let approvalDetail = NSTextField(wrappingLabelWithString: "")
    private let approvalBack = NSView()
    private var approvalButtons: [AIActionButton] = []
    private var pendingApproval: AIAgentApproval?
    private var sources: [AIActionButton] = []
    private var controls: [AIActionButton] = []
    private var answer: AIAnswerSnapshot?
    private var shownConversation: AIRequestID?
    private var rendered: [(item: AIConversationItem, text: NSAttributedString)] = []
    /// The chips of tabs given to the next message, and the @ list while one is typed.
    private var chipButtons: [AIChipButton] = []
    private var mentionRows: [AIActionButton] = []
    private var mentionIndex = 0
    private var mention: AIMentionSnapshot?
    /// The query whose list Esc closed: it stays closed until the text after @ changes.
    private var dismissedMention: String?
    private let mentionBack = NSView()

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
        heading.lineBreakMode = .byTruncatingTail
        heading.setAccessibilityIdentifier("ai-heading")
        question.font = .systemFont(ofSize: Metrics.ai.questionFont.value, weight: .medium)
        question.maximumNumberOfLines = 2; question.lineBreakMode = .byTruncatingTail
        text.isEditable = false; text.isSelectable = true; text.isRichText = true
        text.drawsBackground = false; text.textColor = .labelColor
        text.font = .systemFont(ofSize: Metrics.ai.bodyFont.value)
        text.autoresizingMask = [.width]; text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        text.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
        text.delegate = self
        text.setAccessibilityIdentifier("ai-answer")
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        close.setAccessibilityIdentifier("ai-close")
        close.onPress = { [weak self] in guard let self else { return }; dispatch(.assist(answer?.busy == true && answer?.conversation == nil ? .cancel : .dismiss)) }
        input.placeholderString = "Ask a follow-up"
        input.font = .systemFont(ofSize: Metrics.ai.bodyFont.value)
        input.lineBreakMode = .byTruncatingTail
        input.usesSingleLineMode = true
        input.cell?.sendsActionOnEndEditing = false
        input.target = self; input.action = #selector(submit)
        input.delegate = self
        input.identify(.aiControl("input"))
        mentionBack.wantsLayer = true
        mentionBack.layer?.cornerRadius = Metrics.ai.approvalRadius.value
        mentionBack.layer?.borderWidth = Metrics.ai.borderWidth.value
        mentionBack.layer?.borderColor = NSColor.separatorColor.cgColor
        mentionBack.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        mentionBack.isHidden = true
        mentionBack.setAccessibilityIdentifier("ai-mentions")
        send.identify(.aiControl("send"))
        send.onPress = { [weak self] in self?.sendOrStop() }
        folder.identify(.aiControl("folder"))
        folder.toolTip = "Start a session that may run commands and change files in a folder you choose. It asks you first."
        folder.onPress = { dispatch(.assist(.chooseFolder)) }
        settings.identify(.aiControl("agent-settings"))
        settings.toolTip = "Choose the agent, model and effort in Settings → Max."
        settings.onPress = { dispatch(.settings(.openPane(.max))) }
        folderStatus.font = .systemFont(ofSize: Metrics.ai.stepFont.value)
        folderStatus.textColor = .secondaryLabelColor
        folderStatus.lineBreakMode = .byTruncatingMiddle
        folderStatus.setAccessibilityIdentifier("ai-folder-status")
        approvalBack.wantsLayer = true
        approvalBack.layer?.cornerRadius = Metrics.ai.approvalRadius.value
        approvalBack.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        approvalBack.setAccessibilityIdentifier("ai-approval")
        approvalTitle.font = .systemFont(ofSize: Metrics.ai.bodyFont.value, weight: .medium)
        approvalTitle.maximumNumberOfLines = 2; approvalTitle.lineBreakMode = .byTruncatingTail
        approvalDetail.font = .monospacedSystemFont(ofSize: Metrics.ai.stepFont.value, weight: .regular)
        approvalDetail.textColor = .secondaryLabelColor
        approvalDetail.maximumNumberOfLines = 4; approvalDetail.lineBreakMode = .byTruncatingTail
        for view in [material, heading, question, scroll, close, progress, approvalBack, approvalTitle, approvalDetail, folderStatus, folder, settings, input, send, mentionBack] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    @objc private func submit() {
        guard answer?.busy != true else { return }
        sendOrStop()
    }

    private func sendOrStop() {
        guard let answer else { return }
        if answer.busy { dispatch(.assist(.stop)); return }
        let message = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        input.stringValue = ""
        dispatch(.assist(.followUp(message)))
    }

    func render(_ answer: AIAnswerSnapshot?, in area: CGRect) {
        guard let answer else {
            self.answer = nil; shownConversation = nil; rendered = []; isHidden = true; progress.stopAnimation(nil)
            return
        }
        isHidden = false
        let m = Metrics.ai
        let width = min(m.width.value, max(m.minimumWidth.value, area.width - m.inset.value * 2))
        frame = CGRect(x: area.maxX - width - m.inset.value, y: area.minY + m.inset.value,
                       width: width, height: max(m.minimumHeight.value, area.height - m.inset.value * 2))
        if self.answer != answer {
            self.answer = answer
            question.stringValue = answer.title
            heading.stringValue = Self.headingText(answer.conversation)
            showTranscript(answer)
            close.title = answer.busy && answer.conversation == nil ? "Cancel" : "Close"
            if answer.busy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
            showInput(answer)
            showChips(answer.conversation)
            showMention(answer.conversation?.mention)
            showApproval(answer)
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
            for button in sources + controls { addSubview(button) }
        }
        needsLayout = true
    }

    /// "Max · Claude · Opus 5.5", with the effort when one was chosen.
    private static func headingText(_ conversation: AIConversationSnapshot?) -> String {
        guard let name = conversation?.agentName else { return "Max · Local agent" }
        return (["Max", name, conversation?.model, conversation?.effort].compactMap { $0 }).joined(separator: " · ")
    }

    private func showInput(_ answer: AIAnswerSnapshot) {
        let conversation = answer.conversation
        let open = conversation?.ended == false
        input.isHidden = !open
        send.isHidden = !open
        send.title = answer.busy ? "Stop" : "Send"
        send.identify(.aiControl(answer.busy ? "stop" : "send"))
        input.isEnabled = !answer.busy
        input.placeholderString = conversation?.folder != nil && !(conversation?.items.contains { if case .user = $0 { true } else { false } } ?? false) ? "Tell the agent what to do here"
            : conversation?.fresh == true ? "Ask about these tabs, or type @ to add one" : conversation?.tabs == true ? "Ask a follow-up, or type @ to add a tab" : "Ask a follow-up"
        folder.isHidden = !open || conversation?.folder != nil
        settings.isHidden = false
        folderStatus.isHidden = conversation == nil
        if let path = conversation?.folder {
            folderStatus.stringValue = "Tools on in " + (path as NSString).lastPathComponent
            folderStatus.toolTip = path
        } else if conversation?.tabs == true {
            folderStatus.stringValue = "Tab tools on · others ask"
            folderStatus.toolTip = "The agent reads this profile's tabs. It asks before it first closes or moves them, and before every command, file change or other tool of its own."
        } else {
            folderStatus.stringValue = "Tools off"
            folderStatus.toolTip = "This conversation cannot run commands or change files."
        }
        // A new conversation takes the keyboard, once the window has finished applying its own focus for this pass.
        if open, let id = conversation?.id, id != shownConversation {
            shownConversation = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, !self.isHidden, !self.input.isHidden else { return }
                self.window?.makeFirstResponder(self.input)
            }
        }
    }

    private func showApproval(_ answer: AIAnswerSnapshot) {
        let approval = answer.conversation?.items.lazy.compactMap { item -> AIAgentApproval? in
            if case .approval(let value) = item, value.answer == nil { value } else { nil }
        }.first
        guard approval != pendingApproval else { return }
        pendingApproval = approval
        for button in approvalButtons { button.removeFromSuperview() }
        approvalButtons = []
        approvalBack.isHidden = approval == nil
        approvalTitle.isHidden = approval == nil
        approvalDetail.isHidden = approval == nil || approval?.detail.isEmpty == true
        guard let approval else { return }
        approvalTitle.stringValue = approval.title
        approvalDetail.stringValue = approval.detail
        for option in approval.options {
            let button = AIActionButton(option.title)
            button.identify(.aiControl("approval-" + option.kind.rawValue))
            button.onPress = { [weak self] in self?.dispatch(.assist(.approve(approval: approval.id, option: option.id))) }
            approvalButtons.append(button)
            addSubview(button)
        }
    }

    private func showTranscript(_ answer: AIAnswerSnapshot) {
        guard let conversation = answer.conversation else {
            rendered = []
            if text.string != answer.text { text.textStorage?.setAttributedString(NSAttributedString(string: answer.text, attributes: Self.body)) }
            return
        }
        let wasAtBottom = scroll.documentVisibleRect.maxY >= text.bounds.height - Metrics.ai.gap.value
        // Only what changed is built again: while the agent writes, that is its last row.
        var next: [(item: AIConversationItem, text: NSAttributedString)] = []
        for (index, item) in conversation.items.enumerated() {
            guard let value = AIConversationText.attributed(item) else { continue }
            _ = index
            if next.count < rendered.count, rendered[next.count].item == item { next.append(rendered[next.count]) }
            else { next.append((item, value)) }
        }
        rendered = next
        let joined = NSMutableAttributedString()
        for (index, row) in rendered.enumerated() {
            if index > 0 { joined.append(NSAttributedString(string: "\n\n", attributes: Self.body)) }
            joined.append(row.text)
        }
        if text.attributedString() != joined { text.textStorage?.setAttributedString(joined) }
        if wasAtBottom { text.scrollToEndOfDocument(nil) }
    }

    private static var body: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: Metrics.ai.bodyFont.value), .foregroundColor: NSColor.labelColor]
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let address = (link as? URL)?.absoluteString ?? link as? String
        guard let address, let url = URL(string: address) else { return true }
        if let tab = AgentTabLink.id(url) { dispatch(.assist(.openTabLink(tab))) }
        else if ["http", "https"].contains(url.scheme?.lowercased()) { dispatch(.commandBar(.submit(url.absoluteString))) }
        return true
    }

    // MARK: Chips and @

    private func showChips(_ conversation: AIConversationSnapshot?) {
        let attached = conversation?.ended == false ? conversation?.attached ?? [] : []
        guard attached.map(\.id) != chipButtons.map(\.chipID) || attached.map(\.title) != chipButtons.map(\.chipTitle) else { return }
        for chip in chipButtons { chip.removeFromSuperview() }
        chipButtons = attached.map { attachment in
            let count = attachment.tabs.count
            let title = attachment.kind == .tab ? attachment.title : "\(attachment.title) · \(count)"
            let chip = AIChipButton(id: attachment.id, title: title)
            chip.toolTip = attachment.tabs.prefix(12).map { $0.title + ($0.url.map { " — " + $0.absoluteString } ?? "") }.joined(separator: "\n")
            chip.setAccessibilityIdentifier("ai-chip-" + attachment.id)
            chip.onRemove = { [weak self] in self?.dispatch(.assist(.detach(attachment.id))) }
            addSubview(chip)
            return chip
        }
    }

    private func showMention(_ next: AIMentionSnapshot?) {
        let shown = next.flatMap { $0.query == dismissedMention || $0.matches.isEmpty ? nil : $0 }
        guard shown != mention else { return }
        if shown?.query != mention?.query { mentionIndex = 0 }
        mention = shown
        for row in mentionRows { row.removeFromSuperview() }
        mentionRows = (shown?.matches ?? []).enumerated().map { index, tab in
            let host = tab.url?.host.map { "  —  " + $0 } ?? ""
            let row = AIActionButton(AgentCopyText.oneLine(tab.title, limit: 60) + host)
            row.isBordered = false; row.alignment = .left; row.lineBreakMode = .byTruncatingTail
            row.setAccessibilityIdentifier("ai-mention-\(index)")
            row.onPress = { [weak self] in self?.pickMention(index) }
            addSubview(row)
            return row
        }
        mentionBack.isHidden = mentionRows.isEmpty
        mentionIndex = min(mentionIndex, max(0, mentionRows.count - 1))
        highlightMention()
    }

    private func highlightMention() {
        for (index, row) in mentionRows.enumerated() {
            row.wantsLayer = true
            row.layer?.cornerRadius = Metrics.ai.chipRadius.value
            row.layer?.backgroundColor = index == mentionIndex ? NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor : nil
        }
    }

    /// The text after the @ that starts a word, up to the end of the input; nil when there is none.
    static func mentionQuery(_ text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at > text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        let query = String(text[text.index(after: at)...])
        guard query.count <= 60, !query.contains(where: \.isNewline) else { return nil }
        return query
    }

    func controlTextDidChange(_ notification: Notification) {
        let query = Self.mentionQuery(input.stringValue)
        if query != dismissedMention { dismissedMention = nil }
        guard answer?.conversation?.tabs == true else { return }
        if query != answer?.conversation?.mention?.query || (query == nil) != (answer?.conversation?.mention == nil) { dispatch(.assist(.mention(query))) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === input, !mentionRows.isEmpty else { return false }
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            mentionIndex = (mentionIndex + 1) % mentionRows.count; highlightMention(); return true
        case #selector(NSResponder.moveUp(_:)):
            mentionIndex = (mentionIndex + mentionRows.count - 1) % mentionRows.count; highlightMention(); return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            pickMention(mentionIndex); return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismissedMention = mention?.query
            showMention(nil)
            return true
        default: return false
        }
    }

    /// The tab under @ becomes a chip, and the @ and what followed it leave the text.
    private func pickMention(_ index: Int) {
        guard let mention, mention.matches.indices.contains(index) else { return }
        let text = input.stringValue
        if let at = text.lastIndex(of: "@") { input.stringValue = String(text[..<at]) }
        dispatch(.assist(.attach([.tab(mention.matches[index].id)])))
        dispatch(.assist(.mention(nil)))
        window?.makeFirstResponder(input)
        input.currentEditor()?.selectedRange = NSRange(location: (input.stringValue as NSString).length, length: 0)
    }

    /// Tabs dragged from the sidebar are over the panel: its outline says it takes them.
    func showDropTarget(_ on: Bool) {
        layer?.borderWidth = on ? Metrics.ai.dropBorderWidth.value : Metrics.ai.borderWidth.value
        layer?.borderColor = (on ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
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
        if !input.isHidden {
            bottom -= row
            send.frame = CGRect(x: bounds.width - pad - m.sendWidth.value, y: bottom, width: m.sendWidth.value, height: row)
            input.frame = CGRect(x: pad, y: bottom + 2, width: send.frame.minX - gap - pad, height: row - 4)
            bottom -= gap
            // Chips sit on the input's edge, left to right, as many lines as they need.
            if !chipButtons.isEmpty {
                let height = m.chipHeight.value, width = bounds.width - pad * 2
                var lines: [[(AIChipButton, CGFloat)]] = [[]]
                var x: CGFloat = 0
                for chip in chipButtons {
                    let w = min(m.chipMaxWidth.value, chip.intrinsicContentSize.width + gap)
                    if x > 0, x + w > width { lines.append([]); x = 0 }
                    lines[lines.count - 1].append((chip, w))
                    x += w + gap / 2
                }
                for line in lines.reversed() {
                    bottom -= height
                    var left = pad
                    for (chip, w) in line { chip.frame = CGRect(x: left, y: bottom, width: w, height: height); left += w + gap / 2 }
                    bottom -= gap / 2
                }
                bottom -= gap / 2
            }
            // The @ list floats over the transcript, just above the input.
            if !mentionRows.isEmpty {
                let height = m.mentionRowHeight.value, inner = gap / 2
                var top = (chipButtons.first?.frame.minY ?? input.frame.minY) - gap / 2 - CGFloat(mentionRows.count) * height - inner * 2
                mentionBack.frame = CGRect(x: pad, y: top, width: bounds.width - pad * 2, height: CGFloat(mentionRows.count) * height + inner * 2)
                top += inner
                for row in mentionRows {
                    row.frame = CGRect(x: pad + inner, y: top, width: bounds.width - (pad + inner) * 2, height: height)
                    top += height
                }
            }
        }
        // The status line: what this conversation may do, a way to a folder, a way to the agent's settings.
        bottom -= row
        let settingsWidth = m.settingsWidth.value, folderWidth = folder.isHidden ? 0 : m.folderWidth.value
        settings.frame = CGRect(x: bounds.width - pad - settingsWidth, y: bottom, width: settingsWidth, height: row)
        folder.frame = CGRect(x: settings.frame.minX - gap - folderWidth, y: bottom, width: folderWidth, height: row)
        folderStatus.frame = CGRect(x: pad, y: bottom + 5, width: max(0, (folder.isHidden ? settings.frame.minX : folder.frame.minX) - gap - pad), height: row - 8)
        bottom -= gap
        if pendingApproval != nil {
            let inner = pad / 2
            let buttons = approvalButtons
            bottom -= row + inner
            var x = bounds.width - pad - inner
            for button in buttons.reversed() {
                let width = max(m.closeWidth.value, button.intrinsicContentSize.width + gap)
                x -= width
                button.frame = CGRect(x: x, y: bottom, width: width, height: row)
                x -= gap
            }
            bottom -= gap
            var top = bottom
            if !approvalDetail.isHidden {
                top -= m.approvalDetailHeight.value
                approvalDetail.frame = CGRect(x: pad + inner, y: top, width: bounds.width - (pad + inner) * 2, height: m.approvalDetailHeight.value)
            }
            top -= m.approvalTitleHeight.value
            approvalTitle.frame = CGRect(x: pad + inner, y: top, width: bounds.width - (pad + inner) * 2, height: m.approvalTitleHeight.value)
            approvalBack.frame = CGRect(x: pad, y: top - inner, width: bounds.width - pad * 2, height: (bounds.height - pad) - (top - inner) - (bounds.height - pad - bottom) + row + inner * 2 + gap)
            bottom = top - inner - gap
        }
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

/// A conversation's rows as text: the agent's words with their Markdown shown, steps and notices quieter.
enum AIConversationText {
    @MainActor static func attributed(_ item: AIConversationItem) -> NSAttributedString? {
        let bodySize = Metrics.ai.bodyFont.value, smallSize = Metrics.ai.stepFont.value
        switch item {
        case .user(let text):
            return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: bodySize, weight: .semibold), .foregroundColor: NSColor.labelColor])
        case .assistant(let text):
            return text.isEmpty ? nil : markdown(text.trimmingCharacters(in: .whitespacesAndNewlines), size: bodySize)
        case .step(let step):
            let mark = switch step.state { case .running: "⋯"; case .done: "✓"; case .failed: "✗" }
            return NSAttributedString(string: mark + " " + step.title, attributes: [.font: NSFont.systemFont(ofSize: smallSize), .foregroundColor: NSColor.secondaryLabelColor])
        case .approval(let approval):
            guard let answer = approval.answer, let option = approval.options.first(where: { $0.id == answer }) else { return nil }
            return NSAttributedString(string: option.title + ": " + approval.title, attributes: [.font: NSFont.systemFont(ofSize: smallSize), .foregroundColor: NSColor.secondaryLabelColor])
        case .notice(let text):
            return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: smallSize), .foregroundColor: NSColor.secondaryLabelColor])
        }
    }

    /// Agents answer in Markdown. Code blocks and headings by line, the rest through Foundation's inline parser.
    static func markdown(_ text: String, size: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let plain: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.labelColor]
        let code: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular), .foregroundColor: NSColor.labelColor]
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
                out.append(table(rows, size: size))
                continue
            }
            let hashes = line.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                out.append(inline(String(line.dropFirst(hashes + 1)), size: size, weight: .semibold))
            } else {
                out.append(inline(line, size: size, weight: .regular))
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

    /// Rows as an AppKit text table: hairline borders, the header row in semibold.
    private static func table(_ rows: [[String]], size: CGFloat) -> NSAttributedString {
        let columns = rows.map(\.count).max() ?? 1
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.collapsesBorders = true
        let out = NSMutableAttributedString()
        for (row, cells) in rows.enumerated() {
            for column in 0..<columns {
                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setWidth(4, type: .absoluteValueType, for: .padding)
                block.setWidth(Metrics.ai.borderWidth.value, type: .absoluteValueType, for: .border)
                block.setBorderColor(.separatorColor)
                if row == 0 { block.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06) }
                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                let cell = NSMutableAttributedString(attributedString: inline(column < cells.count ? cells[column] : "", size: size - 1, weight: row == 0 ? .semibold : .regular))
                cell.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: size - 1)]))
                cell.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: cell.length))
                out.append(cell)
            }
        }
        return out
    }

    private static func inline(_ line: String, size: CGFloat, weight: NSFont.Weight) -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let parsed = try? AttributedString(markdown: line, options: .init(allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: line, attributes: [.font: base, .foregroundColor: NSColor.labelColor])
        }
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            var font = base
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) { font = NSFont.systemFont(ofSize: size, weight: .semibold) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            if intent.contains(.code) { font = NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            if let link = run.link, ["http", "https", AgentTabLink.scheme].contains(link.scheme?.lowercased()) { attributes[.link] = link }
            out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return out
    }
}

/// A tab, folder or Space given to the next message: its title, and an × that takes it back.
@MainActor
private final class AIChipButton: NSButton {
    let chipID: String
    let chipTitle: String
    var onRemove: () -> Void = {}
    init(id: String, title: String) {
        chipID = id
        chipTitle = title
        super.init(frame: .zero)
        self.title = "✕  " + title
        bezelStyle = .inline; setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: Metrics.ai.stepFont.value)
        lineBreakMode = .byTruncatingTail
        target = self; action = #selector(pressed)
        setAccessibilityLabel("Remove " + title)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    @objc private func pressed() { onRemove() }
}

enum AgentCopyText {
    static func oneLine(_ text: String, limit: Int) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
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
