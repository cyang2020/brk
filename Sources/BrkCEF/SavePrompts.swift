import AppKit
import BrkBase

/// Chromium's own "Save password?", "Save address?" and "Save card?" bubbles, replaced by Arc's centred cards (`SavePrompt`). CEF has no interface for
/// the password manager's prompt, so the bubble is found when its window comes on screen, read through its
/// accessibility tree (Chromium's text follows the Mac's language, so by its structure, not its words), made
/// invisible and click-through, and the app is asked instead. The app's answer presses the bubble's own button, so
/// Chromium saves, declines or blocklists exactly as its bubble would. A bubble Chromium closes by itself (the page
/// left, the tab changed) withdraws the card.
///
/// Like `HostWindows`, this depends on Chromium's private window class and on its bubble's layout; the scenario
/// Password-SaveCard checks the whole path with a real login form and real clicks.
@MainActor
final class SavePrompts {
    /// The live pages as (id, CEF host window, current URL).
    var pages: () -> [(page: PageID, host: NSWindow?, url: URL?)] = { [] }
    var offer: (SavePrompt, @escaping @MainActor (SavePromptAnswer) -> Void) -> Void = { _, reply in reply(.notNow) }
    var withdraw: (String) -> Void = { _ in }

    private struct Pending {
        let id: String
        let buttons: SaveBubble.Buttons
    }
    /// Bubbles already looked at (the password bubble and every other Chromium widget), so each is read once.
    private let seen = NSHashTable<NSWindow>.weakObjects()
    private var pending: [ObjectIdentifier: Pending] = [:]
    private var observers: [NSObjectProtocol] = []
    private var counter = 0

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        // A window coming on screen changes its occlusion state; Chromium's bubbles post it like any other window.
        observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.windowChanged(window) }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.closed(window) }
        })
    }

    private func windowChanged(_ window: NSWindow) {
        guard NSStringFromClass(type(of: window)) == "NativeWidgetMacNSWindow" else { return }
        if !window.isVisible { closed(window); return }
        guard !seen.contains(window) else { return }
        // The widget's views may still be filling in when it first shows; look a few times before giving up on it.
        inspect(window, attempt: 0)
    }

    private func inspect(_ window: NSWindow, attempt: Int) {
        guard window.isVisible, !seen.contains(window) else { return }
        let tree = AXNode.read(window)
        if let found = SaveBubble.classify(tree, rightToLeft: Self.rightToLeft) {
            seen.add(window)
            take(window, kind: found.kind, buttons: found.buttons)
            return
        }
        guard attempt < 3 else { seen.add(window); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + [0.05, 0.15, 0.35][attempt]) { [weak self, weak window] in
            guard let self, let window else { return }
            self.inspect(window, attempt: attempt + 1)
        }
    }

    /// Chromium lays its bubbles out right to left in the Mac's first language when that language reads that way.
    private static var rightToLeft: Bool {
        Locale.preferredLanguages.first.map { Locale.Language(identifier: $0).characterDirection == .rightToLeft } ?? false
    }

    private func take(_ bubble: NSWindow, kind: SavePrompt.Kind, buttons: SaveBubble.Buttons) {
        guard let owner = owner(of: bubble) else { return }
        // Invisible and click-through, not closed: its buttons are how the answer reaches Chromium. Chromium fades the
        // widget in by animating its alpha, which would undo a single change, so its content is hidden too (as
        // `HostWindows.hideStatusBubble` does) and the alpha set again while the fade could still be running.
        Self.hide(bubble)
        for delay in [0.05, 0.15, 0.3, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak bubble] in if let bubble { Self.hide(bubble) } }
        }
        counter += 1
        let id = "save-\(counter)"
        pending[ObjectIdentifier(bubble)] = Pending(id: id, buttons: buttons)
        let site = owner.url?.host.flatMap { $0.isEmpty ? nil : $0 }
        offer(SavePrompt(id: id, page: owner.page, kind: kind, site: site)) { [weak self, weak bubble] answer in
            guard let self, let bubble, let entry = self.pending.removeValue(forKey: ObjectIdentifier(bubble)) else { return }
            let target: AXNode?
            switch answer {
            case .save: target = entry.buttons.save
            case .notNow: target = entry.buttons.notNow
            case .never: target = entry.buttons.never ?? entry.buttons.notNow
            }
            if target?.press() != true { bubble.close() }
        }
    }

    private static func hide(_ bubble: NSWindow) {
        bubble.alphaValue = 0
        bubble.hasShadow = false
        bubble.ignoresMouseEvents = true
        bubble.contentView?.isHidden = true
    }

    /// The page whose host window the bubble belongs to: its parent chain, else the host its frame lies in.
    private func owner(of bubble: NSWindow) -> (page: PageID, url: URL?)? {
        let pages = pages()
        var parent = bubble.parent
        while let window = parent {
            if let match = pages.first(where: { $0.host === window }) { return (match.page, match.url) }
            parent = window.parent
        }
        let centre = CGPoint(x: bubble.frame.midX, y: bubble.frame.midY)
        return pages.first { $0.host?.isVisible == true && $0.host?.frame.contains(centre) == true }.map { ($0.page, $0.url) }
    }

    private func closed(_ window: NSWindow) {
        guard let entry = pending.removeValue(forKey: ObjectIdentifier(window)) else { return }
        withdraw(entry.id)
    }
}

/// One element of a window's accessibility tree: its role, its frame on screen and its children, with the object
/// itself kept for pressing. Built from AppKit's accessibility protocol, in process.
struct AXNode {
    var role: String
    var frame: CGRect
    var children: [AXNode]
    var element: AnyObject?

    init(role: String, frame: CGRect, children: [AXNode] = [], element: AnyObject? = nil) {
        self.role = role; self.frame = frame; self.children = children; self.element = element
    }

    @MainActor
    static func read(_ object: Any, depth: Int = 0) -> AXNode {
        guard depth < 24, let element = object as? NSAccessibilityProtocol else { return AXNode(role: "", frame: .zero) }
        let children = depth < 23 ? (element.accessibilityChildren() ?? []).map { read($0, depth: depth + 1) } : []
        return AXNode(role: element.accessibilityRole()?.rawValue ?? "", frame: element.accessibilityFrame(), children: children, element: element as AnyObject)
    }

    func flattened() -> [AXNode] { [self] + children.flatMap { $0.flattened() } }

    @MainActor
    func press() -> Bool {
        guard let element = element as? NSAccessibilityProtocol else { return false }
        return element.accessibilityPerformPress()
    }
}

/// How Chromium 156's save bubbles are recognized, each with a heading, its small close button and one row of
/// full-height buttons, Save last in reading order (first in a right-to-left language):
/// - password (ManagePasswordsBubbleView, save state): the username and password combo boxes, the show-password check
///   box, three buttons: Never, No Thanks, Save. The update state has two buttons and does not match.
/// - address (SaveAddressProfileView): no fields, a second small button (Edit address), two buttons: No thanks, Save.
/// - card (SaveCardBubbleViews): no fields, the card network's image, two buttons: No Thanks, Save.
enum SaveBubble {
    struct Buttons {
        let never: AXNode?
        let notNow: AXNode
        let save: AXNode
    }

    static func classify(_ root: AXNode, rightToLeft: Bool = false) -> (kind: SavePrompt.Kind, buttons: Buttons)? {
        if let buttons = passwordButtons(in: root, rightToLeft: rightToLeft) { return (.password, buttons) }
        let all = root.flattened()
        guard all.contains(where: { $0.role == heading }),
              !all.contains(where: { $0.role == NSAccessibility.Role.comboBox.rawValue || $0.role == NSAccessibility.Role.checkBox.rawValue
                  || $0.role == NSAccessibility.Role.textField.rawValue }),
              let row = actionRow(all, count: 2, rightToLeft: rightToLeft) else { return nil }
        let small = all.filter { $0.role == NSAccessibility.Role.button.rawValue && $0.frame.height < 28 }.count
        let image = all.contains { $0.role == NSAccessibility.Role.image.rawValue }
        let buttons = Buttons(never: nil, notNow: row[0], save: row[1])
        if small == 2, !image { return (.address, buttons) }
        if small == 1, image { return (.card, buttons) }
        return nil
    }

    /// The one row of `count` full-height buttons (the close and edit buttons are 22 to 24 tall, these 36), in reading order.
    private static func actionRow(_ all: [AXNode], count: Int, rightToLeft: Bool) -> [AXNode]? {
        let buttons = all.filter { $0.role == NSAccessibility.Role.button.rawValue && $0.frame.height >= 28 }
        let rows = Dictionary(grouping: buttons) { Int($0.frame.minY.rounded()) }.values
        guard rows.count == 1, let row = rows.first, row.count == count else { return nil }
        return row.sorted { rightToLeft ? $0.frame.minX > $1.frame.minX : $0.frame.minX < $1.frame.minX }
    }

    /// AppKit names the heading role only from macOS 26 (NSAccessibilityHeadingRole); Chromium reports it on every version.
    static let heading = "AXHeading"

    static func passwordButtons(in root: AXNode, rightToLeft: Bool = false) -> Buttons? {
        let all = root.flattened()
        guard all.contains(where: { $0.role == heading }),
              all.filter({ $0.role == NSAccessibility.Role.comboBox.rawValue }).count == 2,
              all.contains(where: { $0.role == NSAccessibility.Role.checkBox.rawValue }) else { return nil }
        guard let row = actionRow(all, count: 3, rightToLeft: rightToLeft) else { return nil }
        return Buttons(never: row[0], notNow: row[1], save: row[2])
    }
}
