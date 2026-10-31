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
    private let log = Logger(subsystem: "brk", category: "links")

    public init(send: @escaping @MainActor (Input) -> Void) {
        self.send = send
        super.init()
    }

    public func install() {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handle(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue, let url = URL(string: text) else {
            log.notice("GetURL without a usable URL")
            return
        }
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
