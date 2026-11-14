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
    public var presentation: UpdatePresentation? { driver.presentation }

    let driver = UpdateUserDriver()
    private let bundle: Bundle
    private var updater: SPUUpdater?
    private var feed: UpdateFeed?

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
        super.init()
    }

    public func start() {
        guard updater == nil else { return }
        let info = bundle.infoDictionary ?? [:]
        guard bundle.bundleURL.pathExtension == "app", bundle.bundleIdentifier != nil,
              let version = info["CFBundleVersion"] as? String, UInt64(version) != nil,
              let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32,
              let url = UpdateFeed.url(info: info, arm64: UpdateFeed.nativeArm64) else { return }
        let feed = UpdateFeed(url: url)
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: feed)
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = false
        updater.updateCheckInterval = 8 * 60 * 60
        updater.sendsSystemProfile = false
        do {
            try updater.start()
            self.feed = feed
            self.updater = updater
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
}

@MainActor
final class UpdateFeed: NSObject, SPUUpdaterDelegate {
    private let url: URL

    init(url: URL) { self.url = url }

    func feedURLString(for updater: SPUUpdater) -> String? { url.absoluteString }

    static var nativeArm64: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    static func url(info: [String: Any], arm64: Bool) -> URL? {
        guard let string = info["SUFeedURL"] as? String, let configured = URL(string: string),
              ["https", "http"].contains(configured.scheme?.lowercased() ?? ""), configured.host != nil else { return nil }
        // A custom feed, including the disposable loopback fixture, keeps its configured URL.
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
        generation &+= 1
        session = .idle
    }

    func install() {
        switch session {
        case .offered(let release, let stage, let reply):
            session = stage == .downloaded ? .preparing(release) : .downloading(Download(release: release))
            publish()
            reply(.install)
        case .ready(let release, let reply):
            finish(release: release, reply: reply)
        default: break
        }
    }

    private func finish(release: UpdateRelease, reply: @escaping Reply) {
        session = .installing(release)
        let generation = generation
        publish()
        Quit.enqueue { [weak self] in
            guard let self, self.generation == generation, case .installing = self.session else { return }
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
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, automaticUpdateDownloading: false, sendSystemProfile: false))
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
        let release = UpdateRelease(version: appcastItem.displayVersionString, build: build)
        session = state.stage == .installing ? .ready(release, reply) : .offered(release, state.stage, reply)
        publish()
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

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
        install()
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
