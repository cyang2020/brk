import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

@MainActor final class MediaPageView: NSView {
    private let dispatch: Dispatch
    private let title = NSTextField(labelWithString: "Media")
    private let detail = NSTextField(labelWithString: "")
    private let image = NSImageView()
    private let scroll = NSScrollView()
    private let list = CaptureListDocument()
    private var records: [CaptureRecord] = []
    private var files: [String: URL] = [:]
    private var selected: CaptureRecord?
    private var buttons: [NSButton] = []
    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        title.font = .systemFont(ofSize: LibraryDraw.list.titleFontSize.value, weight: .bold)
        detail.lineBreakMode = .byTruncatingMiddle
        detail.font = .systemFont(ofSize: LibraryDraw.list.detailFont.value)
        image.imageScaling = .scaleProportionallyUpOrDown
        scroll.documentView = list; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        for view in [title, detail, image, scroll] { addSubview(view) }
        for (label, selector, name) in [("Open", #selector(open), "open"), ("Export…", #selector(export), "export"), ("Remove", #selector(remove), "remove"), ("Insert in Easel", #selector(insert), "easel")] {
            let button = NSButton(title: label, target: self, action: selector); button.bezelStyle = .rounded
            button.identify(.tabTool("capture-" + name)); buttons.append(button); addSubview(button)
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    func hide() { isHidden = true; image.image = nil; records = []; files = [:]; selected = nil; list.subviews.forEach { $0.removeFromSuperview() } }
    func show(_ library: LibrarySnapshot, in rect: CGRect, scheme: Scheme) {
        frame = rect; isHidden = false
        let colors = LibraryColors.of(scheme)
        layer?.backgroundColor = colors.page.cgColor; title.textColor = colors.foregroundPrimary; detail.textColor = colors.foregroundSecondary
        records = library.captures; files = library.captureFiles
        selected = records.first { $0.id == library.capturePreview } ?? records.first
        image.image = selected.flatMap { files[$0.id] }.flatMap { NSImage(contentsOf: $0) }
        if let selected { detail.stringValue = "\(selected.title) · \(selected.width) × \(selected.height) · \(selected.url.host ?? "")" }
        else { detail.stringValue = "Capture an area, a full page or a portrait to add it here. Private captures stay in memory." }
        if let message = library.captureMessage { detail.stringValue = message }
        for button in buttons { button.isEnabled = selected != nil }
        list.subviews.forEach { $0.removeFromSuperview() }
        for record in records {
            let button = NSButton(title: "\(record.title)\n\(record.width) × \(record.height)", target: self, action: #selector(choose(_:)))
            button.bezelStyle = .rounded; button.image = files[record.id].flatMap { NSImage(contentsOf: $0) }; button.imagePosition = .imageLeft
            button.imageScaling = .scaleProportionallyDown; button.toolTip = record.title
            button.identifier = NSUserInterfaceItemIdentifier(record.id)
            button.image?.size = NSSize(width:60,height:44)
            list.addSubview(button)
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let m = LibraryDraw.list.padding.value, gap = LibraryDraw.list.gap.value
        title.frame = CGRect(x:m,y:m,width:bounds.width-m*2,height:40)
        detail.frame = CGRect(x:m,y:title.frame.maxY+gap,width:bounds.width-m*2,height:30)
        scroll.frame = CGRect(x:m,y:detail.frame.maxY+gap,width:220,height:max(0,bounds.height-detail.frame.maxY-m*2))
        list.frame = CGRect(x:0,y:0,width:scroll.contentSize.width,height:max(scroll.contentSize.height,CGFloat(records.count)*72))
        for (index,row) in list.subviews.enumerated() { row.frame = CGRect(x:0,y:CGFloat(index)*72,width:scroll.contentSize.width-12,height:60) }
        let x = scroll.frame.maxX + gap
        image.frame = CGRect(x:x,y:detail.frame.maxY+gap,width:max(0,bounds.width-x-m),height:max(0,bounds.height-detail.frame.maxY-m-60))
        var bx = x
        for button in buttons { let width = button.fittingSize.width; button.frame = CGRect(x:bx,y:bounds.height-m-30,width:width,height:30); bx += width+gap }
    }
    @objc private func choose(_ sender: NSButton) { if let id = sender.identifier?.rawValue { dispatch(.capture(.preview(id))) } }
    @objc private func open() { if let selected, let url = files[selected.id] { NSWorkspace.shared.open(url) } }
    @objc private func export() { if let selected { dispatch(.capture(.export(selected.id))) } }
    @objc private func remove() { if let selected { dispatch(.capture(.remove(selected.id))) } }
    @objc private func insert() { if let selected { dispatch(.capture(.insertInEasel(selected.id))) } }
}

@MainActor private final class CaptureListDocument: NSView { override var isFlipped: Bool { true } }
