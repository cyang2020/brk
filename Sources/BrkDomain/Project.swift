import BrkBase
import Foundation

/// Inputs to the projection besides state: the clock's time and the calendar for archive buckets.
public struct ProjectionContext: Sendable {
    public let now: Instant
    public let calendar: Calendar
    public init(now: Instant, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
    }
}

/// The whole read side. Pure. Called by AppStore after every changing transition and on clock ticks (so archive
/// buckets and "now" stay right). Cost is O(items) per call; sidebars hold hundreds of rows, not millions.
///
/// Derivations that live only here (single source of truth):
/// - row status (current/visible/idle) from the window's shown item and split focus;
/// - row titles (custom title, page title, display URL, "New Tab");
/// - `pages`: every loaded tab of every window -> PageSpec(initialURL: tab.url, profile: space.profile);
/// - `focus`: overlay input > rename field > dialog > focused pane's page > none;
/// - `enabledActions`: which table actions apply (e.g. removeSplitView only with a split shown);
/// - command bar candidates (open tabs focused-first then by recency, history, `ActionID`s with a listing);
/// - archive groups by bucket (`archiveBucket`).
public func project(_ state: AppState, _ ctx: ProjectionContext) -> AppSnapshot {
    // TODO(W1): build each WindowSnapshot with projectWindow; collect pages app-wide (sorted by id, stable).
    fatalError("not implemented")
}

/// The bucket of an archive entry relative to `now` in `calendar`: today, yesterday, past week (7 days),
/// past month (30 days), beyond. Owner: W4 (archive).
public func archiveBucket(of archivedAt: Instant, now: Instant, calendar: Calendar) -> ArchiveBucket {
    fatalError("not implemented")
}
