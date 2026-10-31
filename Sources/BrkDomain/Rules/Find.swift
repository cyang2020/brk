import BrkBase
import Foundation

struct FindSession: Equatable, Sendable {
    enum Capture: Equatable, Sendable { case selection, replace, jump }
    let page: PageID
    let context: BrowsingContext
    var document: DocumentToken?
    var query = FindQuery(text: "")
    var replacement = false
    var search: SearchToken?
    var request: FindRequestID?
    var capture: (id: FindRequestID, purpose: Capture)?
    var operation: FindRequestID?
    var ticket: SelectionTicket?
    var editable: EditableKind?
    var count: Int?
    var ordinal: Int?
    var searching = false
    var message = ""
    var focusInput = true
    var focusRequest: FindRequestID?
    static func == (a: Self, b: Self) -> Bool {
        a.page == b.page && a.context == b.context && a.document == b.document && a.query == b.query &&
        a.replacement == b.replacement && a.search == b.search && a.request == b.request &&
        a.capture?.id == b.capture?.id && a.capture?.purpose == b.capture?.purpose && a.operation == b.operation &&
        a.ticket == b.ticket && a.editable == b.editable && a.count == b.count && a.ordinal == b.ordinal &&
        a.searching == b.searching && a.message == b.message && a.focusInput == b.focusInput && a.focusRequest == b.focusRequest
    }
}

public struct FindSnapshot: Equatable, Sendable, Codable {
    public var page: PageID
    public var query: FindQuery
    public var replacement: Bool
    public var count: Int?
    public var ordinal: Int?
    public var searching: Bool
    public var canReplace: Bool
    public var message: String
    public var scope: String
    public var focusRequest: FindRequestID?
}

extension AppState {
    func findPage(in window: WindowID) -> PageID? {
        guard let tab = resolveTab(.focused, in: window) else { return nil }
        let page = PageID(window: window, item: tab)
        return session.loaded.contains(page) ? page : nil
    }
}

extension Work {
    mutating func find(_ intent: FindIntent, in window: WindowID) {
        if case .close = intent { closeFind(in: window); return }
        guard let page = state.findPage(in: window) else { return }
        let context = state.browsingContext(of: page.item)
        if state.session.windows[window]?.find?.page != page {
            closeFind(in: window)
            state.session.windows[window]?.find = FindSession(page: page, context: context)
        }
        guard var f = state.session.windows[window]?.find else { return }
        if case .ready(let doc) = state.session.live[page]?.document { f.document = doc }
        f.message = ""
        switch intent {
        case .open(let replace):
            f.replacement = replace; f.focusInput = true; f.focusRequest = FindRequestID(ctx.newID())
            if replace { captureFind(&f, purpose: .replace) }
            else if !f.query.text.isEmpty { startFind(&f) }
        case .query(let query): f.query = query; startFind(&f)
        case .step(let direction):
            if f.query.text.isEmpty { f.query = state.session.windows[window]?.lastFind[context] ?? FindQuery(text: "") }
            if let search = f.search, !f.query.text.isEmpty {
                let id = FindRequestID(ctx.newID()); f.request = id; f.searching = true
                effects.append(.find(.step(id, search, direction)))
            } else { startFind(&f) }
        case .useSelection: f.focusInput = true; f.focusRequest = FindRequestID(ctx.newID()); captureFind(&f, purpose: .selection)
        case .captureScope: f.replacement = true; f.focusInput = true; f.focusRequest = FindRequestID(ctx.newID()); captureFind(&f, purpose: .replace)
        case .jumpToSelection: captureFind(&f, purpose: .jump)
        case .replaceCurrent(let replacement), .replaceAll(let replacement):
            guard f.operation == nil, let ticket = f.ticket, f.editable != nil, f.replacement else {
                f.message = "Select text in a supported editable field, then capture that field."; break
            }
            let id = FindRequestID(ctx.newID()); f.operation = id
            let all: Bool = if case .replaceAll = intent { true } else { false }
            effects.append(.find(.replace(id, ticket, f.query, replacement: replacement, all: all)))
        case .close: break
        }
        if !f.query.text.isEmpty { state.session.windows[window]?.lastFind[context] = f.query }
        state.session.windows[window]?.find = f
    }

    mutating func captureFind(_ f: inout FindSession, purpose: FindSession.Capture) {
        guard let doc = f.document else { f.message = "Wait for the page to finish loading."; return }
        guard f.operation == nil else { f.message = "Wait for replacement confirmation before capturing another field."; return }
        // The adapter stops native Find without clearing the selection being captured.
        f.search = nil; f.request = nil; f.count = nil; f.ordinal = nil; f.searching = false
        f.ticket = nil; f.editable = nil
        let id = FindRequestID(ctx.newID()); f.capture = (id, purpose)
        effects.append(.find(.captureSelection(id, doc)))
    }

    mutating func startFind(_ f: inout FindSession) {
        if let search = f.search { effects.append(.find(.stop(search))) }
        f.search = nil; f.request = nil; f.count = nil; f.ordinal = nil; f.searching = false
        guard !f.query.text.isEmpty else { return }
        guard let doc = f.document else { f.message = "Wait for the page to finish loading."; return }
        let scope: FindScope
        if f.replacement {
            guard let ticket = f.ticket, f.editable != nil else {
                f.message = "Select text in a supported editable field, then capture that field."; return
            }
            scope = .editable(ticket)
        } else { scope = .page }
        let token = SearchToken(id: SearchID(ctx.newID()), document: doc), id = FindRequestID(ctx.newID())
        f.search = token; f.request = id; f.searching = true
        effects.append(.find(.search(id, token, f.query, scope)))
    }

    mutating func closeFind(in window: WindowID) {
        guard let f = state.session.windows[window]?.find else { return }
        state.session.windows[window]?.find = nil
        if let s = f.search { effects.append(.find(.stop(s))) }
        if let d = f.document { effects.append(.find(.release(d))) }
    }

    /// Runs after normalize, so every target, context and overlay change shares the same invalidation rule.
    mutating func reconcileFind(from old: AppState) {
        for (window, session) in old.session.windows where state.session.windows[window] == nil {
            if let d = session.find?.document { effects.append(.find(.release(d))) }
        }
        for window in state.session.windows.keys {
            guard var f = state.session.windows[window]?.find else { continue }
            let session = state.session.windows[window]!
            let conflict: Bool = switch session.overlay { case .commandBar?, .library?: true; default: false }
            if state.findPage(in: window) != f.page || state.browsingContext(of: f.page.item) != f.context ||
                conflict || session.renaming != nil || session.dialog != nil || session.profileDialog != nil {
                closeFind(in: window); continue
            }
            let doc: DocumentToken? = if case .ready(let d) = state.session.live[f.page]?.document { d } else { nil }
            if f.document != doc {
                if let d = f.document { effects.append(.find(.release(d))) }
                f.document = doc; f.search = nil; f.ticket = nil; f.editable = nil; f.capture = nil; f.operation = nil
                f.message = doc == nil ? "Wait for the page to finish loading." : ""
                startFind(&f)
                state.session.windows[window]?.find = f
            }
        }
    }

    mutating func findUpdated(_ update: FindUpdate) {
        for window in state.session.windows.keys {
            guard var f = state.session.windows[window]?.find else { continue }
            switch update {
            case .matches(let id, let token, let count, let ordinal, let complete):
                guard f.search == token, f.request == id, f.document == token.document else { continue }
                f.count = max(0, count); f.ordinal = ordinal; f.searching = !complete
            case .selection(let id, let ticket, let text, let editable):
                guard f.capture?.id == id, f.document == ticket.document else { continue }
                let purpose = f.capture!.purpose; f.capture = nil; f.ticket = ticket; f.editable = editable
                if purpose == .jump {
                    let id = FindRequestID(ctx.newID()); f.operation = id; f.focusInput = false
                    effects.append(.find(.jump(id, ticket)))
                } else {
                    if purpose == .selection || !text.isEmpty { f.query.text = text }
                    if purpose == .replace && editable == nil { f.message = "Select an enabled text field or a simple editable text region." }
                    else { startFind(&f) }
                }
            case .jumped(let id, let ticket):
                guard f.operation == id, f.ticket == ticket else { continue }
                f.operation = nil; f.message = "Selection revealed."
            case .edited(let id, let ticket, let result):
                guard f.operation == id, f.ticket == ticket else { continue }
                if result != .unconfirmed { f.operation = nil; f.ticket = nil }
                f.editable = nil; f.search = nil; f.count = nil; f.ordinal = nil; f.searching = false
                switch result {
                case .replaced(let n): f.message = "Replaced \(n). Select and capture the field to continue."
                case .partial(let n, let reason): f.message = "Replaced \(n). \(reason)"
                case .unconfirmed: f.message = "Replacement was not confirmed. Check the field before trying again."
                }
            case .invalidated(let ticket):
                guard f.ticket == ticket else { continue }
                f.ticket = nil; f.editable = nil
                if f.replacement {
                    f.search = nil; f.count = nil; f.ordinal = nil; f.searching = false
                    f.message = "The selection changed. Select and capture the field again."
                }
            case .failed(let id, let failure):
                guard f.request == id || f.capture?.id == id || f.operation == id else { continue }
                f.message = failure.message; f.searching = false; f.capture = nil; f.operation = nil
                if f.request == id { f.search = nil; f.request = nil }
                f.ticket = nil; f.editable = nil
            }
            if !f.query.text.isEmpty { state.session.windows[window]?.lastFind[f.context] = f.query }
            state.session.windows[window]?.find = f
        }
    }
}
