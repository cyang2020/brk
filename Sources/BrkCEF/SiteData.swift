import BrkBase
import BrkEngine
import CefKit
import Foundation

extension CEFEngine {
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
        guard phase == .running, contexts.permitsWork(context) else { return result("The profile is closing") }
        guard clearingContexts[context] == nil else { return result("Website data is already being cleared in this profile") }
        guard !hasProtectedDataOperation(context) else { return result("Wait for this profile's active downloads, document output or extension operations before clearing website data") }
        clearingContexts[context] = request.id
        defer { if clearingContexts[context] == request.id { clearingContexts[context] = nil } }
        func check() throws {
            guard phase == .running, contexts.permitsWork(context) else { throw CefProtocolError(message: "The profile closed while clearing data") }
            guard !hasProtectedDataOperation(context) else { throw CefProtocolError(message: "A new protected operation started. Remaining data classes were not cleared") }
        }
        do {
            let store = try await dataStore(for: request.profile)
            defer { store.release() }
            try check()
            if request.kinds.contains(.cookies) {
                try await store.clearCookies { completed.insert(.cookies) }
            }
            try check()
            if request.kinds.contains(.cache) {
                try await store.clearCache()
                completed.insert(.cache)
            }
            try check()
            if request.kinds.contains(.history) { completed.insert(.history) }
            return result(nil)
        } catch { return result(error.localizedDescription) }
    }

    public func importCookies(_ cookies: [ImportedCookie], profile: ProfileID) async throws -> Int {
        let context = BrowsingContext.profile(profile)
        guard phase == .running, contexts.permitsWork(context) else { throw CefProtocolError(message: "The profile is closing") }
        guard !cookies.isEmpty else { return 0 }
        let store = try await dataStore(for: profile)
        defer { store.release() }
        return try await store.setCookies(cookies)
    }

    public func cancelSiteData(_ id: String) {
        if clearingContexts.values.contains(id) { cancelledSiteClears.insert(id) }
    }

    public func clearSiteData(_ request: ClearSiteData) async -> ClearSiteDataResult {
        var completed: Set<SiteDataKind> = []
        func result(_ error: String?) -> ClearSiteDataResult { ClearSiteDataResult(request: request, completed: completed, error: error) }
        guard phase == .running, contexts.permitsWork(request.target.context),
              let page = live[request.target.page], page.matches(request.target) else { return result("The originating document is no longer available") }
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
        let protocolSession = page.browser.protocolSession
        func checkContext() throws {
            guard !cancelledSiteClears.contains(request.id) else { throw CefProtocolError(message: "Stopped remaining steps. Completed data classes have already been removed") }
            guard !protectedOperation() else { throw CefProtocolError(message: "A new protected operation started. Remaining data classes were not cleared") }
            guard phase == .running, contexts.permitsWork(request.target.context), isLive(page), page.matches(request.target) else {
                throw CefProtocolError(message: "Website data clearing was interrupted by navigation, closure or context expiry")
            }
        }
        do {
            try await page.resumeForOperation(request.target.document)
            try checkContext()
            if request.kinds.contains(.cookies) {
                try checkContext()
                if request.scope == .profile { _ = try await protocolSession.call("Network.clearBrowserCookies") }
                else {
                    // Get applicable cookies, including HttpOnly and domain cookies. Delete the exact partition/name/domain/path tuple.
                    let values = try await protocolSession.call("Storage.getCookies")
                    guard let cookies = values["cookies"] as? [[String: Any]] else { throw CefProtocolError(message: "Chromium returned no cookie enumeration") }
                    for cookie in cookies {
                        try checkContext()
                        guard let name = cookie["name"], let domain = cookie["domain"] as? String, let path = cookie["path"],
                              let host = request.target.origin.url.host?.lowercased() else { continue }
                        let base = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        guard host == base || (domain.hasPrefix(".") && host.hasSuffix("." + base)) else { continue }
                        var params: [String: Any] = ["name": name, "domain": domain, "path": path]
                        if let partition = cookie["partitionKey"] { params["partitionKey"] = partition }
                        _ = try await protocolSession.call("Network.deleteCookies", params)
                    }
                }
                completed.insert(.cookies)
            }
            if request.kinds.contains(.cache) {
                try checkContext()
                _ = try await protocolSession.call("Network.clearBrowserCache")
                completed.insert(.cache)
            }
            if request.kinds.contains(.storage) {
                try checkContext()
                _ = try await protocolSession.call("Storage.clearDataForOrigin", ["origin": request.target.origin.value,
                    "storageTypes": "local_storage,indexeddb,cache_storage,service_workers,file_systems,websql"])
                completed.insert(.storage)
            }
            try checkContext()
            if request.kinds.contains(.history) { completed.insert(.history) }
            return result(nil)
        } catch { return result(error.localizedDescription) }
    }

    func permission(_ page: ChromePage, prompt: SitePermissionPrompt, reply: @escaping @MainActor (SitePermission) -> Void) {
        guard isLive(page), page.matchesPermission(prompt.target), contexts.permitsWork(page.context) else { reply(.deny); return }
        delegate?.engine(self, permission: prompt, reply: reply) ?? reply(.deny)
    }
    func dismissPermission(_ id: String) { delegate?.engine(self, dismissPermission: id) }
}
