import AppKit
import BrkDomain
import Foundation
import UniformTypeIdentifiers

/// Share-by-link, replaced by a file (user decision). The reducer built the `ExportDocument`; this asks where to
/// save it (JSON or Netscape bookmark HTML, by the chosen extension) and writes `ExportCodec`'s bytes. Nothing here
/// reads the tree or the state.
@MainActor
public enum ShareExport {
    /// Shows the save panel for the key window and writes the file. `write` is injectable for tests; the default
    /// writes atomically.
    @discardableResult
    public static func run(_ document: ExportDocument, in window: NSWindow?,
                           write: @escaping @MainActor (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
                           completion: @escaping @MainActor (String) -> Void = { _ in }) -> NSSavePanel? {
        guard let window, window.isVisible, window.attachedSheet == nil else { completion("Export unavailable: finish the open sheet first."); return nil }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json, .html]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ExportCodec.filename(document, as: .json)
        panel.title = "Export"
        let finish: (NSApplication.ModalResponse) -> Void = { [weak window] response in
            guard response == .OK else { completion("Export cancelled. No file written."); return }
            guard window?.isVisible == true, let url = panel.url else { completion("Export cancelled because its window closed."); return }
            let format: ExportFormat = url.pathExtension.lowercased() == "html" ? .html : .json
            do { try write(ExportCodec.encode(document, as: format), url); completion("Exported \(url.lastPathComponent).") }
            catch {
                completion("Export failed: \(error.localizedDescription)")
                if let window {
                    let alert = NSAlert(); alert.messageText = "Export failed"; alert.informativeText = error.localizedDescription
                    alert.beginSheetModal(for: window)
                }
            }
        }
        panel.beginSheetModal(for: window, completionHandler: finish)
        return panel
    }
}
