import BrkBase
import BrkEngine
import CefKit
import Foundation

extension CEFEngine {
    private func extensionManager(context: BrowsingContext, target: PageID? = nil) async throws -> ChromePage {
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while phase == .running, contexts.permitsWork(context), ProcessInfo.processInfo.systemUptime < deadline {
            if let target, !wanted.contains(where: { $0.id == target && $0.context == context }) { break }
            if let page = live.values.sorted(by: { $0.id < $1.id }).first(where: { page in
                guard target == nil || target == page.id, page.context == context,
                      page.browser.url?.scheme == "chrome", page.browser.url?.host == "extensions" else { return false }
                if case .ready = page.mainDocument.availability { return true }; return false
            }) { return page }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw CefProtocolError(message: "The originating profile's extension manager is unavailable")
    }

    private func managerValue(_ page: ChromePage, expression: String, timeout: Double = 10, userGesture: Bool = false) async throws -> Any? {
        guard isLive(page), contexts.permitsWork(page.context), case .ready(let document) = page.mainDocument.availability,
              page.browser.url?.scheme == "chrome", page.browser.url?.host == "extensions" else {
            throw CefProtocolError(message: "The extension manager document changed")
        }
        let response = try await page.browser.protocolSession.call("Runtime.evaluate", ["expression": expression, "awaitPromise": true, "returnByValue": true, "userGesture": userGesture], timeout: timeout)
        guard isLive(page), contexts.permitsWork(page.context), page.mainDocument.availability == .ready(document) else {
            throw CefProtocolError(message: "The extension manager document changed")
        }
        if let details = response["exceptionDetails"] as? [String: Any] {
            let exception = details["exception"] as? [String: Any]
            throw CefProtocolError(message: exception?["description"] as? String ?? details["text"] as? String ?? "Chromium extension operation failed")
        }
        return (response["result"] as? [String: Any])?["value"]
    }

    public func extensionCatalog(context: BrowsingContext) async -> ExtensionCatalog {
        guard case .profile = context else { return ExtensionCatalog(context: context, extensions: [], error: "Extension management is unavailable in private windows") }
        do {
            let page = try await extensionManager(context: context)
            guard let rows = try await managerValue(page, expression: "chrome.developerPrivate.getExtensionsInfo({includeDisabled:true,includeTerminated:true})") as? [[String: Any]] else {
                throw CefProtocolError(message: "Chromium returned no extension catalog")
            }
            let values = rows.compactMap { row -> BrowserExtension? in
                guard let id = row["id"] as? String, let name = row["name"] as? String, let version = row["version"] as? String else { return nil }
                return BrowserExtension(id: id, name: name, version: version, enabled: row["state"] as? String == "ENABLED")
            }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
            return ExtensionCatalog(context: context, extensions: values, error: nil)
        } catch { return ExtensionCatalog(context: context, extensions: [], error: error.localizedDescription) }
    }

    public func installExtension(at directory: URL, context: BrowsingContext, in target: PageID) async -> String? {
        guard case .profile = context else { return "Private installation is disabled" }
        do {
            let page = try await extensionManager(context: context, target: target)
            guard case .ready(let document) = page.mainDocument.availability else { return "The installer document is unavailable" }
            let lease = BrowserResources<ChromePage>.Lease.extensionOperation(UUID().uuidString)
            guard resources.acquire(lease, browser: page.incarnation) else { return "The installer browser is closing" }
            defer {
                page.approvedExtensionDirectory = nil
                if page.extensionInstallerDocument == document { page.extensionInstallerDocument = nil }
                resources.release(lease, browser: page.incarnation); closeIfUnowned(page.incarnation)
            }
            page.extensionInstallerDocument = document
            page.approvedExtensionDirectory = (document, directory)
            _ = try await managerValue(page, expression: "(async()=>{await chrome.developerPrivate.updateProfileConfiguration({inDeveloperMode:true});await chrome.developerPrivate.loadUnpacked({failQuietly:false});return true})()", timeout: 30, userGesture: true)
            return nil
        } catch { return error.localizedDescription }
    }

    public func invokeExtension(_ id: String, target: SiteTarget) async -> String? {
        guard phase == .running, case .profile = target.context, contexts.permitsWork(target.context), let page = live[target.page], page.matches(target) else { return "The originating website changed" }
        do {
            let response = try await page.browser.protocolSession.call("Target.getTargetInfo")
            guard page.matches(target), isLive(page), let info = response["targetInfo"] as? [String: Any], let targetID = info["targetId"] as? String else { return "The originating website changed" }
            _ = try await page.browser.protocolSession.call("Extensions.triggerAction", ["id": id, "targetId": targetID])
            return nil
        } catch { return error.localizedDescription }
    }

    public func removeExtension(_ id: String, context: BrowsingContext, in target: PageID) async -> String? {
        guard case .profile = context else { return "Private extension management is disabled" }
        do {
            let page = try await extensionManager(context: context, target: target)
            // The native confirmation is a pending choice, not an accepted operation lease.
            // Closing its manager must be able to cancel the dialog and release the protocol wait.
            _ = try await managerValue(page, expression: "new Promise((resolve,reject)=>{chrome.management.uninstall(\(ChromePage.jsString(id)),{showConfirmDialog:true},()=>{const error=chrome.runtime.lastError;if(error)reject(new Error(error.message));else resolve(true)})})", timeout: 300, userGesture: true)
            return nil
        } catch { return error.localizedDescription }
    }
}

extension ChromePage {
    func browser(_ b: CefBrowser, fileDialog request: CefFileDialogRequest, callback: CefFileDialogCallback) -> Bool {
        extensionFileDialogCallbacks += 1
        guard engine.isLive(self) else { extensionDialogDecision = "cancelled: retired browser"; callback.cancel(); return true }
        if let document = extensionInstallerDocument, mainDocument.availability != .ready(document) { extensionDialogDecision = "cancelled: installer document changed"; callback.cancel(); return true }
        guard let approval = approvedExtensionDirectory else { extensionDialogDecision = "default: no approved directory"; return false }
        // Pinned Chrome's unpacked installer reports OPEN (0), despite requesting a directory.
        // The compatibility is restricted to this approved manager document; ordinary file dialogs fall through.
        guard request.folder || request.rawMode == 0, engine.isLive(self), case .profile = context,
              mainDocument.availability == .ready(approval.document), b.url?.scheme == "chrome", b.url?.host == "extensions" else {
            extensionDialogDecision = "cancelled: mode=\(request.rawMode), folder=\(request.folder), manager=\(b.url?.host == "extensions")"
            approvedExtensionDirectory = nil; callback.cancel(); return true
        }
        // The user already selected and confirmed this exact directory in Brk. Consume before native reentry.
        approvedExtensionDirectory = nil
        extensionDialogDecision = "selected approved directory"
        callback.select([approval.directory])
        return true
    }
}
