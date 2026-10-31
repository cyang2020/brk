import BrkBase
import CefKit
import Foundation

/// One adapter per browser incarnation. It owns no browser lease, and is invalidated before presentation retires.
@MainActor
final class PageFind {
    private unowned let browser: CefBrowser
    private let publish: (FindUpdate) -> Void
    private(set) var document: DocumentToken?
    private var correlation = FindCorrelation()
    private var scopedSearch: (SearchToken, FindQuery, SelectionTicket)?
    private struct Selection { let ticket: SelectionTicket; let frame: CefBrowser.FrameDocument }
    private var selection: Selection?
    private var captureRequest: FindRequestID?
    private enum Operation {
        case capture(SelectionTicket), jump(SelectionTicket), edit(SelectionTicket)
        case search(SearchToken), validate(SelectionTicket), revision
    }
    private struct Pending {
        let document: DocumentToken
        let frame: CefBrowser.FrameDocument
        let operation: Operation
    }
    private var pending: [FindRequestID: Pending] = [:]
    private var timeouts: [FindRequestID: Task<Void, Never>] = [:]
    private var mutations = FindMutations()
    private var poll: Task<Void, Never>?
    private var pagePoll: Task<Void, Never>?
    private var refresh: Task<Void, Never>?
    private var revisions = FindRevisions()
    private var rendererUsed = false

    init(browser: CefBrowser, publish: @escaping (FindUpdate) -> Void) { self.browser = browser; self.publish = publish }

    func observe(_ event: PageEvent) {
        if case .documentChanged(let availability) = event {
            let next: DocumentToken? = if case .ready(let token) = availability { token } else { nil }
            if document != next { invalidate(); document = next }
        }
    }
    func invalidate(nativeAlive: Bool = true, keepMutationHistory: Bool = false) {
        if !keepMutationHistory { mutations.removeAll() }
        let hadNativeSearch = correlation.search != nil
        correlation.reset(); scopedSearch = nil
        pagePoll?.cancel(); pagePoll = nil; refresh?.cancel(); refresh = nil; revisions.removeAll()
        poll?.cancel(); poll = nil
        if nativeAlive {
            if hadNativeSearch { browser.stopFinding() }
            if rendererUsed {
                for frame in browser.frameDocuments { _ = browser.sendRenderer(to: frame, request: UUID().uuidString, payload: "{\"op\":\"release\"}") }
            }
        }
        rendererUsed = false
        selection = nil; captureRequest = nil; pending.removeAll(); document = nil
        for task in timeouts.values { task.cancel() }; timeouts.removeAll()
    }

    func perform(_ request: FindRequest) {
        guard document == request.document else { return }
        switch request {
        case .search(let id, let token, let query, let scope):
            let hadNativeSearch = correlation.search != nil
            correlation.reset(); scopedSearch = nil
            pagePoll?.cancel(); pagePoll = nil; refresh?.cancel(); refresh = nil
            if hadNativeSearch { browser.stopFinding() }
            guard !query.text.isEmpty else { publish(.matches(id, token, count: 0, ordinal: nil, passComplete: true)); return }
            switch scope {
            case .page:
                guard !query.text.contains("\r") else { publish(.failed(id,.unsupported("Page find does not support carriage returns."))); return }
                correlation.begin(id, token, query)
                revisions.beginQuery()
                pollPage()
            case .editable(let ticket):
                guard let selection, selection.ticket == ticket, browser.focusedDocument() == selection.frame else { publish(.failed(id, .staleSelection)); return }
                scopedSearch = (token, query, ticket)
                send(id, selection.frame, .search(token), ["op":"search", "ticket":ticket.id.rawValue,
                    "query":query.text, "caseSensitive":query.caseSensitive])
            }
        case .step(let id, let token, let direction):
            if let (search, query, ticket) = scopedSearch, search == token {
                guard let selection, selection.ticket == ticket, browser.focusedDocument() == selection.frame else { publish(.failed(id, .staleSelection)); return }
                send(id, selection.frame, .search(token), ["op":"search", "ticket":ticket.id.rawValue,
                    "query":query.text,"caseSensitive":query.caseSensitive,"step":true,"forward":direction == .next])
            } else if let step = correlation.step(id, token, direction) { run(step) }
        case .stop(let token):
            if correlation.search == token { correlation.reset(); pagePoll?.cancel(); pagePoll = nil; refresh?.cancel(); refresh = nil; browser.stopFinding() }
            if scopedSearch?.0 == token { scopedSearch = nil }
        case .release:
            let saved = document; invalidate(keepMutationHistory: true); document = saved
        case .captureSelection(let id, let doc):
            captureRequest = id
            let superseded = pending.filter { if case .capture = $0.value.operation { true } else { false } }
            for (old, _) in superseded { pending[old] = nil; timeouts.removeValue(forKey: old)?.cancel() }
            let hadNativeSearch = correlation.search != nil
            correlation.reset(); scopedSearch = nil
            pagePoll?.cancel(); pagePoll = nil; refresh?.cancel(); refresh = nil
            if hadNativeSearch { browser.stopFinding(clearSelection: false) }
            let ticket = SelectionTicket(id: SelectionID(UUID().uuidString), document: doc)
            selection = nil; poll?.cancel(); poll = nil
            for (old, _) in superseded { publish(.failed(old, .staleSelection)) }
            guard captureRequest == id else { return }
            guard let frame = browser.focusedDocument() else { captureRequest = nil; publish(.failed(id, .unavailable)); return }
            send(id, frame, .capture(ticket), ["op":"capture","ticket":ticket.id.rawValue])
        case .jump(let id, let ticket):
            guard let selection, selection.ticket == ticket, browser.focusedDocument() == selection.frame else { publish(.failed(id, .staleSelection)); return }
            send(id, selection.frame, .jump(ticket), ["op":"jump","ticket":ticket.id.rawValue])
        case .replace(let id, let ticket, let query, let replacement, let all):
            if let result = mutations.begin(id, ticket: ticket) { publish(result); return }
            guard let selection, selection.ticket == ticket, browser.focusedDocument() == selection.frame else { publish(.failed(id, .staleSelection)); return }
            poll?.cancel(); poll = nil
            send(id, selection.frame, .edit(ticket), ["op":"replace","request":id.rawValue,"ticket":ticket.id.rawValue,
                "query":query.text,"caseSensitive":query.caseSensitive,"replacement":replacement,"all":all])
        }
    }
    func nativeResult(id: Int, count: Int, ordinal: Int, final: Bool) {
        guard let (update, next) = correlation.receive(id: id, count: count, ordinal: ordinal, final: final, document: document) else { return }
        publish(update)
        if let next { run(next) }
    }
    private func run(_ step: FindCorrelation.Step) {
        guard correlation.current == step, let query = correlation.query, correlation.search?.document == document else { return }
        browser.find(query.text, forward: step.direction == .next, matchCase: query.caseSensitive, findNext: true)
    }
    private func send(_ id: FindRequestID, _ frame: CefBrowser.FrameDocument, _ operation: Operation, _ parameters: [String: Any]) {
        guard let document, let data = try? JSONSerialization.data(withJSONObject: parameters),
              let payload = String(data: data, encoding: .utf8) else { return }
        rendererUsed = true
        pending[id] = Pending(document: document, frame: frame, operation: operation)
        guard browser.sendRenderer(to: frame, request: id.rawValue, payload: payload) else {
            if captureRequest == id { captureRequest = nil }
            pending[id] = nil; publish(.failed(id, .staleSelection)); return
        }
        timeouts[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self?.timedOut(id) }
        }
    }
    private func timedOut(_ id: FindRequestID) {
        timeouts[id] = nil
        guard let p = pending[id], p.document == document else { return }
        switch p.operation {
        case .edit(let ticket): publish(.edited(id, ticket, .unconfirmed)) // keep the fence for a late confirmation
        case .validate, .revision: pending[id] = nil
        default:
            pending[id] = nil
            if captureRequest == id { captureRequest = nil }
            publish(.failed(id, .failed("The page did not answer. Try selecting text again.")))
        }
    }
    func receive(_ message: CefRendererMessage) {
        if message.kind == "released" || message.kind == "created" {
            let retired = selection.flatMap { !browser.isCurrent($0.frame) ? $0.ticket : nil }
            for (id, value) in pending where !browser.isCurrent(value.frame) {
                pending[id] = nil; timeouts.removeValue(forKey: id)?.cancel()
                if captureRequest == id { captureRequest = nil }
                switch value.operation {
                case .edit(let ticket):
                    _ = mutations.complete(id, ticket: ticket, result: .unconfirmed)
                    publish(.failed(id, .failed("Replacement was not confirmed because its frame changed. Select and capture the field again.")))
                case .capture, .jump, .search: publish(.failed(id, .staleSelection))
                case .validate, .revision: break
                }
            }
            if let retired { invalidateSelection(retired) }
            if correlation.search != nil { scheduleRefresh() }
            return
        }
        let id = FindRequestID(message.request)
        guard let p = pending[id], p.document == document,
              p.frame.frame == message.frame, p.frame.document == message.document, browser.isCurrent(p.frame) else { return }
        pending[id] = nil; timeouts.removeValue(forKey: id)?.cancel()
        if case .capture = p.operation {
            guard captureRequest == id else { return }
            captureRequest = nil
            guard browser.focusedDocument() == p.frame else { publish(.failed(id, .staleSelection)); return }
        }
        guard let data = message.payload.data(using: .utf8),
              let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let status = value["status"] as? String else {
            if case .edit(let ticket) = p.operation { publish(mutations.complete(id, ticket: ticket, result: .unconfirmed)) }
            else { publish(.failed(id, .failed("The page returned an unreadable result."))) }
            return
        }
        if status == "refused" {
            publish(.failed(id, .unsupported(value["message"] as? String ?? "This selection is not supported.")))
            selection = nil; poll?.cancel(); poll = nil; return
        }
        switch p.operation {
        case .capture(let ticket):
            guard status == "selection", let text = value["text"] as? String else { publish(.failed(id, .unavailable)); return }
            selection = Selection(ticket: ticket, frame: p.frame)
            publish(.selection(id, ticket, text: text, editable: (value["editable"] as? String).flatMap(EditableKind.init(rawValue:))))
            pollSelection(ticket)
        case .search(let token):
            guard scopedSearch?.0 == token, status == "matches", let count = value["count"] as? Int else { return }
            let ordinal = value["ordinal"] as? Int ?? 0
            publish(.matches(id, token, count: count, ordinal: ordinal > 0 && ordinal <= count ? ordinal : nil, passComplete: true))
        case .jump(let ticket):
            if status == "jumped" { publish(.jumped(id, ticket)) }
        case .edit(let ticket):
            let result = Self.editResult(value)
            let update = mutations.complete(id, ticket: ticket, result: result)
            if result != .unconfirmed { selection = nil }
            publish(update)
        case .revision:
            guard correlation.search != nil, status == "revision", let revision = value["revision"] as? Int else { return }
            if revisions.observe(frameDocument: p.frame.document, revision: revision) { scheduleRefresh() }
        case .validate(let ticket):
            if status != "valid" { invalidateSelection(ticket) }
        }
    }
    static func editResult(_ value: [String: Any]) -> EditResult {
        let n = value["applied"] as? Int
        switch value["status"] as? String {
        case "edited" where n != nil && n! >= 0: return .replaced(n!)
        case "partial" where n != nil && n! >= 0: return .partial(applied: n!, reason: value["message"] as? String ?? "The remaining edits were stopped.")
        default: return .unconfirmed
        }
    }
    private func pollPage() {
        pagePoll?.cancel()
        pagePoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.correlation.search != nil else { return }
                let frames = self.browser.frameDocuments.filter { self.browser.isCurrent($0) }
                if frames.isEmpty, self.revisions.needsInitial { self.scheduleRefresh() }
                for frame in frames {
                    self.send(FindRequestID(UUID().uuidString), frame, .revision, ["op":"revision"])
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }
    private func scheduleRefresh() {
        guard refresh == nil else { return }
        refresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, let self else { return }
            self.refresh = nil
            guard let token = self.correlation.search, token.document == self.document,
                  let query = self.correlation.query, let step = self.correlation.current else { return }
            self.revisions.started()
            self.correlation.pauseForRefresh(); self.browser.stopFinding()
            self.correlation.resumeAfterRefresh()
            self.publish(.matches(step.request, token, count: 0, ordinal: nil, passComplete: false))
            guard self.correlation.search == token, self.correlation.current == step, self.correlation.query == query else { return }
            self.browser.find(query.text, forward: step.direction == .next, matchCase: query.caseSensitive, findNext: true)
        }
    }
    private func invalidateSelection(_ ticket: SelectionTicket) {
        guard selection?.ticket == ticket else { return }
        selection = nil; scopedSearch = nil; poll?.cancel(); poll = nil; publish(.invalidated(ticket))
    }
    private func pollSelection(_ ticket: SelectionTicket) {
        poll?.cancel()
        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let self, let selection = self.selection, selection.ticket == ticket,
                      self.document == ticket.document else { return }
                if self.browser.focusedDocument() != selection.frame { self.invalidateSelection(ticket); return }
                if !self.pending.isEmpty { continue }
                self.send(FindRequestID(UUID().uuidString), selection.frame, .validate(ticket), ["op":"validate","ticket":ticket.id.rawValue])
            }
        }
    }
}
