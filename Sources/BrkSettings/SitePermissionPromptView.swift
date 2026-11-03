import AppKit
import BrkBase
import BrkUIKit

/// Brk's own permission prompt, in a popover under the address: Chromium's bubble wording ("<site> wants to", one
/// line per request) and its three answers. Allow while visiting the site and Never allow are remembered for the
/// origin in this profile; Allow this time answers only this request. Closing the prompt decides nothing.
@MainActor
public final class SitePermissionPromptView: NSView {
    /// (decision, remember).
    public var answer: ((SitePermission, Bool) -> Void)?
    private let stack = NSStackView()

    public init(prompt: SitePermissionPrompt) {
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Self.spacing
        stack.edgeInsets = NSEdgeInsets(top: Self.inset, left: Self.inset, bottom: Self.inset, right: Self.inset)
        let title = NSTextField(labelWithString: Self.heading(prompt))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingMiddle
        stack.addArrangedSubview(title)
        if prompt.requestingOrigin != prompt.target.origin {
            let embedded = NSTextField(labelWithString: "Embedded in " + Self.site(prompt.target.origin))
            embedded.font = .systemFont(ofSize: 11); embedded.textColor = .secondaryLabelColor
            stack.addArrangedSubview(embedded)
        }
        for capability in SiteCapability.prompted where prompt.capabilities.contains(capability) {
            let row = NSStackView()
            row.orientation = .horizontal; row.spacing = 8
            let icon = NSImageView(image: NSImage(systemSymbolName: Self.symbol(capability), accessibilityDescription: nil) ?? NSImage())
            icon.symbolConfiguration = .init(pointSize: 13, weight: .regular)
            icon.contentTintColor = .secondaryLabelColor
            row.addArrangedSubview(icon)
            row.addArrangedSubview(NSTextField(labelWithString: Self.line(capability)))
            stack.addArrangedSubview(row)
        }
        let buttons: [(String, String, SitePermission, Bool)] = [
            ("Allow while visiting the site", "sitePermissionAllow", .allow, true),
            ("Allow this time", "sitePermissionAllowOnce", .allow, false),
            ("Never allow", "sitePermissionDeny", .deny, true),
        ]
        for (index, (text, field, decision, remember)) in buttons.enumerated() {
            let button = NSButton(title: text, target: self, action: #selector(choose(_:)))
            button.bezelStyle = .rounded
            button.tag = index
            button.identify(.settingsField(field))
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Self.inset).isActive = true
            choices.append((decision, remember))
        }
        stack.setCustomSpacing(Self.spacing * 2, after: stack.arrangedSubviews[stack.arrangedSubviews.count - buttons.count - 1])
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: Self.width),
        ])
        identify(.settingsField("sitePermissionPrompt"))
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    private var choices: [(SitePermission, Bool)] = []

    public var preferredSize: CGSize { layoutSubtreeIfNeeded(); return fittingSize }

    @objc private func choose(_ sender: NSButton) {
        let (decision, remember) = choices[sender.tag]
        answer?(decision, remember)
    }

    static let width = 320.0, inset = 16.0, spacing = 8.0

    /// "127.0.0.1:8764 wants to": the requesting site as Chromium names it (host, and the port when there is one).
    public static func heading(_ prompt: SitePermissionPrompt) -> String { site(prompt.requestingOrigin) + " wants to" }
    static func site(_ origin: SiteOrigin) -> String {
        let url = origin.url
        return (url.host ?? origin.value) + (url.port.map { ":\($0)" } ?? "")
    }

    /// Chromium's request lines.
    public static func line(_ capability: SiteCapability) -> String {
        switch capability {
        case .camera: "Use your cameras"
        case .microphone: "Use your microphones"
        case .location: "Know your location"
        case .notifications: "Show notifications"
        case .clipboard: "See text and images copied to the clipboard"
        case .midi: "Control and reprogram your MIDI devices"
        case .windowManagement: "Manage windows on all your displays"
        case .storageAccess: "Use cookies and site data on this site"
        case .sensors: "Use your motion sensors"
        case .automaticDownloads: "Download multiple files"
        case .pointerLock: "Lock and use your mouse"
        case .desktopCapture: "Share your screen"
        case .other: "Use another browser feature"
        }
    }
    static func symbol(_ capability: SiteCapability) -> String {
        switch capability {
        case .camera: "video"
        case .microphone: "mic"
        case .location: "location"
        case .notifications: "bell"
        case .clipboard: "doc.on.clipboard"
        case .midi: "pianokeys"
        case .windowManagement: "macwindow.on.rectangle"
        case .storageAccess: "externaldrive"
        case .sensors: "sensor"
        case .automaticDownloads: "arrow.down.circle"
        case .pointerLock: "cursorarrow"
        case .desktopCapture: "rectangle.on.rectangle"
        case .other: "questionmark.circle"
        }
    }
    /// The site settings' row title for a remembered choice.
    public static func title(_ capability: SiteCapability) -> String {
        switch capability {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .location: "Location"
        case .notifications: "Notifications"
        case .clipboard: "Clipboard"
        case .midi: "MIDI devices"
        case .windowManagement: "Window management"
        case .storageAccess: "Third-party storage"
        case .sensors: "Motion sensors"
        case .automaticDownloads: "Automatic downloads"
        case .pointerLock: "Mouse lock"
        case .desktopCapture: "Screen capture"
        case .other: "Other"
        }
    }
}
