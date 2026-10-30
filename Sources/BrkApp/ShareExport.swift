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
    public static func run(_ document: ExportDocument, in window: NSWindow?,
                           write: @escaping @MainActor (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json, .html]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ExportCodec.filename(document, as: .json)
        panel.title = "Export"
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            let format: ExportFormat = url.pathExtension.lowercased() == "html" ? .html : .json
            try? write(ExportCodec.encode(document, as: format), url)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: finish) } else { finish(panel.runModal()) }
    }
}
