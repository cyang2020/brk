import BrkBase
import Foundation

// Owner: R3-6. Arc's "top apps" (anatomy-m 1.6 `TopApp`, ARC_AppTray): the sites whose Favorite tile or Pinned row
// carries more than the favicon. A tile shows at most one overlay (`AppTrayItemOverlay`: `subtitle(...)` or
// `badge(NSColor)`): the time to the next meeting under a calendar, or an unread dot in the site's badge color.
// Hovering a supported Favorite or Pinned tab with Arc Previews on shows that site's card (Arc's `HoverCards`).
// The context menu turns each off per site ("Show Unread Badge", "Show Time to Next Meeting", "Show Hover Preview";
// `topAppsBadgingDisabledHosts`, `topAppsSubtitleDisabledHosts`).

/// The sites Arc treats specially, by host. Mail sites have no Brk data source (no account sign-in), so they
/// get neither a badge nor a card.
public enum TopApp: String, Hashable, Sendable, Codable, CaseIterable {
    case gmail, gcal, outlookMail, outlookCalendar, notionCalendar, github, whatsapp, twitter, linear, notion, figma

    public static func of(_ url: URL?) -> TopApp? {
        guard let url, let raw = url.host?.lowercased() else { return nil }
        let host = raw.hasPrefix("www.") ? String(raw.dropFirst(4)) : raw
        switch host {
        case "mail.google.com": return .gmail
        case "calendar.google.com": return .gcal
        case "outlook.office.com", "outlook.live.com", "outlook.office365.com":
            return url.path.lowercased().hasPrefix("/calendar") ? .outlookCalendar : .outlookMail
        case "calendar.notion.so", "calendar.notion.com": return .notionCalendar
        case "github.com": return .github
        case "web.whatsapp.com": return .whatsapp
        case "twitter.com", "x.com": return .twitter
        case "linear.app": return .linear
        case "notion.so", "notion.com": return .notion
        case "figma.com": return .figma
        default: return nil
        }
    }

    /// The host the per-site switches are kept under (Arc keys them by host).
    public static func key(_ url: URL?) -> String? {
        guard let raw = url?.host?.lowercased() else { return nil }
        return raw.hasPrefix("www.") ? String(raw.dropFirst(4)) : raw
    }

    public var isCalendar: Bool { [.gcal, .outlookCalendar, .notionCalendar].contains(self) }

    /// ARC_AppTray's badge colors (visual-and-copy.md: GithubBadgeBlack, GMailBadgeRed, WhatsAppBadgeRed,
    /// TwitterBadgeGray). Only GitHub has a Brk source; the others keep their color for when one exists.
    public var badgeTint: BadgeTint? {
        switch self {
        case .github: .black
        case .gmail, .whatsapp: .red
        case .twitter: .gray
        default: nil
        }
    }

    /// The card Arc's Previews show for this site ("Show Arc Previews:" lists the calendars, the mail sites and
    /// "Recent pages on Linear, Notion, and Figma").
    public var preview: HoverCardKind? {
        switch self {
        case .gcal, .outlookCalendar, .notionCalendar: .calendar
        case .linear, .notion, .figma: .recentPages
        case .gmail, .outlookMail, .github, .whatsapp, .twitter: nil
        }
    }

    public var name: String {
        switch self {
        case .gmail: "Gmail"
        case .gcal: "Google Calendar"
        case .outlookMail: "Outlook"
        case .outlookCalendar: "Outlook Calendar"
        case .notionCalendar: "Notion Calendar"
        case .github: "GitHub"
        case .whatsapp: "WhatsApp"
        case .twitter: "X"
        case .linear: "Linear"
        case .notion: "Notion"
        case .figma: "Figma"
        }
    }
}

public enum BadgeTint: String, Hashable, Sendable, Codable { case black, red, gray }
public enum HoverCardKind: String, Hashable, Sendable, Codable { case calendar, recentPages }

/// The per-site switches in a Favorite's or Pinned tab's context menu.
public enum SiteDisplayOption: String, Hashable, Sendable, Codable, CaseIterable {
    /// "Show Unread Badge".
    case unreadBadge
    /// "Show Time to Next Meeting".
    case nextMeeting
    /// "Show Hover Preview".
    case hoverPreview

    public var title: String {
        switch self {
        case .unreadBadge: "Show Unread Badge"
        case .nextMeeting: "Show Time to Next Meeting"
        case .hoverPreview: "Show Hover Preview"
        }
    }
}

/// What a supported tab shows on hover. Calendars list the coming meetings with Join; Linear, Notion and Figma list
/// the pages visited on that site most recently.
public enum HoverCardSnapshot: Hashable, Sendable, Codable {
    case calendar(site: String, meetings: [HoverMeeting])
    case recentPages(site: String, pages: [HoverPage])
}

public struct HoverMeeting: Hashable, Sendable, Codable {
    public var title: String
    public var start: Instant
    public var end: Instant
    /// The meeting's link when it is one Join may open (https).
    public var joinURL: URL?
    public init(title: String, start: Instant, end: Instant, joinURL: URL?) { self.title = title; self.start = start; self.end = end; self.joinURL = joinURL }
}

public struct HoverPage: Hashable, Sendable, Codable {
    public var title: String
    public var url: URL
    public var visitedAt: Instant
    public init(title: String, url: URL, visitedAt: Instant) { self.title = title; self.url = url; self.visitedAt = visitedAt }
}

public enum TopAppCopy {
    /// The calendar tile's subtitle (`AppTrayItemSubtitleConfiguration.subtitle`, "Show Time to Next Meeting"):
    /// "Now" while a meeting runs, else the time until the next one that starts within a day. GUESS: Arc's exact
    /// wording was not recovered from static strings; the parent compares with P08 once Arc's tile is captured.
    public static func timeToNextMeeting(_ meetings: [CalendarMeeting], now: Instant) -> String? {
        guard let next = meetings.filter({ $0.end > now }).min(by: { $0.start < $1.start }) else { return nil }
        if next.start <= now { return "Now" }
        let minutes = Int((next.start.milliseconds - now.milliseconds + 59_999) / 60_000)
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60
        return hours < 24 ? "in \(hours)h" : nil
    }

    /// Header of the calendar card.
    public static let upcoming = "Upcoming"
    public static let join = "Join"
    public static func searchSite(_ site: String) -> String { "Search \(site)…" }
}

/// Most Linear, Notion and Figma pages a card lists; how far ahead the calendar card looks.
let hoverPageLimit = 6
let hoverMeetingLimit = 5

extension AppState {
    /// The tab's top-app overlay and card. `favorite` is false for Pinned rows, which get the card but no overlay
    /// (Arc's overlay belongs to the favorites tray).
    func topAppDecoration(_ row: inout TabRow, tab: ItemID, url: URL?, profile: ProfileID, favorite: Bool, now: Instant) {
        guard let app = TopApp.of(url), let host = TopApp.key(url) else { return }
        let prefs = doc.tabPreferences
        if favorite {
            if app.isCalendar, !prefs.subtitleHiddenHosts.contains(host), let feed = session.calendars[profile], feed.access == .ready,
               now.since(feed.fetchedAt) < .seconds(300) {
                row.subtitle = TopAppCopy.timeToNextMeeting(feed.meetings, now: now)
            }
            if row.subtitle == nil, let tint = app.badgeTint, let count = row.badge, count > 0, !prefs.badgeHiddenHosts.contains(host) {
                row.badgeTint = tint
            }
        }
        guard prefs.hoverPreviews, !prefs.previewHiddenHosts.contains(host), let kind = app.preview else { return }
        switch kind {
        case .calendar:
            guard let feed = session.calendars[profile], feed.access == .ready, now.since(feed.fetchedAt) < .seconds(300) else { return }
            let meetings = feed.meetings.filter { $0.end > now && $0.start <= now.advanced(by: .seconds(86_400)) }
                .sorted { $0.start < $1.start }.prefix(hoverMeetingLimit)
                .map { HoverMeeting(title: $0.title, start: $0.start, end: $0.end, joinURL: $0.url.scheme == "https" ? $0.url : nil) }
            row.hoverCard = .calendar(site: app.name, meetings: Array(meetings))
        case .recentPages:
            var seen: Set<String> = [url?.absoluteString ?? ""]
            let pages = doc.history.filter { $0.profile == profile && TopApp.key($0.url) == host }
                .sorted { $0.visitedAt > $1.visitedAt }
                .filter { seen.insert($0.url.absoluteString).inserted }
                .prefix(hoverPageLimit)
                .map { HoverPage(title: $0.title.isEmpty ? $0.url.absoluteString : $0.title, url: $0.url, visitedAt: $0.visitedAt) }
            if !pages.isEmpty { row.hoverCard = .recentPages(site: app.name, pages: Array(pages)) }
        }
    }

    /// The context menu's per-site switches for a Favorite (all that apply) or a Pinned tab (the card only).
    func siteDisplayEntries(url: URL?, favorite: Bool, item: ItemID? = nil) -> [MenuEntry] {
        guard let app = TopApp.of(url), let host = TopApp.key(url) else { return [] }
        let prefs = doc.tabPreferences
        var entries: [MenuEntry] = []
        // Brk's sources (Arc reads the signed-in site): a GitHub Favorite connects its notifications, a calendar
        // reads a selected .ics export.
        if favorite, app == .github, let item {
            entries.append(.action(title: "Connect GitHub Notifications…", command: .tabTools(.site(.connectGitHub(favorite: item))), enabled: true))
        }
        if app.isCalendar {
            entries.append(.action(title: "Select Calendar Export…", command: .tabTools(.site(.connectCalendar)), enabled: true))
        }
        if favorite, app.badgeTint != nil {
            let on = !prefs.badgeHiddenHosts.contains(host)
            entries.append(.choice(title: SiteDisplayOption.unreadBadge.title, command: .tabTools(.siteDisplay(host: host, .unreadBadge, on: !on)), on: on))
        }
        if favorite, app.isCalendar {
            let on = !prefs.subtitleHiddenHosts.contains(host)
            entries.append(.choice(title: SiteDisplayOption.nextMeeting.title, command: .tabTools(.siteDisplay(host: host, .nextMeeting, on: !on)), on: on))
        }
        if app.preview != nil, prefs.hoverPreviews {
            let on = !prefs.previewHiddenHosts.contains(host)
            entries.append(.choice(title: SiteDisplayOption.hoverPreview.title, command: .tabTools(.siteDisplay(host: host, .hoverPreview, on: !on)), on: on))
        }
        return entries
    }
}

extension Work {
    mutating func siteDisplay(host: String, _ option: SiteDisplayOption, on: Bool) {
        let key = host.lowercased()
        guard !key.isEmpty else { return }
        func set(_ hidden: inout Set<String>) { if on { hidden.remove(key) } else { hidden.insert(key) } }
        switch option {
        case .unreadBadge: set(&state.doc.tabPreferences.badgeHiddenHosts)
        case .nextMeeting: set(&state.doc.tabPreferences.subtitleHiddenHosts)
        case .hoverPreview: set(&state.doc.tabPreferences.previewHiddenHosts)
        }
    }
}
