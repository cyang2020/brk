import BrkBase
import BrkDomain
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
    /// Ranks results for `query`, at most Metrics.CommandBar.maxVisibleRows:
    /// 1. "open what you typed" (`.commandBar(.submit(query))`) when the query is non-empty;
    /// 2. open tabs whose title or URL contains the query (`.tab(.focus(id))`), current space first;
    /// 3. actions whose title or triggers match (`action.spec.command`);
    /// 4. history entries (`.commandBar(.submit(url))`), deduplicated against open tabs by URL.
    /// Case- and diacritic-insensitive prefix match on words beats substring match.
    public static func rank(query: String, bar: CommandBarSnapshot, appName: String) -> [Suggestion] {
        fatalError("not implemented")
    }
}
