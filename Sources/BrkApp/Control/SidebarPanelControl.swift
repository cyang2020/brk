import AppKit
import BrkBase
import BrkControl
import Foundation

@MainActor
enum SidebarPanelControl {
    struct Invalid: Error { let message: String }
    static func run(_ action: SidebarPanelControlAction, in owner: NSWindow) async throws -> ControlResult {
        guard let sheet = owner.attachedSheet, let root = sheet.contentView else { throw Invalid(message: "No attached native sheet") }
        func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
        let views = walk(root) + ((sheet as? NSSavePanel)?.accessoryView.map(walk) ?? [])
        let events = EventInjector()
        func press(_ chord: String, in window: NSWindow) throws {
            guard let parsed = KeyChord(parsing: chord) else { throw Invalid(message: "Invalid native panel key") }
            try events.press(parsed, in: window)
        }
        func goTo(_ path: String, in panel: NSWindow) async throws {
            try press("cmd+shift+g", in: panel)
            try await Task.sleep(for: .milliseconds(300))
            let destination = panel.attachedSheet ?? panel
            try press("cmd+a", in: destination)
            try events.type(path, in: destination)
            try press("return", in: destination)
            try await Task.sleep(for: .milliseconds(400))
        }
        switch action {
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
                if let button = view as? NSButton { return "button:" + button.title }
                if let field = view as? NSTextField, !field.isEditable { return field.stringValue }
                if let popup = view as? NSPopUpButton { return "select:" + (popup.identifier?.rawValue ?? "") }
                return view.identifier.map { "view:" + $0.rawValue }
            })
        case .button(let title):
            if sheet is NSSavePanel, title == "Cancel" { try press("escape", in: sheet); return .ok }
            guard let button = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == title && $0.isEnabled }) else {
                throw Invalid(message: "Native button not found: " + title)
            }
            button.performClick(nil)
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
        case .save(let directory, let filename):
            guard let panel = sheet as? NSSavePanel, !(panel is NSOpenPanel) else { throw Invalid(message: "No native save panel") }
            NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(250))
            try press("cmd+a", in: panel)
            try events.type(filename, in: panel)
            try await goTo(directory, in: panel)
            try press("return", in: panel)
        case .open(let path):
            guard let panel = sheet as? NSOpenPanel else { throw Invalid(message: "No native open panel") }
            NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
            try await goTo(path, in: panel)
            try press("return", in: panel)
        }
        return .ok
    }
}
