import AppKit
import BrkBase
import BrkEngine
import Foundation

/// Help > Troubleshooting > Open Task Manager: Chrome's task manager as a Brk window. One row per browser process
/// (the browser itself, each renderer with its tab titles, GPU, utilities, workers) with its memory footprint, CPU
/// and GPU memory, refreshed every second; End Process ends the selected process when Chromium allows it (a page's
/// renderer: the tab shows its crashed state and reloads on Cmd+R).
@MainActor
final class TaskManagerWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let engine: any WebEngine
    private(set) var rows: [EngineTask] = []
    let window: NSWindow
    private let table = NSTableView()
    private let endButton = NSButton(title: "End Process", target: nil, action: nil)
    private var timer: Timer?

    static let columns: [(id: String, title: String, width: CGFloat)] = [
        ("task", "Task", 300), ("memory", "Memory Footprint", 130), ("cpu", "CPU", 70), ("gpu", "GPU Memory", 110),
    ]

    init(engine: any WebEngine) {
        self.engine = engine
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 420), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Task Manager - \(Product.name)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 240)
        for column in Self.columns {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
            c.title = column.title
            c.width = column.width
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.setAccessibilityIdentifier("taskManager.table")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        endButton.target = self
        endButton.action = #selector(endSelected)
        endButton.isEnabled = false
        endButton.setAccessibilityIdentifier("taskManager.end")
        endButton.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(scroll)
        content.addSubview(endButton)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            endButton.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            endButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            endButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        window.contentView = content
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window)
    }

    func show() {
        refresh()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    func refresh() {
        let selected = table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow].id : nil
        rows = Self.ordered(engine.tasks())
        table.reloadData()
        if let selected, let index = rows.firstIndex(where: { $0.id == selected }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        updateButton()
    }

    /// The browser process first, then by memory, largest first (Chrome's default sort is by task; by memory is
    /// what the troubleshooting row is for).
    static func ordered(_ tasks: [EngineTask]) -> [EngineTask] {
        tasks.sorted { a, b in
            if (a.kind == .browser) != (b.kind == .browser) { return a.kind == .browser }
            return (a.memory ?? -1, b.title) > (b.memory ?? -1, a.title)
        }
    }

    static func text(_ task: EngineTask, column: String) -> String {
        switch column {
        case "task": return task.title.isEmpty ? task.kind.rawValue.capitalized : task.title
        case "memory": return task.memory.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory) } ?? "–"
        case "cpu": return task.cpu.map { String(format: "%.1f", $0) } ?? "–"
        case "gpu": return task.gpuMemory.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory) } ?? "–"
        default: return ""
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn?.identifier.rawValue, rows.indices.contains(row) else { return nil }
        let field = NSTextField(labelWithString: Self.text(rows[row], column: column))
        field.lineBreakMode = .byTruncatingTail
        if column != "task" { field.alignment = .right }
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButton() }

    private func updateButton() {
        endButton.isEnabled = table.selectedRow >= 0 && table.selectedRow < rows.count && rows[table.selectedRow].killable
    }

    @objc private func endSelected() {
        guard table.selectedRow >= 0, table.selectedRow < rows.count else { return }
        if !engine.endTask(rows[table.selectedRow].id) { NSSound.beep() }
        refresh()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }
}
