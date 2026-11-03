import AppKit
import BrkBase
import Foundation
import UniformTypeIdentifiers

/// Help > Restore Data (Arc: `RestoreDataWindowController`, "Backup can be restored" / "Backup cannot be restored"
/// and a button that finalizes the restore). Lists the launch backups newest first, or takes any file through Choose
/// File…; each choice is checked by the state codec before Restore and Relaunch is enabled. Confirming hands the
/// file to `confirmed` (Lifecycle quits in order, puts the backup in place and starts again).
@MainActor
final class RestoreDataWindow: NSObject {
    let window: NSWindow
    private let backups: StateBackups
    private let popup = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let restoreButton = NSButton(title: "Restore and Relaunch", target: nil, action: nil)
    private var choices: [URL] = []
    private(set) var selected: URL?
    private(set) var check: StateBackups.Check?
    var confirmed: (@MainActor (URL) -> Void)?

    init(backups: StateBackups) {
        self.backups = backups
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 210), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Restore Data"
        window.isReleasedWhenClosed = false
        let intro = NSTextField(wrappingLabelWithString:
            "Choose a backup of your \(Product.name) data. \(Product.name) keeps the current data as a backup first, then restarts with the one you choose.")
        popup.target = self
        popup.action = #selector(choose)
        popup.setAccessibilityIdentifier("restoreData.backups")
        let browse = NSButton(title: "Choose File…", target: self, action: #selector(browseFile))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(close))
        cancel.keyEquivalent = "\u{1b}"
        restoreButton.target = self
        restoreButton.action = #selector(restore)
        restoreButton.keyEquivalent = "\r"
        restoreButton.setAccessibilityIdentifier("restoreData.restore")
        status.setAccessibilityIdentifier("restoreData.status")
        let choose = NSStackView(views: [popup, browse])
        let buttons = NSStackView(views: [cancel, restoreButton])
        let stack = NSStackView(views: [intro, choose, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor), stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            intro.widthAnchor.constraint(equalToConstant: 480), status.widthAnchor.constraint(equalToConstant: 480),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 340),
        ])
        buttons.setHuggingPriority(.defaultLow, for: .horizontal)
        window.contentView = content
    }

    func show() {
        reload()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    /// The launch backups, newest first; the first is chosen.
    func reload() {
        let format = DateFormatter()
        format.dateStyle = .medium
        format.timeStyle = .short
        choices = backups.list().map(\.url)
        popup.removeAllItems()
        for (url, backup) in zip(choices, backups.list()) {
            let before = url.lastPathComponent.hasPrefix("state-before-restore") ? " (before the last restore)" : ""
            popup.addItem(withTitle: format.string(from: backup.date) + before)
        }
        if choices.isEmpty { popup.addItem(withTitle: "No backups yet"); popup.isEnabled = false } else { popup.isEnabled = true }
        select(choices.first)
    }

    func select(_ url: URL?) {
        selected = url
        check = url.map(StateBackups.check)
        switch check {
        case .restorable(let spaces, let tabs)?:
            status.stringValue = "Backup can be restored: \(spaces) \(spaces == 1 ? "space" : "spaces") and \(tabs) \(tabs == 1 ? "tab" : "tabs")."
            status.textColor = .secondaryLabelColor
        case .notRestorable(let why)?:
            status.stringValue = "Backup cannot be restored. " + why
            status.textColor = .systemRed
        case nil:
            status.stringValue = "\(Product.name) makes a backup each time it starts. Choose File… to restore another copy."
            status.textColor = .secondaryLabelColor
        }
        restoreButton.isEnabled = { if case .restorable? = check { true } else { false } }()
    }

    @objc private func choose() {
        let index = popup.indexOfSelectedItem
        select(choices.indices.contains(index) ? choices[index] : nil)
    }

    @objc private func browseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.directoryURL = backups.folder
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.select(url) }
        }
    }

    @objc private func restore() {
        guard let selected, case .restorable? = check else { return }
        window.close()
        confirmed?(selected)
    }

    @objc private func close() { window.close() }
}
