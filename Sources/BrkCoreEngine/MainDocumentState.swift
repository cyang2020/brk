import BrkBase
import Foundation

/// Converts main-frame callbacks into document observations without letting an older attempt fail its replacement.
struct MainDocumentState {
    private(set) var browser: BrowserToken
    private var sequence: UInt64 = 0
    private var document: DocumentAvailability = .unavailable
    var availability: DocumentAvailability { document }
    var readyDocument: DocumentToken? { if case .ready(let token) = document { token } else { nil } }
    var lastSequence: UInt64 { sequence }
    private var failed = false
    private var acceptedURLs: Set<String> = []
    private var pendingAddress: URL?
    private var committedAddress: URL?

    init(browser: BrowserToken) { self.browser = browser }

    mutating func rebind(to browser: BrowserToken) {
        self.browser = browser
        switch document {
        case .ready(let token): document = .ready(DocumentToken(browser: browser, sequence: token.sequence))
        case .loading(let token): document = .loading(DocumentToken(browser: browser, sequence: token.sequence))
        case .unavailable: break
        }
    }

    mutating func prepareNavigation() {
        failed = false
        acceptedURLs.removeAll()
        pendingAddress = nil
    }

    mutating func allowed(_ url: URL, redirect: Bool) -> [PageEvent] {
        if !redirect { acceptedURLs.removeAll() }
        acceptedURLs.insert(url.absoluteString)
        failed = false
        return [.navigationRequested(url)]
    }

    mutating func addressChanged(_ url: URL?, loading: Bool) -> [PageEvent] {
        if url == committedAddress { return loadingChanged(loading) }
        pendingAddress = url
        return url.map { [.navigationRequested($0)] + loadingChanged(loading) } ?? []
    }

    mutating func started(_ url: URL?) -> [PageEvent] {
        sequence += 1
        pendingAddress = nil
        if acceptedURLs.isEmpty, let url { acceptedURLs.insert(url.absoluteString) }
        let events = changed(failed ? .unavailable : .loading(DocumentToken(browser: browser, sequence: sequence)))
        guard !failed, let url else { return events }
        committedAddress = url
        return events + [.committed(url)]
    }

    mutating func finished(_ url: URL?) -> [PageEvent] {
        guard !failed, case .loading(let token) = document else { return [] }
        pendingAddress = nil
        if let url { committedAddress = url }
        return (url.map { [.committed($0)] } ?? []) + changed(.ready(token))
    }

    mutating func loadingChanged(_ loading: Bool) -> [PageEvent] {
        guard !loading, !failed, case .ready = document, let address = pendingAddress else { return [] }
        pendingAddress = nil
        // The domain shows this address now, so going back to the document's first address is a change again.
        committedAddress = address
        return [.committed(address)]
    }

    mutating func loadFailed(code: Int, description: String, url: String) -> [PageEvent] {
        // ERR_ABORTED also reports superseded navigations and attachment responses. It is not a failed document.
        if code == -3 {
            if pendingAddress?.absoluteString == url { pendingAddress = nil }
            return []
        }
        guard acceptedURLs.isEmpty || acceptedURLs.contains(url) else { return [] }
        failed = true
        pendingAddress = nil
        return changed(.unavailable) + [.loadFailed(code: code, description: description, url: url)]
    }

    mutating func stopped() -> [PageEvent] {
        guard case .loading = document else { return [] }
        failed = true
        pendingAddress = nil
        return changed(.unavailable)
    }

    mutating func rendererGone() -> [PageEvent] {
        failed = true
        pendingAddress = nil
        return changed(.unavailable)
    }

    private mutating func changed(_ value: DocumentAvailability) -> [PageEvent] {
        document = value
        return [.documentChanged(value)]
    }
}
