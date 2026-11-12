import AppKit
import BrkBase
import BrkContent
import BrkControl
import BrkDomain
import BrkEngine
import BrkImport
import BrkUIKit
import Foundation
import UniformTypeIdentifiers

/// The first-run onboarding window (in place of the old Welcome alert) and the Import from Another Browser… window.
/// Owns only the flow: which screen, what is picked, what was read. What changes the browser goes through AppStore:
/// one `browserImported` event for everything the import brings, `completeOnboarding` at the end, and the existing
/// commands for the theme, the ad blocker and Max. Passwords go into the profile's Login Data (`PasswordImport`),
/// cookies through the engine's cookie store.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    struct Host {
        var snapshot: @MainActor () -> AppSnapshot
        var target: @MainActor (WindowID) -> SidebarImportTarget?
        var dispatch: @MainActor (Input) -> Void
        var engine: any WebEngine
        var now: @MainActor () -> Instant
        var showBrowserWindow: @MainActor (WindowID) -> Void
        /// Reads what the user picked, off the main thread (tests answer without files or the keychain).
        var read: @Sendable (ImportChoice, @escaping @Sendable (String?) -> Void) -> ImportRead = BrowserImportRun.read
    }

    private let host: Host
    private(set) var window: NSWindow?
    private var surface: (any OnboardingSurface)?
    private var owner = WindowID("")
    private(set) var state = OnboardingSnapshot()
    private var history: [OnboardingStep] = []
    private var discovered: [DiscoveredBrowser] = []
    private var selectedProfiles: Set<String> = []
    private var safariFile: URL?
    private var read: ImportRead?
    /// The Space and profile the import started from: the passwords, the cookies and then the rest land there, even if
    /// the browser window shows another Space by the time Import is clicked.
    private var importTarget: SidebarImportTarget?
    private var applied = false
    private var importTask: Task<Void, Never>?
    private var passwordsWritten = 0, passwordsStaged = 0, cookiesSet = 0
    // Bookmarks: the combined tree, ids are index paths ("0.2.1").
    private var nodes: [ImportNode] = []
    private var selection: Set<String> = []
    private var expanded: Set<String> = []
    private var starred: Set<String> = []
    private var leafCount = 0
    private var sites: [SourceTopSite] = []
    private var pickedSites: Set<String> = []

    init(host: Host) { self.host = host }

    var isOpen: Bool { window != nil }

    // MARK: Opening and closing

    func open(mode: OnboardingMode, owner: WindowID) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        self.owner = owner
        state = OnboardingSnapshot()
        state.mode = mode
        state.step = mode == .firstRun ? .welcome : .pickBrowser
        state.isDefaultBrowser = DefaultBrowser.isDefault()
        state.blockAds = host.snapshot().settings.general.blockAds != false
        history = []; read = nil; importTarget = nil; applied = false; safariFile = nil
        passwordsWritten = 0; passwordsStaged = 0; cookiesSet = 0
        discover()
        let size = OnboardingLayoutSize.fitted
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = mode == .firstRun ? "Welcome to \(Product.name)" : "Import from Another Browser"
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("brk-onboarding")
        window.delegate = self
        let surface = OnboardingViews.make(dispatch: { [weak self] in self?.handle($0) }, appIcon: NSApp.applicationIconImage)
        surface.view.frame = CGRect(origin: .zero, size: size)
        surface.view.autoresizingMask = [.width, .height]
        window.contentView = surface.view
        window.center()
        self.surface = surface
        self.window = window
        render()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Closing the first-run window finishes setup with what was picked, so the browser window appears.
        if state.mode == .firstRun { finish(); return false }
        close()
        return false
    }

    func close() {
        importTask?.cancel(); importTask = nil
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        surface = nil
    }

    // MARK: Actions

    func handle(_ action: OnboardingAction) {
        switch action {
        case .next: next()
        case .back:
            // While macOS asks for the password the read is under way; its answer would take over whatever screen is up.
            guard !state.waitingForPassword, let previous = history.popLast() else { return }
            state.step = previous
            state.mustQuit = nil
        case .skip: skip()
        case .setName(let name): state.name = String(name.prefix(60))
        case .pickBrowser(let id):
            state.selectedBrowser = id
            state.mustQuit = nil
            let kind = BrowserKind(rawValue: id)
            state.browserName = kind?.name ?? "a file"
            state.browserSentence = kind?.importsSentence ?? "Choose a bookmarks HTML or JSON file, a history JSON file, or a passwords CSV file you exported."
            selectedProfiles = Set(discovered.first { $0.kind == kind }?.profiles.map(\.id) ?? [])
        case .toggleProfile(let id):
            if selectedProfiles.contains(id) { selectedProfiles.remove(id) } else { selectedProfiles.insert(id) }
        case .importSecrets(let on): state.importSecrets = on
        case .beginImport: beginImport()
        case .chooseSafariFile: chooseFile(types: [.zip, .folder], directories: true) { [weak self] url in self?.useSafariFile(url) }
        case .useSafariFile(let url): useSafariFile(url)
        case .openSafari:
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Safari.app"), configuration: NSWorkspace.OpenConfiguration())
        case .openFullDiskAccess:
            if state.step == .safari { go(.safariLegacy) }
            else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
        case .toggleBookmark(let id): toggleBookmark(id)
        case .expandBookmark(let id):
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        case .selectAllBookmarks(let on): selection = on ? Set(leafIDs(nodes, prefix: "")) : []
        case .toggleSite(let id):
            if pickedSites.contains(id) { pickedSites.remove(id) } else { pickedSites.insert(id) }
        case .theme(let theme):
            state.theme = theme
            if let target = host.target(owner) { host.dispatch(.user(owner, .space(.update(target.space, title: nil, icon: nil, theme: theme)))) }
        case .blockAds(let on): state.blockAds = on
        case .enableMax(let on):
            if on { host.dispatch(.user(owner, .settings(.max(.enable(true))))) }
            state.maxOn = on
            go(state.isDefaultBrowser ? .finish : .defaultBrowser)
        case .makeDefault(let on):
            if on { host.dispatch(.user(owner, .app(.setAsDefaultBrowser))) }
            go(.finish)
        case .restart: restart()
        case .finish: finish()
        }
        render()
    }

    private func go(_ step: OnboardingStep) {
        history.append(state.step)
        state.step = step
        if step == .finish { refreshSummary(final: true) }
    }

    private func next() {
        switch state.step {
        case .welcome: go(.name)
        case .name: go(.pickBrowser)
        case .pickBrowser:
            guard let id = state.selectedBrowser else { return }
            if id == "file" {
                chooseFile(types: [.json, .html, .commaSeparatedText], directories: false) { [weak self] url in self?.start(.file(url)) }
                return
            }
            guard let kind = BrowserKind(rawValue: id) else { return }
            if kind == .safari { go(.safari); return }
            if kind == .firefox, kind.bundleIdentifiers.contains(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) {
                state.mustQuit = "Quit Firefox to continue importing"; return
            }
            let profiles = discovered.first { $0.kind == kind }?.profiles ?? []
            if profiles.count > 1 { go(.profiles) }
            else if kind == .firefox { start(.browser(kind, profiles)) }
            else { go(.keychain) }
        case .profiles:
            guard let kind = state.selectedBrowser.flatMap(BrowserKind.init(rawValue:)) else { return }
            if kind == .firefox { start(.browser(kind, chosenProfiles(kind))) } else { go(.keychain) }
        case .keychain, .safari, .safariLegacy: beginImport()
        case .progress:
            guard state.progressDone else { return }
            if leafCount > 0 { go(.bookmarks) } else { applyImport(); afterImport() }
        case .bookmarks: applyImport(); afterImport()
        case .favorites: go(.theme)
        case .theme: go(.adBlocker)
        case .adBlocker:
            host.dispatch(.user(owner, .settings(.general(.blockAds(state.blockAds)))))
            go(.max)
        case .max: handle(.enableMax(true)); return
        case .defaultBrowser: go(.finish)
        case .finish: finish()
        }
    }

    private func skip() {
        switch state.step {
        case .name: state.name = ""; go(.pickBrowser)
        case .pickBrowser, .safari, .safariLegacy:
            if state.mode == .importOnly { close(); return }
            prepareSites(); go(.favorites)
        case .bookmarks: selection = []; applyImport(); afterImport()
        case .favorites: pickedSites = []; go(.theme)
        case .theme: go(.adBlocker)
        case .max:
            // After Enable Max and Back, "Not now" is the answer that counts.
            if state.maxOn { host.dispatch(.user(owner, .settings(.max(.enable(false))))) }
            state.maxOn = false; go(state.isDefaultBrowser ? .finish : .defaultBrowser)
        default: next()
        }
    }

    private func afterImport() {
        // The import is in; going back cannot re-run it (Arc resets the destination instead; Brk dedupes, so a second
        // import later is the way to add more).
        history = []
        if state.mode == .importOnly { go(.finish); history = []; return }
        if read?.hasArcFavorites == true {
            // Arc's own Favorites came over one to one; the Favorites step and its picks are not needed.
            sites = []; pickedSites = []
            go(.theme)
        } else {
            prepareSites()
            go(.favorites)
        }
        history = []
    }

    // MARK: Discovery and import

    private var applicationSupport: URL {
        if ImportKeys.testing, let root = ProcessInfo.processInfo.environment["BRK_TEST_IMPORT_ROOT"], !root.isEmpty {
            return URL(fileURLWithPath: root, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private func discover() {
        discovered = BrowserCatalog.discover(applicationSupport: applicationSupport)
        var tiles = discovered.map { browser -> OnboardingBrowserTile in
            let app = browser.kind.bundleIdentifiers.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
            let count = browser.profiles.count
            let detail = browser.kind == .safari ? "Export file" : (count == 1 ? "1 profile" : "\(count) profiles")
            return OnboardingBrowserTile(id: browser.kind.rawValue, name: browser.kind.name, detail: detail, appPath: app?.path)
        }
        tiles.append(OnboardingBrowserTile(id: "file", name: "From a file…", detail: "HTML, JSON or CSV", appPath: nil))
        state.browsers = tiles
    }

    private func chosenProfiles(_ kind: BrowserKind) -> [SourceProfile] {
        (discovered.first { $0.kind == kind }?.profiles ?? []).filter { selectedProfiles.contains($0.id) }
    }

    private func useSafariFile(_ url: URL) {
        safariFile = url
        state.safariFile = url.path
        state.safariError = nil
        render()
    }

    private func beginImport() {
        switch state.step {
        case .keychain:
            guard let kind = state.selectedBrowser.flatMap(BrowserKind.init(rawValue:)) else { return }
            start(.browser(kind, chosenProfiles(kind)))
        case .safari:
            guard let safariFile else { state.safariError = "Choose the .zip file Safari exported."; return }
            start(.safariExport(safariFile))
        case .safariLegacy:
            let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/Bookmarks.plist")
            guard FileManager.default.isReadableFile(atPath: plist.path) else {
                state.safariError = "Brk does not have Full Disk Access yet. Turn it on in System Settings, then try again."; return
            }
            start(.safariLegacy)
        default: break
        }
    }

    private func start(_ source: ImportChoice.Source) {
        importTarget = host.target(owner)
        let choice = ImportChoice(source: source, secrets: state.importSecrets, now: host.now(), applicationSupport: applicationSupport,
                                  library: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true))
        let secretsWanted: Bool
        if case .browser(let kind, _) = source { secretsWanted = state.importSecrets && kind.isChromium } else { secretsWanted = false }
        if secretsWanted { state.waitingForPassword = true; state.waitingProfile = choice.source.firstProfileName }
        else { beginProgress() }
        render()
        let report: @Sendable (String?) -> Void = { [weak self] profile in
            Task { @MainActor in self?.waiting(profile) }
        }
        let read = host.read
        importTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) { read(choice, report) }.value
            guard let self, !Task.isCancelled else { return }
            if self.state.step != .progress { self.beginProgress() }
            self.state.waitingForPassword = false
            await self.finishRead(result)
        }
    }

    private func waiting(_ profile: String?) {
        if let profile { state.waitingForPassword = true; state.waitingProfile = profile }
        else { state.waitingForPassword = false; if state.step != .progress { beginProgress() } }
        render()
    }

    private func beginProgress() {
        state.progressTitle = "Importing from \(state.browserName.isEmpty ? "your browser" : state.browserName)"
        state.progressDetail = "Reading bookmarks and history…"
        state.progressDone = false
        state.failures = []
        state.summary = []
        if state.step != .progress { go(.progress) }
    }

    private func finishRead(_ result: ImportRead) async {
        read = result
        // The Favorites step offers this read's sites; a skip before the import filled the built-in list.
        sites = []; pickedSites = []
        var failures = result.failures
        state.summary = readSummary(result)
        render()
        guard host.target(owner) != nil, let target = importTarget else { state.failures = failures + ["The browser window closed"]; state.progressDone = true; render(); return }
        // Brk profiles an Arc import names must exist before their passwords and cookies can be written.
        let names = Set(result.profiles.compactMap(\.brkProfile))
        for name in names where !host.snapshot().settings.profiles.contains(where: { $0.profile.name.caseInsensitiveCompare(name) == .orderedSame }) {
            host.dispatch(.user(owner, .profile(.create(name: name, icon: nil))))
        }
        func profileID(_ name: String?) -> ProfileID {
            guard let name else { return target.profile }
            return host.snapshot().settings.profiles.first { $0.profile.name.caseInsensitiveCompare(name) == .orderedSame }?.profile.id ?? target.profile
        }
        // Passwords first: a profile Chromium has not opened yet takes them at once; cookies then open it.
        for item in result.profiles where !item.read.logins.isEmpty {
            state.progressDetail = "Saving passwords…"; render()
            do {
                let outcome = try PasswordImport.write(item.read.logins, profile: profileID(item.brkProfile))
                passwordsWritten += outcome.written; passwordsStaged += outcome.staged
            } catch { failures.append("Passwords import failed for profile \(item.profile.name): \(error.localizedDescription)") }
        }
        for item in result.profiles where !item.read.cookies.isEmpty {
            state.progressDetail = "Keeping you logged in…"; render()
            let cookies = item.read.cookies.map { cookie in
                ImportedCookie(domain: cookie.host, name: cookie.name, value: cookie.value, path: cookie.path, expires: Chromium.instant(cookie.expires),
                               creation: Chromium.instant(cookie.creation), lastAccess: Chromium.instant(cookie.lastAccess), secure: cookie.secure,
                               httpOnly: cookie.httpOnly, sameSite: cookie.sameSite, priority: cookie.priority)
            }
            do { cookiesSet += try await host.engine.importCookies(cookies, profile: profileID(item.brkProfile)) }
            catch { failures.append("Cookies import failed for profile \(item.profile.name): \(error.localizedDescription)") }
        }
        guard window != nil else { return }
        prepareBookmarks(result)
        state.failures = failures
        state.summary = readSummary(result)
        state.progressDone = true
        state.progressDetail = ""
        state.passwordsNeedRestart = passwordsStaged > 0
        render()
    }

    private func readSummary(_ result: ImportRead) -> [String] {
        var lines: [String] = []
        func add(_ count: Int, _ one: String, _ many: String) { if count > 0 { lines.append("\(count) \(count == 1 ? one : many)") } }
        add(result.spaces.count, "Space", "Spaces")
        add(result.spaces.reduce(0) { $0 + $1.pinned.reduce(0) { $0 + $1.tabCount } + $1.today.reduce(0) { $0 + $1.tabCount } }, "tab", "pinned and Today tabs")
        add(result.profiles.reduce(0) { $0 + $1.read.favorites.reduce(0) { $0 + $1.tabCount } }, "Favorite", "Favorites")
        add(result.profiles.reduce(0) { $0 + $1.read.bookmarks.reduce(0) { $0 + $1.tabCount } }, "bookmark", "bookmarks")
        add(result.profiles.reduce(0) { $0 + $1.read.visits.count }, "history visit", "history visits from the last 90 days")
        add(passwordsWritten + passwordsStaged, "password", "passwords")
        add(cookiesSet, "site login (cookie)", "site logins (cookies)")
        return lines
    }

    /// The finish screen's lines: what the import added (deduplicated), in place of the Arc Card.
    private func refreshSummary(final: Bool) {
        state.userName = state.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let summary = host.snapshot().sidebarData.lastImport, applied else { state.summary = []; return }
        var lines: [String] = []
        func add(_ count: Int, _ one: String, _ many: String) { if count > 0 { lines.append("\(count) \(count == 1 ? one : many)") } }
        add(summary.spaces, "Space from \(summary.source)", "Spaces from \(summary.source)")
        add(summary.tabs, "pinned or Today tab", "pinned and Today tabs")
        add(summary.bookmarks, "bookmark in Pinned", "bookmarks in Pinned")
        add(summary.favorites, "Favorite", "Favorites")
        add(summary.history, "history visit", "history visits")
        add(summary.passwords, "password", "passwords")
        add(summary.cookies, "site login kept", "site logins kept")
        state.summary = lines.isEmpty ? ["Nothing new: everything was already here"] : lines
        state.failures = summary.failures
        state.passwordsNeedRestart = passwordsStaged > 0
    }

    private func applyImport() {
        guard let read, !applied, let target = importTarget else { return }
        applied = true
        let bookmarks = filtered(nodes, prefix: "")
        let result = BrowserImportResult(
            source: read.sourceName,
            bookmarkFolder: read.kind == nil ? "Imported from \(read.profiles.first?.profile.name ?? "a file")" : nil,
            bookmarks: bookmarks, spaces: read.spaces,
            profiles: read.profiles.map { ImportedProfileData(profileName: $0.brkProfile, favorites: $0.read.favorites, visits: $0.read.visits) },
            passwords: passwordsWritten + passwordsStaged, cookies: cookiesSet, failures: state.failures)
        host.dispatch(.system(.sidebarData(.browserImported(owner, target: target, result))))
        if let theme = read.spaces.first?.theme { state.theme = theme }
    }

    // MARK: Finishing

    private func finish() {
        let owner = self.owner
        if state.mode == .firstRun {
            // An Arc Space that took over the starting Space keeps its title; otherwise the starting Space is "Personal".
            let title = applied && read?.spaces.isEmpty == false ? (host.target(owner)?.title ?? "") : ""
            let topApps: [ImportNode] = sites.filter { pickedSites.contains($0.url.absoluteString) }.map { .tab(title: $0.title, url: $0.url) }
            let choices = OnboardingChoices(spaceName: title, starterTabs: !applied, favorites: false, tour: true, importAfter: false,
                                            defaultBrowser: false, userName: state.name, topApps: topApps)
            close()
            host.showBrowserWindow(owner)
            host.dispatch(.user(owner, .sidebarData(.completeOnboarding(choices))))
        } else {
            close()
        }
    }

    /// Restart to let staged passwords in: a confirmed quit (the button was the answer, so "Warn before quitting" does not
    /// ask again), and the app starts again only once the ordered quit has run, as Restore Data does.
    private func restart() {
        finish()
        Quit.request(relaunch: true)
    }

    // MARK: Bookmarks step

    private func prepareBookmarks(_ result: ImportRead) {
        nodes = result.bookmarks
        let counts = result.visitCounts
        leafCount = leafIDs(nodes, prefix: "").count
        // Stars: the bookmarks visited most (three visits or more), at most 30; Arc preselects its recommendation.
        var visited: [(String, Int)] = []
        walk(nodes, prefix: "") { id, node in
            if case .tab(_, let url) = node, let count = counts[url], count >= 3 { visited.append((id, count)) }
        }
        starred = Set(visited.sorted { $0.1 > $1.1 }.prefix(30).map(\.0))
        selection = starred.isEmpty ? Set(leafIDs(nodes, prefix: "")) : starred
        expanded = Set(nodes.indices.map(String.init))
        state.recommendedCount = starred.count
    }

    private func walk(_ list: [ImportNode], prefix: String, _ body: (String, ImportNode) -> Void) {
        for (index, node) in list.enumerated() {
            let id = prefix.isEmpty ? "\(index)" : "\(prefix).\(index)"
            body(id, node)
            if case .folder(_, let children) = node { walk(children, prefix: id, body) }
        }
    }

    private func leafIDs(_ list: [ImportNode], prefix: String) -> [String] {
        var out: [String] = []
        walk(list, prefix: prefix) { id, node in if case .folder = node {} else { out.append(id) } }
        return out
    }

    private func node(_ id: String) -> ImportNode? {
        var list = nodes, current: ImportNode?
        for part in id.split(separator: ".") {
            guard let index = Int(part), list.indices.contains(index) else { return nil }
            current = list[index]
            if case .folder(_, let children)? = current { list = children } else { list = [] }
        }
        return current
    }

    private func toggleBookmark(_ id: String) {
        guard let node = node(id) else { return }
        if case .folder(_, let children) = node {
            let leaves = leafIDs(children, prefix: id)
            if leaves.allSatisfy(selection.contains) { selection.subtract(leaves) } else { selection.formUnion(leaves) }
        } else if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func filtered(_ list: [ImportNode], prefix: String) -> [ImportNode] {
        list.enumerated().compactMap { index, node in
            let id = prefix.isEmpty ? "\(index)" : "\(prefix).\(index)"
            if case .folder(let title, let children) = node {
                let kept = filtered(children, prefix: id)
                return kept.isEmpty ? nil : .folder(title: title, children: kept)
            }
            return selection.contains(id) ? node : nil
        }
    }

    private func bookmarkRows() -> [OnboardingBookmarkRow] {
        var rows: [OnboardingBookmarkRow] = []
        func add(_ list: [ImportNode], prefix: String, level: Int) {
            for (index, node) in list.enumerated() {
                let id = prefix.isEmpty ? "\(index)" : "\(prefix).\(index)"
                switch node {
                case .folder(let title, let children):
                    let leaves = leafIDs(children, prefix: id)
                    let chosen = leaves.filter(selection.contains).count
                    rows.append(OnboardingBookmarkRow(id: id, title: title, detail: "\(leaves.count)", level: level, isFolder: true, expanded: expanded.contains(id),
                                                      selected: !leaves.isEmpty && chosen == leaves.count, mixed: chosen > 0 && chosen < leaves.count, starred: false))
                    if expanded.contains(id) { add(children, prefix: id, level: level + 1) }
                case .tab(let title, let url):
                    rows.append(OnboardingBookmarkRow(id: id, title: title, detail: url.host ?? url.absoluteString, level: level, isFolder: false, expanded: false,
                                                      selected: selection.contains(id), mixed: false, starred: starred.contains(id)))
                case .split: break
                }
                if rows.count > 3000 { return }
            }
        }
        add(nodes, prefix: "", level: 0)
        return rows
    }

    // MARK: Favorites step

    private static let defaultSites: [(String, String)] = [
        ("Gmail", "https://mail.google.com/"), ("Google Calendar", "https://calendar.google.com/"), ("YouTube", "https://www.youtube.com/"),
        ("GitHub", "https://github.com/"), ("Wikipedia", "https://www.wikipedia.org/"), ("Notion", "https://www.notion.so/"),
        ("Figma", "https://www.figma.com/"), ("Slack", "https://app.slack.com/"), ("Google Drive", "https://drive.google.com/"),
        ("Reddit", "https://www.reddit.com/"), ("Spotify", "https://open.spotify.com/"), ("LinkedIn", "https://www.linkedin.com/"),
    ]

    private func prepareSites() {
        guard sites.isEmpty else { return }
        let imported = read?.topSites ?? []
        if imported.isEmpty {
            sites = Self.defaultSites.compactMap { name, raw in URL(string: raw).map { SourceTopSite(title: name, url: $0, score: 0) } }
            pickedSites = []
        } else {
            sites = Array(imported.prefix(12))
            // Arc picks the most used ones for you (its auto-select threshold); here the top four.
            pickedSites = Set(sites.prefix(4).map(\.url.absoluteString))
        }
    }

    // MARK: Files

    private func chooseFile(types: [UTType], directories: Bool, _ picked: @escaping @MainActor (URL) -> Void) {
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        SidebarPanelControl.configureTestDirectory(panel)
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async { picked(url) }
        }
    }

    // MARK: Rendering and facts

    private func render() {
        guard let surface else { return }
        state.canGoBack = !history.isEmpty && state.step != .progress && !state.waitingForPassword
        state.profiles = (discovered.first { $0.kind.rawValue == state.selectedBrowser }?.profiles ?? []).map {
            OnboardingProfileRow(id: $0.id, name: $0.name, selected: selectedProfiles.contains($0.id))
        }
        if state.step == .bookmarks {
            state.bookmarks = bookmarkRows()
            state.bookmarkTotal = leafCount
            state.bookmarkSelected = selection.count
        }
        if state.step == .favorites {
            state.sites = sites.map { OnboardingSiteTile(id: $0.url.absoluteString, title: $0.title.isEmpty ? ($0.url.host ?? "") : $0.title,
                                                         host: $0.url.host ?? "", selected: pickedSites.contains($0.url.absoluteString)) }
        }
        surface.render(state)
    }

    /// For the control socket: the open window, its step and every control's screen rectangle (top-left origin).
    func facts() -> OnboardingFacts {
        guard let window, let surface, let content = window.contentView else { return OnboardingFacts() }
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let contentRect = window.convertToScreen(content.convert(content.bounds, to: nil))
        func screen(_ rect: CGRect) -> CGRect {
            CGRect(x: contentRect.minX + rect.minX, y: screenHeight - contentRect.maxY + rect.minY, width: rect.width, height: rect.height)
        }
        return OnboardingFacts(step: state.step.rawValue, windowNumber: window.windowNumber, frame: screen(content.bounds.offsetBy(dx: -content.bounds.minX, dy: -content.bounds.minY)),
                               controls: surface.controlFrames.mapValues(screen), summary: state.summary, failures: state.failures,
                               isKey: window.isKeyWindow, progressDone: state.progressDone)
    }
}

private extension ImportChoice.Source {
    var firstProfileName: String {
        if case .browser(let kind, let profiles) = self { return profiles.first?.name ?? kind.name }
        return ""
    }
}

/// The window's size: Arc's 1280 x 800, smaller on a smaller screen.
enum OnboardingLayoutSize {
    @MainActor static var fitted: CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        return CGSize(width: min(1280, visible.width - 40), height: min(800, visible.height - 40))
    }
}
