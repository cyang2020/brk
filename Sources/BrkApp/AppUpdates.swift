import AppKit
import BrkBase
import Sparkle

/// One application-wide update session. Sparkle owns validation, replacement and relaunch.
@MainActor
public final class AppUpdates: NSObject {
    public var changed: (() -> Void)? {
        didSet { driver.changed = changed }
    }
    public var message: ((String, String) -> Void)? {
        didSet { driver.message = message }
    }
    public var presentation: UpdatePresentation? { driver.presentation ?? summary.map(UpdatePresentation.updated) }
    public var automaticUpdates: Bool {
        updater?.automaticallyDownloadsUpdates
            ?? (defaults.object(forKey: "SUAutomaticallyUpdate") as? Bool)
            ?? (bundle.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool) ?? false
    }
    public var releaseNotesURL: URL? { driver.hasRelease ? driver.releaseNotesURL : summary?.notesURL }
    public var canAutomaticallyRestart: () -> Bool = { false }

    let driver: UpdateUserDriver
    let screenState = UpdateScreenState()
    private let bundle: Bundle
    private let defaults: UserDefaults
    private let history: AppUpdateHistory
    private var summary: UpdateRelease?
    private var updater: SPUUpdater?
    private var feed: UpdateFeed?
    private var automaticInstallTask: Task<Void, Never>?

    public init(bundle: Bundle = .main, defaults: UserDefaults? = nil, directory: URL? = nil) {
        self.bundle = bundle
        self.defaults = defaults ?? (bundle.bundleIdentifier == Bundle.main.bundleIdentifier
                                    ? .standard : bundle.bundleIdentifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard)
        let directory = directory ?? Product.dataDirectory().appendingPathComponent("Updates", isDirectory: true)
        history = AppUpdateHistory(url: directory.appendingPathComponent("history.json"))
        driver = UpdateUserDriver(notesDirectory: directory.appendingPathComponent("Notes", isDirectory: true))
        if bundle.bundleURL.pathExtension == "app",
           let rawBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           let build = UInt64(rawBuild),
           let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            summary = history.summary(for: UpdateRelease(version: version, build: build,
                                                        notesURL: HelpLinks.releaseNotes(bundle: bundle)),
                                      previouslyLaunched: self.defaults.bool(forKey: "SUHasLaunchedBefore"))
        }
        super.init()
        driver.automaticUpdates = { [weak self] in self?.automaticUpdates ?? false }
        driver.readyForAutomaticInstall = { [weak self] in self?.installAutomaticallyIfAllowed() }
        screenState.changed = { [weak self] in self?.installAutomaticallyIfAllowed() }
    }

    deinit { automaticInstallTask?.cancel() }

    public func start() {
        guard updater == nil else { return }
        let info = bundle.infoDictionary ?? [:]
        guard bundle.bundleURL.pathExtension == "app", bundle.bundleIdentifier != nil,
              let version = info["CFBundleVersion"] as? String, UInt64(version) != nil,
              let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32,
              let url = UpdateFeed.url(info: info, arm64: UpdateFeed.nativeArm64) else { return }
        let feed = UpdateFeed(url: url, driver: driver)
        feed.automaticReady = { [weak self] item, install in
            guard let self else { return false }
            guard self.driver.showAutomaticUpdateReady(item, install: install) else { return false }
            self.installAutomaticallyIfAllowed()
            return true
        }
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: feed)
        updater.automaticallyChecksForUpdates = true
        updater.updateCheckInterval = 8 * 60 * 60
        updater.sendsSystemProfile = false
        do {
            try updater.start()
            self.feed = feed
            self.updater = updater
            screenState.start()
            automaticInstallTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    guard let self else { return }
                    self.installAutomaticallyIfAllowed()
                }
            }
        } catch {
            driver.startFailed(error)
        }
    }

    public func check() {
        start()
        guard let updater else {
            let detail: String
            if case .failed(let error) = presentation { detail = error }
            else { detail = "Install the bundled app to check for signed updates." }
            message?("Updates unavailable", detail)
            return
        }
        guard driver.canCheck, updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    public func install() {
        if driver.canCheck { check() } else { driver.install() }
    }

    public func setAutomaticUpdates(_ enabled: Bool) {
        if let updater { updater.automaticallyDownloadsUpdates = enabled }
        else { defaults.set(enabled, forKey: "SUAutomaticallyUpdate") }
        changed?()
        if enabled {
            driver.downloadAutomaticallyIfOffered()
            installAutomaticallyIfAllowed()
        }
    }

    public func dismissSummary() {
        guard case .updated = presentation, let summary else { return }
        history.dismiss(summary)
        self.summary = nil
        changed?()
    }

    func installAutomaticallyIfAllowed() {
        driver.installReady(onlyIf: { [weak self] in
            guard let self else { return false }
            return self.automaticUpdates && self.screenState.isAway && self.canAutomaticallyRestart()
        })
    }
}

@MainActor
final class UpdateFeed: NSObject, SPUUpdaterDelegate {
    private let url: URL
    private weak var driver: UpdateUserDriver?
    var automaticReady: ((SUAppcastItem, @escaping () -> Void) -> Bool)?

    init(url: URL, driver: UpdateUserDriver) { self.url = url; self.driver = driver }

    func feedURLString(for updater: SPUUpdater) -> String? { url.absoluteString }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        automaticReady?(item, immediateInstallHandler) ?? false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        driver?.automaticUpdateCycleFinished(error: error)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        driver?.automaticUpdateCycleFinished(error: error)
    }

    static var nativeArm64: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    static func url(info: [String: Any], arm64: Bool) -> URL? {
        guard let string = info["SUFeedURL"] as? String, let configured = URL(string: string),
              ["https", "http"].contains(configured.scheme?.lowercased() ?? ""), configured.host != nil else { return nil }
        guard ["appcast-arm64.xml", "appcast-x86_64.xml"].contains(configured.lastPathComponent) else { return configured }
        return configured.deletingLastPathComponent().appendingPathComponent("appcast-\(arm64 ? "arm64" : "x86_64").xml")
    }
}

@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {
    private typealias Reply = (SPUUserUpdateChoice) -> Void

    private struct Download {
        let release: UpdateRelease
        var received: UInt64 = 0
        var expected: UInt64 = 0
        var cancel: (() -> Void)?

        var fraction: Double? {
            expected == 0 ? nil : min(1, Double(received) / Double(expected))
        }
    }

    private enum Session {
        case idle
        case checking(cancel: () -> Void)
        case offered(UpdateRelease, SPUUserUpdateStage, Reply)
        case downloading(Download)
        case preparing(UpdateRelease)
        case ready(UpdateRelease, Reply)
        case installing(UpdateRelease)
        case failed(String)

        var presentation: UpdatePresentation? {
            switch self {
            case .idle: nil
            case .checking: .checking
            case .offered(let release, _, _): .available(release)
            case .downloading(let download): .downloading(download.release, fraction: download.fraction)
            case .preparing(let release): .preparing(release)
            case .ready(let release, _): .ready(release)
            case .installing(let release): .installing(release)
            case .failed(let message): .failed(message: message)
            }
        }
    }

    var changed: (() -> Void)?
    var message: ((String, String) -> Void)?
    var automaticUpdates: () -> Bool = { false }
    var readyForAutomaticInstall: (() -> Void)?
    var hasRelease: Bool { release != nil }
    var releaseNotesURL: URL? { cachedNotesURL ?? release?.notesURL }
    var presentation: UpdatePresentation? { session.presentation }
    var canCheck: Bool {
        switch session {
        case .idle, .failed: true
        default: false
        }
    }
    private var session: Session = .idle
    private var published: UpdatePresentation?
    private var generation: UInt64 = 0
    private var manuallyRequestedInstall = false
    private var ownsAutomaticSession = false
    private var automaticQuitState: (confirmed: Bool, relaunch: Bool)?
    private var release: UpdateRelease?
    private var cachedNotesURL: URL?
    private let notesDirectory: URL

    init(notesDirectory: URL) {
        self.notesDirectory = notesDirectory
        super.init()
    }

    private func publish() {
        let next = presentation
        if case .downloading(let release, let fraction) = next,
           case .downloading(let previousRelease, let previousFraction) = published,
           release == previousRelease, let fraction, let previousFraction,
           fraction < 1, abs(fraction - previousFraction) < 0.01 { return }
        guard next != published else { return }
        published = next
        changed?()
    }

    private func reset() {
        if let automaticQuitState, Quit.confirmed, !Quit.relaunch {
            Quit.confirmed = automaticQuitState.confirmed
            Quit.relaunch = automaticQuitState.relaunch
        }
        automaticQuitState = nil
        ownsAutomaticSession = false
        generation &+= 1
        session = .idle
        manuallyRequestedInstall = false
        release = nil
        cachedNotesURL = nil
    }

    func install() {
        switch session {
        case .offered(let release, let stage, let reply):
            manuallyRequestedInstall = true
            session = stage == .downloaded ? .preparing(release) : .downloading(Download(release: release))
            publish()
            reply(.install)
        case .ready(let release, let reply):
            finish(release: release, reply: reply)
        default: break
        }
    }

    func downloadAutomaticallyIfOffered() {
        guard automaticUpdates(), case .offered(let release, let stage, let reply) = session else { return }
        session = stage == .downloaded ? .preparing(release) : .downloading(Download(release: release))
        publish()
        reply(.install)
    }

    func installReady(onlyIf permitted: @escaping () -> Bool) {
        guard permitted(), case .ready(let release, let reply) = session else { return }
        finish(release: release, reply: reply, onlyIf: permitted)
    }

    private func finish(release: UpdateRelease, reply: @escaping Reply, onlyIf permitted: (() -> Bool)? = nil) {
        session = .installing(release)
        let generation = generation
        publish()
        Quit.enqueue { [weak self] in
            guard let self, self.generation == generation, case .installing = self.session else { return }
            if let permitted, !permitted() {
                self.session = .ready(release, reply)
                self.publish()
                return
            }
            if self.ownsAutomaticSession {
                self.automaticQuitState = (Quit.confirmed, Quit.relaunch)
            }
            Quit.confirmed = true
            Quit.relaunch = false
            reply(.install)
        }
    }

    func startFailed(_ error: Error) {
        reset()
        session = .failed(Self.detail(error))
        publish()
    }

    private static func detail(_ error: Error) -> String {
        let error = error as NSError
        return [error.localizedDescription, error.localizedFailureReason, error.localizedRecoverySuggestion]
            .compactMap { $0 }.joined(separator: "\n\n")
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, automaticUpdateDownloading: NSNumber(value: automaticUpdates()), sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        guard canCheck else { cancellation(); return }
        reset()
        session = .checking(cancel: cancellation)
        publish()
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        switch session {
        case .idle, .checking, .failed: break
        default:
            reply(.dismiss)
            return
        }
        guard !appcastItem.isInformationOnlyUpdate, let build = UInt64(appcastItem.versionString) else {
            reset()
            session = .failed("This update has no installable application package or valid build number.")
            publish()
            reply(.dismiss)
            return
        }
        reset()
        let release = rememberRelease(appcastItem, build: build)
        session = state.stage == .installing ? .ready(release, reply) : .offered(release, state.stage, reply)
        publish()
        if automaticUpdates() { downloadAutomaticallyIfOffered() }
        readyForAutomaticInstall?()
    }

    func showAutomaticUpdateReady(_ item: SUAppcastItem, install: @escaping () -> Void) -> Bool {
        guard !item.isInformationOnlyUpdate, let build = UInt64(item.versionString) else { return false }
        switch session {
        case .idle, .failed: break
        default: return false
        }
        reset()
        let release = rememberRelease(item, build: build)
        ownsAutomaticSession = true
        session = .ready(release, { choice in if choice == .install { install() } })
        publish()
        return true
    }

    func automaticUpdateCycleFinished(error: Error?) {
        guard ownsAutomaticSession else { return }
        reset()
        if let error {
            let failure = error as NSError
            let dismissed = failure.domain == SUSparkleErrorDomain &&
                [Int(SUError.noUpdateError.rawValue), Int(SUError.installationCanceledError.rawValue)].contains(failure.code)
            if !dismissed { session = .failed(Self.detail(error)) }
        }
        publish()
    }

    private func rememberRelease(_ item: SUAppcastItem, build: UInt64) -> UpdateRelease {
        let notes = [item.releaseNotesURL, item.infoURL].compactMap { $0 }.first {
            ["https", "http"].contains($0.scheme?.lowercased() ?? "") && $0.host != nil
        }
        var release = UpdateRelease(version: item.displayVersionString, build: build, notesURL: notes)
        self.release = release
        let cached = notesDirectory.appendingPathComponent("\(build).html")
        if FileManager.default.fileExists(atPath: cached.path) { cachedNotesURL = cached }
        if let inline = item.itemDescription, !inline.isEmpty {
            cacheNotes(inline, plainText: item.itemDescriptionFormat == "plain-text", unavailable: false)
            if notes == nil {
                release = UpdateRelease(version: release.version, build: build, notesURL: cachedNotesURL)
                self.release = release
            }
        }
        return release
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard release != nil else { return }
        var encoding = String.Encoding.utf8
        if let name = downloadData.textEncodingName {
            let value = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if value != kCFStringEncodingInvalidId {
                encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(value))
            }
        }
        guard let text = String(data: downloadData.data, encoding: encoding) else {
            showUpdateReleaseNotesFailedToDownloadWithError(NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError))
            return
        }
        cacheNotes(text, plainText: downloadData.mimeType?.lowercased() == "text/plain", unavailable: false)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        guard let release, cachedNotesURL == nil else { return }
        var body = "<h1>Release notes for \(Self.escape(release.version))</h1><p>The release notes could not be downloaded. \(Self.escape(error.localizedDescription))</p>"
        if let url = release.notesURL {
            body += "<p><a href=\"\(Self.escape(url.absoluteString))\">Try the online release notes</a></p>"
        }
        body += "<p>You can still install this update.</p>"
        cacheNotes(body, plainText: false, unavailable: true)
    }

    private func cacheNotes(_ text: String, plainText: Bool, unavailable: Bool) {
        guard let release else { return }
        let content = plainText ? "<pre>\(Self.escape(text))</pre>" : text
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src https: data:; base-uri 'none'; form-action 'none'">
        <title>\(Self.escape(Product.name)) \(Self.escape(release.version)) — Release Notes</title>
        <style>body{font:16px system-ui;line-height:1.6;max-width:760px;margin:48px auto;padding:0 24px;color-scheme:light dark}pre{white-space:pre-wrap}a{color:LinkText}</style>
        </head><body>\(content)</body></html>
        """
        do {
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            let file = notesDirectory.appendingPathComponent("\(release.build)\(unavailable ? "-unavailable" : "").html")
            try Data(html.utf8).write(to: file, options: .atomic)
            cachedNotesURL = file
            changed?()
        } catch {
            NSLog("Could not cache release notes: %@", error.localizedDescription)
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let manual: Bool
        if case .checking = session { manual = true } else { manual = false }
        reset()
        publish()
        if manual { message?("Check for Updates", Self.detail(error)) }
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        startFailed(error)
        message?("Update failed", Self.detail(error))
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        guard case .downloading(var download) = session else { cancellation(); return }
        download.cancel = cancellation
        session = .downloading(download)
        publish()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        guard case .downloading(var download) = session else { return }
        download.expected = expectedContentLength
        session = .downloading(download)
        publish()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        guard case .downloading(var download) = session else { return }
        let (received, overflow) = download.received.addingReportingOverflow(length)
        download.received = overflow ? .max : received
        session = .downloading(download)
        publish()
    }

    func showDownloadDidStartExtractingUpdate() {
        guard case .downloading(let download) = session else { return }
        session = .preparing(download.release)
        publish()
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let release: UpdateRelease
        switch session {
        case .preparing(let current): release = current
        case .downloading(let download): release = download.release
        default: reply(.skip); return
        }
        session = .ready(release, reply)
        publish()
        if manuallyRequestedInstall { install() }
        else { readyForAutomaticInstall?() }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        // Sparkle sends the quit event. The app delegate retains its existing ordered termination path.
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        reset()
        publish()
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        // Sparkle calls this after acknowledging an error too. Retain that failure until the next check.
        if case .failed = session { return }
        reset()
        publish()
    }
}
