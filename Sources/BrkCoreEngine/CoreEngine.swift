import AppKit
import BrkBase
import BrkEngine
import CBrkCore
import os

/// Brk's browser engine. Each native window and browsing context owns a Chromium Browser;
/// its WebContents views attach directly to Brk's page cards.
@MainActor
public final class CoreEngine: NSObject, WebEngine, BrkCoreBrowserDelegate {
    public weak var delegate: (any WebEngineDelegate)?
    public private(set) var pageLog: [PageLogEntry] = []
    public var engineVersion: String? { runtime.application.version }

    let runtime: BrkCoreRuntime
    let resources = BrowserResources<CorePage>()
    let transfers = Transfers()
    private var appearanceObservation: NSKeyValueObservation?
    private var resourceManagement: CoreResourceManagement?
    private var live: [PageID: CorePage] {
        Dictionary(uniqueKeysWithValues: resources.entries.filter { $0.value.presented }.map { ($0.key.page, $0.value.resource) })
    }
    private var ledger = PageLedger()
    private var saveCounter = 0
    private var pendingSaves: [PageID: String] = [:]
    var contexts = ContextLifetimes()
    private var wanted: [PageSpec] = []
    private var requestedPages: [PageSpec] = []
    private var handoffPlaceholders: [PageID: PageSurfaceView] = [:]
    private let reconciliation = PageReconciliation()
    private let outputs = DocumentOutputs()
    private var outputPreparations: [OutputID: Task<Void, Never>] = [:]

    private struct BrowserKey: Hashable { let window: WindowID; let context: BrowsingContext }
    private var browsers: [BrowserKey: any BrkCoreBrowser] = [:]
    /// Loaded Chrome profiles, by Brk's id. Loading is asynchronous even for the default profile; a page waits for it.
    private var profiles: [ProfileID: any BrkCoreProfile] = [:]
    private var loading: Set<ProfileID> = []
    private var incognito: [BrowsingContext: any BrkCoreProfile] = [:]

    private struct FocusRequest { weak var window: NSWindow?; let page: PageID }
    private var focusRequests: [ObjectIdentifier: FocusRequest] = [:]
    private var running = true
    var isRunning: Bool { running }
    /// The clear in progress per context, and the ones asked to stop (site data, as on CEF).
    var clearingContexts: [BrowsingContext: String] = [:]
    var cancelledSiteClears: Set<String> = []
    private var shutdownTask: Task<ShutdownOutcome, Never>?
    private let log = Logger(subsystem: "brk", category: "core")

    public init(runtime: BrkCoreRuntime) {
        self.runtime = runtime
        super.init()
        resourceManagement = CoreResourceManagement(engine: self)
        outputs.acquire = { [weak self] id, browser in self?.resources.acquire(.documentOutput(id.rawValue), browser: browser) ?? false }
        outputs.release = { [weak self] id, browser in
            guard let self else { return }
            self.resources.release(.documentOutput(id.rawValue), browser: browser)
            self.closeIfUnowned(browser)
        }
        outputs.available = { [weak self] request, epoch in
            guard let self, self.running, self.contexts.permitsWork(epoch.context),
                  let entry = self.resources.entries[request.document.browser], entry.context == epoch,
                  entry.presented, entry.resource.readyDocument == request.document,
                  self.delegate?.engine(self, ownerWindow: request.document.browser.page.window)?.isStillOpen == true else { return false }
            return true
        }
        outputs.publish = { [weak self] update in guard let self else { return }; self.delegate?.engine(self, output: update) }
        outputs.destination = { [weak self] prompt, reply in
            guard let self, let delegate = self.delegate else { reply(.ownerGone); return }
            delegate.engine(self, outputDestination: prompt, reply: reply)
        }
        outputs.print = { [weak self] request, url, reply in
            guard let self, let delegate = self.delegate else { reply(.ownerGone); return }
            delegate.engine(self, printOutput: request, pdf: url, reply: reply)
        }
        outputs.dismiss = { [weak self] id in guard let self else { return }; self.delegate?.engine(self, dismissOutput: id) }
        outputs.render = { [weak self] request, path, done in self?.render(request, to: path, done: done) }
        transfers.publish = { [weak self] update in
            guard let self else { return }
            self.delegate?.engine(self, download: update)
        }
        transfers.prompt = { [weak self] prompt, reply in
            guard let self, let delegate = self.delegate else { reply(.ownerGone); return }
            delegate.engine(self, destination: prompt, reply: reply)
        }
        transfers.dismiss = { [weak self] ticket in
            guard let self else { return }; self.delegate?.engine(self, dismissDestination: ticket)
        }
        transfers.acquire = { [weak self] id, browser in self?.resources.acquire(.transfer(id), browser: browser) ?? false }
        transfers.release = { [weak self] id, browser in
            guard let self else { return }
            self.resources.release(.transfer(id), browser: browser)
            self.closeIfUnowned(browser)
        }
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.running else { return }
                for page in self.live.values where page.websitePolicy.appearance == .automatic { page.refreshWebsitePolicy() }
            }
        }
    }

    // MARK: Pages

    public func reconcile(_ pages: [PageSpec]) {
        guard running else { return }
        requestedPages = pages.filter { contexts.permitsWork($0.context) }
        let requestedIDs = Set(requestedPages.map(\.id))
        handoffPlaceholders = handoffPlaceholders.filter { requestedIDs.contains($0.key) }
        wanted = uniquePageOwners(requestedPages)
        reconciliation.submit(wanted, invalidate: {
            for page in Array(self.live.values) where !self.wanted.contains(where: { $0.id == page.id && $0.context == page.context }) {
                if !self.canHandoff(page) || !self.wanted.contains(where: { $0.id.item == page.id.item && $0.context == page.context }) {
                    self.retire(page)
                }
            }
        }) {
            self.applyDemand($0)
            self.resourceManagement?.reconcile()
        }
    }

    private func applyDemand(_ pages: [PageSpec]) {
        guard running else { return }
        let pages = pages.filter { contexts.permitsWork($0.context) }
        let ids = Set(pages.map(\.id))
        focusRequests = focusRequests.filter { $0.value.window != nil && ids.contains($0.value.page) }
        for spec in pages {
            guard running, contexts.permitsWork(spec.context),
                  wanted.contains(where: { $0.id == spec.id && $0.context == spec.context }) else { continue }
            if let page = live[spec.id] {
                page.downloadPolicy = spec.downloadPolicy
                page.setMuted(spec.muted)
                page.applyWebsitePolicy(spec.websitePolicy)
                page.applyBoostPolicy(spec.boostPolicy)
                continue
            }
            if handoff(to: spec) { continue }
            guard let url = spec.initialURL, let browser = browser(window: spec.id.window, context: spec.context) else { continue }
            let incarnation = ledger.create(spec.id)
            let page = CorePage(spec: spec, url: url, engine: self, incarnation: incarnation, browser: browser)
            resources.insert(page, browser: incarnation, context: contexts.epoch(for: spec.context))
            // There is no host window to wait for, only the page itself.
            resources.hostClosed(incarnation)
            record(.created, page)
            delegate?.engine(self, page: incarnation, didEmit: .browserCreated(spec.context, .unavailable))
            page.reportInitialLoading()
        }
    }

    private struct LogicalPage: Hashable { let item: ItemID; let context: BrowsingContext }

    private func canHandoff(_ page: CorePage) -> Bool {
        !page.websiteOperationProtected() && !page.contents.isLoading && page.openDialog == nil && pendingSaves[page.id] == nil
            && page.contents.committedURL?.host != "chromewebstore.google.com"
    }

    private func uniquePageOwners(_ pages: [PageSpec]) -> [PageSpec] {
        let groups = Dictionary(grouping: pages) { LogicalPage(item: $0.id.item, context: $0.context) }
        let owners = Dictionary(grouping: live.values) { LogicalPage(item: $0.id.item, context: $0.context) }
        return groups.compactMap { key, candidates in
            let existing = owners[key]?.first
            if let existing, !canHandoff(existing), let spec = candidates.first(where: { $0.id == existing.id }) { return spec }
            if let focused = candidates.first(where: { $0.websitePolicy.visible && delegate?.engine(self, ownerWindow: $0.id.window)?.isKeyWindow == true }) {
                return focused
            }
            if let existing, let spec = candidates.first(where: { $0.id == existing.id }) { return spec }
            return candidates.sorted { $0.id < $1.id }.first
        }.sorted { $0.id < $1.id }
    }

    /// Rebinds the Swift presentation while Chromium moves the same TabModel, renderer, and document.
    private func handoff(to spec: PageSpec) -> Bool {
        guard live[spec.id] == nil,
              let page = live.values.first(where: { $0.id.item == spec.id.item && $0.context == spec.context }),
              canHandoff(page), let destination = browser(window: spec.id.window, context: spec.context),
              destination.takeOwnership(of: page.contents) else { return false }
        let previous = page.incarnation
        let oldDocument = page.readyDocument
        page.find.invalidate()
        page.policyRevision &+= 1
        page.boostRevision &+= 1
        page.surface.removeFromSuperview()
        outputs.sourceGone(previous)
        transfers.sourceGone(previous)
        _ = ledger.retire(page.id)
        let replacement = ledger.create(spec.id)
        precondition(resources.transfer(previous, to: replacement))
        _ = ledger.closed(previous)
        page.id = spec.id
        page.incarnation = replacement
        page.browser = destination
        page.surface.rebind(to: spec.id)
        page.mainDocument.rebind(to: replacement)
        page.permissionGrants = page.permissionGrants.map {
            (DocumentToken(browser: replacement, sequence: $0.document.sequence), $0.requesting, $0.top, $0.capabilities)
        }
        if let document = page.readyDocument, oldDocument != nil {
            if let value = page.policyWorld { page.policyWorld = (document, value.context) }
            if let value = page.websiteStyleOwner { page.websiteStyleOwner = (document, value.id) }
            if page.boostDocument == oldDocument { page.boostDocument = document }
        }
        page.downloadPolicy = spec.downloadPolicy
        page.setMuted(spec.muted)
        page.lastResourceUse = ProcessInfo.processInfo.systemUptime
        delegate?.engine(self, page: previous, didEmit: .documentChanged(.unavailable))
        delegate?.engine(self, page: previous, didEmit: .closed)
        delegate?.engine(self, page: replacement, didEmit: .browserCreated(spec.context, page.mainDocument.availability))
        pageDidEmit(page, .documentChanged(page.mainDocument.availability))
        if let url = page.contents.committedURL { pageDidEmit(page, .locationRestored(from: previous, url: url)) }
        pageDidEmit(page, .titleChanged(page.contents.title))
        if let favicon = page.lastFavicon { pageDidEmit(page, .faviconChanged(favicon)) }
        if let document = page.readyDocument {
            pageDidEmit(page, .mediaChanged(document, page.mediaPlayers, error: nil))
            pageDidEmit(page, .selectionChanged(document, page.reportedSelection))
            if let language = page.detectedLanguage { pageDidEmit(page, .languageDetected(document, language)) }
        }
        pageDidEmit(page, .loadingChanged(isLoading: page.contents.isLoading,
                                         canGoBack: page.contents.canGoBack, canGoForward: page.contents.canGoForward))
        page.reportZoom()
        page.reportSecurity()
        checkSelection(page.id)
        page.applyWebsitePolicy(spec.websitePolicy)
        page.applyBoostPolicy(spec.boostPolicy)
        return true
    }

    /// The `Browser` of this window and context; nil while its profile loads, and the demand replays when it has.
    private func browser(window: WindowID, context: BrowsingContext) -> (any BrkCoreBrowser)? {
        let key = BrowserKey(window: window, context: context)
        let native = delegate?.engine(self, ownerWindow: window)
        if let existing = browsers[key], existing.isAlive {
            if existing.window !== native { existing.window = native }
            return existing
        }
        guard let profile = profile(for: context) else { return nil }
        let created = profile.createBrowser(for: native, delegate: self)
        browsers[key] = created
        return created
    }

    private func profile(for context: BrowsingContext) -> (any BrkCoreProfile)? {
        switch context {
        case .profile(let id): return loadedProfile(id)
        case .incognito:
            if let existing = incognito[context] { return existing }
            guard let base = loadedProfile(.default) else { return nil }
            let created = base.incognito()
            incognito[context] = created
            return created
        }
    }

    private func loadedProfile(_ id: ProfileID) -> (any BrkCoreProfile)? {
        if let loaded = profiles[id] { return loaded }
        if loading.insert(id).inserted {
            let directory = id == .default ? "Default" : ProfileDirectories.directoryName(id)
            runtime.application.loadProfile(directory) { [weak self] profile in
                guard let self else { return }
                self.loading.remove(id)
                if let profile {
                    self.profiles[id] = profile
                    self.observeExtensions(profile, context: .profile(id))
                    if self.running { self.reconcile(self.requestedPages) }
                } else {
                    self.log.fault("profile \(directory, privacy: .public) did not load")
                }
            }
        }
        return profiles[id]
    }

    public func surface(for page: PageID) -> PageSurfaceView? {
        if let surface = live[page]?.surface { return surface }
        guard requestedPages.contains(where: { $0.id == page }) else { return nil }
        if let existing = handoffPlaceholders[page] { return existing }
        let placeholder = PageHandoffPlaceholder(page: page) { [weak self] in
            guard let self else { return }
            self.delegate?.engine(self, ownerWindow: page.window)?.makeKeyAndOrderFront(nil)
            self.reconcile(self.requestedPages)
        }
        handoffPlaceholders[page] = placeholder
        return placeholder
    }

    func livePage(_ id: PageID) -> CorePage? { live[id] }
    var livePages: [CorePage] { Array(live.values) }

    public func cancelDownload(_ id: DownloadID) { transfers.cancel(id) }

    public func perform(_ action: PageAction, on page: PageID) {
        guard running else { return }
        if live[page] == nil, let spec = requestedPages.first(where: { $0.id == page }) {
            _ = handoff(to: spec)
        }
        guard let live = live[page] else { return }
        switch action {
        case .navigate, .goBack, .goForward, .reload, .recover: outputs.sourceGone(live.incarnation)
        default: break
        }
        switch action {
        case .navigate(let url): live.prepareNavigation(); live.contents.load(url)
        case .goBack: live.prepareNavigation(); live.contents.goBack()
        case .goForward: live.prepareNavigation(); live.contents.goForward()
        case .reload(let ignoringCache): live.requestReload(ignoringCache: ignoringCache)
        case .stop: live.prepareStop(); live.contents.stopLoading()
        case .zoom(let step):
            live.contents.zoomLevel = BrowserZoom.next(step, level: live.contents.zoomLevel)
            live.reportZoom()
            DispatchQueue.main.async { [weak live] in live?.reportZoom() }
        case .recover: live.prepareNavigation(); live.contents.reloadBypassingCache(false)
        case .media(let request): live.control(request)
        case .exitFullscreen: live.contents.exitFullscreen()
        case .toggleDevTools: live.contents.developerOperation("toggle")
        case .cast: live.contents.showCastDialog()
        case .developer(let operation): live.developer(operation)
        case .documentPictureInPicture(let control): live.controlDocumentPiP(control)
        }
    }

    public func focus(_ page: PageID?, in window: NSWindow) {
        guard running else { return }
        let owner = ObjectIdentifier(window)
        if let request = focusRequests[owner], request.window === window, request.page != page,
           let previous = live[request.page], previous.surface.window == nil || previous.surface.window === window {
            previous.dropFocus()
        }
        guard let page, wanted.contains(where: { $0.id == page }) else {
            focusRequests[owner] = nil
            for live in live.values where live.surface.window === window && live.surface.containsFirstResponder { live.dropFocus() }
            return
        }
        focusRequests[owner] = FocusRequest(window: window, page: page)
        guard let target = live[page], target.surface.window === window, target.surface.isReadyForFocus else { return }
        if !target.surface.containsFirstResponder { target.takeFocus() }
    }

    private func restoreFocus(_ page: CorePage) {
        guard running, live[page.id] === page, let window = page.surface.window, window.isVisible,
              let request = focusRequests[ObjectIdentifier(window)], request.window === window, request.page == page.id,
              window.firstResponder == nil || window.firstResponder === window,
              !page.surface.isHiddenOrHasHiddenAncestor, page.surface.isReadyForFocus else { return }
        page.takeFocus()
    }

    public func evaluate(_ script: String, in page: PageID) {
        guard running else { return }
        live[page]?.evaluate(script)
    }

    public func evaluateForResult(_ script: String, in page: PageID) async throws -> String? {
        guard running, let live = live[page] else { throw CocoaError(.featureUnsupported) }
        let parameters = try String(decoding: JSONSerialization.data(withJSONObject: ["expression": script, "returnByValue": true, "awaitPromise": true]), as: UTF8.self)
        let result = try await devTools(live, "Runtime.evaluate", parameters)
        guard let value = (result["result"] as? [String: Any])?["value"], !(value is NSNull) else { return nil }
        if let text = value as? String { return text }
        return String(decoding: try JSONSerialization.data(withJSONObject: [value]).dropFirst().dropLast(), as: UTF8.self)
    }

    public func selectedText(_ page: PageID) async -> String? {
        guard running, let live = live[page] else { return nil }
        let script = "(()=>{try{let d=document;while(d.activeElement?.tagName==='IFRAME'&&d.activeElement.contentDocument)d=d.activeElement.contentDocument;return d.getSelection().toString().slice(0,4000)}catch{return ''}})()"
        guard let text = try? await evaluateForResult(script, in: live.id), !text.isEmpty else { return nil }
        return text
    }

    private func devTools(_ page: CorePage, _ method: String, _ parameters: String) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            page.contents.sendDevToolsCommand(method, parameters: parameters) { result, error in
                if let result, let data = result.data(using: .utf8),
                   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    continuation.resume(returning: json)
                } else {
                    continuation.resume(throwing: NSError(domain: "BrkCore", code: 1, userInfo: [NSLocalizedDescriptionKey: error ?? "DevTools gave no answer"]))
                }
            }
        }
    }

    public func facts(for id: PageID) -> PageFacts? {
        guard let page = live[id] else { return nil }
        var facts = page.facts
        facts.context = page.context
        // As CEF's request context: a private window's data is in memory, with no folder.
        if case .profile(let profile) = page.context { facts.nativeContextPath = profiles[profile]?.path }
        facts.nativeContextIsGlobal = page.context == .profile(.default)
        return facts
    }

    /// As CEF: while the page's video is in picture in picture, the site rules treat the page as playing.
    public func setPictureInPicture(_ active: Bool, document: DocumentToken) {
        guard running, let page = live[document.browser.page], page.incarnation == document.browser, page.readyDocument == document else { return }
        page.pictureInPictureDocument = active ? document : nil
        page.refreshWebsitePolicy()
    }

    // MARK: Cookie import

    /// Onboarding's import: the cookies go into the profile's cookie store, as CEF's cookie manager writes them (same address rule).
    public func importCookies(_ cookies: [ImportedCookie], profile: ProfileID) async throws -> Int {
        guard running else { throw CoreProtocolError(message: "The profile is closing") }
        guard !cookies.isEmpty else { return 0 }
        guard let target = await profileNow(profile) else { throw CoreProtocolError(message: "The profile did not load") }
        let rows: [[String: Any]] = cookies.map { cookie in
            let host = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            var row: [String: Any] = [
                "url": (cookie.secure ? "https://" : "http://") + host + (cookie.path.hasPrefix("/") ? cookie.path : "/"),
                "name": cookie.name, "value": cookie.value, "domain": cookie.domain.hasPrefix(".") ? cookie.domain : "",
                "path": cookie.path, "secure": cookie.secure, "httpOnly": cookie.httpOnly,
                "sameSite": cookie.sameSite, "priority": cookie.priority,
            ]
            func seconds(_ instant: Instant?) -> Double? { instant.map { Double($0.milliseconds) / 1000 } }
            row["expires"] = seconds(cookie.expires)
            row["creation"] = seconds(cookie.creation)
            row["lastAccess"] = seconds(cookie.lastAccess)
            return row
        }
        let accepted = await withCheckedContinuation { (continuation: CheckedContinuation<UInt, Never>) in
            target.setCookies(rows) { continuation.resume(returning: $0) }
        }
        return Int(accepted)
    }

    /// The profile, loaded now if it is not yet (a first-run import comes before any page).
    private func profileNow(_ id: ProfileID) async -> (any BrkCoreProfile)? {
        if let loaded = profiles[id] { return loaded }
        let directory = id == .default ? "Default" : ProfileDirectories.directoryName(id)
        /// The framework calls back on the main thread; the profile object only crosses that one hop.
        final class Loaded: @unchecked Sendable { var profile: (any BrkCoreProfile)? }
        let box = Loaded()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            runtime.application.loadProfile(directory) { profile in
                box.profile = profile
                continuation.resume()
            }
        }
        if let loaded = box.profile, profiles[id] == nil {
            profiles[id] = loaded
            observeExtensions(loaded, context: .profile(id))
        }
        return box.profile
    }

    // MARK: Find

    public func find(_ request: FindRequest) {
        guard running, let page = live[request.document.browser.page], page.incarnation == request.document.browser else { return }
        page.find.perform(request)
    }

    func findUpdated(_ update: FindUpdate) { delegate?.engine(self, find: update) }

    /// As CEF: whether the page has a selection now, reported when it changes.
    public func checkSelection(_ id: PageID) {
        guard running, let page = live[id], !page.isAIReader, let document = page.readyDocument else { return }
        Task { @MainActor [weak self, weak page] in
            let text = await self?.selectedText(id)
            guard let self, let page, self.isLive(page), page.readyDocument == document else { return }
            let selected = !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard page.reportedSelection != selected else { return }
            page.reportedSelection = selected
            self.pageDidEmit(page, .selectionChanged(document, selected))
        }
    }

    // MARK: Output

    public func output(_ request: OutputRequest) {
        guard let entry = resources.entries[request.document.browser] else {
            delegate?.engine(self, output: OutputUpdate(id: request.id, document: request.document, stage: .terminal(.failed("Document has closed", .absent))))
            return
        }
        outputs.start(request, context: entry.context)
    }

    public func cancelOutput(_ id: OutputID) { outputs.cancel(id) }

    /// MHTML and PDF from the page's DevTools session, the same call Chrome's own "print to PDF" path answers.
    private func render(_ request: OutputRequest, to path: URL, done: @escaping (Result<Void, Error>) -> Void) {
        guard let page = resources.entries[request.document.browser]?.resource, page.readyDocument == request.document else {
            done(.failure(CocoaError(.userCancelled))); return
        }
        outputPreparations[request.id] = Task { @MainActor [weak self] in
            guard let self else { done(.failure(CocoaError(.userCancelled))); return }
            defer { self.outputPreparations[request.id] = nil }
            do {
                guard self.running, self.outputs.permitsRender(request.id), page.readyDocument == request.document else { throw CocoaError(.userCancelled) }
                let data: Data
                if request.intent == .mhtml {
                    let result = try await self.devTools(page, "Page.captureSnapshot", #"{"format":"mhtml"}"#)
                    guard let text = result["data"] as? String else { throw CocoaError(.fileWriteUnknown) }
                    data = Data(text.utf8)
                } else {
                    let result = try await self.devTools(page, "Page.printToPDF", #"{"printBackground":true}"#)
                    guard let text = result["data"] as? String, let decoded = Data(base64Encoded: text) else { throw CocoaError(.fileWriteUnknown) }
                    data = decoded
                }
                try data.write(to: path, options: .withoutOverwriting)
                done(.success(()))
            } catch { done(.failure(error)) }
        }
    }

    // MARK: Closing

    public func disposeContext(_ request: ContextDisposal) {
        contexts.revoke(request.context)
        wanted.removeAll { $0.context == request.context }
        outputs.revoke(request.context)
        transfers.revoke(request.context)
        for page in live.values where page.context == request.context { retire(page) }
        Task { @MainActor in
            let drained = await self.waitUntil(timeout: Metrics.persistence.shutdownTimeout.value) {
                !self.reconciliation.isApplying && !self.resources.entries.values.contains { $0.context.context == request.context }
                    && !self.outputs.contains(context: request.context) && !self.transfers.contains(context: request.context)
            }
            let result: ContextDisposalResult
            if drained {
                switch request.context {
                case .incognito:
                    self.incognito[request.context] = nil
                    result = .completed(request.id, request.context, .memoryReleased)
                case .profile(let id):
                    // Chromium holds the profile's folder while it runs: the next launch deletes it, as on CEF.
                    self.profiles[id] = nil
                    for (key, browser) in self.browsers where key.context == request.context {
                        if browser.isAlive { browser.close() }
                        self.browsers[key] = nil
                    }
                    do {
                        try ProfileDirectories(root: self.runtime.userDataDirectory).mark(id)
                        result = .completed(request.id, request.context, .deletionScheduledForNextLaunch)
                    } catch {
                        result = .failed(request.id, request.context, reason: error.localizedDescription)
                    }
                }
            } else {
                self.transfers.reportTimeout(context: request.context)
                result = .failed(request.id, request.context, reason: "Context callbacks did not drain")
            }
            self.delegate?.engine(self, contextDisposed: result)
        }
    }

    public func shutdown() async -> ShutdownOutcome {
        if let shutdownTask { return await shutdownTask.value }
        let task = Task { @MainActor in await self.runShutdown() }
        shutdownTask = task
        return await task.value
    }

    /// Every page closes first. Chromium's own shutdown comes after the app replies to `applicationShouldTerminate`, which is what ends
    /// `BrkCoreRuntime.run` and so the process (`-[BrowserCrApplication replyToApplicationShouldTerminate:]`).
    private func runShutdown() async -> ShutdownOutcome {
        running = false
        resourceManagement?.stop()
        focusRequests.removeAll()
        wanted = []
        contexts.stop()
        outputs.stop()
        transfers.stop()
        for page in live.values { retire(page) }
        // Test instances say what the quit waits for, once a second (as CEFEngine's "fixture cef" lines).
        let traced = ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil, began = ProcessInfo.processInfo.systemUptime
        var said = began
        let drained = await waitUntil(timeout: Metrics.persistence.shutdownTimeout.value) {
            if traced, ProcessInfo.processInfo.systemUptime - said >= 1 {
                said = ProcessInfo.processInfo.systemUptime
                let pending = self.resources.entries.map { "\($0.key.page.item.rawValue.prefix(8)) presented=\($0.value.presented) leases=\($0.value.leases.count) closing=\($0.value.closing) closed=\($0.value.browserClosed)" }
                FileHandle.standardError.write(Data("fixture core: waiting at +\(Int(said - began)) s: outputs empty=\(self.outputs.isEmpty) preparing=\(self.outputPreparations.count) pages=\(pending)\n".utf8))
            }
            return !self.reconciliation.isApplying && self.outputs.isEmpty && self.outputPreparations.isEmpty && self.transfers.isEmpty
                && self.resources.entries.isEmpty
        }
        if traced { FileHandle.standardError.write(Data("fixture core: pages \(drained ? "closed" : "did not close") at +\(String(format: "%.2f", ProcessInfo.processInfo.systemUptime - began)) s\n".utf8)) }
        guard drained else {
            outputs.reportTimeout()
            transfers.reportTimeout()
            return .timedOut(unclosed: resources.entries.keys.map(\.page).sorted())
        }
        for browser in browsers.values where browser.isAlive { browser.close() }
        browsers.removeAll()
        return .clean
    }

    private func waitUntil(timeout: Double, _ predicate: @escaping @MainActor () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !predicate() {
            if ProcessInfo.processInfo.systemUptime >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    // MARK: Save prompts

    /// Chromium's offer to save what a page sent, asked through the app (Arc's card, the same as CEF's path). A newer offer of
    /// the page replaces an older one; a page that goes withdraws its card.
    func offerSave(_ page: CorePage, _ offer: any BrkCoreSaveOffer) {
        guard isLive(page), let delegate else { offer.answer(.notNow); return }
        saveCounter += 1
        let id = "core-save-\(saveCounter)"
        let kind: SavePrompt.Kind = switch offer.kind {
        case .address: .address
        case .card: .card
        default: .password
        }
        if let older = pendingSaves[page.id] { delegate.engine(self, dismissSave: older) }
        pendingSaves[page.id] = id
        delegate.engine(self, save: SavePrompt(id: id, page: page.id, kind: kind, site: offer.site)) { [weak self] answer in
            if self?.pendingSaves[page.id] == id { self?.pendingSaves[page.id] = nil }
            switch answer {
            case .save: offer.answer(.save)
            case .never: offer.answer(.never)
            case .notNow: offer.answer(.notNow)
            }
        }
    }

    private func withdrawSave(_ page: CorePage) {
        guard let id = pendingSaves.removeValue(forKey: page.id) else { return }
        delegate?.engine(self, dismissSave: id)
    }

    private func retire(_ page: CorePage) {
        guard ledger.isLive(page.incarnation), ledger.retire(page.id) == page.incarnation else { return }
        withdrawSave(page)
        resources.unpresent(page.incarnation)
        page.park()
        outputs.sourceGone(page.incarnation)
        transfers.sourceGone(page.incarnation)
        closeIfUnowned(page.incarnation)
    }

    func closeIfUnowned(_ browser: BrowserToken) {
        guard resources.beginClose(browser), let page = resources.entries[browser]?.resource else { return }
        record(.closeRequested, page)
        page.close()
    }

    private func record(_ kind: PageLogEntry.Kind, _ page: CorePage) {
        pageLog.append(PageLogEntry(page: page.id, generation: page.incarnation.generation, kind: kind,
                                    browserID: Int(page.contents.tabID), uptime: ProcessInfo.processInfo.systemUptime))
        // As on CEF: the newest entries are enough at quit, and a long session must not grow it.
        if pageLog.count > 4096 { pageLog.removeFirst(pageLog.count - 4096) }
    }

    // MARK: Called by CorePage

    func isLive(_ page: CorePage) -> Bool { running && ledger.isLive(page.incarnation) && live[page.id] === page }

    func pageLoadProgress(_ page: CorePage, progress: Double) {
        guard progress.isFinite else { return }
        pageDidEmit(page, .loadProgress(min(1, max(0, progress))))
    }

    func pageDidEmit(_ page: CorePage, _ event: PageEvent) {
        guard isLive(page) else { return }
        page.find.observe(event)
        switch event {
        case .navigationRequested, .rendererGone: outputs.sourceGone(page.incarnation)
        case .gainedFocus:
            guard page.surface.window?.isVisible == true, !page.surface.isHiddenOrHasHiddenAncestor else { return }
        default: break
        }
        delegate?.engine(self, page: page.incarnation, didEmit: event)
        switch event {
        case .committed, .locationRestored, .loadingChanged, .titleChanged: restoreFocus(page)
        default: break
        }
    }

    func pageKeyHandling(_ page: CorePage, _ press: KeyPress, stage: KeyStage, pressID: PressID) -> KeyHandling {
        guard isLive(page), page.surface.window?.isVisible == true, !page.surface.isHiddenOrHasHiddenAncestor else { return KeyHandling(handled: false, shortcut: false) }
        return delegate?.engine(self, page: page.id, keyHandling: press, stage: stage, pressID: pressID) ?? KeyHandling(handled: false, shortcut: false)
    }

    func pageShouldNavigate(_ page: CorePage, to url: URL, userGesture: Bool) -> Bool {
        guard running, live[page.id] === page else { return true }
        return delegate?.engine(self, page: page.id, shouldNavigateTo: url, userGesture: userGesture) ?? true
    }

    func pageReadyForFocus(_ page: CorePage) { restoreFocus(page) }

    func permission(_ page: CorePage, prompt: SitePermissionPrompt, reply: @escaping @MainActor (SitePermission) -> Void) {
        guard isLive(page), page.matchesPermission(prompt.target), contexts.permitsWork(page.context) else { reply(.deny); return }
        delegate?.engine(self, permission: prompt, reply: reply) ?? reply(.deny)
    }

    func dismissPermission(_ id: String) { delegate?.engine(self, dismissPermission: id) }

    func pageDidClose(_ page: CorePage) {
        record(.closed, page)
        let effect = ledger.closed(page.incarnation)
        transfers.browserClosed(page.incarnation)
        resources.unpresent(page.incarnation)
        resources.browserClosed(page.incarnation)
        switch effect {
        case .retiredClosed(let liveAgain):
            if !liveAgain, running { delegate?.engine(self, page: page.incarnation, didEmit: .closed) }
        case .liveClosedByPage:
            focusRequests = focusRequests.filter { $0.value.page != page.id }
            if running {
                delegate?.engine(self, page: page.incarnation, didEmit: .closedByPage)
                delegate?.engine(self, page: page.incarnation, didEmit: .closed)
            }
        case .stale: break
        }
        outputs.sourceGone(page.incarnation)
    }

    // MARK: Extensions

    public func invokeExtension(_ id: String, target: SiteTarget) async -> String? {
        guard running, let page = live[target.page], page.readyDocument == target.document else { return "The originating website changed" }
        page.browser.activate(page.contents)
        return page.browser.executeExtensionAction(id)
    }

    public func extensionCatalog(context: BrowsingContext) async -> ExtensionCatalog {
        guard case .profile(let id) = context else {
            return ExtensionCatalog(context: context, extensions: [], error: "Extension management is unavailable in private windows")
        }
        guard let profile = await profileWhenLoaded(id) else {
            return ExtensionCatalog(context: context, extensions: [], error: "The profile did not load")
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            profile.whenExtensionsReady { continuation.resume() }
        }
        // Incognito access and commands as Chrome's own extensions page reads them (developerPrivate), when the profile has that page
        // open, as on CEF; the action and the list are the profile's own.
        let managed = await managerExtensionInfo(context: context)
        let values = profile.installedExtensions().map { item in
            let row = managed[item.extensionID]
            return BrowserExtension(id: item.extensionID, name: item.name, version: item.version, enabled: item.enabled,
                                    supportsNativeAction: item.hasAction, incognitoAllowed: row?.incognitoAllowed,
                                    canChangeIncognito: row?.canChangeIncognito, commands: row?.commands, icon: item.iconData)
        }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        return ExtensionCatalog(context: context, extensions: values, error: nil)
    }

    func profileWhenLoaded(_ id: ProfileID) async -> (any BrkCoreProfile)? {
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let profile = loadedProfile(id) { return profile }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    public func installExtension(at directory: URL, context: BrowsingContext, in page: PageID) async -> String? {
        guard case .profile(let id) = context, let profile = await profileWhenLoaded(id) else { return "Private installation is disabled" }
        return await withCheckedContinuation { continuation in
            profile.installUnpackedExtension(atPath: directory.path) { _, error in continuation.resume(returning: error) }
        }
    }

    // MARK: BrkCoreBrowserDelegate: an extension's action popup

    public func browser(_ browser: any BrkCoreBrowser, requestsOpeningExtensionOptions url: URL, extensionID: String, source: any BrkCoreWebContents) {
        guard let page = livePages.first(where: { $0.browser === browser && $0.contents === source }) else { return }
        if popupBrowser === browser { browser.closeExtensionPopup() }
        Task { @MainActor [weak self, weak page] in
            guard let self, let page, self.isLive(page) else { return }
            let catalog = await self.extensionCatalog(context: page.context)
            guard self.isLive(page), page.browser === browser else { return }
            self.delegate?.engine(self, extensionsDidChange: catalog)
            self.pageDidEmit(page, .extensionOptionsRequested(id: extensionID, url: url))
        }
    }

    private var popupPanel: NSWindow?
    private var popupObservers: [NSObjectProtocol] = []
    private weak var popupBrowser: (any BrkCoreBrowser)?
    /// The user moved the popup's window; it then stays where they put it (Arc's `userHasMovedWindow`).
    private var popupMoved = false

    /// Arc 1.170's `Arc.BrowserExtensionWindow`, read from its binary (docs/chromium/ARC-ENGINE.md, "The action popup"): an NSWindow made with
    /// the titled and closable style and buffered backing, moved by its background, a full-screen auxiliary, never a tab, a child of the
    /// browser window, its frame remembered under one autosave name once the user moved it. Escape and losing key close it, as Chrome's bubble.
    public func browser(_ browser: any BrkCoreBrowser, didOpenExtensionPopup extensionID: String, view: NSView) {
        closePopupPanel()
        let panel = ExtensionPopupPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled, .closable],
                                        backing: .buffered, defer: false)
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = .fullScreenAuxiliary
        panel.tabbingMode = .disallowed
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak browser] in browser?.closeExtensionPopup() }
        panel.contentView = view
        let saved = UserDefaults.standard.string(forKey: ExtensionPopupPanel.autosaveName).map(NSPointFromString)
        popupMoved = saved != nil
        if let saved { panel.setFrameTopLeftPoint(saved) }
        placePopup(panel, for: browser, size: NSSize(width: 25, height: 25))
        browser.window?.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        browser.focusExtensionPopup()
        popupPanel = panel
        popupBrowser = browser
        popupObservers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { _ in
                MainActor.assumeIsolated { [weak browser] in browser?.closeExtensionPopup() }
            },
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { _ in
                MainActor.assumeIsolated { [weak browser] in browser?.closeExtensionPopup() }
            },
            // Posted when the user starts dragging it, not for the placement here.
            NotificationCenter.default.addObserver(forName: NSWindow.willMoveNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.popupMoved = true }
            },
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self, weak panel] _ in
                MainActor.assumeIsolated {
                    guard let self, let panel, self.popupMoved else { return }
                    UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: panel.frame.minX, y: panel.frame.maxY)), forKey: ExtensionPopupPanel.autosaveName)
                }
            },
        ]
    }

    public func browser(_ browser: any BrkCoreBrowser, didResizeExtensionPopup extensionID: String, size: NSSize) {
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
            FileHandle.standardError.write(Data("fixture core: popup \(extensionID.prefix(8)) size \(Int(size.width))x\(Int(size.height)) panel=\(popupPanel != nil)\n".utf8))
        }
        guard let popupPanel else { return }
        placePopup(popupPanel, for: browser, size: size)
    }

    public func browser(_ browser: any BrkCoreBrowser, didCloseExtensionPopup extensionID: String) { closePopupPanel() }

    private func closePopupPanel() {
        for observer in popupObservers { NotificationCenter.default.removeObserver(observer) }
        popupObservers = []
        guard let panel = popupPanel else { return }
        popupPanel = nil
        panel.parent?.removeChildWindow(panel)
        panel.contentView = nil
        panel.orderOut(nil)
    }

    /// Chrome's size limits (25x25 to 800x600). Under the owner window's top right, where Brk's site controls open it, until the user moves
    /// it; then its top left stays where they left it and only the size follows the page.
    private func placePopup(_ panel: NSWindow, for browser: any BrkCoreBrowser, size: NSSize) {
        let content = NSSize(width: min(max(size.width, 25), 800), height: min(max(size.height, 25), 600))
        let frame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        if popupMoved {
            let top = panel.frame.maxY
            panel.setFrame(NSRect(x: panel.frame.minX, y: top - frame.height, width: frame.width, height: frame.height), display: true)
            return
        }
        let owner = browser.window?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: owner.maxX - frame.width - 12, y: owner.maxY - frame.height - 48, width: frame.width, height: frame.height), display: true)
    }
}

/// The window an extension's action popup shows in (Arc's `BrowserExtensionWindow` is an NSWindow too).
private final class ExtensionPopupPanel: NSWindow {
    /// Where the user last left it (top left). Arc keeps its frame under one defaults key, `browserExtensionWindowAutosaveFrame`.
    static let autosaveName = "BrkExtensionPopupTopLeft"
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
