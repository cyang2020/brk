import AppKit
import BrkBase
import BrkDomain
import BrkEngine
import BrkLayout
import BrkSettings
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
    /// Read by the AppleScript objects (BrkApp/Scripting) through `AppState.script…`; only `apply` changes it.
    private(set) var state: AppState
    private let clock: any Clock
    let engine: any WebEngine
    private let stateFile: StateFile
    private let boostFiles: BoostFiles
    private var loadedBoostProfiles: Set<ProfileID> = []
    private var boostPicks: [WindowID: (editor: String, target: SiteTarget)] = [:]
    private var windows: [WindowID: WindowController] = [:]
    /// The one settings window, created on first use (F1).
    private var settingsWindow: SettingsWindowController?
    /// The Icon pane's drawing last set as `NSApp.applicationIconImage` (the Dock icon); nil before the first render.
    private(set) var shownIcon: AppIconChoice?
    /// The "Warn before quitting" dialog is open.
    private var askingQuit = false
    static let dockIconSide: CGFloat = 512
    private lazy var aboutWindow = AboutWindow(engineVersion: engine.engineVersion) { [weak self] command in
        guard let self, let window = self.windowController(nil)?.id else { return }
        self.dispatch(.user(window, command))
    }
    /// Fallback for in-process input while the display is locked or the app has no key window.
    weak var inputWindow: NSWindow?
    private lazy var suggestions = SuggestionFetcher(send: { [weak self] in self?.dispatch($0) })
    private lazy var aiServices = AIServices(engine: engine, send: { [weak self] event in self?.dispatch(.system(event)) })
    private var queue: [Input] = []
    private var dispatching = false
    private(set) var isTerminating = false
    private let calendar = Calendar.autoupdatingCurrent
    private let log = Logger(subsystem: "brk", category: "store")
    private let popupTarget = PopupTarget()
    let destinations = DownloadSheets()
    private let syncIO = SidebarSyncIO()
    private var syncTask: Task<Void, Never>?
    private var syncTaskID: UUID?
    private var sidebarShuttingDown = false
    private let exports = ExportSheets()
    private lazy var filterListDownloads = FilterListDownloads(send: { [weak self] event in self?.dispatch(.system(event)) })
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
    let easelFiles: EaselFiles
    public var insertCaptureInEasel: (@MainActor (EaselCaptureInsertion, WindowID) -> Void)?
    let outputSheets = OutputSheets()
    var didPublish: ((AppSnapshot) -> Void)?
    /// Check for Updates… and the Help menu (`AppEffect.help`).
    private(set) lazy var help = HelpActions(engine: engine, now: { [clock] in clock.now() }, send: { [weak self] window, command in
        self?.dispatch(.user(window, command))
    }, owner: { [weak self] window in self?.windows[window]?.window ?? self?.windowController(nil)?.window })
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
        self.boostFiles = BoostFiles(root: stateFile.url.deletingLastPathComponent())
        captureFiles = CaptureFiles(root: stateFile.url.deletingLastPathComponent())
        easelFiles = EaselFiles(root: stateFile.url.deletingLastPathComponent())
        snapshot = project(restored.state, ProjectionContext(now: clock.now(), calendar: Calendar.autoupdatingCurrent))
        for row in snapshot.settings.profiles {
            let id = row.profile.id
            let (catalog, error) = boostFiles.read(id)
            state = reduce(state, .system(.boost(.loaded(id, catalog, error: error))), Context(now: clock.now(), newID: { UUID().uuidString })).state
            loadedBoostProfiles.insert(id)
        }
        snapshot = project(state, ProjectionContext(now: clock.now(), calendar: Calendar.autoupdatingCurrent))
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

    func selectLinkExportFixture(_ destination: URL, owner: WindowID) -> Bool {
        exports.selectFixture(destination, owner: owner)
    }

    public func windowController(_ id: WindowID?) -> WindowController? {
        if let id { return windows[id] }
        return windows.values.first { $0.window.isKeyWindow }
            ?? windows.values.first { $0.window === inputWindow } ?? windows.values.first
    }

    func prepareForTermination() {
        guard !isTerminating else { return }
        isTerminating = true
        settingsWindow?.endSheets()
        // An open Warn before quitting sheet (a quit that did not ask, SIGTERM or the control socket, overtook it).
        for controller in windows.values { if let sheet = controller.window.attachedSheet, sheet.className.contains("Alert") { controller.window.endSheet(sheet) } }
        aiServices.cancelAll()
        cancelExports()
        for window in snapshot.windows.keys { destinations.ownerGone(window); outputSheets.ownerGone(window) }
        let active = snapshot.windows.values.compactMap(\.output).filter { if case .terminal = $0.stage { false } else { true } }
        for output in active { engine.cancelOutput(output.id) }
    }

    func stopAI() async { await aiServices.stop() }

    /// "Warn before quitting" (`QuitWarning`): `answer` gets whether to go on quitting. Asks only while the setting is
    /// on, as a sheet on `window`; "Quit, and don’t ask again" turns it off through the reducer, so the answer is saved
    /// before the ordered quit flushes.
    func confirmQuit(on window: NSWindow?, answer: @escaping @MainActor (Bool) -> Void) {
        QuitWarning.confirm(snapshot.settings.general, on: window, dispatch: { [weak self] command in
            guard let self, let window = self.windowController(nil)?.id else { return }
            self.dispatch(.user(window, command))
        }, ask: Self.askQuit, answer: answer)
    }

    /// The quit dialog; tests answer it without presenting it.
    static var askQuit: @MainActor (NSAlert, NSWindow?, @escaping @MainActor (QuitWarning.Answer) -> Void) -> Void = QuitWarning.present

    private func quitNow() {
        // AppKit can defer termination while a save sheet remains attached.
        sidebarPanels.cancelForQuit()
        exports.cancelAll()
        spacePanels.cancelAll()
        Quit.request()
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
        return KeyHandling(handled: t.keyHandled, shortcut: t.keyShortcut, action: t.keyAction?.rawValue)
    }

    /// Project, save, reconcile pages, then windows: closed ones go, new ones are placed and
    /// shown, every one renders. A new window is key and on screen before its first render, because keyboard focus
    /// into a Chromium view only sticks in a key window.
    private func publish(docChanged: Bool) {
        snapshot = projected()
        let profiles = Set(snapshot.settings.profiles.map { $0.profile.id })
        for profile in profiles.subtracting(loadedBoostProfiles) {
            let (catalog, error) = boostFiles.read(profile)
            queue.append(.system(.boost(.loaded(profile, catalog, error: error))))
        }
        for profile in loadedBoostProfiles.subtracting(profiles) {
            do { try boostFiles.remove(profile) } catch { log.error("Could not remove Boost files: \(error.localizedDescription)") }
        }
        loadedBoostProfiles = profiles
        for (window, pick) in boostPicks {
            if snapshot.windows[window]?.boostEditor?.pickID != pick.editor || snapshot.windows[window]?.boostEditor?.picking != true {
                engine.cancelBoostPick(pick.target); boostPicks[window] = nil
            }
        }
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

    /// The settings window follows `snapshot.settings.pane` (created the first time a pane opens); the Dock shows
    /// the Icon pane's choice.
    private func renderSettings() {
        let icon = snapshot.settings.general.appIcon ?? .original
        if icon != shownIcon {
            shownIcon = icon
            NSApp.applicationIconImage = AppIconArt.image(icon, side: Self.dockIconSide)
        }
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
        for (id, controller) in windows {
            if let window = snapshot.windows[id] { controller.render(window) }
        }
        // After the windows, so a new popover anchors to the site button where this snapshot lays it out.
        sitePanels.render(snapshot.sites, owner: { windows[$0]?.window }, scheme: { snapshot.windows[$0]?.theme.scheme })
        renderSettings()
    }

    private lazy var siteTools: SiteToolsAdapter = {
        let adapter = SiteToolsAdapter { [weak self] event in self?.dispatch(.system(event)) }
        adapter.selectCalendar = { [weak self] window, file, join in
            self?.dispatch(.user(window, .tabTools(.site(.selectCalendar(file, join: join)))))
        }
        return adapter
    }()
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
    func captureAwaitsStore(_ request: CaptureRequest) -> Bool { state.captureAwaitsStore(request) }

    private func run(_ effects: [Effect]) {
        siteTools.reconcile(Set(snapshot.windows.values.compactMap { $0.tabTools.pendingSiteRequest }))
        for effect in effects {
            switch effect {
            case .capture(let effect): runCapture(effect)
            case .easel(let effect): runEasel(effect)
            case .find(let request): engine.find(request)
            case .boost(let request): runBoost(request)
            case .siteRequest(let request):
                if let window = windows[request.window]?.window { siteTools.run(request, in: window) }
            case .iconPicker(let window, let item, let initial):
                guard let owner = windows[window]?.window else { continue }
                TabIconPicker.present(for: item, in: owner, initial: initial) { [weak self, weak owner] icon in
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
            case .copySharedQuote(let page, let url, let title, let format):
                // The plain copy at once (nothing highlighted is the common case), then the link to the highlight
                // once the page answers, unless something else was copied in between.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(SharedQuote.plain(url: url, title: title, format: format), forType: .string)
                let copied = NSPasteboard.general.changeCount
                Task { @MainActor [engine] in
                    guard let selection = await engine.selectedText(page), NSPasteboard.general.changeCount == copied else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(SharedQuote.text(url: url, title: title, selection: selection, format: format), forType: .string)
                }
            case .window(let id, let effect):
                guard let window = windows[id]?.window else { continue }
                switch effect {
                case .toggleFullScreen: windows[id]?.toggleFullScreen()
                case .pageFullScreen(let on): windows[id]?.setPageFullScreen(on)
                case .leaveFullScreen: if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
                case .miniaturize: window.miniaturize(nil)
                case .close: window.performClose(nil)
                case .requestArchiveClear: windows[id]?.root.library.requestClearConfirmation()
                }
            case .app(let effect):
                switch effect {
                case .quit:
                    // "Warn before quitting": the question comes first, before anything is torn down, as a sheet on
                    // this window (no nested run loop: the key press that asked returns, and the ordered quit that
                    // follows does not run inside a modal session). While it is open another quit is ignored,
                    // except an already confirmed one (the control socket's), which quits.
                    if askingQuit { if Quit.confirmed { quitNow() }; break }
                    if Quit.confirmed || !snapshot.settings.general.warnBeforeQuitting { quitNow(); break }
                    askingQuit = true
                    confirmQuit(on: NSApp.keyWindow ?? windowController(nil)?.window) { [weak self] go in
                        guard let self else { return }
                        self.askingQuit = false
                        if go || Quit.confirmed { self.quitNow() }
                    }
                case .hide: NSApp.hide(nil)
                case .hideOthers: NSApp.hideOtherApplications(nil)
                case .beep: NSSound.beep()
                case .showAbout: aboutWindow.show(icon: snapshot.settings.general.appIcon ?? .original)
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
                case .help(let action, let owner): help.run(action, owner: owner)
                }
            case .popupMenu(let id, let model, let at):
                guard let controller = windows[id] else { continue }
                let menu = popupTarget.menu(for: model) { [weak self] command in self?.dispatch(.user(id, command)) }
                NotificationCenter.default.post(name:ContextMenuCapture.willPresent,object:menu)
                // A context menu, not a positioned popup: it opens below and right of the pointer with no row
                // highlighted, as Arc's sidebar menus do (P12). `at` is in the root view's coordinates.
                let point = controller.root.convert(at, to: nil)
                if let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [],
                                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.window.windowNumber,
                                                  context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    NSMenu.popUpContextMenu(menu, with: event, for: controller.root)
                } else {
                    menu.popUp(positioning: nil, at: at, in: controller.root)
                }
                popupTarget.clear()
            case .export(let document, let owner):
                guard let window = windows[owner]?.window else { continue }
                exports.present(document, owner: owner, in: window, selected: { [weak self] url in
                    self?.dispatch(.user(owner, .sidebarData(.exportSelected(url))))
                }, reply: { [weak self] outcome in
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
            case .ai(let id, let task, let choice): aiServices.answer(id, task: task, choice: choice, detected: snapshot.settings.max.detected)
            case .aiCancel(let id): aiServices.cancel(id)
            case .aiRead(let id, let document): aiServices.read(id, document: document)
            case .aiTranslate(let id, let content, let nodes): aiServices.translate(id, content: content, nodes: nodes)
            case .aiWatch(let id, let seconds): aiServices.watch(id, seconds: seconds)
            case .aiHover(let window, let url): aiServices.hover(window, url: url)
            case .aiRenameDownload(let id, let path, let name): aiServices.rename(id, path: path, filename: name)
            case .fetchSuggestions(let window, let query, let url):
                suggestions.fetch(window, query: query, url: url)
            case .disposeContext: break
            case .loadWebsiteRules(let file, let context):
                Task { @MainActor [weak self] in
                    let update = await Task.detached(priority: .utility) { SiteRulesFiles.read(file) }.value
                    self?.dispatch(.system(.websiteRulesLoaded(context, update)))
                }
            case .fetchFilterList(let context, let record): filterListDownloads.fetch(context, record)
            case .chooseWebsiteRules(let id, let context):
                guard let owner = windows[id]?.window, owner.attachedSheet == nil else { continue }
                let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
                SidebarPanelControl.configureTestDirectory(panel)
                panel.message = "Choose an EasyList-syntax filter list, or Brk rules JSON. A list becomes this profile's imported list; rules JSON replaces the built-in rules."
                panel.beginSheetModal(for: owner) { [weak self] response in
                    guard let self, response == .OK, let file = panel.url else { return }
                    self.dispatch(.user(id, .site(.selectedBlockingRules(file, context))))
                }
            case .editExtension(let id, let edit, let context):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error = await self.engine.editExtension(id, edit: edit, context: context) {
                        self.dispatch(.system(.extensionOperationFailed(context, error)))
                    } else {
                        self.dispatch(.system(.extensionsRead(await self.engine.extensionCatalog(context: context))))
                    }
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
            case .clearProfileData(let request):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let result = await self.engine.clearProfileData(request)
                    self.dispatch(.system(.profileDataCleared(result)))
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
        case .importSelected(let owner, let url, let format, let target):
            guard let window = windows[owner]?.window else { return }
            sidebarPanels.importSelected(url, format: format, captured: target, owner: owner, window: window)
        case .connectSelectedFolder(let owner, let url, let target):
            guard let window = windows[owner]?.window else { return }
            sidebarPanels.connectSelectedFolder(url, captured: target, owner: owner, window: window)
        case .exportSelected(let owner, let url):
            if !exports.saveSelected(url, owner: owner) {
                dispatch(.system(.exportFinished(owner, .failed("No open export belongs to this window."))))
            }
        case .cancelFilePanel(let owner):
            sidebarPanels.cancelFilePanel(owner)
            exports.ownerGone(owner)
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
final class PopupTarget: NSObject, NSMenuDelegate {
    private var commands: [Int: Command] = [:]
    private var choose: ((Command) -> Void)?

    func menu(for model: MenuModel, choose: @escaping (Command) -> Void) -> NSMenu {
        self.choose = choose
        commands.removeAll()
        let menu = build(model.entries)
        menu.delegate = self
        return menu
    }

    /// Submenus are built in place; every choosable row gets the next tag, so one table serves the whole tree.
    private func build(_ entries: [MenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func row(_ title: String, _ command: Command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: "")
            item.target = self
            item.tag = commands.count
            commands[item.tag] = command
            return item
        }
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .header(let title):
                // Arc draws its captions as plain grey rows at the menu's own size (P12-e), not AppKit's smaller
                // section headers.
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            case .action(let title, let command, let enabled):
                let item = row(title, command)
                item.isEnabled = enabled
                menu.addItem(item)
            case .choice(let title, let command, let on):
                let item = row(title, command)
                item.state = on ? .on : .off
                menu.addItem(item)
            case .submenu(let title, let children):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = build(children)
                item.isEnabled = !children.isEmpty
                menu.addItem(item)
            }
        }
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
            NotificationCenter.default.post(name: PageSurfaceView.contextMenuWillOpen, object: menu)
        }
    }
    func menuDidClose(_ menu: NSMenu) {
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
            NotificationCenter.default.post(name: PageSurfaceView.contextMenuDidClose, object: menu)
        }
    }

    func clear() { commands.removeAll(); choose = nil }

    @objc private func fire(_ sender: NSMenuItem) {
        if let command = commands[sender.tag] { choose?(command) }
    }
}

extension AppStore {
    private func runBoost(_ effect: BoostEffect) {
        func failure(_ window: WindowID, _ error: any Error) { dispatch(.system(.boost(.failed(window, error.localizedDescription)))) }
        switch effect {
        case .write(let window, let profile, let catalog, let editor):
            guard state.boostProfileForIO(window) == profile else { return }
            do {
                try boostFiles.write(catalog, profile: profile)
                dispatch(.system(.boost(.written(window, profile, catalog, editor: editor))))
            } catch { failure(window, error) }
        case .confirm(let id, let editor, let boost):
            guard let owner = windows[id]?.window, owner.attachedSheet == nil else { return }
            let alert = NSAlert()
            alert.messageText = "Allow JavaScript in “\(boost.name)”?"
            alert.informativeText = "This code can read and change matching pages: \(boost.scope.label). Only allow code you trust.\n\nChanging the code, scope or private-window permission requires confirmation again."
            alert.addButton(withTitle: "Allow JavaScript & Save"); alert.addButton(withTitle: "Cancel")
            alert.buttons[0].setAccessibilityIdentifier(ViewID.boostControl("confirm-javascript").identifier)
            alert.beginSheetModal(for: owner) { [weak self] result in
                guard result == .alertFirstButtonReturn else { return }
                self?.dispatch(.system(.boost(.approved(id, editor, boost))))
            }
        case .pick(let window, let editor, let target):
            boostPicks[window] = (editor, target)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let selector = try? await self.engine.pickBoostElement(target)
                self.dispatch(.system(.boost(.picked(window, editor, target, selector))))
            }
        case .importFile(let window, let profile, let selected):
            let read: (URL) -> Void = { [weak self] file in
                guard let self, self.state.boostProfileForIO(window) == profile else { return }
                do {
                    if let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int, size > BoostCodec.maxBytes {
                        throw CocoaError(.fileReadTooLarge, userInfo: [NSLocalizedDescriptionKey: "Boost file exceeds 10 MB."])
                    }
                    let values = try BoostCodec.imported(Data(contentsOf: file), newID: { UUID().uuidString })
                    self.dispatch(.system(.boost(.imported(window, profile, values))))
                } catch { self.dispatch(.system(.boost(.failed(window, "Cannot install Boost: " + error.localizedDescription)))) }
            }
            if let selected { read(selected) }
            else if let owner = windows[window]?.window, owner.attachedSheet == nil {
                let panel = NSOpenPanel(); panel.title = "Install Boost from File"; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                SidebarPanelControl.configureTestDirectory(panel)
                panel.beginSheetModal(for: owner) { result in if result == .OK, let url = panel.url { read(url) } }
            }
        case .exportFile(let window, let boost, let selected):
            guard let profile = state.boostProfileForIO(window) else { return }
            let write: (URL) -> Void = { [weak self] file in
                guard let self, self.state.boostProfileForIO(window) == profile else { return }
                do {
                    try BoostCodec.export(boost).write(to: file, options: .atomic)
                    self.dispatch(.system(.boost(.failed(window, "Exported “\(file.lastPathComponent)”. JavaScript approval and private permission are not exported."))))
                } catch { self.dispatch(.system(.boost(.failed(window, "Cannot export Boost: " + error.localizedDescription)))) }
            }
            if let selected { write(selected) }
            else if let owner = windows[window]?.window, owner.attachedSheet == nil {
                let panel = NSSavePanel(); panel.title = "Export Boost"; panel.nameFieldStringValue = "Boost.brkboost.json"
                SidebarPanelControl.configureTestDirectory(panel)
                panel.beginSheetModal(for: owner) { result in if result == .OK, let url = panel.url { write(url) } }
            }
        }
    }
}
