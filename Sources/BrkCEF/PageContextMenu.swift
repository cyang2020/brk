import AppKit
import BrkEngine
import CefKit

/// CEF's host window no longer contains the page. Present its menu on the actual embedded surface.
@MainActor final class PageContextMenu: NSObject, NSMenuDelegate {
    private struct Item {
        let title: String
        let command: Int
        let separator: Bool
        let enabled: Bool
        let checked: Bool
        let children: [Item]?
    }
    private final class Pending: NSObject {
        let callback: CefRunContextMenuCallback
        var menu: NSMenu?
        var selected: Int?
        init(_ callback: CefRunContextMenuCallback) { self.callback = callback; super.init() }
        @objc func choose(_ item: NSMenuItem) { selected = item.tag }
    }
    private var pending: Pending?

    func show(_ model: CefMenuModel, at point: CGPoint, in surface: NSView,
              callback: CefRunContextMenuCallback, valid: @escaping @MainActor () -> Bool) {
        cancel()
        let items = snapshot(model)
        guard !items.isEmpty, let owner = surface.window else { callback.cancel(); return }
        let request = Pending(callback)
        pending = request
        // CEF forbids entering an OS modal loop inside run_context_menu. The model is borrowed only above.
        DispatchQueue.main.async { [weak self, weak surface, weak owner] in
            guard let self, self.pending === request else { callback.cancel(); return }
            guard let surface, let owner, surface.window === owner, owner.isVisible,
                  !surface.isHiddenOrHasHiddenAncestor, valid() else { self.cancel(); return }
            let menu = self.makeMenu(items, target: request)
            request.menu = menu
            _ = menu.popUp(positioning: nil, at: point, in: surface)
            guard self.pending === request else { return }
            self.pending = nil
            if let command = request.selected, valid() { callback.select(commandID: command) }
            else { callback.cancel() }
        }
    }

    func cancel() {
        guard let request = pending else { return }
        pending = nil
        request.menu?.cancelTracking()
        request.callback.cancel()
    }

    private func snapshot(_ model: CefMenuModel) -> [Item] {
        (0..<model.count).compactMap { i in
            guard model.isVisible(at: i) else { return nil }
            if model.isSeparator(at: i) { return Item(title: "", command: -1, separator: true, enabled: false, checked: false, children: nil) }
            return Item(title: label(model.label(at: i)), command: model.commandID(at: i),
                        separator: false, enabled: model.isEnabled(at: i), checked: model.isChecked(at: i),
                        children: model.withSubmenu(at: i) { snapshot($0) })
        }
    }

    private func label(_ source: String) -> String {
        var chars = source.makeIterator(), value = ""
        while let char = chars.next() {
            if char == "&" { if let next = chars.next() { value.append(next) } }
            else { value.append(char) }
        }
        return value
    }

    private func makeMenu(_ items: [Item], target: Pending) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self
        for item in items {
            if item.separator { menu.addItem(.separator()); continue }
            let native = NSMenuItem(title: item.title, action: #selector(Pending.choose(_:)), keyEquivalent: "")
            native.target = target; native.tag = item.command; native.isEnabled = item.enabled
            native.state = item.checked ? .on : .off
            if let children = item.children { native.submenu = makeMenu(children, target: target) }
            menu.addItem(native)
        }
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
            NotificationCenter.default.post(name: PageSurfaceView.contextMenuWillOpen, object: menu)
        }
    }
    func menuDidClose(_ menu: NSMenu) {
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
            NotificationCenter.default.post(name: PageSurfaceView.contextMenuDidClose, object: menu)
        }
    }

}
