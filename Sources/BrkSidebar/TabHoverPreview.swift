import AppKit
import BrkBase
import BrkDomain

/// The card uses only the row's already projected metadata. It never fetches a page or crosses profiles.
@MainActor
final class TabHoverPreview {
    private var task: Task<Void, Never>?
    private var popover: NSPopover?
    private var content: String?
    func update(hovered: Bool, text: String?, over view: NSView) {
        guard hovered, let text, view.window != nil else { cancel(); return }
        if content != text { cancel(); content = text }
        guard task == nil, popover == nil else { return }
        task = Task { @MainActor [weak self, weak view] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, let view, view.window?.isVisible == true else { return }
            let controller = NSViewController()
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 12)
            label.frame = NSRect(x: 12, y: 10, width: 260, height: 68)
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 284, height: 88))
            host.addSubview(label)
            controller.view = host
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.contentViewController = controller
            self.popover = popover
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxX)
        }
    }
    func cancel() { content = nil; task?.cancel(); task = nil; popover?.close(); popover = nil }
}
