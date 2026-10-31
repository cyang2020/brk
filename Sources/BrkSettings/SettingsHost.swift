import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: F1. The settings window's content, laid out the way Arc's is: Arc builds its settings with the
/// sindresorhus/Settings package (`Settings.SettingsWindowController`, `ToolbarItemStyleViewController`,
/// `Settings.Container`, `Settings.Section` are in its binary), so the panes are toolbar items in Arc's enum order
/// (General, Max, Profiles, Shortcuts, Links, Advanced; anatomy-m 4.1), the window is titled with the pane, and the
/// window fits each pane's height. The panes are SwiftUI in an `NSHostingController`, like Arc's
/// `PaneHostingController`.
///
/// BrkApp hosts this view as the content of its one settings NSWindow (SettingsWindowController) and feeds it
/// `AppSnapshot.settings` after every change. The host installs its toolbar on that window. Every control dispatches
/// a `.settings(...)` command and shows only the snapshot, so the window and the control socket's `settings` op
/// cannot disagree. Cmd+W and Esc dispatch `.settings(.closeWindow)`.
///
/// Public surface (what BrkApp may call): `init(dispatch:)`, `render(_:)`.
///
/// The feature editors are `ProfilesPane` (F2), `LinksRoutesEditor` (F3), and `ShortcutsPane` (F4).
@MainActor
public final class SettingsHost: NSView {
    let dispatch: Dispatch
    private let controller: NSHostingController<SettingsRootView>
    private let scrollView = NSScrollView()
    private let toolbar: SettingsToolbar
    private(set) var settings: SettingsSnapshot?
    /// The pane on screen: the open pane, or the last one while the window is closed (so it does not go blank as it
    /// hides).
    private(set) var shownPane: SettingsPane = .general
    /// Whether macOS opens http and https links with this app; read when the window opens and when it becomes key
    /// (the user may have changed it in System Settings meanwhile).
    private(set) var isDefaultBrowser = false
    var defaultBrowserCheck: @MainActor () -> Bool = SettingsHost.appIsDefaultBrowser
    /// The Download Location menu's "Other…": a folder panel starting at the current folder; nil when cancelled.
    var chooseFolder: @MainActor (String?) -> String? = SettingsHost.runFolderPanel
    private var keyObserver: NSObjectProtocol?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        controller = NSHostingController(rootView: SettingsRootView(context: nil, pane: .general))
        toolbar = SettingsToolbar(dispatch: dispatch)
        super.init(frame: CGRect(origin: .zero, size: Metrics.settings.windowSize.value))
        controller.sizingOptions = []
        controller.safeAreaRegions = []
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = controller.view
        addSubview(scrollView)
        identify(.settingsWindow)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    /// The whole settings slice; an equal slice changes nothing.
    public func render(_ settings: SettingsSnapshot) {
        guard settings != self.settings else { return }
        let opening = settings.pane != nil && self.settings?.pane == nil
        let changingPane = settings.pane != nil && settings.pane != self.settings?.pane
        if changingPane || settings.pane == nil { window?.makeFirstResponder(nil) }
        self.settings = settings
        if let pane = settings.pane { shownPane = pane }
        if opening { isDefaultBrowser = defaultBrowserCheck() }
        update()
        if changingPane { scrollToTop() }
    }

    // MARK: Window

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        guard let window else { return }
        if window.toolbar !== toolbar.toolbar {
            window.toolbar = toolbar.toolbar
            window.toolbarStyle = .preference
        }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDefaultBrowser() }
        }
        update()
    }

    private func refreshDefaultBrowser() {
        let now = defaultBrowserCheck()
        guard now != isDefaultBrowser else { return }
        isDefaultBrowser = now
        update()
    }

    /// Cmd+W and Esc close the window when nothing inside took the key (a shortcut recorder may want them).
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard Self.closesWindow(event) else { return false }
        dispatch(.settings(.closeWindow))
        return true
    }

    public override func cancelOperation(_ sender: Any?) {
        dispatch(.settings(.closeWindow))
    }

    static func closesWindow(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.keyCode == Key.escape.code { return modifiers.isEmpty }
        return event.keyCode == Key.w.code && modifiers == .command
    }

    // MARK: Rendering

    private func update() {
        let context = settings.map { settings in
            PaneContext(settings: settings, dispatch: dispatch, isDefaultBrowser: isDefaultBrowser,
                        chooseFolder: { [weak self] current in self?.chooseFolder(current) ?? nil })
        }
        controller.rootView = SettingsRootView(context: context, pane: shownPane)
        toolbar.show(shownPane)
        window?.title = SettingsCopy.title(shownPane)
        fitWindow()
    }

    private func scrollToTop() {
        let document = controller.view
        let y = document.isFlipped ? 0 : max(0, document.frame.height - scrollView.contentSize.height)
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Fits the window to the pane, keeping its top edge where it is (the Settings package resizes per pane).
    private func fitWindow() {
        guard let window, let content = window.contentView else { return }
        let width = Metrics.settings.contentWidth.value + 2 * Metrics.settings.horizontalPadding.value
        // Never taller than the screen leaves room for: a pane that stretches (a flexible view added to it) gets
        // the screen's height instead of an infinite window.
        let chrome = window.frame.height - content.frame.height
        let tallest = (window.screen ?? NSScreen.main).map { $0.visibleFrame.height - chrome } ?? Metrics.settings.windowSize.value.height
        let fitted = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        let size = CGSize(width: width, height: min(fitted.height, tallest).rounded(.up))
        controller.view.setFrameSize(CGSize(width: width, height: max(size.height, fitted.height.rounded(.up))))
        guard size.height > 0, size != content.frame.size else { return }
        var frame = window.frame
        frame.size.width += size.width - content.frame.width
        frame.size.height += size.height - content.frame.height
        frame.origin.y = window.frame.maxY - frame.height
        if let screen = window.screen ?? NSScreen.main {
            frame.origin.y = max(screen.visibleFrame.minY, min(frame.origin.y, screen.visibleFrame.maxY - frame.height))
        }
        if window.isVisible {
            NSAnimationContext.runAnimationGroup { _ in window.animator().setFrame(frame, display: true) }
        } else {
            window.setFrame(frame, display: false)
        }
    }

    // MARK: System

    static func appIsDefaultBrowser() -> Bool {
        ["http", "https"].allSatisfy { scheme in
            guard let probe = URL(string: scheme + "://example.com/"), let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
            return handler.standardizedFileURL.resolvingSymlinksInPath() == Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        }
    }

    static func runFolderPanel(_ current: String?) -> String? {
        let panel = NSOpenPanel()
        panel.title = SettingsCopy.chooseFolderTitle
        panel.prompt = SettingsCopy.chooseFolderPrompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let current { panel.directoryURL = URL(fileURLWithPath: current, isDirectory: true) }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

/// What every pane is given: the snapshot, how to send, and the two facts that are not app state.
struct PaneContext {
    let settings: SettingsSnapshot
    let dispatch: Dispatch
    let isDefaultBrowser: Bool
    let chooseFolder: @MainActor (String?) -> String?
}

struct SettingsRootView: View {
    let context: PaneContext?
    let pane: SettingsPane

    var body: some View {
        if let context {
            SettingsContainer {
                switch pane {
                case .general: GeneralPane(context: context)
                case .max: MaxPane(context: context)
                case .profiles: ProfilesPane(context: context)
                case .shortcuts: ShortcutsPane(rows: context.settings.shortcuts, dispatch: context.dispatch)
                case .links: LinksPane(context: context)
                case .advanced: AdvancedPane(context: context)
                }
            }
            .background(IdentifiedRegion(id: .settingsPane(pane), label: SettingsCopy.paneDescription(pane)))
            .onExitCommand { context.dispatch(.settings(.closeWindow)) }
        } else {
            Color.clear.frame(width: Metrics.settings.windowSize.value.width, height: Metrics.settings.windowSize.value.height)
        }
    }
}

/// The pane toolbar (Arc: the Settings package's `ToolbarItemStyleViewController`): one selectable item per pane.
@MainActor
final class SettingsToolbar: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "settings")
    private let dispatch: Dispatch

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init()
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
    }

    static func identifier(_ pane: SettingsPane) -> NSToolbarItem.Identifier { NSToolbarItem.Identifier(ViewID.settingsPane(pane).identifier) }

    func show(_ pane: SettingsPane) {
        let id = Self.identifier(pane)
        if toolbar.selectedItemIdentifier != id { toolbar.selectedItemIdentifier = id }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { SettingsPane.allCases.map(Self.identifier) }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { SettingsPane.allCases.map(Self.identifier) }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { SettingsPane.allCases.map(Self.identifier) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = SettingsPane.allCases.first(where: { Self.identifier($0) == itemIdentifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = SettingsCopy.title(pane)
        item.paletteLabel = SettingsCopy.title(pane)
        item.toolTip = SettingsCopy.paneDescription(pane)
        item.image = NSImage(systemSymbolName: SettingsCopy.symbol(pane), accessibilityDescription: SettingsCopy.title(pane))
        item.target = self
        item.action = #selector(select(_:))
        return item
    }

    @objc func select(_ item: NSToolbarItem) {
        guard let pane = SettingsPane.allCases.first(where: { Self.identifier($0) == item.itemIdentifier }) else { return }
        dispatch(.settings(.openPane(pane)))
    }
}
