import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Window-scoped transient feedback. The transparent host never intercepts page input.
@MainActor
final class TabToolsOverlayView: NSView {
    private let dispatch: Dispatch
    private let recent = NSView()
    private let toast = NSButton(title: "", target: nil, action: nil)
    private let education = NSButton(title: "", target: nil, action: nil)
    private let outputStatus = NSTextField(labelWithString: "")
    private var outputTask: Task<Void, Never>?
    private var lastOutput: OutputUpdate?
    private var lastExport: ExportOutcome?
    private var toastTask: Task<Void, Never>?
    private var toastExpiry: Instant?
    private var labels: [NSTextField] = []

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        for view in [recent, toast, education, outputStatus] as [NSView] { addSubview(view) }
        outputStatus.isHidden = true
        outputStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        outputStatus.lineBreakMode = .byTruncatingMiddle
        outputStatus.wantsLayer = true
        outputStatus.layer?.cornerRadius = 6
        recent.identify(.tabTool("switcher"))
        toast.identify(.tabTool("toast"))
        education.identify(.tabTool("education"))
        recent.wantsLayer = true
        recent.layer?.cornerRadius = Metrics.content.cornerRadius.value
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
                output: OutputUpdate? = nil, exported: ExportOutcome? = nil) {
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
        if let switcher = tools.recent {
            labels.forEach { $0.removeFromSuperview() }
            labels = []
            let at = switcher.items.firstIndex { $0.id == switcher.selected } ?? 0
            let shown = Array(switcher.items.dropFirst(max(0, at - 5)).prefix(12))
            let width = min(440.0, max(220.0, bounds.width - 48))
            let height = Double(shown.count) * 38 + 24
            recent.frame = NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
            recent.layer?.backgroundColor = palette.color(palette.tokens.itemBackground).cgColor
            for (i, item) in shown.enumerated() {
                let label = NSTextField(labelWithString: (item.id == switcher.selected ? "› " : "  ") + item.title)
                label.font = .systemFont(ofSize: 14, weight: item.id == switcher.selected ? .semibold : .regular)
                label.textColor = palette.color(palette.tokens.foregroundStrong)
                label.lineBreakMode = .byTruncatingMiddle
                label.frame = NSRect(x: 16, y: Double(shown.count - i - 1) * 38 + 12, width: width - 32, height: 26)
                recent.addSubview(label)
                labels.append(label)
            }
        }
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
        toast.isHidden = tools.toast == nil
        toast.title = tools.toast.map { $0.text + "   ×" } ?? ""
        toast.sizeToFit()
        toast.frame.origin = NSPoint(x: (bounds.width - toast.frame.width) / 2, y: bounds.height - 58)
        education.isHidden = true
        education.title = tools.archiveEducation.map { $0 + "  ×" } ?? ""
        education.cell?.wraps = true
        education.frame = NSRect(x: 8, y: bounds.height - 130, width: max(0, sidebarWidth - 16), height: 68)
    }
    @objc private func dismissToast() { dispatch(.tabTools(.dismissToast)) }
    @objc private func dismissEducation() { dispatch(.tabTools(.dismissArchiveEducation)) }
}
