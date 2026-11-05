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
    /// Fill that stays while the button's popover is open.
    var latchedFill: RGBA? { didSet { if latchedFill != oldValue { stateChanged() } } }
    /// Arc's own tooltip while the pointer is on the button (`ArcTooltip`), for the controls that have it.
    var tip: String?
    private var symbolName: String?

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
        if self.glyph != glyph || glyphSize != size { icon.image = glyph.image(size: size, weight: weight) }
        self.glyph = glyph
        glyphSize = size
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

    override func setHovered(_ hovered: Bool) {
        super.setHovered(hovered)
        if tip != nil { ArcTooltip.pointer(on: self, text: hovered && isEnabled ? tip : nil) }
    }

    override func layout() {
        super.layout()
        icon.frame = bounds
    }

    override func stateChanged() {
        guard let palette else { return }
        layer?.cornerRadius = radius
        let fill: RGBA? = !isEnabled ? nil : isPressed ? palette.tokens.tabPressed : latchedFill ?? (isHovered ? hoverFill : nil)
        layer?.backgroundColor = fill.map { palette.color($0).cgColor }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if tip != nil { ArcTooltip.pointer(on: self, text: nil) }
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(local(event))
        isPressed = false
        if isEnabled, inside { action?(event.modifierFlags) }
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
