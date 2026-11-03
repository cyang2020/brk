import BrkBase
import CefKit
import Foundation

extension ChromePage {
    func applyBoostPolicy(_ policy: BoostPolicy) {
        guard boostPolicy != policy else { return }
        boostPolicy = policy
        refreshBoosts()
    }

    func boostTarget() -> SiteTarget? {
        // Committed documents count (review F1/16): a page whose load event is late or never comes still gets its Boosts.
        let document: DocumentToken
        switch mainDocument.availability { case .ready(let value), .loading(let value): document = value; case .unavailable: return nil }
        guard engine.isLive(self), let origin = browser.url.flatMap(SiteOrigin.init) else { return nil }
        return SiteTarget(document: document, context: context, origin: origin)
    }

    /// `revision` nil: the caller does not care whether the injected CSS changes meanwhile (the Zap picker).
    func boostWorld(_ target: SiteTarget, revision: UInt64?) async throws -> Int {
        @MainActor func valid() -> Bool { engine.isLive(self) && matches(target) && (revision.map { boostRevision == $0 } ?? true) }
        guard valid() else { throw CocoaError(.userCancelled) }
        let frameTree = try await browser.protocolSession.call("Page.getFrameTree")
        guard valid(), let tree = frameTree["frameTree"] as? [String: Any], let frame = tree["frame"] as? [String: Any],
              let frameID = frame["id"] as? String else { throw CocoaError(.userCancelled) }
        let world = try await browser.protocolSession.call("Page.createIsolatedWorld", ["frameId": frameID, "worldName": "brk-boosts"])
        guard valid(), let id = world["executionContextId"] as? Int else { throw CocoaError(.userCancelled) }
        return id
    }

    func refreshBoosts() {
        boostRevision &+= 1
        let revision = boostRevision
        guard let target = boostTarget() else { return }
        if boostDocument != target.document {
            boostDocument = target.document; boostExecuted = []; boostOwner = UUID().uuidString
        }
        let privateContext = if case .incognito = context { true } else { false }
        let injections = boostPolicy.boosts.filter { $0.scope.matches(target.origin.url) && (!privateContext || $0.allowPrivate) }
        let owner = boostOwner
        Task { @MainActor [weak self] in
            guard let self else { return }
            @MainActor func valid() -> Bool { self.engine.isLive(self) && self.matches(target) && self.boostRevision == revision }
            do {
                let world = try await self.boostWorld(target, revision: revision)
                guard valid() else { return }
                let css = injections.map { $0.css }.joined(separator: "\n")
                let script = """
                (()=>{if(location.origin!==\(Self.jsString(target.origin.value)))return false;
                const owner=\(Self.jsString(owner));for(const old of document.querySelectorAll('style[data-brk-boost-owner]'))if(old.getAttribute('data-brk-boost-owner')!==owner)old.remove();
                let s=document.querySelector('style[data-brk-boost-owner="'+owner+'"]');
                if(!s){s=document.createElement('style');s.setAttribute('data-brk-boost-owner',owner);(document.head||document.documentElement).append(s);}
                s.textContent=\(Self.jsString(css));if(!s.textContent)s.remove();return true;})()
                """
                _ = try await self.browser.protocolSession.call("Runtime.evaluate", ["expression": script, "contextId": world, "returnByValue": true])
                guard valid() else { return }
                for boost in injections where !boost.javascript.isEmpty {
                    let key = boost.id + "\n" + boost.scope.label + "\n" + boost.javascript
                    guard !self.boostExecuted.contains(key) else { continue }
                    // Reserve before awaiting so an incidental reconcile cannot execute the same program twice.
                    self.boostExecuted.insert(key)
                    let expression = """
                    (()=>{if(location.origin!==\(Self.jsString(target.origin.value)))return 'ok';
                    globalThis.__brkBoostRan=globalThis.__brkBoostRan||new Set();const key=\(Self.jsString(key));if(globalThis.__brkBoostRan.has(key))return 'ok';globalThis.__brkBoostRan.add(key);
                    try{(new Function(\(Self.jsString(boost.javascript))))();return 'ok';}catch(e){return 'Boost JavaScript: '+String(e);}})()
                    """
                    let result = try await self.browser.protocolSession.call("Runtime.evaluate", ["expression": expression, "contextId": world, "returnByValue": true])
                    guard valid() else { return }
                    if let value = (result["result"] as? [String: Any])?["value"] as? String, value != "ok" { self.boostError = value; self.engine.pageDidEmit(self, .boostFailed(target.document, value)) }
                }
            } catch {
                guard valid() else { return }
                self.boostError = error.localizedDescription
                self.engine.pageDidEmit(self, .boostFailed(target.document, error.localizedDescription))
            }
        }
    }

    func pickBoostElement(_ target: SiteTarget) async throws -> String? {
        guard matches(target), engine.isLive(self), case .profile = context else { throw CocoaError(.userCancelled) }
        boostPickerGeneration &+= 1
        let picker = boostPickerGeneration
        // Zap's own CSS changes the Boost policy between picks; the picker only needs the same document.
        let world = try await boostWorld(target, revision: nil)
        guard matches(target), engine.isLive(self), picker == boostPickerGeneration else { throw CocoaError(.userCancelled) }
        let pickToken = UUID().uuidString
        boostPickerWorld = (target, world, pickToken)
        defer { if boostPickerWorld?.token == pickToken { boostPickerWorld = nil } }
        // Arc's Zap: the element under the pointer turns into a yellow block (P37-c2); a click hides it. Clicks on the
        // page background are ignored, Escape ends picking (null). The native side cancels a pick it no longer wants.
        let script = """
        new Promise(resolve=>{
          if(location.origin!==\(Self.jsString(target.origin.value))){resolve(null);return;}
          if(globalThis.__brkZapCancel)globalThis.__brkZapCancel();
          let current=null;const highlight=document.createElement('div');highlight.setAttribute('data-brk-zap-highlight','');highlight.style.cssText='position:fixed;pointer-events:none;z-index:2147483647;background:#ffcc02;mix-blend-mode:multiply;border-radius:4px;box-sizing:border-box;display:none';document.documentElement.append(highlight);
          const place=()=>{if(!current||!current.isConnected){highlight.style.display='none';return;}const r=current.getBoundingClientRect();Object.assign(highlight.style,{display:'block',left:(r.left-2)+'px',top:(r.top-2)+'px',width:(r.width+4)+'px',height:(r.height+4)+'px'});};
          const ignored=t=>!t||t===document.documentElement||t===document.body||t===highlight;
          const finish=value=>{highlight.remove();for(const [n,f] of listeners)window.removeEventListener(n,f,true);if(globalThis.__brkZapToken===\(Self.jsString(pickToken))){delete globalThis.__brkZapCancel;delete globalThis.__brkZapToken;}resolve(value);};
          const over=e=>{const t=e.target instanceof Element?e.target:null;current=ignored(t)?null:t;place();};
          const selector=el=>{const parts=[];while(el&&el.nodeType===1){
            if(el.id){const id='#'+CSS.escape(el.id);if(document.querySelectorAll(id).length===1){parts.unshift(id);break;}}
            const tag=el.localName;const siblings=el.parentElement?Array.from(el.parentElement.children).filter(x=>x.localName===tag):[el];
            parts.unshift(CSS.escape(tag)+':nth-of-type('+(siblings.indexOf(el)+1)+')');el=el.parentElement;
          }return parts.join(' > ');};
          const swallow=e=>{if(!e.isTrusted)return;e.preventDefault();e.stopImmediatePropagation();};
          const click=e=>{if(!e.isTrusted)return;e.preventDefault();e.stopImmediatePropagation();const t=e.target instanceof Element?e.target:null;if(ignored(t))return;finish(selector(t));};
          const key=e=>{if(e.key==='Escape'){e.preventDefault();e.stopImmediatePropagation();finish(null);}};
          const listeners=[['mouseover',over],['scroll',place],['resize',place],['mousedown',swallow],['mouseup',swallow],['pointerdown',swallow],['auxclick',swallow],['click',click],['keydown',key]];
          globalThis.__brkZapToken=\(Self.jsString(pickToken));globalThis.__brkZapCancel=()=>finish(null);
          for(const [n,f] of listeners)window.addEventListener(n,f,true);
        })
        """
        let result = try await browser.protocolSession.call("Runtime.evaluate", ["expression": script, "contextId": world, "returnByValue": true, "awaitPromise": true], timeout: 3600)
        guard matches(target), engine.isLive(self) else { throw CocoaError(.userCancelled) }
        return (result["result"] as? [String: Any])?["value"] as? String
    }
}

extension CEFEngine {
    public func cancelBoostPick(_ target: SiteTarget) {
        guard let page = live[target.page] else { return }
        page.boostPickerGeneration &+= 1
        guard let world = page.boostPickerWorld, world.target == target, page.matches(target) else { return }
        Task { @MainActor in
            guard page.matches(target), self.isLive(page) else { return }
            _ = try? await page.browser.protocolSession.call("Runtime.evaluate", ["expression": "if(globalThis.__brkZapToken===\(ChromePage.jsString(world.token)))globalThis.__brkZapCancel?.()", "contextId": world.id])
        }
    }
    public func pickBoostElement(_ target: SiteTarget) async throws -> String? {
        guard let page = live[target.page], page.matches(target) else { throw CocoaError(.userCancelled) }
        return try await page.pickBoostElement(target)
    }
}
