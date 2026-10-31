import AppKit
import BrkBase
import BrkContent
import BrkDomain
import BrkEngine
import BrkLayout
import BrkUIKit

/// Owner: F3. The Little Arc window (Arc: `LittleBrowserWindow`, an NSPanel; anatomy-m 1.10, visual-and-copy.md
/// "Little Arc"): a small window for one page with no sidebar. The root view (the same `WindowRootView` as a
/// standard window, rendering the `.little` snapshot: no sidebar, one card, the command bar) fills
/// Metrics.littleArc.defaultSize; under it a hint strip (Metrics.peek.hintHeight) carries Arc's hint ("Click “Open
/// in” to move this page in a full window, or ⌘W to close") and the "Open in <space>" pull-down, whose menu is
/// `OpenInMenu.model` (every space, then "Open in current Space"); each choice dispatches `.window(.openIn(...))`,
/// which moves the tab to that space's Today and closes this panel. The title is "Little <app> — <page>".
///
/// The first Little Arc is centered on the main screen at the default size (no saved frame); the next cascades by
/// Metrics.littleArc.cascade, which the reducer decides from the last one's reported frame. A panel, as Arc's, but
/// one that stays when the app is not active (`hidesOnDeactivate` off) and takes key status like a window, because
/// the page and the command bar need keyboard focus.
@MainActor
public final class LittleWindowController: WindowController {
    let strip = NSView(frame: .zero)
    let hint = NSTextField(labelWithString: LittleArcCopy.hint)
    let openIn = NSPopUpButton(frame: .zero, pullsDown: true)
    private let popupTarget = PopupTarget()
    private var menuKey: [DockItem] = []
    private var folderKey: [FolderDestinationCandidate] = []
    private var titledFor: String?

    init(id: WindowID, engine: any WebEngine, send: @escaping @MainActor (Input) -> Void,
         routeKey: @escaping @MainActor (KeyInput) -> Bool = { _ in false }) {
        let size = Metrics.littleArc.defaultSize.value
        let stripHeight = Metrics.peek.hintHeight.value
        let panel = BrowserPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height + stripHeight)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = false
        panel.title = LittleArcCopy.title(page: nil)
        super.init(id: id, kind: .little, engine: engine, send: send, routeKey: routeKey, window: panel)
        // The panel's content is the root (the page area, at the default size) over the hint strip.
        let container = NSView(frame: CGRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size))
        container.autoresizesSubviews = true
        root.frame = CGRect(x: 0, y: stripHeight, width: container.bounds.width, height: container.bounds.height - stripHeight)
        root.autoresizingMask = [.width, .height]
        strip.frame = CGRect(x: 0, y: 0, width: container.bounds.width, height: stripHeight)
        strip.autoresizingMask = [.width, .maxYMargin]
        strip.wantsLayer = true
        container.addSubview(root)
        container.addSubview(strip)
        panel.contentView = container

        hint.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.identify(.littleHint)
        hint.frame = CGRect(x: 12, y: 0, width: max(0, strip.bounds.width - 12 - 190), height: stripHeight)
        hint.autoresizingMask = [.width]
        strip.addSubview(hint)

        openIn.controlSize = .small
        openIn.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        openIn.frame = CGRect(x: strip.bounds.width - 178, y: (stripHeight - 22) / 2, width: 170, height: 22)
        openIn.autoresizingMask = [.minXMargin]
        strip.addSubview(openIn)
    }

    /// The first Little Arc has no frame yet: Arc's default size, centered on the main screen. A frame the reducer
    /// set (the cascade from the last Little Arc) or AppKit reported is fitted like any saved frame.
    override func initialFrame(for snapshot: WindowSnapshot, screens: [CGRect], main: CGRect) -> CGRect {
        if let saved = snapshot.bounds { return WindowPlacement.fit(saved, screens: screens, main: main) }
        let size = window.frameRect(forContentRect: CGRect(origin: .zero, size: CGSize(
            width: Metrics.littleArc.defaultSize.value.width, height: Metrics.littleArc.defaultSize.value.height + Metrics.peek.hintHeight.value))).size
        let width = min(size.width, main.width), height = min(size.height, main.height)
        // Rounded origin, exact size: `.integral` would widen a half-point origin into an extra point.
        return CGRect(x: (main.midX - width / 2).rounded(), y: (main.midY - height / 2).rounded(), width: width, height: height)
    }

    override func render(_ snapshot: WindowSnapshot) {
        super.render(snapshot)
        let page = snapshot.content.panes.first { $0.focused }.flatMap { pane in snapshot.scratch?.rows.compactMap { row -> TabRow? in
            if case .tab(let t) = row, t.id == pane.tab { return t } else { return nil }
        }.first }
        let title = LittleArcCopy.title(page: page?.title)
        if titledFor != title {
            titledFor = title
            window.title = title
        }
        if folderKey != snapshot.openInFolders || menuKey != snapshot.dock || openIn.menu?.items.isEmpty ?? true {
            menuKey = snapshot.dock
            folderKey = snapshot.openInFolders
            let menu = popupTarget.menu(for: OpenInMenu.model(spaces: snapshot.dock, folders: snapshot.openInFolders)) { [send, id] command in send(.user(id, command)) }
            // A pull-down shows its first item as the button's title.
            menu.insertItem(NSMenuItem(title: OpenInMenu.buttonTitle(space: snapshot.space.title), action: nil, keyEquivalent: ""), at: 0)
            openIn.menu = menu
        } else if openIn.menu?.items.first?.title != OpenInMenu.buttonTitle(space: snapshot.space.title) {
            openIn.menu?.items.first?.title = OpenInMenu.buttonTitle(space: snapshot.space.title)
        }
        openIn.isEnabled = snapshot.enabledActions.contains(.openTabIn)
    }
}

/// Arc's Little Arc copy (visual-and-copy.md "Little Arc"), with the app's name where Arc's menu rows substitute it.
public enum LittleArcCopy {
    /// "Little Arc — %@" (`bin:0x103956e80`); a page without a title yet reads "New Tab".
    public static func title(page: String?) -> String {
        let page = page.flatMap { $0.isEmpty ? nil : $0 } ?? Copy.newTab
        return "Little \(Product.name) — \(page)"
    }

    /// `bin:0x103a05b60`, shared with the Peek strip (BrkContent `PeekCopy`).
    public static let hint = PeekCopy.hint
}

/// The Little Arc host window: an NSPanel that routes keys and modifiers like `BrowserWindow`, can be key (its page
/// and command bar take keyboard focus) and keeps AppKit's own traffic lights (no sidebar to place them over).
@MainActor
public final class BrowserPanel: NSPanel, HostWindow {
    public var onActivity: (() -> Void)?
    public var onFlagsChanged: ((NSEvent.ModifierFlags) -> Void)?
    public var onKeyEquivalent: ((NSEvent) -> Bool)?

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public override func sendEvent(_ event: NSEvent) {
        if hostEvent(event) { return }
        super.sendEvent(event)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        hostKeyEquivalent(event, handledByViews: super.performKeyEquivalent(with: event))
    }

    /// The panel keeps its title bar and AppKit's lights where they are.
    public func placeTrafficLights(origin: CGPoint?) {}
}
