import BrkBase

/// Admission is tied to a concrete document and browser, not a logical tab or extension tab ID alone.
struct AudioObservation {
    struct Ticket: Equatable {
        let browser: BrowserToken
        let context: BrowsingContext
        let revision: UInt64
        let target: String
    }
    let browser: BrowserToken
    let context: BrowsingContext
    private var revision: UInt64 = 0
    private var available = false
    private var retired = false
    private(set) var target: String?
    private(set) var audible = false
    private(set) var tab: Int?

    init(browser: BrowserToken, context: BrowsingContext) { self.browser = browser; self.context = context }

    mutating func bind(_ target: String) { if !retired { self.target = target } }
    mutating func document(_ value: DocumentAvailability) {
        revision += 1
        switch value {
        case .loading, .ready: available = true
        case .unavailable: available = false; audible = false
        }
    }
    mutating func invalidate(retire: Bool = false) {
        revision += 1; available = false; audible = false
        if retire { retired = true; target = nil; tab = nil }
    }
    var ticket: Ticket? {
        guard !retired, available, let target else { return nil }
        return Ticket(browser: browser, context: context, revision: revision, target: target)
    }
    mutating func accept(_ value: Bool, tab: Int, for request: Ticket) -> Bool {
        guard request == ticket, tab > 0, self.tab == nil || self.tab == tab else { return false }
        self.tab = tab
        audible = value
        return true
    }
}
