import AppKit
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Native controls keep first-click and keyboard behavior in inactive browser windows, as the settings panes do.
struct SpaceToolsButton: NSViewRepresentable {
    let title: String
    var id: String? = nil
    var key = ""
    var color: RGBA? = nil
    var selected = false
    let action: @MainActor () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.click))
        button.bezelStyle = .rounded
        return button
    }
    func updateNSView(_ button: NSButton, context: NSViewRepresentableContext<Self>) {
        context.coordinator.action = action
        button.title = title; button.keyEquivalent = key
        button.isEnabled = context.environment.isEnabled
        if let id { button.identify(.spaceToolsControl(id)) }
        button.image = selected ? NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) : nil
        button.imagePosition = .imageLeading
        if let color {
            button.title = ""
            button.image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
                NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
                return true
            }
            button.imagePosition = .imageOnly
            button.toolTip = title
            button.setAccessibilityLabel(title)
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: NSViewRepresentableContext<Self>) -> CGSize? {
        let size = nsView.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? size.width, size.width), height: max(size.height, color == nil ? 24 : 28))
    }
    @MainActor final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        init(_ action: @escaping @MainActor () -> Void) { self.action = action }
        @objc func click() { action() }
    }
}
