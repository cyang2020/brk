import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkLayout
import BrkUIKit

@MainActor
final class SplitToolsView: NSView {
    private let dispatch: Dispatch
    private var buttons: [ActionID: NSButton] = [:]
    private var expanded = false

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Metrics.content.cornerRadius.value
        for (action, label) in [(ActionID.splitHorizontal, "↔"), (.splitVertical, "↕"), (.maximizeSplitPane, "Expand"),
                                (.separateTabFromSplitView, "Separate"), (.separateAllSplit, "All")] {
            let button = NSButton(title: label, target: self, action: #selector(clicked(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            button.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
            button.identify(.splitTool(action))
            button.toolTip = action.title(appName: Product.name)
            buttons[action] = button
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(_ content: ContentSnapshot, in area: CGRect, avoiding overlay: CGRect? = nil, palette: Palette) {
        isHidden = content.split == nil
        guard !isHidden else { return }
        expanded = content.expanded
        buttons[.maximizeSplitPane]?.title = expanded ? "Restore" : "Expand"
        buttons[.maximizeSplitPane]?.toolTip = expanded ? "Restore Split Panes" : "Expand Current Split"
        buttons[.splitHorizontal]?.state = content.orientation == .horizontal ? .on : .off
        buttons[.splitVertical]?.state = content.orientation == .vertical ? .on : .off
        appearance = NSAppearance(named: palette.scheme == .dark ? .darkAqua : .aqua)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        frame = SplitToolsLayout.toolbar(in: area, avoiding: overlay)
        var x = 4.0
        for (action, width) in [(ActionID.splitHorizontal, 28.0), (.splitVertical, 28), (.maximizeSplitPane, 62),
                                 (.separateTabFromSplitView, 70), (.separateAllSplit, 36)] {
            buttons[action]?.frame = CGRect(x: x, y: 2, width: width, height: 24)
            x += width + 1
        }
    }

    @objc private func clicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let action = ActionID(rawValue: raw) else { return }
        dispatch(action == .maximizeSplitPane && expanded ? .split(.restore) : action.spec.command)
    }
}

@MainActor
final class SplitDropPreview: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
