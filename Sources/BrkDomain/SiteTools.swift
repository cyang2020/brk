import BrkBase
import Foundation

public enum SiteToolsCommand: Hashable, Sendable, Codable {
    case connectGitHub(favorite: ItemID?)
    case refreshFolder(ItemID)
    case connectCalendar
    case joinMeeting
}
public struct PullRequestLink: Hashable, Sendable, Codable {
    public let title: String
    public let url: URL
    public init(title: String, url: URL) { self.title = title; self.url = url }
}
public struct CalendarMeeting: Hashable, Sendable, Codable {
    public let title: String
    public let url: URL
    public let start: Instant
    public let end: Instant
    public init(title: String, url: URL, start: Instant, end: Instant) { self.title = title; self.url = url; self.start = start; self.end = end }
}
public enum SiteRequestKind: Hashable, Sendable {
    case github(repository: String?, favorite: ItemID?)
    case calendar(join: Bool)
}
public struct SiteRequest: Hashable, Sendable {
    public let id: String
    public let window: WindowID
    public let profile: ProfileID
    public let kind: SiteRequestKind
}
public enum SiteOutcome: Hashable, Sendable {
    case unread(repository: String, count: Int)
    case pullRequests(repository: String, [PullRequestLink])
    case calendar([CalendarMeeting])
    case failed(String)
    case cancelled
}
enum SiteTarget: Hashable, Sendable {
    case folder(ItemID), favorite(ItemID), calendar(ProfileID), newFolder(WindowID)
}
struct PendingSiteRequest: Equatable, Sendable {
    let request: SiteRequest
    let folder: ItemID?
    let space: SpaceID
    var target: SiteTarget {
        if let folder { return .folder(folder) }
        switch request.kind {
        case .github(_, let favorite?): return .favorite(favorite)
        case .github: return .newFolder(request.window)
        case .calendar: return .calendar(request.profile)
        }
    }
}
struct SiteFeed: Equatable, Sendable {
    let profile: ProfileID
    var fetchedAt: Instant
    var badge: Int
    var subtitle: String
}

extension Work {
    mutating func siteTools(_ command: SiteToolsCommand, in window: WindowID) {
        guard let w = state.doc.windows[window], w.kind == .standard, let space = state.doc.spaces[w.space] else { return }
        var folder: ItemID?
        let kind: SiteRequestKind
        switch command {
        case .connectGitHub(let favorite):
            if let favorite { guard state.role(of: favorite)?.kind == .favorites, state.doc.tree[favorite] != nil else { return } }
            kind = .github(repository: nil, favorite: favorite)
        case .refreshFolder(let id):
            guard case .folder(let f)? = state.doc.tree[id]?.body, let repository = f.liveRepository,
                  state.role(of: id)?.space == space.id else { return }
            folder = id
            state.session.liveFolderStatus[id] = "Refreshing…"
            kind = .github(repository: repository, favorite: nil)
        case .connectCalendar: kind = .calendar(join: false)
        case .joinMeeting:
            if let feed = state.session.calendars[space.profile], ctx.now.since(feed.fetchedAt) < .seconds(300) {
                joinNextMeeting(feed.meetings, in: window)
                return
            }
            kind = .calendar(join: true)
        }
        let request = SiteRequest(id: ctx.newID(), window: window, profile: space.profile, kind: kind)
        let pending = PendingSiteRequest(request: request, folder: folder, space: space.id)
        // One current request owns a shared target even when another window starts its refresh.
        state.session.siteRequests = state.session.siteRequests.filter {
            $0.value.request.window != window && $0.value.target != pending.target
        }
        state.session.siteRequests[request.id] = pending
        effects.append(.siteRequest(request))
        toast("Loading selected source…", in: window)
    }
    mutating func siteResult(_ id: String, _ outcome: SiteOutcome) {
        guard let pending = state.session.siteRequests.removeValue(forKey: id), state.siteRequestIsCurrent(pending),
              let w = state.doc.windows[pending.request.window] else { return }
        let window = w.id
        switch outcome {
        case .cancelled:
            if let folder = pending.folder { state.session.liveFolderStatus[folder] = "Refresh cancelled" }
            toast("Source selection cancelled", in: window)
        case .failed(let message):
            if let folder = pending.folder { state.session.liveFolderStatus[folder] = "Could not refresh. " + message }
            toast(message, in: window)
        case .unread(_, let count):
            guard case .github(_, let favorite?) = pending.request.kind, state.role(of: favorite)?.kind == .favorites else { return }
            state.session.favoriteFeeds[favorite] = SiteFeed(profile: pending.request.profile, fetchedAt: ctx.now, badge: max(0, count), subtitle: "Unread GitHub notifications (up to 50) · updated now")
            toast("Favorite updated", in: window)
        case .calendar(let meetings):
            state.session.calendars[pending.request.profile] = CalendarFeed(fetchedAt: ctx.now, meetings: meetings)
            if case .calendar(join: true) = pending.request.kind { joinNextMeeting(meetings, in: window) }
            else { toast("Calendar updated. Refresh by selecting the file again.", in: window) }
        case .pullRequests(let repository, let links):
            guard repository.split(separator: "/").count == 2, links.count <= 100,
                  links.allSatisfy({ ($0.url.scheme == "https" && $0.url.host == "github.com") || ($0.url.scheme == "http" && ["127.0.0.1", "localhost"].contains($0.url.host ?? "")) }) else { toast("Invalid GitHub response", in: window); return }
            guard let space = state.doc.spaces[w.space] else { return }
            let folder = pending.folder ?? ItemID(ctx.newID())
            if pending.folder == nil {
                var payload = Folder(title: repository, collapsed: false, icon: .named(.code))
                payload.liveRepository = repository
                do { try state.doc.tree.insert(folder, .folder(payload), at: .into(parent: space.pinnedRoot, index: 0), createdAt: ctx.now) } catch { return }
            }
            guard case .folder(let f)? = state.doc.tree[folder]?.body, f.liveRepository == repository else { return }
            // Keep IDs for unchanged URLs. New items remain lazy until explicitly selected.
            let wanted = Set(links.map(\.url))
            for child in state.doc.tree[folder]?.children ?? [] where state.tab(child)?.url.map({ !wanted.contains($0) }) ?? true {
                _ = removeItem(child)
                unload(child)
            }
            for (index, link) in links.enumerated() {
                let existing = (state.doc.tree[folder]?.children ?? []).first { state.tab($0)?.url == link.url }
                if let existing {
                    state.doc.tree.updateTab(existing) { $0.title = link.title }
                    _ = moveItem(existing, to: .into(parent: folder, index: index))
                } else {
                    let id = ItemID(ctx.newID())
                    try? state.doc.tree.insert(id, .tab(Tab(url: link.url, title: link.title, lastActiveAt: ctx.now)), at: .into(parent: folder, index: index), createdAt: ctx.now)
                }
            }
            state.session.liveFolderUpdated[folder] = ctx.now
            state.session.liveFolderStatus[folder] = links.isEmpty ? "No open pull requests" : "\(links.count) open pull requests · updated now"
            reveal(folder, in: window)
            toast("GitHub folder updated", in: window)
        }
    }
    private mutating func joinNextMeeting(_ meetings: [CalendarMeeting], in window: WindowID) {
        let next = meetings.filter { $0.end > ctx.now && $0.start <= ctx.now.advanced(by: .seconds(86_400)) }
            .sorted { $0.start < $1.start }.first
        guard let next, next.url.scheme == "https", let space = state.doc.windows[window]?.space else {
            toast("No available meeting in the next 24 hours", in: window)
            return
        }
        _ = openTab(next.url, inSpace: space, window: window, focus: true)
    }
}
struct CalendarFeed: Equatable, Sendable {
    var fetchedAt: Instant
    var meetings: [CalendarMeeting]
}

extension AppState {
    func siteRequestIsCurrent(_ pending: PendingSiteRequest) -> Bool {
        let request = pending.request
        guard let window = doc.windows[request.window], window.kind == .standard,
              doc.spaces[window.space]?.profile == request.profile, doc.profiles[request.profile] != nil else { return false }
        switch pending.target {
        case .folder(let id):
            guard let space = role(of: id)?.space, doc.spaces[space]?.profile == request.profile,
                  case .folder(let folder)? = doc.tree[id]?.body,
                  case .github(let repository?, _) = request.kind else { return false }
            return folder.liveRepository == repository
        case .favorite(let id): return role(of: id) == .favorites(request.profile)
        case .calendar: return true
        case .newFolder: return window.space == pending.space
        }
    }
}
