import AppKit
import BrkBase
import BrkDomain
import BrkEngine
import BrkLayout
import os

/// The one owner of application state. `dispatch` is the only path into `reduce`, and `reduce` is the only writer;
/// everything else (windows, engine, menu, control server) renders or reconciles from the snapshot it publishes.
///
/// One dispatch, in order:
/// 1. `reduce(state, input, ctx)` with `ctx.now = clock.now()`.
/// 2. If `changed`: `state = t.state`; `snapshot = project(state, ...)`; if `docChanged`,
///    `stateFile.schedule(StateCodec.encode(state))` (debounced, off the main thread); `engine.reconcile(snapshot.pages)`
///    so pages exist before anything is shown or navigated; windows: create/close `WindowController`s to match
///    `snapshot.windows`; each renders its `WindowSnapshot` (frames -> views -> page surfaces into cards -> keyboard
///    focus when `focus` changed).
/// 3. Effects, always, changed or not (`EffectRunner`): back, reload, copy URL and quit change no state. Page actions
///    go to the engine, pasteboard, window and app effects, popups.
///
/// Re-entrancy: an effect or a render can cause another input (a popup menu choice, a page event fired
/// synchronously by the engine). Inputs that arrive while a dispatch is running are queued and run right after it, in
/// arrival order, so step 1 never sees a half-applied transition. Key inputs are the exception: they must answer
/// synchronously, so `dispatchKey` runs the reducer at once if nothing is in flight, and otherwise answers
/// "not handled" and lets the page have the key (logged; has not been observed).
@MainActor
public final class AppStore {
    public private(set) var snapshot: AppSnapshot
    private var state: AppState
    private let clock: any Clock
    let engine: any WebEngine
    private let stateFile: StateFile
    private var windows: [WindowID: WindowController] = [:]
    /// The one settings window, created on first use (F1).
    private var settingsWindow: SettingsWindowController?
    /// Fallback for in-process input while the display is locked or the app has no key window.
    weak var inputWindow: NSWindow?
    private lazy var suggestions = SuggestionFetcher(send: { [weak self] in self?.dispatch($0) })
    private var queue: [Input] = []
    private var dispatching = false
    private(set) var isTerminating = false
    private let calendar = Calendar.autoupdatingCurrent
    private let log = Logger(subsystem: "brk", category: "store")
    private let popupTarget = PopupTarget()
    var nativePopupMenu: NSMenu? { popupTarget.presentedMenu }
    let destinations = DownloadSheets()
    private let syncIO = SidebarSyncIO()
    private var syncTask: Task<Void, Never>?
    private var syncTaskID: UUID?
    private var sidebarShuttingDown = false
    private let exports = ExportSheets()
    private lazy var sidebarPanels = SidebarDataPanels(send: { [weak self] event in
        self?.dispatch(.system(.sidebarData(event)))
    }, command: { [weak self] window, command in
        self?.dispatch(.user(window, command))
    }, target: { [weak self] window in self?.state.sidebarImportTarget(in: window) })
    private let spacePanels = SpaceToolsPanels()
    private var appearanceObservation: NSKeyValueObservation?
    let sounds = SoundEffects()
    let captureSheets = CaptureSheets()
    let captureFiles: CaptureFiles
    public var insertCaptureInEasel: (@MainActor (EaselCaptureInsertion, WindowID) -> Void)?
    let outputSheets = OutputSheets()
    var didPublish: ((AppSnapshot) -> Void)?
    let siteDialogs = SiteDialogs()
    lazy var sitePanels: SitePanels = {
        let panels = SitePanels()
        panels.send = { [weak self] id, command in self?.dispatch(.user(id, command)) }
        return panels
    }()

    public init(restored: Restored, clock: any Clock, engine: any WebEngine, stateFile: StateFile) {
        state = restored.state
        self.clock = clock
        self.engine = engine
        self.stateFile = stateFile
        captureFiles = CaptureFiles(root: stateFile.url.deletingLastPathComponent())
        snapshot = project(restored.state, ProjectionContext(now: clock.now(), calendar: Calendar.autoupdatingCurrent))
    }

    /// The first render after launch: windows and pages from the restored snapshot, no transition. Runs as a
    /// dispatch cycle: placing a window reports its geometry (`windowDidResize`), and that input must queue behind
    /// this publish like any other re-entrant one, not run in the middle of it.
    public func start() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        dispatching = true
        for request in state.pendingContextDisposals { engine.disposeContext(request) }
        publish(docChanged: false)
        dispatching = false
        drain()
        if let window = snapshot.windows.keys.sorted().first {
            if snapshot.sidebarData.needsOnboarding { dispatch(.user(window, .sidebarData(.welcome))) }
            else { dispatch(.system(.sidebarData(.syncPoll))) }
        }
    }

    /// Every user command, system event and page event enters here.
    public func dispatch(_ input: Input) {
        if isTerminating, case .user = input { return }
        queue.append(input)
        guard !dispatching else { return }
        drain()
    }

    /// CEF and menu key delivery. Returns whether the key was consumed (`Transition.keyHandled`).
    public func dispatchKey(_ window: WindowID, _ key: KeyInput) -> Bool { dispatchKeyHandling(window, key).handled }

    func dispatchKeyHandling(_ window: WindowID, _ key: KeyInput) -> KeyHandling {
        if isTerminating { return KeyHandling(handled: true, shortcut: true) }
        if dispatching {
            log.notice("key \(key.press.chord.description) arrived during a dispatch; passed to the page")
            return KeyHandling(handled: false, shortcut: false)
        }
        dispatching = true
        let handled = apply(.key(window, key))
        dispatching = false
        drain()
        return handled
    }

    /// Re-projects with a fresh `now` and re-renders (clock ticks keep archive buckets right).
    public func refresh() {
        snapshot = projected()
        reconcileCaptureSheets()
        engine.reconcile(snapshot.pages)
        renderWindows()
    }

    /// Writes state.json synchronously. First step of the ordered quit, before the engine shuts down. A failure is
    /// logged and reported; the quit goes on (the debounced copy on disk is the fallback).
    public func prepareSpaceToolsForShutdown() { spacePanels.cancelAll(); captureSheets.cancelAll() }

    @discardableResult
    public func flush() -> Bool {
        do { try stateFile.writeNow(StateCodec.encode(state)); return true } catch {
            log.error("flush failed: \(error)")
            return false
        }
    }

    public func stopSidebarData() async {
        sidebarShuttingDown = true
        let pending = syncTask
        pending?.cancel()
        await sidebarPanels.shutdown()
        exports.shutdown()
        await pending?.value
        syncTask = nil; syncTaskID = nil
    }

    /// The page's owner, if its current snapshot shows `page`: in one of its panes, or in its Peek card (F3), so a key from
    /// the peeked page (Esc, Cmd+W) routes to that window instead of being passed to the page.
    public func window(showing page: PageID) -> WindowID? {
        guard let window = snapshot.windows[page.window] else { return nil }
        let visible = window.content.presentedPanes.contains { $0.content == .page(page) }
            || { if case .peek(let peek)? = window.overlay { return peek.page == page }; return false }()
        return visible ? page.window : nil
    }

    func selectSpaceExportFixtureDirectory(_ directory: URL, owner: WindowID) -> Bool {
        guard snapshot.windows[owner]?.kind == .standard else { return false }
        return spacePanels.chooseFixtureDirectory(directory, owner: owner)
    }

    public func windowController(_ id: WindowID?) -> WindowController? {
        if let id { return windows[id] }
        return windows.values.first { $0.window.isKeyWindow }
            ?? windows.values.first { $0.window === inputWindow } ?? windows.values.first
    }

    func prepareForTermination() {
        guard !isTerminating else { return }
        isTerminating = true
        cancelExports()
        for window in snapshot.windows.keys { destinations.ownerGone(window); outputSheets.ownerGone(window) }
        let active = snapshot.windows.values.compactMap(\.output).filter { if case .terminal = $0.stage { false } else { true } }
        for output in active { engine.cancelOutput(output.id) }
    }

    func cancelExports() { exports.cancelAll() }

    // MARK: Private

    private func drain() {
        guard !dispatching else { return }
        dispatching = true
        while !queue.isEmpty { _ = apply(queue.removeFirst()) }
        dispatching = false
    }

    private func apply(_ input: Input) -> KeyHandling {
        if case .system(.window(let owner, .closed)) = input { spacePanels.ownerGone(owner) }
        if isTerminating, case .user = input { return KeyHandling(handled: false, shortcut: false) }
        if case .user(let window, .commandBar(let command)) = input {
            switch command { case .queryChanged, .queryChangedForSite, .dismiss: suggestions.cancel(window); default: break }
        }
        let t = reduce(state, input, Context(now: clock.now(), newID: { UUID().uuidString }))
        var checkpointed = false
        if t.docChanged, let failure = t.checkpointFailure {
            do { try stateFile.writeNow(StateCodec.encode(t.state)); checkpointed = true }
            catch { queue.append(.system(failure)); return KeyHandling(handled: false, shortcut: false) }
        }
        // Revocation must happen before reconcile sees the new demand, including synchronous engine callbacks.
        for effect in t.effects { if case .disposeContext(let request) = effect { engine.disposeContext(request) } }
        if t.changed {
            state = t.state
            publish(docChanged: t.docChanged && !checkpointed)
        }
        run(t.effects)
        return KeyHandling(handled: t.keyHandled, shortcut: t.keyShortcut)
    }

    /// Project, save, reconcile pages, then windows: closed ones go, new ones are placed and
    /// shown, every one renders. A new window is key and on screen before its first render, because keyboard focus
    /// into a Chromium view only sticks in a key window.
    private func publish(docChanged: Bool) {
        snapshot = projected()
        sounds.setEnabled(snapshot.settings.advanced.soundEffects)
        suggestions.reconcile(snapshot)
        reconcileCaptureSheets()
        if docChanged { stateFile.schedule(StateCodec.encode(state)) }
        engine.reconcile(snapshot.pages)
        for id in windows.keys where snapshot.windows[id] == nil {
            exports.ownerGone(id)
            outputSheets.ownerGone(id)
            destinations.ownerGone(id)
            spacePanels.ownerGone(id)
            sidebarPanels.ownerGone(id)
            exports.ownerGone(id)
            if let owner = windows[id]?.window, let sheet = owner.attachedSheet {
                owner.endSheet(sheet, returnCode: .cancel)
                sheet.orderOut(nil)
            }
            windows[id]?.window.orderOut(nil)
            windows[id] = nil
        }
        for id in snapshot.windows.keys.sorted() where windows[id] == nil {
            // A Little Arc is an NSPanel with Arc's hint strip and "Open in" control (F3); the other kinds a window.
            let kind = snapshot.windows[id]!.kind
            let send: @MainActor (Input) -> Void = { [weak self] in self?.dispatch($0) }
            let routeKey: @MainActor (KeyInput) -> Bool = { [weak self] input in self?.dispatchKey(id, input) ?? false }
            let controller = kind == .little
                ? LittleWindowController(id: id, engine: engine, send: send, routeKey: routeKey)
                : WindowController(id: id, kind: kind, engine: engine, send: send, routeKey: routeKey)
            windows[id] = controller
            controller.place(snapshot.windows[id]!)
            controller.window.makeKeyAndOrderFront(nil)
            inputWindow = controller.window
        }
        renderWindows()
        renderSettings()
        if !snapshot.sidebarData.connected { syncTask?.cancel(); syncTask = nil; syncTaskID = nil }
        didPublish?(snapshot)
    }

    /// The settings window follows `snapshot.settings.pane` (created the first time a pane opens).
    private func renderSettings() {
        if settingsWindow == nil, snapshot.settings.pane == nil { return }
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(send: { [weak self] command in
                guard let self, let window = self.windowController(nil)?.id else { return }
                self.dispatch(.user(window, command))
            })
        }
        settingsWindow?.render(snapshot.settings)
    }

    private func projected() -> AppSnapshot {
        project(state, ProjectionContext(now: clock.now(), calendar: calendar,
                                         systemScheme: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light))
    }

    private func renderWindows() {
        siteDialogs.validate(snapshot)
        sitePanels.render(snapshot.sites) { windows[$0]?.window }
        for (id, controller) in windows {
            if let window = snapshot.windows[id] { controller.render(window) }
        }
        renderSettings()
    }

    private lazy var siteTools = SiteToolsAdapter { [weak self] event in self?.dispatch(.system(event)) }
    private func chooseLocalExtension(_ id: WindowID, context: BrowsingContext) {
        guard let owner = windows[id]?.window, owner.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose an unpacked extension folder containing manifest.json."
        panel.beginSheetModal(for: owner) { [weak self, weak owner] response in
            guard let self, let owner, owner.isVisible, response == .OK, let directory = panel.url,
                  self.snapshot.pages.contains(where: { $0.context == context && $0.id.window == id }) else { return }
            self.dispatch(.user(id, .site(.installSelectedExtension(directory))))
        }
    }

    private func confirmLocalExtension(_ id: WindowID, context: BrowsingContext, directory: URL) {
        guard let owner = windows[id]?.window, owner.attachedSheet == nil else { return }
        let manifest = directory.appendingPathComponent("manifest.json")
        let size = (try? FileManager.default.attributesOfItem(atPath: manifest.path)[.size] as? NSNumber)?.intValue ?? Int.max
        guard size <= 1_048_576 else { extensionNotice("The selected manifest is missing or exceeds 1 MB", owner: owner); return }
        let summary = (try? Data(contentsOf: manifest)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        guard let summary, let name = summary["name"] as? String else { extensionNotice("The selected folder has no valid manifest.json", owner: owner); return }
        let alert = NSAlert()
        alert.messageText = "Install \(name)?"
        let disclosure: String
        do { disclosure = try ExtensionInstallPermissions.text(summary) }
        catch { extensionNotice("The selected manifest has invalid permission declarations", owner: owner); return }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 230))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false; text.isSelectable = true
        text.font = .systemFont(ofSize: NSFont.systemFontSize)
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.textContainer?.widthTracksTextView = true
        text.isVerticallyResizable = true; text.autoresizingMask = [.width]
        text.string = disclosure
        text.identifier = NSUserInterfaceItemIdentifier("extension-permission-summary")
        text.setAccessibilityIdentifier("extension-permission-summary")
        scroll.documentView = text
        alert.informativeText = "Review the extension's declared access before installing."
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Install"); alert.addButton(withTitle: "Cancel")
        let key = ViewID.settingsField("confirmExtensionInstall").identifier
        alert.buttons[0].identifier = NSUserInterfaceItemIdentifier(key); alert.buttons[0].setAccessibilityIdentifier(key)
        alert.beginSheetModal(for: owner) { [weak self, weak owner] response in
            guard let self, let owner, owner.isVisible, response == .alertFirstButtonReturn else { return }
            self.dispatch(.user(id, .site(.executeExtensionInstall(directory, context))))
        }
    }

    private func extensionNotice(_ message: String, owner: NSWindow) {
        let alert = NSAlert(); alert.messageText = "Extensions"; alert.informativeText = message
        if owner.isVisible, owner.attachedSheet == nil { alert.beginSheetModal(for: owner) }
    }

    private func reconcileCaptureSheets() {
        let captures = snapshot.windows.mapValues { window -> Set<String> in
            if case .library(let library)? = window.overlay { return Set(library.captures.map(\.id)) }
            return []
        }
        captureSheets.reconcile(Set(snapshot.windows.keys), captures:captures)
    }
    func captureWindow(_ id: WindowID) -> NSWindow? { windows[id]?.window }

    private func run(_ effects: [Effect]) {
        siteTools.reconcile(Set(snapshot.windows.values.compactMap { $0.tabTools.pendingSiteRequest }))
        for effect in effects {
            switch effect {
            case .capture(let effect): runCapture(effect)
            case .find(let request): engine.find(request)
            case .siteRequest(let request):
                if let window = windows[request.window]?.window { siteTools.run(request, in: window) }
            case .iconPicker(let window, let item):
                guard let owner = windows[window]?.window else { continue }
                TabIconPicker.present(in: owner) { [weak self, weak owner] icon in
                    guard owner?.isVisible == true else { return }
                    self?.dispatch(.user(window, .item(.setIcon(item, icon))))
                }
            case .output(let request): engine.output(request)
            case .cancelOutput(let id): engine.cancelOutput(id)
            case .page(let page, let action):
                engine.perform(action, on: page)
            case .copyToPasteboard(let text):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            case .window(let id, let effect):
                guard let window = windows[id]?.window else { continue }
                switch effect {
                case .toggleFullScreen: window.toggleFullScreen(nil)
                case .pageFullScreen(let on): windows[id]?.setPageFullScreen(on)
                case .leaveFullScreen: if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
                case .miniaturize: window.miniaturize(nil)
                case .close: window.performClose(nil)
                case .requestArchiveClear: windows[id]?.root.library.requestClearConfirmation()
                }
            case .app(let effect):
                switch effect {
                case .quit:
                    // AppKit can defer termination while a save sheet remains attached.
                    sidebarPanels.cancelForQuit()
                    exports.cancelAll()
                    spacePanels.cancelAll()
                    Quit.request()
                case .hide: NSApp.hide(nil)
                case .hideOthers: NSApp.hideOtherApplications(nil)
                case .beep: NSSound.beep()
                case .showAbout: NSApp.orderFrontStandardAboutPanel(nil)
                case .showSettings:
                    settingsWindow?.present()
                    inputWindow = settingsWindow?.window
                case .registerAsDefaultBrowser:
                    DefaultBrowser.register { [weak self] message in
                        guard let owner = self?.windowController(nil)?.window else { return }
                        let alert = NSAlert(); alert.messageText = "Default browser could not be changed"; alert.informativeText = message
                        alert.beginSheetModal(for: owner)
                    }
                case .revealDataDirectory: NSWorkspace.shared.activateFileViewerSelecting([Product.dataDirectory()])
                }
            case .popupMenu(let id, let model, let at):
                guard let controller = windows[id] else { continue }
                let menu = popupTarget.menu(for: model) { [weak self] command in self?.dispatch(.user(id, command)) }
                menu.popUp(positioning: nil, at: at, in: controller.root)
                popupTarget.clear()
            case .export(let document, let owner):
                guard let window = windows[owner]?.window else { continue }
                exports.present(document, owner: owner, in: window, reply: { [weak self] outcome in
                    self?.dispatch(.system(.exportFinished(owner, outcome)))
                })
            case .sidebarData(let effect): runSidebarData(effect)
            case .exportSpaceFolder(let owner, let token, let document):
                guard let window = windows[owner]?.window else {
                    dispatch(.system(.spaceExportFinished(owner, token: token, .cancelled))); continue
                }
                spacePanels.export(document, owner: owner, token: token, window: window) { [weak self] outcome in
                    self?.dispatch(.system(.spaceExportFinished(owner, token: token, outcome)))
                }
            case .ai(let id, let task, let choice):
                let detected = snapshot.settings.max.detected
                Task { @MainActor [weak self] in
                    let outcome = await AIProviderSeam.answer(task, choice: choice, detected: detected)
                    self?.dispatch(.system(.aiResult(id, outcome)))
                }
            case .fetchSuggestions(let window, let query, let url):
                suggestions.fetch(window, query: query, url: url)
            case .disposeContext: break
            case .loadWebsiteRules(let file, let context):
                Task { @MainActor [weak self] in
                    let update = await Task.detached(priority: .utility) { SiteRulesFiles.read(file) }.value
                    self?.dispatch(.system(.websiteRulesLoaded(context, update)))
                }
            case .chooseWebsiteRules(let id, let context):
                guard let owner = windows[id]?.window, owner.attachedSheet == nil else { continue }
                let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
                panel.message = "Choose Brk blocking rules JSON. This replaces this profile's current network and cosmetic rules."
                panel.beginSheetModal(for: owner) { [weak self] response in
                    guard let self, response == .OK, let file = panel.url else { return }
                    self.dispatch(.user(id, .site(.selectedBlockingRules(file, context))))
                }
            case .queryExtensions(let context):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.dispatch(.system(.extensionsRead(await self.engine.extensionCatalog(context: context))))
                }
            case .invokeExtension(let id, let target):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error = await self.engine.invokeExtension(id, target: target) {
                        self.dispatch(.system(.extensionsRead(ExtensionCatalog(context: target.context, extensions: [], error: error))))
                    }
                }
            case .removeExtension(let id, let context, let page):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let error = await self.engine.removeExtension(id, context: context, in: page)
                    let result = error.map { ExtensionCatalog(context: context, extensions: [], error: $0) }
                    if let result { self.dispatch(.system(.extensionsRead(result))) }
                    else { self.dispatch(.system(.extensionsRead(await self.engine.extensionCatalog(context: context)))) }
                }
            case .confirmSiteData(let request):
                siteDialogs.confirm(request, in: windows[request.target.page.window]?.window) { [weak self] answer in
                    self?.dispatch(.user(request.target.page.window, .site(.confirmClear(request.id, answer))))
                }
            case .cancelSiteData(let id): engine.cancelSiteData(id)
            case .clearSiteData(let request):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let result = await self.engine.clearSiteData(request)
                    self.dispatch(.system(.siteDataCleared(result)))
                }
            case .confirmLocalExtension(let window, let context, let directory):
                confirmLocalExtension(window, context: context, directory: directory)
            case .installLocalExtension(let page, let context, let directory):
                let window = page.window
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let error = await self.engine.installExtension(at: directory, context: context, in: page)
                    self.dispatch(.system(.extensionsRead(await self.engine.extensionCatalog(context: context))))
                    if let error { self.dispatch(.system(.extensionOperationFailed(context, error))) }
                    if let error, let owner = self.windows[window]?.window,
                       self.snapshot.pages.contains(where: { $0.id.window == window && $0.context == context && $0.websitePolicy.visible }) {
                        self.extensionNotice(error, owner: owner)
                    }
                }
            case .addLocalExtension(let window, let context):
                chooseLocalExtension(window, context: context)
            case .cancelDownload(let id): engine.cancelDownload(id)
            case .sound(let event):
                sounds.setEnabled(snapshot.settings.advanced.soundEffects)
                sounds.play(event)
            case .revealFile(let path):
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    private func runSidebarData(_ effect: SidebarDataEffect) {
        guard !sidebarShuttingDown else { return }
        switch effect {
        case .panel(let owner, let panel):
            guard let window = windows[owner]?.window else { return }
            sidebarPanels.show(panel, owner: owner, window: window, status: snapshot.sidebarData)
        case .tour(let owner):
            do {
                let url = try BrkTour.write(in: stateFile.url.deletingLastPathComponent())
                dispatch(.user(owner, .commandBar(.open(.newTab))))
                dispatch(.user(owner, .commandBar(.submit(url.absoluteString))))
            } catch { dispatch(.system(.sidebarData(.failed(epoch: nil, "Could not write the local Brk tour.")))) }
        case .exchange(let epoch, let folder, let replica, let revision, let document):
            guard syncTask == nil else { return }
            // Publishing is permitted only after this exact sidebar edit + replica checkpoint is durable.
            guard flush() else { dispatch(.system(.sidebarData(.failed(epoch: epoch, "Sync paused because local state could not be saved.")))); return }
            let ticket = UUID()
            syncTaskID = ticket
            syncTask = Task { @MainActor [weak self] in
                guard let self else { return }
                var succeeded = false
                do {
                    let received = try await self.syncIO.exchange(folder: URL(fileURLWithPath: folder, isDirectory: true), replica: replica, document: document)
                    guard !Task.isCancelled else { return }
                    self.dispatch(.system(.sidebarData(.syncRead(epoch: epoch, received))))
                    self.dispatch(.system(.sidebarData(.syncWritten(epoch: epoch, revision: revision, published: document))))
                    succeeded = true
                } catch is CancellationError {} catch {
                    self.dispatch(.system(.sidebarData(.failed(epoch: epoch, "Sync failed. Check folder access and replica files, then retry. \(error.localizedDescription)"))))
                }
                guard self.syncTaskID == ticket else { return }
                self.syncTask = nil; self.syncTaskID = nil
                if succeeded, self.state.docNeedsSidebarPublication {
                    self.dispatch(.system(.sidebarData(.syncPoll)))
                }
            }
        }
    }
}

/// Builds a native popup from a `MenuModel`; each item dispatches its entry's command when chosen.
@MainActor
final class PopupTarget: NSObject {
    private(set) weak var presentedMenu: NSMenu?
    private var commands: [Int: Command] = [:]
    private var choose: ((Command) -> Void)?

    func menu(for model: MenuModel, choose: @escaping (Command) -> Void) -> NSMenu {
        self.choose = choose
        commands.removeAll()
        let menu = NSMenu()
        presentedMenu = menu
        for (i, entry) in model.entries.enumerated() {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .action(let title, let command, let enabled):
                let item = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: "")
                item.target = self
                item.tag = i
                item.isEnabled = enabled
                commands[i] = command
                menu.addItem(item)
            }
        }
        menu.autoenablesItems = false
        return menu
    }

    func clear() { commands.removeAll(); choose = nil; presentedMenu = nil }

    @objc private func fire(_ sender: NSMenuItem) {
        if let command = commands[sender.tag] { choose?(command) }
    }
}
