import CoreGraphics
import Foundation

public struct SpaceToolsMetrics: MetricGroup {
    public let folderExportSize = Metric(CGSize(width: 580, height: 250), .guess("folder export sheet fits an editable path, browse, validation and confirmation controls"))
    public let folderExportPadding = Metric(20.0, .guess("native export form margin"))
    public let folderExportSpacing = Metric(12.0, .guess("separation between native export form rows"))
    public let folderExportTitle = Metric(18.0, .guess("native export sheet heading size"))
    public let toolbarHeight = Metric(44.0, .guess("address toolbar height leaves a 32 pt control and card gap; no authenticated reference"))
    public let controlSize = Metric(32.0, .guess("toolbar navigation controls reuse the existing title-row scale"))
    public let controlPitch = Metric(34.0, .guess("two points between 32 point toolbar buttons"))
    public let toolbarAddressLeading = Metric(140.0, .guess("four navigation controls before the toolbar address"))
    public let toolbarRadius = Metric(8.0, .guess("toolbar address rounding matches small library controls"))
    public let managerPadding = Metric(24.0, .guess("readable Spaces manager margin within the Library page"))
    public let managerGap = Metric(14.0, .guess("space between manager cards"))
    public let managerCardMinWidth = Metric(230.0, .guess("width fits export and reorder controls without truncation"))
    public let managerCardHeight = Metric(220.0, .guess("height fits name, profile, edit, export and delete controls"))
    public let managerCardRadius = Metric(12.0, .guess("Spaces card grouping in the Library; no Arc pixel claim"))
    public let editorPadHeight = Metric(120.0, .guess("color-pad height within the existing space popover"))
    public let editorPointSize = Metric(22.0, .guess("color pad handle target and selected ring"))
}
