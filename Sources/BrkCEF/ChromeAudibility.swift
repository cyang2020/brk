import AppKit
import BrkBase
import CefKit
import CCef
import Foundation
import os

/// The only extension we load ourselves. It contains an empty, non-web-accessible document.
/// Native code evaluates a fixed read-only expression through CEF, never a renderer/web message.
enum AudioExtension {
    static let id = "mkcpfepmhobdegbnlihgcmelnebpfabk"
    static let url = URL(string: "chrome-extension://\(id)/observer.html")!

    @MainActor static func configure(_ config: inout CefConfiguration) {
        let directory = Bundle.main.resourceURL!.appendingPathComponent("BrkAudibility")
        config.extraCommandLineSwitches["load-extension"] = directory.path
    }

    /// CEF's public preference API, restricted to the bundled extension's incognito bit. Chromium reads
    /// this bit when it creates an off-the-record extension context. No other extension entry is changed.
    @MainActor static func allowPrivateAccess() -> Bool {
        guard let context = cef_request_context_get_global_context() else { return false }
        defer { release(context) }
        let prefs = UnsafeMutableRawPointer(context).assumingMemoryBound(to: cef_preference_manager_t.self)
        return string("extensions.settings") { name in
            guard prefs.pointee.can_set_preference?(prefs, name) == 1,
                  let value = prefs.pointee.get_preference?(prefs, name) else { return false }
            defer { release(value) }
            guard let all = value.pointee.get_dictionary?(value) else { return false }
            defer { release(all) }
            return string(id) { key in
                guard let entry = all.pointee.get_dictionary?(all, key) else { return false }
                defer { release(entry) }
                if string("incognito", { entry.pointee.get_bool?(entry, $0) }) == 1 { return true }
                guard string("incognito", { entry.pointee.set_bool?(entry, $0, 1) }) == 1 else { return false }
                var error = cef_string_t()
                defer { ccef_string_clear(&error) }
                // SetPreference consumes the input reference.
                let base = UnsafeMutableRawPointer(value).assumingMemoryBound(to: cef_base_ref_counted_t.self)
                base.pointee.add_ref?(base)
                return prefs.pointee.set_preference?(prefs, name, value, &error) == 1
            }
        }
    }

    private static func string<T>(_ value: String, _ body: (UnsafePointer<cef_string_t>) -> T) -> T {
        var raw = cef_string_t()
        let utf16 = Array(value.utf16)
        _ = utf16.withUnsafeBufferPointer { ccef_string_set_utf16($0.baseAddress, $0.count, &raw) }
        defer { ccef_string_clear(&raw) }
        return body(&raw)
    }
    private static func release<T>(_ pointer: UnsafeMutablePointer<T>) {
        let base = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: cef_base_ref_counted_t.self)
        _ = base.pointee.release?(base)
    }
}

/// One reader per exact request context, including the private epoch. The engine owns it until both
/// OnBeforeClose and host-window destruction have drained. No tab URL or title participates in mapping.
@MainActor
final class ChromeAudibility: CefBrowserDelegate {
    struct Reading {
        let token: String
        let target: String
        let tab: Int
        let audible: Bool
        let incognito: Bool
    }
    let context: BrowsingContext
    private let chrome: CefChromeBrowser
    private var transport: CefDevTools?
    private var closed = false
    private var hostClosed = false
    private(set) var stopping = false
    private var ready = false
    private var documentRevision: UInt64 = 0
    private let token = UUID().uuidString
    var drained: Bool { closed && hostClosed }
    var browserID: Int { Int(chrome.browser.id) }

    init(context: BrowsingContext, profile: CefProfile?) {
        self.context = context
        var options = CefChromeBrowserOptions()
        options.isFrameless = true
        options.showsChromeToolbar = false
        options.initialBounds = ChromePage.offscreenBounds
        options.profile = profile
        chrome = CefChromeBrowser.create(url: AudioExtension.url, options: options, delegate: nil)
        chrome.browser.delegate = self
        if let host = chrome.nsWindow { HostWindows.adopt(host, parent: nil) }
        chrome.hide()
        chrome.onWindowDestroyed = { [weak self] in self?.hostClosed = true }
    }

    func read(targets: [String]) async throws -> [Reading] {
        guard ready, !stopping, !targets.isEmpty else { return [] }
        let document = documentRevision
        if transport == nil { transport = CefDevTools(browser: chrome.browser) }
        guard let transport else { return [] }
        let parameters = String(decoding: try JSONSerialization.data(withJSONObject: ["token": token, "targets": targets]), as: UTF8.self)
        let expression = """
        (async () => {
          if (location.href !== '\(AudioExtension.url.absoluteString)' || chrome.runtime.id !== '\(AudioExtension.id)') throw Error('observer origin');
          const request = \(parameters);
          const targets = await chrome.debugger.getTargets();
          const result = [];
          for (const id of request.targets) {
            const matches = targets.filter(t => t.id === id && t.type === 'page' && Number.isInteger(t.tabId));
            if (matches.length !== 1) continue;
            const tab = await chrome.tabs.get(matches[0].tabId).catch(() => null);
            if (!tab || typeof tab.audible !== 'boolean' || tab.incognito !== chrome.extension.inIncognitoContext) continue;
            result.push({token: request.token, target: id, tab: tab.id, audible: tab.audible, incognito: tab.incognito});
          }
          return JSON.stringify(result);
        })()
        """
        let data = try await transport.call("Runtime.evaluate", parameters: ["expression": expression, "awaitPromise": true, "returnByValue": true])
        guard !stopping, ready, document == documentRevision else { return [] }
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              envelope["exceptionDetails"] == nil,
              let result = envelope["result"] as? [String: Any], let value = result["value"] as? String else {
            throw CefDevTools.Failure.protocolError(String(decoding: data, as: UTF8.self))
        }
        guard let rows = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [[String: Any]] else { return [] }
        let readings = rows.compactMap { row -> Reading? in
            guard let token = row["token"] as? String, let target = row["target"] as? String,
                  let tab = row["tab"] as? Int, let audible = row["audible"] as? Bool,
                  let incognito = row["incognito"] as? Bool else { return nil }
            return Reading(token: token, target: target, tab: tab, audible: audible, incognito: incognito)
        }
        let isPrivate: Bool = if case .incognito = context { true } else { false }
        return readings.filter { $0.token == token && $0.incognito == isPrivate && targets.contains($0.target) }
    }

    func stop() {
        guard !stopping else { return }
        stopping = true
        documentRevision += 1
        ready = false
        transport?.invalidate(); transport = nil
        chrome.browser.close(force: true)
    }
    func browser(_ b: CefBrowser, didFinishMainDocument url: URL?) { ready = !stopping && url == AudioExtension.url }
    func browser(_ b: CefBrowser, didStartMainDocument url: URL?) { ready = false; documentRevision += 1 }
    func browser(_ b: CefBrowser, decidePolicyForNavigation url: URL?, isRedirect: Bool, userGesture: Bool) -> CefNavigationDecision {
        url == AudioExtension.url && !stopping ? .allow : .cancel
    }
    func browser(_ b: CefBrowser, decideWindowOpenFor request: CefWindowOpenRequest) -> CefWindowOpenAction { .handled }
    func browser(_ b: CefBrowser, didRequestNewTab url: URL?) -> Bool { true }
    func browser(_ b: CefBrowser, renderProcessDidTerminate reason: CefTerminationReason, errorCode: Int) { stop() }
    func browserDidClose(_ b: CefBrowser) { ready = false; transport?.invalidate(); transport = nil; closed = true }
}
