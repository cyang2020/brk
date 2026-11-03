import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Arc's Cmd+F bar (P18): a PopoverBackground rounded bar with a soft shadow at the card's top-right corner. One row
/// holds the magnifier, the borderless query, the count, up and down arrows, a separator and close; a query with no
/// match shows FindInPageError NOT FOUND in place of the count and arrows. Brk's Find and Replace adds a second row
/// in the same style (Arc 1.170 has no visible replace UI). Errors and replacement results get a line under the rows.
@MainActor
public final class FindBarView: NSView, NSTextFieldDelegate {
    private let dispatch: Dispatch
    private let icon = NSImageView(), replacementIcon = NSImageView()
    private let query = NSTextField(), replacement = NSTextField()
    private let status = NSTextField(labelWithString: ""), message = NSTextField(labelWithString: "")
    private let previous = NSButton(), next = NSButton(), close = NSButton()
    private let replace = NSButton(), all = NSButton(), capture = NSButton()
    private let separator = NSView(), divider = NSView()
    private var last: FindSnapshot?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true; identify(.findBar); isHidden = true
        layer?.masksToBounds = false
        query.identify(.findQuery); replacement.identify(.findReplacement); status.identify(.findStatus)
        query.placeholderString = "Find in Page"; replacement.placeholderString = "Replace in field"
        let m = Metrics.find
        for field in [query, replacement] {
            field.delegate = self
            field.isBordered = false; field.isBezeled = false; field.drawsBackground = false; field.focusRingType = .none
            field.font = .systemFont(ofSize: m.queryFont.value)
            field.cell?.usesSingleLineMode = true; field.cell?.isScrollable = true; field.cell?.wraps = false
        }
        status.alignment = .right; status.lineBreakMode = .byClipping
        message.font = .systemFont(ofSize: m.messageFont.value); message.lineBreakMode = .byTruncatingTail
        for (view, symbol) in [(icon, "magnifyingglass"), (replacementIcon, "arrow.2.squarepath")] {
            view.image = Self.symbol(symbol, size: m.iconGlyph.value, weight: .medium)
            view.imageScaling = .scaleNone
        }
        for (button, id, selector, symbol, tip) in [
            (previous, ViewID.findPrevious, #selector(back), "arrow.up", "Previous Match"),
            (next, .findNext, #selector(forward), "arrow.down", "Next Match"),
            (close, .findClose, #selector(dismiss), "xmark", "Close Find"),
            (capture, .findCapture, #selector(captureField), "character.cursor.ibeam", "Capture Field: replace only in the selected editable field"),
        ] {
            button.identify(id); button.target = self; button.action = selector; button.toolTip = tip
            button.isBordered = false; button.imagePosition = .imageOnly; button.title = ""
            button.image = Self.symbol(symbol, size: symbol == "xmark" ? m.closeGlyph.value : m.glyph.value, weight: .medium)
        }
        capture.setAccessibilityLabel("Capture Field")
        for (button, id, selector) in [(replace, ViewID.findReplace, #selector(replaceOne)), (all, .findReplaceAll, #selector(replaceAll))] {
            button.identify(id); button.target = self; button.action = selector; button.isBordered = false
        }
        replace.toolTip = "Replace the current match"; all.toolTip = "Replace every match in the captured field"
        for line in [separator, divider] { line.wantsLayer = true }
        for view in [icon, query, status, previous, next, separator, close, divider, replacementIcon, replacement, replace, all, capture, message] as [NSView] {
            addSubview(view)
        }
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError("not used") }
    public override var isFlipped: Bool { true }
    public func focusInput() -> Bool { guard !isHidden, let window else { return false }; return window.makeFirstResponder(query) }

    public func render(_ snapshot: FindSnapshot?, frames: FindFrames?, palette: Palette) {
        guard let snapshot, let frames else { isHidden = true; last = nil; query.stringValue = ""; replacement.stringValue = ""; return }
        if last?.page != snapshot.page { replacement.stringValue = "" }
        let m = Metrics.find, colors = OverlayColors.of(palette.scheme)
        let ink: NSColor = palette.scheme == .light ? .black : .white
        isHidden = false; frame = frames.bar; appearance = .of(palette.scheme)
        layer?.backgroundColor = colors.popover.cgColor
        layer?.cornerRadius = m.cornerRadius.value
        // Through `NSView.shadow`: AppKit keeps it on the layer (a layer's own shadow is reset when AppKit updates it).
        let drop = NSShadow()
        drop.shadowColor = colors.popoverShadow.withAlphaComponent(m.shadowOpacity.value)
        drop.shadowBlurRadius = m.shadowRadius.value
        drop.shadowOffset = NSSize(width: 0, height: -m.shadowOffset.value)
        shadow = drop

        if query.stringValue != snapshot.query.text { query.stringValue = snapshot.query.text }
        for field in [query, replacement] { field.textColor = colors.foregroundPrimary }
        query.placeholderAttributedString = placeholder("Find in Page", colors)
        replacement.placeholderAttributedString = placeholder("Replace in field", colors)
        center(query, in: frames.query, inset: m.textInset.value); center(replacement, in: frames.replacement, inset: m.textInset.value)
        // The glyph is drawn at its own size round the layout's 12 pt square.
        func around(_ rect: CGRect) -> CGRect { rect == .zero ? .zero : rect.insetBy(dx: (rect.width - m.button.value) / 2, dy: (rect.height - m.button.value) / 2) }
        icon.frame = around(frames.icon); replacementIcon.frame = around(frames.replacementIcon)
        for view in [icon, replacementIcon] { view.contentTintColor = colors.foregroundSecondary }
        for (button, rect) in [(previous, frames.previous), (next, frames.next), (close, frames.close), (capture, frames.capture)] {
            button.frame = rect; button.contentTintColor = ink.withAlphaComponent(0.72)
        }
        separator.frame = frames.separator; divider.frame = frames.divider
        for line in [separator, divider] { line.layer?.backgroundColor = colors.hairline.cgColor }

        let notFound = snapshot.notFound
        previous.isHidden = notFound; next.isHidden = notFound
        status.font = notFound ? .systemFont(ofSize: m.statusFont.value, weight: .semibold) : .monospacedDigitSystemFont(ofSize: m.statusFont.value, weight: .medium)
        status.textColor = notFound ? Self.error(palette.scheme) : ink.withAlphaComponent(0.72)
        let stacked = frames.icon == .zero
        status.alignment = stacked ? .left : .right
        status.stringValue = Self.status(snapshot)
        center(status, in: frames.status, inset: stacked ? m.textInset.value : -m.textInset.value)

        let replacing = snapshot.replacement
        for view in [divider, replacementIcon, replacement, replace, all, capture] as [NSView] { view.isHidden = !replacing }
        replace.isEnabled = snapshot.canReplace; all.isEnabled = snapshot.canReplace
        replace.frame = frames.replace; all.frame = frames.replaceAll
        label(replace, "Replace", colors: colors, ink: ink)
        label(all, stacked ? "Replace All" : "All", colors: colors, ink: ink)
        capture.imagePosition = stacked ? .imageLeading : .imageOnly
        capture.title = stacked ? "Capture Field" : ""
        capture.alignment = stacked ? .left : .center
        if snapshot.canReplace { capture.contentTintColor = colors.focusRing }

        message.isHidden = snapshot.message.isEmpty
        message.stringValue = snapshot.message; message.toolTip = snapshot.message
        message.textColor = colors.foregroundSecondary
        center(message, in: frames.message, inset: m.textInset.value)
        last = snapshot
    }

    /// "1/6" after a search, NOT FOUND for none, nothing while typing or searching.
    static func status(_ snapshot: FindSnapshot) -> String {
        if snapshot.notFound { return "NOT FOUND" }
        guard !snapshot.query.text.isEmpty, !snapshot.searching, let count = snapshot.count else { return "" }
        return "\(snapshot.ordinal ?? 0)/\(count)"
    }

    /// FindInPageError #C93333 (P3).
    private static func error(_ scheme: Scheme) -> NSColor {
        scheme == .light ? NSColor(displayP3Red: 0xC9 / 255.0, green: 0x33 / 255.0, blue: 0x33 / 255.0, alpha: 1) : .systemRed
    }

    private static func symbol(_ name: String, size: Double, weight: NSFont.Weight) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight))
    }

    private func placeholder(_ text: String, _ colors: OverlayColors) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.foregroundColor: colors.foregroundTertiary, .font: NSFont.systemFont(ofSize: Metrics.find.queryFont.value)])
    }

    private func label(_ button: NSButton, _ title: String, colors: OverlayColors, ink: NSColor) {
        let color = button.isEnabled ? ink.withAlphaComponent(0.72) : colors.foregroundTertiary
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color, .font: NSFont.systemFont(ofSize: Metrics.find.actionFont.value, weight: .medium),
        ])
    }

    /// Text fields draw from their top edge; the layout gives whole rows, so centre each field's line in its row. The
    /// cell pads its text by `inset`: move the field out by that much so the glyphs start (or, negative, end) where
    /// the layout says.
    private func center(_ field: NSTextField, in row: CGRect, inset: Double = 0) {
        guard row != .zero else { field.frame = .zero; return }
        let height = min(row.height, ceil(field.intrinsicContentSize.height))
        field.frame = CGRect(x: row.minX - max(0, inset), y: row.minY + (row.height - height) / 2, width: row.width + abs(inset), height: height)
    }

    public func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === query else { return }
        dispatch(.find(.query(FindQuery(text: query.stringValue, caseSensitive: last?.query.caseSensitive ?? false))))
    }
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { dispatch(.find(.step(NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? .previous : .next))); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { dismiss(); return true }
        return false
    }
    @objc private func back() { dispatch(.find(.step(.previous))) }
    @objc private func forward() { dispatch(.find(.step(.next))) }
    @objc private func dismiss() { dispatch(.find(.close)) }
    @objc private func replaceOne() { dispatch(.find(.replaceCurrent(replacement.stringValue))) }
    @objc private func replaceAll() { dispatch(.find(.replaceAll(replacement.stringValue))) }
    @objc private func captureField() { dispatch(.find(.captureScope)) }
}
