import AppKit
import BrkBase
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

    /// Brk's own row's command: outside Chromium's ids (MENU_ID_USER_FIRST 26500 to MENU_ID_USER_LAST 28500); Chromium
    /// never sees it, the menu cancels and `onTranslate` runs instead.
    static let translateCommand = 28_400
    /// Arc's own link rows (Q07-b), handled the same way: "Open Link in Split View" and "Open Link in Little Arc" (with
    /// the product's name) go in after "Open Link in New Window".
    static let splitLinkCommand = 28_401, littleLinkCommand = 28_402

    func show(_ model: CefMenuModel, at point: CGPoint, in surface: NSView, link: Bool = false, translateTo: String? = nil,
              callback: CefRunContextMenuCallback, onTranslate: @escaping @MainActor () -> Void = {},
              onLink: @escaping @MainActor (PageLinkTarget) -> Void = { _ in }, valid: @escaping @MainActor () -> Bool) {
        cancel()
        let items = Self.withLinkRows(Self.withTranslate(Self.trimmed(snapshot(model), link: link), translateTo), link: link)
        guard !items.isEmpty, let owner = surface.window else { callback.cancel(); return }
        let request = Pending(callback)
        pending = request
        // CEF forbids entering an OS modal loop inside run_context_menu. The model is borrowed only above.
        DispatchQueue.main.async { [weak self, weak surface, weak owner] in
            guard let self, self.pending === request else { callback.cancel(); return }
            guard let surface, let owner, surface.window === owner, owner.isVisible,
                  !surface.isHiddenOrHasHiddenAncestor, valid() else { self.cancel(); return }
            let menu = self.makeMenu(items, target: request)
            // Q07-b: Arc's link menu has no column for a check mark, its titles start 6 points further left.
            if link { menu.showsStateColumn = false }
            request.menu = menu
            _ = menu.popUp(positioning: nil, at: point, in: surface)
            guard self.pending === request else { return }
            self.pending = nil
            if let command = request.selected, valid() {
                switch command {
                case Self.translateCommand: callback.cancel(); onTranslate()
                case Self.splitLinkCommand: callback.cancel(); onLink(.splitView)
                case Self.littleLinkCommand: callback.cancel(); onLink(.littleWindow)
                default: callback.select(commandID: command)
                }
            } else { callback.cancel() }
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

    /// Chromium rows Arc 1.170 does not show (Q07): the QR code row everywhere. On a plain link (Q07-b, Arc's menu with
    /// the link's words highlighted): opening, saving and copying it, Copy, Copy Link to Highlight, Search, Print…,
    /// Inspect and Speech. Separators left next to each other or at an end go too.
    static let removed: Set<String> = ["Create QR Code for this Page", "Create QR Code for this Image"]
    static let linkRows: Set<String> = ["Open Link in New Tab", "Open Link in New Window", "Open Link in Incognito Window",
                                        "Save Link As…", "Copy Link Address", "Copy", "Copy Link to Highlight", "Print…", "Inspect", "Speech"]
    static func isLinkRow(_ title: String) -> Bool { linkRows.contains(title) || (title.hasPrefix("Search ") && title.contains(" for ")) }

    /// "Translate to English" closes the Save As… / Print… / Cast… group, as in Arc's page menu (Q07-a); without that
    /// group it goes before the last group.
    private static func withTranslate(_ items: [Item], _ language: String?) -> [Item] {
        guard let language else { return items }
        let row = Item(title: "Translate to \(language)", command: translateCommand, separator: false, enabled: true, checked: false, children: nil)
        var out = items
        if let cast = out.firstIndex(where: { $0.title.replacingOccurrences(of: "...", with: "…") == "Cast…" }) { out.insert(row, at: cast + 1) }
        else if let separator = out.lastIndex(where: \.separator) { out.insert(row, at: separator) }
        else { out.append(row) }
        return out
    }

    private static func withLinkRows(_ items: [Item], link: Bool) -> [Item] {
        guard link, let window = items.firstIndex(where: { $0.title == "Open Link in New Window" }) else { return items }
        func row(_ title: String, _ command: Int) -> Item { Item(title: title, command: command, separator: false, enabled: true, checked: false, children: nil) }
        var out = items
        out.insert(contentsOf: [row("Open Link in Split View", splitLinkCommand), row("Open Link in Little \(Product.name)", littleLinkCommand)], at: window + 1)
        return out
    }

    private static func trimmed(_ items: [Item], link: Bool) -> [Item] {
        let kept = items.filter { item in
            let title = item.title.replacingOccurrences(of: "...", with: "…")
            return item.separator || (!removed.contains(title) && (!link || isLinkRow(title)))
        }
        var out: [Item] = []
        for item in kept {
            if item.separator, out.last?.separator ?? true { continue }
            out.append(item)
        }
        while out.last?.separator == true { out.removeLast() }
        return out
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
