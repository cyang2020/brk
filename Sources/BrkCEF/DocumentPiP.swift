import BrkBase
import CefKit
import Foundation

@MainActor final class DocumentPiPHost: CefBrowserDelegate {
    let browser: CefBrowser
    let source: DocumentToken
    unowned let engine: CEFEngine
    init(browser: CefBrowser, source: DocumentToken, engine: CEFEngine) { self.browser = browser; self.source = source; self.engine = engine; browser.delegate = self }
    func browserDidClose(_ b: CefBrowser) {
        engine.pictureInPictureWindows[b.id] = nil
        guard let page = engine.live[source.browser.page], page.readyDocument == source else { return }
        engine.pageDidEmit(page, .documentPictureInPictureChanged(source, false, error: nil))
    }
    func browser(_ b: CefBrowser, decideWindowOpenFor request: CefWindowOpenRequest) -> CefWindowOpenAction { .deny }
    func browser(_ b: CefBrowser, didRequestNewTab url: URL?) -> Bool { true }
}

extension ChromePage {
    func browser(_ b: CefBrowser, didCreateNativePopup popup: CefBrowser) {
        guard engine.isLive(self), let document = readyDocument else { popup.close(force: true); return }
        let host = DocumentPiPHost(browser: popup, source: document, engine: engine)
        engine.pictureInPictureWindows[popup.id] = host
    }
    func closeDocumentPiP() {
        for host in Array(engine.pictureInPictureWindows.values) where host.source.browser == incarnation { host.browser.close(force: true) }
    }
    func controlDocumentPiP(_ control: DocumentPiPControl) {
        guard control.document == readyDocument, engine.isLive(self) else { return }
        if !control.enter { closeDocumentPiP(); return }
        Task { @MainActor [weak self] in
            guard let self, self.readyDocument == control.document, self.engine.isLive(self) else { return }
            do {
                let session = self.browser.protocolSession
                let tree = try await session.call("Page.getFrameTree")
                guard let frameTree = tree["frameTree"] as? [String: Any], let frame = frameTree["frame"] as? [String: Any], let frameID = frame["id"] as? String else { return }
                let world = try await session.call("Page.createIsolatedWorld", ["frameId":frameID,"worldName":"brk-document-pip"])
                guard let contextID = world["executionContextId"] as? Int, self.readyDocument == control.document, self.engine.isLive(self) else { return }
                let script = """
                (async()=>{
                  if (globalThis.__brkPiP && !globalThis.__brkPiP.closed) return true;
                  if (typeof documentPictureInPicture==='undefined') throw Error('Document picture in picture is unavailable');
                  const w=await documentPictureInPicture.requestWindow({width:480,height:360});
                  globalThis.__brkPiP=w;
                  for (const sheet of document.styleSheets) { try { const style=w.document.createElement('style');style.textContent=Array.from(sheet.cssRules,r=>r.cssText).join('\\n');w.document.head.append(style); } catch { if(sheet.href){const link=w.document.createElement('link');link.rel='stylesheet';link.href=sheet.href;w.document.head.append(link);} } }
                  const nodes=Array.from(document.body.children).filter(n=>!['SCRIPT','STYLE','LINK'].includes(n.tagName));
                  const saved=nodes.map(node=>{const marker=document.createComment('Brk PiP');node.before(marker);w.document.body.append(node);return {node,marker};});
                  w.addEventListener('pagehide',()=>{for(const {node,marker} of saved){if(marker.isConnected)marker.replaceWith(node);}globalThis.__brkPiP=null;},{once:true});
                  return !w.closed;
                })()
                """
                let result = try await session.call("Runtime.evaluate", ["expression":script,"contextId":contextID,"awaitPromise":true,"returnByValue":true,"userGesture":control.userInitiated])
                guard self.readyDocument == control.document, self.engine.isLive(self) else { self.closeDocumentPiP(); return }
                guard result["exceptionDetails"] == nil, (result["result"] as? [String: Any])?["value"] as? Bool == true else { throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey:String(describing:result)]) }
                self.engine.pageDidEmit(self, .documentPictureInPictureChanged(control.document, true, error: nil))
            } catch {
                guard self.readyDocument == control.document, self.engine.isLive(self) else { return }
                self.engine.pageDidEmit(self, .documentPictureInPictureChanged(control.document, false, error: error.localizedDescription))
            }
        }
    }
}
