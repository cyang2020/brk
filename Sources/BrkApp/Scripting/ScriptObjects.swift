import AppKit
import BrkBase
import BrkDomain
import Foundation

// AppleScript (Brk.sdef, Arc's dictionary: anatomy-m 1.1). Cocoa scripting builds these objects on demand: each
// holds ids only and reads the state through `AppState.script…` (BrkDomain/Scripting.swift) when asked, and every
// change is an ordinary command dispatched to the window it concerns, so a script can do nothing a menu, key or
// click could not. `execute` runs only while View > Developer > Allow JavaScript from Apple Events is on.
//
// The application's `windows` and write-only `tabs` live on the app delegate (`Lifecycle+Scripting`).

/// The store the scripting objects read and dispatch to.
@MainActor
enum Scripting {
    static var store: AppStore? { storeOverride ?? (NSApp.delegate as? Lifecycle)?.store }
    /// The tests' store (they run without the app delegate).
    static var storeOverride: AppStore?

    /// Browser windows front to back, Little and incognito windows included: by each window's place in the window
    /// server's order (`NSApp.orderedWindows` leaves Little windows out); windows not on screen last.
    static func orderedWindows(_ store: AppStore) -> [WindowID] {
        let front = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { $0[kCGWindowNumber as String] as? Int }
        let place = Dictionary(front.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return store.snapshot.windows.keys.sorted().sorted { a, b in
            let pa = store.windowController(a).flatMap { place[$0.window.windowNumber] } ?? Int.max
            let pb = store.windowController(b).flatMap { place[$0.window.windowNumber] } ?? Int.max
            return pa < pb
        }
    }

    /// An address the user typed or a script set: what the command bar would make of it (a host gets https).
    static func url(_ text: String) -> URL? {
        if let url = URL(string: text), url.scheme != nil { return url }
        return resolveTypedInput(text)
    }

    /// Ends `command` with an AppleScript error.
    static func fail(_ command: NSScriptCommand, _ message: String, number: Int = errOSAGeneralError) {
        command.scriptErrorNumber = number
        command.scriptErrorString = message
    }

    static let javaScriptOff = "Executing JavaScript through AppleScript is turned off. To turn it on, choose View > Developer > Allow JavaScript from Apple Events."
}

private let errOSAGeneralError = -2700
/// AppleScript's "not allowed" (errAEEventNotPermitted).
let errEventNotPermitted = -10004

@MainActor
@objc(BrkScriptWindow)
final class ScriptWindow: NSObject {
    private(set) var windowID: WindowID?
    /// Set by `make new window with properties {mode: "incognito"}` before the window exists.
    private var pendingIncognito = false

    nonisolated override init() { super.init() }
    nonisolated init(_ id: WindowID) { windowID = id; super.init() }

    private var store: AppStore? { Scripting.store }
    private var facts: ScriptWindowFacts? { windowID.flatMap { id in store?.state.scriptWindow(id) } }
    var nsWindow: NSWindow? { windowID.flatMap { store?.windowController($0)?.window } }

    @objc var uniqueID: String { windowID?.rawValue ?? "" }
    /// The title of the tab it shows (Brk's windows hide their title bar text).
    @objc var title: String {
        guard let id = windowID, let tab = facts?.activeTab, let fact = store?.state.scriptTab(tab, in: id) else { return Product.name }
        return fact.title
    }
    @objc var orderedIndex: Int {
        get { store.flatMap { s in windowID.flatMap { Scripting.orderedWindows(s).firstIndex(of: $0) } }.map { $0 + 1 } ?? 0 }
        set { if newValue <= 1 { nsWindow?.makeKeyAndOrderFront(nil) } }
    }
    @objc var hasCloseBox: Bool { nsWindow?.styleMask.contains(.closable) ?? false }
    @objc var isMiniaturizable: Bool { nsWindow?.styleMask.contains(.miniaturizable) ?? false }
    @objc var isMiniaturized: Bool {
        get { nsWindow?.isMiniaturized ?? false }
        set { if newValue { nsWindow?.miniaturize(nil) } else { nsWindow?.deminiaturize(nil) } }
    }
    @objc var isResizable: Bool { nsWindow?.styleMask.contains(.resizable) ?? false }
    @objc var isVisible: Bool {
        get { nsWindow?.isVisible ?? false }
        set { if newValue { nsWindow?.orderFront(nil) } else { nsWindow?.orderOut(nil) } }
    }
    @objc var isZoomable: Bool { nsWindow?.styleMask.contains(.resizable) ?? false }
    @objc var isZoomed: Bool {
        get { nsWindow?.isZoomed ?? false }
        set { if newValue != (nsWindow?.isZoomed ?? false) { nsWindow?.zoom(nil) } }
    }
    @objc var isIncognito: Bool {
        get { windowID == nil ? pendingIncognito : facts?.kind == .incognito }
        set { if windowID == nil { pendingIncognito = newValue } }
    }
    /// "normal" or "incognito"; settable only in `make new window with properties {mode: …}`.
    @objc var mode: String {
        get { isIncognito ? "incognito" : "normal" }
        set { if windowID == nil { pendingIncognito = newValue == "incognito" } }
    }
    @objc var activeTab: ScriptTab? {
        guard let id = windowID, let tab = facts?.activeTab else { return nil }
        return ScriptTab(window: id, item: tab, container: .window)
    }
    @objc var activeSpace: ScriptSpace? {
        guard let id = windowID, let space = facts?.activeSpace else { return nil }
        return ScriptSpace(window: id, space: space)
    }

    @objc var scriptTabs: [ScriptTab] {
        guard let id = windowID, let store else { return [] }
        return store.state.scriptTabs(in: id).map { ScriptTab(window: id, item: $0.id, container: .window) }
    }
    @objc func valueInScriptTabsWithUniqueID(_ uniqueID: String) -> ScriptTab? {
        guard let id = windowID, store?.state.scriptTab(ItemID(uniqueID), in: id) != nil else { return nil }
        return ScriptTab(window: id, item: ItemID(uniqueID), container: .window)
    }
    /// `make new tab at end of tabs of window 1 with properties {URL: …}`.
    @objc func insertInScriptTabs(_ tab: ScriptTab) { if let id = windowID { tab.open(in: id, space: nil) } }
    @objc(insertInScriptTabs:atIndex:) func insertInScriptTabs(_ tab: ScriptTab, at index: Int) { insertInScriptTabs(tab) }

    @objc var scriptSpaces: [ScriptSpace] {
        guard let id = windowID, let store else { return [] }
        return store.state.scriptSpaces(in: id).map { ScriptSpace(window: id, space: $0.id) }
    }
    @objc func valueInScriptSpacesWithUniqueID(_ uniqueID: String) -> ScriptSpace? {
        guard let id = windowID, store?.state.scriptSpaces(in: id).contains(where: { $0.id.rawValue == uniqueID }) == true else { return nil }
        return ScriptSpace(window: id, space: SpaceID(uniqueID))
    }

    /// `make new window`: a standard or incognito window, as File > New Window and New Incognito Window.
    func create() {
        guard windowID == nil, let store, let from = store.commandWindow else { return }
        let before = Set(store.snapshot.windows.keys)
        store.dispatch(.user(from, .window(pendingIncognito ? .newIncognito : .new)))
        windowID = store.snapshot.windows.keys.first { !before.contains($0) }
    }

    @objc func handleClose(_ command: NSScriptCommand) -> Any? {
        guard let id = windowID, store?.snapshot.windows[id] != nil else { Scripting.fail(command, "The window is gone."); return nil }
        store?.dispatch(.user(id, .window(.close)))
        return nil
    }

    nonisolated override var objectSpecifier: NSScriptObjectSpecifier? {
        nonisolated(unsafe) var made: NSScriptObjectSpecifier?
        MainActor.assumeIsolated { made = specifier }
        return made
    }
    var specifier: NSScriptObjectSpecifier? {
        guard let app = NSScriptClassDescription(for: NSApplication.self) else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: app, containerSpecifier: nil, key: "scriptWindows", uniqueID: uniqueID)
    }
}

@MainActor
@objc(BrkScriptTab)
final class ScriptTab: NSObject {
    enum Container: Equatable { case window, space(SpaceID), application }
    private(set) var windowID: WindowID?
    private(set) var itemID: ItemID?
    private var container: Container = .window
    /// The address `make new tab with properties {URL: …}` gives before the tab exists.
    private var pendingURL: String?

    nonisolated override init() { super.init() }
    nonisolated init(window: WindowID, item: ItemID, container: Container) {
        windowID = window; itemID = item; self.container = container
        super.init()
    }

    private var store: AppStore? { Scripting.store }
    private var facts: ScriptTabFacts? {
        guard let window = windowID, let item = itemID else { return nil }
        return store?.state.scriptTab(item, in: window)
    }

    @objc var uniqueID: String { itemID?.rawValue ?? "" }
    @objc var title: String { facts?.title ?? "" }
    @objc(URL) var address: String {
        get { facts?.url?.absoluteString ?? pendingURL ?? "" }
        set {
            guard let window = windowID, let item = itemID else { pendingURL = newValue; return }
            guard let url = Scripting.url(newValue) else { return }
            store?.dispatch(.user(window, .page(.navigate(.item(item), url))))
        }
    }
    @objc var loading: Bool { facts?.loading ?? false }
    @objc var location: String { facts?.location.rawValue ?? ScriptTabLocation.unpinned.rawValue }

    /// Makes the tab `make` asked for: a new focused tab in `window` (in `space` first, when given), at the URL
    /// the properties named.
    func open(in window: WindowID, space: SpaceID?) {
        guard itemID == nil, let store, let text = pendingURL, let url = Scripting.url(text) else { return }
        if let space { store.dispatch(.user(window, .space(.focus(space)))) }
        store.dispatch(.user(window, .commandBar(.open(.newTab))))
        store.dispatch(.user(window, .commandBar(.submit(url.absoluteString))))
        windowID = window
        itemID = store.state.scriptWindow(window)?.activeTab
        container = space.map(Container.space) ?? .window
    }

    /// The application's write-only `tabs`: `make new tab with properties {URL: …}` opens a Little window.
    func openLittle() {
        guard itemID == nil, let store, let text = pendingURL, let url = Scripting.url(text), let from = store.commandWindow else { return }
        let before = Set(store.snapshot.windows.keys)
        store.dispatch(.user(from, .window(.newLittle(url))))
        guard let little = store.snapshot.windows.keys.first(where: { !before.contains($0) }) else { return }
        windowID = little
        itemID = store.state.scriptWindow(little)?.activeTab
        container = .window
    }

    private func dispatch(_ command: NSScriptCommand, _ make: (ItemID) -> Command) -> Any? {
        guard let window = windowID, let item = itemID, facts != nil else { Scripting.fail(command, "The tab is gone."); return nil }
        store?.dispatch(.user(window, make(item)))
        return nil
    }

    @objc func handleSelect(_ command: NSScriptCommand) -> Any? { dispatch(command) { .tab(.focus($0)) } }
    @objc func handleGoBack(_ command: NSScriptCommand) -> Any? { dispatch(command) { .page(.back(.item($0))) } }
    @objc func handleGoForward(_ command: NSScriptCommand) -> Any? { dispatch(command) { .page(.forward(.item($0))) } }
    @objc func handleReload(_ command: NSScriptCommand) -> Any? { dispatch(command) { .page(.reload(.item($0), ignoringCache: false)) } }
    @objc func handleStop(_ command: NSScriptCommand) -> Any? { dispatch(command) { .page(.stop(.item($0))) } }
    @objc func handleClose(_ command: NSScriptCommand) -> Any? { dispatch(command) { .tab(.close(.item($0))) } }

    /// `execute tab … javascript "…"`: the page's main frame, its value as text. Refused while the Developer menu's
    /// switch is off, and for a tab without a live page.
    @objc func handleExecute(_ command: NSScriptCommand) -> Any? {
        guard let store, let window = windowID, let item = itemID, facts != nil else { Scripting.fail(command, "The tab is gone."); return nil }
        guard store.snapshot.settings.general.javaScriptFromAppleEvents == true else {
            Scripting.fail(command, Scripting.javaScriptOff, number: errEventNotPermitted); return nil
        }
        guard let script = command.evaluatedArguments?["javascript"] as? String else { Scripting.fail(command, "Give the javascript to run."); return nil }
        let page = PageID(window: window, item: item)
        guard store.snapshot.pages.contains(where: { $0.id == page }) else { Scripting.fail(command, "The tab has no page loaded; select it first."); return nil }
        command.suspendExecution()
        Task { @MainActor in
            do {
                let value = try await store.engine.evaluateForResult(script, in: page)
                command.resumeExecution(withResult: value ?? "")
            } catch {
                Scripting.fail(command, "The script failed: \(error.localizedDescription)")
                command.resumeExecution(withResult: nil)
            }
        }
        return nil
    }

    nonisolated override var objectSpecifier: NSScriptObjectSpecifier? {
        nonisolated(unsafe) var made: NSScriptObjectSpecifier?
        MainActor.assumeIsolated { made = specifier }
        return made
    }
    var specifier: NSScriptObjectSpecifier? {
        guard let window = windowID else { return nil }
        let owner: NSScriptObjectSpecifier?
        let ownerClass: AnyClass
        switch container {
        case .window, .application: owner = ScriptWindow(window).specifier; ownerClass = ScriptWindow.self
        case .space(let space): owner = ScriptSpace(window: window, space: space).specifier; ownerClass = ScriptSpace.self
        }
        guard let description = NSScriptClassDescription(for: ownerClass) else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: description, containerSpecifier: owner, key: "scriptTabs", uniqueID: uniqueID)
    }
}

@MainActor
@objc(BrkScriptSpace)
final class ScriptSpace: NSObject {
    let windowID: WindowID
    let spaceID: SpaceID

    nonisolated init(window: WindowID, space: SpaceID) { windowID = window; spaceID = space; super.init() }

    private var store: AppStore? { Scripting.store }

    @objc var uniqueID: String { spaceID.rawValue }
    @objc var title: String { store?.state.scriptSpaces(in: windowID).first { $0.id == spaceID }?.title ?? "" }

    @objc var scriptTabs: [ScriptTab] {
        guard let store else { return [] }
        return store.state.scriptTabs(inSpace: spaceID, window: windowID).map { ScriptTab(window: windowID, item: $0.id, container: .space(spaceID)) }
    }
    @objc func valueInScriptTabsWithUniqueID(_ uniqueID: String) -> ScriptTab? {
        guard store?.state.scriptTabs(inSpace: spaceID, window: windowID).contains(where: { $0.id.rawValue == uniqueID }) == true else { return nil }
        return ScriptTab(window: windowID, item: ItemID(uniqueID), container: .space(spaceID))
    }
    /// `make new tab at end of tabs of space "Work" of window 1 …`: the window switches to the space first.
    @objc func insertInScriptTabs(_ tab: ScriptTab) { tab.open(in: windowID, space: spaceID) }
    @objc(insertInScriptTabs:atIndex:) func insertInScriptTabs(_ tab: ScriptTab, at index: Int) { insertInScriptTabs(tab) }

    @objc func handleFocus(_ command: NSScriptCommand) -> Any? {
        guard store?.state.scriptSpaces(in: windowID).contains(where: { $0.id == spaceID }) == true else {
            Scripting.fail(command, "The space is gone."); return nil
        }
        store?.dispatch(.user(windowID, .space(.focus(spaceID))))
        return nil
    }

    nonisolated override var objectSpecifier: NSScriptObjectSpecifier? {
        nonisolated(unsafe) var made: NSScriptObjectSpecifier?
        MainActor.assumeIsolated { made = specifier }
        return made
    }
    var specifier: NSScriptObjectSpecifier? {
        guard let description = NSScriptClassDescription(for: ScriptWindow.self) else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: description, containerSpecifier: ScriptWindow(windowID).specifier,
                                   key: "scriptSpaces", uniqueID: uniqueID)
    }
}
