import BrkBase

/// One collection owns every incarnation until both browser and native host have closed.
/// Presentation and operations are independent reasons to keep the original browser alive.
@MainActor
public final class BrowserResources<Resource: AnyObject> {
    public enum Lease: Hashable { case transfer(DownloadID), documentOutput(String), siteData(String), extensionOperation(String) }
    public struct Entry {
        public let resource: Resource
        public let context: ContextEpoch
        public fileprivate(set) var presented = true
        public fileprivate(set) var leases: Set<Lease> = []
        public fileprivate(set) var closing = false
        public fileprivate(set) var browserClosed = false
        public fileprivate(set) var hostClosed = false
    }
    public private(set) var entries: [BrowserToken: Entry] = [:]
    public var leasesDidChange: ((BrowserToken) -> Void)?
    public init() {}
    public func insert(_ resource: Resource, browser: BrowserToken, context: ContextEpoch) {
        precondition(entries[browser] == nil)
        entries[browser] = Entry(resource: resource, context: context)
    }
    public func acquire(_ lease: Lease, browser: BrowserToken) -> Bool {
        guard let entry = entries[browser], !entry.closing else { return false }
        if entries[browser]!.leases.insert(lease).inserted { leasesDidChange?(browser) }
        return true
    }
    public func release(_ lease: Lease, browser: BrowserToken) {
        let removed = entries[browser]?.leases.remove(lease)
        removeIfClosed(browser)
        if removed != nil { leasesDidChange?(browser) }
    }
    public func unpresent(_ browser: BrowserToken) { entries[browser]?.presented = false }
    public func beginClose(_ browser: BrowserToken) -> Bool {
        guard let entry = entries[browser], !entry.presented, entry.leases.isEmpty, !entry.closing, !entry.browserClosed else { return false }
        entries[browser]!.closing = true
        return true
    }
    public func browserClosed(_ browser: BrowserToken) {
        entries[browser]?.browserClosed = true
        removeIfClosed(browser)
    }
    public func hostClosed(_ browser: BrowserToken) {
        entries[browser]?.hostClosed = true
        removeIfClosed(browser)
    }
    private func removeIfClosed(_ browser: BrowserToken) {
        guard let entry = entries[browser], entry.browserClosed, entry.hostClosed, entry.leases.isEmpty else { return }
        entries[browser] = nil
    }
}
