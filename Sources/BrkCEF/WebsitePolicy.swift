import AppKit
import BrkBase
import CefKit
import Foundation

@MainActor
struct PagePermissionRequest {
    let prompt: SitePermissionPrompt
    let nativeID: UInt64?
    let callback: CefPermissionCallback
}

extension ChromePage {
    func matches(_ target: SiteTarget) -> Bool {
        incarnation == target.document.browser && context == target.context
            && mainDocument.availability == .ready(target.document) && browser.url.flatMap(SiteOrigin.init) == target.origin
    }

    func matchesPermission(_ target: SiteTarget) -> Bool {
        let token: DocumentToken?
        switch mainDocument.availability { case .ready(let value), .loading(let value): token = value; case .unavailable: token = nil }
        return token == target.document && incarnation == target.document.browser && context == target.context && browser.url.flatMap(SiteOrigin.init) == target.origin
    }

    func websiteOperationProtected() -> Bool {
        audio.audible || pictureInPictureDocument == mainDocument.readyDocument && pictureInPictureDocument != nil
            || engine.transfers.contains(context: context) || !permissionRequests.isEmpty
            || engine.resources.entries[incarnation]?.leases.isEmpty == false
    }

    func resumeForOperation(_ document: DocumentToken) async throws {
        func valid() -> Bool {
            guard let entry = engine.resources.entries[incarnation] else { return false }
            return entry.resource === self && !entry.closing && !entry.browserClosed && !entry.leases.isEmpty
                && mainDocument.availability == .ready(document)
        }
        guard valid() else { throw CocoaError(.userCancelled) }
        guard browser.url.flatMap(SiteOrigin.init) != nil else { return }
        policyRevision += 1
        _ = try await browser.protocolSession.call("Page.setWebLifecycleState", ["state": "active"])
        guard valid() else { throw CocoaError(.userCancelled) }
        frozen = false
    }

    func applyWebsitePolicy(_ policy: WebsitePolicy) {
        let changed = websitePolicy != policy
        websitePolicy = policy
        configureRequestFilter(browser.url)
        if changed || (frozen && websiteOperationProtected()) { refreshWebsitePolicy() }
    }

    func configureRequestFilter(_ url: URL?) {
        let rule = url.flatMap(SiteOrigin.init).map { websitePolicy.preferences.rule(for: $0) } ?? SiteRule()
        let rules = websitePolicy.preferences.blockingRules ?? .builtIn
        browser.requestFilter?.configure(enabled: rule.blocking, hosts: rules.blockedHosts, paths: rules.blockedPathPrefixes, urlPrefixes: rules.blockedURLPrefixes ?? [])
    }

    func refreshWebsitePolicy() {
        if case .profile = context { browser.setWebsiteColorScheme(websitePolicy.appearance.rawValue) }
        guard case .ready(let document) = mainDocument.availability, let origin = browser.url.flatMap(SiteOrigin.init) else { return }
        policyRevision += 1
        let revision = policyRevision
        let policy = websitePolicy
        let rule = policy.preferences.rule(for: origin)
        let css = policy.themeCSS.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value);" }.joined()
        let rules = policy.preferences.blockingRules ?? .builtIn
        let cosmetic = rule.blocking ? rules.cosmeticSelectors.map { $0 + "{display:none!important;}" }.joined() : ""
        let banners = rule.hideCookieBanners ? "[data-cookie-banner],[aria-label=\"cookie consent\"]{display:none!important;}" : ""
        // A dedicated style element changes no inline user styles. Opt-out removes exactly this owner's CSS.
        let content = ":root{" + css + "}" + cosmetic + banners
        let literal = Self.jsString(content)
        if websiteStyleOwner?.document != document { websiteStyleOwner = (document, UUID().uuidString) }
        let owner = Self.jsString(websiteStyleOwner!.id)
        let script = """
        (()=>{if(location.origin!==\(Self.jsString(origin.value)))return false;const owner=\(owner);let s=document.querySelector('style[data-brk-policy-owner="'+owner+'"]');if(!s){s=document.createElement('style');s.setAttribute('data-brk-policy-owner',owner);(document.head||document.documentElement).append(s);}s.textContent=\(literal);if(!s.textContent||s.textContent===':root{}')s.remove();return true;})();
        """
        Task { @MainActor [weak self] in
            guard let self, self.engine.isLive(self), self.policyRevision == revision, self.mainDocument.availability == .ready(document) else { return }
            do {
                if self.frozen {
                    _ = try await self.browser.protocolSession.call("Page.setWebLifecycleState", ["state": "active"])
                    guard self.policyRevision == revision, self.engine.isLive(self), self.mainDocument.availability == .ready(document) else { return }
                    self.frozen = false
                }
                // Color-scheme emulation changes matchMedia and CSS. Automatic resolves the native application appearance and updates through its owned observer.
                let automatic = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
                let effective = policy.appearance == .automatic ? automatic : policy.appearance.rawValue
                let features: [[String: String]] = [["name": "prefers-color-scheme", "value": effective]]
                _ = try await self.browser.protocolSession.call("Emulation.setEmulatedMedia", ["features": features])
                guard self.policyRevision == revision, self.engine.isLive(self), self.mainDocument.availability == .ready(document) else { return }
                let frameTree = try await self.browser.protocolSession.call("Page.getFrameTree")
                guard let tree = frameTree["frameTree"] as? [String: Any], let frame = tree["frame"] as? [String: Any], let frameID = frame["id"] as? String,
                      self.policyRevision == revision, self.mainDocument.availability == .ready(document), self.engine.isLive(self) else { return }
                let world = try await self.browser.protocolSession.call("Page.createIsolatedWorld", ["frameId": frameID, "worldName": "brk-site-policy"])
                guard let contextID = world["executionContextId"] as? Int, self.policyRevision == revision,
                      self.mainDocument.availability == .ready(document), self.engine.isLive(self) else { return }
                _ = try await self.browser.protocolSession.call("Runtime.evaluate", ["expression": script, "contextId": contextID, "returnByValue": true])
                guard self.policyRevision == revision, self.mainDocument.availability == .ready(document), self.engine.isLive(self) else { return }
                let shouldFreeze = !policy.visible && rule.suspendWhenHidden && !rule.keepAlive && !rule.excludeSuspension
                    && !self.websiteOperationProtected()
                var media = false
                if shouldFreeze {
                    let result = try await self.browser.protocolSession.call("Runtime.evaluate", ["expression": "Array.from(document.querySelectorAll('video,audio')).some(x=>!x.paused&&!x.ended)", "returnByValue": true, "contextId": contextID])
                    media = (result["result"] as? [String: Any])?["value"] as? Bool ?? true
                }
                guard self.policyRevision == revision, self.engine.isLive(self), self.mainDocument.availability == .ready(document) else { return }
                let freeze = shouldFreeze && !media && !self.websiteOperationProtected()
                _ = try await self.browser.protocolSession.call("Page.setWebLifecycleState", ["state": freeze ? "frozen" : "active"])
                guard self.policyRevision == revision, self.engine.isLive(self), self.mainDocument.availability == .ready(document) else { return }
                self.frozen = freeze
                self.websiteError = nil
                let authorization = await OSSiteAuthorization.shared.readback()
                guard self.policyRevision == revision, self.engine.isLive(self), self.mainDocument.availability == .ready(document) else { return }
                self.engine.pageDidEmit(self, .websitePolicyApplied(WebsitePolicyStatus(document: document, appearance: policy.appearance, themeApplied: !policy.themeCSS.isEmpty, frozen: freeze, error: nil, osAuthorization: authorization)))
            } catch {
                self.websiteError = error.localizedDescription
                guard self.policyRevision == revision, self.mainDocument.availability == .ready(document), self.engine.isLive(self) else { return }
                self.engine.pageDidEmit(self, .websitePolicyApplied(WebsitePolicyStatus(document: document, appearance: policy.appearance, themeApplied: false, frozen: self.frozen, error: error.localizedDescription)))
            }
        }
    }

    static func jsString(_ string: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [string])
        return String(decoding: data, as: UTF8.self).dropFirst().dropLast().description
    }

    func browser(_ b: CefBrowser, permission request: CefPermissionRequest, callback: CefPermissionCallback) {
        let document: DocumentToken
        switch mainDocument.availability { case .ready(let value), .loading(let value): document = value; case .unavailable: callback.resolve(.deny); return }
        guard engine.isLive(self), let origin = b.url.flatMap(SiteOrigin.init), let url = URL(string: request.origin), let requesting = SiteOrigin(url) else {
            callback.resolve(.deny); return
        }
        var kinds: Set<SiteCapability> = []
        if request.desktopCapture { kinds.insert(.desktopCapture) }
        else {
            if request.kinds.contains(.camera) { kinds.insert(.camera) }
            if request.kinds.contains(.microphone) { kinds.insert(.microphone) }
        }
        if request.kinds.contains(.geolocation) { kinds.insert(.location) }
        if request.kinds.contains(.notifications) { kinds.insert(.notifications) }
        let supported: CefPermissionKind = [.camera, .microphone, .geolocation, .notifications]
        if !request.kinds.subtracting(supported).isEmpty || kinds.isEmpty { kinds.insert(.other) }
        // Screen capture needs a source picker; never describe it as device camera access.
        if kinds.contains(.desktopCapture) || kinds.contains(.other) { callback.resolve(.deny); return }
        let decisions = websitePolicy.preferences.permissions(for: requesting, embeddedIn: origin)
        if kinds.contains(where: { decisions[$0] == .deny }) { callback.resolve(.deny); return }
        let prompt = SitePermissionPrompt(id: UUID().uuidString,
            target: SiteTarget(document: document, context: context, origin: origin), requestingOrigin: requesting,
            capabilities: kinds, frame: request.frameIdentifier, mask: request.requestedMask)
        permissionRequests[prompt.id] = PagePermissionRequest(prompt: prompt, nativeID: request.promptID, callback: callback)
        Task { @MainActor [weak self] in
            let granted = await OSSiteAuthorization.shared.grants(kinds) { [weak self] in
                guard let self else { return false }
                return self.permissionRequests[prompt.id] != nil && self.engine.isLive(self) && self.matchesPermission(prompt.target)
            }
            guard let self, self.permissionRequests[prompt.id] != nil else { return }
            guard self.engine.isLive(self), self.matchesPermission(prompt.target), granted else {
                self.answerPermission(prompt.id, .deny); return
            }
            let currentDecisions = self.websitePolicy.preferences.permissions(for: requesting, embeddedIn: origin)
            if kinds.contains(where: { currentDecisions[$0] == .deny }) { self.answerPermission(prompt.id, .deny); return }
            if kinds.allSatisfy({ currentDecisions[$0] == .allow }) { self.answerPermission(prompt.id, .allow); return }
            self.engine.permission(self, prompt: prompt) { [weak self] decision in self?.answerPermission(prompt.id, decision) }
        }
    }

    func answerPermission(_ id: String, _ decision: SitePermission) {
        guard let owner = permissionRequests.removeValue(forKey: id) else { return }
        let valid = engine.isLive(self) && matchesPermission(owner.prompt.target)
        engine.dismissPermission(id)
        owner.callback.resolve(valid && decision == .allow ? .allow : decision == .ask ? .dismiss : .deny)
    }

    func cancelPermissions(frame: String? = nil) {
        let ids = permissionRequests.filter { frame == nil || $0.value.prompt.frame == nil || $0.value.prompt.frame == frame }.map(\.key)
        for id in ids { answerPermission(id, .ask) }
    }
    func browser(_ b: CefBrowser, willNavigateFrame identifier: String) { cancelPermissions(frame: identifier) }
    func browser(_ b: CefBrowser, dismissedPermission promptID: UInt64) {
        let ids = permissionRequests.filter { $0.value.nativeID == promptID }.map(\.key)
        for id in ids {
            guard let owner = permissionRequests.removeValue(forKey: id) else { continue }
            engine.dismissPermission(id)
            owner.callback.invalidate()
        }
    }
}

extension CEFEngine {
    /// captures-media owns the actual PiP surface. A stale owner cannot protect a replacement page.
    public func setPictureInPicture(_ active: Bool, document: DocumentToken) {
        guard phase == .running, let page = live[document.browser.page], page.incarnation == document.browser,
              page.readyDocument == document, contexts.permitsWork(page.context) else { return }
        page.pictureInPictureDocument = active ? document : nil
        page.refreshWebsitePolicy()
    }
}
