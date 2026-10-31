import AppKit
import BrkBase
import CefKit
import CCef
import Foundation
import os

/// The bundled observer has no web-accessible resources or message listeners. Native code evaluates fixed
/// expressions through CEF; player state and controls stay in the extension-isolated world of each frame.
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
        let players: [MediaPlayer]
        let mediaError: String?
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
        options.prepareWindow = { HostWindows.adopt($0, parent: nil) }
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
            let players = [], mediaError = null;
            try {
              let frames = await chrome.scripting.executeScript({injectImmediately:true,target:{tabId:tab.id,allFrames:true},func:()=>globalThis.__brkMedia?.snapshot() ?? null});
              const missing = frames.filter(f=>f.result === null).map(f=>f.documentId);
              if (missing.length) {
                await chrome.scripting.executeScript({injectImmediately:true,target:{tabId:tab.id,documentIds:missing},files:['media.js']});
                frames = await chrome.scripting.executeScript({injectImmediately:true,target:{tabId:tab.id,allFrames:true},func:()=>globalThis.__brkMedia?.snapshot() ?? []});
              }
              for (const frame of frames) for (const player of frame.result ?? []) players.push({...player,document:frame.documentId,frame:frame.frameId});
            } catch(e) { mediaError = String(e); }
            result.push({token: request.token, target: id, tab: tab.id, audible: tab.audible, incognito: tab.incognito, players, mediaError});
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
            let players = (row["players"] as? [[String: Any]] ?? []).compactMap { value -> MediaPlayer? in
                guard let document = value["document"] as? String, let frame = value["frame"] as? Int,
                      let element = value["element"] as? String, let rawKind = value["kind"] as? String,
                      let kind = MediaKind(rawValue: rawKind), let paused = value["paused"] as? Bool,
                      let ended = value["ended"] as? Bool, let pip = value["pictureInPicture"] as? Bool else { return nil }
                return MediaPlayer(id: MediaPlayerID(document: document, frame: frame, element: element), kind: kind, paused: paused, ended: ended, pictureInPicture: pip)
            }
            return Reading(token: token, target: target, tab: tab, audible: audible, incognito: incognito, players: players, mediaError: row["mediaError"] as? String)
        }
        let isPrivate: Bool = if case .incognito = context { true } else { false }
        return readings.filter { $0.token == token && $0.incognito == isPrivate && targets.contains($0.target) }
    }

    func control(target: String, tab: Int, player: MediaPlayerID, operation: MediaOperation, userInitiated: Bool = true) async throws {
        guard ready, !stopping, let transport else { throw CefDevTools.Failure.unavailable }
        let args = String(decoding: try JSONSerialization.data(withJSONObject: ["target": target, "tab": tab, "document": player.document, "frame": player.frame, "element": player.element, "operation": operation.rawValue]), as: UTF8.self)
        let script = """
        (async()=>{
          if (location.href !== '\(AudioExtension.url.absoluteString)' || chrome.runtime.id !== '\(AudioExtension.id)') throw Error('observer origin');
          const r=\(args), targets=await chrome.debugger.getTargets();
          if (!targets.some(t=>t.id===r.target && t.tabId===r.tab && t.type==='page')) throw Error('Target changed');
          const tab=await chrome.tabs.get(r.tab);
          if (tab.incognito !== chrome.extension.inIncognitoContext) throw Error('Context changed');
          const result=await chrome.scripting.executeScript({injectImmediately:true,target:{tabId:r.tab,documentIds:[r.document]},args:[r.element,r.operation],func:async(id,op)=>{
            try { if (!globalThis.__brkMedia) throw Error('Player document unavailable'); return {value:await globalThis.__brkMedia.control(id,op)}; }
            catch(e) { return {error:e.name+': '+e.message}; }
          }});
          if (result.length!==1 || result[0].frameId!==r.frame || result[0].documentId!==r.document) throw Error('Player document changed');
          if (result[0].result?.error) throw Error(result[0].result.error);
          return true;
        })()
        """
        let data = try await transport.call("Runtime.evaluate", parameters: ["expression": script, "awaitPromise": true, "returnByValue": true, "userGesture": userInitiated])
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], value["exceptionDetails"] == nil,
              (value["result"] as? [String: Any])?["value"] as? Bool == true else {
            throw CefDevTools.Failure.protocolError(String(decoding: data, as: UTF8.self))
        }
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
