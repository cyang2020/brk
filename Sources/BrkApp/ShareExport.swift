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
                           isValid: @escaping @MainActor () -> Bool = { true },
                           completion: @escaping @MainActor (ExportFileResult) -> Void = { _ in }) -> NSSavePanel? {
        guard let window, window.isVisible, window.attachedSheet == nil else { completion(.failed("Finish the open sheet first.")); return nil }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json, .html]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ExportCodec.filename(document, as: .json)
        panel.title = "Export"
        var completed = false
        let finish: @MainActor (NSApplication.ModalResponse) -> Void = { [weak window] response in
            guard !completed else { return }; completed = true
            guard response == .OK, isValid(), window?.isVisible == true, let url = panel.url else { completion(.cancelled); return }
            let format: ExportFormat = url.pathExtension.lowercased() == "html" ? .html : .json
            do { try write(ExportCodec.encode(document, as: format), url); completion(.saved(url)) }
            catch { completion(.failed(error.localizedDescription)) }
        }
        panel.beginSheetModal(for: window, completionHandler: finish)
        return panel
    }
}

public enum ExportFileResult: Sendable {
    case saved(URL)
    case cancelled
    case failed(String)
}
