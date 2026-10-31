import AppKit
import BrkDomain
import Foundation
import UniformTypeIdentifiers

/// Share-by-link, replaced by a file (user decision). The reducer built the `ExportDocument`; this asks where to
/// save it (JSON or Netscape bookmark HTML, by the chosen extension) and writes `ExportCodec`'s bytes. Nothing here
/// reads the tree or the state.
@MainActor
public enum ShareExport {
    public typealias Result = ExportOutcome
    /// Shows the save panel for the key window and writes the file. `write` is injectable for tests; the default
    /// writes atomically.
    public static func run(_ document: ExportDocument, in window: NSWindow?,
                           write: @escaping @MainActor (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
                           prepared: @escaping @MainActor (NSSavePanel) -> Void = { _ in },
                           completed: @escaping @MainActor (Result) -> Void = { _ in }) {
        guard let window, window.isVisible, window.attachedSheet == nil else {
            completed(.failed("The initiating window is unavailable or already has a dialog")); return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json, .html]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ExportCodec.filename(document, as: .json)
        panel.title = "Export"
        let finish: (NSApplication.ModalResponse) -> Void = { [weak window] response in
            panel.orderOut(nil)
            guard response == .OK, let url = panel.url else { completed(.cancelled); return }
            guard let window, window.isVisible else { completed(.failed("The initiating window closed")); return }
            let format: ExportFormat = url.pathExtension.lowercased() == "html" ? .html : .json
            do { try write(ExportCodec.encode(document, as: format), url); completed(.saved(url)) }
            catch {
                let message = error.localizedDescription
                completed(.failed(message))
                guard window.isVisible else { return }
                let alert = NSAlert()
                alert.messageText = "Export failed"
                alert.informativeText = message
                alert.beginSheetModal(for: window)
            }
        }
        prepared(panel)
        guard window.isVisible else { completed(.cancelled); return }
        panel.beginSheetModal(for: window, completionHandler: finish)
    }
}
