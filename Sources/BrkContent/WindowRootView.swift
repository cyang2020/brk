import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkOverlays
import BrkSidebar
import BrkTheme
import BrkUIKit

/// A window's content view. Bottom to top: themed background, anchored sidebar, content cards (page surfaces inside),
/// archive page (inside the content area), floating sidebar (only while peeking a hidden sidebar), command bar, space
/// dialog (SwiftUI in an NSHostingView).
/// Native views above Chromium's moved views draw and take focus normally (spike unknown 2, embed mode).
@MainActor
public final class WindowRootView: NSView {
    public let background = ThemeBackgroundView(frame: .zero)
    public let sidebar: SidebarView
    public let content: ContentAreaView
    public let archive: ArchivePageView
    public let commandBar: CommandBarView
    public let spaceDialog: SpaceDialogHost
    private var lastTheme: ResolvedTheme?

    public init(dispatch: @escaping Dispatch) {
        sidebar = SidebarView(dispatch: dispatch)
        content = ContentAreaView(dispatch: dispatch)
        archive = ArchivePageView(dispatch: dispatch)
        commandBar = CommandBarView(dispatch: dispatch)
        spaceDialog = SpaceDialogHost(dispatch: dispatch)
        super.init(frame: .zero)
        wantsLayer = true
        for view in [background, sidebar, content, archive, commandBar, spaceDialog] as [NSView] { addSubview(view) }
        background.identify(.themeBackground)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// Applies one snapshot. `surface` looks up the engine's view for a page (nil until the page exists).
    ///
    /// Order: background (crossfade when the theme changed and this is not the first render), sidebar (anchored or
    /// floating: same view, re-parented above `content` while floating), content cards (each card hosts the
    /// surface for its pane; a surface that moved to another card is simply re-added there), archive, command bar.
    /// Gives keyboard focus to the native view a `FocusTarget` names. Returns false for `.page` and `.none` (the
    /// engine's business, handled by the window controller) and when the view is not on screen yet. This is the
    /// only way BrkApp reaches a view's focus: the fields themselves are internal to their targets.
    public func focus(_ target: FocusTarget) -> Bool {
        switch target {
        case .commandBarInput: commandBar.focusInput()
        case .renameField(let item): sidebar.focusRenameField(item)
        case .spaceDialog: spaceDialog.focusForm()
        case .sidebar: sidebar.focusList()
        case .page, .none: false
        }
    }

    public func render(_ snapshot: WindowSnapshot, frames: WindowFrames, surface: (PageID) -> NSView?) {
        // TODO(W2): background.frame = bounds; background.show(snapshot.theme, animated: lastTheme != nil);
        // let palette = Palette(snapshot.theme)
        // sidebar.render(snapshot, frames: frames, palette: palette); sidebar.isHidden = frames.sidebar == nil;
        //   if frames.sidebarFloats, keep sidebar above content (sortSubviews or remove/add once on change).
        // content.render(snapshot.content, frames: frames, palette: palette, surface: surface)
        // archive.render(the .archive overlay or nil, frames: frames, palette: palette)
        // commandBar.render(the .commandBar overlay or nil, frames: frames, palette: palette)
        // spaceDialog.render(snapshot.dialog, frames: frames, palette: palette)
        lastTheme = snapshot.theme
        fatalError("not implemented")
    }
}
