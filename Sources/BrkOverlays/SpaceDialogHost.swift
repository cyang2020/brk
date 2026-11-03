import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: W4 (dialogs). Every space dialog of a window, matched to the 2026-11-03 Arc 1.170 captures:
/// - New Space: the Create a Space flow in place of the sidebar's contents, a blank card over the content area, the
///   icon popover from the name field's icon button and the theme panel as a popover from Choose a Theme
///   (`SpaceCreateFlow.swift`). The draft's theme and icon are reported through `onDraft` while it is open.
/// - Rename Space and the delete confirmation: the small centred dialogs (`SpaceAlertView.swift`).
/// - Change Space Icon…: the Emoji / Icon popover under the space header (`SpaceIconPicker.swift`).
/// - Edit Theme…, Edit Theme Color… and the Library Space card's Edit Space…: the theme panel beside the sidebar
///   (`ThemeEditor.swift`); each edit is saved as it is made.
///
/// The host spans the window and takes clicks only on what it shows.
@MainActor
public final class SpaceDialogHost: NSView {
    let dispatch: Dispatch
    public var profiles: [ProfileRow] = [] {
        didSet {
            guard profiles != oldValue else { return }
            create?.profiles = profiles
        }
    }
    /// The Create a Space draft (theme and icon) whenever it changes, nil once the flow closes.
    public var onDraft: ((SpaceTheme, SpaceIcon)?) -> Void = { _ in }

    private var dialog: SpaceDialogSnapshot?
    private var deletion: SpaceDeletionRequest?
    private var scheme: Scheme = .light
    private var frames: WindowFrames?

    // Create a Space.
    private var create: SpaceCreateModel?
    private var flow: NSHostingView<SpaceCreateFlowView>?
    private let blank = NSView()
    private var themePopover: ThemePopover?
    // Rename and delete.
    private(set) var alert: SpaceAlertView?
    // Icon and theme.
    private var iconPopover: IconPickerPopover?
    private var themePanel: ThemePanelWindow?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        blank.wantsLayer = true
        blank.layer?.cornerCurve = .continuous
        blank.isHidden = true
        addSubview(blank)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// Keyboard focus into what is open: the delete dialog, the rename field or the Create a Space name field. False
    /// while nothing is shown or the view is not in a window.
    public func focusForm() -> Bool {
        guard !isHidden, let window else { return false }
        if let alert { return alert.focus() }
        if let flow {
            flow.layoutSubtreeIfNeeded()
            return window.makeFirstResponder(Self.firstEditableField(in: flow) ?? flow)
        }
        // The popovers and the theme panel leave the browser window's focus where it is.
        return iconPopover != nil || themePanel != nil
    }

    /// SwiftUI's text fields are NSTextFields underneath; the first in view order is the name.
    private static func firstEditableField(in view: NSView) -> NSTextField? {
        for child in view.subviews {
            if let field = child as? NSTextField, field.isEditable { return field }
            if let field = firstEditableField(in: child) { return field }
        }
        return nil
    }

    public func render(_ dialog: SpaceDialogSnapshot?, deletion: SpaceDeletionRequest?, frames: WindowFrames, palette: Palette) {
        if let superview { frame = superview.bounds }
        self.frames = frames
        let schemeChanged = palette.scheme != scheme
        scheme = palette.scheme
        let previous = self.dialog
        self.dialog = dialog
        self.deletion = deletion

        // What closed.
        if !Self.sameKind(previous, dialog) {
            closeCreate()
            iconPopover?.dismiss(); iconPopover = nil
            themePanel?.dismiss(); themePanel = nil
        }
        let wantsAlert: SpaceAlertKind? = deletion.map { .delete($0) } ?? {
            if case .rename(let id, let title)? = dialog { return .rename(id: id, title: title) }
            return nil
        }()
        if alert?.alert != wantsAlert || schemeChanged {
            alert?.removeFromSuperview()
            alert = wantsAlert.map { SpaceAlertView($0, scheme: scheme, dispatch: dispatch) }
            if let alert { addSubview(alert) }
        }
        alert?.frame = bounds
        // Shown before the popovers open: AppKit shows none relative to a hidden view.
        isHidden = dialog == nil && deletion == nil

        switch dialog {
        case .newSpace?: showCreate(frames: frames)
        case .icon(let id, let icon)?: showIconPicker(space: id, icon: icon, frames: frames)
        case .theme(let id, let theme)?: showThemePanel(space: id, theme: theme, frames: frames)
        case .rename?, nil: break
        }
    }

    private static func sameKind(_ a: SpaceDialogSnapshot?, _ b: SpaceDialogSnapshot?) -> Bool {
        switch (a, b) {
        case (nil, nil), (.newSpace?, .newSpace?): true
        case (.rename(let x, _)?, .rename(let y, _)?): x == y
        case (.icon(let x, _)?, .icon(let y, _)?): x == y
        case (.theme(let x, _)?, .theme(let y, _)?): x == y
        default: false
        }
    }

    private var systemScheme: Scheme {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    // MARK: Create a Space

    private func showCreate(frames: WindowFrames) {
        guard let sidebar = frames.sidebar else { return }
        if create == nil {
            let model = SpaceCreateModel(dispatch: dispatch)
            model.profiles = profiles
            model.systemScheme = systemScheme
            model.theme.draft.systemScheme = systemScheme
            model.changed = { [weak self] draft in self?.onDraft((draft.theme, draft.icon)) }
            model.showIconPicker = { [weak self, weak model] in
                guard let self, let model, let flow = self.flow else { return }
                self.iconPopover?.dismiss()
                let popover = IconPickerPopover(icon: model.draft.icon, pick: { [weak model] icon in model?.draft.icon = icon }, closed: { [weak self] in self?.iconPopover = nil })
                self.iconPopover = popover
                let field = CreateFlow.field.value
                popover.show(relativeTo: CGRect(x: field.minX + 4, y: field.minY - CreateFlow.top.value, width: 22, height: field.height), of: flow,
                             scheme: resolveTheme(model.draft.theme, systemScheme: self.systemScheme).scheme)
            }
            model.showThemeEditor = { [weak self, weak model] in
                guard let self, let model, let flow = self.flow else { return }
                let popover = self.themePopover ?? ThemePopover(model: model.theme)
                self.themePopover = popover
                let row = CreateFlow.themeRow.value
                popover.show(relativeTo: CGRect(x: row.minX, y: row.minY - CreateFlow.top.value, width: row.width, height: row.height), of: flow, scheme: .light)
            }
            create = model
            onDraft((model.draft.theme, model.draft.icon))
        }
        guard let create else { return }
        let top = sidebar.frame.minY + CreateFlow.top.value
        let height = max(0, sidebar.dock.minY - top)
        if flow == nil {
            let view = NSHostingView(rootView: SpaceCreateFlowView(model: create, height: height))
            view.identify(.spaceDialog)
            addSubview(view)
            flow = view
        } else if flow?.rootView.height != height {
            flow?.rootView = SpaceCreateFlowView(model: create, height: height)
        }
        flow?.frame = CGRect(x: sidebar.frame.minX, y: top, width: sidebar.frame.width, height: height)
        blank.isHidden = false
        blank.frame = frames.contentArea
        blank.layer?.cornerRadius = Metrics.content.cornerRadius.value
        blank.layer?.backgroundColor = NSColor.white.withAlphaComponent(scheme == .light ? 0.75 : 0.08).cgColor
    }

    private func closeCreate() {
        guard create != nil || flow != nil else { return }
        themePopover?.dismiss(); themePopover = nil
        flow?.removeFromSuperview(); flow = nil
        create = nil
        blank.isHidden = true
        onDraft(nil)
    }

    // MARK: Icon and theme

    private func showIconPicker(space: SpaceID, icon: SpaceIcon, frames: WindowFrames) {
        guard iconPopover == nil, let header = frames.sidebar?.spaceHeader else { return }
        let popover = IconPickerPopover(icon: icon, pick: { [dispatch] icon in
            dispatch(.space(.update(space, title: nil, icon: icon, theme: nil)))
        }, closed: { [weak self, dispatch] in
            guard let self, case .icon(space, _)? = self.dialog else { return }
            self.iconPopover = nil
            dispatch(.sidebar(.openDialog(nil)))
        })
        iconPopover = popover
        popover.show(relativeTo: CGRect(x: header.minX + 8, y: header.minY, width: 22, height: header.height), of: self, scheme: scheme)
    }

    private func showThemePanel(space: SpaceID, theme: SpaceTheme, frames: WindowFrames) {
        guard let window else { return }
        let draft = ThemeDraft(theme: theme, systemScheme: systemScheme)
        if themePanel?.space != space {
            themePanel?.dismiss()
            themePanel = ThemePanelWindow(space: space, draft: draft, onChange: { [dispatch] draft in
                dispatch(.space(.update(space, title: nil, icon: nil, theme: draft.theme)))
            }, close: { [dispatch] in dispatch(.sidebar(.openDialog(nil))) })
        }
        themePanel?.update(draft)
        themePanel?.show(over: window, sidebarMaxX: Double(frames.sidebar?.frame.maxX ?? 0), scheme: scheme)
    }
}

extension RGBA {
    var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    var swiftUI: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

/// A space icon as the dock draws it: the emoji, the named icon's symbol, or a dot in the theme color.
struct SpaceGlyph: View {
    let icon: SpaceIcon
    let dot: Color

    var body: some View {
        switch icon {
        case .none:
            let side = OverlayMetrics.dialog.dotSize.value
            Circle().fill(dot).frame(width: side, height: side).overlay(Circle().stroke(.white.opacity(0.6)))
        case .custom(.emoji(let emoji)): Text(emoji)
        case .custom(.named(let name)): Image(systemName: NamedIconSymbol.of(name))
        case .custom(.symbol(let symbol)): Image(systemName: symbol)
        }
    }
}
