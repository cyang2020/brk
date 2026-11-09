import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The pages of one transcript: a sandboxed view for each page item, kept while the page stays in the transcript and
/// placed by its card row (`AIPageRowView`). A page's own height, once it reports one, wins over the one it was rendered
/// with. A page that leaves, or gets new data or HTML, commits what is being typed first, out of sight but still in the
/// window (`host`).
@MainActor
final class TranscriptPages {
    private var views: [AIPageID: PageSandboxView] = [:]
    private var revisions: [AIPageID: Int] = [:]
    private var heights: [AIPageID: Int] = [:]
    /// Where a page waits, out of sight, while it commits its edits on its way out.
    weak var host: NSView?
    /// The page saved its own state (`window.brk.save`).
    var onSave: ((AIPageID, String) -> Void)?
    var theme: PageTheme?
    var onEvent: ((AIPageID, PageSandboxEvent) -> Void)?
    var menu: ((AIPageID) -> [NSMenuItem])?
    /// A page's height changed, or a page was made anew: the transcript must be laid out again.
    var onHeight: (() -> Void)?

    /// The height a page shows at: what it reported last, else what it was rendered with, within Brk's limits.
    func height(_ page: AIPageSnapshot) -> Int { AIPageLimits.height(heights[page.id] ?? page.height) }

    /// The view for `page`: the one it has, the one on its way out (its edits in progress kept), or a new one. New data
    /// or HTML loads it again once the shown page has committed what is being typed; its own saves never do.
    func view(for page: AIPageSnapshot) -> PageSandboxView {
        if let old = views[page.id], revisions[page.id] != page.revision { replace(old, page: page.id) }
        if views[page.id] == nil, revisions[page.id] == page.revision, let back = leaving.removeValue(forKey: page.id) {
            back.identify(.aiControl("page-" + page.id.rawValue))
            views[page.id] = back
        }
        return views[page.id] ?? make(page)
    }

    /// Every page not in `shown` leaves.
    func keep(only shown: Set<AIPageID>) {
        for (id, view) in views where !shown.contains(id) { retire(view, page: id) }
    }

    /// Views committing their page's edits on their way out, by page.
    private var leaving: [AIPageID: PageSandboxView] = [:]
    private var replacing: Set<AIPageID> = []

    /// The page left the transcript: out of sight, still in the window so it runs, until it has committed its edits.
    private func retire(_ view: PageSandboxView, page: AIPageID) {
        views[page] = nil
        leaving[page] = view
        if let host, view.superview !== host { host.addSubview(view) }
        view.frame.origin.x = -100_000
        view.identify(.aiControl("page-leaving-" + page.rawValue))
        Task { @MainActor [weak self] in
            await view.commitEdits()
            guard let self, self.leaving[page] === view else { return }
            self.leaving[page] = nil
            if self.views[page] == nil { self.revisions[page] = nil }
            view.removeFromSuperview()
        }
    }

    /// New data or HTML: the shown page commits first, then the transcript is laid out again and the page made anew.
    private func replace(_ view: PageSandboxView, page: AIPageID) {
        guard replacing.insert(page).inserted else { return }
        Task { @MainActor [weak self] in
            await view.commitEdits()
            guard let self else { return }
            self.replacing.remove(page)
            if self.views[page] === view {
                view.removeFromSuperview()
                self.views[page] = nil
                self.revisions[page] = nil
            }
            self.onHeight?()
        }
    }

    /// A page on screen under `point` (window coordinates) that scrolls sideways there: it takes a two-finger swipe first.
    func scrollsSideways(atWindowPoint point: CGPoint) -> Bool {
        views.values.contains { !$0.isHiddenOrHasHiddenAncestor && $0.window != nil && $0.scrollsSideways(atWindowPoint: point) }
    }

    /// Commits every page's edits in progress (the transcript's view is about to go).
    func commitEdits() async {
        let commits = (Array(views.values) + Array(leaving.values)).map { page in Task { @MainActor in await page.commitEdits() } }
        for commit in commits { await commit.value }
    }

    func apply(_ theme: PageTheme) {
        self.theme = theme
        for view in views.values { view.apply(theme) }
    }

    func removeAll() {
        for (page, view) in views { retire(view, page: page) }
    }

    private func make(_ page: AIPageSnapshot) -> PageSandboxView {
        let html = (try? String(contentsOf: page.html, encoding: .utf8)) ?? Self.missing
        let view = PageSandboxView(html: html, data: page.data, saved: page.saved, saveSchema: page.saveSchema, theme: theme ?? PageTheme(.fallbackLight), page: page.id)
        view.identify(.aiControl("page-" + page.id.rawValue))
        let id = page.id
        revisions[id] = page.revision
        view.onSave = { [weak self] text in self?.onSave?(id, text) }
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

/// The kept pages a window's cards show, each in the sandbox under a caption row (docs/design/ai-right-panel.md): the
/// page's name and how often it refreshes on the left, as above a page in the panel, and a button back to the conversation
/// that made it on the right (none once that conversation is deleted). A page whose card goes (its tab hidden or switched
/// away) first commits an edit in progress (`PageSandboxView.commitEdits`), out of sight but still in the window; shown
/// again meanwhile, the same view comes back. New data or HTML for a shown page waits for the old page to commit before the
/// new one loads.
@MainActor
final class AIPageCardsView {
    private typealias Entry = (page: AIPageID, revision: Int, view: PageSandboxView, back: NSView, caption: AIPageCaptionView)
    private let dispatch: Dispatch
    private var views: [PageID: Entry] = [:]
    /// Views committing their page's edits on their way out, by page.
    private var leaving: [AIPageID: Entry] = [:]
    /// Cards whose shown page commits before new data or HTML replaces it.
    private var replacing: Set<PageID> = []
    private var last: (cards: [AIPageCard], frames: [CardFrame], theme: ResolvedTheme)?
    weak var parent: NSView?
    var below: NSView?

    init(dispatch: @escaping Dispatch) { self.dispatch = dispatch }

    func render(_ cards: [AIPageCard], frames: [CardFrame], theme: ResolvedTheme) {
        last = (cards, frames, theme)
        var seen = Set<PageID>()
        let pageTheme = PageTheme(theme, background: theme.scheme == .light ? RGBA(1, 1, 1) : RGBA(hex: "#202124"))
        for card in cards {
            guard let frame = frames.first(where: { if case .aiPage(let page, _) = $0.content { page == card.page } else { false } }) else { continue }
            seen.insert(card.page)
            let content = card.content
            let revision = content?.revision ?? 0
            if let existing = views[card.page], existing.page != content?.id || existing.revision != revision {
                if existing.page == content?.id {
                    // New data or HTML for this page: it is loaded again once the page has committed what is being typed.
                    replace(existing, of: card.page)
                    place(existing, in: frame, theme: pageTheme, content: content, style: AIPanelStyle(theme, onCard: true))
                    continue
                }
                retire(existing)
                views[card.page] = nil
            }
            let entry = views[card.page] ?? content.flatMap { comeBack($0.id, revision: revision) } ?? make(content, theme: pageTheme)
            views[card.page] = entry
            place(entry, in: frame, theme: pageTheme, content: content, style: AIPanelStyle(theme, onCard: true))
        }
        for (page, entry) in views where !seen.contains(page) {
            retire(entry)
            views[page] = nil
        }
    }

    private func make(_ content: AIPageSnapshot?, theme: PageTheme) -> Entry {
        let back = NSView()
        back.wantsLayer = true
        back.layer?.masksToBounds = true
        back.identify(.aiControl("page-card"))
        let html = content.flatMap { try? String(contentsOf: $0.html, encoding: .utf8) } ?? TranscriptPages.missing
        let view = PageSandboxView(html: html, data: content?.data, saved: content?.saved, saveSchema: content?.saveSchema, theme: theme, page: content?.id)
        view.identify(.aiControl("page-card-view"))
        let id = content?.id
        view.onEvent = { [weak self] event in
            if case .link(let url) = event, let id { self?.dispatch(.assist(.pageLink(id, url))) }
        }
        if let id { view.onSave = { [weak self] text in self?.dispatch(.assist(.pageSave(id, text))) } }
        back.addSubview(view)
        let caption = AIPageCaptionView()
        caption.onConversation = { [weak self] id in self?.dispatch(.assist(.showConversation(id))) }
        back.addSubview(caption)
        return (page: content?.id ?? AIPageID(""), revision: content?.revision ?? 0, view: view, back: back, caption: caption)
    }

    private func place(_ entry: Entry, in frame: CardFrame, theme: PageTheme, content: AIPageSnapshot?, style: AIPanelStyle) {
        if entry.back.superview == nil, let parent {
            if let below { parent.addSubview(entry.back, positioned: .below, relativeTo: below) } else { parent.addSubview(entry.back) }
        }
        entry.back.frame = frame.rect
        entry.back.layer?.cornerRadius = frame.cornerRadius
        entry.back.layer?.backgroundColor = theme.backgroundColor.cgColor
        let m = Metrics.ai, inset = m.keptPageInset.value
        let captionWidth = max(0, entry.back.bounds.width - inset * 2)
        entry.caption.frame = CGRect(x: inset, y: inset / 2, width: captionWidth, height: m.pageHeaderHeight.value)
        entry.caption.show(content, style: style)
        let top = entry.caption.frame.maxY + m.keptPageGap.value
        entry.view.frame = CGRect(x: inset, y: top, width: captionWidth, height: max(0, entry.back.bounds.height - top - inset))
        entry.view.apply(theme)
    }

    /// The card went: out of sight, still in the window so the page runs, until it has committed its edits. It answers
    /// to other identifiers meanwhile, so nothing takes it for the shown page.
    private func retire(_ entry: Entry) {
        leaving[entry.page] = entry
        entry.back.frame.origin.x = -100_000
        entry.back.identify(.aiControl("page-card-leaving"))
        entry.view.identify(.aiControl("page-card-view-leaving"))
        entry.caption.identify(.aiControl("page-caption-leaving"))
        Task { @MainActor [weak self] in
            await entry.view.commitEdits()
            guard let self, self.leaving[entry.page]?.view === entry.view else { return }
            self.leaving[entry.page] = nil
            entry.back.removeFromSuperview()
        }
    }

    /// The page's view that is on its way out, back on screen as it is (its edits in progress included).
    private func comeBack(_ page: AIPageID, revision: Int) -> Entry? {
        guard let entry = leaving[page], entry.revision == revision else { return nil }
        leaving[page] = nil
        entry.back.identify(.aiControl("page-card"))
        entry.view.identify(.aiControl("page-card-view"))
        entry.caption.identify(.aiControl("page-caption"))
        return entry
    }

    private func replace(_ entry: Entry, of card: PageID) {
        guard replacing.insert(card).inserted else { return }
        Task { @MainActor [weak self] in
            await entry.view.commitEdits()
            guard let self else { return }
            self.replacing.remove(card)
            if self.views[card]?.view === entry.view {
                entry.back.removeFromSuperview()
                self.views[card] = nil
            }
            if let last = self.last { self.render(last.cards, frames: last.frames, theme: last.theme) }
        }
    }

    var allViews: [NSView] { views.values.map(\.back) }
}

/// A kept page's caption row at the top of its card: its name and refresh frequency, a hairline under them, and a button
/// that opens the conversation that made it in the panel (`AIIntent.showConversation`; another Space's switches there).
/// The words follow the conversation's language.
@MainActor
final class AIPageCaptionView: NSView {
    private let title = aiLabel(Metrics.ai.stepFont.value, weight: .semibold)
    private let schedule = aiLabel(Metrics.ai.noticeFont.value)
    private let open = AIIconButton(symbol: "bubble.left.and.bubble.right", tip: "")
    private let rule = NSView()
    private var conversation: AIRequestID?
    var onConversation: ((AIRequestID) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        identify(.aiControl("page-caption"))
        rule.wantsLayer = true
        open.identify(.aiControl("page-conversation"))
        open.layer?.cornerRadius = Metrics.ai.iconRadius.value
        open.onPress = { [weak self] in if let id = self?.conversation { self?.onConversation?(id) } }
        for view in [title, schedule, rule, open] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    /// The card under it is a drag region of nothing: a press on the row must not move the window.
    override var mouseDownCanMoveWindow: Bool { false }

    func show(_ content: AIPageSnapshot?, style: AIPanelStyle) {
        let copy = AIPanelCopy(language: content?.language ?? .en)
        conversation = content?.conversation
        title.stringValue = content?.title ?? ""
        title.textColor = style.cardText
        title.toolTip = content?.title
        schedule.stringValue = content?.schedule.map { "· " + copy.schedule($0) } ?? ""
        schedule.textColor = style.cardText.withAlphaComponent(0.5)
        open.isHidden = content?.conversation == nil
        open.tooltip(AIThreadWords.openConversation(copy.language))
        open.tint = style.cardText.withAlphaComponent(0.55)
        open.hoverFill = style.scheme == .light ? NSColor(white: 0, alpha: 0.06) : NSColor(white: 1, alpha: 0.1)
        open.pressFill = open.hoverFill
        rule.layer?.backgroundColor = style.separator.cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let m = Metrics.ai, header = bounds.height
        open.frame = CGRect(x: bounds.width - m.iconSize.value, y: (header - m.iconSize.value) / 2, width: m.iconSize.value, height: m.iconSize.value)
        let lineHeight = ceil(title.intrinsicContentSize.height)
        let y = ((header - lineHeight) / 2).rounded()
        let room = (open.isHidden ? bounds.width : open.frame.minX) - 4
        let titleWidth = min(CGFloat(title.cellWidth), room * 0.7)
        title.frame = CGRect(x: 0, y: y, width: titleWidth, height: lineHeight)
        schedule.frame = CGRect(x: title.frame.maxX + 4, y: y + 1, width: max(0, room - titleWidth - 4), height: lineHeight)
        rule.frame = CGRect(x: 0, y: header - 1, width: bounds.width, height: 1)
    }
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
