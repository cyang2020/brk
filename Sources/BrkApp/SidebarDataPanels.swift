import AppKit
import BrkBase
import BrkDomain
import Foundation
import UniformTypeIdentifiers

/// Native panel drafts and OS resources only. Accepted changes return through AppStore and the reducer.
@MainActor
final class SidebarDataPanels {
    private struct Operation {
        let id: UUID
        let sheet: NSWindow
        let cancel: @MainActor () -> Void
    }
    private var operations: [WindowID: Operation] = [:]
    private var tasks: [WindowID: Task<Void, Never>] = [:]
    private var closeObservers: [WindowID: NSObjectProtocol] = [:]
    let send: @MainActor (SidebarDataEvent) -> Void
    let command: @MainActor (WindowID, Command) -> Void
    let target: @MainActor (WindowID) -> SidebarImportTarget?

    init(send: @escaping @MainActor (SidebarDataEvent) -> Void,
         command: @escaping @MainActor (WindowID, Command) -> Void,
         target: @escaping @MainActor (WindowID) -> SidebarImportTarget?) {
        self.send = send; self.command = command; self.target = target
    }

    func ownerGone(_ id: WindowID) {
        if let observer = closeObservers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(observer) }
        tasks.removeValue(forKey: id)?.cancel()
        guard let operation = operations.removeValue(forKey: id) else { return }
        operation.cancel()
        if let parent = operation.sheet.sheetParent { parent.endSheet(operation.sheet, returnCode: .cancel) }
        operation.sheet.orderOut(nil)
    }

    func shutdown() async {
        let pending = Array(tasks.values)
        for id in Set(operations.keys).union(tasks.keys).union(closeObservers.keys) { ownerGone(id) }
        for task in pending { await task.value }
    }

    func show(_ panel: SidebarPanel, owner: WindowID, window: NSWindow, status: SidebarDataSnapshot) {
        guard operations[owner] == nil, tasks[owner] == nil, window.attachedSheet == nil else {
            send(.failed(epoch: nil, "Finish the open sheet before starting another sidebar operation.")); return
        }
        if closeObservers[owner] == nil {
            closeObservers[owner] = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.ownerGone(owner) }
            }
        }
        switch panel {
        case .welcome: welcome(owner: owner, window: window, needsSetup: status.needsOnboarding)
        case .importFile: chooseImport(owner: owner, window: window)
        case .syncSettings: sync(owner: owner, window: window, status: status)
        }
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.preferredMaxLayoutWidth = 430
        return field
    }

    private func stack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.frame = CGRect(x: 0, y: 0, width: 440, height: stack.fittingSize.height)
        stack.setFrameSize(CGSize(width: 440, height: max(80, stack.fittingSize.height)))
        return stack
    }

    private func checkbox(_ title: String, id: String, on: Bool) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = on ? .on : .off; button.identifier = NSUserInterfaceItemIdentifier(id)
        return button
    }

    private func begin(_ alert: NSAlert, owner: WindowID, window: NSWindow,
                       finish: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        let ticket = UUID()
        operations[owner] = Operation(id: ticket, sheet: alert.window, cancel: {})
        alert.beginSheetModal(for: window) { [weak self, weak window] response in
            guard let self, self.operations[owner]?.id == ticket else { return }
            self.operations[owner] = nil
            guard window?.isVisible == true, self.target(owner) != nil else { return }
            finish(response)
        }
    }

    private func welcome(owner: WindowID, window: NSWindow, needsSetup: Bool) {
        let alert = NSAlert()
        alert.messageText = "Welcome to Brk"
        alert.informativeText = needsSetup ? "Set up your first Space without an account. You can import exported files now or later." : "Your profile is already set up. Reopen the local tour or import exported files."
        if !needsSetup {
            alert.addButton(withTitle: "Open Brk 101"); alert.addButton(withTitle: "Close")
            begin(alert, owner: owner, window: window) { [weak self] response in
                if response == .alertFirstButtonReturn { self?.command(owner, .sidebarData(.tour)) }
            }
            return
        }
        let name = NSTextField(string: "Personal"); name.placeholderString = "Space name"
        name.identifier = NSUserInterfaceItemIdentifier("onboarding-space")
        name.widthAnchor.constraint(equalToConstant: 420).isActive = true
        let tabs = checkbox("Add Wikipedia and MDN starter tabs", id: "onboarding-tabs", on: true)
        let favorites = checkbox("Add Wikipedia to Favorites", id: "onboarding-favorites", on: true)
        let tour = checkbox("Open the local Brk 101 tour", id: "onboarding-tour", on: true)
        let importer = checkbox("Choose an import file after setup", id: "onboarding-import", on: false)
        let browser = checkbox("Ask macOS to make Brk the default browser", id: "onboarding-default", on: false)
        alert.accessoryView = stack([label("Name your Space"), name, tabs, favorites, tour, importer, browser])
        alert.addButton(withTitle: "Finish setup"); alert.addButton(withTitle: "Start empty")
        begin(alert, owner: owner, window: window) { [weak self] response in
            let defaults = response == .alertFirstButtonReturn
            self?.command(owner, .sidebarData(.completeOnboarding(OnboardingChoices(spaceName: name.stringValue,
                starterTabs: defaults && tabs.state == .on, favorites: defaults && favorites.state == .on,
                tour: defaults && tour.state == .on, importAfter: defaults && importer.state == .on,
                defaultBrowser: defaults && browser.state == .on))))
        }
    }

    private func chooseImport(owner: WindowID, window: NSWindow) {
        guard let captured = target(owner) else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an exported browser file"
        panel.prompt = "Preview"; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .html, .commaSeparatedText]
        let format = NSPopUpButton()
        format.identifier = NSUserInterfaceItemIdentifier("import-format")
        format.addItems(withTitles: ["Bookmarks HTML", "Bookmarks JSON (Chromium or Brk)", "History JSON (Takeout or array)", "Passwords CSV (local Keychain)"])
        panel.accessoryView = stack([label("Select the format of the file you exported. Brk never scans browser profiles or reads browser password databases."), format])
        let ticket = UUID()
        operations[owner] = Operation(id: ticket, sheet: panel, cancel: { panel.cancel(nil) })
        panel.beginSheetModal(for: window) { [weak self, weak window] response in
            guard let self, self.operations[owner]?.id == ticket else { return }
            self.operations[owner] = nil
            guard response == .OK, let url = panel.url, let window, window.isVisible, self.target(owner) == captured else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let source = try SidebarImport.parse(Data(contentsOf: url), format: SidebarImportFormat.allCases[format.indexOfSelectedItem])
                self.preview(source, filename: url.lastPathComponent, captured: captured, owner: owner, window: window)
            } catch { self.error("Import failed: \(error)", owner: owner, window: window) }
        }
    }

    private func preview(_ source: SidebarImportSource, filename: String, captured: SidebarImportTarget, owner: WindowID, window: NSWindow) {
        let preview = source.preview
        let alert = NSAlert()
        alert.messageText = "Preview \(filename)"
        alert.informativeText = "\(preview.bookmarkCount) bookmarks, \(preview.visits.count) history entries, \(preview.passwords) passwords.\n\(preview.rejected) invalid entries skipped. Existing bookmarks/history URLs and Keychain entries are deduplicated.\nThe source file stays unchanged. Cancel makes no changes."
        let destination = NSPopUpButton()
        destination.identifier = NSUserInterfaceItemIdentifier("import-destination")
        destination.addItems(withTitles: ["Pinned in \(captured.title)", "Favorites of this profile"])
        let details = preview.entries.prefix(6).map { entry -> String in
            switch entry { case .folder(let title, _): return "Folder: \(title)"; case .link(let title, let url): return "\(title)  (\(url.host ?? "site"))" }
        }.joined(separator: "\n")
        alert.accessoryView = stack([destination, label(details.isEmpty ? "History is imported into this Space's profile. Passwords require macOS authentication and are stored in Brk's protected local Keychain collection." : details)])
        alert.addButton(withTitle: "Import"); alert.addButton(withTitle: "Cancel")
        begin(alert, owner: owner, window: window) { [weak self, weak window] response in
            guard let self, response == .alertFirstButtonReturn, self.target(owner) == captured else { return }
            self.tasks[owner] = Task { @MainActor [weak self, weak window] in
                guard let self else { return }
                do {
                    let stored = try await ImportedPasswordVault.store(source.passwords, profile: captured.profile) { [weak self, weak window] in
                        !Task.isCancelled && window?.isVisible == true && self?.target(owner) == captured
                    }
                    guard !Task.isCancelled, self.target(owner) == captured else { return }
                    var result = preview; result.passwords = stored
                    self.send(.imported(owner, target: captured, result, favorites: destination.indexOfSelectedItem == 1))
                    self.tasks[owner] = nil
                    self.command(owner, .sidebarData(.syncSettings))
                } catch {
                    if let window, window.isVisible, !Task.isCancelled, self.target(owner) == captured {
                        self.error("\(error)", owner: owner, window: window)
                    }
                }
                self.tasks[owner] = nil
            }
        }
    }

    private func sync(owner: WindowID, window: NSWindow, status: SidebarDataSnapshot) {
        let alert = NSAlert()
        alert.messageText = "Sidebar Data"
        alert.informativeText = status.status + "\n\nShare this profile's Spaces, Pinned tabs and Favorites through a folder you choose. Map this folder to the current Space's profile on every device. Today, history, cookies, passwords, downloads, private tabs, settings and windows stay local.\n\nOnly saved HTTP(S) addresses without credentials, queries, fragments or local hosts are shared. \(status.excluded) tabs are excluded. Names and public URL paths are visible to anyone who can read the folder."
        alert.addButton(withTitle: status.connected ? "Sync now" : "Choose sync folder…")
        alert.addButton(withTitle: "Close")
        if status.connected { alert.addButton(withTitle: "Disconnect") }
        begin(alert, owner: owner, window: window) { [weak self, weak window] response in
            guard let self, let window else { return }
            if response == .alertThirdButtonReturn { self.command(owner, .sidebarData(.disconnect)); return }
            guard response == .alertFirstButtonReturn else { return }
            if status.connected { self.command(owner, .sidebarData(.syncNow)); return }
            self.chooseSyncFolder(owner: owner, window: window)
        }
    }

    private func chooseSyncFolder(owner: WindowID, window: NSWindow) {
        guard let captured = target(owner) else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose sidebar sync folder"; panel.prompt = "Connect this profile"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = "This folder's shared profile maps only to the current local profile. No credentials or browsing settings are copied."
        let ticket = UUID()
        operations[owner] = Operation(id: ticket, sheet: panel, cancel: { panel.cancel(nil) })
        panel.beginSheetModal(for: window) { [weak self, weak window] response in
            guard let self, self.operations[owner]?.id == ticket else { return }
            self.operations[owner] = nil
            guard response == .OK, let url = panel.url, window?.isVisible == true, self.target(owner) == captured else { return }
            self.send(.connected(owner, folder: url.path))
        }
    }

    private func error(_ message: String, owner: WindowID, window: NSWindow) {
        send(.failed(epoch: nil, message))
        let alert = NSAlert(); alert.messageText = "Sidebar Data"; alert.informativeText = message
        alert.addButton(withTitle: "OK")
        begin(alert, owner: owner, window: window) { _ in }
    }
}
