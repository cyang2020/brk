import AppKit
import BrkBase
import CBrkCore
import Foundation

/// One open permission request of a page: Brk's prompt and Chromium's request it answers.
@MainActor
struct CorePermissionRequest {
    let prompt: SitePermissionPrompt
    let request: any BrkCorePermissionRequest
}

/// Applies website policy through DevTools and answers Chromium's permission requests with remembered site choices.
extension CorePage {
    var protocolSession: CoreProtocolSession { CoreProtocolSession(contents: contents) }

    func matches(_ target: SiteTarget) -> Bool {
        incarnation == target.document.browser && context == target.context
            && mainDocument.availability == .ready(target.document) && contents.committedURL.flatMap(SiteOrigin.init) == target.origin
    }

    func matchesPermission(_ target: SiteTarget) -> Bool {
        let token: DocumentToken?
        switch mainDocument.availability { case .ready(let value), .loading(let value): token = value; case .unavailable: token = nil }
        return token == target.document && incarnation == target.document.browser && context == target.context
            && contents.committedURL.flatMap(SiteOrigin.init) == target.origin
    }

    /// What keeps a hidden page running even when its site is set to suspend, as on CEF.
    func websiteOperationProtected() -> Bool {
        audible || pictureInPictureDocument == mainDocument.readyDocument && pictureInPictureDocument != nil
            || mediaPlayers.contains(where: \.pictureInPicture)
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
        guard contents.committedURL.flatMap(SiteOrigin.init) != nil else { return }
        policyRevision += 1
        _ = try await protocolSession.call("Page.setWebLifecycleState", ["state": "active"])
        guard valid() else { throw CocoaError(.userCancelled) }
        frozen = false
    }

    func applyWebsitePolicy(_ policy: WebsitePolicy) {
        let changed = websitePolicy != policy
        let before = websitePolicy.preferences
        websitePolicy = policy
        if let origin = contents.committedURL.flatMap(SiteOrigin.init) {
            permissionSync += Self.changedPermissions(before, policy.preferences, top: origin)
            flushPermissionSync()
        }
        configureRequestFilter(navigatingTo ?? contents.committedURL)
        if changed || (frozen && websiteOperationProtected()) { refreshWebsitePolicy() }
    }

    /// The profile's built-in blocking rules for this document, as Chromium's DevTools URL blocking (CEF uses a request handler). The
    /// EasyList-syntax filter lists are not applied on BrkCore yet.
    func configureRequestFilter(_ url: URL?) {
        let rule = url.flatMap(SiteOrigin.init).map { websitePolicy.preferences.rule(for: $0) } ?? SiteRule()
        let rules = websitePolicy.preferences.blockingRules ?? .builtIn
        var patterns: [String] = []
        if rule.blocking, ["http", "https"].contains(url?.scheme?.lowercased() ?? "") {
            for host in rules.blockedHosts {
                let name = Self.patternEscaped(host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                patterns += ["*://\(name):*/*", "*://*.\(name):*/*"]
            }
            for path in rules.blockedPathPrefixes { patterns.append("*://*:*" + Self.patternEscaped(path) + "*") }
            for prefix in rules.blockedURLPrefixes ?? [] {
                guard let base = URL(string: prefix), let scheme = base.scheme, let host = base.host else { continue }
                let port = base.port.map(String.init) ?? "*"
                patterns.append("\(scheme)://\(Self.patternEscaped(host)):\(port)" + Self.patternEscaped(base.path.isEmpty ? "/" : base.path) + "*")
            }
        }
        guard patterns != requestFilterPatterns else { return }
        requestFilterPatterns = patterns
        let session = protocolSession
        Task { @MainActor [weak self] in
            do {
                if !patterns.isEmpty, self?.requestFilterEnabled == false {
                    _ = try await session.call("Network.enable", ["maxPostDataSize": 0])
                    self?.requestFilterEnabled = true
                }
                _ = try await session.call("Network.setBlockedURLs", ["urlPatterns": patterns.map { ["urlPattern": $0, "block": true] }])
                self?.trace("[site-filter] page=\(self?.id.description ?? "-") patterns=\(patterns.count)")
            } catch {
                self?.trace("[site-filter] page=\(self?.id.description ?? "-") failed: \(error.localizedDescription)")
            }
        }
    }

    /// URLPattern constructor strings give these characters a meaning.
    static func patternEscaped(_ text: String) -> String {
        var out = ""
        for character in text {
            if ":*?+(){}[]\\".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }

    func refreshWebsitePolicy() {
        refreshBoosts()
        guard case .ready(let document) = mainDocument.availability, let origin = contents.committedURL.flatMap(SiteOrigin.init) else { return }
        policyRevision += 1
        let revision = policyRevision
        let policy = websitePolicy
        let rule = policy.preferences.rule(for: origin)
        let css = policy.themeCSS.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value);" }.joined()
        let rules = policy.preferences.blockingRules ?? .builtIn
        let cosmetic = rule.blocking ? rules.cosmeticSelectors.map { $0 + "{display:none!important;}" }.joined(separator: "\n") : ""
        let banners = rule.hideCookieBanners ? CookieBanners.css : ""
        let content = ":root{" + css + "}" + cosmetic + banners
        if websiteStyleOwner?.document != document { websiteStyleOwner = (document, UUID().uuidString) }
        let owner = Self.jsString(websiteStyleOwner!.id)
        let canvas = policy.appearance == .dark ? "true" : "false"
        let script = """
        (()=>{
          if(location.origin!==\(Self.jsString(origin.value)))return false;
          const owner=\(owner);let s=document.querySelector('style[data-brk-policy-owner="'+owner+'"]');
          if(!s){s=document.createElement('style');s.setAttribute('data-brk-policy-owner',owner);(document.head||document.documentElement).append(s);}
          s.textContent=\(Self.jsString(content));
          if(\(canvas)){const bare=e=>{const c=getComputedStyle(e);return c.backgroundColor==='rgba(0, 0, 0, 0)'&&c.backgroundImage==='none'};
            if(bare(document.documentElement)&&(!document.body||bare(document.body)))s.textContent+=':where(html){background-color:Canvas}';}
          if(!s.textContent||s.textContent===':root{}')s.remove();
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
        let session = protocolSession
        Task { @MainActor [weak self] in
            guard let self, self.engine.isLive(self), self.policyRevision == revision, self.mainDocument.availability == .ready(document) else { return }
            @MainActor func current() -> Bool { self.policyRevision == revision && self.engine.isLive(self) && self.mainDocument.availability == .ready(document) }
            do {
                if self.frozen {
                    _ = try await session.call("Page.setWebLifecycleState", ["state": "active"])
                    guard current() else { return }
                    self.frozen = false
                }
                let automatic = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
                let effective = policy.appearance == .automatic ? automatic : policy.appearance.rawValue
                _ = try await session.call("Emulation.setEmulatedMedia", ["features": [["name": "prefers-color-scheme", "value": effective]]])
                guard current() else { return }
                let dark = policy.appearance == .dark, sent = self.autoDark
                if (sent?.enabled ?? false) != dark || dark && sent?.document != document {
                    _ = try await session.call("Emulation.setAutoDarkModeOverride", dark ? ["enabled": true] : [:])
                    self.autoDark = (document, dark)
                    guard current() else { return }
                }
                @MainActor func newWorld() async throws -> Int? {
                    let frameTree = try await session.call("Page.getFrameTree")
                    guard let tree = frameTree["frameTree"] as? [String: Any], let frame = tree["frame"] as? [String: Any], let frameID = frame["id"] as? String,
                          current() else { return nil }
                    let world = try await session.call("Page.createIsolatedWorld", ["frameId": frameID, "worldName": "brk-site-policy"])
                    guard let created = world["executionContextId"] as? Int, current() else { return nil }
                    self.policyWorld = (document, created)
                    return created
                }
                var contextID: Int
                if let world = self.policyWorld, world.document == document { contextID = world.context }
                else if let created = try await newWorld() { contextID = created } else { return }
                do {
                    _ = try await session.call("Runtime.evaluate", ["expression": script, "contextId": contextID, "returnByValue": true])
                } catch where self.policyWorld?.context == contextID {
                    self.policyWorld = nil
                    guard let created = try await newWorld() else { return }
                    contextID = created
                    _ = try await session.call("Runtime.evaluate", ["expression": script, "contextId": contextID, "returnByValue": true])
                }
                guard current() else { return }
                let shouldFreeze = !policy.visible && rule.suspendWhenHidden && !self.websiteOperationProtected()
                var media = false
                if shouldFreeze {
                    let expression = "Array.from(document.querySelectorAll('video,audio')).some(x=>!x.ended&&(!x.paused||globalThis.brkMedia?.playing.has(x)===true))"
                    let result = try await session.call("Runtime.evaluate", ["expression": expression, "returnByValue": true, "contextId": contextID])
                    media = (result["result"] as? [String: Any])?["value"] as? Bool ?? true
                }
                guard current() else { return }
                let freeze = shouldFreeze && !media && !self.websiteOperationProtected()
                _ = try await session.call("Page.setWebLifecycleState", ["state": freeze ? "frozen" : "active"])
                guard current() else { return }
                self.frozen = freeze
                self.websiteError = nil
                let authorization = await OSSiteAuthorization.shared.readback()
                guard current() else { return }
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

    // MARK: Permissions

    static func capabilities(_ kinds: BrkCorePermissionKind) -> Set<SiteCapability> {
        var out: Set<SiteCapability> = []
        let map: [(BrkCorePermissionKind, SiteCapability)] = [(.camera, .camera), (.microphone, .microphone), (.geolocation, .location),
            (.notifications, .notifications), (.clipboard, .clipboard), (.midi, .midi), (.windowManagement, .windowManagement),
            (.storageAccess, .storageAccess), (.sensors, .sensors), (.multipleDownloads, .automaticDownloads), (.pointerLock, .pointerLock)]
        for (kind, capability) in map where kinds.contains(kind) { out.insert(capability) }
        if kinds.contains(.other) || out.isEmpty { out.insert(.other) }
        return out
    }

    /// Chromium's PermissionRequestManager asks (CEF's OnShowPermissionPrompt): the same checks and prompt as on CEF.
    func requestPermission(_ request: any BrkCorePermissionRequest) {
        guard !isAIReader else { request.answer(.deny); return }
        let document: DocumentToken
        switch mainDocument.availability { case .ready(let value), .loading(let value): document = value; case .unavailable: request.answer(.deny); return }
        guard engine.isLive(self), let origin = contents.committedURL.flatMap(SiteOrigin.init),
              let url = URL(string: request.requestingOrigin), let requesting = SiteOrigin(url) else {
            request.answer(.deny); return
        }
        let kinds = Self.capabilities(request.kinds)
        if kinds.contains(.other) { request.answer(.deny); return }
        let decisions = websitePolicy.preferences.permissions(for: requesting, embeddedIn: origin)
        if kinds.contains(where: { decisions[$0] == .deny }) { request.answer(.deny); return }
        let prompt = SitePermissionPrompt(id: UUID().uuidString, target: SiteTarget(document: document, context: context, origin: origin),
                                          requestingOrigin: requesting, capabilities: kinds, frame: nil, mask: request.kinds.rawValue)
        permissionRequests[prompt.id] = CorePermissionRequest(prompt: prompt, request: request)
        trace("[site-permission] request id=\(prompt.id) native=\(request.promptID) capabilities=\(kinds.map(\.rawValue).sorted())")
        Task { @MainActor [weak self] in
            let granted = await OSSiteAuthorization.shared.grants(kinds) { [weak self] in
                guard let self else { return false }
                return self.permissionRequests[prompt.id] != nil && self.engine.isLive(self) && self.matchesPermission(prompt.target)
            }
            guard let self, self.permissionRequests[prompt.id] != nil else { return }
            guard self.engine.isLive(self), self.matchesPermission(prompt.target), granted else { self.answerPermission(prompt.id, .deny); return }
            let current = self.websitePolicy.preferences.permissions(for: requesting, embeddedIn: origin)
            if kinds.contains(where: { current[$0] == .deny }) { self.answerPermission(prompt.id, .deny); return }
            if kinds.allSatisfy({ current[$0] == .allow }) { self.answerPermission(prompt.id, .allow); return }
            self.engine.permission(self, prompt: prompt) { [weak self] decision in self?.answerPermission(prompt.id, decision) }
        }
    }

    func answerPermission(_ id: String, _ decision: SitePermission) {
        guard let owner = permissionRequests.removeValue(forKey: id) else { return }
        let valid = engine.isLive(self) && matchesPermission(owner.prompt.target)
        engine.dismissPermission(id)
        let prompt = owner.prompt
        trace("[site-permission] answer id=\(id) decision=\(decision.rawValue) valid=\(valid) capabilities=\(prompt.capabilities.map(\.rawValue).sorted())")
        permissionSync = permissionSync.compactMap { change in
            guard change.requesting == prompt.requestingOrigin, change.top == prompt.target.origin else { return change }
            let rest = change.capabilities.subtracting(prompt.capabilities)
            return rest.isEmpty ? nil : (change.requesting, change.top, rest)
        }
        if valid && decision == .allow {
            permissionGrants.append((prompt.target.document, prompt.requestingOrigin, prompt.target.origin, prompt.capabilities))
        }
        owner.request.answer(valid && decision == .allow ? .allow : decision == .ask ? .dismiss : .deny)
        Task { @MainActor [weak self] in self?.flushPermissionSync() }
    }

    /// When the document that was allowed ends, its grants go back to what Brk remembers: an Allow this time returns to asking.
    func settlePermissionGrants(keeping document: DocumentToken?) {
        let ended = permissionGrants.filter { $0.document != document }
        permissionGrants.removeAll { $0.document != document }
        for grant in ended { pushPermissions(grant.capabilities, requesting: grant.requesting, top: grant.top) }
    }

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
            let allowed: Bool? = switch remembered[capability] { case .allow?: capability.needsOSAuthorization ? nil : true; case .deny?: false; default: nil }
            trace("[site-permission] chromium store \(capability.rawValue) \(requesting.value) in \(top.value) = \(allowed.map { $0 ? "allow" : "block" } ?? "ask")")
            contents.setPermission(kind, requestingOrigin: requesting.url, topLevelOrigin: top.url, allowed: allowed.map { NSNumber(value: $0) })
        }
    }

    static func permissionKind(_ capability: SiteCapability) -> BrkCorePermissionKind? {
        switch capability {
        case .camera: .camera
        case .microphone: .microphone
        case .location: .geolocation
        case .notifications: .notifications
        case .clipboard: .clipboard
        case .windowManagement: .windowManagement
        case .storageAccess: .storageAccess
        case .sensors: .sensors
        case .automaticDownloads: .multipleDownloads
        case .pointerLock: .pointerLock
        // As on CEF: Chromium's own stored MIDI decision is left alone; the choice is applied when Chromium asks.
        case .midi, .desktopCapture, .other: nil
        }
    }

    func cancelPermissions() {
        let ids = Array(permissionRequests.keys)
        if !ids.isEmpty { trace("[site-permission] cancel ids=\(ids)") }
        for id in ids { answerPermission(id, .ask) }
    }

    /// Chromium took a request back (navigation, the page closed).
    func permissionDismissed(_ promptID: UInt64) {
        let ids = permissionRequests.filter { $0.value.request.promptID == promptID }.map(\.key)
        trace("[site-permission] chromium dismissed native=\(promptID) open=\(ids)")
        for id in ids {
            guard permissionRequests.removeValue(forKey: id) != nil else { continue }
            engine.dismissPermission(id)
        }
    }

    // MARK: Connection security

    /// The site controls' Secure / Insecure, from the visible entry's SSL status, as `ChromePage.reportSecurity`.
    func reportSecurity() {
        let status = contents.security
        guard let document = mainDocument.readyDocument, status.known else { return }
        let security = PageSecurity(document: document, secureConnection: status.secureConnection, certificateError: status.certificateError,
                                    insecureContent: status.insecureContent, insecureForm: status.insecureForm)
        guard security != reportedSecurity else { return }
        reportedSecurity = security
        trace("[site-security] page=\(id) secure=\(security.secure) tls=\(status.secureConnection) cert=0x\(String(status.certStatus, radix: 16)) content=0x\(String(status.contentStatus, radix: 16))")
        engine.pageDidEmit(self, .securityChanged(security))
    }

    func trace(_ line: @autoclosure () -> String) {
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil { print(line()) }
    }
}
