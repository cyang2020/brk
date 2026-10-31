import AppKit
import BrkBase
import BrkDomain
import BrkEngine
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
    private let engine: any WebEngine
    private let stateFile: StateFile
    private var windows: [WindowID: WindowController] = [:]
    /// The one settings window, created on first use (F1).
    private var settingsWindow: SettingsWindowController?
    /// Fallback for in-process input while the display is locked or the app has no key window.
    weak var inputWindow: NSWindow?
    private lazy var suggestions = SuggestionFetcher(send: { [weak self] in self?.dispatch($0) })
    private var queue: [Input] = []
    private var dispatching = false
    private let calendar = Calendar.autoupdatingCurrent
    private let log = Logger(subsystem: "brk", category: "store")
    private let popupTarget = PopupTarget()
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

    public init(restored: Restored, clock: any Clock, engine: any WebEngine, stateFile: StateFile) {
        state = restored.state
        self.clock = clock
        self.engine = engine
        self.stateFile = stateFile
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
            dispatch(.user(window, .sidebarData(snapshot.sidebarData.needsOnboarding ? .welcome : .syncNow)))
        }
    }

    /// Every user command, system event and page event enters here.
    public func dispatch(_ input: Input) {
        queue.append(input)
        guard !dispatching else { return }
        drain()
    }

    /// CEF and menu key delivery. Returns whether the key was consumed (`Transition.keyHandled`).
    public func dispatchKey(_ window: WindowID, _ key: KeyInput) -> Bool { dispatchKeyHandling(window, key).handled }

    func dispatchKeyHandling(_ window: WindowID, _ key: KeyInput) -> KeyHandling {
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
        renderWindows()
    }

    /// Writes state.json synchronously. First step of the ordered quit, before the engine shuts down. A failure is
    /// logged and reported; the quit goes on (the debounced copy on disk is the fallback).
    public func prepareSpaceToolsForShutdown() { spacePanels.cancelAll() }

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

    // MARK: Private

    private func drain() {
        guard !dispatching else { return }
        dispatching = true
        while !queue.isEmpty { _ = apply(queue.removeFirst()) }
        dispatching = false
    }

    private func apply(_ input: Input) -> KeyHandling {
        if case .system(.window(let owner, .closed)) = input { spacePanels.ownerGone(owner) }
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
        if docChanged { stateFile.schedule(StateCodec.encode(state)) }
        engine.reconcile(snapshot.pages)
        for id in windows.keys where snapshot.windows[id] == nil {
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
        for (id, controller) in windows {
            if let window = snapshot.windows[id] { controller.render(window) }
        }
        renderSettings()
    }

    private lazy var siteTools = SiteToolsAdapter { [weak self] event in self?.dispatch(.system(event)) }

    private func run(_ effects: [Effect]) {
        siteTools.reconcile(Set(snapshot.windows.values.compactMap { $0.tabTools.pendingSiteRequest }))
        for effect in effects {
            switch effect {
            case .find(let request): engine.find(request)
            case .siteRequest(let request):
                if let window = windows[request.window]?.window { siteTools.run(request, in: window) }
            case .iconPicker(let window, let item):
                guard let owner = windows[window]?.window else { continue }
                TabIconPicker.present(in: owner) { [weak self, weak owner] icon in
                    guard owner?.isVisible == true else { return }
                    self?.dispatch(.user(window, .item(.setIcon(item, icon))))
                }
            case .page(let page, let action):
                engine.perform(action, on: page)
            case .copyToPasteboard(let text):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            case .window(let id, let effect):
                guard let window = windows[id]?.window else { continue }
                switch effect {
                case .toggleFullScreen: window.toggleFullScreen(nil)
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
                case .registerAsDefaultBrowser: DefaultBrowser.register()
                case .revealDataDirectory: NSWorkspace.shared.activateFileViewerSelecting([Product.dataDirectory()])
                }
            case .popupMenu(let id, let model, let at):
                guard let controller = windows[id] else { continue }
                let menu = popupTarget.menu(for: model) { [weak self] command in self?.dispatch(.user(id, command)) }
                menu.popUp(positioning: nil, at: at, in: controller.root)
                popupTarget.clear()
            case .export(let document, let owner):
                guard let window = windows[owner]?.window else { continue }
                exports.present(document, owner: owner, in: window, reply: { [weak self] message in
                    self?.dispatch(.system(.sidebarData(.exportFinished(message))))
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
            case .cancelDownload(let id): engine.cancelDownload(id)
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
    private var commands: [Int: Command] = [:]
    private var choose: ((Command) -> Void)?

    func menu(for model: MenuModel, choose: @escaping (Command) -> Void) -> NSMenu {
        self.choose = choose
        commands.removeAll()
        let menu = NSMenu()
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

    func clear() { commands.removeAll(); choose = nil }

    @objc private func fire(_ sender: NSMenuItem) {
        if let command = commands[sender.tag] { choose?(command) }
    }
}
