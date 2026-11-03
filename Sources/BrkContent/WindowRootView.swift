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
/// content cards (page surfaces inside), the Library (its panel in place of the sidebar, its page over the content
/// area; the archive is one of its pages), the Peek card, floating sidebar (only while peeking a hidden sidebar),
/// command bar, space dialog (SwiftUI in an NSHostingView). TODO(F2): the profile dialog host.
/// Native views above Chromium's moved views draw and take focus normally (spike unknown 2, embed mode).
@MainActor
public final class WindowRootView: NSView {
    private let deleteConfirmation = SpaceDeleteConfirmation()
    private let dispatch: Dispatch
    public let background = ThemeBackgroundView(frame: .zero)
    public let toolbar: AddressToolbarView
    public let sidebar: SidebarView
    public let content: ContentAreaView
    public let library: LibraryView
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
        peek = PeekCardView(dispatch: dispatch)
        findBar = FindBarView(dispatch: dispatch)
        commandBar = CommandBarView(dispatch: dispatch)
        spaceDialog = SpaceDialogHost(dispatch: dispatch)
        super.init(frame: .zero)
        wantsLayer = true
        for view in [background, sidebar, content, toolbar, library, peek, findBar, aiAnswer, commandBar, spaceDialog, tabTools, zapOverlay, captureOverlay] as [NSView] { addSubview(view) }
        background.identify(.themeBackground)
        sidebar.contentDrop = { [weak content] item, point in content?.dropCommand(item, at: point) }
        sidebar.beginContentDrop = { [weak content] item in content?.beginDrop(item) }
        sidebar.endContentDrop = { [weak content] in content?.endDrop() }
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
        background.frame = bounds
        background.show(snapshot.theme, animated: lastTheme != nil && lastTheme != snapshot.theme)
        let palette = Palette(snapshot.theme)
        if frames.sidebarFloats != sidebarFloats {
            sidebarFloats = frames.sidebarFloats
            sidebar.removeFromSuperview()
            if sidebarFloats { addSubview(sidebar, positioned: .above, relativeTo: peek) }
            else { addSubview(sidebar, positioned: .above, relativeTo: background) }
        }
        sidebar.render(snapshot, frames: frames, palette: palette)   // hidden, it keeps its reveal strip and slide-in
        content.isDropEnabled = snapshot.find == nil && snapshot.overlay == nil && snapshot.dialog == nil && snapshot.profileDialog == nil && snapshot.pendingSpaceDeletion == nil
        content.render(snapshot.content, frames: frames, theme: snapshot.theme, palette: palette, surface: surface)
        toolbar.render(snapshot.urlPill, rect: frames.toolbar, palette: palette)
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
        commandBar.render(barSnapshot, frames: frames, palette: palette)
        spaceDialog.profiles = snapshot.spaceProfiles
        spaceDialog.render(snapshot.dialog, frames: frames, palette: palette)
        ProfileDialogHost.render(snapshot.profileDialog, over: spaceDialog, frames: frames, palette: palette)
        tabTools.frame = bounds
        tabTools.render(snapshot.tabTools, sidebarWidth: snapshot.sidebar.visible ? snapshot.sidebar.width : 0, palette: palette, output: snapshot.output, exported: snapshot.exportOutcome)
        boostPanel.render(snapshot.boostEditor, parent: window)
        zapOverlay.render(snapshot.boostEditor, card: snapshot.boostEditor?.target.flatMap { target in
            frames.cards.first { if case .page(let page) = $0.content { page == target.page } else { false } }?.page
        })
        deleteConfirmation.render(snapshot.pendingSpaceDeletion, in: window, dispatch: dispatch)
        captureOverlay.frame = bounds
        captureOverlay.render(snapshot.capture, frames: frames, peek:peekSnapshot)
        lastTheme = snapshot.theme
    }
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
/// (#725137 under the #F2EAE4 capture theme) and the Peek buttons' glyphs (#C39C7F). A grey theme gives grey shades.
enum ThemeAccent {
    static func splitFocusRing(_ theme: ResolvedTheme) -> NSColor {
        shade(theme, saturationScale: 9, saturationCap: 0.53, brightness: theme.scheme == .dark ? 0.8 : 0.45)
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

/// Arc's Peek and Little Arc copy shared by the card and the Little Arc panel (visual-and-copy.md "Little Arc").
public enum PeekCopy {
    /// `bin:0x103a05b60`, Arc's Little Arc hint; the Peek strip reads the same, since both close with ⌘W and move with "Open in".
    public static let hint = "Click “Open in” to move this page in a full window, or ⌘W to close"
    public static let openInTab = "Open as Tab"
    public static let openInSplit = "Open in Split View"
    public static let close = "Close"
}
