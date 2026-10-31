import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

@MainActor
final class SpacesPageView: NSView, NSSearchFieldDelegate {
    private let dispatch: Dispatch
    private let title = NSTextField(labelWithString: "Spaces")
    private let search = NSSearchField()
    private let create = NSButton(title: "New Space…", target: nil, action: nil)
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let scroll = NSScrollView()
    private let grid = SpacesGridView()
    private var cards: [SpaceID: SpaceManagerCard] = [:]
    private var snapshot: LibrarySnapshot?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        identify(.spaceToolsControl("manager"))
        wantsLayer = true
        layer?.cornerRadius = Metrics.content.cornerRadius.value
        title.font = .systemFont(ofSize: LibraryDraw.list.titleFontSize.value, weight: .bold)
        search.placeholderString = "Search spaces or profiles"; search.delegate = self
        search.identify(.spaceToolsControl("manager-search"))
        create.target = self; create.action = #selector(newSpace); create.bezelStyle = .rounded
        create.identify(.spaceToolsControl("manager-new"))
        feedback.font = .systemFont(ofSize: LibraryDraw.list.detailFont.value)
        feedback.textColor = .secondaryLabelColor
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.documentView = grid
        for view in [title, search, create, feedback, scroll] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    func show(_ library: LibrarySnapshot, in rect: CGRect, scheme: Scheme) {
        isHidden = false; frame = rect; snapshot = library
        appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        layer?.backgroundColor = LibraryColors.of(scheme).page.cgColor
        create.isEnabled = library.canManageSpaces
        search.isEnabled = library.canManageSpaces
        feedback.stringValue = !library.canManageSpaces ? "Open Spaces in a standard window to manage saved spaces." : (library.spaceExportMessage ?? (library.spaceExportInProgress ? "Choose an export folder…" : ""))
        rebuild()
    }
    func hide() { isHidden = true; snapshot = nil; search.stringValue = ""; for card in cards.values { card.removeFromSuperview() }; cards = [:] }
    func controlTextDidChange(_ obj: Notification) { rebuild() }
    override func layout() { super.layout(); place() }
    private func rebuild() {
        guard let snapshot else { return }
        let visible = snapshot.spaces.filter { search.stringValue.isEmpty || $0.title.localizedCaseInsensitiveContains(search.stringValue) || $0.profileName.localizedCaseInsensitiveContains(search.stringValue) }
        let keep = Set(visible.map(\.id))
        for (id, card) in cards where !keep.contains(id) { card.removeFromSuperview(); cards[id] = nil }
        for row in visible {
            let card = cards[row.id] ?? SpaceManagerCard(dispatch: dispatch)
            if cards[row.id] == nil { cards[row.id] = card; grid.addSubview(card) }
            let index = snapshot.spaces.firstIndex { $0.id == row.id } ?? 0
            card.render(row, index: index, count: snapshot.spaces.count, exportBusy: snapshot.spaceExportInProgress)
        }
        grid.order = visible.map(\.id); place()
        if visible.isEmpty && snapshot.canManageSpaces { feedback.stringValue = "No matching spaces." }
    }
    private func place() {
        let layout = SpaceManagerLayout.compute(in: bounds, count: grid.order.count)
        title.frame = layout.title; create.frame = layout.create; search.frame = layout.search; feedback.frame = layout.feedback
        scroll.frame = layout.scroll; grid.frame = CGRect(origin: .zero, size: layout.gridSize)
        for (index, id) in grid.order.enumerated() { cards[id]?.frame = layout.cards[index] }
    }
    @objc private func newSpace() { dispatch(.sidebar(.openDialog(.newSpace))) }
}

private final class SpacesGridView: NSView {
    var order: [SpaceID] = []
    override var isFlipped: Bool { true }
}

@MainActor
private final class SpaceManagerCard: NSView {
    private let dispatch: Dispatch
    private let open = NSButton()
    private let detail = NSTextField(labelWithString: "")
    private let edit = NSButton(title: "Edit…", target: nil, action: nil)
    private let earlier = NSButton(title: "←", target: nil, action: nil)
    private let later = NSButton(title: "→", target: nil, action: nil)
    private let export = NSButton(title: "Export into Folder…", target: nil, action: nil)
    private let delete = NSButton(title: "Delete Space…", target: nil, action: nil)
    private var row: SpaceManagerRow?
    private var index = 0
    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = Metrics.spaceTools.managerCardRadius.value
        for (button, action) in [(open, #selector(focus)), (edit, #selector(editSpace)), (earlier, #selector(moveEarlier)), (later, #selector(moveLater)), (export, #selector(exportSpace)), (delete, #selector(deleteSpace))] {
            button.target = self; button.action = action; button.bezelStyle = .rounded; addSubview(button)
        }
        detail.font = .systemFont(ofSize: LibraryDraw.list.detailFont.value); detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail; addSubview(detail)
        open.isBordered = false; open.alignment = .left; open.font = .systemFont(ofSize: 16, weight: .semibold)
        open.lineBreakMode = .byTruncatingTail
        delete.contentTintColor = .systemRed
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    func render(_ row: SpaceManagerRow, index: Int, count: Int, exportBusy: Bool) {
        self.row = row; self.index = index
        let prefix: String = if case .custom(.emoji(let icon)) = row.icon { icon + " " } else { "" }
        open.title = prefix + row.title + (row.active ? " ✓" : "")
        detail.stringValue = "\(row.tabCount) tabs · \(row.profileName)"
        let color = row.theme.windowColor
        layer?.backgroundColor = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 0.35).cgColor
        earlier.isEnabled = index > 0; later.isEnabled = index + 1 < count
        earlier.toolTip = "Move \(row.title) earlier"; later.toolTip = "Move \(row.title) later"
        export.isEnabled = !exportBusy; delete.isEnabled = count > 1
        for (button, name) in [(open, "open"), (edit, "edit"), (earlier, "earlier"), (later, "later"), (export, "export"), (delete, "delete")] {
            button.identify(.spaceToolsControl("manager-\(name)-\(row.id)"))
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let f = SpaceManagerLayout.cardControls(in: bounds)
        for (view, rect) in zip([open, detail, edit, earlier, later, export, delete] as [NSView], f) { view.frame = rect }
    }
    @objc private func focus() { if let row { dispatch(.space(.focus(row.id))) } }
    @objc private func editSpace() { if let row { dispatch(.sidebar(.openDialog(.editSpace(.space(row.id))))) } }
    @objc private func moveEarlier() { if let row { dispatch(.space(.move(row.id, index: index - 1))) } }
    @objc private func moveLater() { if let row { dispatch(.space(.move(row.id, index: index + 1))) } }
    @objc private func exportSpace() { if let row { dispatch(.space(.exportIntoFolder(row.id))) } }
    @objc private func deleteSpace() { if let row { dispatch(.space(.requestDelete(row.id))) } }
}
