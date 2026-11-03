import AppKit
import BrkBase
import BrkLayout

/// A local AppKit sheet: no remote file-provider view participates in choosing a PNG destination.
@MainActor final class CaptureSheets {
    /// `listed`: the sheet belongs to a Library row and closes when that row goes; a menu card's Save… holds its
    /// pixels itself and closes only with its window.
    private struct Entry { let alert: NSAlert; let owner: NSWindow; let capture: String; var listed = true }
    private var entries: [WindowID: Entry] = [:]
    static func fileName(_ request: CaptureRequest) -> String {
        let host = request.url.host.map { $0.replacingOccurrences(of: ".", with: "-") } ?? "Capture"
        return "Screenshot-" + host + "-" + String(request.id.prefix(8)) + ".png"
    }
    func choose(name: String, capture: String, listed: Bool = true, in owner: NSWindow, id: WindowID, reply: @escaping @MainActor (URL?) -> Void) {
        guard owner.attachedSheet == nil, entries[id] == nil else { return }
        let alert = NSAlert()
        alert.messageText = listed ? "Export Capture" : "Save Capture"
        alert.informativeText = "Save a PNG copy. Enter the full file path."
        alert.addButton(withTitle:listed ? "Export" : "Save"); alert.addButton(withTitle:"Cancel")
        let folder = FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        let field = NSTextField(string:folder.appendingPathComponent(name).path)
        field.frame = CGRect(x:0,y:0,width:480,height:28)
        field.identifier = NSUserInterfaceItemIdentifier(ViewID.tabTool("capture-export-path").identifier)
        field.setAccessibilityIdentifier(ViewID.tabTool("capture-export-path").identifier)
        field.setAccessibilityLabel("PNG file path")
        alert.accessoryView = field; alert.window.initialFirstResponder = field
        entries[id] = Entry(alert:alert,owner:owner,capture:capture,listed:listed)
        alert.beginSheetModal(for:owner) { [weak self, weak owner] response in
            guard let self, let owner, self.entries[id]?.alert === alert else { return }
            self.entries[id] = nil
            guard response == .alertFirstButtonReturn, owner.isVisible else { reply(nil); return }
            let path = (field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines) as NSString).expandingTildeInPath
            guard path.hasPrefix("/"), path.utf8.count < 4096 else { self.error("Enter an absolute path to a PNG file.",in:owner,id:id,capture:capture); reply(nil); return }
            var url = URL(fileURLWithPath:path).standardizedFileURL
            if url.pathExtension.lowercased() != "png" { url.appendPathExtension("png") }
            guard FileManager.default.fileExists(atPath:url.path) else { reply(url); return }
            let replace = NSAlert(); replace.messageText = "Replace “\(url.lastPathComponent)”?"
            replace.informativeText = "The existing file will be replaced by this capture."
            replace.addButton(withTitle:"Replace"); replace.addButton(withTitle:"Cancel")
            self.entries[id] = Entry(alert:replace,owner:owner,capture:capture,listed:listed)
            replace.beginSheetModal(for:owner) { [weak self, weak owner] answer in
                guard let self, self.entries[id]?.alert === replace else { return }
                self.entries[id] = nil; reply(answer == .alertFirstButtonReturn && owner?.isVisible == true ? url : nil)
            }
        }
    }
    func open(_ record: CaptureRecord, png: Data, in owner: NSWindow, id: WindowID) throws {
        guard owner.attachedSheet == nil, entries[id] == nil else { return }
        guard let image = NSImage(data:png) else { throw CocoaError(.fileReadCorruptFile) }
        image.size = NSSize(width:Double(record.width)/record.scale,height:Double(record.height)/record.scale)
        let imageView = CaptureImageDocument(frame:CGRect(origin:.zero,size:image.size)); imageView.image = image; imageView.imageScaling = .scaleNone
        let scroll = NSScrollView(frame:CGRect(x:0,y:0,width:min(640,image.size.width),height:min(480,image.size.height)))
        scroll.documentView = imageView; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let alert = NSAlert(); alert.messageText = record.title
        alert.informativeText = "\(record.width) × \(record.height) PNG · \(record.url.host ?? "")"
        alert.accessoryView = scroll; alert.addButton(withTitle:"Close")
        entries[id] = Entry(alert:alert,owner:owner,capture:record.id)
        alert.beginSheetModal(for:owner) { [weak self] _ in if self?.entries[id]?.alert === alert { self?.entries[id] = nil } }
    }
    private func error(_ message: String, in window: NSWindow, id: WindowID, capture: String) {
        let alert = NSAlert(); alert.messageText = message
        entries[id] = Entry(alert:alert,owner:window,capture:capture)
        alert.beginSheetModal(for:window) { [weak self] _ in if self?.entries[id]?.alert === alert { self?.entries[id] = nil } }
    }
    func reconcile(_ windows: Set<WindowID>, captures: [WindowID: Set<String>] = [:]) {
        for id in Array(entries.keys) {
            guard let entry = entries[id] else { continue }
            if !windows.contains(id) || (entry.listed && captures[id]?.contains(entry.capture) != true) { cancel(id) }
        }
    }
    private func cancel(_ id: WindowID) {
        guard let entry = entries.removeValue(forKey:id) else { return }
        entry.owner.endSheet(entry.alert.window,returnCode:.alertSecondButtonReturn); entry.alert.window.orderOut(nil)
    }
    func cancelAll() { for id in Array(entries.keys) { cancel(id) } }
}

@MainActor private final class CaptureImageDocument: NSImageView { override var isFlipped: Bool { true } }
