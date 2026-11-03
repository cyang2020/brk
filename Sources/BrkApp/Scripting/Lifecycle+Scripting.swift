import AppKit
import BrkBase
import BrkDomain
import Foundation

/// The application object's elements in Brk.sdef. Cocoa scripting asks the delegate for the keys it claims, so
/// NSApplication's own `orderedWindows` (which would list the settings and About windows too) stays out of it.
extension Lifecycle {
    public func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        ["scriptWindows", "scriptTabs"].contains(key)
    }

    /// `windows`: the browser windows, front to back.
    @objc var scriptWindows: [ScriptWindow] {
        guard let store else { return [] }
        return Scripting.orderedWindows(store).map { ScriptWindow($0) }
    }

    @objc func valueInScriptWindowsWithUniqueID(_ uniqueID: String) -> ScriptWindow? {
        guard store?.snapshot.windows[WindowID(uniqueID)] != nil else { return nil }
        return ScriptWindow(WindowID(uniqueID))
    }

    /// `make new window [with properties {mode: "incognito"}]`.
    @objc func insertInScriptWindows(_ window: ScriptWindow) { window.create() }
    @objc(insertInScriptWindows:atIndex:) func insertInScriptWindows(_ window: ScriptWindow, at index: Int) { window.create() }

    /// `tabs` of the application is write-only (Arc: "allows you to create new Little Arc tabs").
    @objc var scriptTabs: [ScriptTab] { [] }
    @objc func insertInScriptTabs(_ tab: ScriptTab) { tab.openLittle() }
    @objc(insertInScriptTabs:atIndex:) func insertInScriptTabs(_ tab: ScriptTab, at index: Int) { tab.openLittle() }
}
