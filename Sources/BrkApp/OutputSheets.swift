import AppKit
import BrkBase
import BrkEngine
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Native resources only. Each entry is bound to its initiating window; it never falls back to the key window.
@MainActor final class OutputSheets {
    @MainActor private final class Entry: NSObject {
        let request: OutputRequest
        weak var window: NSWindow?
        var panel: NSSavePanel?
        var printOperation: NSPrintOperation?
        var printPanel: NSPrintPanel?
        var reply: (@MainActor (DestinationAnswer) -> Void)?
        var printReply: (@MainActor (PrintAnswer) -> Void)?
        var retry: Timer?
        var start: (() -> Void)?
        init(_ request: OutputRequest, window: NSWindow) { self.request = request; self.window = window }
        @objc func printed(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
            let reply = printReply; printReply = nil; printOperation = nil; printPanel = nil
            reply?(success ? .submitted : .failed("The print system rejected the job"))
        }
    }
    private var entries: [OutputID: Entry] = [:]
    /// Opt-in control socket supplies an owned fixture destination before a real panel begins.
    var fixtureDestinations: [WindowID: URL] = [:]
    var chosenFixtures: [WindowID: URL] = [:]

    func destination(_ prompt: OutputDestinationPrompt, in window: NSWindow?, reply: @escaping @MainActor (DestinationAnswer) -> Void) {
        guard let window, window.isStillOpen else { reply(.ownerGone); return }
        if let fixture = chosenFixtures.removeValue(forKey: prompt.request.document.browser.page.window) {
            reply(.accepted(fixture)); return
        }
        let entry = Entry(prompt.request, window: window)
        entry.reply = reply
        entries[entry.request.id] = entry
        entry.start = { [weak self, weak entry] in
            guard let self, let entry, self.entries[entry.request.id] === entry, let owner = entry.window else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = entry.request.intent == .pdf ? [.pdf] : [UTType(filenameExtension: "mhtml") ?? .data]
            panel.canCreateDirectories = true
            let name = entry.request.suggestedName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            panel.nameFieldStringValue = String(name.prefix(100)) + (entry.request.intent == .pdf ? ".pdf" : ".mhtml")
            if let fixture = self.fixtureDestinations.removeValue(forKey: entry.request.document.browser.page.window) {
                panel.directoryURL = fixture.deletingLastPathComponent()
                panel.nameFieldStringValue = fixture.lastPathComponent
            }
            panel.title = entry.request.intent == .pdf ? "Export PDF" : "Save Offline Page"
            entry.panel = panel
            panel.beginSheetModal(for: owner) { [weak self, weak entry] response in
                guard let self, let entry, self.entries[entry.request.id] === entry else { return }
                self.entries[entry.request.id] = nil
                entry.panel = nil
                let reply = entry.reply; entry.reply = nil
                reply?(response == .OK ? panel.url.map(DestinationAnswer.accepted) ?? .cancelled : .cancelled)
            }
        }
        schedule(entry)
    }

    func print(_ request: OutputRequest, pdf: URL, in window: NSWindow?, reply: @escaping @MainActor (PrintAnswer) -> Void) {
        guard let window, window.isStillOpen else { reply(.ownerGone); return }
        let entry = Entry(request, window: window)
        entry.printReply = { [weak self, weak entry] answer in
            guard let self, let entry else { return }; self.entries[entry.request.id] = nil; reply(answer)
        }
        entries[request.id] = entry
        entry.start = { [weak self, weak entry] in
            guard let self, let entry, self.entries[request.id] === entry, let owner = entry.window else { return }
            guard let document = PDFDocument(url: pdf),
                  let operation = document.printOperation(for: NSPrintInfo(dictionary: [:]), scalingMode: .pageScaleToFit, autoRotate: true) else {
                let reply = entry.printReply; entry.printReply = nil; reply?(.failed("Could not prepare PDF for printing")); return
            }
            entry.printOperation = operation
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            let panel = operation.printPanel
            panel.options = [.showsCopies, .showsPageRange, .showsPaperSize, .showsOrientation, .showsScaling]
            entry.printPanel = panel
            panel.beginSheet(using: operation.printInfo, on: owner) { [weak entry, weak owner] result in
                guard let entry else { return }
                entry.printPanel = nil
                guard result == .printed, let owner, owner.isVisible else {
                    entry.printOperation = nil
                    let reply = entry.printReply; entry.printReply = nil
                    reply?(result == .cancelled ? .cancelled : .ownerGone)
                    return
                }
                operation.runModal(for: owner, delegate: entry, didRun: #selector(Entry.printed(_:success:contextInfo:)), contextInfo: nil)
            }
        }
        schedule(entry)
    }

    /// Download and output sheets share AppKit's actual attached-sheet barrier. Work remains asynchronous.
    private func schedule(_ entry: Entry) {
        guard entries[entry.request.id] === entry else { return }
        guard let window = entry.window, window.isStillOpen else { ownerGone(entry.request.document.browser.page.window); return }
        // A minimized window, or one of a hidden app, gets its panel once it is back on screen.
        if window.attachedSheet != nil || !window.isVisible {
            entry.retry = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self, weak entry] _ in
                MainActor.assumeIsolated { guard let self, let entry else { return }; self.schedule(entry) }
            }
            return
        }
        entry.retry?.invalidate(); entry.retry = nil
        let start = entry.start; entry.start = nil
        start?()
    }

    /// Takes the entry's sheet away. A destination still asked for is answered `.ownerGone`, never dropped: the output
    /// waits for that answer with no time limit (only rendering is timed), and DocumentOutputs ignores a late one.
    func dismiss(_ id: OutputID) {
        guard let entry = entries[id] else { return }
        entry.retry?.invalidate(); entry.retry = nil; entry.start = nil
        let reply = entry.reply; entry.reply = nil
        defer { reply?(.ownerGone) }
        if let panel = entry.panel {
            entries[id] = nil; entry.panel = nil
            panel.cancel(nil)
            panel.sheetParent?.endSheet(panel, returnCode: .cancel)
            panel.orderOut(nil)
        } else if entry.printOperation != nil {
            // Keep the PDF and delegate until NSPrintOperation answers. Ending the sheet alone is not completion.
            if let sheet = entry.window?.attachedSheet {
                if let button = Self.button("Cancel", in: sheet.contentView) { button.performClick(nil) }
                else { entry.window?.endSheet(sheet, returnCode: .cancel) }
            }
        } else {
            entries[id] = nil
            let printReply = entry.printReply; entry.printReply = nil
            printReply?(.ownerGone)
        }
    }

    static func button(_ title: String, in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.title == title { return button }
        return view.subviews.lazy.compactMap { button(title, in: $0) }.first
    }

    func ownerGone(_ window: WindowID) {
        fixtureDestinations[window] = nil; chosenFixtures[window] = nil
        for entry in Array(entries.values) where entry.request.document.browser.page.window == window { dismiss(entry.request.id) }
    }
}
