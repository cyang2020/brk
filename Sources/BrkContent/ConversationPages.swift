import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The space a page takes in a transcript's text: an attachment as wide as the text and as tall as the page. The page
/// itself is a `PageSandboxView` laid over it (`TranscriptPages`), so it scrolls with the text.
final class PageAttachmentCell: NSTextAttachmentCell {
    let page: AIPageID
    var size: NSSize
    init(page: AIPageID, size: NSSize) {
        self.page = page
        self.size = size
        super.init(textCell: "")
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError("not used") }
    override func cellSize() -> NSSize { size }
    override func cellBaselineOffset() -> NSPoint { .zero }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}
    override func wantsToTrackMouse() -> Bool { false }
}

/// The row under a page in a transcript: its title, and Keep as Tab (Show Tab once kept).
@MainActor
final class PageCaptionView: NSView {
    private let title = NSTextField(labelWithString: "")
    let keep = NSButton(title: "Keep as Tab", target: nil, action: nil)
    var onKeep: (() -> Void)?

    init(page: AIPageID) {
        super.init(frame: .zero)
        title.font = .systemFont(ofSize: Metrics.ai.stepFont.value)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.usesSingleLineMode = true
        title.cell?.wraps = false
        keep.isBordered = false
        keep.font = .systemFont(ofSize: Metrics.ai.stepFont.value, weight: .medium)
        keep.contentTintColor = .linkColor
        keep.target = self
        keep.action = #selector(pressed)
        keep.identify(.aiControl("keep-" + page.rawValue))
        keep.toolTip = "Keep this page as a tab in the sidebar, with its data and this conversation."
        addSubview(title)
        addSubview(keep)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    @objc private func pressed() { onKeep?() }

    func show(_ page: AIPageSnapshot) {
        title.stringValue = page.title
        keep.title = page.kept ? "Show Tab" : "Keep as Tab"
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = ceil(keep.intrinsicContentSize.width) + 8
        keep.frame = CGRect(x: bounds.width - width, y: 0, width: width, height: bounds.height)
        title.frame = CGRect(x: 0, y: (bounds.height - 16) / 2, width: max(0, keep.frame.minX - 8), height: 16)
    }
}

/// The pages of one transcript: a sandboxed view for each page item, placed over its attachment with its caption row
/// under it, kept while the page stays in the transcript. A page's own height, once it reports one, wins over the one
/// it was rendered with.
@MainActor
final class TranscriptPages {
    private weak var text: NSTextView?
    private var views: [AIPageID: PageSandboxView] = [:]
    private var captions: [AIPageID: PageCaptionView] = [:]
    var onKeep: ((AIPageID) -> Void)?
    /// The caption row under each page.
    static let captionHeight: CGFloat = 26
    private var heights: [AIPageID: Int] = [:]
    var theme: PageTheme?
    var onEvent: ((AIPageID, PageSandboxEvent) -> Void)?
    var menu: ((AIPageID) -> [NSMenuItem])?
    /// A page's height changed: the text must be laid out again.
    var onHeight: (() -> Void)?

    init(text: NSTextView) { self.text = text }

    private var cache: [AIPageID: (size: NSSize, text: NSAttributedString)] = [:]

    /// The attachment for `page`, `width` wide; the same object while its size stays, so unchanged text compares equal.
    func attachment(_ page: AIPageSnapshot, width: CGFloat) -> NSAttributedString {
        let size = NSSize(width: max(40, width.rounded(.down)), height: CGFloat(AIPageLimits.height(heights[page.id] ?? page.height)) + Self.captionHeight)
        if let cached = cache[page.id], cached.size == size { return cached.text }
        let attachment = NSTextAttachment()
        attachment.attachmentCell = PageAttachmentCell(page: page.id, size: size)
        let text = NSAttributedString(attachment: attachment)
        cache[page.id] = (size, text)
        return text
    }

    /// Places a view over every page attachment in the text, making the ones that are new; drops the rest.
    func place(_ pages: [AIPageSnapshot]) {
        guard let text, let storage = text.textStorage, let layout = text.layoutManager, let container = text.textContainer else { return }
        layout.ensureLayout(for: container)
        var seen = Set<AIPageID>()
        let origin = text.textContainerOrigin
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let cell = (value as? NSTextAttachment)?.attachmentCell as? PageAttachmentCell, let page = pages.first(where: { $0.id == cell.page }) else { return }
            seen.insert(page.id)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            rect.size = cell.size
            let view = views[page.id] ?? make(page)
            if view.superview !== text { text.addSubview(view) }
            view.frame = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - Self.captionHeight)
            let caption = captions[page.id] ?? {
                let made = PageCaptionView(page: page.id)
                made.onKeep = { [weak self] in self?.onKeep?(page.id) }
                captions[page.id] = made
                return made
            }()
            if caption.superview !== text { text.addSubview(caption) }
            caption.frame = CGRect(x: rect.minX, y: rect.maxY - Self.captionHeight, width: rect.width, height: Self.captionHeight)
            caption.show(page)
        }
        for (id, view) in views where !seen.contains(id) {
            view.removeFromSuperview()
            views[id] = nil
            captions.removeValue(forKey: id)?.removeFromSuperview()
            cache[id] = nil
        }
    }

    func apply(_ theme: PageTheme) {
        self.theme = theme
        for view in views.values { view.apply(theme) }
    }

    func removeAll() {
        for view in views.values { view.removeFromSuperview() }
        for caption in captions.values { caption.removeFromSuperview() }
        views = [:]
        captions = [:]
    }

    private func make(_ page: AIPageSnapshot) -> PageSandboxView {
        let html = (try? String(contentsOf: page.html, encoding: .utf8)) ?? Self.missing
        let view = PageSandboxView(html: html, data: page.data, theme: theme ?? PageTheme(.fallbackLight), page: page.id)
        view.identify(.aiControl("page-" + page.id.rawValue))
        let id = page.id
        view.onEvent = { [weak self] event in
            guard let self else { return }
            if case .height(let value) = event {
                let height = AIPageLimits.height(value)
                if self.heights[id] != height { self.heights[id] = height; self.onHeight?() }
            }
            self.onEvent?(id, event)
        }
        view.menuItems = { [weak self] in self?.menu?(id) ?? [] }
        views[page.id] = view
        return view
    }

    static let missing = "<!doctype html><p style=\"color:var(--muted-foreground)\">This page's file is missing.</p>"
}

extension ResolvedTheme {
    /// A theme for the moment before the first snapshot names one.
    static var fallbackLight: ResolvedTheme { resolveTheme(.default, systemScheme: .light) }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void
    init(_ title: String, enabled: Bool = true, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: enabled ? #selector(fire) : nil, keyEquivalent: "")
        target = self
        isEnabled = enabled
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { run() }
}

/// The conversation tabs a window's cards show: one document view per card, in its tab style.
@MainActor
final class ConversationCardsView {
    private let dispatch: Dispatch
    private var views: [PageID: AIAnswerDocumentView] = [:]
    weak var parent: NSView?
    /// Views above which the cards sit (the panel, overlays): kept in front.
    var below: NSView?

    init(dispatch: @escaping Dispatch) { self.dispatch = dispatch }

    func render(_ cards: [ConversationCard], frames: [CardFrame], theme: ResolvedTheme) {
        var seen = Set<PageID>()
        for card in cards {
            guard let frame = frames.first(where: { if case .conversation(let page, _) = $0.content { page == card.page } else { false } }) else { continue }
            seen.insert(card.page)
            let view = views[card.page] ?? {
                let made = AIAnswerDocumentView(dispatch: dispatch, style: .tab)
                views[card.page] = made
                return made
            }()
            if view.superview == nil, let parent {
                if let below { parent.addSubview(view, positioned: .below, relativeTo: below) } else { parent.addSubview(view) }
            }
            view.layer?.cornerRadius = frame.cornerRadius
            view.render(card.answer, in: frame.rect, theme: theme)
        }
        for (page, view) in views where !seen.contains(page) {
            view.removeFromSuperview()
            views[page] = nil
        }
    }

    /// The card under a drop of tabs, if any shows a conversation there.
    func view(at point: CGPoint) -> AIAnswerDocumentView? { views.values.first { !$0.isHidden && $0.frame.contains(point) } }
    func clearDropTargets() { for view in views.values { view.showDropTarget(false) } }
    var allViews: [NSView] { Array(views.values) }
}

/// The kept pages a window's cards show, each in the sandbox, filling its card.
@MainActor
final class AIPageCardsView {
    private let dispatch: Dispatch
    private var views: [PageID: (page: AIPageID, view: PageSandboxView, back: NSView)] = [:]
    weak var parent: NSView?
    var below: NSView?

    init(dispatch: @escaping Dispatch) { self.dispatch = dispatch }

    func render(_ cards: [AIPageCard], frames: [CardFrame], theme: ResolvedTheme) {
        var seen = Set<PageID>()
        let pageTheme = PageTheme(theme, background: theme.scheme == .light ? RGBA(1, 1, 1) : RGBA(hex: "#202124"))
        for card in cards {
            guard let frame = frames.first(where: { if case .aiPage(let page, _) = $0.content { page == card.page } else { false } }) else { continue }
            seen.insert(card.page)
            let content = card.content
            if let existing = views[card.page], existing.page != content?.id {
                existing.back.removeFromSuperview()
                views[card.page] = nil
            }
            let entry = views[card.page] ?? {
                let back = NSView()
                back.wantsLayer = true
                back.layer?.masksToBounds = true
                back.identify(.aiControl("page-card"))
                let html = content.flatMap { try? String(contentsOf: $0.html, encoding: .utf8) } ?? TranscriptPages.missing
                let view = PageSandboxView(html: html, data: content?.data, theme: pageTheme, page: content?.id)
                let id = content?.id
                view.onEvent = { [weak self] event in
                    if case .link(let url) = event, let id { self?.dispatch(.assist(.pageLink(id, url))) }
                }
                back.addSubview(view)
                let made = (page: content?.id ?? AIPageID(""), view: view, back: back)
                views[card.page] = made
                return made
            }()
            if entry.back.superview == nil, let parent {
                if let below { parent.addSubview(entry.back, positioned: .below, relativeTo: below) } else { parent.addSubview(entry.back) }
            }
            entry.back.frame = frame.rect
            entry.back.layer?.cornerRadius = frame.cornerRadius
            entry.back.layer?.backgroundColor = pageTheme.backgroundColor.cgColor
            let inset = Metrics.ai.tabColumnInset.value
            entry.view.frame = entry.back.bounds.insetBy(dx: inset, dy: inset)
            entry.view.apply(pageTheme)
        }
        for (page, entry) in views where !seen.contains(page) {
            entry.back.removeFromSuperview()
            views[page] = nil
        }
    }

    var allViews: [NSView] { views.values.map(\.back) }
}

/// Asks before a link in an agent's page opens a new address (`AIPageLinkPrompt`).
@MainActor
final class PageLinkPromptView: NSView {
    private let dispatch: Dispatch
    private let title = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let open = NSButton(title: "Open", target: nil, action: nil)
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    private let material = NSVisualEffectView()

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        wantsLayer = true
        layer?.cornerRadius = Metrics.ai.cornerRadius.value
        layer?.masksToBounds = true
        layer?.borderWidth = Metrics.ai.borderWidth.value
        layer?.borderColor = NSColor.separatorColor.cgColor
        material.material = .popover; material.blendingMode = .withinWindow; material.state = .active
        identify(.aiControl("page-link-prompt"))
        title.font = .systemFont(ofSize: Metrics.ai.bodyFont.value, weight: .semibold)
        title.maximumNumberOfLines = 1; title.lineBreakMode = .byTruncatingMiddle; title.usesSingleLineMode = true
        detail.font = .systemFont(ofSize: Metrics.ai.stepFont.value)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        detail.stringValue = "This page was written by an agent after it read web pages, and this address is new to this profile. The address itself can carry what the agent read."
        open.bezelStyle = .rounded; open.keyEquivalent = "\r"
        cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        open.target = self; open.action = #selector(answerOpen)
        cancel.target = self; cancel.action = #selector(answerCancel)
        open.identify(.aiControl("page-link-open"))
        cancel.identify(.aiControl("page-link-cancel"))
        for view in [material, title, detail, open, cancel] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    @objc private func answerOpen() { dispatch(.assist(.answerPageLink(true))) }
    @objc private func answerCancel() { dispatch(.assist(.answerPageLink(false))) }

    func render(_ prompt: AIPageLinkPrompt?, in area: CGRect) {
        isHidden = prompt == nil
        guard let prompt else { return }
        title.stringValue = "Open " + AgentCopyText.oneLine(prompt.url.absoluteString, limit: 160) + "?"
        let m = Metrics.ai
        let width = min(m.linkPromptWidth.value, area.width - m.inset.value * 2)
        frame = CGRect(x: area.midX - width / 2, y: area.minY + m.inset.value * 3, width: width, height: m.linkPromptHeight.value)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let m = Metrics.ai, pad = m.padding.value / 1.5, row = m.buttonHeight.value, gap = m.gap.value
        material.frame = bounds
        title.frame = CGRect(x: pad, y: pad, width: bounds.width - pad * 2, height: 20)
        detail.frame = CGRect(x: pad, y: title.frame.maxY + gap / 2, width: bounds.width - pad * 2, height: 34)
        open.frame = CGRect(x: bounds.width - pad - 76, y: bounds.height - pad - row, width: 76, height: row)
        cancel.frame = CGRect(x: open.frame.minX - gap - 76, y: open.frame.minY, width: 76, height: row)
    }
}
