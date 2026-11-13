import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

// Owner: W3. The two building blocks every sidebar control shares: hover/press state from a tracking area, and a
// glyph button with Arc's translucent hover fill. Hover and press are view state, never app state.

/// A flipped, layer-backed view that knows whether the pointer is over it and whether it is pressed.
@MainActor
class HoverView: NSView {
    private(set) var isHovered = false
    var isPressed = false { didSet { if isPressed != oldValue { stateChanged() } } }
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Since macOS 14 views do not clip by default, and an unclipped view's `visibleRect` (which the
        // `.inVisibleRect` tracking area follows) reaches past its bounds: every row would count as hovered.
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    /// A click on a row, tile or button acts at once, even in a window that is not key yet (as Arc's sidebar does).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Labels, icons and fills inside never take the pointer: a hit on them is a hit on the nearest interactive
    /// view (this one, a nested button, or the rename field). A view faded out to nothing takes no click either, as a
    /// hidden one: AppKit's hit test ignores alpha, so a row's ×, Tidy or the pill's copy link while not showing acted
    /// on the click meant for the row or pill under it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard alphaValue > 0, let hit = super.hitTest(point) else { return nil }
        return hit is HoverView || hit is RenameField || hit.superview is RenameField ? hit : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if tracking == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
            addTrackingArea(area)
            tracking = area
        }
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    override func viewDidHide() {
        super.viewDidHide()
        setHovered(false)
        isPressed = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setHovered(false); isPressed = false }
    }

    func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        stateChanged()
    }

    /// Hover or press changed. Subclasses redraw their fill.
    func stateChanged() {}

    /// `event`'s location in this view.
    func local(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }
}

extension NSView {
    /// A window-base location (`NSEvent.locationInWindow`) in the window's content view, top-left origin: the space
    /// `WindowFrames` and `Command`'s points use.
    @MainActor
    func rootPoint(fromWindow location: CGPoint) -> CGPoint {
        guard let root = window?.contentView else { return location }
        return root.convert(location, from: nil)
    }

    /// A point of this view in the window's content view, top-left origin.
    @MainActor
    func rootPoint(of point: CGPoint) -> CGPoint {
        guard let root = window?.contentView else { return point }
        return root.convert(point, from: self)
    }
}

/// How a toolbar glyph moves while its button is held (Arc's `SidebarIcon`, `ArrowIcon`, `ReloadIcon`).
enum PressMotion: Equatable {
    /// Scales about its centre (the sidebar toggle: 0.95).
    case scale(Double)
    /// Moves sideways by this many points (back -3, forward +3).
    case shift(Double)
    /// Turns clockwise by this many degrees (reload: 90).
    case turn(Double)
}

/// A glyph with a rounded hover fill. `action` runs on mouse-up inside, with the modifier keys held.
@MainActor
final class GlyphButton: HoverView {
    private let icon = NSImageView()
    var action: ((NSEvent.ModifierFlags) -> Void)?
    var isEnabled = true
    private var glyph: Glyph?
    private var glyphSize = 0.0
    private var palette: Palette?
    private var radius = 0.0
    /// Fill when hovered; pressed uses the pressed token.
    private var hoverFill: RGBA?
    /// Fill that stays while the button's popover is open.
    var latchedFill: RGBA? { didSet { if latchedFill != oldValue { stateChanged() } } }
    /// Arc's own tooltip while the pointer is on the button (`ArcTooltip`), for the controls that have it.
    var tip: String?
    private var symbolName: String?
    /// How the glyph moves while the button is held (Arc's toolbar icons read `isArcButtonPressed`); nil keeps it
    /// still. With a motion the glyph is drawn by `motion` instead of the image view.
    var pressMotion: PressMotion? { didSet { if pressMotion != oldValue { motionChanged() } } }
    /// A glyph change (reload ↔ stop) shrinks the old one away and grows the new one in, as Arc's `ReloadIcon`.
    var springsGlyphChange = false
    private var motion: CALayer?
    private var moreIcon: MoreMenuIconLayer?
    var menuOpen = false { didSet { if menuOpen != oldValue { stateChanged() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.imageScaling = .scaleNone
        addSubview(icon)
        layer?.cornerCurve = .continuous
    }

    /// A drawn, already tinted picture in place of the glyph's symbol (the dock's Library box).
    var image: NSImage? {
        get { icon.image }
        set { icon.image = newValue }
    }

    func render(_ glyph: Glyph, size: Double, weight: NSFont.Weight = .medium, palette: Palette, tint: NSColor? = nil, radius: Double, hoverFill: RGBA?) {
        if self.glyph != glyph || glyphSize != size {
            let swapped = springsGlyphChange && self.glyph != nil && self.glyph != glyph && glyphSize == size
            if swapped { springAway() }
            icon.image = glyph.image(size: size, weight: weight)
            refreshMotionGlyph()
            if swapped { springIn(entering: glyph) }
        }
        self.glyph = glyph
        glyphSize = size
        if glyph == .more, moreIcon == nil {
            let more = MoreMenuIconLayer()
            layer?.addSublayer(more.layer)
            moreIcon = more
        }
        moreIcon?.layer.isHidden = glyph != .more
        icon.alphaValue = glyph == .more || pressMotion != nil ? 0 : 1
        apply(palette: palette, tint: tint, radius: radius, hoverFill: hoverFill)
    }

    /// The same with a symbol picked by name (the mini player's speaker changes with the volume).
    func renderSymbol(_ name: String, size: Double, weight: NSFont.Weight = .medium, palette: Palette, tint: NSColor? = nil, radius: Double, hoverFill: RGBA?) {
        if symbolName != name || glyphSize != size { icon.image = symbolImage(name, size: size, weight: weight) }
        symbolName = name
        glyphSize = size
        apply(palette: palette, tint: tint, radius: radius, hoverFill: hoverFill)
    }

    private func apply(palette: Palette, tint: NSColor?, radius: Double, hoverFill: RGBA?) {
        self.palette = palette
        self.radius = radius
        self.hoverFill = hoverFill
        icon.contentTintColor = tint ?? (isEnabled ? palette.ink.secondary : palette.ink.placeholder)
        stateChanged()
    }

    // MARK: Press motion

    private func motionChanged() {
        icon.alphaValue = pressMotion == nil ? 1 : 0
        if pressMotion == nil { motion?.removeFromSuperlayer(); motion = nil; return }
        if motion == nil {
            let host = CALayer()
            host.mask = CALayer()
            layer?.addSublayer(host)
            motion = host
        }
        refreshMotionGlyph()
    }

    /// The glyph as a mask over a layer filled with the ink, so the ink can change smoothly.
    private func refreshMotionGlyph() {
        guard let motion, let mask = motion.mask else { return }
        let scale = window?.backingScaleFactor ?? 2
        let size = icon.image?.size ?? .zero
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        motion.bounds = CGRect(origin: .zero, size: size)
        motion.position = CGPoint(x: bounds.midX, y: bounds.midY)
        mask.frame = motion.bounds
        mask.contentsScale = scale
        mask.contents = icon.image?.layerContents(forContentsScale: scale)
        CATransaction.commit()
    }

    private func pressSpring(_ keyPath: String) -> CASpringAnimation {
        let k = Draw.toolbarPressSpring.value
        let m = MotionSpring(response: k[0], dampingRatio: k[1])
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = m.stiffness
        animation.damping = m.damping
        animation.duration = animation.settlingDuration
        return animation
    }

    /// Moves the glyph to its held or resting place and ink on Arc's press spring.
    private func applyMotion(tint: NSColor) {
        guard let motion, let pressMotion else { return }
        let held = isPressed && isEnabled
        var target = CATransform3DIdentity
        switch pressMotion {
        case .scale(let s): if held { target = CATransform3DMakeScale(s, s, 1) }
        case .shift(let dx): if held { target = CATransform3DMakeTranslation(dx, 0, 0) }
        case .turn(let degrees): if held { target = CATransform3DMakeRotation(degrees * .pi / 180, 0, 0, 1) }
        }
        let ink = held ? (palette?.scheme == .dark ? NSColor(white: 1, alpha: Draw.toolbarPressedInk.value) : NSColor(white: 0, alpha: Draw.toolbarPressedInk.value)) : tint
        let animate = window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fromTransform = (motion.presentation() ?? motion).transform
        let fromInk = (motion.presentation() ?? motion).backgroundColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        motion.transform = target
        motion.backgroundColor = ink.cgColor
        CATransaction.commit()
        guard animate else { return }
        if !CATransform3DEqualToTransform(fromTransform, target) {
            let spring = pressSpring("transform")
            spring.fromValue = NSValue(caTransform3D: fromTransform)
            spring.toValue = NSValue(caTransform3D: target)
            motion.add(spring, forKey: "press-transform")
        }
        if let fromInk, fromInk != ink.cgColor {
            let spring = pressSpring("backgroundColor")
            spring.fromValue = fromInk
            spring.toValue = ink.cgColor
            motion.add(spring, forKey: "press-ink")
        }
    }

    /// The old glyph shrinks to 0.7 and fades (Arc's `ReloadIcon`: spring 0.2 / 0.6, the stop sign delayed 0.1 s,
    /// the arrow 0.2 s).
    private func springAway() {
        guard let motion, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let old = CALayer()
        old.bounds = motion.bounds
        old.position = motion.position
        old.backgroundColor = motion.backgroundColor
        let mask = CALayer()
        mask.frame = old.bounds
        mask.contentsScale = motion.mask?.contentsScale ?? 2
        mask.contents = motion.mask?.contents
        old.mask = mask
        layer?.addSublayer(old)
        let swap = Draw.toolbarGlyphSwap.value
        CATransaction.begin()
        CATransaction.setCompletionBlock { old.removeFromSuperlayer() }
        CATransaction.setDisableActions(true)
        old.opacity = 0
        old.transform = CATransform3DMakeScale(swap[0], swap[0], 1)
        for (key, from, to) in [("opacity", 1.0, 0.0), ("transform.scale", 1.0, swap[0])] {
            let spring = pressSpring(key)
            spring.fromValue = from
            spring.toValue = to
            old.add(spring, forKey: key)
        }
        CATransaction.commit()
    }

    private func springIn(entering glyph: Glyph) {
        guard let motion, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let swap = Draw.toolbarGlyphSwap.value
        let delay = glyph == .stop ? swap[1] : swap[2]
        for (key, from) in [("opacity", 0.0), ("transform.scale", swap[0])] {
            let spring = pressSpring(key)
            spring.fromValue = from
            spring.toValue = 1.0
            spring.beginTime = CACurrentMediaTime() + delay
            spring.fillMode = .backwards
            motion.add(spring, forKey: "swap-" + key)
        }
    }

    /// The pointer came onto the button or left it (the Library button's picture plays its motion on both).
    var hoverChanged: ((Bool) -> Void)?

    override func setHovered(_ hovered: Bool) {
        let was = isHovered
        super.setHovered(hovered)
        if tip != nil { ArcTooltip.pointer(on: self, text: hovered && isEnabled ? tip : nil) }
        if isHovered != was { hoverChanged?(isHovered) }
    }

    override func layout() {
        super.layout()
        icon.frame = bounds
        refreshMotionGlyph()
        moreIcon?.layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshMotionGlyph()
    }

    override func stateChanged() {
        guard let palette else { return }
        layer?.cornerRadius = radius
        let fill: RGBA? = !isEnabled ? nil : isPressed ? palette.tokens.tabPressed : latchedFill ?? (isHovered ? hoverFill : nil)
        layer?.backgroundColor = fill.map { palette.color($0).cgColor }
        if let tint = icon.contentTintColor {
            applyMotion(tint: tint)
            moreIcon?.show(open: menuOpen, size: glyphSize, tint: tint,
                           animated: window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if tip != nil { ArcTooltip.pointer(on: self, text: nil) }
        isPressed = true
    }

    /// Only after a press that started here: the site controls keep the press on the site button that closes them,
    /// and AppKit still hands the release to the button, which opened them again.
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(local(event)), pressed = isPressed
        isPressed = false
        if isEnabled, pressed, inside { action?(event.modifierFlags) }
    }
}

/// The in-place title editor of a tab row, a folder row or a favorite tile (identified `rename-field`). Return commits,
/// Escape cancels, losing focus or a click outside the field commits: `onFinish` runs once, with the typed title or
/// nil for a cancel. `retire` drops the field without either (the rename ended elsewhere).
@MainActor
final class RenameField: NSTextField, NSTextFieldDelegate {
    /// Set once the rename has been committed, cancelled or retired, so losing focus afterwards sends nothing.
    private(set) var finished = false
    private let onFinish: (String?) -> Void
    /// Rows, tiles and buttons never take first responder, so a click on one would not end the edit on its own.
    private var outsideClicks: Any?

    init(text: String, font: NSFont?, color: NSColor, onFinish: @escaping (String?) -> Void) {
        self.onFinish = onFinish
        super.init(frame: .zero)
        identify(.renameField)
        self.font = font
        textColor = color
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        lineBreakMode = .byClipping
        usesSingleLineMode = true
        cell?.isScrollable = true
        delegate = self
        stringValue = text
        outsideClicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.clicked(event) }
            return event
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Keyboard focus with the title selected. An editor that already has focus keeps it as it is: making the field
    /// first responder again would make its field editor resign, which ends (commits) the edit.
    func focus(in window: NSWindow) -> Bool {
        guard !finished else { return false }
        if let editor = currentEditor(), window.firstResponder === editor { return true }
        guard window.makeFirstResponder(self) else { return false }
        currentEditor()?.selectAll(nil)
        return true
    }

    func retire() {
        finished = true
        stopOutsideClicks()
        delegate = nil
        removeFromSuperview()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { finish(commit: true); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { finish(commit: false); return true }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) { finish(commit: true) }

    private func clicked(_ event: NSEvent) {
        guard !finished, event.window === window else { return }
        if !bounds.contains(convert(event.locationInWindow, from: nil)) { finish(commit: true) }
    }

    private func finish(commit: Bool) {
        guard !finished else { return }
        finished = true
        stopOutsideClicks()
        onFinish(commit ? stringValue : nil)
    }

    private func stopOutsideClicks() {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
    }
}
