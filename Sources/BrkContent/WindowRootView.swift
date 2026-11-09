import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkLibrary
import BrkOverlays
import BrkSidebar
import BrkTheme
import BrkUIKit

/// Owner: W2 (the Library slot: F5). A window's content view. Bottom to top: themed background, anchored sidebar,
/// content cards (page surfaces inside), the History page over its card, the Library (its panel in place of the
/// sidebar; the archive is one of its pages), the Peek card, floating sidebar (only while peeking a hidden sidebar),
/// command bar, space dialog (SwiftUI in an NSHostingView). TODO(F2): the profile dialog host.
/// Native views above Chromium's moved views draw and take focus normally (spike unknown 2, embed mode).
@MainActor
public final class WindowRootView: NSView {
    private let dispatch: Dispatch
    public let background = ThemeBackgroundView(frame: .zero)
    /// Over the background: lighter while the app is not frontmost, darker while websites are set to Dark (Arc, P01-d, P19-b).
    private let inactiveVeil = InactiveVeilView(frame: .zero)
    public let toolbar: AddressToolbarView
    public let sidebar: SidebarView
    public let content: ContentAreaView
    public let library: LibraryView
    public let history: HistoryPageView
    public let easel: EaselBoardView
    public let peek: PeekCardView
    public let findBar: FindBarView
    public let commandBar: CommandBarView
    public let spaceDialog: SpaceDialogHost
    private let zapOverlay: BoostZapOverlayView
    private let boostPanel: BoostPanel
    private let aiAnswer: AIPanelView
    /// The Library's "AI 对话" page's selected conversation, over the content card.
    private let libraryConversation: LibraryConversationPreview
    /// Conversation tabs and kept pages, drawn over their cards like History and Easels.
    private let conversationCards: ConversationCardsView
    private let pageCards: AIPageCardsView
    private let linkPrompt: PageLinkPromptView
    private let aiPreview: AIPreviewCardView
    private let linkStatus = LinkStatusCapsule()
    private let captureOverlay: CaptureOverlayView
    private let tabTools: TabToolsOverlayView
    private var lastTheme: ResolvedTheme?
    private var libraryProgress: Double?
    private var sidebarFloats = false
    /// The Create a Space draft while the flow is open: its theme on the window and its icon in the dock (Arc shows
    /// both before the space exists, P24 flow).
    private var draft: (theme: SpaceTheme, icon: SpaceIcon)?
    private var last: (snapshot: WindowSnapshot, frames: WindowFrames)?
    private let thumbnails = PageThumbnails()
    private var switcherShown = false
    /// Takes the window's image as the window server shows it (BrkApp's `WindowCapture`), for the Ctrl+Tab
    /// switcher's page images. Nil (tests): the switcher shows white cards.
    public var captureWindow: (() -> CGImage?)? {
        get { thumbnails.capture }
        set { thumbnails.capture = newValue }
    }
    private let loadingBar = LoadingBarView(frame: .zero)

    public init(dispatch: @escaping Dispatch) {
        zapOverlay = BoostZapOverlayView(dispatch: dispatch)
        boostPanel = BoostPanel(dispatch: dispatch)
        aiAnswer = AIPanelView(dispatch: dispatch)
        libraryConversation = LibraryConversationPreview(dispatch: dispatch)
        conversationCards = ConversationCardsView(dispatch: dispatch)
        pageCards = AIPageCardsView(dispatch: dispatch)
        linkPrompt = PageLinkPromptView(dispatch: dispatch)
        aiPreview = AIPreviewCardView(dispatch: dispatch)
        captureOverlay = CaptureOverlayView(dispatch: dispatch)
        tabTools = TabToolsOverlayView(dispatch: dispatch)
        self.dispatch = dispatch
        toolbar = AddressToolbarView(dispatch: dispatch)
        sidebar = SidebarView(dispatch: dispatch)
        content = ContentAreaView(dispatch: dispatch)
        library = LibraryView(dispatch: dispatch)
        history = HistoryPageView(dispatch: dispatch)
        easel = EaselBoardView(dispatch: dispatch)
        peek = PeekCardView(dispatch: dispatch)
        findBar = FindBarView(dispatch: dispatch)
        commandBar = CommandBarView(dispatch: dispatch)
        spaceDialog = SpaceDialogHost(dispatch: dispatch)
        super.init(frame: .zero)
        wantsLayer = true
        for view in [background, inactiveVeil, sidebar, content, history, easel, toolbar, loadingBar, library, libraryConversation, peek, findBar, aiAnswer, linkPrompt, linkStatus, aiPreview, commandBar, spaceDialog, tabTools, zapOverlay, captureOverlay] as [NSView] { addSubview(view) }
        conversationCards.parent = self
        conversationCards.below = toolbar
        pageCards.parent = self
        pageCards.below = toolbar
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak veil = inactiveVeil] _ in
                guard let veil else { return }
                MainActor.assumeIsolated { veil.update() }
            }
        }
        background.identify(.themeBackground)
        sidebar.edgeViewsAbove = loadingBar   // the resize handle over the cards and the toolbar
        sidebar.contentDrop = { [weak content] item, point in content?.dropCommand(item, at: point) }
        sidebar.contentDropCardSize = { [weak content] in content?.dropCardSize ?? .zero }
        sidebar.beginContentDrop = { [weak content] item in content?.beginDrop(item) }
        sidebar.endContentDrop = { [weak content, weak aiAnswer, weak self] in
            content?.endDrop()
            aiAnswer?.showDropTarget(false)
            self?.conversationCards.clearDropTargets()
        }
        sidebar.panelSpaceDrop = { [weak aiAnswer, weak self] space, point in
            guard let aiAnswer, !aiAnswer.isHidden, aiAnswer.frame.contains(point) else {
                aiAnswer?.showDropTarget(false)
                // A conversation's tab takes the drop like the panel does.
                if let tab = self?.conversationCards.view(at: point), let id = tab.conversationID { tab.showDropTarget(true); return .assist(.inTab(id, .attach([.space(space)]))) }
                return nil
            }
            aiAnswer.showDropTarget(true)
            return .assist(.attach([.space(space)]))
        }
        sidebar.panelDropEnded = { [weak aiAnswer, weak self] in aiAnswer?.showDropTarget(false); self?.conversationCards.clearDropTargets() }
        sidebar.panelDrop = { [weak content, weak aiAnswer, weak self] item, kind, point in
            guard let aiAnswer, !aiAnswer.isHidden, aiAnswer.frame.contains(point) else {
                aiAnswer?.showDropTarget(false)
                guard let tab = self?.conversationCards.view(at: point), let id = tab.conversationID, kind != .section else { self?.conversationCards.clearDropTargets(); return nil }
                if kind == .tab { _ = content?.dropCommand(item, at: CGPoint(x: -1, y: -1)) }
                tab.showDropTarget(true)
                return .assist(.inTab(id, .attach([kind == .folder ? .folder(item) : .tab(item.rawValue)])))
            }
            // The page under the panel shows no drop slot while the panel takes the drop.
            if kind == .tab { _ = content?.dropCommand(item, at: CGPoint(x: -1, y: -1)) }
            aiAnswer.showDropTarget(true)
            switch kind {
            case .tab, .split: return .assist(.attach([.tab(item.rawValue)]))
            case .folder: return .assist(.attach([.folder(item)]))
            case .section: return nil
            }
        }
        // Both span the window from its top left, so the Library's coordinates are the dialog host's.
        spaceDialog.cardHeader = { [weak library] space in library?.spaceCardHeader(space) }
        sidebar.onThemeBlend = { [weak background] from, to, progress in background?.scrub(from: from, to: to, progress: progress) }
        sidebar.onThemeBlendEnded = { [weak self] in
            guard let self, let theme = self.lastTheme else { return }
            self.background.show(theme, animated: false)
        }
        sidebar.onLibraryProgress = { [weak self] progress in self?.libraryMoved(progress) }
        spaceDialog.onDraft = { [weak self] draft in
            guard let self else { return }
            self.draft = draft
            if let last = self.last { self.renderChrome(last.snapshot, frames: last.frames) }
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }
    public func cancelDrag() -> Bool { sidebar.cancelDrag() }

    /// Gives keyboard focus to the native view a `FocusTarget` names. Returns false for `.page` and `.none` (the
    /// engine's business, handled by the window controller) and when the view is not on screen yet. This is the
    /// only way BrkApp reaches a view's focus: the fields themselves are internal to their targets.
    public func focus(_ target: FocusTarget) -> Bool {
        switch target {
        case .capture: window?.makeFirstResponder(captureOverlay) ?? false
        case .findInput: findBar.focusInput()
        case .commandBarInput: commandBar.focusInput()
        case .renameField(let item): sidebar.focusRenameField(item)
        case .spaceDialog: spaceDialog.focusForm()
        case .easel: easel.focusBoard()
        case .profileDialog: ProfileDialogHost.focus(over: spaceDialog)
        case .sidebar: sidebar.focusList()
        case .page, .none: false
        }
    }

    /// The sidebar's swipe between Spaces, else the AI panel's between its list and its conversation.
    public func handleScrollWheel(_ event: NSEvent) -> Bool { sidebar.handleScrollWheel(event) || aiAnswer.handleScrollWheel(event) }

    /// The title still being typed on Easel `id`'s board, committed first (`EaselBoardView.commitTitle(of:)`).
    public func commitEaselTitle(_ id: EaselID) -> String? { easel.commitTitle(of: id) }

    /// ⇧⌘-drag on the page (Arc's capture shortcut): the capture that is about to begin starts from this mouse-down.
    public func expectCaptureShortcut(_ expected: Bool) { captureOverlay.expectShortcutDrag(expected) }

    /// Applies one snapshot. `surface` looks up the engine's view for a page (nil until the page exists).
    ///
    /// Order: background (crossfade when the theme changed and this is not the first render), sidebar (anchored or
    /// floating: same view, re-parented above `content` while floating), content cards (each card hosts the
    /// surface for its pane; a surface that moved to another card is simply re-added there), Library, command bar.
    public func render(_ snapshot: WindowSnapshot, frames: WindowFrames, surface: (PageID) -> NSView?) {
        last = (snapshot, frames)
        // The screen still shows the last frame: the page the switcher starts from is taken before it covers it.
        thumbnails.beforeRender(opening: snapshot.tabTools.recent != nil && !switcherShown, in: self)
        switcherShown = snapshot.tabTools.recent != nil
        if frames.sidebarFloats != sidebarFloats {
            sidebarFloats = frames.sidebarFloats
            sidebar.removeFromSuperview()
            if sidebarFloats { addSubview(sidebar, positioned: .above, relativeTo: peek) }
            else { addSubview(sidebar, positioned: .above, relativeTo: inactiveVeil) }
        }
        renderChrome(snapshot, frames: frames)
        defer { placeForLibrary() }
        let palette = Palette(snapshot.theme)
        content.isDropEnabled = snapshot.find == nil && snapshot.overlay == nil && snapshot.dialog == nil && snapshot.profileDialog == nil && snapshot.pendingSpaceDeletion == nil && snapshot.pendingEaselDeletion == nil && snapshot.pendingConversationDeletion == nil
        content.render(snapshot.content, frames: frames, theme: snapshot.theme, palette: palette, surface: surface)
        // Arc's Create a Space flow shows no page: the content area is a blank card over the draft's theme.
        content.isHidden = snapshot.dialog == .newSpace
        let historyCard = frames.cards.first { if case .history = $0.content { true } else { false } }
        let historyPage: PageID? = if case .history(let page)? = historyCard?.content { page } else { nil }
        history.render(snapshot.history, page: historyPage, in: historyCard?.rect, scheme: palette.scheme, now: snapshot.now, meaning: snapshot.historyMeaning)
        history.layer?.cornerRadius = historyCard?.cornerRadius ?? 0
        // One board at a time: the focused card's Easel, else the first card showing one.
        let easelCards = frames.cards.filter { if case .easel = $0.content { true } else { false } }
        let easelCard = easelCards.first { card in snapshot.content.panes.indices.contains(card.pane) && snapshot.content.panes[card.pane].focused } ?? easelCards.first
        let shownEasel = easelCard.flatMap { card in snapshot.easels.first { if case .easel(let page, _) = card.content { $0.page == page } else { false } } }
        easel.render(shownEasel, in: easelCard?.rect, cornerRadius: easelCard?.cornerRadius ?? 0)
        conversationCards.render(snapshot.conversations, frames: frames.cards, theme: snapshot.theme, agents: snapshot.aiAgents)
        pageCards.render(snapshot.aiPages, frames: frames.cards, theme: snapshot.theme)
        toolbar.render(snapshot.urlPill, rect: frames.toolbar, palette: palette)
        let focusedCard = snapshot.content.panes.firstIndex(where: \.focused).flatMap { i in frames.cards.first { $0.pane == i }?.rect } ?? frames.cards.first?.rect
        loadingBar.render(loading: snapshot.urlPill.loading && snapshot.overlay == nil, progress: snapshot.urlPill.loadProgress,
                          over: focusedCard.map { card in frames.toolbar.map { CGRect(x: card.minX, y: $0.minY, width: card.width, height: card.maxY - $0.minY) } ?? card },
                          scheme: palette.scheme)
        var librarySnapshot: LibrarySnapshot?, barSnapshot: CommandBarSnapshot?, peekSnapshot: PeekSnapshot?
        switch snapshot.overlay {
        case .library(let l)?: librarySnapshot = l
        case .peek(let p)?: peekSnapshot = p
        case .commandBar(let b)?: barSnapshot = b
        case nil: break
        }
        library.render(librarySnapshot, now: snapshot.now, frames: frames, palette: palette)
        if let librarySnapshot, librarySnapshot.page == .conversations {
            // The card keeps its closed width and runs past the window's right edge; the conversation takes its visible part.
            let card = frames.cards.first?.rect ?? frames.contentArea
            let visible = card.intersection(CGRect(x: 0, y: 0, width: frames.contentSize.width - Metrics.content.inset.value, height: frames.contentSize.height))
            libraryConversation.render(librarySnapshot.conversations, card: visible.isNull ? card : visible, cornerRadius: frames.cards.first?.cornerRadius ?? 0, theme: snapshot.theme)
        } else { libraryConversation.render(nil, card: .zero, cornerRadius: 0, theme: snapshot.theme) }
        peek.render(peekSnapshot, frames: frames, theme: snapshot.theme, palette: palette, surface: surface)
        findBar.render(snapshot.find, frames: frames.find, palette: palette)
        // The panel's column (none over the Library: the panel waits, as it is, until the Library closes).
        if let panel = frames.aiPanel { aiAnswer.render(snapshot.ai, panel: snapshot.aiPanel, agents: snapshot.aiAgents, in: panel, theme: snapshot.theme) }
        else if snapshot.ai == nil && snapshot.aiPanel == nil { aiAnswer.render(nil, panel: nil, in: .zero, theme: nil) }
        else { aiAnswer.isHidden = true }
        linkPrompt.render(snapshot.pageLinkPrompt, in: frames.contentArea)
        linkStatus.render(snapshot.overlay == nil ? snapshot.linkStatus : nil, frames: frames)
        aiPreview.render(snapshot.overlay == nil ? snapshot.aiPreview : nil, frames: frames)
        commandBar.render(barSnapshot, frames: frames, palette: palette, window: snapshot.kind)
        spaceDialog.profiles = snapshot.spaceProfiles
        spaceDialog.render(snapshot.dialog, deletion: snapshot.pendingSpaceDeletion, easelDeletion: snapshot.pendingEaselDeletion,
                           conversationDeletion: snapshot.pendingConversationDeletion, frames: frames, palette: palette)
        ProfileDialogHost.render(snapshot.profileDialog, over: spaceDialog, frames: frames, palette: palette,
                                 spaceNames: Dictionary(snapshot.dock.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first }))
        tabTools.frame = bounds
        tabTools.render(snapshot.tabTools, sidebarWidth: snapshot.sidebar.visible ? snapshot.sidebar.width : 0, palette: palette, output: snapshot.output,
                        exported: snapshot.exportOutcome, contentArea: frames.contentArea, thumbnails: thumbnails.images)
        boostPanel.render(snapshot.boostEditor, parent: window, yielding: barSnapshot != nil)
        zapOverlay.render(snapshot.boostEditor, card: snapshot.boostEditor?.target.flatMap { target in
            frames.cards.first { if case .page(let page) = $0.content { page == target.page } else { false } }?.page
        })
        captureOverlay.frame = bounds
        captureOverlay.render(snapshot.capture, frames: frames, peek:peekSnapshot)
        thumbnails.afterRender(snapshot, frames: frames, in: self)
    }

    /// The background and the sidebar. While Create a Space is open they show the draft: its theme, and in the dock
    /// a cell for the space to be, current, after the others.
    private func renderChrome(_ snapshot: WindowSnapshot, frames: WindowFrames) {
        var shown = snapshot, shownFrames = frames
        if snapshot.dialog == .newSpace, let draft, var cell = snapshot.dock.first {
            let system: Scheme = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
            shown.theme = resolveTheme(draft.theme, systemScheme: system)
            cell.id = Self.draftSpace
            cell.title = ""
            cell.icon = draft.icon
            cell.active = true
            cell.color = draft.theme.colors.first ?? cell.color
            shown.dock = snapshot.dock.map { var item = $0; item.active = false; return item } + [cell]
            shownFrames = WindowLayout.compute(shown, contentSize: frames.contentSize)
        }
        // While the column moves toward or away from the Library it stays drawn, as it stands with the Library closed.
        if sidebar.isPagingLibrary, case .library? = shown.overlay {
            var closed = shown
            closed.overlay = nil
            shownFrames = WindowLayout.compute(closed, contentSize: frames.contentSize)
        }
        background.frame = bounds
        let themeChanged = lastTheme != nil && lastTheme != shown.theme
        inactiveVeil.frame = bounds
        inactiveVeil.scheme = shown.theme.scheme
        inactiveVeil.darkWebsites = shown.websiteAppearance == .dark
        lastTheme = shown.theme
        sidebar.render(shown, frames: shownFrames, palette: Palette(shown.theme))   // hidden, it keeps its reveal strip and slide-in
        // A Space change moves the column, and the colors follow its position; another theme change crossfades.
        if !sidebar.isPaging { background.show(shown.theme, animated: themeChanged) }
    }

    /// The Library's position changed (`SidebarView.onLibraryProgress`): nil at rest.
    private func libraryMoved(_ progress: Double?) {
        let changed = (progress == nil) != (libraryProgress == nil)
        libraryProgress = progress
        // The column appears or goes as the move starts or ends.
        if changed, let last { renderChrome(last.snapshot, frames: last.frames) }
        placeForLibrary()
    }

    /// Between a Space and the Library (Arc: `WindowLayoutController` with `LayoutState.transitioning`, Q19-library): the Library
    /// panel comes in one to one with the position, the cards run from the sidebar's edge to the panel's, and the column
    /// shrinks a little, moves right and fades.
    private func placeForLibrary() {
        guard let last else { return }
        let moving: [NSView] = [content, history, easel, toolbar, loadingBar, findBar] + conversationCards.allViews + pageCards.allViews
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let progress = libraryProgress, case .library? = last.snapshot.overlay, let panel = last.frames.library?.frame else {
            for view in moving { view.layer?.transform = CATransform3DIdentity }
            library.layer?.transform = CATransform3DIdentity
            sidebar.layer?.transform = CATransform3DIdentity
            sidebar.alphaValue = 1
            return
        }
        var closed = last.snapshot
        closed.overlay = nil
        let closedFrames = WindowLayout.compute(closed, contentSize: last.frames.contentSize)
        let shift = (last.frames.contentArea.minX - closedFrames.contentArea.minX) * (1 - progress)
        for view in moving { view.layer?.transform = CATransform3DMakeTranslation(-shift, 0, 0) }
        library.layer?.transform = CATransform3DMakeTranslation(-panel.width * (1 - progress), 0, 0)
        let m = Metrics.pageSwipe
        let scale = 1 - m.librarySidebarScale.value * progress
        var column = CATransform3DMakeTranslation(sidebar.bounds.width / 2 + m.librarySidebarSlide.value * progress, sidebar.bounds.height / 2, 0)
        column = CATransform3DScale(column, scale, scale, 1)
        sidebar.layer?.transform = CATransform3DTranslate(column, -sidebar.bounds.width / 2, -sidebar.bounds.height / 2, 0)
        sidebar.alphaValue = max(0, 1 - m.librarySidebarFade.value * progress)
    }

    private static let draftSpace = SpaceID("brk-create-a-space-draft")
}

/// Owner: F3. The Peek card (Arc: `modalV2`; visual-and-copy.md "Peek"), as on Arc 1.170: the peeked page's surface in
/// a white rounded, shadowed card over the content area (`WindowFrames.peek`, `PeekLayout.card`), and beside its top
/// right corner a column of three round buttons (`PeekLayout.controls`): close (`.peek(.close)`, what Esc does), open
/// as a tab (`.peek(.openAsTab)`: the last tab of Today, same live page) and open in a split (`.peek(.openInSplit)`).
/// Under the card the page stays where it is, washed toward the window color (Metrics.peek.backdropAlpha); a click
/// on that wash closes the Peek. The card's frame is exactly the peek rect, so the control socket reads it; the
/// wash and the buttons are sibling views installed beside the card in the root.
@MainActor
public final class PeekCardView: NSView {
    private let dispatch: Dispatch
    private let card = CardView(frame: .zero)
    private let backdrop = PeekBackdropView(frame: .zero)
    private let buttons: [PeekRoundButton]
    private var last: PeekSnapshot?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        buttons = [
            PeekRoundButton(symbol: "xmark", tip: PeekCopy.close, id: .peekClose) { dispatch(.peek(.close)) },
            PeekRoundButton(symbol: "arrow.up.left.and.arrow.down.right", tip: PeekCopy.openInTab, id: .peekOpenIn) { dispatch(.peek(.openAsTab)) },
            PeekRoundButton(symbol: "rectangle.split.2x1", tip: PeekCopy.openInSplit, id: .peekSplit) { dispatch(.peek(.openInSplit)) },
        ]
        super.init(frame: .zero)
        wantsLayer = true
        identify(.peek)
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = Metrics.peek.shadowRadius.value
        layer?.shadowOffset = CGSize(width: 0, height: -Metrics.peek.shadowRadius.value / 4)
        card.layer?.cornerRadius = Metrics.peek.cornerRadius.value
        addSubview(card)
        backdrop.onClick = { dispatch(.peek(.close)) }
        backdrop.isHidden = true
        for button in buttons { button.isHidden = true }
        isHidden = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// The wash goes under the card and the buttons over it, as siblings in the root.
    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let superview else { return }
        superview.addSubview(backdrop, positioned: .below, relativeTo: self)
        for button in buttons { superview.addSubview(button, positioned: .above, relativeTo: self) }
    }

    public func render(_ peek: PeekSnapshot?, frames: WindowFrames, theme: ResolvedTheme, palette: Palette, surface: (PageID) -> NSView?) {
        guard let peek, let rect = frames.peek else {
            isHidden = true
            backdrop.isHidden = true
            for button in buttons { button.isHidden = true }
            last = nil
            card.host(nil, placeholder: nil)
            return
        }
        isHidden = false
        frame = rect
        card.frame = bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Metrics.peek.cornerRadius.value, cornerHeight: Metrics.peek.cornerRadius.value, transform: nil)
        card.host(peek.page.flatMap(surface), placeholder: peek.page == nil ? peek.tab.title : nil)
        backdrop.isHidden = false
        backdrop.frame = frames.contentArea
        backdrop.render(color: NSColor(srgbRed: theme.windowColor.red, green: theme.windowColor.green, blue: theme.windowColor.blue,
                                       alpha: Metrics.peek.backdropAlpha.value))
        let tint = ThemeAccent.peekGlyph(theme)
        for (button, place) in zip(buttons, PeekLayout.controls(beside: rect)) {
            button.isHidden = false
            button.frame = place
            button.render(tint: tint, scheme: palette.scheme)
        }
        last = peek
    }
}

/// The wash over the page under a Peek; a click on it closes the Peek.
@MainActor
final class PeekBackdropView: NSView {
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.content.cornerRadius.value
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func render(color: NSColor) { layer?.backgroundColor = color.cgColor }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

/// One of the Peek's round buttons: a white circle with a soft shadow and the theme-tinted glyph.
@MainActor
final class PeekRoundButton: NSView {
    private let glyph = NSImageView()
    private let symbol: String
    private let action: () -> Void
    private var pressed = false

    init(symbol: String, tip: String, id: ViewID, action: @escaping () -> Void) {
        self.symbol = symbol
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 3
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        toolTip = tip
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
        identify(id)
        addSubview(glyph)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// The button takes the click itself, not its glyph or label (an image view would swallow the mouse-up).
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    func render(tint: NSColor, scheme: Scheme) {
        layer?.cornerRadius = bounds.width / 2
        layer?.backgroundColor = (scheme == .dark ? NSColor(white: 0.2, alpha: 1) : NSColor.white).cgColor
        let size = Metrics.peek.controlGlyph.value
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .medium))
        glyph.contentTintColor = tint
        glyph.frame = bounds.insetBy(dx: (bounds.width - size - 2) / 2, dy: (bounds.height - size - 2) / 2)
    }

    override func mouseDown(with event: NSEvent) { pressed = true; alphaValue = 0.8 }
    override func mouseUp(with event: NSEvent) {
        alphaValue = 1
        defer { pressed = false }
        if pressed, bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

/// Shades of the space's primary color, same hue, for chrome Arc tints with the theme: the split view's focus ring
/// and the Peek buttons' glyphs (#C39C7F). A grey theme gives grey shades.
public enum ThemeAccent {
    /// Light: the primary's hue and saturation (HSL) at the lightness whose relative luminance is Arc's 0.097. That is
    /// the ring in both Arc captures, which is also Arc's folder outline there: #725137 under the #F2EAE4 theme
    /// (P23-a) and #006362 under the cyan one (P23-c, the round-2 Arc space). Dark keeps a light shade.
    /// The ring's colour for a space's primary colour (a Little window names its space in this colour, P21-b).
    public static func ring(of primary: RGBA) -> NSColor { luminanceMatched(primary, luminance: ThemeAccentDraw.ringLuminance.value) }

    public static func splitFocusRing(_ theme: ResolvedTheme) -> NSColor {
        guard theme.scheme == .light else { return shade(theme, saturationScale: 9, saturationCap: 0.53, brightness: 0.8) }
        return luminanceMatched(theme.gradient.first ?? RGBA(0.5, 0.5, 0.5, 1), luminance: ThemeAccentDraw.ringLuminance.value)
    }

    /// `color`'s hue and HSL saturation at the HSL lightness (at most 0.5) that gives `luminance`.
    static func luminanceMatched(_ color: RGBA, luminance target: Double) -> NSColor {
        let hi = max(color.red, color.green, color.blue), lo = min(color.red, color.green, color.blue), l = (hi + lo) / 2
        var hue = 0.0, saturation = 0.0
        if hi > lo {
            let d = hi - lo
            saturation = l > 0.5 ? d / (2 - hi - lo) : d / (hi + lo)
            if hi == color.red { hue = (color.green - color.blue) / d + (color.green < color.blue ? 6 : 0) }
            else if hi == color.green { hue = (color.blue - color.red) / d + 2 }
            else { hue = (color.red - color.green) / d + 4 }
            hue /= 6
        }
        func rgb(_ l: Double) -> (Double, Double, Double) {
            let q = l < 0.5 ? l * (1 + saturation) : l + saturation - l * saturation, p = 2 * l - q
            func channel(_ t: Double) -> Double {
                let t = t < 0 ? t + 1 : t > 1 ? t - 1 : t
                if t < 1.0 / 6 { return p + (q - p) * 6 * t }
                if t < 0.5 { return q }
                if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
                return p
            }
            return (channel(hue + 1.0 / 3), channel(hue), channel(hue - 1.0 / 3))
        }
        func luminance(_ c: (Double, Double, Double)) -> Double {
            func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(c.0) + 0.7152 * linear(c.1) + 0.0722 * linear(c.2)
        }
        var low = 0.0, high = 0.5
        for _ in 0..<30 {
            let mid = (low + high) / 2
            if luminance(rgb(mid)) < target { low = mid } else { high = mid }
        }
        let c = rgb((low + high) / 2)
        return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
    }

    static func peekGlyph(_ theme: ResolvedTheme) -> NSColor {
        shade(theme, saturationScale: 6, saturationCap: 0.35, brightness: theme.scheme == .dark ? 0.85 : 0.76)
    }

    private static func shade(_ theme: ResolvedTheme, saturationScale: Double, saturationCap: Double, brightness: Double) -> NSColor {
        let primary = theme.gradient.first ?? RGBA(0.5, 0.5, 0.5, 1)
        let color = NSColor(srgbRed: primary.red, green: primary.green, blue: primary.blue, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, value: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(saturationCap, saturation * saturationScale), brightness: brightness, alpha: 1)
    }
}

let ThemeAccentDraw = ThemeAccentMetrics()

struct ThemeAccentMetrics: MetricGroup {
    let ringLuminance = Metric(0.097, .anatomy("verify/visual-pairs/run-20261103/P23: the split focus ring #725137 (P23-a) and #006362 (P23-c) both have relative luminance 0.096 to 0.098"))
}

/// Arc's Peek and Little Arc copy shared by the card and the Little Arc panel (visual-and-copy.md "Little Arc").
public enum PeekCopy {
    /// `bin:0x103a05b60`, Arc's Little Arc hint; the Peek strip reads the same, since both close with ⌘W and move with "Open in".
    public static let hint = "Click “Open in” to move this page in a full window, or ⌘W to close"
    public static let openInTab = "Open as Tab"
    public static let openInSplit = "Open in Split View"
    public static let close = "Close"
}

/// Share's PNG of an Easel's board, for BrkApp (which reaches the Library's drawing only through this module).
@MainActor
public enum EaselExport {
    public static func png(_ card: EaselCard) -> Data? { EaselDrawing.png(card) }
}

/// Arc's window background changes with two states while the sidebar's text and the cards do not: the background,
/// and with it the sidebar's translucent rows, tiles and the margins round the cards, turns lighter while the app is
/// not frontmost and darker while View > Appearance sets websites to Dark. Measured on Arc 1.170 with the #F2EAE4
/// theme (verify/visual-pairs/run-20261103): P01-d against P01-a, #F0EAE6 reads #F7F2EE and the favorites' tile
/// #E6E1DF reads #EDE8E5 (white at 40% lands within 2 of each channel); P19-b against P19-c, #F0EBE7 reads #DCD6D3
/// and the tile #E5E0DE reads #D2CDCA (black at 8.6%). Dark themes keep their look (no Arc capture of one).
@MainActor
final class InactiveVeilView: NSView {
    var scheme: Scheme = .light { didSet { if scheme != oldValue { update() } } }
    var darkWebsites = false { didSet { if darkWebsites != oldValue { update() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func update() {
        let veil: NSColor? = scheme == .dark ? nil
            : darkWebsites ? NSColor(white: 0, alpha: 0.086)
            : NSApplication.shared.isActive ? nil : NSColor(white: 1, alpha: 0.4)
        isHidden = veil == nil
        layer?.backgroundColor = veil?.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
