import BrkBase
import Foundation

func markdownTitle(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "[", with: "\\[")
        .replacingOccurrences(of: "]", with: "\\]")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
}

/// A bounded suggestion/legacy-file index derived from the complete visit ledger.
func historyIndex(_ visits: [HistoryEntry]) -> [HistoryEntry] {
    struct Key: Hashable { let profile: ProfileID; let url: URL }
    var seen: Set<Key> = []
    return Array(visits.filter { seen.insert(Key(profile: $0.profile, url: $0.url)).inserted }.prefix(Metrics.persistence.historyCap.value))
}

func openInFolders(_ state: AppState) -> [FolderDestinationCandidate] {
    state.doc.tree.items.values.compactMap { item in
        guard case .folder(let folder) = item.body, case .pinned(let space)? = state.doc.tree.role(of: item.id) else { return nil }
        return FolderDestinationCandidate(id: item.id, title: state.displayTitle(of: space) + " / " + folder.title)
    }.sorted { ($0.title, $0.id) < ($1.title, $1.id) }
}
