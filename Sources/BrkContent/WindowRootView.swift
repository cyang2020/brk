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
    public let toolbar: AddressToolbarView
    public let sidebar: SidebarView
    public let content: ContentAreaView
    public let library: LibraryView
    public let history: HistoryPageView
    public let peek: PeekCardView
    public let findBar: FindBarView
    public let commandBar: CommandBarView
    public let spaceDialog: SpaceDialogHost
    private let zapOverlay: BoostZapOverlayView
    private let boostPanel: BoostPanel
    private let aiAnswer: AIAnswerDocumentView
    private let captureOverlay: CaptureOverlayView
    private let tabTools: TabToolsOverlayView
    private var lastTheme: ResolvedTheme?
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
        aiAnswer = AIAnswerDocumentView(dispatch: dispatch)
        captureOverlay = CaptureOverlayView(dispatch: dispatch)
        tabTools = TabToolsOverlayView(dispatch: dispatch)
        self.dispatch = dispatch
        toolbar = AddressToolbarView(dispatch: dispatch)
        sidebar = SidebarView(dispatch: dispatch)
        content = ContentAreaView(dispatch: dispatch)
        library = LibraryView(dispatch: dispatch)
        history = HistoryPageView(dispatch: dispatch)
        peek = PeekCardView(dispatch: dispatch)
        findBar = FindBarView(dispatch: dispatch)
        commandBar = CommandBarView(dispatch: dispatch)
        spaceDialog = SpaceDialogHost(dispatch: dispatch)
        super.init(frame: .zero)
        wantsLayer = true
        for view in [background, sidebar, content, history, toolbar, loadingBar, library, peek, findBar, aiAnswer, commandBar, spaceDialog, tabTools, zapOverlay, captureOverlay] as [NSView] { addSubview(view) }
        background.identify(.themeBackground)
        sidebar.edgeViewsAbove = loadingBar   // the resize handle over the cards and the toolbar
        sidebar.contentDrop = { [weak content] item, point in content?.dropCommand(item, at: point) }
        sidebar.beginContentDrop = { [weak content] item in content?.beginDrop(item) }
        sidebar.endContentDrop = { [weak content] in content?.endDrop() }
        // Both span the window from its top left, so the Library's coordinates are the dialog host's.
        spaceDialog.cardHeader = { [weak library] space in library?.spaceCardHeader(space) }
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
        case .profileDialog: ProfileDialogHost.focus(over: spaceDialog)
        case .sidebar: sidebar.focusList()
        case .page, .none: false
        }
    }

    public func handleScrollWheel(_ event: NSEvent) -> Bool { sidebar.handleScrollWheel(event) }

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
            else { addSubview(sidebar, positioned: .above, relativeTo: background) }
        }
        renderChrome(snapshot, frames: frames)
        let palette = Palette(snapshot.theme)
        content.isDropEnabled = snapshot.find == nil && snapshot.overlay == nil && snapshot.dialog == nil && snapshot.profileDialog == nil && snapshot.pendingSpaceDeletion == nil
        content.render(snapshot.content, frames: frames, theme: snapshot.theme, palette: palette, surface: surface)
        // Arc's Create a Space flow shows no page: the content area is a blank card over the draft's theme.
        content.isHidden = snapshot.dialog == .newSpace
        let historyCard = frames.cards.first { if case .history = $0.content { true } else { false } }
        let historyPage: PageID? = if case .history(let page)? = historyCard?.content { page } else { nil }
        history.render(snapshot.history, page: historyPage, in: historyCard?.rect, scheme: palette.scheme, now: snapshot.now)
        history.layer?.cornerRadius = historyCard?.cornerRadius ?? 0
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
        peek.render(peekSnapshot, frames: frames, theme: snapshot.theme, palette: palette, surface: surface)
        findBar.render(snapshot.find, frames: frames.find, palette: palette)
        aiAnswer.render(snapshot.ai, in: frames.contentArea)
        commandBar.render(barSnapshot, frames: frames, palette: palette, window: snapshot.kind)
        spaceDialog.profiles = snapshot.spaceProfiles
        spaceDialog.render(snapshot.dialog, deletion: snapshot.pendingSpaceDeletion, frames: frames, palette: palette)
        ProfileDialogHost.render(snapshot.profileDialog, over: spaceDialog, frames: frames, palette: palette,
                                 spaceNames: Dictionary(snapshot.dock.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first }))
        tabTools.frame = bounds
        tabTools.render(snapshot.tabTools, sidebarWidth: snapshot.sidebar.visible ? snapshot.sidebar.width : 0, palette: palette, output: snapshot.output,
                        exported: snapshot.exportOutcome, contentArea: frames.contentArea, thumbnails: thumbnails.images)
        boostPanel.render(snapshot.boostEditor, parent: window)
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
        background.frame = bounds
        background.show(shown.theme, animated: lastTheme != nil && lastTheme != shown.theme)
        lastTheme = shown.theme
        sidebar.render(shown, frames: shownFrames, palette: Palette(shown.theme))   // hidden, it keeps its reveal strip and slide-in
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
enum ThemeAccent {
    /// Light: the primary's hue and saturation (HSL) at the lightness whose relative luminance is Arc's 0.097. That is
    /// the ring in both Arc captures, which is also Arc's folder outline there: #725137 under the #F2EAE4 theme
    /// (P23-a) and #006362 under the cyan one (P23-c, the round-2 Arc space). Dark keeps a light shade.
    static func splitFocusRing(_ theme: ResolvedTheme) -> NSColor {
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
