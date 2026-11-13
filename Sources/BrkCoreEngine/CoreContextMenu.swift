import AppKit
import BrkBase
import BrkEngine
import CBrkCore

/// A page's context menu on BrkCore: Chrome's own rows, trimmed and extended with Arc's as CEF's Brk does (BrkCEF/PageContextMenu.swift: the
/// same rows removed, "Translate to <language>" after Cast…, the Split View and Little Arc link rows), shown as an NSMenu on the page's view.
/// The framework waits for the answer, as Chrome's own menu does, and runs a Chrome row's command itself.
@MainActor
final class CoreContextMenu: NSObject, NSMenuDelegate {
    private struct Item {
        let title: String
        let command: Int
        let separator: Bool
        let enabled: Bool
        let checked: Bool
        let children: [Item]?
    }
    private final class Choice: NSObject {
        var selected: Int?
        @objc func choose(_ item: NSMenuItem) { selected = item.tag }
    }
    private var open: NSMenu?

    /// Outside Chromium's command ids, as on CEF.
    static let translateCommand = 28_400
    static let splitLinkCommand = 28_401, littleLinkCommand = 28_402
    static let removed: Set<String> = ["Create QR Code for this Page", "Create QR Code for this Image"]
    /// No Open Link in Incognito Window yet: the bridge forwards only new-window opens (OpenURLFromTabHook), so an
    /// off-the-record open takes Chrome's own path, toward a Chrome window of its own, not a Brk incognito window.
    /// CEF's menu has the row.
    static let linkRows: Set<String> = ["Open Link in New Tab", "Open Link in New Window",
                                        "Save Link As…", "Copy Link Address", "Copy", "Copy Link to Highlight", "Print…", "Inspect", "Speech"]
    static func isLinkRow(_ title: String) -> Bool { linkRows.contains(title) || (title.hasPrefix("Search ") && title.contains(" for ")) }

    /// The chosen Chrome command, or -1 (nothing, or one of Brk's own rows, which `onTranslate` and `onLink` handle).
    func run(_ raw: [[String: Any]], at point: CGPoint, in surface: NSView, link: Bool, translateTo: String?,
             onTranslate: () -> Void, onLink: (PageLinkTarget) -> Void) -> Int {
        let items = Self.withLinkRows(Self.withTranslate(Self.trimmed(Self.parse(raw), link: link), translateTo), link: link)
        guard !items.isEmpty, surface.window?.isVisible == true, !surface.isHiddenOrHasHiddenAncestor else { return -1 }
        let choice = Choice()
        let menu = makeMenu(items, target: choice)
        open = menu
        defer { open = nil }
        menu.popUpAsContextMenu(at: point, in: surface)
        guard let command = choice.selected else { return -1 }
        switch command {
        case Self.translateCommand: onTranslate(); return -1
        case Self.splitLinkCommand: onLink(.splitView); return -1
        case Self.littleLinkCommand: onLink(.littleWindow); return -1
        default: return command
        }
    }

    func cancel() { open?.cancelTracking() }

    private static func parse(_ raw: [[String: Any]]) -> [Item] {
        raw.map { row in
            if row["separator"] as? Bool == true { return Item(title: "", command: -1, separator: true, enabled: false, checked: false, children: nil) }
            return Item(title: label(row["title"] as? String ?? ""), command: row["command"] as? Int ?? -1, separator: false,
                        enabled: row["enabled"] as? Bool ?? false, checked: row["checked"] as? Bool ?? false,
                        children: (row["children"] as? [[String: Any]]).map(parse))
        }
    }

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

    private static func label(_ source: String) -> String {
        var chars = source.makeIterator(), value = ""
        while let char = chars.next() {
            if char == "&" { if let next = chars.next() { value.append(next) } }
            else { value.append(char) }
        }
        return value
    }

    private func makeMenu(_ items: [Item], target: Choice) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self
        for item in items {
            if item.separator { menu.addItem(.separator()); continue }
            let native = NSMenuItem(title: item.title, action: #selector(Choice.choose(_:)), keyEquivalent: "")
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

extension CorePage {
    /// As `ChromePage.browser(_:presentContextMenu:params:callback:)`.
    func runContextMenu(_ items: [[String: Any]], info: [String: Any]) -> Int {
        guard engine.isLive(self) else { return -1 }
        let linkURL = info["linkURL"] as? URL
        let editable = info["editable"] as? Bool ?? false
        let media = info["mediaType"] as? String ?? "none"
        let plainLink = linkURL != nil && media == "none" && !editable
        engine.pageDidEmit(self, .linkHovered(nil))
        let system = Locale.preferredLanguages.first ?? "en"
        let base = { (code: String) in String(code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "") }
        let translate: String? = if !plainLink, !editable, media == "none", !isAIReader, let language = detectedLanguage,
            !base(language).isEmpty, base(language) != base(system) { Locale(identifier: "en_US").localizedString(forLanguageCode: base(system)) } else { nil }
        let point = CGPoint(x: info["x"] as? Double ?? 0, y: info["y"] as? Double ?? 0)
        return contextMenu.run(items, at: point, in: surface, link: plainLink, translateTo: translate, onTranslate: {
            guard let translate, engine.isLive(self) else { return }
            engine.pageDidEmit(self, .translateRequested(translate))
        }, onLink: { target in
            guard let linkURL, engine.isLive(self) else { return }
            engine.pageDidEmit(self, .linkMenuRequested(linkURL, target))
        })
    }
}
