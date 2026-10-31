import AppKit
import BrkBase

/// In-process input for the control socket: key and mouse events handed to `NSApp.sendEvent`, so they take the
/// path a real event takes (menu key equivalents while a native view has focus, the first responder's `keyDown`,
/// Chromium's views and CEF's key handler while a page has focus; spike unknown 3). No Accessibility permission:
/// nothing is posted to the window server.
///
/// Key events are built the way the system builds them: a `CGEvent` from the physical key code (`Key`, US positions)
/// and modifier flags, whose characters come from the current keyboard layout, wrapped by `NSEvent(cgEvent:)`. A
/// synthetic `NSEvent.keyEvent` does not match menu items such as Ctrl+Shift+= or Cmd+Shift+K the way a real press
/// does (verified on the stub shell: no match with "+" or "K"; the CGEvent-backed event matches like a keyboard).
/// Such events carry no window, so when the app has no key window (inactive, or the display is locked) they are
/// delivered as AppKit would to the target window: menu key equivalents first, then the window.
@MainActor
final class EventInjector {
    private var eventNumber = 0
    private let source = CGEventSource(stateID: .privateState)
    /// Tracking areas the injected pointer is inside, so the next `hover` can send their exits.
    private var hovered: [ObjectIdentifier: NSTrackingArea] = [:]
    private weak var pointerTarget: NSView?
    private weak var pointerWindow: NSWindow?

    /// "cmd", "ctrl+shift", "alt", "" -> modifiers; nil for an unknown name.
    static func modifiers(_ text: String) -> Modifiers? {
        var out = Modifiers()
        for part in text.lowercased().split(separator: "+").map(String.init) where !part.isEmpty {
            switch part {
            case "cmd", "command": out.insert(.command)
            case "shift": out.insert(.shift)
            case "alt", "option", "opt": out.insert(.option)
            case "ctrl", "control": out.insert(.control)
            default: return nil
            }
        }
        return out
    }

    // MARK: Keys

    func press(_ chord: KeyChord, in window: NSWindow) throws {
        try sendKey(code: chord.key.code, flags: chord.modifiers, text: nil, in: window)
    }

    /// Modifier down (one flagsChanged per modifier, as a keyboard sends them), `times` presses, modifiers up.
    func hold(_ held: Modifiers, chord: KeyChord, times: Int, in window: NSWindow) throws {
        let order: [(Modifiers, UInt16)] = [(.control, 59), (.option, 58), (.shift, 56), (.command, 55)]
        var down = Modifiers()
        for (modifier, code) in order where held.contains(modifier) {
            down.insert(modifier)
            try deliver(try event(code: code, down: true, flags: down, type: .flagsChanged), to: window)
        }
        for _ in 0..<times { try sendKey(code: chord.key.code, flags: down.union(chord.modifiers), text: nil, in: window) }
        for (modifier, code) in order.reversed() where down.contains(modifier) {
            down.remove(modifier)
            try deliver(try event(code: code, down: false, flags: down, type: .flagsChanged), to: window)
        }
    }

    /// One key-down and key-up per character, into whatever has keyboard focus. The key code is the character's US
    /// position (0 when it has none) and the event's text is the character itself, whatever the layout.
    func type(_ text: String, in window: NSWindow) throws {
        for character in text {
            let (code, shift) = Self.usKey(for: character)
            try sendKey(code: code, flags: shift ? .shift : [], text: String(character), in: window)
        }
    }

    private func sendKey(code: UInt16, flags: Modifiers, text: String?, in window: NSWindow) throws {
        try deliver(try event(code: code, down: true, flags: flags, text: text), to: window)
        try deliver(try event(code: code, down: false, flags: flags, text: text), to: window)
    }

    private func event(code: UInt16, down: Bool, flags: Modifiers, text: String? = nil, type: CGEventType? = nil) throws -> NSEvent {
        guard let cg = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { throw InjectionError("CGEvent for key \(code)") }
        cg.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
        // A CGEvent from a private source has timestamp 0; the press id is minted from the timestamp, so every press
        // would look like the same press to the duplicate guard. Real events carry uptime in nanoseconds.
        cg.timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        if let type { cg.type = type }
        if let text {
            let units = Array(text.utf16)
            cg.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        }
        guard let event = NSEvent(cgEvent: cg) else { throw InjectionError("NSEvent from CGEvent for key \(code)") }
        return event
    }

    /// Posts the event at the head of the app's queue and dequeues it, as the run loop does, so `NSApp.currentEvent`
    /// is this event while it is handled (the menu target reads it to mint the press id), then dispatches it. Without
    /// a key window (inactive app, locked display) it takes `NSApp.sendEvent`'s order itself. With a page focused, a
    /// key window hands every Cmd chord to Chromium's view, which claims it before the menu (spike unknown 3) but
    /// only while its window is key; the view's `keyDown` takes the same path (CEF's key handler before and after the
    /// page), so the event goes straight to the window and the menu never sees it. With a native view focused, a
    /// key-down is offered as a key equivalent to the window's views, then to the menu, then to the first responder.
    private func deliver(_ event: NSEvent, to window: NSWindow) throws {
        var current = Self.dequeue(event)
        var owner: NSWindow? = window
        while let candidate = owner, !(candidate is NSSavePanel) { owner = candidate.sheetParent }
        if owner is NSSavePanel, current.type == .keyDown || current.type == .keyUp {
            // Give remote file views their host window ID; CGEvent-backed events have no window.
            guard let targeted = NSEvent.keyEvent(with: current.type, location: .zero, modifierFlags: current.modifierFlags,
                timestamp: current.timestamp, windowNumber: window.windowNumber, context: nil,
                characters: current.characters ?? "", charactersIgnoringModifiers: current.charactersIgnoringModifiers ?? "",
                isARepeat: current.isARepeat, keyCode: current.keyCode) else { throw InjectionError("native file-panel event") }
            current = targeted
        }
        if NSApp.keyWindow === window {
            NSApp.sendEvent(current)
            return
        }
        if current.type == .keyDown, ViewTree.page(containing: window.firstResponder) == nil {
            if (window.contentView?.superview ?? window.contentView)?.performKeyEquivalent(with: current) == true { return }
            if (window as? any HostWindow)?.routeKeyEquivalent(current) == true { return }
            if performResponderKeyEquivalent(current, in: window, menu: NSApp.mainMenu) { return }
            if NSApp.mainMenu?.performKeyEquivalent(with: current) == true { return }
        }
        window.sendEvent(current)
    }

    /// AppKit resolves nil-target menu actions through the key window. In an inactive app, use the window the
    /// control operation actually targets so Select All, Copy, and other editing actions reach its editor.
    private func performResponderKeyEquivalent(_ event: NSEvent, in window: NSWindow, menu: NSMenu?) -> Bool {
        guard let menu, let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift, .function])
        for item in menu.items {
            if performResponderKeyEquivalent(event, in: window, menu: item.submenu) { return true }
            guard item.target == nil, let action = item.action, !item.keyEquivalent.isEmpty,
                  item.keyEquivalent.lowercased() == characters else { continue }
            var required = item.keyEquivalentModifierMask.intersection([.command, .control, .option, .shift, .function])
            if item.keyEquivalent != item.keyEquivalent.lowercased() { required.insert(.shift) }
            if required == modifiers, window.firstResponder?.tryToPerform(action, with: item) == true { return true }
        }
        return false
    }

    private static func dequeue(_ event: NSEvent) -> NSEvent {
        NSApp.postEvent(event, atStart: true)
        return NSApp.nextEvent(matching: NSEvent.EventTypeMask(type: event.type), until: Date.distantPast, inMode: .default, dequeue: true) ?? event
    }

    private func flags(_ modifiers: Modifiers) -> NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers.rawValue) }

    // MARK: Mouse

    func pointer(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) throws {
        if type == .leftMouseDown {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            pointerWindow = window
            pointerTarget = window.contentView?.superview?.hitTest(point) ?? window.contentView?.hitTest(point)
        }
        guard pointerWindow === window, let target = pointerTarget else { throw InjectionError("pointer sequence has no live down target") }
        let event = Self.dequeue(try mouse(type, at: point, modifiers: [], clickCount: 1, in: window))
        if window.isKeyWindow { NSApp.sendEvent(event) }
        else {
            switch type {
            case .leftMouseDown: target.mouseDown(with: event)
            case .leftMouseDragged: target.mouseDragged(with: event)
            case .leftMouseUp: target.mouseUp(with: event)
            default: break
            }
        }
        if type == .leftMouseUp { pointerTarget = nil; pointerWindow = nil }
    }

    /// Left click at a window point (AppKit window coordinates). The mouse-up is queued before the mouse-down is
    /// handled, so a control that runs its own tracking loop inside `mouseDown` (NSButton) finds it; if nothing
    /// consumed it, it is dequeued and handled here, so the click is complete when this returns.
    ///
    /// In a key window the events go through `NSApp.sendEvent`. A window that is not key (inactive app, locked
    /// display) would take the press as a first click that only activates it, so the events go to the view AppKit's
    /// hit test picks, the way a key window delivers them: a control through `NSWindow.sendEvent` (controls accept
    /// the first click and run their tracking there; called directly, NSButton does not track), any other view by a
    /// direct `mouseDown`/`mouseUp` (AppKit forwards what the view does not handle to the view below, as it does for
    /// a real click).
    func click(at point: CGPoint, modifiers: Modifiers, count: Int, in window: NSWindow) throws {
        if !window.isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        let key = window.isKeyWindow
        guard let target = window.contentView?.superview?.hitTest(point) ?? window.contentView?.hitTest(point) else {
            throw InjectionError("nothing under \(point) in window \(window.windowNumber)")
        }
        func handle(_ event: NSEvent) {
            if key { NSApp.sendEvent(event) }
            else if target is NSControl { window.sendEvent(event) }
            else if event.type == .leftMouseDown {
                // What a key window's sendEvent does first: report the click's modifiers (a Shift+click opens a Peek).
                _ = (window as? any HostWindow)?.hostEvent(event)
                // Direct mouseDown delivery skips NSWindow's responder handoff. Preserve that handoff for
                // a page click even when this injected window cannot become key on the shared display.
                if ViewTree.page(containing: target) != nil {
                    var candidate: NSView? = target
                    while let view = candidate {
                        if view.acceptsFirstResponder, window.makeFirstResponder(view) { break }
                        candidate = view.superview
                    }
                    print("[control] page-click target=\(NSStringFromClass(Swift.type(of: target))) responder=\(window.firstResponder.map { NSStringFromClass(Swift.type(of: $0)) } ?? "nil")")
                }
                target.mouseDown(with: event)
            }
            else { target.mouseUp(with: event) }
        }
        for n in 1...count {
            let down = Self.dequeue(try mouse(.leftMouseDown, at: point, modifiers: modifiers, clickCount: n, in: window))
            NSApp.postEvent(try mouse(.leftMouseUp, at: point, modifiers: modifiers, clickCount: n, in: window), atStart: false)
            handle(down)
            if let up = NSApp.nextEvent(matching: .leftMouseUp, until: Date.distantPast, inMode: .default, dequeue: true) { handle(up) }
        }
    }

    func rightClick(at point: CGPoint, in window: NSWindow) throws {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard let target = window.contentView?.superview?.hitTest(point) ?? window.contentView?.hitTest(point) else {
            throw InjectionError("nothing under context-menu point")
        }
        let down = Self.dequeue(try mouse(.rightMouseDown, at: point, modifiers: [], clickCount: 1, in: window))
        NSApp.postEvent(try mouse(.rightMouseUp, at: point, modifiers: [], clickCount: 1, in: window), atStart: false)
        if window.isKeyWindow { NSApp.sendEvent(down) } else { target.rightMouseDown(with: down) }
        if let up = NSApp.nextEvent(matching: .rightMouseUp, until: Date.distantPast, inMode: .default, dequeue: true) {
            if window.isKeyWindow { NSApp.sendEvent(up) } else { target.rightMouseUp(with: up) }
        }
    }

    /// Moves the injected pointer: a mouse-moved event for the window, then what AppKit's tracking would send for the
    /// new position (exits, entries, moves to the owners of the tracking areas that contain it), because synthetic
    /// events do not drive the window server's tracking-area bookkeeping.
    func hover(at point: CGPoint, in window: NSWindow) {
        if let moved = try? mouse(.mouseMoved, at: point, modifiers: [], clickCount: 0, in: window) { NSApp.sendEvent(moved) }
        guard let top = window.contentView?.superview ?? window.contentView else { return }
        var inside: [ObjectIdentifier: NSTrackingArea] = [:]
        ViewTree.walk(top) { view in
            guard !view.isHiddenOrHasHiddenAncestor else { return }
            for area in view.trackingAreas {
                let rect = area.options.contains(.inVisibleRect) ? view.visibleRect : area.rect
                if view.convert(rect, to: nil).contains(point) { inside[ObjectIdentifier(area)] = area }
            }
        }
        for (id, area) in hovered where inside[id] == nil && area.options.contains(.mouseEnteredAndExited) {
            if let event = enterExit(.mouseExited, at: point, in: window) { (area.owner as? NSResponder)?.mouseExited(with: event) }
        }
        for (id, area) in inside where hovered[id] == nil && area.options.contains(.mouseEnteredAndExited) {
            if let event = enterExit(.mouseEntered, at: point, in: window) { (area.owner as? NSResponder)?.mouseEntered(with: event) }
        }
        for area in inside.values where area.options.contains(.mouseMoved) {
            if let event = try? mouse(.mouseMoved, at: point, modifiers: [], clickCount: 0, in: window) {
                (area.owner as? NSResponder)?.mouseMoved(with: event)
            }
        }
        hovered = inside
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, modifiers: Modifiers, clickCount: Int, in window: NSWindow) throws -> NSEvent {
        eventNumber += 1
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags(modifiers),
                                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                             context: nil, eventNumber: eventNumber, clickCount: clickCount,
                                             pressure: type == .leftMouseDown || type == .rightMouseDown ? 1 : 0) else { throw InjectionError("could not build a mouse event") }
        return event
    }

    private func enterExit(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) -> NSEvent? {
        eventNumber += 1
        return NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber, trackingNumber: 0,
                                      userData: nil)
    }

    // MARK: US layout

    static func usKey(for character: Character) -> (code: UInt16, shift: Bool) {
        if let code = unshiftedCodes[character] { return (code, false) }
        if character.isUppercase, let lower = character.lowercased().first, let code = unshiftedCodes[lower] { return (code, true) }
        if let base = shifted.first(where: { $0.value == character })?.key, let code = unshiftedCodes[base] { return (code, true) }
        return (0, false)
    }

    private static let unshiftedCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14,
        "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27,
        "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "\r": 36, "l": 37, "j": 38, "'": 39, "k": 40,
        ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "\t": 48, " ": 49, "`": 50,
    ]

    private static let shifted: [Character: Character] = [
        "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")", "-": "_", "=": "+",
        "[": "{", "]": "}", "\\": "|", ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?", "`": "~",
    ]
}

struct InjectionError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
