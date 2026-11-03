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
        let permissionsChanged = websitePolicy.preferences.rules.mapValues(\.permissions) != policy.preferences.rules.mapValues(\.permissions)
            || websitePolicy.preferences.embeddedPermissions != policy.preferences.embeddedPermissions
        websitePolicy = policy
        if permissionsChanged, let origin = browser.url.flatMap(SiteOrigin.init) { syncPermissions(top: origin) }
        configureRequestFilter(browser.url)
        if changed || (frozen && websiteOperationProtected()) { refreshWebsitePolicy() }
    }

    func configureRequestFilter(_ url: URL?) {
        let rule = url.flatMap(SiteOrigin.init).map { websitePolicy.preferences.rule(for: $0) } ?? SiteRule()
        let rules = websitePolicy.preferences.blockingRules ?? .builtIn
        // The profile's EasyList-syntax lists, judged against this document: third-party, $domain and page-wide
        // exceptions read the page the request belongs to (a new top-level page judges itself).
        let lists = rule.blocking ? engine.filterLists.lists(websitePolicy.preferences.activeFilterKeys) : []
        browser.requestFilter?.configure(enabled: rule.blocking, hosts: rules.blockedHosts, paths: rules.blockedPathPrefixes,
                                         urlPrefixes: rules.blockedURLPrefixes ?? [], matcher: lists.isEmpty ? nil : FilterResourceTypes.matcher(lists, document: url))
    }

    func refreshWebsitePolicy() {
        refreshBoosts()
        if case .profile = context { browser.setWebsiteColorScheme(websitePolicy.appearance.rawValue) }
        guard case .ready(let document) = mainDocument.availability, let origin = browser.url.flatMap(SiteOrigin.init) else { return }
        policyRevision += 1
        let revision = policyRevision
        let policy = websitePolicy
        let trace = ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil
        if trace { print("[site-lifecycle] refresh page=\(id) revision=\(revision) visible=\(policy.visible) cachedFrozen=\(frozen)") }
        let rule = policy.preferences.rule(for: origin)
        let css = policy.themeCSS.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value);" }.joined()
        let rules = policy.preferences.blockingRules ?? .builtIn
        let lists = rule.blocking ? engine.filterLists.lists(policy.preferences.activeFilterKeys) : []
        let listed = FilterLists.hiddenSelectors(lists, documentURL: browser.url, pageFlags: FilterLists.pageFlags(lists, documentURL: browser.url))
        // One rule per selector, so a selector this Chromium does not support drops alone.
        let cosmetic = rule.blocking ? (rules.cosmeticSelectors + listed).map { $0 + "{display:none!important;}" }.joined(separator: "\n") : ""
        let banners = rule.hideCookieBanners ? "[data-cookie-banner],[aria-label=\"cookie consent\"]{display:none!important;}" : ""
        // A dedicated style element changes no inline user styles. Opt-out removes exactly this owner's CSS.
        let content = ":root{" + css + "}" + cosmetic + banners
        let literal = Self.jsString(content)
        if websiteStyleOwner?.document != document { websiteStyleOwner = (document, UUID().uuidString) }
        let owner = Self.jsString(websiteStyleOwner!.id)
        let mediaMarker = Self.jsString("data-brk-media-" + websiteStyleOwner!.id)
        // Dark (P19-b): a page that leaves its canvas to the browser shows Chromium's dark Canvas (#121212) as in Arc,
        // not the Chrome-runtime frame grey (#202020) drawn under it. Pages with their own root or body background
        // keep it (a root background would stop the body's from filling the canvas).
        let canvas = policy.appearance == .dark ? "true" : "false"
        let script = """
        (()=>{
          if(location.origin!==\(Self.jsString(origin.value)))return false;
          const owner=\(owner);let s=document.querySelector('style[data-brk-policy-owner="'+owner+'"]');
          if(!s){s=document.createElement('style');s.setAttribute('data-brk-policy-owner',owner);(document.head||document.documentElement).append(s);}
          s.textContent=\(literal);
          if(\(canvas)){const bare=e=>{const c=getComputedStyle(e);return c.backgroundColor==='rgba(0, 0, 0, 0)'&&c.backgroundImage==='none'};
            if(bare(document.documentElement)&&(!document.body||bare(document.body)))s.textContent+=':where(html){background-color:Canvas}';}
          if(!s.textContent||s.textContent===':root{}')s.remove();
          const marker=\(mediaMarker), installed=marker+'-observed';
          const reconcile=()=>{for(const media of document.querySelectorAll('audio,video')){
            if(!media.paused&&!media.ended)media.setAttribute(marker,'');else media.removeAttribute(marker);
          }};
          if(!document.documentElement.hasAttribute(installed)){
            const changed=event=>{
              const media=event.target;if(!(media instanceof HTMLMediaElement))return;
              if(event.type==='play')media.setAttribute(marker,'');
              else if(event.type==='ended'||!document.hidden)media.removeAttribute(marker);
            };
            for(const event of ['play','pause','ended'])document.addEventListener(event,changed,true);
            document.addEventListener('visibilitychange',()=>{if(!document.hidden)reconcile();},true);
            document.documentElement.setAttribute(installed,'');reconcile();
          }
          if(!document.hidden)reconcile();
          return true;
        })();
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
                // Arc's Dark (P19-b) also darkens pages without a dark style: Chromium's automatic dark mode. Light and
                // Automatic leave pages as their own styles draw them. Sent when it changes and once per document while
                // on, so the refreshes of a hidden page (which wait on these round trips before freezing it) do not grow.
                let dark = policy.appearance == .dark, sent = self.autoDark
                if (sent?.enabled ?? false) != dark || dark && sent?.document != document {
                    _ = try await self.browser.protocolSession.call("Emulation.setAutoDarkModeOverride", dark ? ["enabled": true] : [:])
                    self.autoDark = (document, dark)
                    guard self.policyRevision == revision, self.engine.isLive(self), self.mainDocument.availability == .ready(document) else { return }
                }
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
                    // Chromium automatically pauses muted media on hide. Preserve the document's playing
                    // intent until a visible pause, end, removal, or visible reconciliation clears it.
                    let expression = "Array.from(document.querySelectorAll('video,audio')).some(x=>!x.ended&&(!x.paused||x.hasAttribute(\(mediaMarker))))"
                    let result = try await self.browser.protocolSession.call("Runtime.evaluate", ["expression": expression, "returnByValue": true, "contextId": contextID])
                    media = (result["result"] as? [String: Any])?["value"] as? Bool ?? true
                    if trace { print("[site-media] page=\(self.id) revision=\(revision) protected=\(media)") }
                }
                guard self.policyRevision == revision, self.engine.isLive(self), self.mainDocument.availability == .ready(document) else { return }
                let freeze = shouldFreeze && !media && !self.websiteOperationProtected()
                if trace { print("[site-lifecycle] apply page=\(self.id) revision=\(revision) frozen=\(freeze)") }
                _ = try await self.browser.protocolSession.call("Page.setWebLifecycleState", ["state": freeze ? "frozen" : "active"])
                guard self.policyRevision == revision, self.engine.isLive(self), self.mainDocument.availability == .ready(document) else { return }
                self.frozen = freeze
                self.websiteError = nil
                let authorization = await OSSiteAuthorization.shared.readback()
                guard self.policyRevision == revision, self.engine.isLive(self), self.mainDocument.availability == .ready(document) else { return }
                self.engine.pageDidEmit(self, .websitePolicyApplied(WebsitePolicyStatus(document: document, appearance: policy.appearance, themeApplied: !policy.themeCSS.isEmpty, frozen: freeze, error: nil, osAuthorization: authorization, htmlMediaActive: shouldFreeze ? media : nil)))
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
        guard !isAIReader else { callback.resolve(.deny); return }
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
        let unprompted: [(CefPermissionKind, SiteCapability)] = [(.clipboard, .clipboard), (.midi, .midi), (.windowManagement, .windowManagement),
            (.storageAccess, .storageAccess), (.sensors, .sensors), (.downloads, .automaticDownloads), (.pointerLock, .pointerLock)]
        for (kind, capability) in unprompted where request.kinds.contains(kind) { kinds.insert(capability) }
        let supported: CefPermissionKind = [.camera, .microphone, .geolocation, .notifications, .clipboard, .midi, .windowManagement, .storageAccess, .sensors, .downloads, .pointerLock]
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
        let prompt = owner.prompt
        if valid && decision == .allow {
            permissionGrants.append((prompt.target.document, prompt.requestingOrigin, prompt.target.origin, prompt.capabilities))
        }
        owner.callback.resolve(valid && decision == .allow ? .allow : decision == .ask ? .dismiss : .deny)
    }

    /// Chromium stores every request Brk accepts or blocks. When the document that was allowed ends, its grants go back
    /// to what Brk remembers: an Allow this time returns to asking.
    func settlePermissionGrants(keeping document: DocumentToken?) {
        let ended = permissionGrants.filter { $0.document != document }
        permissionGrants.removeAll { $0.document != document }
        for grant in ended { pushPermissions(grant.capabilities, requesting: grant.requesting, top: grant.top) }
    }

    /// Writes Brk's remembered choices for a top-level site (and what it embeds) into Chromium's store, so a choice
    /// changed in the site settings takes effect: allow, block, or back to asking. Grants of the live document stay.
    func syncPermissions(top: SiteOrigin) {
        let live = Set(permissionGrants.filter { $0.top == top }.flatMap(\.capabilities))
        pushPermissions(Set(SiteCapability.prompted).subtracting(live), requesting: top, top: top)
        for key in (websitePolicy.preferences.embeddedPermissions ?? [:]).keys {
            let parts = key.split(separator: "\n").map(String.init)
            guard parts.count == 2, parts[0] == top.value, let url = URL(string: parts[1]), let requesting = SiteOrigin(url) else { continue }
            pushPermissions(Set(SiteCapability.prompted), requesting: requesting, top: top)
        }
    }

    private func pushPermissions(_ capabilities: Set<SiteCapability>, requesting: SiteOrigin, top: SiteOrigin) {
        let remembered = websitePolicy.preferences.permissions(for: requesting, embeddedIn: top)
        for capability in capabilities {
            guard let kind = Self.permissionKind(capability) else { continue }
            // A remembered allow of a device macOS must authorize stays with Brk (asking), so the OS check runs first.
            let allowed: Bool? = switch remembered[capability] { case .allow?: capability.needsOSAuthorization ? nil : true; case .deny?: false; default: nil }
            browser.setPermission(kind, requesting: requesting.url, topLevel: top.url, allowed: allowed)
        }
    }

    static func permissionKind(_ capability: SiteCapability) -> CefPermissionKind? {
        switch capability {
        case .camera: .camera
        case .microphone: .microphone
        case .location: .geolocation
        case .notifications: .notifications
        case .clipboard: .clipboard
        case .midi: .midi
        case .windowManagement: .windowManagement
        case .storageAccess: .storageAccess
        case .sensors: .sensors
        case .automaticDownloads: .downloads
        case .pointerLock: .pointerLock
        case .desktopCapture, .other: nil
        }
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
