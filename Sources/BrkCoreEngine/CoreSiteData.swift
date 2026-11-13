import BrkBase
import BrkEngine
import CBrkCore
import Foundation

/// Clears one site's data through its DevTools session, or a whole profile through its network context.
extension CoreEngine {
    func hasProtectedDataOperation(_ context: BrowsingContext, except clear: String? = nil) -> Bool {
        transfers.contains(context: context) || resources.entries.values.contains { entry in
            entry.context.context == context && entry.leases.contains { lease in
                if case .siteData(let id) = lease, id == clear { return false }
                return true
            }
        }
    }

    public func clearProfileData(_ request: ClearProfileData) async -> ClearProfileDataResult {
        let context = BrowsingContext.profile(request.profile)
        var completed: Set<SiteDataKind> = []
        func result(_ error: String?) -> ClearProfileDataResult { .init(request: request, completed: completed, error: error) }
        guard !request.kinds.isEmpty, !request.kinds.contains(.storage) else {
            return result("Profile-wide localStorage, IndexedDB, Cache Storage and service-worker removal is unavailable. Use Website Controls for each website")
        }
        guard isRunning, contexts.permitsWork(context) else { return result("The profile is closing") }
        guard clearingContexts[context] == nil else { return result("Website data is already being cleared in this profile") }
        guard !hasProtectedDataOperation(context) else { return result("Wait for this profile's active downloads, document output or extension operations before clearing website data") }
        clearingContexts[context] = request.id
        defer { if clearingContexts[context] == request.id { clearingContexts[context] = nil } }
        guard let profile = await profileWhenLoaded(request.profile) else { return result("The profile did not load") }
        func check() -> String? {
            guard isRunning, contexts.permitsWork(context) else { return "The profile closed while clearing data" }
            guard !hasProtectedDataOperation(context) else { return "A new protected operation started. Remaining data classes were not cleared" }
            return nil
        }
        if let error = check() { return result(error) }
        if request.kinds.contains(.cookies) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                profile.clearCookies { _ in continuation.resume() }
            }
            completed.insert(.cookies)
        }
        if let error = check() { return result(error) }
        if request.kinds.contains(.cache) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                profile.clearCache { continuation.resume() }
            }
            completed.insert(.cache)
        }
        if let error = check() { return result(error) }
        if request.kinds.contains(.history) { completed.insert(.history) }
        return result(nil)
    }

    public func cancelSiteData(_ id: String) {
        if clearingContexts.values.contains(id) { cancelledSiteClears.insert(id) }
    }

    public func clearSiteData(_ request: ClearSiteData) async -> ClearSiteDataResult {
        var completed: Set<SiteDataKind> = []
        func result(_ error: String?) -> ClearSiteDataResult { ClearSiteDataResult(request: request, completed: completed, error: error) }
        guard isRunning, contexts.permitsWork(request.target.context),
              let page = livePage(request.target.page), page.matches(request.target) else { return result("The originating document is no longer available") }
        func protectedOperation() -> Bool { hasProtectedDataOperation(request.target.context, except: request.id) }
        guard !protectedOperation() else { return result("Wait for this profile's active downloads, document output or extension operations before clearing website data") }
        guard clearingContexts[request.target.context] == nil else { return result("Website data is already being cleared in this profile") }
        guard request.scope != .profile || !request.kinds.contains(.storage) else { return result("Choose a site to clear origin storage. Profile-wide storage removal is unavailable") }
        guard resources.acquire(.siteData(request.id), browser: page.incarnation) else { return result("The browser is closing") }
        clearingContexts[request.target.context] = request.id
        defer {
            cancelledSiteClears.remove(request.id)
            if clearingContexts[request.target.context] == request.id { clearingContexts[request.target.context] = nil }
            resources.release(.siteData(request.id), browser: page.incarnation); closeIfUnowned(page.incarnation)
        }
        let session = page.protocolSession
        func checkContext() throws {
            guard !cancelledSiteClears.contains(request.id) else { throw CoreProtocolError(message: "Stopped remaining steps. Completed data classes have already been removed") }
            guard !protectedOperation() else { throw CoreProtocolError(message: "A new protected operation started. Remaining data classes were not cleared") }
            guard isRunning, contexts.permitsWork(request.target.context), isLive(page), page.matches(request.target) else {
                throw CoreProtocolError(message: "Website data clearing was interrupted by navigation, closure or context expiry")
            }
        }
        do {
            try await page.resumeForOperation(request.target.document)
            try checkContext()
            if request.kinds.contains(.cookies) {
                try checkContext()
                if request.scope == .profile { _ = try await session.call("Network.clearBrowserCookies") }
                else {
                    // The cookies that apply, HttpOnly and domain cookies included; each exact partition, name, domain and path is deleted.
                    let values = try await session.call("Storage.getCookies")
                    guard let cookies = values["cookies"] as? [[String: Any]] else { throw CoreProtocolError(message: "Chromium returned no cookie enumeration") }
                    for cookie in cookies {
                        try checkContext()
                        guard let name = cookie["name"], let domain = cookie["domain"] as? String, let path = cookie["path"],
                              let host = request.target.origin.url.host?.lowercased() else { continue }
                        let base = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        guard host == base || (domain.hasPrefix(".") && host.hasSuffix("." + base)) else { continue }
                        var params: [String: Any] = ["name": name, "domain": domain, "path": path]
                        if let partition = cookie["partitionKey"] { params["partitionKey"] = partition }
                        _ = try await session.call("Network.deleteCookies", params)
                    }
                }
                completed.insert(.cookies)
            }
            if request.kinds.contains(.cache) {
                try checkContext()
                _ = try await session.call("Network.clearBrowserCache")
                completed.insert(.cache)
            }
            if request.kinds.contains(.storage) {
                try checkContext()
                _ = try await session.call("Storage.clearDataForOrigin", ["origin": request.target.origin.value,
                    "storageTypes": "local_storage,indexeddb,cache_storage,service_workers,file_systems,websql"])
                completed.insert(.storage)
            }
            try checkContext()
            if request.kinds.contains(.history) { completed.insert(.history) }
            return result(nil)
        } catch { return result(error.localizedDescription) }
    }
}
