import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkLibrary
import BrkOverlays
import BrkSidebar
import BrkTheme
import BrkUIKit

/// Owner: W2. A window's content view. Bottom to top: themed background, anchored sidebar, content cards (page
/// surfaces inside), the Library host with the archive page inside it (both inside the content area), the Peek
/// card, floating sidebar (only while peeking a hidden sidebar), command bar, space dialog (SwiftUI in an
/// NSHostingView). TODO(F2): the profile dialog host; TODO(F3): Arc's Peek card chrome.
/// Native views above Chromium's moved views draw and take focus normally (spike unknown 2, embed mode).
@MainActor
public final class WindowRootView: NSView {
    public let background = ThemeBackgroundView(frame: .zero)
    public let sidebar: SidebarView
    public let content: ContentAreaView
    public let library: LibraryView
    public let archive: ArchivePageView
    public let peek: PeekCardView
    public let commandBar: CommandBarView
    public let spaceDialog: SpaceDialogHost
    private var lastTheme: ResolvedTheme?
    private var sidebarFloats = false

    public init(dispatch: @escaping Dispatch) {
        sidebar = SidebarView(dispatch: dispatch)
        content = ContentAreaView(dispatch: dispatch)
        library = LibraryView(dispatch: dispatch)
        archive = ArchivePageView(dispatch: dispatch)
        peek = PeekCardView(dispatch: dispatch)
        commandBar = CommandBarView(dispatch: dispatch)
        spaceDialog = SpaceDialogHost(dispatch: dispatch)
        super.init(frame: .zero)
        wantsLayer = true
        for view in [background, sidebar, content, library, archive, peek, commandBar, spaceDialog] as [NSView] { addSubview(view) }
        background.identify(.themeBackground)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// Gives keyboard focus to the native view a `FocusTarget` names. Returns false for `.page` and `.none` (the
    /// engine's business, handled by the window controller) and when the view is not on screen yet. This is the
    /// only way BrkApp reaches a view's focus: the fields themselves are internal to their targets.
    public func focus(_ target: FocusTarget) -> Bool {
        switch target {
        case .commandBarInput: commandBar.focusInput()
        case .renameField(let item): sidebar.focusRenameField(item)
        case .spaceDialog: spaceDialog.focusForm()
        case .profileDialog: false   // TODO(F2): the profile dialog host
        case .sidebar: sidebar.focusList()
        case .page, .none: false
        }
    }

    /// Applies one snapshot. `surface` looks up the engine's view for a page (nil until the page exists).
    ///
    /// Order: background (crossfade when the theme changed and this is not the first render), sidebar (anchored or
    /// floating: same view, re-parented above `content` while floating), content cards (each card hosts the
    /// surface for its pane; a surface that moved to another card is simply re-added there), archive, command bar.
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
        content.render(snapshot.content, frames: frames, palette: palette, surface: surface)
        var librarySnapshot: LibrarySnapshot?, barSnapshot: CommandBarSnapshot?, peekSnapshot: PeekSnapshot?
        switch snapshot.overlay {
        case .library(let l)?: librarySnapshot = l
        case .peek(let p)?: peekSnapshot = p
        case .commandBar(let b)?: barSnapshot = b
        case nil: break
        }
        library.render(librarySnapshot, frames: frames, palette: palette)
        archive.render(librarySnapshot?.archive, frames: frames, palette: palette)
        peek.render(peekSnapshot, frames: frames, palette: palette, surface: surface)
        commandBar.render(barSnapshot, frames: frames, palette: palette)
        spaceDialog.render(snapshot.dialog, frames: frames, palette: palette)
        lastTheme = snapshot.theme
    }
}

/// Owner: F3. The Peek card (Arc: `modalV2`; visual-and-copy.md "Peek"): the peeked page's surface in a rounded,
/// shadowed card over the content area (`WindowFrames.peek`, the content area inset Metrics.peek.inset), with a
/// strip under it carrying the hint ("Click “Open in” to move this page in a full window, or ⌘W to close"), "Open
/// in tab" (promotes the page to the current space's Today, `.window(.openIn(.current))`) and "Close"
/// (`.peek(.close)`, what Esc does). The view's frame is exactly the peek rect, so the control socket reads it; the
/// radius, shadow and strip height are the labeled guesses in Metrics.peek until Arc's are measured. No backdrop
/// dims the content (that would need a sibling view in W2's root).
@MainActor
public final class PeekCardView: NSView {
    private let dispatch: Dispatch
    private let card = CardView(frame: .zero)
    private let strip = NSView(frame: .zero)
    private let hint = NSTextField(labelWithString: PeekCopy.hint)
    private let close = NSButton(title: PeekCopy.close, target: nil, action: nil)
    private let openIn = NSButton(title: PeekCopy.openInTab, target: nil, action: nil)
    private var last: PeekSnapshot?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        identify(.peek)
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = Metrics.peek.shadowRadius.value
        layer?.shadowOffset = CGSize(width: 0, height: -Metrics.peek.shadowRadius.value / 3)
        card.layer?.cornerRadius = Metrics.peek.cornerRadius.value
        addSubview(card)
        strip.wantsLayer = true
        addSubview(strip)
        hint.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        strip.addSubview(hint)
        for (button, id, action) in [(close, ViewID.peekClose, #selector(closeClicked)), (openIn, ViewID.peekOpenIn, #selector(openInClicked))] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            button.target = self
            button.action = action
            button.identify(id)
            strip.addSubview(button)
        }
        close.keyEquivalent = "\u{1b}"   // the card's Close is Esc's "Exit", also reachable by mouse
        isHidden = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    public func render(_ peek: PeekSnapshot?, frames: WindowFrames, palette: Palette, surface: (PageID) -> NSView?) {
        guard let peek, let rect = frames.peek else {
            isHidden = true
            last = nil
            card.host(nil, placeholder: nil)
            return
        }
        isHidden = false
        frame = rect
        let hintHeight = Metrics.peek.hintHeight.value
        card.frame = CGRect(x: 0, y: 0, width: rect.width, height: max(0, rect.height - hintHeight))
        layer?.shadowPath = CGPath(roundedRect: card.frame, cornerWidth: Metrics.peek.cornerRadius.value, cornerHeight: Metrics.peek.cornerRadius.value, transform: nil)
        card.host(peek.page.flatMap(surface), placeholder: peek.page == nil ? peek.tab.title : nil)
        strip.frame = CGRect(x: 0, y: card.frame.maxY, width: rect.width, height: hintHeight)
        let buttonHeight = min(22, hintHeight - 4), y = (hintHeight - buttonHeight) / 2
        close.frame = CGRect(x: rect.width - 72, y: y, width: 64, height: buttonHeight)
        openIn.frame = CGRect(x: close.frame.minX - 8 - 104, y: y, width: 104, height: buttonHeight)
        hint.frame = CGRect(x: 8, y: 0, width: max(0, openIn.frame.minX - 16), height: hintHeight)
        last = peek
    }

    @objc private func closeClicked() { dispatch(.peek(.close)) }
    @objc private func openInClicked() { dispatch(.window(.openIn(.current))) }
}

/// Arc's Peek and Little Arc copy shared by the card and the Little Arc panel (visual-and-copy.md "Little Arc").
public enum PeekCopy {
    /// `bin:0x103a05b60`, Arc's Little Arc hint; the Peek strip reads the same, since both close with ⌘W and move with "Open in".
    public static let hint = "Click “Open in” to move this page in a full window, or ⌘W to close"
    public static let openInTab = "Open in tab"
    public static let close = "Close"
}
