import AppKit
import BrkControl
import Foundation

@MainActor
enum SidebarPanelControl {
    struct Invalid: Error { let message: String }
    static func run(_ action: SidebarPanelControlAction, in owner: NSWindow) throws -> ControlResult {
        guard let sheet = owner.attachedSheet, let root = sheet.contentView else { throw Invalid(message: "No attached native sheet") }
        func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
        let views = walk(root)
        switch action {
        case .inspect:
            return .menuItems([sheet.title] + views.compactMap { view in
                if let button = view as? NSButton { return "button:" + button.title }
                if let field = view as? NSTextField, !field.isEditable { return field.stringValue }
                if let popup = view as? NSPopUpButton { return "select:" + (popup.identifier?.rawValue ?? "") }
                return view.identifier.map { "view:" + $0.rawValue }
            })
        case .button(let title):
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
            panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
            panel.nameFieldStringValue = filename
            panel.validateVisibleColumns()
            panel.ok(nil)
        case .open(let path):
            guard let panel = sheet as? NSOpenPanel else { throw Invalid(message: "No native open panel") }
            let url = URL(fileURLWithPath: path)
            panel.directoryURL = panel.canChooseDirectories ? url : url.deletingLastPathComponent()
            if panel.canChooseFiles { panel.nameFieldStringValue = url.lastPathComponent }
            panel.validateVisibleColumns()
            panel.ok(nil)
        }
        return .ok
    }
}
