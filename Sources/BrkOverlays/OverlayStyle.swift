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

/// The command bar's own colors (Arc 1.170, measured on the 2026-11-03 captures in verify/visual-pairs/run-20261103).
/// In a space's window the highlight and the text selection of both bars (Cmd+T, and Cmd+L over the URL pill) are shades
/// of the sidebar theme's primary color, grey under a white theme; a window without a space (blank, Little, incognito)
/// highlights in Arc's blue-violet (P20-a, P21-a, Q03-a). All follow the sidebar's scheme, not the system's (P29-c).
struct CommandBarColors {
    let card: NSColor
    let border: NSColor
    let text: NSColor
    let secondary: NSColor
    let placeholder: NSColor
    let highlight: NSColor
    /// Text, hints and arrows on the highlighted row.
    let onHighlight: NSColor
    let textSelection: NSColor
    let hairline: NSColor
    /// The Switch to Tab arrow's square, the Tab key and the Contact the Team tile; white on the highlighted row.
    let accessory: NSColor
    let accessoryText: NSColor
    let tileOnHighlight: NSColor
    let infoCircle: NSColor
    /// The magnifier beside the input (Q01-a, P49: pure black) and the glyphs in the rows (P49: #545454).
    let inputGlyph: NSColor
    let rowGlyph: NSColor

    static func of(_ scheme: Scheme, primary: RGBA, spaceless: Bool = false) -> CommandBarColors {
        let base = OverlayColors.of(scheme)
        let ink: NSColor = scheme == .light ? .black : .white
        guard scheme == .light else {
            // Q03-a (incognito): a neutral #191A1C card, the highlight #424ADD with a white tile under its glyph. P29-c (a
            // standard window in the system's dark appearance): a dark card over a blur, reading #2E3336 over the light
            // sidebar and #161818 over the page (this tint over the HUD material), a #565656 edge, the highlight
            // #676767, the selected address on #7B7B7B.
            return CommandBarColors(card: spaceless ? srgb(0x191A1C) : srgb(0x171919).withAlphaComponent(0.72),
                                    border: ink.withAlphaComponent(spaceless ? 0.12 : 0.27), text: base.textPrimary, secondary: base.textSecondary,
                                    placeholder: ink.withAlphaComponent(0.4), highlight: spaceless ? srgb(0x424ADD) : ink.withAlphaComponent(0.29),
                                    onHighlight: .white, textSelection: spaceless ? srgb(0x2E3485) : ink.withAlphaComponent(0.36), hairline: base.hairline,
                                    accessory: ink.withAlphaComponent(0.08), accessoryText: base.accessoryForeground,
                                    tileOnHighlight: spaceless ? .white : ink.withAlphaComponent(0.2), infoCircle: ink.withAlphaComponent(0.12),
                                    inputGlyph: base.textPrimary, rowGlyph: base.textPrimary)
        }
        // One rule for both bars, from the theme's dark shade (its hue and saturation at relative luminance 0.097, Arc's
        // split focus ring): halfway to white for the highlight, 60% for the selected text. Measured: #F2EAE4 (ring
        // #725137): #B8A89B and #C8B9AF (P02-b). White (ring #585858): #ABABAB and #BBBBBB (Q01-a/b). Teal (ring
        // #006362): #68B1B1 (P49), whose green and blue this gives; Arc's red is lower, its ring lies outside sRGB.
        // P20-a, P21-a (blank and Little windows): highlight #8F95FF. Q01-a: the card's 0.5 pt edge reads #AEAEAE on #F9F9FA.
        let highlight = spaceless ? srgb(0x8F95FF) : towardWhite(primary, 0.5)
        let selection = spaceless ? srgb(0xC9CCFF) : towardWhite(primary, 0.6)
        return CommandBarColors(card: NSColor(srgbRed: 0xF9 / 255.0, green: 0xF9 / 255.0, blue: 0xFA / 255.0, alpha: 1),
                                border: ink.withAlphaComponent(0.34), text: base.textPrimary, secondary: ink.withAlphaComponent(0.3),
                                placeholder: ink.withAlphaComponent(0.45), highlight: highlight, onHighlight: .white, textSelection: selection,
                                hairline: ink.withAlphaComponent(0.105), accessory: ink.withAlphaComponent(0.04), accessoryText: ink.withAlphaComponent(0.48),
                                tileOnHighlight: .white, infoCircle: .white, inputGlyph: .black, rowGlyph: ink.withAlphaComponent(0.66))
    }

    private static func srgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: 1)
    }

    /// `color` with its hue kept, saturation and brightness scaled (sRGB HSB).
    private static func towardWhite(_ primary: RGBA, _ white: Double) -> NSColor {
        let ring = themeShade(primary, luminance: 0.097)
        func lift(_ value: Double) -> Double { value + (1 - value) * white }
        return NSColor(srgbRed: lift(ring.red), green: lift(ring.green), blue: lift(ring.blue), alpha: 1)
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

/// Sizes measured on Arc 1.170's command bar in verify/visual-pairs/run-20261103 (P02-b, P02-c, Q01-a, Q01-b), at 2x.
private let measured = "verify/visual-pairs/run-20261103/REPORT.md, Arc captures P02-b/c and Q01-a/b"

struct CommandBarOverlayMetrics: MetricGroup {
    let cornerRadius = Metric(Metrics.urlPill.cornerRadius.value, .derived(
        rule: "the URL pill's radius, so the bar opened over the pill covers it edge to edge",
        from: ["URL pill corner radius"]))
    let rowInset = Metric(10.0, .anatomy("\(measured): the highlight is 10 in from the card's sides"))
    let rowVerticalInset = Metric(2.0, .anatomy("\(measured): a 46 tall highlight in each 50 pt row"))
    let rowCornerRadius = Metric(7.0, .anatomy("\(measured): the highlight's corners, continuous"))
    /// Icons are centred 32 from the card's left edge and text starts at 52, in the input row and in every row.
    let iconCentreX = Metric(32.0, .anatomy("\(measured): icon centres at 32 from the card's left"))
    let textX = Metric(52.0, .anatomy("\(measured): text starts 52 from the card's left"))
    /// The ⓘ button or the Tab key ends 22 from the card's right edge; both are 24 tall.
    let accessoryRightInset = Metric(22.0, .anatomy("\(measured): ⓘ and the Tab key end 22 from the right"))
    let accessorySize = Metric(24.0, .anatomy("\(measured): ⓘ circle, Tab key, Switch to Tab arrow and icon tiles are 24 tall"))
    /// Text-to-text gaps less the 2 pt a label keeps inside its frame on each side.
    let offerGap = Metric(11.5, .anatomy("verify/visual-pairs/run-20261103/P02/P02-c-arc.png: the card ends at x 734 px, 359 points wide with \"Search Google Docs\""))
    let keyGap = Metric(6.5, .anatomy("\(measured): 8.5 between \"Search Google Docs\" and its Tab key"))
    let keyPadding = Metric(4.0, .anatomy("\(measured): the Tab key is 30.5 wide around 13 pt \"Tab\""))
    let arrowRightInset = Metric(13.0, .anatomy("\(measured): the Switch to Tab arrow ends 13 in from the highlight (Q01-a: its square spans 26 to 50 pt of the crop against Brk's earlier 26.5 to 50.5)"))
    let centeredInputFontSize = Metric(18.0, .anatomy("\(measured): Cmd+T placeholder cap height 12.7"))
    let attachedInputFontSize = Metric(13.0, .anatomy("\(measured): the URL over the pill has a 9.5 ascender"))
    let titleFontSize = Metric(13.0, .anatomy("\(measured): row titles have a 9 pt cap height"))
    let keyFontSize = Metric(13.0, .anatomy("\(measured): \"Tab\" is as tall as \"Search Wikipedia\" beside it"))
    let hintFontSize = Metric(11.0, .guess("an action's key hint pill; Arc's were not in these captures"))
    let iconSize = Metric(16.0, .guess("favicon and SF Symbol size in a result row"))
    let symbolPointSize = Metric(12.0, .anatomy("verify/visual-pairs/run-20261103/P49/P49-cmd-arc.png: the magnifier spans x 566 to 589 px, 12 points of ink"))
    let inputRaise = Metric(0.5, .anatomy("verify/visual-pairs/run-20261103/Q01/Q01-a-arc.png: the placeholder's ink starts at y 481 px, half a point above the row's middle"))
    let hairlineInset = Metric(1.0, .anatomy("verify/visual-pairs/run-20261103/Q01/Q01-b-arc.png: the hairline spans x 538 to 2022 px, the highlight 534 to 2026 px"))
    let detailMaxShare = Metric(0.37, .anatomy("verify/visual-pairs/run-20261103/P21/P21-a-arc.png and Q03/Q03-a-arc.png: an address and its dash stop at about 175 points in a 470 pt row, 275 in a 746 pt row"))
    let hintPadding = Metric(6.0, .guess("horizontal padding inside a hint pill"))
    let hintTextSlack = Metric(2.0, .guess("room each side of a hint pill's centred text, which keeps its place; the measured width alone can cut the last letter"))
    let offerDotSize = Metric(8.0, .guess("the colour beside a prefix's offer; Brk's own"))
    let offerDotGap = Metric(5.0, .guess("between that colour and the offer; Brk's own"))
    let hintHeight = Metric(20.0, .guess("hint pill height"))
    let hintRadius = Metric(6.0, .anatomy("\(measured): the Tab key and the arrow square have about 6 pt corners"))
    let shadowRadius = Metric(24.0, .guess("popover shadow blur; the color is PopoverShadow"))
    /// The command bar's own shadow is much wider than a popover's. Arc's, measured round the centered card (Q01-a)
    /// and the one over the pill (P02-b): 22% black just outside a side, a Gaussian fall-off of about 46 pt, and the
    /// whole shadow 22 pt lower than the card (8% black 19 pt above the top, 30% under the bottom).
    let cardShadowRadius = Metric(46.0, .anatomy("\(measured): the sides fade like a 46 pt Gaussian (12.5% at 27 pt, 3% at 67 pt)"))
    let cardShadowAlpha = Metric(0.44, .anatomy("\(measured): 22% black just outside the card's right side, half the shadow's own"))
    let cardShadowOffset = Metric(22.0, .anatomy("\(measured): 8% black 19 pt above the card, 30% just under it"))
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
    let swatchSize = Metric(24.0, .guess("preset swatch diameter; nine fit one row of the dialog"))
    let ringGap = Metric(3.0, .guess("gap between a chosen swatch and its ring"))
    let dotSize = Metric(8.0, .guess("the theme-color dot drawn for a space without an icon"))
}

/// Copy the overlay views use that BrkUIKit's `Copy` does not have yet. Observed strings are Arc's
/// (visual-and-copy.md section 3); the short labels Arc keeps in code did not survive and are marked GUESS, the
/// same choices as electron-v1 `src/shared/copy.ts`.
enum OverlayCopy {
    /// Observed caption.
    static let switchToTab = "Switch to Tab"
    /// Arc's "Ask ChatGPT" caption on the Ask row (P49), with the local tool's name.
    static func ask(_ provider: String) -> String { "Ask \(provider)" }
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
    static let icon = "Icon"
    static let color = "Color"
    static let createSpace = "Create Space"
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
        icon.systemSymbolName
    }
}
