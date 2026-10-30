import AppKit
import BrkBase
import BrkControl
import BrkDomain
import os

/// TEMPORARY (W2). Delete this file and its three uses in AppStore when W1's rules land.
///
/// Stands in for the reducer rules that still `fatalError` in W1's first pass (`.commandBar(.open/.dismiss/.submit)`,
/// `.split(.addPane/.closePane)`, `.tab(.close)`, `.sidebar(.toggle)`, and the `.closedByPage` / `.openRequested`
/// page events), so the engine, the window host and the CEF key path can be exercised on the display before the
/// domain is complete. Enabled only by `BRK_W1_SHIM=1`; a normal launch never constructs it.
///
/// It never touches `AppState`: it keeps a few values of its own (an open command bar, extra split panes, closed
/// pages, a hidden sidebar) and patches the projected snapshot after `project`. Snapshot structs have internal
/// initializers, so the two it must build from scratch go through BrkControl's wire coder (`ControlWire`), which the
/// architecture rule allows; everything else is a public-field edit of a projected value. Key routing repeats the
/// three rules it needs (priority by stage, repeats, the duplicate guard) over the public `KeyMap`.
@MainActor
final class DomainShim {
    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> DomainShim? {
        guard environment["BRK_W1_SHIM"] == "1" else { return nil }
        return DomainShim(startURL: environment["BRK_START_URL"].flatMap(URL.init(string:)))
    }

    private let startURL: URL?
    private var barOpenID: Int?
    private var opens = 0
    private var extraPanes: [WindowID: [PageSpec]] = [:]
    private var focusedExtra: PageID?
    private var closed: Set<PageID> = []
    private var sidebarHidden = false
    private var lastDispatched: PressID?
    private var paneCounter = 0
    private let keyMap = KeyMap()
    private let log = Logger(subsystem: "brk", category: "w1-shim")

    init(startURL: URL?) {
        self.startURL = startURL
        log.notice("W1 shim active: command bar, split, close and sidebar toggle are simulated outside the reducer")
    }

    // MARK: Inputs

    /// Nil: not the shim's business, pass to `reduce`. Otherwise the input was consumed; the value is `keyHandled`.
    func intercept(_ input: Input, snapshot: AppSnapshot) -> Bool? {
        switch input {
        case .user(let window, let command):
            return apply(command, in: window, snapshot: snapshot) ? false : nil
        case .key(let window, let key):
            guard key.press.phase == .down, let (action, priority) = keyMap.lookup(key.press.chord),
                  handles(action.spec.command) else { return nil }
            if key.press.isRepeat, !action.spec.repeats { return key.stage == .beforePage ? false : nil }
            if key.pressID == lastDispatched { return false }
            let dispatch = key.stage != .beforePage || priority == .app
            guard dispatch else { return false }
            lastDispatched = key.pressID
            _ = apply(action.spec.command, in: window, snapshot: snapshot)
            return true
        case .system(.page(let page, let event)):
            switch event {
            case .closedByPage:
                closed.insert(page)
                if focusedExtra == page { focusedExtra = nil }
                return false
            case .openRequested:
                log.notice("openRequested dropped (W1's rule is not written)")
                return false
            default:
                return nil
            }
        case .system:
            return nil
        }
    }

    private func handles(_ command: Command) -> Bool {
        switch command {
        case .commandBar, .split(.addPane), .split(.closePane), .tab(.close), .sidebar(.toggle): true
        case .app(.exit): barOpenID != nil
        default: false
        }
    }

    private func apply(_ command: Command, in window: WindowID, snapshot: AppSnapshot) -> Bool {
        guard handles(command) else { return false }
        switch command {
        case .commandBar(.open):
            if barOpenID == nil {
                opens += 1
                barOpenID = opens
            }
        case .commandBar(.dismiss), .commandBar(.submit), .app(.exit):
            barOpenID = nil
        case .split(.addPane):
            barOpenID = nil
            let count = snapshot.windows[window]?.content.panes.count ?? 0
            guard count < Metrics.content.maxPanes.value else { break }
            paneCounter += 1
            let id = PageID(ItemID("shim-pane-\(paneCounter)"))
            let url = startURL.map { $0.deletingLastPathComponent().appendingPathComponent("page2.html") } ?? URL(string: "about:blank")!
            extraPanes[window, default: []].append(PageSpec(id: id, initialURL: url, profile: .default))
            focusedExtra = id
        case .split(.closePane):
            closeFocused(in: window, snapshot: snapshot)
        case .tab(.close):
            closeFocused(in: window, snapshot: snapshot)
        case .sidebar(.toggle):
            sidebarHidden.toggle()
        default:
            return false
        }
        log.notice("shim applied \(String(describing: command), privacy: .public): bar=\(self.barOpenID ?? 0, privacy: .public) extraPanes=\(self.extraPanes[window]?.count ?? 0) closed=\(self.closed.count)")
        return true
    }

    /// The focused extra pane goes first; otherwise the window's own focused page.
    private func closeFocused(in window: WindowID, snapshot: AppSnapshot) {
        if let focusedExtra, let i = extraPanes[window]?.firstIndex(where: { $0.id == focusedExtra }) {
            extraPanes[window]?.remove(at: i)
            closed.insert(focusedExtra)
            self.focusedExtra = extraPanes[window]?.last?.id
        } else if case .page(let page)? = snapshot.windows[window]?.focus {
            closed.insert(page)
        } else if let first = snapshot.windows[window]?.content.panes.first, case .page(let page) = first.content {
            closed.insert(page)
        }
    }

    // MARK: Snapshot

    func patch(_ snapshot: AppSnapshot) -> AppSnapshot {
        guard barOpenID != nil || !extraPanes.isEmpty || !closed.isEmpty || sidebarHidden else { return snapshot }
        var app = snapshot
        app.pages.removeAll { closed.contains($0.id) }
        for extras in extraPanes.values {
            for spec in extras where !closed.contains(spec.id) && !app.pages.contains(where: { $0.id == spec.id }) { app.pages.append(spec) }
        }
        for (id, var window) in app.windows {
            window.content.panes.removeAll { pane in
                switch pane.content {
                case .page(let p), .crashed(let p): closed.contains(p)
                case .blank: false
                }
            }
            if let extras = extraPanes[id]?.filter({ !closed.contains($0.id) }), !extras.isEmpty, let template = window.content.panes.first ?? Self.blankPane {
                for spec in extras {
                    var pane = template
                    pane.tab = spec.id.item
                    pane.content = .page(spec.id)
                    window.content.panes.append(pane)
                }
                window.content.split = ItemID("shim-split")
            }
            let share = 1.0 / Double(max(window.content.panes.count, 1))
            for i in window.content.panes.indices { window.content.panes[i].fraction = share }

            let focusedPage: PageID?
            if let focusedExtra, window.content.panes.contains(where: { $0.content == .page(focusedExtra) }) { focusedPage = focusedExtra }
            else if case .page(let p) = window.focus, !closed.contains(p) { focusedPage = p }
            else { focusedPage = window.content.panes.lazy.compactMap { if case .page(let p) = $0.content { p } else { nil } }.first }
            for i in window.content.panes.indices { window.content.panes[i].focused = window.content.panes[i].content == focusedPage.map(PaneContent.page) }
            if let barOpenID {
                window.overlay = .commandBar(Self.bar(openID: barOpenID))
                window.focus = .commandBarInput
            } else {
                window.overlay = nil
                window.focus = focusedPage.map(FocusTarget.page) ?? .none
            }
            if sidebarHidden { window.sidebar.visible = false }
            app.windows[id] = window
        }
        return app
    }

    static func bar(openID: Int) -> CommandBarSnapshot {
        let json = #"{"openID":\#(openID),"placement":"centered","initialQuery":"","tabs":[],"history":[],"actions":[]}"#
        return try! ControlWire.decode(CommandBarSnapshot.self, line: Data(json.utf8))
    }

    static let blankPane: Pane? = {
        let json = #"{"tab":"shim-blank","content":{"blank":{}},"fraction":1,"focused":false}"#
        return try? ControlWire.decode(Pane.self, line: Data(json.utf8))
    }()
}
