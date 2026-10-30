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
    /// view (this one, a nested button, or the rename field).
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
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

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.imageScaling = .scaleNone
        addSubview(icon)
        layer?.cornerCurve = .continuous
    }

    func render(_ glyph: Glyph, size: Double, palette: Palette, tint: NSColor? = nil, radius: Double, hoverFill: RGBA?) {
        if self.glyph != glyph || glyphSize != size { icon.image = glyph.image(size: size) }
        self.glyph = glyph
        glyphSize = size
        self.palette = palette
        self.radius = radius
        self.hoverFill = hoverFill
        icon.contentTintColor = tint ?? (isEnabled ? palette.ink.secondary : palette.ink.placeholder)
        stateChanged()
    }

    override func layout() {
        super.layout()
        icon.frame = bounds
    }

    override func stateChanged() {
        guard let palette else { return }
        layer?.cornerRadius = radius
        let fill: RGBA? = !isEnabled ? nil : isPressed ? palette.tokens.tabPressed : isHovered ? hoverFill : nil
        layer?.backgroundColor = fill.map { palette.color($0).cgColor }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(local(event))
        isPressed = false
        if isEnabled, inside { action?(event.modifierFlags) }
    }
}

/// The in-place rename field of a row (identified `rename-field`).
@MainActor
final class RenameField: NSTextField {
    /// Set once the rename has been committed or cancelled, so losing focus afterwards sends nothing.
    var finished = false
}
