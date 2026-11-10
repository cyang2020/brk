import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import QuickLookUI

/// Arc's preview of a Library item (`HomeBadging.ItemPreviewPresenter`, opened by a click on a flyout row): the window
/// dims, a card over its middle shows the file through Quick Look, and the card's toolbar holds ×, ‹ ›, the name and its
/// age, a … menu and "Open in <app> ↗". Esc, × or a click on the dimmed window closes it. Measured on Arc 1.170
/// (verify/library-hover-preview/README.md, p15 and p16).
@MainActor
final class LibraryItemPreviewView: NSView {
    private let dispatch: Dispatch
    private let dim = NSView()
    private let card = NSView()
    private let toolbar = NSView()
    private let close = NSButton()
    private let previous = NSButton()
    private let next = NSButton()
    private let name = NSTextField(labelWithString: "")
    private let age = NSTextField(labelWithString: "")
    private let more = NSButton()
    private let openIn = NSButton()
    private var preview: QLPreviewView?
    private let imageView = NSImageView()
    private var item: LibraryFlyoutItem?
    private var sequence: [LibraryItemKey] = []
    private var keys: Any?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        identify(.tabTool("library-item-preview"))
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor(white: 0, alpha: Metrics.libraryFlyout.previewDim.value).cgColor
        addSubview(dim)
        card.wantsLayer = true
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor(white: Metrics.libraryFlyout.previewCardWhite.value, alpha: 1).cgColor
        addSubview(card)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        card.addSubview(imageView)
        toolbar.wantsLayer = true
        card.addSubview(toolbar)
        for (button, symbol, tip) in [(close, "xmark", "Close"), (previous, "chevron.left", "Previous"), (next, "chevron.right", "Next"), (more, "ellipsis", "More")] {
            button.isBordered = false
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
                .withSymbolConfiguration(.init(pointSize: Metrics.libraryFlyout.previewGlyph.value, weight: .semibold))
            button.contentTintColor = NSColor(white: 0, alpha: 0.85)
            button.toolTip = tip
            button.target = self
            toolbar.addSubview(button)
        }
        close.action = #selector(closePreview)
        previous.action = #selector(showPrevious)
        next.action = #selector(showNext)
        more.action = #selector(showMenu)
        close.identify(.tabTool("library-item-preview-close"))
        name.font = .systemFont(ofSize: Metrics.libraryFlyout.titleFont.value, weight: .semibold)
        name.textColor = NSColor(white: 0, alpha: 0.85)
        age.font = .systemFont(ofSize: Metrics.libraryFlyout.titleFont.value)
        age.textColor = NSColor(white: 0, alpha: 0.45)
        for label in [name, age] { label.lineBreakMode = .byTruncatingTail; toolbar.addSubview(label) }
        openIn.isBordered = false
        openIn.wantsLayer = true
        openIn.layer?.cornerCurve = .continuous
        openIn.layer?.backgroundColor = NSColor(white: 0, alpha: 0.06).cgColor
        openIn.font = .systemFont(ofSize: Metrics.libraryFlyout.titleFont.value, weight: .semibold)
        openIn.contentTintColor = NSColor(white: 0, alpha: 0.85)
        openIn.target = self
        openIn.action = #selector(openInApp)
        openIn.identify(.tabTool("library-item-preview-open"))
        toolbar.addSubview(openIn)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func render(_ item: LibraryFlyoutItem?, sequence: [LibraryItemKey], now: Instant) {
        self.sequence = sequence
        guard let item else {
            if !isHidden { isHidden = true; preview?.previewItem = nil; stopKeys() }
            self.item = nil
            return
        }
        let changed = item.key != self.item?.key || item.file != self.item?.file
        self.item = item
        isHidden = false
        startKeys()
        name.stringValue = item.title
        age.stringValue = LibraryPreviewCopy.relative(item.date, now: now)
        let index = sequence.firstIndex(of: item.key)
        // The rows run oldest to newest up the flyout; ‹ goes to the newer item, › to the older one (Arc greys › on
        // the oldest row's item).
        previous.isEnabled = (index ?? 0) > 0
        next.isEnabled = index.map { $0 + 1 < sequence.count } ?? false
        let app = item.file.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        openIn.title = "Open in " + (app.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? "Finder") + " ↗"
        if changed { show(item) }
        needsLayout = true
    }

    private func show(_ item: LibraryFlyoutItem) {
        guard let file = item.file else { imageView.image = nil; preview?.isHidden = true; return }
        if case .capture = item.content {
            imageView.image = NSImage(contentsOf: file)
            imageView.isHidden = false
            preview?.isHidden = true
            return
        }
        imageView.isHidden = true
        if preview == nil, let view = QLPreviewView(frame: .zero, style: .compact) {
            view.autostarts = true
            view.shouldCloseWithWindow = false
            card.addSubview(view, positioned: .below, relativeTo: toolbar)
            preview = view
        }
        preview?.isHidden = false
        preview?.previewItem = file as NSURL
    }

    override func layout() {
        super.layout()
        let m = Metrics.libraryFlyout
        dim.frame = bounds
        let insets = m.previewInsets.value
        let rect = bounds.insetBy(dx: (bounds.width * insets[0]).rounded(), dy: (bounds.height * insets[1]).rounded())
        card.frame = rect
        card.layer?.cornerRadius = m.previewRadius.value
        let bar = m.previewToolbar.value
        toolbar.frame = CGRect(x: 0, y: 0, width: rect.width, height: bar)
        toolbar.layer?.backgroundColor = NSColor(srgbRed: 0.973, green: 0.973, blue: 0.973, alpha: 0.66).cgColor
        let content = CGRect(x: 0, y: bar, width: rect.width, height: rect.height - bar).insetBy(dx: m.previewPadding.value, dy: m.previewPadding.value)
        imageView.frame = content
        preview?.frame = content
        let glyph = m.previewButton.value
        for (button, x) in [(close, m.previewButtons.value[0]), (previous, m.previewButtons.value[1]), (next, m.previewButtons.value[2])] {
            button.frame = CGRect(x: x - glyph / 2, y: (bar - glyph) / 2, width: glyph, height: glyph)
        }
        name.sizeToFit()
        name.frame.origin = CGPoint(x: m.previewButtons.value[3], y: (bar - name.frame.height) / 2)
        age.sizeToFit()
        age.frame.origin = CGPoint(x: name.frame.maxX + m.previewNameGap.value, y: (bar - age.frame.height) / 2)
        openIn.sizeToFit()
        let openWidth = openIn.frame.width + 2 * m.previewOpenPadding.value
        openIn.frame = CGRect(x: rect.width - m.previewOpenTrailing.value - openWidth, y: (bar - m.previewOpenHeight.value) / 2,
                              width: openWidth, height: m.previewOpenHeight.value)
        openIn.layer?.cornerRadius = m.previewOpenRadius.value
        more.frame = CGRect(x: openIn.frame.minX - m.previewMoreGap.value - glyph / 2, y: (bar - glyph) / 2, width: glyph, height: glyph)
    }

    // A click on the dimmed window closes the preview; the card keeps its own clicks.
    override func mouseDown(with event: NSEvent) {
        if !card.frame.contains(convert(event.locationInWindow, from: nil)) { closePreview() }
    }

    private func startKeys() {
        guard keys == nil else { return }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            guard code == 53 || code == 123 || code == 124 else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, !self.isHidden, self.window?.isKeyWindow == true else { return false }
                switch code {
                case 53: self.closePreview()
                case 123: self.showPrevious()
                default: self.showNext()
                }
                return true
            }
            return handled ? nil : event
        }
    }

    private func stopKeys() {
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
    }

    @objc private func closePreview() { dispatch(.library(.flyout(.preview(nil)))) }

    @objc private func showPrevious() { step(-1) }
    @objc private func showNext() { step(1) }

    private func step(_ by: Int) {
        guard let item, let index = sequence.firstIndex(of: item.key), sequence.indices.contains(index + by) else { return }
        dispatch(.library(.flyout(.preview(sequence[index + by]))))
    }

    @objc private func openInApp() {
        guard let file = item?.file else { return }
        NSWorkspace.shared.open(file)
    }

    @objc private func showMenu() {
        guard let file = item?.file else { return }
        let menu = NSMenu()
        let reveal = NSMenuItem(title: "Show in Finder", action: #selector(revealFile), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = file
        menu.addItem(reveal)
        menu.popUp(positioning: nil, at: CGPoint(x: more.frame.minX, y: more.frame.maxY), in: toolbar)
    }

    @objc private func revealFile(_ sender: NSMenuItem) {
        if let file = sender.representedObject as? URL { NSWorkspace.shared.activateFileViewerSelecting([file]) }
    }
}

enum LibraryPreviewCopy {
    /// "2 minutes ago" beside the name, as the flyout's rows read it.
    static func relative(_ date: Instant, now: Instant) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        formatter.locale = Locale(identifier: "en_US")
        return formatter.localizedString(fromTimeInterval: -max(1, Double(now.since(date).components.seconds)))
    }
}
