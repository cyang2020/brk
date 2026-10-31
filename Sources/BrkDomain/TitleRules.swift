import Foundation

/// Exact host and suffix rules. User titles are resolved before these rules by the projection.
public enum TitleRules {
    public static func shorten(_ title: String, url: URL?) -> String {
        guard let host = url?.host?.lowercased() else { return title }
        let suffixes: [String]
        switch host {
        case "github.com": suffixes = [" · GitHub"]
        case "youtube.com", "www.youtube.com": suffixes = [" - YouTube"]
        case "docs.google.com": suffixes = [" - Google Docs", " - Google Sheets", " - Google Slides"]
        case "calendar.google.com": suffixes = [" - Google Calendar"]
        case "mail.google.com": suffixes = [" - Gmail"]
        default: return title
        }
        for suffix in suffixes where title.hasSuffix(suffix) {
            let candidate = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty { return candidate }
        }
        return title
    }
}
