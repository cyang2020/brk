import AppKit
import BrkBase
import BrkLayout
import BrkUIKit
import Foundation

/// A captured-window export destination. The path remains editable when the OS browser is unavailable.
@MainActor
final class SpaceFolderSheet: NSObject, NSWindowDelegate {
    let window: NSPanel
    private weak var owner: NSWindow?
    private let path = NSTextField()
    private let error = NSTextField(wrappingLabelWithString: "")
    private var browser: NSOpenPanel?
    private var selected: URL?
    private var finished = false
    private var ending = false
    private let reply: @MainActor (URL?) -> Void

    init(directory: URL, reply: @escaping @MainActor (URL?) -> Void) {
        self.reply = reply
        window = NSPanel(contentRect: CGRect(origin: .zero, size: Metrics.spaceTools.folderExportSize.value),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Export Space into Folder"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let root = NSView()
        window.contentView = root
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Metrics.spaceTools.folderExportSpacing.value
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Metrics.spaceTools.folderExportPadding.value),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Metrics.spaceTools.folderExportPadding.value),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: Metrics.spaceTools.folderExportPadding.value),
        ])
        let title = NSTextField(labelWithString: "Choose an export folder")
        title.font = .systemFont(ofSize: Metrics.spaceTools.folderExportTitle.value, weight: .semibold)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString: "Creates a new folder containing bookmarks.json and bookmarks.html. Existing exports are kept."))
        let location = NSStackView()
        location.orientation = .horizontal
        location.spacing = 8
        path.stringValue = directory.path
        path.usesSingleLineMode = true
        path.cell?.isScrollable = true
        path.placeholderString = "Folder path"
        path.identify(.spaceToolsControl("folder-export-path"))
        location.addArrangedSubview(path)
        let browse = NSButton(title: "Browse…", target: self, action: #selector(browseClicked))
        browse.bezelStyle = .rounded
        browse.identify(.spaceToolsControl("folder-export-browse"))
        location.addArrangedSubview(browse)
        stack.addArrangedSubview(location)
        error.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        error.textColor = .systemRed
        error.identify(.spaceToolsControl("folder-export-error"))
        stack.addArrangedSubview(error)
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        let export = NSButton(title: "Export Here", target: self, action: #selector(exportClicked))
        export.bezelStyle = .rounded; export.keyEquivalent = "\r"
        export.identify(.spaceToolsControl("folder-export-confirm"))
        buttons.addArrangedSubview(cancel); buttons.addArrangedSubview(export)
        stack.addArrangedSubview(buttons)
        for view in [location, error] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }

    func begin(in owner: NSWindow) {
        self.owner = owner
        owner.beginSheet(window) { [weak self] response in
            guard let self, !self.finished else { return }
            self.finished = true
            self.browser?.cancel(nil)
            self.browser = nil
            self.window.orderOut(nil)
            self.reply(response == .OK ? self.selected : nil)
        }
        window.makeFirstResponder(path)
    }

    func setDirectory(_ directory: URL) { path.stringValue = directory.path; error.stringValue = "" }
    func cancel() {
        guard !finished, !ending else { return }
        ending = true
        browser?.cancel(nil)
        browser = nil
        owner?.endSheet(window, returnCode: .cancel)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancel(); return false }
    @objc private func cancelClicked() { cancel() }

    @objc private func exportClicked() {
        guard !finished, !ending, window.attachedSheet == nil else { return }
        window.makeFirstResponder(nil)
        let text = path.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { error.stringValue = "Choose a folder or enter its path."; return }
        let directory = URL(fileURLWithPath: (text as NSString).expandingTildeInPath, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            error.stringValue = "That folder does not exist. Choose an existing folder."; return
        }
        selected = directory
        ending = true
        owner?.endSheet(window, returnCode: .OK)
    }

    @objc private func browseClicked() {
        guard browser == nil, !finished, !ending else { return }
        window.makeFirstResponder(nil)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.directoryURL = URL(fileURLWithPath: (path.stringValue as NSString).expandingTildeInPath, isDirectory: true)
        browser = panel
        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            guard let self, let panel, self.browser === panel, !self.finished else { return }
            self.browser = nil
            if response == .OK, let directory = panel.url { self.setDirectory(directory) }
        }
    }
}
