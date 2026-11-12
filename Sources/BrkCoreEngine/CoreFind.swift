import BrkBase
import BrkEngine
import CBrkCore
import Foundation
import PageEditorScript

/// BrkCore's side of find: Chrome's FindTabHelper, and FindEditorScript in Chrome's isolated world of each frame. The script's function
/// lives on that world's global for the document, where the page's own scripts cannot reach it, as CEF keeps it in renderer memory.
@MainActor
final class CoreFindHost: FindHost {
    private weak var contents: (any BrkCoreWebContents)?
    /// Where the editor's answers go (PageFind.receive), as CEF's renderer channel delivers them.
    var receive: ((FindEditorMessage) -> Void)?

    init(_ contents: any BrkCoreWebContents) { self.contents = contents }

    func startFinding(_ text: String, forward: Bool, matchCase: Bool) {
        contents?.findText(text, forward: forward, matchCase: matchCase)
    }
    func stopFinding(clearSelection: Bool) { contents?.stopFindingClearingSelection(clearSelection) }
    var findFrames: [FindFrame] { (contents?.frameDocuments ?? [:]).map { FindFrame(frame: $0.key, document: $0.value) } }
    func focusedFindFrame() -> FindFrame? {
        guard let contents, let frame = contents.focusedFrame, let document = contents.frameDocuments[frame] else { return nil }
        return FindFrame(frame: frame, document: document)
    }
    func isCurrent(_ frame: FindFrame) -> Bool { contents?.frameDocuments[frame.frame] == frame.document }

    func sendEditor(to frame: FindFrame, request: String, payload: String) -> Bool {
        guard let contents, isCurrent(frame) else { return false }
        contents.evaluateIsolatedScript(Self.call(payload), inFrame: frame.frame, document: frame.document) { [weak self] json in
            // As CEF's renderer: no value (the document went, or the script threw) answers "unconfirmed". Always on a later turn, so the
            // caller has recorded the request before its answer arrives.
            let answer = json.flatMap(Self.string) ?? #"{"status":"unconfirmed"}"#
            DispatchQueue.main.async {
                self?.receive?(FindEditorMessage(frame: frame.frame, document: frame.document, kind: "result", request: request, payload: answer))
            }
        }
        return true
    }

    /// The frames changed: PageFind rechecks every pending request and selection against the frames now, as after CEF's "released".
    func framesChanged() {
        receive?(FindEditorMessage(frame: "", document: "", kind: "released", request: "", payload: ""))
    }

    /// The first call in a document makes the editor (its listeners start then); later calls reuse it.
    static func call(_ payload: String) -> String {
        let quoted = (try? JSONSerialization.data(withJSONObject: payload, options: .fragmentsAllowed)) ?? Data("\"\"".utf8)
        let argument = String(decoding: quoted, as: UTF8.self)
        return "(globalThis.__brkFindEditor ??= \(FindEditorScript.source))(\(argument))"
    }

    /// The editor answers JSON text; the engine hands back the value as JSON, so a string arrives quoted.
    private static func string(_ json: String) -> String? {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)) as? String
    }
}
