import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The toolbar (Shift+Cmd+D; Arc: the address bar across the top of the content card). It is the card's top: white,
/// rounded at the top corners, a hairline under the 32 pt control row. Back, forward and reload (stop while loading)
/// at the left; the link glyph and the host centred on the card (a click edits the address); copy link, the site
/// controls and a new split pane at the right. While it shows, the sidebar keeps only the traffic lights and its toggle.
@MainActor
public final class AddressToolbarView: NSView {
    private let address = NSButton()
    private let link = NSImageView()
    private let host = NSTextField(labelWithString: "")
    private let hairline = NSView()
    private var buttons: [NSButton] = []
    private var trailing: [NSButton] = []
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
        for view in [address, link, host, hairline] as [NSView] { addSubview(view) }
        isHidden = true
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError("not used") }
    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { true }

    private static func button(_ symbol: String, name: String, target: AnyObject, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Draw.toolbarGlyph.value, weight: .regular))
        let button = NSButton(image: image ?? NSImage(), target: target, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        return button
    }

    public func render(_ pill: URLPillSnapshot, rect: CGRect?, palette: Palette) {
        guard let rect else { isHidden = true; return }
        isHidden = false; frame = rect
        let enabled = NSColor(white: 0, alpha: Draw.toolbarGlyphAlpha.value), disabled = NSColor(white: 0, alpha: Draw.toolbarDisabledAlpha.value)
        for (i, button) in buttons.enumerated() { button.frame = AddressToolbarLayout.button(i, in: bounds) }
        for (i, button) in trailing.enumerated() {
            button.frame = AddressToolbarLayout.trailingButton(i, in: bounds)
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
        let area = AddressToolbarLayout.address(in: bounds)
        address.frame = area
        let text = pill.toolbarText ?? pill.host ?? pill.text
        host.stringValue = text ?? Copy.urlPlaceholder
        host.textColor = NSColor(white: 0, alpha: text == nil ? Draw.toolbarDisabledAlpha.value : Draw.toolbarTextAlpha.value)
        address.toolTip = pill.text ?? Copy.urlPlaceholder
        link.contentTintColor = enabled
        link.isHidden = text == nil
        // The glyph and the host together are centred on the card, within the address area.
        let glyph = Draw.toolbarGlyph.value + Draw.toolbarLinkGap.value
        let textWidth = min(ceil(host.intrinsicContentSize.width), max(0, area.width - glyph))
        let total = (link.isHidden ? 0 : glyph) + textWidth
        let x = min(max(area.minX, bounds.midX - total / 2), max(area.minX, area.maxX - total))
        link.frame = CGRect(x: x, y: area.midY - Draw.toolbarGlyph.value / 2, width: Draw.toolbarGlyph.value, height: Draw.toolbarGlyph.value)
        let height = host.intrinsicContentSize.height
        host.frame = CGRect(x: x + (link.isHidden ? 0 : glyph), y: area.midY - height / 2, width: textWidth, height: height)
        let line = Draw.hairline.value
        hairline.frame = CGRect(x: 0, y: bounds.height - line, width: bounds.width, height: line)
    }

    @objc private func editAddress() { dispatch(.commandBar(.open(.editCurrent))) }
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
