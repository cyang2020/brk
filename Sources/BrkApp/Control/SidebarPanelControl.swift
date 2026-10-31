import AppKit
import BrkBase
import BrkControl
import Foundation

@MainActor
enum SidebarPanelControl {
    struct Invalid: Error { let message: String }
    private static var testDirectory: URL?

    /// Remote panels consume the starting directory before presentation; no user preference is written.
    static func configureTestDirectory(_ panel: NSSavePanel) {
        guard let path = ProcessInfo.processInfo.environment["BRK_TEST_FILE_PANEL_DIRECTORY"],
              ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil else { return }
        panel.directoryURL = testDirectory ?? URL(fileURLWithPath: path)
    }

    static func run(_ action: SidebarPanelControlAction, in owner: NSWindow) async throws -> ControlResult {
        if case .directory(let path) = action {
            guard ProcessInfo.processInfo.environment["BRK_TEST_FILE_PANEL_DIRECTORY"] != nil else {
                throw Invalid(message: "Starting-directory configuration requires an owned panel test run")
            }
            testDirectory = URL(fileURLWithPath: path)
            (owner.attachedSheet as? NSSavePanel)?.directoryURL = testDirectory
            return .ok
        }
        let preview = owner.childWindows?.first { window in
            return window.isVisible && ViewTree.find("web-link-preview", in: window) != nil
        }
        guard let sheet = owner.attachedSheet ?? preview, let root = sheet.contentView else { throw Invalid(message: "No attached native sheet or link preview") }
        func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
        let views = walk(root) + ((sheet as? NSSavePanel)?.accessoryView.map(walk) ?? [])
        let events = EventInjector()
        func press(_ chord: String, in window: NSWindow) throws {
            guard let parsed = KeyChord(parsing: chord) else { throw Invalid(message: "Invalid native panel key") }
            try events.press(parsed, in: window)
        }
        switch action {
        case .directory:
            break // Handled before the attached-sheet check so tests can configure the next panel.
        case .selection:
            guard let panel = sheet as? NSSavePanel else { throw Invalid(message: "No native file panel") }
            let urls = (panel as? NSOpenPanel)?.urls ?? panel.url.map { [$0] } ?? []
            return .menuItems(urls.map { $0.resolvingSymlinksInPath().path })
        case .capture(let path):
            guard let image = WindowCapture.image(of: sheet),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw Invalid(message: "Native sheet capture unavailable")
            }
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
            return .screenshot(path: path, pixelWidth: image.width, pixelHeight: image.height)
        case .inspect:
            let panel = sheet as? NSSavePanel
            return .menuItems([sheet.title, panel?.prompt ?? "", String(describing: type(of: sheet))] + views.compactMap { view in
                if let popup = view as? NSPopUpButton { return "select:" + (popup.identifier?.rawValue ?? "") + ":" + String(popup.indexOfSelectedItem) }
                if let button = view as? NSButton { return "button:" + button.title }
                if let field = view as? NSTextField, !field.isEditable { return field.stringValue }
                return view.identifier.map { "view:" + $0.rawValue }
            })
        case .button(let title):
            if sheet is NSSavePanel, title == "Cancel" { try press("escape", in: sheet); return .ok }
            guard let button = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == title && $0.isEnabled }) else {
                throw Invalid(message: "Native button not found: " + title)
            }
            button.performClick(nil)
        case .focus(let identifier):
            guard let view = views.first(where: { $0.identifier?.rawValue == identifier || $0.accessibilityIdentifier() == identifier }), sheet.makeFirstResponder(view) else {
                throw Invalid(message: "Native control cannot take focus: " + identifier)
            }
        case .text(let identifier, let value):
            guard let field = views.first(where: { $0.identifier?.rawValue == identifier }) as? NSTextField, field.isEditable else {
                throw Invalid(message: "Native field not found")
            }
            field.stringValue = value
        case .select(let identifier, let index):
            guard let popup = views.first(where: { $0.identifier?.rawValue == identifier }) as? NSPopUpButton,
                  index >= 0, index < popup.numberOfItems else { throw Invalid(message: "Native menu not found") }
            popup.selectItem(at: index)
            if let action = popup.action { NSApp.sendAction(action, to: popup.target, from: popup) }
        case .save, .open:
            throw Invalid(message: "File selection requires the external AX driver and verified selection. Use explicit selected-file commands only when AX is unavailable.")
        }
        return .ok
    }
}
