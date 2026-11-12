import BrkBase
import BrkEngine
import CefKit

/// CEF's side of find: CefBrowserHost's find and the renderer channel that runs FindEditorScript in each frame's main world.
@MainActor
final class CEFFindHost: FindHost {
    private unowned let browser: CefBrowser

    init(_ browser: CefBrowser) { self.browser = browser }

    func startFinding(_ text: String, forward: Bool, matchCase: Bool) {
        browser.find(text, forward: forward, matchCase: matchCase, findNext: true)
    }
    func stopFinding(clearSelection: Bool) { browser.stopFinding(clearSelection: clearSelection) }
    var findFrames: [FindFrame] { browser.frameDocuments.map(Self.frame) }
    func focusedFindFrame() -> FindFrame? { browser.focusedDocument().map(Self.frame) }
    func isCurrent(_ frame: FindFrame) -> Bool { browser.isCurrent(Self.native(frame)) }
    func sendEditor(to frame: FindFrame, request: String, payload: String) -> Bool {
        browser.sendRenderer(to: Self.native(frame), request: request, payload: payload)
    }

    private static func frame(_ document: CefBrowser.FrameDocument) -> FindFrame {
        FindFrame(frame: document.frame, document: document.document)
    }
    private static func native(_ frame: FindFrame) -> CefBrowser.FrameDocument {
        CefBrowser.FrameDocument(frame: frame.frame, document: frame.document)
    }
}

extension PageFind {
    convenience init(browser: CefBrowser, publish: @escaping (FindUpdate) -> Void) {
        self.init(host: CEFFindHost(browser), publish: publish)
    }

    func receive(_ message: CefRendererMessage) {
        receive(FindEditorMessage(frame: message.frame, document: message.document, kind: message.kind,
                                  request: message.request, payload: message.payload))
    }
}
