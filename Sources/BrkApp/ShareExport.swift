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
    /// Selection returns to the owner; the same selected-file command handles native and explicit destinations.
    @discardableResult
    public static func run(_ document: ExportDocument, in window: NSWindow,
                           completion: @escaping @MainActor (URL?) -> Void) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json, .html]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ExportCodec.filename(document, as: .json)
        panel.title = "Export"
        SidebarPanelControl.configureTestDirectory(panel)
        panel.beginSheetModal(for: window) { response in
            let url = response == .OK ? panel.url : nil
            // Completion precedes AppKit's sheet detachment.
            DispatchQueue.main.async { completion(url) }
        }
        return panel
    }

    public static func writeSelected(_ document: ExportDocument, to url: URL,
                                     write: @MainActor (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) -> ExportOutcome {
        guard url.isFileURL else { return .failed("Export requires a selected local file.") }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let format: ExportFormat = url.pathExtension.lowercased() == "html" ? .html : .json
        do { try write(ExportCodec.encode(document, as: format), url); return .saved(url) }
        catch { return .failed(error.localizedDescription) }
    }
}
