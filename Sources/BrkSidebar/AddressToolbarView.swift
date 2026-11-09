import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The toolbar (Shift+Cmd+D; Arc: the address bar across the top of the content card). It is the card's top: white,
/// rounded at the top corners, a hairline under the 32 pt control row. Back, forward and reload (stop while loading)
/// at the left; the link glyph and the host centred on the card (a click edits the address); copy link, the site
/// controls and a new split pane at the right. While it shows, the sidebar keeps only the traffic lights and its toggle.
/// Brk's own: while the window can open the AI panel its chat button ends the row (docs/design/ai-right-panel.md).
@MainActor
public final class AddressToolbarView: NSView {
    private let address = NSButton()
    private let link = PassthroughImageView()
    private let host = PassthroughLabel(labelWithString: "")
    private let hairline = NSView()
    private var buttons: [NSButton] = []
    private var trailing: [NSButton] = []
    private let ai = AddressToolbarView.button(AIToggleBadge.symbol, name: "ai", target: nil, action: nil)
    private let aiBadge = AIToggleBadge()
    private let dispatch: Dispatch
    private var loading = false

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.content.cornerRadius.value
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        identify(.toolbar)
        for (i, (name, symbol)) in [("back", "arrow.left"), ("forward", "arrow.right"), ("reload", "arrow.clockwise")].enumerated() {
            let button = Self.button(symbol, name: name, target: self, action: #selector(clicked(_:)))
            button.tag = i
            button.identify(.toolbarButton(name))
            addSubview(button); buttons.append(button)
        }
        for (i, (name, symbol, tip)) in [("copy-link", "link", "Copy Link"), ("site-controls", "slider.horizontal.2.square", "Website controls and privacy"),
                                         ("split", "rectangle.split.2x1", "Add Split View")].enumerated() {
            let button = Self.button(symbol, name: name, target: self, action: #selector(trailingClicked(_:)))
            button.tag = i
            button.toolTip = tip
            button.identify(.toolbarButton(name))
            addSubview(button); trailing.append(button)
        }
        address.target = self; address.action = #selector(editAddress)
        address.isBordered = false
        address.title = ""
        address.identify(.toolbarAddress)
        link.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Draw.toolbarGlyph.value, weight: .regular))
        host.font = .systemFont(ofSize: Draw.urlFont.value, weight: .medium)
        host.lineBreakMode = .byTruncatingMiddle
        host.isSelectable = false
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor(white: 0, alpha: Draw.toolbarHairlineAlpha.value).cgColor
        ai.target = self
        ai.action = #selector(aiClicked)
        ai.wantsLayer = true
        ai.identify(.toolbarButton("ai"))
        aiBadge.identify(.aiControl("toolbar-toggle-badge"))
        for view in [address, link, host, hairline, ai, aiBadge] as [NSView] { addSubview(view) }
        isHidden = true
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError("not used") }
    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { true }

    private static func button(_ symbol: String, name: String, target: AnyObject?, action: Selector?) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Draw.toolbarGlyph.value, weight: .regular))
        let button = NSButton(image: image ?? NSImage(), target: target, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        return button
    }

    public func render(_ pill: URLPillSnapshot, rect: CGRect?, palette: Palette, ai toggleState: AIToggleSnapshot? = nil) {
        guard let rect else { isHidden = true; return }
        isHidden = false; frame = rect
        let enabled = NSColor(white: 0, alpha: Draw.toolbarGlyphAlpha.value), disabled = NSColor(white: 0, alpha: Draw.toolbarDisabledAlpha.value)
        let chat = toggleState != nil
        ai.isHidden = !chat
        if let toggleState {
            ai.frame = AddressToolbarLayout.aiButton(in: bounds)
            ai.contentTintColor = enabled
            ai.toolTip = AIThreadWords.toggleTip(toggleState.language)
            ai.setAccessibilityValue(toggleState.open ? "open" : "closed")
            // Open: the fill a hovered sidebar button has, the panel's switch shown on.
            ai.layer?.cornerRadius = Draw.navButtonRadius.value
            ai.layer?.backgroundColor = toggleState.open ? NSColor(white: 0, alpha: 0.06).cgColor : nil
        }
        aiBadge.show(chat ? toggleState?.waiting ?? 0 : 0, on: ai.frame, palette: palette)
        for (i, button) in buttons.enumerated() { button.frame = AddressToolbarLayout.button(i, in: bounds) }
        for (i, button) in trailing.enumerated() {
            button.frame = AddressToolbarLayout.trailingButton(i, in: bounds, ai: chat)
            button.contentTintColor = enabled
            button.isEnabled = pill.text != nil
        }
        buttons[0].isEnabled = pill.canGoBack; buttons[1].isEnabled = pill.canGoForward
        buttons[2].isEnabled = pill.text != nil
        for button in buttons { button.contentTintColor = button.isEnabled ? enabled : disabled }
        loading = pill.loading
        buttons[2].image = NSImage(systemSymbolName: loading ? "xmark" : "arrow.clockwise", accessibilityDescription: loading ? "Stop" : "Reload")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Draw.toolbarGlyph.value, weight: .regular))
        buttons[2].toolTip = loading ? "Stop" : "Reload"
        let area = AddressToolbarLayout.address(in: bounds, ai: chat)
        address.frame = area
        let text = pill.toolbarText ?? pill.host ?? pill.text
        host.stringValue = text ?? Copy.urlPlaceholder
        host.textColor = NSColor(white: 0, alpha: text == nil ? Draw.toolbarDisabledAlpha.value : Draw.toolbarTextAlpha.value)
        address.toolTip = pill.text ?? Copy.urlPlaceholder
        link.contentTintColor = enabled
        link.isHidden = text == nil
        // The glyph and the host together are centred on the card, within the address area.
        let glyph = Draw.toolbarGlyph.value + Draw.toolbarLinkGap.value
        // The cell's own size includes its inset; the intrinsic width alone clips a short host ("12…0.1").
        let natural = Double(ceil(host.cell?.cellSize.width ?? host.intrinsicContentSize.width)) + Draw.toolbarHostSlack.value
        let textWidth = min(natural, max(0, area.width - glyph))
        let total = (link.isHidden ? 0 : glyph) + textWidth
        let x = min(max(area.minX, bounds.midX - total / 2), max(area.minX, area.maxX - total))
        link.frame = CGRect(x: x, y: area.midY - Draw.toolbarGlyph.value / 2, width: Draw.toolbarGlyph.value, height: Draw.toolbarGlyph.value)
        let height = host.intrinsicContentSize.height
        host.frame = CGRect(x: x + (link.isHidden ? 0 : glyph), y: area.midY - height / 2, width: textWidth, height: height)
        let line = Draw.hairline.value
        hairline.frame = CGRect(x: 0, y: bounds.height - line, width: bounds.width, height: line)
    }

    @objc private func editAddress() { dispatch(.commandBar(.open(.editCurrent))) }
    @objc private func aiClicked() { dispatch(.assist(.togglePanel)) }
    @objc private func clicked(_ sender: NSButton) {
        switch sender.tag {
        case 0: dispatch(.page(.back(.focused)))
        case 1: dispatch(.page(.forward(.focused)))
        default: dispatch(loading ? .page(.stop(.focused)) : .page(.reload(.focused, ignoringCache: NSEvent.modifierFlags.contains(.option))))
        }
    }
    @objc private func trailingClicked(_ sender: NSButton) {
        switch sender.tag {
        case 0: dispatch(.page(.copyURL(.plain)))
        case 1: dispatch(.site(.controls))
        default: dispatch(.split(.addPane))
        }
    }
}

/// The toolbar's host and link glyph draw over the address button; clicks go through them to it.
final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
