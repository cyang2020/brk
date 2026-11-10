import BrkBase
import Foundation

/// Brk's own site-engagement score. Arc ranks with Chromium's `SiteEngagementService`, which CEF does not expose; this
/// one counts the same two things Chromium's mainly counts: visits (half a point each, as Chromium gives a navigation)
/// and time on screen (a point per five minutes), capped at Chromium's 100.
public enum SiteEngagement {
    /// One stretch on screen counts at most this many seconds.
    public static let longestStretch: Double = 1_800

    /// "scheme://host" for a web page, nil otherwise.
    public static func site(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return "\(scheme)://\(host)"
    }

    public static func score(visits: Int, foregroundSeconds: Double) -> Double {
        min(100, 0.5 * Double(visits) + foregroundSeconds / 300)
    }
}

/// What the command bar's ranking reads from a profile's history: one row per page with its visit and typed counts, the
/// most visited pages, and each site's engagement.
struct CommandBarHistory {
    /// Chromium's most-visited list holds this many pages (Arc's missing value for the rank is 20).
    static let mostVisitedCount = 10

    var pages: [HistoryCandidate]
    var mostVisited: [URL]
    var engagement: [String: Double]

    /// `visits` newest first, all of one profile. Pages keep the newest visit's title and time, and `historyIndex`'s order
    /// and cap.
    init(visits: [HistoryEntry], foreground: [String: Double]) {
        var count: [URL: Int] = [:], typed: [URL: Int] = [:], siteVisits: [String: Int] = [:]
        for visit in visits {
            count[visit.url, default: 0] += 1
            if visit.typed { typed[visit.url, default: 0] += 1 }
            if let site = SiteEngagement.site(visit.url) { siteVisits[site, default: 0] += 1 }
        }
        pages = historyIndex(visits).map {
            HistoryCandidate(url: $0.url, title: $0.title, visitedAt: $0.visitedAt, visitCount: count[$0.url] ?? 1, typedCount: typed[$0.url] ?? 0)
        }
        mostVisited = pages.enumerated().sorted { a, b in
            a.element.visitCount != b.element.visitCount ? a.element.visitCount > b.element.visitCount : a.offset < b.offset
        }.prefix(Self.mostVisitedCount).map(\.element.url)
        var engagement: [String: Double] = [:]
        for site in Set(siteVisits.keys).union(foreground.keys) {
            engagement[site] = SiteEngagement.score(visits: siteVisits[site] ?? 0, foregroundSeconds: foreground[site] ?? 0)
        }
        self.engagement = engagement
    }
}
