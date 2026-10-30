import BrkBase
import BrkDomain
import BrkUIKit
import Foundation

/// Owner: W4. One command bar result and the command it dispatches when chosen. Choosing a result is just
/// dispatching that command, so the bar has no behavior of its own.
public struct Suggestion: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case openTyped, switchToTab, history, action }
    public let kind: Kind
    public let title: String
    public let subtitle: String?
    public let symbol: String?
    public let command: Command
}

public enum Suggest {
    /// Ranks results for `query`, at most Metrics.commandBar.maxVisibleRows (Arc shows 5; the Electron version
    /// showed 8). Order, as the Electron `suggest.test.ts` spec has it (SuggestSpecTests):
    /// 1. open tabs whose title or URL matches (`.tab(.focus(id))`), never the focused one; word-start matches
    ///    before mid-word; with an empty query in view order without the focused tab;
    /// 2. "open what you typed" (`.commandBar(.submit(trimmed))`) when the query is non-blank; a typed URL that is
    ///    also in history shows once, as this row;
    /// 3. history entries (`.commandBar(.submit(url))`), newest first, one row per URL, none that an open tab has;
    /// 4. actions with a command bar listing whose title or triggers match (`action.spec.command`), carrying the
    ///    formatted first key.
    /// Matching is case- and diacritic-insensitive on titles and URLs.
    public static func rank(query: String, bar: CommandBarSnapshot, appName: String) -> [Suggestion] {
        fatalError("not implemented")
    }
}
