import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Arc's capture mode (P33): the whole window dims (the page grey, the sidebar faded), a card at the bottom says
/// "Drag to capture a portion of this page", and a strip at the top right teaches ⇧⌘-drag. The dragged area shows the
/// page undimmed with a blue line along its bottom; releasing captures at once and opens the menu card beside it.
@MainActor final class CaptureOverlayView: NSView, NSTextFieldDelegate {
    private let dispatch: Dispatch
    private var snapshot: CaptureSnapshot?
    private var page = CGRect.zero
    private var selection = CGRect.zero
    private var anchor: CGPoint?
    private var moved = false
    /// Started by ⇧⌘-drag on the page: the "Next time, hold ⇧⌘" lesson is already learned.
    private var viaShortcut = false
    private var shortcutPending = false
    /// Above the dim and below the hint card: greys the page out (Arc's mask is colourless, P33-a).
    private let shade = CaptureShadeView()
    /// The hint card, the ⇧⌘ lesson and the selection's blue line, drawn above the grey-out so they keep their colours.
    private let chrome = CaptureChromeView()
    private let menuCard = CaptureMenuCard()
    private var tracking: NSTrackingArea?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        identify(.tabTool("capture-overlay"))
        menuCard.chosen = { [weak self] action in self?.dispatch(.capture(.act(action))) }
        chrome.drawChrome = { [weak self] in self?.drawChrome() }
        addSubview(shade); addSubview(chrome); addSubview(menuCard)
        isHidden = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The next capture comes from ⇧⌘-drag (WindowController's shortcut), so its mouse-down is already the drag start.
    func expectShortcutDrag(_ expected: Bool) { shortcutPending = expected }

    func render(_ value: CaptureSnapshot?, frames: WindowFrames, peek: PeekSnapshot?) {
        // A full-page capture has nothing to select: Arc's page stays as it is until the copied toast (P33-d).
        guard let value, value.request.mode != .fullPage else { isHidden = true; snapshot = nil; window?.invalidateCursorRects(for: self); return }
        let rect = frames.cards.first(where: { if case .page(let page) = $0.content { page == value.request.document.browser.page } else { false } })?.page
            ?? (peek?.page == value.request.document.browser.page ? frames.peek : nil)
        guard let rect else { isHidden = true; snapshot = nil; return }
        let fresh = snapshot?.request.id != value.request.id
        let retaken = snapshot?.image != nil && value.image == nil && !value.rendering
        snapshot = value; page = rect; isHidden = false
        if fresh {
            viaShortcut = shortcutPending; shortcutPending = false
            anchor = nil
            let width = min(360, rect.width, rect.height * 9 / 16)
            selection = value.request.mode == .portrait ? CGRect(x: rect.midX - width / 2, y: rect.midY - width * 8 / 9, width: width, height: width * 16 / 9) : .zero
        } else if retaken, value.request.mode != .portrait { selection = .zero }
        let showMenu = value.image != nil && value.action == nil
        menuCard.isHidden = !showMenu
        if showMenu {
            menuCard.render(privateCapture: !value.canSaveToLibrary)
            let size = Metrics.capture.menuCard.value, gap = Metrics.capture.menuGap.value
            var x = selection.maxX + gap
            if x + size.width > bounds.maxX - 6 { x = max(bounds.minX + 6, selection.minX - gap - size.width) }
            let y = min(max(bounds.minY + 6, selection.minY), bounds.maxY - 6 - size.height)
            menuCard.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    // MARK: Drawing

    override func layout() {
        super.layout()
        shade.frame = bounds; chrome.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        guard snapshot != nil else { return }
        let cut = selection.isEmpty ? nil : selection
        // The sidebar and window frame fade; the page dims to grey (P33-a: white → #C6C6C6, black text → #959594).
        let outside = NSBezierPath(rect: bounds); outside.append(NSBezierPath(rect: page)); outside.windingRule = .evenOdd
        NSColor.white.withAlphaComponent(Metrics.capture.sidebarFade.value).setFill(); outside.fill()
        let dim = NSBezierPath(rect: page)
        if let cut { dim.append(NSBezierPath(rect: cut)); dim.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(Metrics.capture.pageDim.value).setFill(); dim.fill()
        shade.render(page: page, cut: cut)
        chrome.needsDisplay = true
    }

    private func drawChrome() {
        guard let snapshot else { return }
        let cut = selection.isEmpty ? nil : selection
        if let cut, cut.width > 12, cut.height > 10 {
            let line = CGRect(x: cut.minX + 4.5, y: cut.maxY - 8, width: cut.width - 9, height: 4)
            NSColor(srgbRed: 0x99 / 255.0, green: 0xBD / 255.0, blue: 0xE7 / 255.0, alpha: 1).setFill()
            NSBezierPath(roundedRect: line, xRadius: 2, yRadius: 2).fill()
        }
        guard snapshot.image == nil, !snapshot.rendering else { return }
        if anchor == nil, cut == nil || snapshot.request.mode == .portrait { drawHintCard(portrait: snapshot.request.mode == .portrait) }
        if !viaShortcut { drawShortcutLesson() }
    }

    /// The white card at the bottom centre with its soft colour glow (P33-a).
    private func drawHintCard(portrait: Bool) {
        let size = Metrics.capture.hintCard.value, radius = Metrics.capture.hintCardRadius.value
        let card = CGRect(x: page.midX - size.width / 2, y: page.maxY - Metrics.capture.hintCardBottom.value - size.height, width: size.width, height: size.height)
        let path = NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius)
        for (color, radius) in [(NSColor(srgbRed: 1, green: 0.62, blue: 0.72, alpha: 0.55), CGFloat(34)), (NSColor(srgbRed: 0.55, green: 0.62, blue: 1, alpha: 0.6), 22)] {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow(); glow.shadowColor = color; glow.shadowBlurRadius = radius; glow.shadowOffset = .zero; glow.set()
            NSColor.white.setFill(); path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor.white.setFill(); path.fill()
        let text = NSAttributedString(string: portrait ? "Drag to frame a portrait, or click to capture it" : "Drag to capture a portion of this page",
                                      attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                                                   .foregroundColor: NSColor(srgbRed: 0x67 / 255.0, green: 0x47 / 255.0, blue: 0xB0 / 255.0, alpha: 1)])
        let textSize = text.size()
        text.draw(at: CGPoint(x: card.midX - textSize.width / 2, y: card.midY - textSize.height / 2))
    }

    /// "Next time, hold ⇧⌘ and drag your mouse to capture any time." in the toast style (P15-a), top right.
    private func drawShortcutLesson() {
        let font = NSFont.systemFont(ofSize: 15)
        let ink: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let before = NSAttributedString(string: "Next time, hold", attributes: ink)
        let keys = NSAttributedString(string: "⇧⌘", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.black])
        let after = NSAttributedString(string: "and drag your mouse to capture any time.", attributes: ink)
        let chip = CGSize(width: keys.size().width + 20, height: 28)
        let width = 14 + before.size().width + 8 + chip.width + 8 + after.size().width + 16
        let strip = CGRect(x: page.maxX - 8 - width, y: page.minY + 9, width: width, height: Metrics.capture.lessonHeight.value)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.12); shadow.shadowBlurRadius = 6; shadow.shadowOffset = CGSize(width: 0, height: -1); shadow.set()
        NSColor(srgbRed: 0xE8 / 255.0, green: 0xF6 / 255.0, blue: 0xF6 / 255.0, alpha: 1).setFill()
        NSBezierPath(roundedRect: strip, xRadius: Metrics.capture.lessonRadius.value, yRadius: Metrics.capture.lessonRadius.value).fill()
        NSGraphicsContext.restoreGraphicsState()
        var x = strip.minX + 14
        before.draw(at: CGPoint(x: x, y: strip.midY - before.size().height / 2)); x += before.size().width + 8
        let chipRect = CGRect(x: x, y: strip.midY - chip.height / 2, width: chip.width, height: chip.height)
        NSColor(srgbRed: 0xC9 / 255.0, green: 0xD5 / 255.0, blue: 0xD5 / 255.0, alpha: 1).setFill()
        NSBezierPath(roundedRect: chipRect, xRadius: 6, yRadius: 6).fill()
        keys.draw(at: CGPoint(x: chipRect.midX - keys.size().width / 2, y: chipRect.midY - keys.size().height / 2)); x += chip.width + 8
        after.draw(at: CGPoint(x: x, y: strip.midY - after.size().height / 2))
    }

    // MARK: Pointer

    override func resetCursorRects() {
        guard snapshot != nil, snapshot?.image == nil else { return }
        addCursorRect(page, cursor: Self.cameraCursor)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func cursorUpdate(with event: NSEvent) { pointerCursor(event) }
    override func mouseMoved(with event: NSEvent) { pointerCursor(event) }
    private func pointerCursor(_ event: NSEvent) {
        guard snapshot != nil, snapshot?.image == nil, page.contains(convert(event.locationInWindow, from: nil)) else { return }
        Self.cameraCursor.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let snapshot, !snapshot.rendering else { return }
        let p = convert(event.locationInWindow, from: nil)
        if snapshot.image != nil {
            // The menu card is open: a click elsewhere leaves capture mode.
            if !menuCard.frame.contains(p) { dispatch(.capture(.cancel)) }
            return
        }
        guard page.contains(p) else { dispatch(.capture(.cancel)); return }
        anchor = clamp(p); moved = false
        if snapshot.request.mode != .portrait { selection = .zero }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let p = clamp(convert(event.locationInWindow, from: nil))
        if !moved, hypot(p.x - anchor.x, p.y - anchor.y) < 3 { return }
        moved = true
        if snapshot?.request.mode == .portrait {
            let width = min(max(1, abs(p.x - anchor.x)), page.width, page.height * 9 / 16)
            let height = width * 16 / 9
            selection = CGRect(x: min(max(page.minX, min(p.x, anchor.x)), page.maxX - width), y: min(max(page.minY, min(p.y, anchor.y)), page.maxY - height), width: width, height: height)
        } else {
            selection = CGRect(x: min(p.x, anchor.x), y: min(p.y, anchor.y), width: abs(p.x - anchor.x), height: abs(p.y - anchor.y))
        }
        Self.cameraCursor.set()
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard anchor != nil else { return }
        mouseDragged(with: event)
        anchor = nil
        // Arc captures on release; a plain click keeps a portrait frame where it is and captures it.
        if moved || snapshot?.request.mode == .portrait { capture() } else { selection = .zero }
        needsDisplay = true
    }
    private func clamp(_ p: CGPoint) -> CGPoint { CGPoint(x: min(page.maxX, max(page.minX, p.x)), y: min(page.maxY, max(page.minY, p.y))) }
    override func keyDown(with event: NSEvent) { if event.keyCode == Key.escape.code { dispatch(.capture(.cancel)) } else { super.keyDown(with: event) } }
    private func capture() {
        guard selection.width >= 1, selection.height >= 1, page.width > 0, page.height > 0 else { selection = .zero; return }
        dispatch(.capture(.select(CaptureRegion(x: (selection.minX - page.minX) / page.width, y: (selection.minY - page.minY) / page.height,
                                                width: selection.width / page.width, height: selection.height / page.height))))
    }

    /// A crosshair with a small camera at its upper right (P33-a/b).
    static let cameraCursor: NSCursor = {
        let size = NSSize(width: 40, height: 40), hot = NSPoint(x: 13, y: 27)
        let image = NSImage(size: size, flipped: true) { _ in
            for (color, width) in [(NSColor.white, CGFloat(3)), (NSColor.black, CGFloat(1.2))] {
                color.setStroke()
                let cross = NSBezierPath(); cross.lineWidth = width
                cross.move(to: NSPoint(x: hot.x - 10, y: hot.y)); cross.line(to: NSPoint(x: hot.x + 10, y: hot.y))
                cross.move(to: NSPoint(x: hot.x, y: hot.y - 10)); cross.line(to: NSPoint(x: hot.x, y: hot.y + 10))
                cross.stroke()
            }
            let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            for (color, inset) in [(NSColor.white, CGFloat(-1.5)), (NSColor.black, CGFloat(0))] {
                guard let camera = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(configuration.applying(.init(paletteColors: [color]))) else { continue }
                camera.draw(in: CGRect(x: 21 + inset, y: 4 + inset, width: camera.size.width - inset * 2, height: camera.size.height - inset * 2),
                            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            return true
        }
        return NSCursor(image: image, hotSpot: hot)
    }()
}

/// Neutral grey composited with a saturation blend: whatever is under it keeps its brightness and loses its colour.
@MainActor final class CaptureShadeView: NSView {
    private var page = CGRect.zero, cut: CGRect?
    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        compositingFilter = CIFilter(name: "CISaturationBlendMode")
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func render(page: CGRect, cut: CGRect?) {
        guard page != self.page || cut != self.cut else { return }
        self.page = page; self.cut = cut; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: page)
        if let cut { path.append(NSBezierPath(rect: cut)); path.windingRule = .evenOdd }
        NSColor(white: 0.5, alpha: 1).setFill(); path.fill()
    }
}

@MainActor final class CaptureChromeView: NSView {
    var drawChrome: (() -> Void)?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { drawChrome?() }
}

/// The menu card beside a finished selection (P33-c): a Send To… field, then Save to Library, Copy, Save…, Send via
/// iMessage… | Edit, Retake | New Easel. Brk has no iMessage or Easel hand-off here, so those rows are shown disabled.
@MainActor final class CaptureMenuCard: NSView, NSTextFieldDelegate {
    struct Row { let action: CaptureAction?; let title: String; let symbol: String; let id: String }
    static let groups: [[Row]] = [
        [Row(action: .library, title: "Save to Library", symbol: "circle", id: "library"), Row(action: .copy, title: "Copy", symbol: "doc.on.doc", id: "copy"),
         Row(action: .file, title: "Save…", symbol: "square.and.arrow.down", id: "file"), Row(action: nil, title: "Send via iMessage…", symbol: "message.fill", id: "imessage")],
        [Row(action: .edit, title: "Edit", symbol: "pencil.circle", id: "edit"), Row(action: .retake, title: "Retake", symbol: "arrow.counterclockwise", id: "retake")],
        [Row(action: nil, title: "New Easel", symbol: "plus", id: "easel")],
    ]
    var chosen: ((CaptureAction) -> Void)?
    private let field = NSTextField()
    private var rows: [(Row, CaptureMenuRow)] = []
    private var separators: [CGFloat] = []
    private var privateCapture = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor; layer?.cornerRadius = Metrics.capture.menuRadius.value; layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.2; layer?.shadowRadius = 10; layer?.shadowOffset = CGSize(width: 0, height: -3)
        identify(.tabTool("capture-menu"))
        field.placeholderString = "Send To…"; field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .systemFont(ofSize: 15); field.delegate = self; field.identify(.tabTool("capture-menu-search"))
        addSubview(field)
        for group in Self.groups {
            for row in group {
                let view = CaptureMenuRow(row)
                view.identify(.tabTool("capture-menu-" + row.id))
                view.onPress = { [weak self] in if let action = row.action { self?.chosen?(action) } }
                rows.append((row, view)); addSubview(view)
            }
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func render(privateCapture: Bool) {
        self.privateCapture = privateCapture
        refresh()
    }
    func controlTextDidChange(_ obj: Notification) { refresh() }
    private func refresh() {
        let query = field.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        for (row, view) in rows {
            view.isHidden = !query.isEmpty && !row.title.lowercased().contains(query)
            view.isEnabled = row.action != nil && !(privateCapture && (row.action == .library || row.action == .edit))
        }
        needsLayout = true; needsDisplay = true
    }
    override func layout() {
        super.layout()
        field.frame = CGRect(x: 20, y: 17.5, width: bounds.width - 40, height: 21)
        var y: CGFloat = 52
        separators = []
        var index = 0
        for (g, group) in Self.groups.enumerated() {
            var shown = 0
            for _ in group {
                let view = rows[index].1; index += 1
                guard !view.isHidden else { continue }
                view.frame = CGRect(x: 8, y: y, width: bounds.width - 16, height: 36); y += Metrics.capture.menuRowPitch.value; shown += 1
            }
            if shown > 0, g < Self.groups.count - 1 { separators.append(y + 2); y += 9 }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0xEF / 255.0, green: 0xEF / 255.0, blue: 0xEF / 255.0, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: 10, y: 13, width: bounds.width - 21, height: 30), xRadius: 6, yRadius: 6).fill()
        for y in separators { CGRect(x: 8, y: y, width: bounds.width - 16, height: 1).fill() }
    }
}

@MainActor final class CaptureMenuRow: NSView {
    let row: CaptureMenuCard.Row
    var onPress: (() -> Void)?
    var isEnabled = true { didSet { needsDisplay = true } }
    private var hovered = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    init(_ row: CaptureMenuCard.Row) { self.row = row; super.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; NSCursor.arrow.set() }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { if isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() } }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { row.title }
    override func draw(_ dirtyRect: NSRect) {
        if hovered, isEnabled {
            NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.05).setFill(); NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        let ink = isEnabled ? NSColor.black : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3)
        let icon = isEnabled ? NSColor(srgbRed: 0x82 / 255.0, green: 0x82 / 255.0, blue: 0x82 / 255.0, alpha: 1) : ink
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular).applying(.init(paletteColors: [icon]))
        if let image = NSImage(systemSymbolName: row.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            image.draw(in: CGRect(x: 17 - image.size.width / 2, y: bounds.midY - image.size.height / 2, width: image.size.width, height: image.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let text = NSAttributedString(string: row.title, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: ink])
        text.draw(at: CGPoint(x: 34, y: bounds.midY - text.size().height / 2))
    }
}
