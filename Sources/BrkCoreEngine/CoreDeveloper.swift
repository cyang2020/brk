import AppKit
import BrkBase
import Foundation

extension CorePage {
    func developer(_ operation: DeveloperOperation) {
        guard engine.isLive(self) else { return }
        guard operation == .source else { contents.developerOperation(operation.rawValue); return }
        guard let document = readyDocument else { return }
        sourceRequest &+= 1
        let request = sourceRequest
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let session = CoreProtocolSession(contents: contents)
                let tree = try await session.call("DOM.getDocument", ["depth": 0])
                guard let node = (tree["root"] as? [String: Any])?["nodeId"] as? Int else { return }
                let result = try await session.call("DOM.getOuterHTML", ["nodeId": node])
                guard let text = result["outerHTML"] as? String, engine.isLive(self),
                      readyDocument == document, sourceRequest == request else { return }
                let window = sourceWindow ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                    styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.title = "Source — " + (contents.committedURL?.absoluteString ?? "Page")
                let scroll = NSScrollView(frame: window.contentView?.bounds ?? .zero)
                scroll.autoresizingMask = [.width, .height]
                scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
                let editor = NSTextView(frame: scroll.bounds)
                editor.isEditable = false; editor.isRichText = false
                editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
                editor.string = text; editor.autoresizingMask = [.width]
                scroll.documentView = editor; window.contentView = scroll
                if sourceWindow == nil { window.center() }
                sourceWindow = window
                window.makeKeyAndOrderFront(nil)
                developerResult = "Source displayed: \(text.utf8.count) bytes"
            } catch {
                if engine.isLive(self), readyDocument == document, sourceRequest == request {
                    developerResult = "Could not read page source: \(error.localizedDescription)"
                }
            }
        }
    }
}
