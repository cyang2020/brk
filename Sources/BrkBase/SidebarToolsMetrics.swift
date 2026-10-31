import CoreGraphics

/// Existing tray (47 pt), pill (36 pt, radius 12) and content (10 pt inset, radius 6) use recovered Arc
/// constants. Badge, preview and glow details below are Brk choices; no matching Arc pixels are available.
public struct SidebarToolsMetrics: MetricGroup {
    public let sourceRadius = Metric(3.0, .guess("six point source-state dot fits the minimum Favorite tile"))
    public let unreadRadius = Metric(8.0, .guess("sixteen point unread badge, GitHub black from visual-and-copy.md"))
    public let glowRadius = Metric(2.0, .guess("soft progress line inside the existing URL pill"))
    public let glowHeight = Metric(3.0, .guess("visible halo without changing the recovered 36 point pill geometry"))
    public let glowBlur = Metric(8.0, .guess("diffuse glow around real progress; Arc shader geometry unrecovered"))
    public let glowDuration = Metric(0.12, .guess("short interpolation between Chromium progress readings"))
    public let previewSize = Metric(CGSize(width: 330, height: 180), .guess("room for title, URL, error and summary action"))
    public let previewHoverDelay = Metric(0.65, .guess("deliberate hover delay; anatomy has no recovered preview delay"))
    public let sadIllustration = Metric(CGSize(width: 96, height: 104), .guess("original sad document illustration; Arc SadTab asset not available"))
    public let sadMessageWidth = Metric(360.0, .guess("readable two-line crash explanation at ordinary window sizes"))
}
