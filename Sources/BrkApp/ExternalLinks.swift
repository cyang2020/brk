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
// handler (macOS shows its own confirmation). TODO(F3): the bundle must declare `CFBundleURLTypes` for http and
// https (scripts/build.sh, the CEF plugin's Info.plist) or `setDefaultApplication` refuses.

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
    /// the user. TODO(F3): read the current handler for the General pane's notice (`isDefaultBrowser`).
    public static func register() {
        guard let bundle = Bundle.main.bundleURL as URL? else { return }
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: bundle, toOpenURLsWithScheme: scheme) { error in
                if let error { Logger(subsystem: "brk", category: "links").notice("default browser (\(scheme, privacy: .public)): \(error)") }
            }
        }
    }
}
