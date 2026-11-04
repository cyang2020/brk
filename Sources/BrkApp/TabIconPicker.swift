import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Arc's "Change Icon…" for a tab, folder or split (P10-a): a popover hanging from the row's icon, titled "Icon",
/// with three rows of eight glyphs. A click sets that icon and closes; clicking the current icon again restores
/// the default; Escape or a click elsewhere closes without a change.
@MainActor
enum TabIconPicker {
    /// The glyphs in Arc's order, left to right and top to bottom.
    static let icons: [NamedIcon] = [
        .star, .bookmark, .heart, .flash, .triangle, .medical, .notifications, .bulb,
        .chatBubbleEllipses, .people, .construction, .egg, .ellipse, .moon, .planet, .leaf,
        .cloud, .paw, .restaurant, .airplane, .musicalNote, .video, .code, .skull,
    ]
    private static var shown: NSPopover?
    private static var clicks: Any?
    private static var resign: NSObjectProtocol?

    /// Closes the open picker without a change. The popover is application-defined (a row's hover card, itself a
    /// transient popover, would otherwise close it), so a click outside it and leaving the app close it here.
    /// Escape closes an open picker before anything else sees the key (Lifecycle's Escape monitor asks).
    static var isOpen: Bool { shown != nil }

    static func close() {
        if let clicks { NSEvent.removeMonitor(clicks) }
        if let resign { NotificationCenter.default.removeObserver(resign) }
        clicks = nil
        resign = nil
        shown?.close()
        shown = nil
    }

    static func present(for item: ItemID, in window: NSWindow, initial: CustomIcon? = nil, choose: @escaping (CustomIcon?) -> Void) {
        close()
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        let grid = IconGridController(initial: initial) { icon in
            close()
            choose(icon)
        }
        popover.contentViewController = grid
        shown = popover
        clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            MainActor.assumeIsolated { if event.window !== grid.view.window { close() } }
            return event
        }
        resign = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { close() }
        }
        // The arrow points at the row's icon (16 points centred 26 from the sidebar edge), as Arc's does.
        if let row = ViewTree.find(ViewID.row(item).identifier, in: window) ?? ViewTree.find(ViewID.favorite(item).identifier, in: window),
           !row.isHiddenOrHasHiddenAncestor {
            let favorite = row.accessibilityIdentifier() == ViewID.favorite(item).identifier
            // The arrow touches the row's icon, 8 above the row's bottom edge (P10-a: the card's top at y 762 px).
            let anchor = favorite ? row.bounds : CGRect(x: min(18, row.bounds.width), y: 0, width: 16, height: max(0, row.bounds.height - 8))
            popover.show(relativeTo: anchor, of: row, preferredEdge: row.isFlipped ? .maxY : .minY)
        } else if let content = window.contentView {
            popover.show(relativeTo: CGRect(x: content.bounds.midX, y: content.bounds.midY, width: 1, height: 1), of: content, preferredEdge: .maxY)
        }
        // Key when AppKit allows it, so Escape typed into the popover itself closes it too.
        grid.view.window?.makeKey()
        grid.view.window?.makeFirstResponder(grid.view)
    }
}

@MainActor
private final class IconGridController: NSViewController {
    static let columns = 8, spacing: CGFloat = 31, size = CGSize(width: 272, height: 144)
    private let initial: CustomIcon?
    private let choose: (CustomIcon?) -> Void

    init(initial: CustomIcon?, choose: @escaping (CustomIcon?) -> Void) {
        self.initial = initial
        self.choose = choose
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let root = KeyView(frame: CGRect(origin: .zero, size: Self.size))
        root.setAccessibilityIdentifier("tab-icon-picker")
        let title = NSTextField(labelWithString: "Icon")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center
        title.frame = CGRect(x: 0, y: Self.size.height - 22.5 - 9, width: Self.size.width, height: 18)
        root.addSubview(title)
        let left = (Self.size.width - Self.spacing * CGFloat(Self.columns - 1)) / 2
        for (i, icon) in TabIconPicker.icons.enumerated() {
            let column = i % Self.columns, row = i / Self.columns
            let center = CGPoint(x: left + Self.spacing * CGFloat(column), y: Self.size.height - 57 - Self.spacing * CGFloat(row))
            let button = NSButton(frame: CGRect(x: center.x - 13, y: center.y - 13, width: 26, height: 26))
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.title = ""
            button.image = NamedIconArt.image(icon, pointSize: 11)
            button.imagePosition = .imageOnly
            button.contentTintColor = .secondaryLabelColor
            button.tag = i
            button.target = self
            button.action = #selector(picked(_:))
            button.setAccessibilityIdentifier("tab-icon-" + icon.rawValue)
            button.setAccessibilityLabel(icon.rawValue)
            if initial == .named(icon) {
                button.wantsLayer = true
                button.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
                button.layer?.cornerCurve = .continuous
                button.layer?.cornerRadius = Metrics.dock.cellRadius.value
            }
            root.addSubview(button)
        }
        view = root
        preferredContentSize = Self.size
    }

    @objc private func picked(_ sender: NSButton) {
        let icon = TabIconPicker.icons[sender.tag]
        choose(initial == .named(icon) ? nil : .named(icon))
    }

    override func cancelOperation(_ sender: Any?) { close() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }

    private func close() {
        TabIconPicker.close()
    }
}

/// Takes key focus inside the popover so its window can become key.
private final class KeyView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
}
