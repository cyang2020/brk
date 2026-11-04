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

    /// What keeps a hidden page running even when its site is set to suspend: audible sound, picture in picture
    /// (video, document, or the typed hook), camera or microphone capture, a download in its profile, an open
    /// permission request, and operations holding the browser (document output, extension work).
    func websiteOperationProtected() -> Bool {
        audio.audible || pictureInPictureDocument == mainDocument.readyDocument && pictureInPictureDocument != nil
            || documentPiPActive || mediaPlayers.contains(where: \.pictureInPicture) || capturingMedia
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
        let before = websitePolicy.preferences
        websitePolicy = policy
        if let origin = browser.url.flatMap(SiteOrigin.init) {
            permissionSync += Self.changedPermissions(before, policy.preferences, top: origin)
            flushPermissionSync()
        }
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
        let framesPlaying = mediaPlayers.contains { $0.id.frame != 0 && !$0.paused && !$0.ended }
        if policy.visible { subframeMediaIntent = framesPlaying } else if framesPlaying { subframeMediaIntent = true }
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
          // The playing intent lives in this isolated world (one per document), never in the page's DOM.
          if(!globalThis.brkMedia){
            const playing=new WeakSet();
            const reconcile=()=>{for(const media of document.querySelectorAll('audio,video')){
              if(!media.paused&&!media.ended)playing.add(media);else playing.delete(media);
            }};
            const changed=event=>{
              const media=event.target;if(!(media instanceof HTMLMediaElement))return;
              if(event.type==='play')playing.add(media);
              else if(event.type==='ended'||!document.hidden)playing.delete(media);
            };
            for(const event of ['play','pause','ended'])document.addEventListener(event,changed,true);
            document.addEventListener('visibilitychange',()=>{if(!document.hidden)reconcile();},true);
            globalThis.brkMedia={playing,reconcile};reconcile();
          }
          if(!document.hidden)globalThis.brkMedia.reconcile();
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
                @MainActor func newWorld() async throws -> Int? {
                    let frameTree = try await self.browser.protocolSession.call("Page.getFrameTree")
                    guard let tree = frameTree["frameTree"] as? [String: Any], let frame = tree["frame"] as? [String: Any], let frameID = frame["id"] as? String,
                          self.policyRevision == revision, self.mainDocument.availability == .ready(document), self.engine.isLive(self) else { return nil }
                    let world = try await self.browser.protocolSession.call("Page.createIsolatedWorld", ["frameId": frameID, "worldName": "brk-site-policy"])
                    guard let created = world["executionContextId"] as? Int, self.policyRevision == revision,
                          self.mainDocument.availability == .ready(document), self.engine.isLive(self) else { return nil }
                    self.policyWorld = (document, created)
                    return created
                }
                var contextID: Int
                if let world = self.policyWorld, world.document == document { contextID = world.context }
                else if let created = try await newWorld() { contextID = created } else { return }
                do {
                    _ = try await self.browser.protocolSession.call("Runtime.evaluate", ["expression": script, "contextId": contextID, "returnByValue": true])
                } catch where self.policyWorld?.context == contextID {
                    // The kept world is gone (its context went with a renderer swap): one new world, one more try.
                    self.policyWorld = nil
                    guard let created = try await newWorld() else { return }
                    contextID = created
                    _ = try await self.browser.protocolSession.call("Runtime.evaluate", ["expression": script, "contextId": contextID, "returnByValue": true])
                }
                guard self.policyRevision == revision, self.mainDocument.availability == .ready(document), self.engine.isLive(self) else { return }
                let shouldFreeze = !policy.visible && rule.suspendWhenHidden && !rule.keepAlive && !rule.excludeSuspension
                    && !self.websiteOperationProtected()
                var media = false
                if shouldFreeze {
                    // Chromium automatically pauses muted media on hide. Preserve the document's playing
                    // intent until a visible pause, end, removal, or visible reconciliation clears it.
                    let expression = "Array.from(document.querySelectorAll('video,audio')).some(x=>!x.ended&&(!x.paused||globalThis.brkMedia?.playing.has(x)===true))"
                    let result = try await self.browser.protocolSession.call("Runtime.evaluate", ["expression": expression, "returnByValue": true, "contextId": contextID])
                    media = (result["result"] as? [String: Any])?["value"] as? Bool ?? true
                    // The main document cannot see into cross-origin frames; the audio extension's reading can.
                    media = media || self.subframeMediaIntent
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
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
            print("[site-permission] request id=\(prompt.id) native=\(request.promptID.map(String.init) ?? "-") capabilities=\(kinds.map(\.rawValue).sorted())")
        }
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
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
            print("[site-permission] answer id=\(id) decision=\(decision.rawValue) valid=\(valid) capabilities=\(prompt.capabilities.map(\.rawValue).sorted())")
        }
        // Chromium stores this answer itself; a choice remembered with it needs no second write.
        permissionSync = permissionSync.compactMap { change in
            guard change.requesting == prompt.requestingOrigin, change.top == prompt.target.origin else { return change }
            let rest = change.capabilities.subtracting(prompt.capabilities)
            return rest.isEmpty ? nil : (change.requesting, change.top, rest)
        }
        if valid && decision == .allow {
            permissionGrants.append((prompt.target.document, prompt.requestingOrigin, prompt.target.origin, prompt.capabilities))
        }
        owner.callback.resolve(valid && decision == .allow ? .allow : decision == .ask ? .dismiss : .deny)
        // A choice remembered with this answer reached the policy before the answer; write it once Chromium has the answer.
        Task { @MainActor [weak self] in self?.flushPermissionSync() }
    }

    /// Chromium stores every request Brk accepts or blocks. When the document that was allowed ends, its grants go back
    /// to what Brk remembers: an Allow this time returns to asking.
    func settlePermissionGrants(keeping document: DocumentToken?) {
        let ended = permissionGrants.filter { $0.document != document }
        permissionGrants.removeAll { $0.document != document }
        for grant in ended { pushPermissions(grant.capabilities, requesting: grant.requesting, top: grant.top) }
    }

    /// The remembered choices that differ between two preference values for a top-level site and what it embeds.
    static func changedPermissions(_ old: SitePreferences, _ new: SitePreferences, top: SiteOrigin) -> [(requesting: SiteOrigin, top: SiteOrigin, capabilities: Set<SiteCapability>)] {
        func differing(_ a: [SiteCapability: SitePermission], _ b: [SiteCapability: SitePermission]) -> Set<SiteCapability> {
            Set(SiteCapability.prompted.filter { (a[$0] ?? .ask) != (b[$0] ?? .ask) })
        }
        var out: [(SiteOrigin, SiteOrigin, Set<SiteCapability>)] = []
        let own = differing(old.rule(for: top).permissions, new.rule(for: top).permissions)
        if !own.isEmpty { out.append((top, top, own)) }
        let prefix = top.value + "\n"
        for key in Set((old.embeddedPermissions ?? [:]).keys).union((new.embeddedPermissions ?? [:]).keys) where key.hasPrefix(prefix) {
            guard let url = URL(string: String(key.dropFirst(prefix.count))), let requesting = SiteOrigin(url) else { continue }
            let embedded = differing(old.embeddedPermissions?[key] ?? [:], new.embeddedPermissions?[key] ?? [:])
            if !embedded.isEmpty { out.append((requesting, top, embedded)) }
        }
        return out.map { (requesting: $0.0, top: $0.1, capabilities: $0.2) }
    }

    /// Writes changed remembered choices into Chromium's store, so a choice changed in the site settings takes effect
    /// (allow, block, or back to asking). Waits while a request is open: Chromium settles it from the same store.
    func flushPermissionSync() {
        guard permissionRequests.isEmpty, !permissionSync.isEmpty else { return }
        let work = permissionSync
        permissionSync = []
        let live = permissionGrants.filter { $0.document == mainDocument.readyDocument }
        for change in work {
            let granted = Set(live.filter { $0.requesting == change.requesting && $0.top == change.top }.flatMap(\.capabilities))
            pushPermissions(change.capabilities.subtracting(granted), requesting: change.requesting, top: change.top)
        }
    }

    private func pushPermissions(_ capabilities: Set<SiteCapability>, requesting: SiteOrigin, top: SiteOrigin) {
        let remembered = websitePolicy.preferences.permissions(for: requesting, embeddedIn: top)
        for capability in capabilities {
            guard let kind = Self.permissionKind(capability) else { continue }
            // A remembered allow of a device macOS must authorize stays with Brk (asking), so the OS check runs first.
            let allowed: Bool? = switch remembered[capability] { case .allow?: capability.needsOSAuthorization ? nil : true; case .deny?: false; default: nil }
            if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
                print("[site-permission] chromium store \(capability.rawValue) \(requesting.value) in \(top.value) = \(allowed.map { $0 ? "allow" : "block" } ?? "ask")")
            }
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
        case .windowManagement: .windowManagement
        case .storageAccess: .storageAccess
        case .sensors: .sensors
        case .automaticDownloads: .downloads
        case .pointerLock: .pointerLock
        // Chromium 154 traps on writing the MIDI settings (probed: CEF_CONTENT_SETTING_TYPE_MIDI / _MIDI_SYSEX), so a
        // MIDI choice is applied when Chromium asks Brk, and Chromium's own stored MIDI decision is left alone.
        case .midi, .desktopCapture, .other: nil
        }
    }

    func cancelPermissions(frame: String? = nil) {
        let ids = permissionRequests.filter { frame == nil || $0.value.prompt.frame == nil || $0.value.prompt.frame == frame }.map(\.key)
        if !ids.isEmpty, ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil { print("[site-permission] cancel frame=\(frame ?? "all") ids=\(ids)") }
        for id in ids { answerPermission(id, .ask) }
    }
    func browser(_ b: CefBrowser, willNavigateFrame identifier: String) { cancelPermissions(frame: identifier) }
    func browser(_ b: CefBrowser, dismissedPermission promptID: UInt64) {
        let ids = permissionRequests.filter { $0.value.nativeID == promptID }.map(\.key)
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil { print("[site-permission] chromium dismissed native=\(promptID) open=\(ids)") }
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
