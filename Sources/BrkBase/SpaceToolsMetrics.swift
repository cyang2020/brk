import CoreGraphics
import Foundation

public struct SpaceToolsMetrics: MetricGroup {
    public let folderExportSize = Metric(CGSize(width: 580, height: 250), .guess("folder export sheet fits an editable path, browse, validation and confirmation controls"))
    public let folderExportPadding = Metric(20.0, .guess("native export form margin"))
    public let folderExportSpacing = Metric(12.0, .guess("separation between native export form rows"))
    public let folderExportTitle = Metric(18.0, .guess("native export sheet heading size"))
    /// The toolbar is the top of the content card: 32 pt of controls over a 1 pt hairline, then the page.
    public let toolbarHeight = Metric(33.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-b: Arc's card top at 10, hairline at 42"))
    public let toolbarPageOverlap = Metric(1.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-b Arc capture: the page's text sits 1 pt higher than a page starting under the hairline, so the page starts at 42 and the hairline lies on it"))
    public let controlSize = Metric(32.0, .guess("toolbar navigation controls reuse the existing title-row scale"))
    /// Back, forward and reload centred 21, 58 and 95 from the card's left edge; the three right buttons centred
    /// 22, 58 and 94 from its right edge.
    public let controlPitch = Metric(37.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-b: toolbar glyph centres 37 apart"))
    public let toolbarControlInset = Metric(5.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-b: first and last 32 pt buttons 5 and 6 from the card edges"))
    public let toolbarRadius = Metric(8.0, .guess("toolbar address rounding matches small library controls"))
    public let managerPadding = Metric(24.0, .guess("readable Spaces manager margin within the Library page"))
    public let managerGap = Metric(14.0, .guess("space between manager cards"))
    public let managerCardMinWidth = Metric(230.0, .guess("width fits export and reorder controls without truncation"))
    public let managerCardHeight = Metric(220.0, .guess("height fits name, profile, edit, export and delete controls"))
    public let managerCardRadius = Metric(12.0, .guess("Spaces card grouping in the Library; no Arc pixel claim"))
    public let editorPadHeight = Metric(120.0, .guess("color-pad height within the existing space popover"))
    public let editorPointSize = Metric(22.0, .guess("color pad handle target and selected ring"))
}
