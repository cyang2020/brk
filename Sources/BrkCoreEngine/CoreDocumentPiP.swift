import BrkBase
import Foundation

extension CorePage {
    func controlDocumentPiP(_ control: DocumentPiPControl) {
        guard engine.isLive(self), control.document == readyDocument else { return }
        documentPiPTask?.cancel()
        documentPiPTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let session = CoreProtocolSession(contents: contents)
            do {
                if !control.enter {
                    if let world = documentPiPWorld, world.document == control.document {
                        _ = try await session.call("Runtime.evaluate", ["expression": "globalThis.__brkPiP?.close()", "contextId": world.context])
                    }
                    setDocumentPiP(false, document: control.document)
                    return
                }
                let tree = try await session.call("Page.getFrameTree")
                guard let frame = (tree["frameTree"] as? [String: Any])?["frame"] as? [String: Any], let frameID = frame["id"] as? String else { return }
                let world = try await session.call("Page.createIsolatedWorld", ["frameId": frameID, "worldName": "brk-document-pip"])
                guard let context = world["executionContextId"] as? Int, readyDocument == control.document, !Task.isCancelled else { return }
                documentPiPWorld = (control.document, context)
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
                let result = try await session.call("Runtime.evaluate", ["expression": script, "contextId": context,
                    "awaitPromise": true, "returnByValue": true, "userGesture": control.userInitiated])
                guard result["exceptionDetails"] == nil, (result["result"] as? [String: Any])?["value"] as? Bool == true else {
                    throw CoreProtocolError(message: "The page could not enter picture in picture")
                }
                guard !Task.isCancelled, readyDocument == control.document, engine.isLive(self) else { return }
                setDocumentPiP(true, document: control.document)
                while !Task.isCancelled, readyDocument == control.document, engine.isLive(self) {
                    try await Task.sleep(for: .milliseconds(250))
                    let state = try await session.call("Runtime.evaluate", ["expression": "!!globalThis.__brkPiP && !globalThis.__brkPiP.closed", "contextId": context, "returnByValue": true])
                    if (state["result"] as? [String: Any])?["value"] as? Bool != true {
                        setDocumentPiP(false, document: control.document)
                        return
                    }
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, readyDocument == control.document, engine.isLive(self) else { return }
                setDocumentPiP(false, document: control.document, error: error.localizedDescription)
            }
        }
    }

    private func setDocumentPiP(_ active: Bool, document: DocumentToken, error: String? = nil) {
        guard readyDocument == document, engine.isLive(self) else { return }
        pictureInPictureDocument = active ? document : nil
        if !active { documentPiPWorld = nil }
        engine.pageDidEmit(self, .documentPictureInPictureChanged(document, active, error: error))
        refreshWebsitePolicy()
    }
}
