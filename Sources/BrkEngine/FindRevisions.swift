/// Renderer revisions supplement Chromium's find, which does not recount every same-document mutation.
struct FindRevisions {
    private var versions: [String: Int] = [:]
    private(set) var needsInitial = false
    mutating func beginQuery() { needsInitial = true }
    mutating func started() { needsInitial = false }
    mutating func removeAll() { versions.removeAll(); needsInitial = false }
    mutating func observe(frameDocument: String, revision: Int) -> Bool {
        let changed = needsInitial || versions[frameDocument] != revision
        versions[frameDocument] = revision
        return changed
    }
}
