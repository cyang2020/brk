import AppKit
import BrkBase
import BrkEngine

@MainActor
final class PageHandoffPlaceholder: PageSurfaceView {
    private let showHere: () -> Void

    init(page: PageID, showHere: @escaping () -> Void) {
        self.showHere = showHere
        super.init(page: page)
        let message = NSTextField(wrappingLabelWithString: "This tab is open in another window.")
        message.textColor = .secondaryLabelColor
        message.alignment = .center
        let button = NSButton(title: "Show Here", target: self, action: #selector(activateTab))
        let stack = NSStackView(views: [message, button])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
        ])
    }

    @objc private func activateTab() { showHere() }
}
