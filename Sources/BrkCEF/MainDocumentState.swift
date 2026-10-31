import BrkBase
import Foundation

/// Converts main-frame callbacks into document observations without letting an older attempt fail its replacement.
struct MainDocumentState {
    let browser: BrowserToken
    private var sequence: UInt64 = 0
    private var document: DocumentAvailability = .unavailable
    var availability: DocumentAvailability { document }
    var lastSequence: UInt64 { sequence }
    private var failed = false
    private var acceptedURLs: Set<String> = []
    private var pendingAddress: URL?

    init(browser: BrowserToken) { self.browser = browser }

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
        pendingAddress = url
        return url.map { [.navigationRequested($0)] + loadingChanged(loading) } ?? []
    }

    mutating func started(_ url: URL?) -> [PageEvent] {
        sequence += 1
        pendingAddress = nil
        if acceptedURLs.isEmpty, let url { acceptedURLs.insert(url.absoluteString) }
        return changed(failed ? .unavailable : .loading(DocumentToken(browser: browser, sequence: sequence)))
    }

    mutating func finished(_ url: URL?) -> [PageEvent] {
        guard !failed, case .loading(let token) = document else { return [] }
        pendingAddress = nil
        return (url.map { [.committed($0)] } ?? []) + changed(.ready(token))
    }

    mutating func loadingChanged(_ loading: Bool) -> [PageEvent] {
        guard !loading, !failed, case .ready = document, let address = pendingAddress else { return [] }
        pendingAddress = nil
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
