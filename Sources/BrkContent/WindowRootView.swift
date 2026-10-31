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
/// command bar, space dialog (SwiftUI in an NSHostingView). TODO(F2): the profile dialog host; TODO(F3): Arc's Peek card chrome.
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
    private let boostEditor: BoostEditorView
    private let aiAnswer: AIAnswerDocumentView
    private let captureOverlay: CaptureOverlayView
    private let tabTools: TabToolsOverlayView
    private var lastTheme: ResolvedTheme?
    private var sidebarFloats = false

    public init(dispatch: @escaping Dispatch) {
        zapOverlay = BoostZapOverlayView(dispatch: dispatch)
        boostEditor = BoostEditorView(dispatch: dispatch)
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
        for view in [background, sidebar, content, toolbar, library, peek, findBar, aiAnswer, commandBar, spaceDialog, tabTools, boostEditor, zapOverlay, captureOverlay] as [NSView] { addSubview(view) }
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
        content.render(snapshot.content, frames: frames, palette: palette, surface: surface)
        toolbar.render(snapshot.urlPill, rect: frames.toolbar, palette: palette)
        var librarySnapshot: LibrarySnapshot?, barSnapshot: CommandBarSnapshot?, peekSnapshot: PeekSnapshot?
        switch snapshot.overlay {
        case .library(let l)?: librarySnapshot = l
        case .peek(let p)?: peekSnapshot = p
        case .commandBar(let b)?: barSnapshot = b
        case nil: break
        }
        library.render(librarySnapshot, now: snapshot.now, frames: frames, palette: palette)
        peek.render(peekSnapshot, frames: frames, palette: palette, surface: surface)
        peek.setFindVisible(snapshot.find != nil)
        findBar.render(snapshot.find, frames: frames.find, palette: palette)
        aiAnswer.render(snapshot.ai, in: frames.contentArea)
        commandBar.render(barSnapshot, frames: frames, palette: palette)
        spaceDialog.profiles = snapshot.spaceProfiles
        spaceDialog.render(snapshot.dialog, frames: frames, palette: palette)
        ProfileDialogHost.render(snapshot.profileDialog, over: spaceDialog, frames: frames, palette: palette)
        tabTools.frame = bounds
        tabTools.render(snapshot.tabTools, sidebarWidth: snapshot.sidebar.visible ? snapshot.sidebar.width : 0, palette: palette, output: snapshot.output, exported: snapshot.exportOutcome)
        boostEditor.render(snapshot.boostEditor, in: frames.contentArea, scheme: palette.scheme)
        zapOverlay.render(snapshot.boostEditor, in: frames.contentArea)
        deleteConfirmation.render(snapshot.pendingSpaceDeletion, in: window, dispatch: dispatch)
        captureOverlay.render(snapshot.capture, frames: frames, peek:peekSnapshot)
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
    private let destinations = NSPopUpButton(frame: .zero, pullsDown: true)
    private var destinationCommands: [Command] = []

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
        destinations.target = self; destinations.action = #selector(destinationChosen)
        destinations.controlSize = .small
        strip.addSubview(destinations)
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
        let entries = OpenInMenu.model(spaces: peek.spaces, folders: peek.folders).entries
        destinationCommands = entries.compactMap { if case .action(_, let command, _) = $0 { command } else { nil } }
        let titles = entries.compactMap { if case .action(let title, _, _) = $0 { title } else { nil } }
        destinations.removeAllItems(); destinations.addItems(withTitles: ["Move to…"] + titles)
        destinations.frame = CGRect(x: max(8, openIn.frame.minX - 126), y: y, width: 118, height: buttonHeight)
        destinations.toolTip = "Reopens the committed address in the destination profile; unsaved form state stays in the temporary page until moved."
        hint.frame.size.width = max(0, destinations.frame.minX - 16)
        last = peek
    }

    func setFindVisible(_ visible: Bool) { close.keyEquivalent = visible ? "" : "\u{1b}" }

    @objc private func destinationChosen() {
        let index = destinations.indexOfSelectedItem - 1
        if destinationCommands.indices.contains(index) { dispatch(destinationCommands[index]) }
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
