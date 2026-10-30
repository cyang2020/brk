import AppKit
import BrkBase
import BrkDomain

// The overlay views' colors, numbers and copy that the shared tables do not have yet. Each number is a `Metric`
// with its source, like the rows of `Metrics`, and each string says where it came from, so the integrator can move
// these groups into BrkBase/Metrics.swift and BrkUIKit's `Copy` unchanged (W4 report, deviations).

/// Arc's popover and command bar colors for one scheme (visual-and-copy.md: "Base tokens", "Text colors", the
/// ARC_CommandBar table, "Content area background and corners").
struct OverlayColors {
    /// PopoverBackground #FAFBFF / #151C30 (P3).
    let popover: NSColor
    /// PopoverShadow #151C32 @ 0.3 / 0.8.
    let popoverShadow: NSColor
    /// CommandBarTextPrimaryColor black / white @ 0.8.
    let textPrimary: NSColor
    /// CommandBarTextSecondaryColor black / white @ 0.33.
    let textSecondary: NSColor
    /// CommandBarPlaceholderPlaceholderText @ 0.3.
    let placeholder: NSColor
    /// CommandBarRowHoverBackgroundColor black / white @ 0.05: the highlighted row.
    let rowHighlight: NSColor
    /// CommandBarHairlineDividerColor black / white @ 0.1.
    let hairline: NSColor
    /// CommandBarSuggestionHintPillText #458AFF / #FAFBFF @ 0.33 ("Switch to Tab").
    let hintPillText: NSColor
    /// CommandBarAccessoryBackgroundColor black / white @ 0.05 and ForegroundColor @ 0.5 / white @ 0.66 (key hints).
    let accessoryBackground: NSColor
    let accessoryForeground: NSColor
    /// FocusRing #458AFF (P3), both schemes: the chosen swatch.
    let focusRing: NSColor
    /// PreviewBackgroundColor #FFFFFF / #212222: the archive page inside the content card.
    let page: NSColor
    /// ForegroundPrimary / Secondary / Tertiary.
    let foregroundPrimary: NSColor
    let foregroundSecondary: NSColor
    let foregroundTertiary: NSColor
    /// PrimaryButton #3139FB (P3).
    let primaryButton: NSColor

    static func of(_ scheme: Scheme) -> OverlayColors {
        let ink: NSColor = scheme == .light ? .black : .white
        let accent = NSColor(displayP3Red: 0x45 / 255.0, green: 0x8A / 255.0, blue: 0xFF / 255.0, alpha: 1)
        return OverlayColors(
            popover: scheme == .light ? p3(0xFAFBFF) : p3(0x151C30),
            popoverShadow: srgb(0x151C32, alpha: scheme == .light ? 0.3 : 0.8),
            textPrimary: ink.withAlphaComponent(0.8),
            textSecondary: ink.withAlphaComponent(0.33),
            placeholder: ink.withAlphaComponent(0.3),
            rowHighlight: ink.withAlphaComponent(0.05),
            hairline: ink.withAlphaComponent(0.1),
            hintPillText: scheme == .light ? accent : p3(0xFAFBFF, alpha: 0.33),
            accessoryBackground: ink.withAlphaComponent(0.05),
            accessoryForeground: scheme == .light ? ink.withAlphaComponent(0.5) : ink.withAlphaComponent(0.66),
            focusRing: accent,
            page: scheme == .light ? .white : srgb(0x212222),
            foregroundPrimary: scheme == .light ? p3(0x0E0F10, alpha: 0.9) : ink.withAlphaComponent(0.8),
            foregroundSecondary: ink.withAlphaComponent(0.5),
            foregroundTertiary: ink.withAlphaComponent(0.3),
            primaryButton: p3(0x3139FB)
        )
    }

    private static func p3(_ hex: Int, alpha: Double = 1) -> NSColor {
        NSColor(displayP3Red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func srgb(_ hex: Int, alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension NSAppearance {
    /// Aqua or Dark Aqua for a theme scheme, so AppKit and SwiftUI controls inside an overlay match its colors.
    static func of(_ scheme: Scheme) -> NSAppearance? {
        NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
    }
}

/// The overlay views' numbers that layout-constants.md does not have (the command bar's radius, fonts and shadow
/// were passed in at run time and not recovered; the archive page and the space dialog were not measured).
let OverlayMetrics = OverlayMetricsTable()

struct OverlayMetricsTable: MetricGroup {
    let commandBar = CommandBarOverlayMetrics()
    let archive = ArchiveOverlayMetrics()
    let dialog = DialogOverlayMetrics()
}

struct CommandBarOverlayMetrics: MetricGroup {
    let cornerRadius = Metric(Metrics.urlPill.cornerRadius.value, .derived(
        rule: "the URL pill's radius, so the bar opened over the pill covers it edge to edge",
        from: ["URL pill corner radius"]))
    let rowInset = Metric(6.0, .guess("highlighted row inset from the card edge, half the content inset 12"))
    let rowCornerRadius = Metric(6.0, .guess("card radius 12 minus the row inset 6, so the highlight's corners nest in the card's"))
    let inputFontSize = Metric(18.0, .guess("input text size; Arc's fonts were passed in at run time"))
    let titleFontSize = Metric(14.0, .guess("result title size"))
    let hintFontSize = Metric(11.0, .guess("hint pill and key hint text size"))
    let iconSize = Metric(16.0, .guess("favicon and SF Symbol size in a result row"))
    let hintPadding = Metric(6.0, .guess("horizontal padding inside a hint pill"))
    let hintHeight = Metric(20.0, .guess("hint pill height"))
    let hintRadius = Metric(5.0, .guess("hint pill corner radius"))
    let shadowRadius = Metric(24.0, .guess("popover shadow blur; the color is PopoverShadow"))
    let shadowOffset = Metric(8.0, .guess("popover shadow drop"))
    /// A spring from Metrics.commandBar.openBounceFrom to 1 (Arc: `arc_commandBarBounce`, scale only, no fade).
    let bounceStiffness = Metric(420.0, .guess("spring stiffness of the opening bounce; settles in about 0.3 s"))
    let bounceDamping = Metric(22.0, .guess("spring damping of the opening bounce; one small overshoot"))
}

struct ArchiveOverlayMetrics: MetricGroup {
    let columnMaxWidth = Metric(760.0, .guess("readable width of the archive list inside a wide content card"))
    let padding = Metric(32.0, .guess("archive page margin inside the content card"))
    let titleFontSize = Metric(26.0, .guess("\"Archive\" title size"))
    let headerHeight = Metric(40.0, .guess("title row height"))
    let toolbarHeight = Metric(28.0, .guess("filter, threshold and Clear row height"))
    let filterWidth = Metric(240.0, .guess("filter field width"))
    let gap = Metric(12.0, .guess("space between toolbar controls and between sections"))
    let groupHeaderHeight = Metric(36.0, .guess("bucket header height"))
    let groupFontSize = Metric(13.0, .guess("bucket header text size"))
    let entryHeight = Metric(44.0, .guess("archive entry row height: title over URL"))
    let entryTitleFontSize = Metric(13.0, .guess("archive entry title size"))
    let entryDetailFontSize = Metric(11.0, .guess("archive entry URL and time size"))
    let faviconSize = Metric(16.0, .guess("favicon size in an archive entry"))
    let entryCornerRadius = Metric(8.0, .guess("archive entry hover background radius"))
}

struct DialogOverlayMetrics: MetricGroup {
    let width = Metric(420.0, .guess("space dialog width"))
    let cornerRadius = Metric(Metrics.urlPill.cornerRadius.value, .derived(
        rule: "same popover radius as the command bar", from: ["URL pill corner radius"]))
    let padding = Metric(20.0, .guess("space dialog inner margin"))
    let previewHeight = Metric(64.0, .guess("live theme preview tile height"))
    let swatchSize = Metric(24.0, .guess("preset swatch diameter; nine fit one row of the dialog"))
    let iconButtonSize = Metric(28.0, .guess("icon choice button size"))
}

/// Copy the overlay views use that BrkUIKit's `Copy` does not have yet. Observed strings are Arc's
/// (visual-and-copy.md section 3); the short labels Arc keeps in code did not survive and are marked GUESS, the
/// same choices as electron-v1 `src/shared/copy.ts`.
enum OverlayCopy {
    /// Observed caption.
    static let switchToTab = "Switch to Tab"
    /// GUESS: the verb on the "search or navigate what you typed" row.
    static let searchVerb = "Search"
    static let openVerb = "Open"

    /// Observed: "Opens the Archive, where all your closed tabs live." The page title is a GUESS (short label).
    static let archiveTitle = "Archive"
    /// Observed.
    static let archiveFilter = "Filter Archived Tabs"
    static let clearArchive = "Clear Archive"
    static let archiveThreshold = "Archive tabs after"
    /// GUESS (short labels).
    static let restore = "Restore"
    static let close = "Close"
    static let cancel = "Cancel"
    static let noMatch = "No archived tabs match your filter."

    /// "Earlier This Week" observed; the others GUESS (Arc's buckets are enum names only).
    static func bucket(_ bucket: ArchiveBucket) -> String {
        switch bucket {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .pastWeek: "Earlier This Week"
        case .pastMonth: "Past Month"
        case .beyond: "Beyond"
        }
    }

    /// Inferred from the comments "Auto archive threshold; 12 hours" and so on; the visible labels live in code.
    static func threshold(_ threshold: AutoArchiveThreshold) -> String {
        switch threshold {
        case .oneHour: "1 hour"
        case .sixHours: "6 hours"
        case .twelveHours: "12 hours"
        case .twentyFourHours: "24 hours"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .never: "Never"
        }
    }

    /// GUESS: Arc's reasons are enum names only (the filter asks "How was the tab closed?").
    static func reason(_ reason: ArchiveReason) -> String {
        switch reason {
        case .manual: "Closed"
        case .auto: "Auto-archived"
        case .clearToday: "Cleared from Today"
        case .containerDeleted: "Folder or Space deleted"
        }
    }

    /// "New Space" is the observed menu title without the ellipsis; the rest GUESS (short labels).
    static let newSpaceTitle = "New Space"
    static let editSpaceTitle = "Edit Space"
    static let spaceName = "Name"
    static let spaceNamePlaceholder = "Space Name"
    static let icon = "Icon"
    static let emojiPlaceholder = "Emoji"
    static let color = "Color"
    static let createSpace = "Create Space"
    static let save = "Save"
    /// Observed: "Default Space Icon", "Set space color to ", "Cycle noise texture" (tooltip), "Automatic
    /// Appearance", "Light Appearance".
    static let noIcon = "Default Space Icon"
    static func setColor(_ hex: String) -> String { "Set space color to \(hex)" }
    static let texture = "Cycle noise texture"
    /// GUESS (short labels on the editor's controls).
    static let wheel = "Colors"
    static let noise = "Noise"
    static let intensity = "Intensity"
    static let appearance = "Appearance"
    static func wheelName(_ wheel: ColorWheel) -> String {
        switch wheel {
        case .analogous: "Analogous"
        case .complementary: "Complementary"
        }
    }
    static func textureName(_ texture: Texture) -> String { texture.rawValue.capitalized }
    static func appearanceName(_ choice: AppearanceChoice) -> String {
        switch choice {
        case .auto: "Automatic Appearance"
        case .light: "Light Appearance"
        case .dark: "Dark Appearance"   // GUESS, by analogy
        }
    }
}

/// SF Symbols for Arc's named icons. W3's dock draws the same names; one table in BrkUIKit would serve both.
enum NamedIconSymbol {
    static func of(_ icon: NamedIcon) -> String {
        switch icon {
        case .star: "star.fill"
        case .bookmark: "bookmark.fill"
        case .heart: "heart.fill"
        case .flag: "flag.fill"
        case .folder: "folder.fill"
        case .calendar: "calendar"
        case .mail: "envelope.fill"
        case .terminal: "terminal.fill"
        case .egg: "oval.portrait.fill"
        case .home: "house.fill"
        case .briefcase: "briefcase.fill"
        case .book: "book.fill"
        case .camera: "camera.fill"
        case .music: "music.note"
        case .globe: "globe"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
}
