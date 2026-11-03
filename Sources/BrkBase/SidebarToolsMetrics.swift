import CoreGraphics

/// Existing tray (47 pt), pill (36 pt, radius 12) and content (10 pt inset, radius 6) use recovered Arc
/// constants. Badge, preview and glow details below are Brk choices; no matching Arc pixels are available.
public struct SidebarToolsMetrics: MetricGroup {
    /// Arc's favorites overlay (`AppTrayItemOverlay`: `badge(NSColor)` or `subtitle(...)`): a dot or a capsule.
    public let unreadDot = Metric(8.0, .guess("unread dot on the favicon's top-right corner; Arc's AppTrayItemBadgeView size was not traced (P08 pending)"))
    public let subtitleHeight = Metric(14.0, .guess("calendar subtitle capsule height inside the 47 pt tile (P08 pending)"))
    public let subtitlePadding = Metric(4.0, .guess("calendar subtitle capsule side padding beyond the label cell's own 2 pt"))
    public let subtitleFont = Metric(9.0, .guess("calendar subtitle text size; fits 'in 45m' in the narrowest tile"))
    public let subtitleInset = Metric(2.0, .guess("the capsule never touches the tile's sides"))
    public let subtitleBottom = Metric(4.0, .guess("capsule gap above the tile's bottom edge"))
    public let subtitleIconTop = Metric(8.0, .guess("favicon moves up so the capsule fits under it"))
    public let glowRadius = Metric(2.0, .guess("soft progress line inside the existing URL pill"))
    public let glowHeight = Metric(3.0, .guess("visible halo without changing the recovered 36 point pill geometry"))
    public let glowBlur = Metric(8.0, .guess("diffuse glow around real progress; Arc shader geometry unrecovered"))
    public let glowDuration = Metric(0.12, .guess("short interpolation between Chromium progress readings"))
    public let previewSize = Metric(CGSize(width: 330, height: 180), .guess("room for title, URL, error and summary action"))
    public let previewButtonRadius = Metric(11.0, .guess("Summarize capsule on the link preview card; Arc's 5-Second Previews card was not captured"))
    public let previewHoverDelay = Metric(0.65, .guess("deliberate hover delay; anatomy has no recovered preview delay"))
    public let sadIllustration = Metric(CGSize(width: 96, height: 104), .guess("original sad document illustration; Arc SadTab asset not available"))
    public let sadMessageWidth = Metric(360.0, .guess("readable two-line crash explanation at ordinary window sizes"))
}
