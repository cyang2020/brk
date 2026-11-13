import AppKit
import BrkBase
import BrkDomain
import XCTest

/// What the pointer sweep and the readability check do to a drawn surface (PointerSweepTests, AppSurfaceSweepTests).
@MainActor
enum SurfaceChecks {
    // MARK: Appearance

    /// The Mac's appearance and the Space's colour. A view takes its ink and its surface from the Mac's appearance or from
    /// the Space's scheme. The default Space colour keeps a light scheme in Dark (dark ink on #B6B2AE), so Dark (the user's
    /// Mac) is checked with it and with a dark Space colour (navy, an Arc preset): a view that mixes the two sources shows
    /// up in one of them. (Navy in Light is Arc's own pale blue with white words, below 3:1 by Arc's design.)
    struct Look: CustomStringConvertible {
        let mac: Scheme
        let navy: Bool
        var description: String { navy ? "\(mac) Mac, navy Space" : "\(mac) Mac" }
        /// #2D4468, one of Arc's dark presets (one flat colour, a dark scheme).
        static let navyColor = BrkDomain.RGBA(hex: "#2D4468")
    }
    static let looks = [Look(mac: .light, navy: false), Look(mac: .dark, navy: false), Look(mac: .dark, navy: true)]
    /// For surfaces that follow only the Mac (Settings).
    static let macLooks = [Look(mac: .light, navy: false), Look(mac: .dark, navy: false)]

    /// Runs `body` with the app in Light or Dark, as on a Mac set to it: every window without an appearance of its own
    /// takes it, and colours resolved while views are made are that appearance's (AppKit makes the app's appearance the
    /// current one for each event it handles; a test has no event loop, so it is made current here).
    static func appearing<T>(_ scheme: Scheme, _ body: () throws -> T) throws -> T {
        let app = NSApplication.shared
        let before = app.appearance
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
        app.appearance = appearance
        defer { app.appearance = before }
        return try withoutActuallyEscaping(body) { body in
            var result: Result<T, Error>?
            appearance.performAsCurrentDrawingAppearance { result = Result { try body() } }
            return try result!.get()
        }
    }

    /// A window ordered in (cards and popovers open only over a visible window) but off every screen, where it covers no
    /// other app's window and takes no real click: other agents share this Mac's screen.
    static func window(_ size: CGSize, style: NSWindow.StyleMask = [.titled]) -> NSWindow {
        let window = OffscreenWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.setFrameOrigin(offscreen)
        window.orderFront(nil)
        return window
    }

    static let offscreen = CGPoint(x: -6000, y: -6000)

    /// Runs the main run loop until `done` or `timeout` seconds: a hover card's delay runs as a task, which comes later
    /// than its 0.5 s while other work loads this Mac.
    @discardableResult
    static func wait(_ timeout: Double = 3, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return done()
    }

    /// AppKit moves a titled window that is ordered in onto a screen; this one stays where it is put.
    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    /// A window the app made itself (a Little Arc panel, a popover), which AppKit keeps on a screen: ordered in but
    /// see-through and taking no real click, so it neither shows nor catches another agent's pointer.
    static func conceal(_ window: NSWindow) {
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.orderFront(nil)
    }

    // MARK: Pointer

    /// Sends every pointer-tracking owner under `view` the pointer coming in at the middle of its area and moving there,
    /// a press and a release there (left, then right), and the pointer leaving, as a person's pointer passing over it
    /// would. A menu a press opens closes at once, as Escape would; so does a sheet. Returns how many tracking areas it
    /// reached.
    @discardableResult
    static func sweep(_ view: NSView, in window: NSWindow) -> Int {
        let closing = closingMenus()
        defer { NotificationCenter.default.removeObserver(closing) }
        // Collected first: coming in or a press can add views (a card, a menu) or take them away. Brk's views that take a
        // click but follow no pointer (a dialog's buttons) get the press and release alone.
        var areas: [(NSView, NSTrackingArea)] = [], buttons: [NSView] = []
        func collect(_ view: NSView) {
            guard !view.isHidden else { return }
            view.updateTrackingAreas()
            for area in view.trackingAreas { areas.append((view, area)) }
            if view.trackingAreas.isEmpty, takesPress(view), overrides(view, #selector(NSView.mouseDown(with:))) { buttons.append(view) }
            view.subviews.forEach(collect)
        }
        collect(view)
        func press(_ target: NSView, at point: CGPoint) {
            guard takesPress(target), target.window === window else { return }
            target.mouseDown(with: mouse(.leftMouseDown, at: point, in: window))
            target.mouseUp(with: mouse(.leftMouseUp, at: point, in: window))
            // The right button too, for the menus rows and items have (each closes at once).
            guard target.window === window else { return }
            target.rightMouseDown(with: mouse(.rightMouseDown, at: point, in: window))
            target.rightMouseUp(with: mouse(.rightMouseUp, at: point, in: window))
        }
        var reached = 0
        for (view, area) in areas where view.window === window && view.trackingAreas.contains(area) {
            guard let owner = area.owner as? NSResponder else { continue }
            let rect = area.options.contains(.inVisibleRect) ? view.visibleRect : area.rect
            let point = view.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil)
            let options = area.options
            if options.contains(.mouseEnteredAndExited) { owner.mouseEntered(with: crossing(.mouseEntered, at: point, in: window)) }
            if options.contains(.mouseMoved) { owner.mouseMoved(with: mouse(.mouseMoved, at: point, in: window)) }
            if let target = owner as? NSView { press(target, at: point) }
            if options.contains(.mouseEnteredAndExited) { owner.mouseExited(with: crossing(.mouseExited, at: point, in: window)) }
            reached += 1
        }
        for target in buttons where target.window === window {
            press(target, at: target.convert(CGPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil))
            reached += 1
        }
        if let sheet = window.attachedSheet { window.endSheet(sheet) }
        return reached
    }

    /// Whether `view`'s class implements `selector` itself rather than taking NSView's.
    private static func overrides(_ view: NSView, _ selector: Selector) -> Bool {
        class_getMethodImplementation(object_getClass(view), selector) != class_getMethodImplementation(NSView.self, selector)
    }

    enum Button { case left, right }

    /// A click at `point` (`view`'s coordinates, its middle by default) as a person's lands: the view the window finds
    /// under the point takes the press and the release (whatever is drawn over `view` there takes it instead). A menu it
    /// opens closes at once. `throughApp`: the press goes through the app, so its event monitors see it too (a rename
    /// field's click-away); sending it so does not make the test the active app.
    static func click(_ view: NSView, at point: CGPoint? = nil, _ button: Button = .left, flags: NSEvent.ModifierFlags = [], count: Int = 1,
                      throughApp: Bool = false) {
        guard let window = view.window else { return }
        let closing = closingMenus()
        defer { NotificationCenter.default.removeObserver(closing) }
        let location = view.convert(point ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        let types: [NSEvent.EventType] = button == .left ? [.leftMouseDown, .leftMouseUp] : [.rightMouseDown, .rightMouseUp]
        let events = types.map { type in
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: type == types[0] ? 1 : 0)!
        }
        guard let target = window.contentView?.superview?.hitTest(location) else { return }
        let release = NSEvent.EventTypeMask(rawValue: 1 << events[1].type.rawValue)
        // Straight to the view under the point, as the window hands a click over once it is key (a window that is not key
        // would take the first click only to become key). A text view tracks the press itself until a release comes: that
        // release waits in the queue for it.
        let tracks = target is NSText || target is NSTextField
        if tracks { NSApp.postEvent(events[1], atStart: false) }
        if throughApp { NSApp.sendEvent(events[0]) } else if button == .left { target.mouseDown(with: events[0]) } else { target.rightMouseDown(with: events[0]) }
        if tracks {
            if let up = NSApp.nextEvent(matching: release, until: Date(), inMode: .default, dequeue: true) { window.sendEvent(up) }
            return
        }
        if button == .left { target.mouseUp(with: events[1]) } else { target.rightMouseUp(with: events[1]) }
    }

    /// Until the observer it returns is removed, a menu that opens (a row's menu, a pop-up) closes at once, as Escape would.
    private static func closingMenus() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            nonisolated(unsafe) let menu = note.object as? NSMenu
            RunLoop.main.perform(inModes: [.eventTracking, .common]) { MainActor.assumeIsolated { menu?.cancelTrackingWithoutAnimation() } }
        }
    }

    /// Brk's own views take the press. AppKit's controls, text and scroll views run a tracking loop on a press that
    /// waits for a real release, and SwiftUI's are not views a press is sent to.
    private static func takesPress(_ view: NSView) -> Bool {
        guard String(reflecting: type(of: view)).hasPrefix("Brk") else { return false }
        return !(view is NSControl || view is NSText || view is NSScrollView || view is NSClipView || view is NSScroller)
    }

    private static func crossing(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) -> NSEvent {
        NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
    }

    private static func mouse(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: type == .mouseMoved ? 0 : 1,
                           pressure: type == .leftMouseDown || type == .rightMouseDown ? 1 : 0)!
    }

    // MARK: Readability

    /// Every visible label (or field's typed text) under `root` whose text does not read on what is drawn behind it: WCAG
    /// contrast of 3 or less between its ink and the opaque surface under its middle. The surface is `base` (what the
    /// window itself shows there: the theme's colour, a popover's fill) with every fill drawn before the label laid over
    /// it in drawing order: layer backgrounds and gradients, the views' own backgrounds, a material over the desktop as
    /// its appearance's window colour. A label an opaque view drawn after it covers is not seen, and is skipped.
    ///
    /// A hint Arc draws at its placeholder strength (ink at 40% or less: "+ New Tab", "Switch to Tab", the + menu's
    /// shortcuts) is meant to be faint and is held to 1.5:1, which text the colour of its background still fails.
    /// `exempt` names labels Arc itself draws below 3:1 (with the capture that shows it) or a custom control that is off;
    /// they stay as they are.
    static func unreadable(in root: NSView, base: NSColor, _ name: String, exempt: (NSTextField) -> Bool = { _ in false }) -> [String] {
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()   // views that colour their layer when drawn (`updateLayer`)
        // Drawing order, with each view's frame in the window and its alpha times its ancestors', worked out once.
        var order: [(view: NSView, frame: CGRect, alpha: Double)] = []
        func walk(_ view: NSView, _ alpha: Double) {
            guard !view.isHidden, view.alphaValue > 0.01 else { return }
            let shown = alpha * Double(view.alphaValue)
            order.append((view, view.convert(view.bounds, to: nil), shown))
            for child in view.subviews { walk(child, shown) }
        }
        walk(root, 1)
        let appearance = root.effectiveAppearance
        var problems: [String] = []
        for (index, entry) in order.enumerated() {
            // A field's typed text too (a rename field's name): it is drawn on the field's own fill, made like a label's.
            guard let label = entry.view as? NSTextField, label.window != nil, !exempt(label), !insideDisabledControl(label, under: root) else { continue }
            let text = label.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, label.visibleRect.width >= 2, label.visibleRect.height >= 2, entry.alpha > 0.05 else { continue }
            let alpha = entry.alpha
            let middle = CGPoint(x: label.bounds.midX, y: label.bounds.midY)
            let spot = label.convert(middle, to: nil)
            if order[(index + 1)...].contains(where: { $0.frame.contains(spot) && !$0.view.isDescendant(of: label) && covers($0.view, alpha: $0.alpha) }) { continue }
            var surface = rgba(base, in: appearance)
            for below in order[..<index] where below.frame.contains(spot) {
                for fill in fills(of: below.view, at: label, middle) { surface = over(fill, alpha: below.alpha, on: surface) }
            }
            for fill in fills(of: label, at: label, middle) { surface = over(fill, alpha: alpha, on: surface) }
            let ink = rgba(inkColor(label), in: label.effectiveAppearance)
            let ratio = contrast(ink, alpha: alpha, on: surface)
            if ratio <= (ink.a * alpha < 0.405 ? 1.5 : 3) {
                problems.append(String(format: "%@: \"%@\" (%@) reads at %.2f:1, ink %@ on %@", name, text, path(label, under: root), ratio,
                                       hex(ink, alpha: ink.a * alpha), hex(surface, alpha: 1)))
            }
        }
        return problems
    }

    /// Whether `view` or one of its ancestors has an accessibility identifier starting with `prefix`.
    static func inside(_ view: NSView, prefix: String) -> Bool {
        var current: NSView? = view
        while let v = current {
            if v.accessibilityIdentifier().hasPrefix(prefix) { return true }
            current = v.superview
        }
        return false
    }

    /// A control that is off draws its words faint on purpose (WCAG leaves inactive controls out).
    private static func insideDisabledControl(_ view: NSView, under root: NSView) -> Bool {
        var current: NSView? = view
        while let v = current, v !== root.superview {
            if let control = v as? NSControl, !control.isEnabled { return true }
            current = v.superview
        }
        return false
    }

    /// The text's colour: the attributed string's own, else the field's.
    private static func inkColor(_ label: NSTextField) -> NSColor {
        let string = label.attributedStringValue
        if string.length > 0, let color = string.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor { return color }
        return label.textColor ?? .labelColor
    }

    /// The fills `view` draws under its subviews where the label's middle is (inside `view`), in drawing order, before its
    /// own alpha.
    private static func fills(of view: NSView, at label: NSView, _ middle: CGPoint) -> [Shade] {
        let appearance = view.effectiveAppearance
        var fills: [Shade] = []
        // A material over what is behind the window is its appearance's window colour there; one within the window blurs what
        // lies under it, which the fills before it already are.
        if (view as? NSVisualEffectView)?.blendingMode == .behindWindow { fills.append(rgba(.windowBackgroundColor, in: appearance)) }
        if let color = view.layer?.backgroundColor, let ns = NSColor(cgColor: color) { fills.append(rgba(ns, in: appearance)) }
        if let gradient = view.layer as? CAGradientLayer, let mean = mean(of: gradient, in: appearance) { fills.append(mean) }
        if let field = view as? NSTextField, field.drawsBackground, let color = field.backgroundColor { fills.append(rgba(color, in: appearance)) }
        if let scroll = view as? NSScrollView, scroll.drawsBackground { fills.append(rgba(scroll.backgroundColor, in: appearance)) }
        if let clip = view as? NSClipView, clip.drawsBackground { fills.append(rgba(clip.backgroundColor, in: appearance)) }
        if let box = view as? NSBox, box.boxType == .custom, !box.isTransparent { fills.append(rgba(box.fillColor, in: appearance)) }
        // Layers a view adds of its own (a highlight, a capsule, a card's gradient), not its subviews'. The label's middle
        // in the view's layer, through the view: a label drawn into its control's layer has none of its own.
        if let layer = view.layer {
            let point = view.convert(middle, from: label)
            let owned = Set(view.subviews.compactMap { $0.layer.map(ObjectIdentifier.init) })
            func visit(_ sublayer: CALayer) {
                guard !owned.contains(ObjectIdentifier(sublayer)), !sublayer.isHidden, sublayer.opacity > 0.01 else { return }
                if sublayer.bounds.contains(sublayer.convert(point, from: layer)) {
                    let own = sublayer.backgroundColor.flatMap { NSColor(cgColor: $0) }.map { rgba($0, in: appearance) }
                    for var fill in [own, (sublayer as? CAGradientLayer).flatMap { mean(of: $0, in: appearance) }].compactMap({ $0 }) {
                        fill.a *= Double(sublayer.opacity)
                        fills.append(fill)
                    }
                }
                sublayer.sublayers?.forEach(visit)
            }
            layer.sublayers?.forEach(visit)
        }
        return fills
    }

    /// A gradient's colours averaged: a theme's stops, a card's shade.
    private static func mean(of gradient: CAGradientLayer, in appearance: NSAppearance) -> Shade? {
        let colors = (gradient.colors as? [CGColor] ?? []).compactMap { NSColor(cgColor: $0).map { rgba($0, in: appearance) } }
        guard !colors.isEmpty else { return nil }
        let n = Double(colors.count)
        func sum(_ part: (Shade) -> Double) -> Double { colors.map(part).reduce(0, +) / n }
        return Shade(r: sum { $0.r }, g: sum { $0.g }, b: sum { $0.b }, a: sum { $0.a })
    }

    /// Whether `view`, drawn after the label over its middle at `alpha` (its own times its ancestors'), hides it.
    private static func covers(_ view: NSView, alpha: Double) -> Bool {
        guard alpha > 0.95 else { return false }
        if (view as? NSVisualEffectView)?.blendingMode == .behindWindow { return true }
        guard let color = view.layer?.backgroundColor else { return false }
        return color.alpha > 0.95
    }

    private static func path(_ view: NSView, under root: NSView) -> String {
        var names: [String] = []
        var current: NSView? = view
        while let v = current, v !== root, names.count < 4 {
            let id = v.accessibilityIdentifier()
            names.append(id.isEmpty ? String(describing: type(of: v)) : id)
            current = v.superview
        }
        return names.reversed().joined(separator: " > ")
    }

    // MARK: Colour

    struct Shade { var r, g, b, a: Double }

    static func rgba(_ color: NSColor, in appearance: NSAppearance) -> Shade {
        var result = Shade(r: 0, g: 0, b: 0, a: 1)
        appearance.performAsCurrentDrawingAppearance {
            guard let c = color.usingColorSpace(.sRGB) else { return }
            result = Shade(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent)
        }
        return result
    }

    private static func over(_ top: Shade, alpha: Double, on under: Shade) -> Shade {
        let a = top.a * alpha
        return Shade(r: top.r * a + under.r * (1 - a), g: top.g * a + under.g * (1 - a), b: top.b * a + under.b * (1 - a), a: 1)
    }

    /// WCAG contrast of `ink` (at its alpha times `alpha`) laid over the opaque `surface`.
    static func contrast(_ ink: Shade, alpha: Double = 1, on surface: Shade) -> Double {
        let top = over(ink, alpha: alpha, on: surface)
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        func luminance(_ c: Shade) -> Double { 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b) }
        let a = luminance(top), b = luminance(surface)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func hex(_ c: Shade, alpha: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.r), byte(c.g), byte(c.b)) + (alpha < 0.999 ? String(format: "@%.2f", alpha) : "")
    }
}
