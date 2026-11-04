import AppKit
import BrkBase
import BrkDomain
import Foundation
import os

// Owner: F3. Links from other apps and default-browser registration.
//
// macOS delivers a URL to open as the GetURL Apple Event (`kInternetEventClass`/`kAEGetURL`) when the app is the
// handler for its scheme. `GetURLHandler` turns it into `SystemEvent.externalURL(url)`, which the reducer routes
// (Air Traffic Control, Links settings). `DefaultBrowser.register()` asks macOS to make us the http and https
// handler (macOS shows its own confirmation); `DefaultBrowser.isDefault()` reads back who handles https today. The
// bundle declares `CFBundleURLTypes` for http and https (scripts/declare-url-types.sh, run by scripts/build.sh after
// the CEF plugin writes Info.plist), without which `setDefaultApplication` refuses and the GetURL event never comes.

@MainActor
public final class GetURLHandler: NSObject {
    private let send: @MainActor (Input) -> Void
    private let testScheme: String?
    private let log = Logger(subsystem: "brk", category: "links")
    /// Every URL string a GetURL event carried since launch, for the control socket (`NativeFacts.receivedGetURLs`).
    public private(set) static var received: [String] = []

    /// `testScheme` (`BRK_TEST_URL_SCHEME`, set only for a test copy of the bundle that declares that scheme): a
    /// Brk-only scheme Launch Services can route to this app without it becoming the http handler. Such a link is
    /// the http address after the scheme (`brk-test://127.0.0.1:8764/a.html` opens `http://127.0.0.1:8764/a.html`).
    public init(testScheme: String? = ProcessInfo.processInfo.environment["BRK_TEST_URL_SCHEME"], send: @escaping @MainActor (Input) -> Void) {
        self.send = send
        self.testScheme = testScheme.flatMap { $0.isEmpty ? nil : $0.lowercased() }
        super.init()
    }

    /// The URL a GetURL string opens: itself, or for the test scheme the http address it carries.
    public static func url(from text: String, testScheme: String?) -> URL? {
        guard let url = URL(string: text) else { return nil }
        guard let testScheme, url.scheme?.lowercased() == testScheme, let colon = text.firstIndex(of: ":") else { return url }
        return URL(string: "http" + text[colon...])
    }

    public func install() {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handle(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = Self.url(from: text, testScheme: testScheme) else {
            log.notice("GetURL without a usable URL")
            return
        }
        Self.received.append(text)
        log.notice("GetURL \(text, privacy: .public)")
        send(.system(.externalURL(url)))
    }
}

@MainActor
public enum DefaultBrowser {
    /// Asks macOS to make this app the handler for http and https. The result arrives later; macOS confirms with
    /// the user. Idempotent: asking while already the handler changes nothing.
    public static func register(failed: @escaping @MainActor @Sendable (String) -> Void = { _ in }) {
        guard let bundle = Bundle.main.bundleURL as URL? else { return }
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: bundle, toOpenURLsWithScheme: scheme) { error in
                if let error {
                    let message = "\(scheme): " + error.localizedDescription
                    Task { @MainActor in failed(message) }
                }
            }
        }
    }

    /// Whether this bundle is what macOS opens https links with right now (the General pane's "Set as Default
    /// Browser" notice; `SettingsSnapshot` has no field for it yet, so BrkApp reads it and the pane shows the button
    /// regardless). False from a SwiftPM test executable, which is not a bundle macOS knows.
    public static func isDefault() -> Bool {
        ["http", "https"].allSatisfy { scheme in
            guard let probe = URL(string: scheme + "://example.com/"), let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
            return handler.standardizedFileURL.resolvingSymlinksInPath() == Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        }
    }
}
