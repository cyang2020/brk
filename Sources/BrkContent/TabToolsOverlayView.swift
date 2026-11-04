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
    private let toast = ToastView(frame: .zero)
    private var toastCommand: Command?
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
        education.identify(.tabTool("education-overlay"))
        toast.onClick = { [weak self] in self?.dispatch(.tabTools(.dismissToast)) }
        toast.onAction = { [weak self] in if let command = self?.toastCommand { self?.dispatch(command) } }
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
                output: OutputUpdate? = nil, exported: ExportOutcome? = nil, contentArea: CGRect? = nil, thumbnails: [ItemID: NSImage] = [:]) {
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
                let seconds = tools.toast?.keycap == nil ? 4.0 : 5.0
                toastTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled, let self, self.toastExpiry == expiry else { return }
                    self.dispatch(.tabTools(.dismissToast))
                }
            }
        }
        toastCommand = tools.toast?.action?.command
        // A notice with a way out is Arc's notice banner (P43-a); any other toast is Arc's toast (P15). Both sit at the
        // top-right corner of the content area, overlapping the window margin above the card.
        let notice = tools.toast?.link != nil ? tools.toast : nil
        let right = contentArea?.maxX ?? bounds.width - Metrics.content.inset.value
        toast.isHidden = tools.toast == nil || notice != nil
        if let snapshot = tools.toast, notice == nil {
            toast.render(snapshot)
            let size = toast.fittingSize
            toast.frame = CGRect(x: right - size.width, y: ToastDraw.top.value, width: size.width, height: size.height)
        }
        banner.isHidden = notice == nil
        if let notice, let link = notice.link { banner.show(notice.text, link: link, right: right, top: ToastDraw.top.value) }
        education.isHidden = true
        education.title = tools.archiveEducation.map(Copy.archiveEducation) ?? ""
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
        body.layer?.cornerRadius = NoticeMetrics.radius.value
        body.layer?.borderWidth = 0.5
        // The toast's surface (P15-c: #EEFBFC with a #AFB9B9 edge); P43-a samples #E7F7F7 to #F0FDFD inside the banner.
        body.layer?.borderColor = NSColor(srgbRed: 0xAF / 255.0, green: 0xB9 / 255.0, blue: 0xB9 / 255.0, alpha: 1).cgColor
        body.layer?.backgroundColor = NSColor(srgbRed: 0xEE / 255.0, green: 0xFB / 255.0, blue: 0xFC / 255.0, alpha: 1).cgColor
        body.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
            shadow.shadowBlurRadius = 12
            shadow.shadowOffset = NSSize(width: 0, height: -3)
            return shadow
        }()
        text.font = .systemFont(ofSize: NoticeMetrics.fontSize.value, weight: .medium)
        text.textColor = NSColor.black.withAlphaComponent(0.88)
        link.isBordered = false
        link.wantsLayer = true
        link.layer?.cornerRadius = NoticeMetrics.linkRadius.value
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
            .font: NSFont.systemFont(ofSize: NoticeMetrics.linkFontSize.value, weight: .medium), .foregroundColor: NSColor.black.withAlphaComponent(0.85),
        ])
        let textSize = CGSize(width: ceil(text.intrinsicContentSize.width) + 4, height: text.intrinsicContentSize.height)
        let pad = NoticeMetrics.padding.value
        let bodySize = CGSize(width: textSize.width + 2 * pad, height: NoticeMetrics.height.value)
        let linkSize = CGSize(width: ceil(self.link.intrinsicContentSize.width) + 14, height: NoticeMetrics.linkHeight.value)
        let size = CGSize(width: bodySize.width, height: bodySize.height + 2 + linkSize.height)
        frame = CGRect(x: right - size.width, y: top, width: size.width, height: size.height)
        body.frame = CGRect(origin: .zero, size: bodySize)
        text.frame = CGRect(x: pad, y: ((bodySize.height - textSize.height) / 2).rounded(), width: textSize.width, height: textSize.height)
        self.link.frame = CGRect(x: size.width - linkSize.width - 8, y: bodySize.height + 2, width: linkSize.width, height: linkSize.height)
    }

    @objc private func follow() { if let command { onLink(command) } }
}

/// Arc's toast (P15-a, P15-c): a near-white rounded strip with a hairline and a soft shadow, black text, and for undo
/// toasts a grey key cap ("Cleared Tabs! Use [⌘Z] to undo"). A click dismisses it.
@MainActor
final class ToastView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let cap = NSTextField(labelWithString: "")
    private let capBackground = NSView()
    private let trailing = NSTextField(labelWithString: "")
    /// Arc's "Screenshot Copied to Clipboard" · Save (P33-d): a white bordered button at the end of the toast.
    private let actionBox = NSView()
    private let actionLabel = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?
    var onAction: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let m = ToastDraw
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = m.radius.value
        layer?.backgroundColor = NSColor(srgbRed: 0xEE / 255, green: 0xFB / 255, blue: 0xFC / 255, alpha: 1).cgColor
        layer?.borderColor = NSColor(srgbRed: 0xAF / 255, green: 0xB9 / 255, blue: 0xB9 / 255, alpha: 1).cgColor
        layer?.borderWidth = m.border.value
        shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor(white: 0, alpha: m.shadowAlpha.value)
            s.shadowBlurRadius = m.shadowBlur.value
            s.shadowOffset = CGSize(width: 0, height: -m.shadowBlur.value / 3)
            return s
        }()
        capBackground.wantsLayer = true
        capBackground.layer?.cornerCurve = .continuous
        capBackground.layer?.cornerRadius = m.capRadius.value
        capBackground.layer?.backgroundColor = NSColor(srgbRed: 0xD8 / 255, green: 0xE4 / 255, blue: 0xE5 / 255, alpha: 1).cgColor
        for field in [label, trailing] { field.font = .systemFont(ofSize: m.font.value, weight: .medium); field.textColor = .black }
        cap.font = .systemFont(ofSize: m.font.value, weight: .semibold)
        cap.textColor = .black
        cap.alignment = .center
        actionBox.wantsLayer = true
        actionBox.layer?.cornerCurve = .continuous
        actionBox.layer?.cornerRadius = m.capRadius.value
        actionBox.layer?.backgroundColor = NSColor.white.cgColor
        actionBox.layer?.borderColor = NSColor(srgbRed: 0xC9 / 255, green: 0xD2 / 255, blue: 0xD3 / 255, alpha: 1).cgColor
        actionBox.layer?.borderWidth = 1
        actionBox.identify(.tabTool("toast-action"))
        actionLabel.font = .systemFont(ofSize: m.font.value, weight: .semibold)
        actionLabel.textColor = .black
        actionLabel.alignment = .center
        for view in [label, capBackground, cap, trailing, actionBox, actionLabel] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) && !isHidden ? self : nil }
    override func mouseDown(with event: NSEvent) {
        if !actionBox.isHidden, actionBox.frame.contains(convert(event.locationInWindow, from: nil)) { onAction?() } else { onClick?() }
    }

    func render(_ toast: ToastSnapshot) {
        label.stringValue = toast.text
        cap.stringValue = toast.keycap ?? ""
        trailing.stringValue = toast.trailing ?? ""
        cap.isHidden = toast.keycap == nil
        capBackground.isHidden = toast.keycap == nil
        trailing.isHidden = toast.trailing == nil
        actionLabel.stringValue = toast.action?.title ?? ""
        actionBox.isHidden = toast.action == nil
        actionLabel.isHidden = toast.action == nil
        needsLayout = true
    }

    override var fittingSize: NSSize {
        let m = ToastDraw
        var width = m.padding.value * 2 + ceil(label.intrinsicContentSize.width)
        if !cap.isHidden { width += m.gap.value + capWidth }
        if !trailing.isHidden { width += m.gap.value + ceil(trailing.intrinsicContentSize.width) }
        if !actionBox.isHidden { width += m.gap.value + actionWidth - m.padding.value + m.actionInset.value }
        return NSSize(width: width, height: m.height.value)
    }

    private var actionWidth: Double { ceil(actionLabel.intrinsicContentSize.width) + 2 * m.actionPadding.value }
    private var m: ToastMetrics { ToastDraw }
    private var capWidth: Double { max(ToastDraw.capMinWidth.value, ceil(cap.intrinsicContentSize.width) + 2 * ToastDraw.capPadding.value) }

    override func layout() {
        super.layout()
        let m = ToastDraw, mid = bounds.midY
        var x = m.padding.value
        func place(_ field: NSTextField) {
            let size = field.intrinsicContentSize
            field.frame = CGRect(x: x, y: mid - size.height / 2, width: ceil(size.width), height: size.height)
            x = field.frame.maxX + m.gap.value
        }
        place(label)
        if !cap.isHidden {
            capBackground.frame = CGRect(x: x, y: mid - m.capHeight.value / 2, width: capWidth, height: m.capHeight.value)
            let size = cap.intrinsicContentSize
            cap.frame = CGRect(x: capBackground.frame.minX, y: mid - size.height / 2, width: capWidth, height: size.height)
            x = capBackground.frame.maxX + m.gap.value
        }
        if !trailing.isHidden { place(trailing) }
        if !actionBox.isHidden {
            actionBox.frame = CGRect(x: x, y: mid - m.actionHeight.value / 2, width: actionWidth, height: m.actionHeight.value)
            let size = actionLabel.intrinsicContentSize
            actionLabel.frame = CGRect(x: actionBox.frame.minX, y: mid - size.height / 2, width: actionWidth, height: size.height)
        }
    }
}

let ToastDraw = ToastMetrics()

struct ToastMetrics: MetricGroup {
    let top = Metric(4.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P15-c: Arc's toast spans y 4 to 50.5 at the content area's top-right"))
    let height = Metric(46.5, .anatomy("verify/visual-pairs/run-20261103/results.tsv P15-c: the toast is 46.5 tall"))
    let padding = Metric(13.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P15-c: the text starts 13 in from the toast's left edge"))
    let gap = Metric(8.0, .guess("space between the toast's text, key cap and trailing text"))
    let font = Metric(14.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P15-c: Space deleted! Use is about 121 wide"))
    let radius = Metric(12.0, .guess("toast corner radius; P15 shows rounded corners like the URL pill's"))
    let border = Metric(0.5, .anatomy("verify/visual-pairs/run-20261103/results.tsv P15-c: a 1 px #AFB9B9 edge"))
    let shadowBlur = Metric(12.0, .guess("soft popover shadow under the toast"))
    let shadowAlpha = Metric(0.12, .guess("the toast's shadow is faint in P15"))
    let actionHeight = Metric(32.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P33-d: the toast's Save button, 64 px tall"))
    let actionPadding = Metric(12.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P33-d: Save sits 24 px in from its button's edges"))
    let actionInset = Metric(7.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P33-d: the Save button ends 14 px before the toast's right edge"))
    let capHeight = Metric(26.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P15-c: the ⌘Z key cap is 36 x 26"))
    let capMinWidth = Metric(36.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P15-c: the ⌘Z key cap is 36 x 26"))
    let capPadding = Metric(7.0, .guess("side padding inside the key cap for longer shortcuts"))
    let capRadius = Metric(7.0, .guess("key cap corner radius"))
}
