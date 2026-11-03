import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: R3-3. An Easel's board, drawn over the card that shows it (`PaneContent.easel`), as on Arc 1.170 (Q09 a):
/// the title box at the top centre (selected on a new Easel: blue stroke, corner handles, the title highlighted for
/// typing) with the + / Aa / − card beside it; the drawing; the toolbar at the bottom left (select, image, text,
/// ellipse, rectangle, arrow, freehand | duplicate); the person button at the bottom right.
///
/// The view keeps only what Arc keeps in the view: the tool, the selection and the stroke being drawn. Every change
/// to the board is a `.easel` command sent when a gesture ends (a shape on release, a move on release, text when
/// its field ends editing), so the saved board is the snapshot's.
///
/// Public surface: `init(dispatch:)`, `render`, `focusBoard`.
@MainActor
public final class EaselBoardView: NSView, NSTextFieldDelegate {
    private let dispatch: Dispatch
    private var easel: EaselSnapshot?
    private(set) var tool: EaselTool = .select
    /// Selected element ids; `titleSelected` is the title box.
    private(set) var selection: Set<String> = []
    private(set) var titleSelected = false

    let titleField = EaselTitleField()
    let fontTool = EaselFontTool()
    let toolbar = EaselToolbar()
    let person = EaselPanelButton()
    /// Marks the selection's frame for the control socket (hidden while nothing is selected).
    private let selectionMarker = NSView()
    /// Edits a text element in place.
    let textEditor = NSTextField()
    private var editingText: (id: String, isNew: Bool, origin: CGPoint)?
    private var editingTitle = false

    private enum Gesture {
        case move(start: CGPoint, offset: CGSize)
        case draw(EaselElement)
        case ink(id: String, points: [CGPoint])
        case marquee(start: CGPoint, end: CGPoint)
    }
    private var gesture: Gesture?
    /// Ids on the board before a duplicate, so its copies can be selected when they arrive.
    private var beforeDuplicate: Set<String>?
    /// A shape or stroke just sent with `.add`: selected once it is on the board.
    private var pendingSelection: Set<String> = []

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        isHidden = true
        identify(.easelBoard)
        titleField.delegate = self
        titleField.identify(.easelControl("title"))
        addSubview(titleField)
        fontTool.identify(.easelControl("font-tool"))
        fontTool.larger.target = self
        fontTool.larger.action = #selector(fontLarger)
        fontTool.smaller.target = self
        fontTool.smaller.action = #selector(fontSmaller)
        addSubview(fontTool)
        toolbar.identify(.easelControl("toolbar"))
        for (tool, button) in toolbar.tools {
            button.target = self
            button.action = #selector(toolClicked(_:))
            button.identify(.easelControl("tool-" + tool.rawValue))
        }
        toolbar.duplicate.target = self
        toolbar.duplicate.action = #selector(duplicateClicked)
        toolbar.duplicate.identify(.easelControl("duplicate"))
        addSubview(toolbar)
        person.image = NSImage(systemSymbolName: "person.badge.plus", accessibilityDescription: "Share")?
            .withSymbolConfiguration(.init(pointSize: EaselDraw.toolbar.glyph.value, weight: .regular))
        person.toolTip = "Share a picture of this Easel"
        person.target = self
        person.action = #selector(shareClicked)
        person.identify(.easelControl("person"))
        addSubview(person)
        selectionMarker.identify(.easelControl("selection"))
        selectionMarker.isHidden = true
        addSubview(selectionMarker)
        textEditor.isBordered = false
        textEditor.drawsBackground = false
        textEditor.focusRingType = .none
        textEditor.isHidden = true
        textEditor.delegate = self
        textEditor.cell?.wraps = false
        textEditor.cell?.isScrollable = true
        textEditor.identify(.easelControl("text-editor"))
        addSubview(textEditor)
        registerForDraggedTypes([.fileURL])
        updateTools()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { easel != nil }

    // MARK: Render

    /// Shows `easel` over `card` (window coordinates); nil hides the board. Idempotent.
    public func render(_ easel: EaselSnapshot?, in card: CGRect?, cornerRadius: Double) {
        guard let easel, let card else {
            // Leaving the board keeps what was being typed, as Arc saves as you go.
            if self.easel != nil { endTextEditing(commit: true); endTitleEditing() }
            self.easel = nil
            isHidden = true
            return
        }
        let previous = self.easel
        if previous?.id != easel.id {
            endTextEditing(commit: true)
            endTitleEditing()
            selection = []
            tool = .select
            gesture = nil
            beforeDuplicate = nil
            pendingSelection = []
            titleSelected = easel.editingTitle
            editingTitle = false
        } else if easel.editingTitle, previous?.editingTitle == false {
            titleSelected = true
        }
        self.easel = easel
        isHidden = false
        frame = card
        layer?.cornerRadius = cornerRadius
        let ids = Set(easel.elements.map(\.id))
        if let before = beforeDuplicate, ids.count > before.count {
            selection = ids.subtracting(before)
            titleSelected = false
            beforeDuplicate = nil
        }
        if !pendingSelection.isEmpty, pendingSelection.isSubset(of: ids) {
            selection = pendingSelection
            titleSelected = false
            pendingSelection = []
        }
        selection.formIntersection(ids)
        if !editingTitle {
            titleField.stringValue = easel.title
        }
        titleField.font = .systemFont(ofSize: easel.titleSize, weight: .bold)
        updateTools()
        needsLayout = true
        needsDisplay = true
    }

    /// Keyboard focus for the board (`FocusTarget.easel`): a new Easel's title, selected for typing; else the board,
    /// which takes Delete for the selection. False while the board is not shown.
    public func focusBoard() -> Bool {
        guard let window, let easel, !isHidden else { return false }
        if easel.editingTitle || editingTitle { return beginTitleEditing(selectAll: true) }
        if editingText != nil { return true }
        return window.makeFirstResponder(self)
    }

    private var origin: CGPoint { CGPoint(x: bounds.midX, y: 0) }

    private func boardPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - origin.x, y: p.y - origin.y) }
    private func viewRect(_ r: CGRect) -> CGRect { EaselDrawing.rect(r, origin: origin, scale: 1) }

    /// The title box (Q09 a: 628 x 78.5 at the top centre, narrower in a narrow card).
    var titleBox: CGRect {
        let b = EaselDraw.board
        let width = min(b.titleBox.value[0], max(120, bounds.width - 2 * b.titleSideMargin.value))
        return CGRect(x: (bounds.width - width) / 2, y: b.titleTop.value, width: width, height: b.titleBox.value[1])
    }

    public override func layout() {
        super.layout()
        let b = EaselDraw.board, t = EaselDraw.toolbar
        let box = titleBox
        let font = titleField.font ?? .systemFont(ofSize: EaselDraw.board.fontToolGlyph.value)
        let line = ceil(font.ascender - font.descender + font.leading) + 2
        titleField.frame = CGRect(x: box.minX + 8, y: box.minY + b.titleInset.value, width: box.width - 16, height: line)
        let fontSize = b.fontTool.value
        fontTool.frame = CGRect(x: box.minX - b.fontToolGap.value - fontSize[0], y: box.minY - 1, width: fontSize[0], height: fontSize[1])
        fontTool.isHidden = !titleSelected && selectedText == nil
        if let text = selectedText {
            let r = viewRect(text.frame).insetBy(dx: -b.elementOutset.value, dy: -b.elementOutset.value)
            fontTool.frame.origin = CGPoint(x: r.minX - b.fontToolGap.value - fontSize[0], y: r.midY - fontSize[1] / 2)
        }
        toolbar.frame = CGRect(x: t.margin.value, y: bounds.height - t.margin.value - t.height.value, width: toolbar.width, height: t.height.value)
        person.frame = CGRect(x: bounds.width - t.margin.value - t.person.value, y: bounds.height - t.margin.value - t.person.value,
                              width: t.person.value, height: t.person.value)
        if let box = selectionBox {
            selectionMarker.isHidden = false
            selectionMarker.frame = box
        } else {
            selectionMarker.isHidden = true
        }
    }

    private var selectedText: EaselElement? {
        guard selection.count == 1, let id = selection.first, let element = easel?.elements.first(where: { $0.id == id }), element.shape == .text else { return nil }
        return element
    }

    /// The frame around the selection, in view points.
    private var selectionBox: CGRect? {
        if titleSelected { return titleBox }
        let outset = EaselDraw.board.elementOutset.value
        let boxes = shownElements.filter { selection.contains($0.id) }.map { viewRect($0.frame).insetBy(dx: -outset, dy: -outset) }
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }

    /// The board's elements as shown right now: a move in progress offsets the selection.
    private var shownElements: [EaselElement] {
        guard let easel else { return [] }
        if case .move(_, let offset)? = gesture, offset != .zero {
            return easel.elements.map { selection.contains($0.id) ? $0.moved(by: offset) : $0 }
        }
        return easel.elements
    }

    public override func draw(_ dirtyRect: NSRect) {
        EaselPalette.board.setFill()
        bounds.fill()
        guard easel != nil else { return }
        let elements = shownElements.filter { $0.id != editingText?.id }
        EaselDrawing.draw(elements, origin: origin, scale: 1)
        switch gesture {
        case .draw(let draft)?: EaselDrawing.draw(draft, origin: origin, scale: 1)
        case .ink(let id, let points)?: EaselDrawing.draw(EaselElement(id: id, shape: .ink, frame: EaselElement.bounds(of: points), points: points), origin: origin, scale: 1)
        case .marquee(let start, let end)?:
            let r = viewRect(CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
            EaselPalette.selection.withAlphaComponent(0.12).setFill()
            r.fill()
            EaselPalette.selection.setStroke()
            NSBezierPath(rect: r).stroke()
        case .move?, nil: break
        }
        if let box = selectionBox { EaselDrawing.selection(box) }
    }

    private func updateTools() {
        for (tool, button) in toolbar.tools { button.isSelectedTool = tool == self.tool }
        // Arc draws duplicate at full ink with nothing selected; a click then does nothing.
        toolbar.duplicate.toolTip = selection.isEmpty ? "Duplicate (select something first)" : "Duplicate"
        window?.invalidateCursorRects(for: self)
    }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .select || tool == .image ? .arrow : tool == .text ? .iBeam : .crosshair)
    }

    // MARK: Pointer

    /// A label click on the title belongs to the board (selects the title box); while editing, the field takes it.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit === titleField, !editingTitle { return self }
        return hit
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDown(with event: NSEvent) {
        guard easel != nil else { return }
        let local = convert(event.locationInWindow, from: nil)
        let p = boardPoint(local)
        if editingText != nil { endTextEditing(commit: true) }
        if editingTitle, !titleField.frame.contains(local) { endTitleEditing() }
        window?.makeFirstResponder(self)
        switch tool {
        case .select, .image:
            if titleBox.contains(local), hitElement(p) == nil {
                selection = []
                titleSelected = true
                if event.clickCount >= 2 { _ = beginTitleEditing(selectAll: false) }
                changed()
                return
            }
            titleSelected = false
            if let hit = hitElement(p) {
                if event.modifierFlags.contains(.shift) {
                    if selection.contains(hit.id) { selection.remove(hit.id) } else { selection.insert(hit.id) }
                } else if !selection.contains(hit.id) {
                    selection = [hit.id]
                }
                if event.clickCount >= 2, hit.shape == .text {
                    beginTextEditing(hit)
                } else {
                    gesture = .move(start: p, offset: .zero)
                }
            } else {
                if !event.modifierFlags.contains(.shift) { selection = [] }
                gesture = .marquee(start: p, end: p)
            }
        case .text:
            selection = []
            titleSelected = false
            beginTextEditing(nil, at: p)
        case .ellipse, .rectangle, .arrow:
            selection = []
            titleSelected = false
            let shape = tool.shape!
            gesture = .draw(EaselElement(id: UUID().uuidString, shape: shape, frame: CGRect(origin: p, size: .zero), points: shape == .arrow ? [p, p] : []))
        case .pen:
            selection = []
            titleSelected = false
            gesture = .ink(id: UUID().uuidString, points: [p])
        }
        changed()
    }

    public override func mouseDragged(with event: NSEvent) {
        guard gesture != nil else { return }
        extend(to: boardPoint(convert(event.locationInWindow, from: nil)), square: event.modifierFlags.contains(.shift))
        changed()
    }

    /// The gesture in progress follows the pointer to `p` (a drag, and the release's own position).
    private func extend(to p: CGPoint, square: Bool) {
        switch gesture {
        case .move(let start, _)?:
            gesture = .move(start: start, offset: CGSize(width: p.x - start.x, height: p.y - start.y))
        case .draw(var draft)?:
            if draft.shape == .arrow {
                draft.points = [draft.points[0], p]
                draft.frame = EaselElement.bounds(of: draft.points)
            } else {
                let start = draft.points.first ?? draft.frame.origin
                draft.points = [start]
                var box = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
                if square { let side = max(box.width, box.height); box.size = CGSize(width: side, height: side) }
                draft.frame = box
            }
            gesture = .draw(draft)
        case .ink(let id, var points)?:
            if let last = points.last, hypot(last.x - p.x, last.y - p.y) >= 1.5 { points.append(p) }
            gesture = .ink(id: id, points: points)
        case .marquee(let start, _)?:
            gesture = .marquee(start: start, end: p)
        case nil: return
        }
    }

    public override func mouseUp(with event: NSEvent) {
        guard let easel else { gesture = nil; return }
        let p = boardPoint(convert(event.locationInWindow, from: nil))
        extend(to: p, square: event.modifierFlags.contains(.shift))
        switch gesture {
        case .move(_, let offset)?:
            if abs(offset.width) >= 1 || abs(offset.height) >= 1 {
                let moved = easel.elements.filter { selection.contains($0.id) }.map { $0.moved(by: offset) }
                dispatch(.easel(.update(easel.id, moved)))
            }
        case .draw(var draft)?:
            if draft.shape == .arrow {
                if hypot(draft.points[1].x - draft.points[0].x, draft.points[1].y - draft.points[0].y) < 4 {
                    draft.points = [p, CGPoint(x: p.x + 120, y: p.y - 80)]
                }
                draft.frame = EaselElement.bounds(of: draft.points)
            } else {
                if draft.frame.width < 4 || draft.frame.height < 4 { draft.frame = CGRect(x: p.x - 60, y: p.y - 60, width: 120, height: 120) }
                draft.points = []
            }
            pendingSelection = [draft.id]
            dispatch(.easel(.add(easel.id, draft)))
            tool = .select
        case .ink(let id, let points)?:
            dispatch(.easel(.add(easel.id, EaselElement(id: id, shape: .ink, frame: EaselElement.bounds(of: points), points: points))))
        case .marquee(let start, let end)?:
            let r = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            if r.width > 2 || r.height > 2 {
                let hit = easel.elements.filter { $0.frame.insetBy(dx: -1, dy: -1).intersects(r) }.map(\.id)
                if event.modifierFlags.contains(.shift) { selection.formUnion(hit) } else { selection = Set(hit) }
            }
        case nil: break
        }
        gesture = nil
        changed()
    }

    private func hitElement(_ p: CGPoint) -> EaselElement? {
        easel?.elements.reversed().first { EaselDrawing.hits($0, p) }
    }

    private func changed() {
        updateTools()
        needsLayout = true
        needsDisplay = true
    }

    // MARK: Keys

    public override func keyDown(with event: NSEvent) {
        guard let easel else { return super.keyDown(with: event) }
        // Delete and Forward Delete by key, or by the character they type (0x7F, the forward-delete function key).
        let character = event.charactersIgnoringModifiers?.unicodeScalars.first?.value
        let delete = event.keyCode == 51 || event.keyCode == 117 || character == 0x7F || character == 0x08 || character == 0xF728
        switch delete ? 51 : event.keyCode {
        case 51:
            guard !selection.isEmpty else { return }
            dispatch(.easel(.remove(easel.id, Array(selection).sorted())))
            selection = []
            changed()
        case 53:   // Esc
            selection = []
            titleSelected = false
            tool = .select
            changed()
        case 36, 76:   // Return: edit the selected text, or the title
            if let text = selectedText { beginTextEditing(text) }
            else if titleSelected { _ = beginTitleEditing(selectAll: true) }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: Title

    @discardableResult
    private func beginTitleEditing(selectAll: Bool) -> Bool {
        guard let window else { return false }
        titleSelected = true
        selection = []
        editingTitle = true
        titleField.isEditable = true
        titleField.isSelectable = true
        guard window.makeFirstResponder(titleField) else { return false }
        if selectAll { titleField.currentEditor()?.selectAll(nil) }
        else { titleField.currentEditor()?.selectedRange = NSRange(location: (titleField.stringValue as NSString).length, length: 0) }
        changed()
        return true
    }

    private func endTitleEditing() {
        guard editingTitle else { return }
        editingTitle = false
        let typed = titleField.stringValue
        if titleField.currentEditor() != nil { window?.endEditing(for: titleField) }
        titleField.isEditable = false
        titleField.isSelectable = false
        guard let easel else { return }
        let title = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { titleField.stringValue = easel.title }
        else if title != easel.title { dispatch(.easel(.rename(easel.id, title: title))) }
    }

    @objc private func fontLarger() { stepFont(1) }
    @objc private func fontSmaller() { stepFont(-1) }

    private func stepFont(_ delta: Int) {
        guard let easel else { return }
        if let text = selectedText {
            var bigger = text
            bigger.fontSize = max(10, min(96, text.fontSize + Double(delta) * 4))
            bigger.frame = EaselDrawing.textFrame(text.text, size: bigger.fontSize, at: text.frame.origin)
            dispatch(.easel(.update(easel.id, [bigger])))
        } else {
            dispatch(.easel(.stepTitleSize(easel.id, by: delta)))
        }
    }

    // MARK: Text elements

    private func beginTextEditing(_ element: EaselElement?, at point: CGPoint = .zero) {
        let size = element?.fontSize ?? EaselElement.textSize
        let origin = element?.frame.origin ?? CGPoint(x: point.x, y: point.y - size * 0.6)
        editingText = (element?.id ?? UUID().uuidString, element == nil, origin)
        textEditor.font = .systemFont(ofSize: size, weight: .medium)
        textEditor.stringValue = element?.text ?? ""
        textEditor.placeholderString = element == nil ? "Text" : nil
        let r = viewRect(EaselDrawing.textFrame(element?.text ?? "Text", size: size, at: origin))
        textEditor.frame = CGRect(x: r.minX - 2, y: r.minY, width: max(r.width + 40, 160), height: r.height + 2)
        textEditor.isHidden = false
        window?.makeFirstResponder(textEditor)
        changed()
    }

    private func endTextEditing(commit: Bool) {
        guard let editing = editingText, let easel else { editingText = nil; textEditor.isHidden = true; return }
        editingText = nil
        let text = textEditor.stringValue
        if textEditor.currentEditor() != nil { window?.endEditing(for: textEditor) }
        textEditor.isHidden = true
        let size = Double(textEditor.font?.pointSize ?? CGFloat(EaselElement.textSize))
        defer { changed() }
        guard commit else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if editing.isNew {
            guard !trimmed.isEmpty else { return }
            let element = EaselElement(id: editing.id, shape: .text, frame: EaselDrawing.textFrame(text, size: size, at: editing.origin), text: text, fontSize: size)
            pendingSelection = [editing.id]
            dispatch(.easel(.add(easel.id, element)))
            tool = .select
        } else if let old = easel.elements.first(where: { $0.id == editing.id }), old.text != text {
            var changed = old
            changed.text = text
            changed.frame = EaselDrawing.textFrame(text, size: old.fontSize, at: old.frame.origin)
            dispatch(.easel(.update(easel.id, [changed])))
        }
        if window?.firstResponder == nil || window?.firstResponder === window { window?.makeFirstResponder(self) }
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        if (obj.object as? NSTextField) === textEditor { endTextEditing(commit: true) }
        else if (obj.object as? NSTextField) === titleField { endTitleEditing(); window?.makeFirstResponder(self) }
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        if control === textEditor { endTextEditing(commit: false); window?.makeFirstResponder(self); return true }
        if control === titleField, let easel { titleField.stringValue = easel.title; endTitleEditing(); window?.makeFirstResponder(self); return true }
        return false
    }

    // MARK: Toolbar

    @objc private func toolClicked(_ sender: EaselToolButton) {
        guard let easel, let tool = sender.tool else { return }
        if editingText != nil { endTextEditing(commit: true) }
        if tool == .image {
            dispatch(.easel(.chooseImage(easel.id, at: CGPoint(x: 0, y: bounds.height * 0.45))))
            return
        }
        self.tool = tool
        if tool != .select { selection = []; titleSelected = false }
        window?.makeFirstResponder(self)
        changed()
    }

    @objc private func duplicateClicked() {
        guard let easel, !selection.isEmpty else { return }
        beforeDuplicate = Set(easel.elements.map(\.id))
        dispatch(.easel(.duplicate(easel.id, Array(selection).sorted())))
    }

    @objc private func shareClicked() {
        guard let easel else { return }
        dispatch(.easel(.share(easel.id)))
    }

    // MARK: Dropped pictures

    private func droppedImages(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { ["png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "webp", "bmp"].contains($0.pathExtension.lowercased()) }
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { easel != nil && !droppedImages(sender).isEmpty ? .copy : [] }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let easel else { return false }
        let p = boardPoint(convert(sender.draggingLocation, from: nil))
        let urls = droppedImages(sender)
        for (i, url) in urls.enumerated() {
            dispatch(.easel(.importImage(easel.id, from: url, at: CGPoint(x: p.x + CGFloat(i) * 24, y: p.y + CGFloat(i) * 24))))
        }
        return !urls.isEmpty
    }
}

/// The title: bold, centred, borderless; editable only while being edited.
final class EaselTitleField: NSTextField {
    init() {
        super.init(frame: .zero)
        isBordered = false
        drawsBackground = false
        isEditable = false
        isSelectable = false
        alignment = .center
        focusRingType = .none
        textColor = EaselPalette.title
        lineBreakMode = .byTruncatingTail
        cell?.usesSingleLineMode = true
        cell?.isScrollable = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
}

/// A white rounded card with a soft shadow: the toolbar, the font-size card and the person button.
class EaselPanelView: NSView {
    init(radius: Double) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = EaselPalette.panel.cgColor
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        EaselPalette.applyShadow(to: layer)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
}

/// The person button at the bottom right (Arc's invite button; Brk shares a picture of the board instead).
final class EaselPanelButton: NSButton {
    init() {
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageOnly
        contentTintColor = EaselPalette.glyph
        wantsLayer = true
        layer?.backgroundColor = EaselPalette.panel.cgColor
        layer?.cornerRadius = EaselDraw.toolbar.radius.value
        layer?.cornerCurve = .continuous
        EaselPalette.applyShadow(to: layer)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
}

/// One toolbar button: its glyph, on the grey square while it is the current tool (Q09 a).
final class EaselToolButton: NSButton {
    let tool: EaselTool?
    var isSelectedTool = false { didSet { if isSelectedTool != oldValue { refresh() } } }

    init(tool: EaselTool?, symbol: String?) {
        self.tool = tool
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerRadius = EaselDraw.toolbar.buttonRadius.value
        layer?.cornerCurve = .continuous
        let glyph = EaselDraw.toolbar.glyph.value
        // Arc's arrow and duplicate glyphs are heavier than the outline tools.
        let weight: NSFont.Weight = tool == .arrow || tool == nil ? .semibold : .regular
        image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: tool?.label ?? "Duplicate")?.withSymbolConfiguration(.init(pointSize: glyph, weight: weight)) }
        toolTip = tool?.label ?? "Duplicate"
        setAccessibilityLabel(toolTip)
        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    private func refresh() {
        let ink = isSelectedTool ? NSColor.white : EaselPalette.glyph
        contentTintColor = ink
        let glyph = EaselDraw.toolbar.glyph.value
        switch tool {
        case .text?: image = EaselDrawing.outlinedA(size: glyph, color: ink)
        case .image?: image = EaselDrawing.pictureGlyph(size: glyph + 5, color: ink)
        case .pen?: image = EaselDrawing.squiggleGlyph(size: glyph + 5, color: ink)
        default: break
        }
        layer?.backgroundColor = isSelectedTool ? EaselPalette.selectedTool.cgColor : NSColor.clear.cgColor
    }
}

/// The toolbar: seven tools, a separator, duplicate.
final class EaselToolbar: EaselPanelView {
    let tools: [(EaselTool, EaselToolButton)]
    let duplicate = EaselToolButton(tool: nil, symbol: "plus.square.on.square")
    private let separator = NSView()

    init() {
        tools = EaselTool.allCases.map { ($0, EaselToolButton(tool: $0, symbol: $0.symbol)) }
        super.init(radius: EaselDraw.toolbar.radius.value)
        for (_, button) in tools { addSubview(button) }
        separator.wantsLayer = true
        separator.layer?.backgroundColor = EaselPalette.separator.cgColor
        addSubview(separator)
        addSubview(duplicate)
    }

    var width: CGFloat {
        let t = EaselDraw.toolbar
        return t.padding.value + CGFloat(tools.count) * t.step.value + t.separatorGap.value[1] + t.button.value + t.padding.value
    }

    override func layout() {
        super.layout()
        let t = EaselDraw.toolbar
        let top = (bounds.height - t.button.value) / 2
        for (i, (_, button)) in tools.enumerated() {
            button.frame = CGRect(x: t.padding.value + CGFloat(i) * t.step.value, y: top, width: t.button.value, height: t.button.value)
        }
        let line = t.padding.value + CGFloat(tools.count) * t.step.value
        separator.frame = CGRect(x: line, y: top, width: t.separatorGap.value[0], height: t.button.value)
        duplicate.frame = CGRect(x: line + t.separatorGap.value[1], y: top, width: t.button.value, height: t.button.value)
    }
}

/// The + / Aa / − card beside the selected title or text (Q09 a).
final class EaselFontTool: EaselPanelView {
    let larger = NSButton()
    let smaller = NSButton()
    private let label = NSTextField(labelWithString: "Aa")

    init() {
        super.init(radius: EaselDraw.board.fontToolRadius.value)
        let size = EaselDraw.board.fontToolGlyph.value
        for (button, symbol, name, id) in [(larger, "plus", "Larger", "font-larger"), (smaller, "minus", "Smaller", "font-smaller")] {
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)?.withSymbolConfiguration(.init(pointSize: size - 2, weight: .regular))
            button.contentTintColor = EaselPalette.fontStep
            button.toolTip = name
            button.identify(.easelControl(id))
            addSubview(button)
        }
        let serif = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) }
        label.font = serif ?? NSFont(name: "Times New Roman", size: size)
        label.textColor = NSColor(white: 0.12, alpha: 1)
        label.alignment = .center
        addSubview(label)
    }

    override func layout() {
        super.layout()
        let third = bounds.height / 3
        larger.frame = CGRect(x: 0, y: 2, width: bounds.width, height: third)
        let labelHeight = ceil(label.intrinsicContentSize.height)
        label.frame = CGRect(x: 0, y: (bounds.height - labelHeight) / 2, width: bounds.width, height: labelHeight)
        smaller.frame = CGRect(x: 0, y: bounds.height - third - 2, width: bounds.width, height: third)
    }
}
