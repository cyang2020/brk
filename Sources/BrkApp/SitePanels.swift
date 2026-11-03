import AppKit
import BrkBase
import BrkDomain
import BrkSettings
import BrkLayout

/// Site controls (Arc's site control center): one NSPopover per window, anchored under the URL pill's site button
/// and attached to that window, so it never floats over other apps. A click elsewhere in the window, Escape or
/// Cmd+W closes it; clicking the site button again toggles it. Sheets and other windows leave it open (a clear
/// confirmation sheet reports its result back into the popover).
@MainActor
final class SitePanels: NSObject, NSPopoverDelegate {
    private final class Entry {
        let popover: NSPopover
        let host: SiteControlsHost
        weak var parent: NSWindow?
        var value: SiteControlSnapshot?
        var monitor: Any?
        init(popover: NSPopover, host: SiteControlsHost, parent: NSWindow) { self.popover = popover; self.host = host; self.parent = parent }
    }
    private var entries: [WindowID: Entry] = [:]
    var send: ((WindowID, Command) -> Void)?

    /// `scheme` is the window theme's: the popover draws light or dark with the sidebar, not with the system.
    func render(_ snapshots: [WindowID: SiteControlSnapshot], owner: (WindowID) -> NSWindow?, scheme: (WindowID) -> Scheme?) {
        for (id, entry) in entries {
            guard snapshots[id] != nil, let parent = owner(id), entry.parent === parent else { dismiss(id); continue }
        }
        for (id, value) in snapshots {
            guard let parent = owner(id), parent.isVisible else { continue }
            let appearance = NSAppearance(named: scheme(id) == .dark ? .darkAqua : .aqua)
            guard let entry = entries[id] ?? open(id, value, in: parent, appearance: appearance) else { continue }
            if entry.popover.appearance?.name != appearance?.name { entry.popover.appearance = appearance }
            guard entry.value != value else { continue }
            entry.value = value
            entry.host.render(value) { [weak self] in self?.send?(id, $0) }
        }
    }

    func window(for id: WindowID) -> NSWindow? { entries[id]?.popover.contentViewController?.view.window }

    private func open(_ id: WindowID, _ value: SiteControlSnapshot, in parent: NSWindow, appearance: NSAppearance?) -> Entry? {
        guard let content = parent.contentView else { return nil }
        let host = SiteControlsHost(frame: .zero)
        let controller = NSViewController()
        controller.view = host
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.appearance = appearance
        popover.contentViewController = controller
        popover.delegate = self
        let entry = Entry(popover: popover, host: host, parent: parent)
        entries[id] = entry
        host.render(value) { [weak self] in self?.send?(id, $0) }
        entry.value = value
        popover.contentSize = host.preferredSize
        host.onResize = { [weak popover] size in popover?.contentSize = size }
        let (rect, edge) = Self.anchor(in: parent, content: content)
        popover.show(relativeTo: rect, of: content, preferredEdge: edge)
        // Arc's popover is a flat PopoverBackground, not the system's translucent material (which also takes on
        // whatever window is behind it).
        if let frame = host.superview {
            let background = PopoverBackground(frame: frame.bounds)
            background.autoresizingMask = [.width, .height]
            frame.addSubview(background, positioned: .below, relativeTo: host)
        }
        entry.monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            self?.handle(event, for: id) ?? event
        }
        return entry
    }
    /// Where Arc's arrow points (P36-a): at the site icon 19 pt in from the URL pill's right edge, the body 8 pt under the
    /// pill; under a split pane's own button when that opened it. Then the site button wherever it is; the content
    /// area's top-left corner when the sidebar is hidden.
    static func anchor(in window: NSWindow, content: NSView) -> (CGRect, NSRectEdge) {
        let below: NSRectEdge = content.isFlipped ? .maxY : .minY
        let m = Metrics.siteControls
        func visible(_ id: ViewID) -> CGRect? {
            guard let view = ViewTree.find(id.identifier, in: window), view.window === window, !view.isHiddenOrHasHiddenAncestor else { return nil }
            let rect = view.convert(view.bounds, to: content)
            return !rect.isEmpty && content.bounds.contains(CGPoint(x: rect.midX, y: rect.midY)) ? rect : nil
        }
        // Opened from a split pane's header: under that pane's button.
        if let pane = visible(.paneSiteInfo), let event = NSApp.currentEvent, event.window === window,
           [.leftMouseDown, .leftMouseUp].contains(event.type), pane.contains(content.convert(event.locationInWindow, from: nil)) {
            return (pane, below)
        }
        if let pill = visible(.urlPill) {
            let x = pill.maxX - m.anchorTrailing.value, rise = m.anchorRise.value
            let rect = content.isFlipped ? CGRect(x: x, y: pill.minY, width: 0, height: pill.height - rise)
                : CGRect(x: x, y: pill.minY + rise, width: 0, height: pill.height - rise)
            return (rect.insetBy(dx: -0.5, dy: 0), below)
        }
        if let button = visible(.siteInfo) { return (button, below) }
        let corner = Metrics.siteControls.fallbackAnchor.value
        let top = content.isFlipped ? content.bounds.minY + corner.y : content.bounds.maxY - corner.y
        return (CGRect(x: content.bounds.minX + corner.x, y: top, width: 0, height: 0).insetBy(dx: -0.5, dy: -0.5), below)
    }

    private func handle(_ event: NSEvent, for id: WindowID) -> NSEvent? {
        guard let entry = entries[id], let parent = entry.parent else { return event }
        let popoverWindow = entry.popover.contentViewController?.view.window
        if event.type == .keyDown {
            guard event.window === popoverWindow || event.window === parent else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
            let escape = event.keyCode == 53 && modifiers.isEmpty
            let closeKey = modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "w" && event.window === popoverWindow
            guard escape || closeKey else { return event }
            close(id); return nil
        }
        guard event.window === parent else { return event }
        // A click on the site button closes the popover instead of reopening it.
        let hit = parent.contentView?.superview?.hitTest(event.locationInWindow) ?? parent.contentView?.hitTest(event.locationInWindow)
        var view = hit
        while let current = view, current.accessibilityIdentifier() != ViewID.siteInfo.identifier { view = current.superview }
        close(id)
        return view == nil ? event : nil
    }

    private func close(_ id: WindowID) {
        guard entries[id] != nil else { return }
        dismiss(id)
        send?(id, .site(.closeControls))
    }

    private func dismiss(_ id: WindowID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        if let monitor = entry.monitor { NSEvent.removeMonitor(monitor) }
        entry.popover.close()
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover, let id = entries.first(where: { $0.value.popover === popover })?.key else { return }
        close(id)
    }
}

@MainActor
final class SiteDialogs: NSObject, NSPopoverDelegate {
    private struct Prompt {
        let target: SiteTarget
        let allowLoading: Bool
        /// Takes the prompt off screen without answering.
        let close: @MainActor () -> Void
        let cancel: () -> Void
    }
    private var prompts: [String: Prompt] = [:]
    func validate(_ snapshot: AppSnapshot) {
        for (id, prompt) in prompts {
            let document = snapshot.observations[prompt.target.page]?.document
            let current = document == .ready(prompt.target.document) || (prompt.allowLoading && document == .loading(prompt.target.document))
            guard !current || !snapshot.pages.contains(where: { $0.id == prompt.target.page && $0.context == prompt.target.context }) else { continue }
            dismiss(id)
        }
    }
    func confirm(_ request: ClearSiteData, in window: NSWindow?, reply: @escaping (Bool) -> Void) {
        guard let window, window.attachedSheet == nil else { reply(false); return }
        let alert = NSAlert()
        alert.messageText = "Clear browsing data?"
        alert.informativeText = request.explanation + "\n\nProfile records, settings, tabs and downloaded files are kept. Active downloads, document output and extension operations must finish first."
        alert.addButton(withTitle: "Clear data"); alert.addButton(withTitle: "Cancel")
        let key = ViewID.settingsField("confirmSiteClear").identifier
        alert.buttons[0].identifier = NSUserInterfaceItemIdentifier(key)
        alert.buttons[0].setAccessibilityIdentifier(key)
        prompts[request.id] = Prompt(target: request.target, allowLoading: false, close: { [weak alert] in
            guard let window = alert?.window else { return }
            window.sheetParent?.endSheet(window, returnCode: .cancel); window.orderOut(nil)
        }, cancel: { reply(false) })
        alert.beginSheetModal(for: window) { [weak self] response in
            guard self?.prompts.removeValue(forKey: request.id) != nil else { return }
            reply(response == .alertFirstButtonReturn)
        }
    }
    /// Brk's own prompt (`SitePermissionPromptView`) in a popover under the address, attached to the page's window.
    /// Escape or a click elsewhere in the window closes it unanswered; a newer document dismisses it (`validate`).
    func permission(_ prompt: SitePermissionPrompt, in window: NSWindow?, answer: @escaping (SitePermission, Bool) -> Void) {
        guard let window, window.isVisible, let content = window.contentView else { answer(.ask, false); return }
        let view = SitePermissionPromptView(prompt: prompt)
        let controller = NSViewController()
        controller.view = view
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = controller
        popover.contentSize = view.preferredSize
        popover.delegate = self
        let id = prompt.id
        view.answer = { [weak self] decision, remember in
            guard let self, self.prompts.removeValue(forKey: id) != nil else { return }
            self.release(id)?.close()
            answer(decision, remember)
        }
        prompts[id] = Prompt(target: prompt.target, allowLoading: true, close: { [weak self] in self?.release(id)?.close() },
                             cancel: { answer(.ask, false) })
        popovers[id] = popover
        let (rect, edge) = SitePanels.anchor(in: window, content: content)
        popover.show(relativeTo: rect, of: content, preferredEdge: edge)
        monitors[id] = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self, weak popover] event in
            let own = popover?.contentViewController?.view.window
            let escape = event.type == .keyDown && event.keyCode == 53 && (event.window === own || event.window === window)
            guard escape || event.type != .keyDown && event.window === window else { return event }
            self?.dismiss(id)
            return escape ? nil : event
        }
    }
    private var popovers: [String: NSPopover] = [:]
    private var monitors: [String: Any] = [:]
    /// Forgets a prompt's popover and event monitor; returns the popover so the caller can close it.
    private func release(_ id: String) -> NSPopover? {
        if let monitor = monitors.removeValue(forKey: id) { NSEvent.removeMonitor(monitor) }
        return popovers.removeValue(forKey: id)
    }
    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover, let id = popovers.first(where: { $0.value === popover })?.key else { return }
        _ = release(id)
        prompts.removeValue(forKey: id)?.cancel()
    }
    /// The open permission prompt's window for a browser window, for the control socket.
    func permissionWindow(for window: WindowID) -> NSWindow? {
        popovers.first { prompts[$0.key]?.target.page.window == window }?.value.contentViewController?.view.window
    }

    func dismiss(_ id: String) {
        guard let prompt = prompts.removeValue(forKey: id) else { return }
        popovers[id] = nil
        prompt.close()
        prompt.cancel()
    }
}

/// The site controls popover's opaque fill (#FAFAFA as measured in P36-a; dark: a neutral popover grey).
@MainActor
private final class PopoverBackground: NSView {
    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.98, alpha: 1)).cgColor
    }
}
