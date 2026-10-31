import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

@MainActor
public final class AddressToolbarView: NSView {
    private let address = NSButton()
    private var buttons: [NSButton] = []
    private let dispatch: Dispatch
    private var loading = false

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        identify(.toolbar)
        let names = ["sidebar", "back", "forward", "reload"]
        for (i, name) in names.enumerated() {
            let button = NSButton(image: NSImage(systemSymbolName: ["sidebar.left", "chevron.left", "chevron.right", "arrow.clockwise"][i], accessibilityDescription: name)!, target: self, action: #selector(clicked(_:)))
            button.tag = i; button.isBordered = false
            button.identify(.toolbarButton(name)); button.toolTip = name.capitalized
            addSubview(button); buttons.append(button)
        }
        address.target = self; address.action = #selector(editAddress)
        address.isBordered = false; address.alignment = .left
        address.font = .systemFont(ofSize: 13)
        address.lineBreakMode = .byTruncatingMiddle
        address.wantsLayer = true; address.layer?.cornerRadius = Metrics.spaceTools.toolbarRadius.value
        address.identify(.toolbarAddress)
        addSubview(address)
        isHidden = true
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError("not used") }
    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { true }

    public func render(_ pill: URLPillSnapshot, rect: CGRect?, palette: Palette) {
        guard let rect else { isHidden = true; return }
        isHidden = false; frame = rect
        for (i, button) in buttons.enumerated() {
            button.frame = AddressToolbarLayout.button(i, in: bounds)
            button.contentTintColor = palette.color(palette.tokens.foregroundStrong)
        }
        buttons[1].isEnabled = pill.canGoBack; buttons[2].isEnabled = pill.canGoForward
        buttons[3].isEnabled = pill.text != nil
        loading = pill.loading
        buttons[3].image = NSImage(systemSymbolName: loading ? "xmark" : "arrow.clockwise", accessibilityDescription: loading ? "Stop" : "Reload")
        buttons[3].toolTip = loading ? "Stop" : "Reload"
        address.frame = AddressToolbarLayout.address(in: bounds)
        address.title = pill.toolbarText ?? pill.text ?? Copy.urlPlaceholder
        address.toolTip = address.title
        address.contentTintColor = palette.color(palette.tokens.foregroundStrong)
        address.layer?.backgroundColor = palette.color(palette.tokens.itemBackground).cgColor
    }
    @objc private func editAddress() { dispatch(.commandBar(.open(.editCurrent))) }
    @objc private func clicked(_ sender: NSButton) {
        switch sender.tag {
        case 0: dispatch(.sidebar(.toggle))
        case 1: dispatch(.page(.back(.focused)))
        case 2: dispatch(.page(.forward(.focused)))
        default: dispatch(loading ? .page(.stop(.focused)) : .page(.reload(.focused, ignoringCache: NSEvent.modifierFlags.contains(.option))))
        }
    }
}
