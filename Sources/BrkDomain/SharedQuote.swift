import Foundation

/// Advanced > "Enable Shared Quotes when highlighting text." (Arc: `shareQuoteLinkEnabledPreference`; the URL pill's
/// `copyQuoteLink`, the command bar's "Copy Quote" and "Copy Link to Highlight"). Arc's quote cards live on its own
/// web service; Brk's quote is a link to the highlight itself, a text fragment (`#:~:text=`) that Chromium, Brk
/// included, scrolls to and highlights when the link is opened. With nothing highlighted, the copy is the plain one.
public enum SharedQuote {
    /// What Copy URL (`.plain`) or Copy URL as Quote (`.quote`) puts on the pasteboard for a page at `url` titled
    /// `title` with `selection` highlighted.
    public static func text(url: URL, title: String, selection: String?, format: CopyURLFormat) -> String {
        let quoted = selection.map(normalized) ?? ""
        guard !quoted.isEmpty, format != .markdown, let link = link(to: quoted, in: url) else { return plain(url: url, title: title, format: format) }
        switch format {
        case .plain, .markdown: return link.absoluteString
        case .quote: return "> \(quoted)\n\(link.absoluteString)"
        }
    }

    /// The copy without a highlight (what Copy URL always copies with Shared Quotes off).
    public static func plain(url: URL, title: String, format: CopyURLFormat) -> String {
        switch format {
        case .plain: url.absoluteString
        case .markdown: "[\(markdownTitle(title))](\(url.absoluteString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")))"
        case .quote: "> \(title)\n\(url.absoluteString)"
        }
    }

    /// `url` with a text directive for `text` (an earlier directive replaced). A long highlight is named by its
    /// first and last words (`text=start,end`), as Chromium's own Copy Link to Highlight does.
    public static func link(to text: String, in url: URL) -> URL? {
        let words = text.split(separator: " ")
        let directive = words.count > longQuoteWords
            ? encode(words.prefix(edgeWords).joined(separator: " ")) + "," + encode(words.suffix(edgeWords).joined(separator: " "))
            : encode(text)
        let base = url.absoluteString.components(separatedBy: ":~:").first ?? url.absoluteString
        let anchor = base.contains("#") ? base : base + "#"
        return URL(string: anchor + ":~:text=" + directive)
    }

    static let longQuoteWords = 10
    static let edgeWords = 5

    /// Whitespace runs (line breaks of a multi-line highlight included) become one space.
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Percent-encoding for a text directive: unreserved characters stay; '-', ',' and '&' are the syntax's own.
    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: directiveAllowed) ?? text
    }

    private static let directiveAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.!~*'()")
}
