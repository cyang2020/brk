import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Window-scoped transient feedback. The transparent host never intercepts page input.
@MainActor
final class TabToolsOverlayView: NSView {
    private let dispatch: Dispatch
    private let recent = TabSwitcherView()
    private let toast = NSButton(title: "", target: nil, action: nil)
    private let banner = NoticeBanner()
    private let education = NSButton(title: "", target: nil, action: nil)
    private let outputStatus = NSTextField(labelWithString: "")
    private var outputTask: Task<Void, Never>?
    private var lastOutput: OutputUpdate?
    private var lastExport: ExportOutcome?
    private var toastTask: Task<Void, Never>?
    private var toastExpiry: Instant?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        for view in [recent, toast, banner, education, outputStatus] as [NSView] { addSubview(view) }
        banner.isHidden = true
        banner.onLink = { [weak self] command in
            self?.dispatch(.tabTools(.dismissToast))
            self?.dispatch(command)
        }
        outputStatus.isHidden = true
        outputStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        outputStatus.lineBreakMode = .byTruncatingMiddle
        outputStatus.wantsLayer = true
        outputStatus.layer?.cornerRadius = Metrics.content.cornerRadius.value
        recent.identify(.tabTool("switcher"))
        toast.identify(.tabTool("toast"))
        banner.identify(.tabTool("notice"))
        education.identify(.tabTool("education"))
        toast.target = self
        toast.action = #selector(dismissToast)
        education.target = self
        education.action = #selector(dismissEducation)
        education.font = .systemFont(ofSize: 11)
        education.toolTip = "Click to dismiss this auto-archive explanation"
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self || hit === outputStatus ? nil : hit
    }
    func render(_ tools: TabToolsSnapshot, sidebarWidth: Double, palette: Palette,
                output: OutputUpdate? = nil, exported: ExportOutcome? = nil, thumbnails: [ItemID: NSImage] = [:]) {
        let active = output.map { if case .terminal = $0.stage { false } else { true } } ?? false
        if output != lastOutput || exported != lastExport {
            outputTask?.cancel()
            lastOutput = output; lastExport = exported
            outputStatus.stringValue = exported?.message ?? output?.message ?? ""
            outputStatus.toolTip = outputStatus.stringValue
            outputStatus.isHidden = outputStatus.stringValue.isEmpty
            if !active {
                outputTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    self?.outputStatus.isHidden = true
                }
            }
        }
        outputStatus.textColor = palette.color(palette.tokens.foregroundStrong)
        outputStatus.layer?.backgroundColor = palette.color(palette.tokens.itemBackground).cgColor
        let statusWidth = min(440.0, max(0, bounds.width - 48))
        outputStatus.frame = NSRect(x: (bounds.width - statusWidth) / 2, y: bounds.height - (tools.toast == nil ? 54 : 94), width: statusWidth, height: 28)
        recent.isHidden = tools.recent == nil
        if let switcher = tools.recent { recent.render(switcher, in: bounds, palette: palette, thumbnails: thumbnails) }
        if toastExpiry != tools.toast?.expiresAt {
            toastTask?.cancel()
            toastExpiry = tools.toast?.expiresAt
            if let expiry = toastExpiry {
                toastTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled, let self, self.toastExpiry == expiry else { return }
                    self.dispatch(.tabTools(.dismissToast))
                }
            }
        }
        // A notice with a link is Arc's top-right banner (P43-a); a plain one stays the bottom toast.
        let notice = tools.toast?.link != nil ? tools.toast : nil
        toast.isHidden = tools.toast == nil || notice != nil
        toast.title = tools.toast.map { $0.text + "   ×" } ?? ""
        toast.sizeToFit()
        toast.frame.origin = NSPoint(x: (bounds.width - toast.frame.width) / 2, y: bounds.height - 58)
        banner.isHidden = notice == nil
        if let notice, let link = notice.link { banner.show(notice.text, link: link, right: bounds.width - 12, top: 6) }
        education.isHidden = true
        education.title = tools.archiveEducation.map { $0 + "  ×" } ?? ""
        education.cell?.wraps = true
        education.frame = NSRect(x: 8, y: bounds.height - 130, width: max(0, sidebarWidth - 16), height: 68)
    }
    @objc private func dismissToast() { dispatch(.tabTools(.dismissToast)) }
    @objc private func dismissEducation() { dispatch(.tabTools(.dismissArchiveEducation)) }
}

/// Arc's notice at the window's top right (P43-a, "ChatGPT in the Command Bar not enabled"): a pale rounded banner
/// with the message and, under its right end, a small link ("Arc Max Preferences ↗") that runs its command.
@MainActor
final class NoticeBanner: NSView {
    var onLink: (Command) -> Void = { _ in }
    private let body = NSView()
    private let text = NSTextField(labelWithString: "")
    private let link = NSButton(title: "", target: nil, action: nil)
    private var command: Command?

    init() {
        super.init(frame: .zero)
        body.wantsLayer = true
        body.layer?.cornerCurve = .continuous
        body.layer?.cornerRadius = 12
        body.layer?.borderWidth = 0.5
        body.layer?.borderColor = NSColor.black.withAlphaComponent(0.25).cgColor
        // P43-a samples #E7F7F7 to #F0FDFD inside the banner.
        body.layer?.backgroundColor = NSColor(srgbRed: 0xEC / 255.0, green: 0xF9 / 255.0, blue: 0xF9 / 255.0, alpha: 0.97).cgColor
        body.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
            shadow.shadowBlurRadius = 12
            shadow.shadowOffset = NSSize(width: 0, height: -3)
            return shadow
        }()
        text.font = .systemFont(ofSize: 15, weight: .medium)
        text.textColor = NSColor.black.withAlphaComponent(0.88)
        link.isBordered = false
        link.wantsLayer = true
        link.layer?.cornerRadius = 6
        link.layer?.backgroundColor = NSColor(srgbRed: 0xE3 / 255.0, green: 0xEF / 255.0, blue: 0xEF / 255.0, alpha: 1).cgColor
        link.target = self
        link.action = #selector(follow)
        body.addSubview(text)
        addSubview(body)
        addSubview(link)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func show(_ message: String, link: ToastLink, right: Double, top: Double) {
        command = link.command
        text.stringValue = message
        self.link.attributedTitle = NSAttributedString(string: link.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.black.withAlphaComponent(0.85),
        ])
        let textSize = CGSize(width: ceil(text.intrinsicContentSize.width) + 4, height: text.intrinsicContentSize.height)
        let bodySize = CGSize(width: textSize.width + 32, height: 42)
        let linkSize = CGSize(width: ceil(self.link.intrinsicContentSize.width) + 14, height: 20)
        let size = CGSize(width: bodySize.width, height: bodySize.height + 2 + linkSize.height)
        frame = CGRect(x: right - size.width, y: top, width: size.width, height: size.height)
        body.frame = CGRect(origin: .zero, size: bodySize)
        text.frame = CGRect(x: 16, y: ((bodySize.height - textSize.height) / 2).rounded(), width: textSize.width, height: textSize.height)
        self.link.frame = CGRect(x: size.width - linkSize.width - 8, y: bodySize.height + 2, width: linkSize.width, height: linkSize.height)
    }

    @objc private func follow() { if let command { onLink(command) } }
}
