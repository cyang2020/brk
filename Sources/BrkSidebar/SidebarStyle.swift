import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

// Owner: W3. The sidebar's drawing numbers, ink colors and copy that the frozen contracts (`Metrics`,
// `SidebarTokens`, `Copy`) do not carry yet. Each one states its source in the same vocabulary as `Metrics`, so the
// integrator can move the whole group into `BrkBase/Metrics.swift` (and the inks into `SidebarTokens`, the strings
// into `Copy`) in one edit. "cra Lnnn" is a line of the measurement notes that layout-constants.md cites as cra.

/// The one instance: `Draw.rowTitleFont.value`.
let Draw = SidebarDrawMetrics()

struct SidebarDrawMetrics: MetricGroup {
    // The tab row's speaker (Q18-media-a, -f, -g) and Arc's own tooltip (Q18-media-e, -f).
    let rowSpeakerGlyph = Metric(12.5, .anatomy("~/brk-arc-reference/Q18/Q18-media-a-arc.png: the speaker's ink is 17.5 x 12.5, speaker.wave.3 at this size"))
    let rowSpeakerMutedGlyph = Metric(15.5, .anatomy("~/brk-arc-reference/Q18/Q18-media-g-arc.png: the struck speaker's ink is 15 x 14.5, speaker.slash at this size"))
    let rowSpeakerInk = Metric(0.55, .anatomy("~/brk-arc-reference/Q18/Q18-media-a-arc.png: the speaker's strokes read #767676"))
    let rowSpeakerRadius = Metric(6.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-f-arc.png: the speaker's hover square"))
    let tooltipDelay = Metric(0.45, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x10249be50: Arc's tooltip modifier takes 0.45"))
    let tooltipOffsetX = Metric(6.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-f-arc.png: pointer at 53, 467, the pill from 59, 474"))
    let tooltipOffsetY = Metric(7.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-f-arc.png: pointer at 53, 467, the pill from 59, 474"))
    let tooltipHeight = Metric(28.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-f-arc.png: the pill spans y 474 to 502"))
    let tooltipLabelSlack = Metric(3.0, .guess("what an NSTextField keeps at each end beyond its text"))
    let tooltipPadding = Metric(10.75, .anatomy("~/brk-arc-reference/Q18/Q18-media-f-arc.png: the pill is 97 wide around 75.5 of text"))
    let tooltipFont = Metric(12.0, .anatomy("cra L790: Arc's tooltips are 12 pt medium"))
    let tooltipFillLight = Metric(0.937, .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: #EFEFEF"))
    let tooltipFillDark = Metric(0.2, .guess("no capture of Arc's tooltip on a dark appearance"))
    let tooltipInkLight = Metric(0.1, .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: #1A1A1A"))
    let tooltipShadow = Metric(0.18, .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: the pill's soft shadow"))
    let tooltipShadowBlur = Metric(8.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: the pill's soft shadow"))
    let tooltipShadowOffset = Metric(1.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: the pill's soft shadow"))

    // The mini player's drawing (Q18-media-c, -e, -g, -j; 650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md).
    let miniPlayerTitleFont = Metric(13.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: Media fixture (playing) is 135 wide, 144 in a 14 pt row"))
    let miniPlayerInkLight = Metric(0.5, .anatomy("docs/arc-anatomy/visual-and-copy.md, ARC_MediaControlsFeature: PlaybackControlForeground #000000 @ 0.5; it reads #878787 on #FDFDFD in Q18-media-c-arc.png"))
    let miniPlayerInkDark = Metric(0.66, .anatomy("docs/arc-anatomy/visual-and-copy.md, ARC_MediaControlsFeature: PlaybackControlForeground dark #FFFFFF @ 0.66"))
    let miniPlayerDim = Metric(0.33, .anatomy("~/brk-arc-reference/Q18/Q18-media-c-arc.png: a disabled previous reads #D6D6D6 on #FDFDFD"))
    let miniPlayerFillLight = Metric(0.992, .anatomy("~/brk-arc-reference/Q18/Q18-media-c-arc.png: #FDFDFD, Arc's `backgroundExtra`, bin:0x10249a610"))
    let miniPlayerHoverLight = Metric(RGBA(0, 0, 0, 0.067), .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: #ECECEC over #FDFDFD"))
    let miniPlayerHoverDark = Metric(RGBA(1, 1, 1, 0.1), .guess("no capture of a mini player on a dark theme"))
    let miniPlayerButtonRadius = Metric(6.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: the pause button's hover square"))
    let miniPlayerCloseGlyph = Metric(14.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x10249be30: xmark at 14"))
    let miniPlayerTrackGlyph = Metric(14.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x10249cf10: previous and next at 14"))
    let miniPlayerPlayGlyph = Metric(14.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-c-arc.png: the pause glyph's ink is 9 x 12"))
    let miniPlayerSpeakerGlyph = Metric(14.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x10249d650: the speaker at 14"))
    let miniPlayerEmptyIcon = Metric(16.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-c-arc.png: the empty icon spans x 22 to 38"))
    let miniPlayerEmptyIconAlpha = Metric(0.78, .anatomy("~/brk-arc-reference/Q18/Q18-media-c-arc.png: #DADADA on #FDFDFD against a row's #C7CBCD on #F0FAFC"))
    let miniPlayerShadowLight = Metric(0.08, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x10249b3e4: black at 0.08 on a light theme"))
    let miniPlayerShadowDark = Metric(0.2, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x10249b3f8: black at 0.2 on a dark theme"))
    let miniPlayerShadowBlur = Metric(8.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x10249b43c: radius 4 in SwiftUI, 8 as an NSShadow's blur"))
    let miniPlayerDarkStroke = Metric(0.5, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x10249a760: a 0.5 line on a dark theme"))
    let miniPlayerDarkStrokeAlpha = Metric(0.1, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x10249a71c: white at 0.1 on a dark theme"))
    let miniPlayerTrackAlpha = Metric(0.66, .anatomy("~/brk-arc-reference/Q18/Q18-media-j-volume-arc.png: the track reads #555555 on #FDFDFD"))
    let miniPlayerKnobShadow = Metric(0.2, .anatomy("~/brk-arc-reference/Q18/Q18-media-j-volume-arc.png: the knob's edge fades through #E5E5E5"))
    let miniPlayerKnobShadowRadius = Metric(2.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-j-volume-arc.png: the knob's edge fades within 4 pt"))
    let miniPlayerKnobShadowOffset = Metric(1.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-j-volume-arc.png: the fade below the knob is stronger"))
    let currentArrowGlyph = Metric(14.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: the arrow's ink is 10 x 12"))
    let currentArrowFillLight = Metric(RGBA(hex: "#F5F5F5"), .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: the circle reads #F5F5F5"))
    let currentArrowFillDark = Metric(RGBA(hex: "#3A3A3C"), .guess("no capture of the round button on a dark theme"))
    let currentArrowInkLight = Metric(0.84, .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: the arrow reads #2A2A2A"))
    let currentArrowShadow = Metric(0.2, .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: the circle's edge fades through #DBDFE0"))
    let currentArrowShadowBlur = Metric(8.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: the fade reaches about 5 pt"))
    let currentArrowShadowOffset = Metric(1.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-e-arc.png: the fade below the circle is stronger"))

    // Type: one family, the system font (visual-and-copy.md, Fonts: the default UI font is `system`).
    let rowTitleFont = Metric(14.0, .anatomy("cra L115: sidebar rows have 14 pt titles"))
    let groupTitleLeading = Metric(10.0, .anatomy("de345fe719:verify/visual-pairs/run-20261103/r5-2/REPORT.md, bin:0x100048260: the header's stack starts 18 in from the cell, the rows' selection 8"))
    let groupTitleFont = Metric(12.0, .guess("tab group header title; Arc reads its font through a key path (bin:0x100d93d68), not resolved to a size"))
    let spaceHeaderFont = Metric(13.0, .anatomy("2a96a9d7f0:verify/visual-pairs/run-20261103 P01-a, P20-a: 对照 is 24.5 x 12 and This Window 80 wide, 13 pt semibold (cra L180 had 14 medium)"))
    let urlFont = Metric(13.0, .anatomy("cra L1219: URL pill host text is SF 13 regular"))
    let smallFont = Metric(12.0, .guess("Clear button and favorites empty title; Arc's tooltips are 12 pt medium (cra L790)"))
    let livePageDot = Metric(7.0, .guess("Brk-only: a live AI page's new-data dot, the size of Arc's unread dot on a Favorite"))
    let captionFont = Metric(11.0, .guess("favorites empty subtitle; Arc's secondary row line is 11 pt (cra L115)"))
    let clearInkDark = Metric(0.35, .anatomy("~/brk-arc-reference/Q18/Q18-navy-row-hover-arc.png: Clear reads white at this strength over the theme, less than the row's 0.45 foreground"))
    let clearFont = Metric(10.0, .anatomy("~/brk-arc-reference/P05/P05-d-arc.png: Clear's ink is 26 x 8 points, 10 pt semibold (11 pt is 28 x 8.5)"))

    // Row interior, measured from the sidebar edge: favicon centred at 26, title at 45 (cra L141, L180).
    let faviconLeading = Metric(10.0, .anatomy("cra L141: favicon 16 pt centred 26 pt from the sidebar edge = selection inset 8 + 10"))
    /// The label's frame; its cell draws the text 2 further in (Arc's text starts at x 44).
    let titleLeading = Metric(34.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-a: Arc's row text starts 3 left of the cra L141 x 45"))
    let spaceChevron = Metric(13.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P05-c: Arc's collapse chevron is 7 pt wide, centred in the icon slot"))
    let spaceHeaderLeading = Metric(6.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-a: Arc's space name starts at x 16, 5 left of the row icon slot"))
    let dividerInset = Metric(18.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-a: the Pinned/Today hairline runs from x 18 to 18 before the sidebar edge"))
    let clearTrailing = Metric(19.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-c: Clear ends 19 before the sidebar edge"))
    let clearGap = Metric(10.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-c: the hairline stops 10 before Clear"))
    let clearArrowWidth = Metric(10.0, .anatomy("~/brk-arc-reference/Q18/Q18-clear-pinned-current-resting-arc.png: the ↓'s ink is 8 pt wide, 9 from the hairline's end, the 10 pt gap to its frame"))
    let clearArrowGap = Metric(2.75, .anatomy("~/brk-arc-reference/Q18/Q18-clear-pinned-current-resting-arc.png: the ↓'s ink ends 3.75 before the word"))
    let clearArrowGlyph = Metric(10.0, .anatomy("~/brk-arc-reference/Q18/Q18-clear-pinned-current-resting-arc.png: the ↓ spans 8 x 9.5 pt"))
    /// Tidy on the Today divider (P46-b, 2x): the hairline stops at x 241 px, the broom spans 259 to 273 px (y 790 to
    /// 813), "Tidy" 290 to 327 px, a separator at 344 px, Clear from 366 px.
    let tidyGaps = Metric([9.0, 6.5, 6.5, 9.5], .anatomy("~/brk-arc-reference/P46/P46-b-arc.png: hairline to broom, broom to Tidy, Tidy to the separator, the separator to Clear"))
    /// The auto-archive banner, from Arc's `AutoArchiveEducationView` (bin 0x10256c910 to 0x10256e720), as no Arc capture
    /// of it exists: a card 2 + 8 in from its surroundings, radius 12, with a band, the message and a filled button.
    let educationMargin = Metric(10.0, .anatomy("de345fe719:verify/visual-pairs/run-20261103/r5-2/REPORT.md, bin:0x10256c7f0 padding 8 around bin:0x10256cb34 padding 2"))
    let educationCorner = Metric(12.0, .anatomy("de345fe719:verify/visual-pairs/run-20261103/r5-2/REPORT.md, bin:0x10256ca88 clipShape radius 12, all four corners"))
    let educationPadding = Metric(12.0, .anatomy("de345fe719:verify/visual-pairs/run-20261103/r5-2/REPORT.md, bin:0x10256d190 the band, bin:0x10256d3a8 the message (top and sides), bin:0x10256e5f0 around the button"))
    let educationTitleFont = Metric(13.0, .anatomy("de345fe719:verify/visual-pairs/run-20261103/r5-2/REPORT.md, bin:0x10256cfcc Font.body (13 pt on macOS) weight medium"))
    let educationMessageFont = Metric(12.0, .anatomy("de345fe719:verify/visual-pairs/run-20261103/r5-2/REPORT.md, bin:0x10256d280 Font.callout (12 pt on macOS) weight regular"))
    let educationButtonFont = Metric(13.0, .anatomy("de345fe719:verify/visual-pairs/run-20261103/r5-2/REPORT.md, bin:0x10256e090 Font.body (13 pt on macOS) weight light"))
    let educationButtonPadding = Metric(8.0, .anatomy("de345fe719:verify/visual-pairs/run-20261103/r5-2/REPORT.md, bin:0x10256e2d4 vertical padding 8 inside the button"))
    let educationButtonCorner = Metric(12.0, .anatomy("de345fe719:verify/visual-pairs/run-20261103/r5-2/REPORT.md, bin:0x10256e5b4 clipShape radius 12, all four corners"))
    let educationIconGap = Metric(6.0, .guess("SwiftUI's Label spacing; Arc uses Label with its title-and-icon style"))
    let tidyGlyph = Metric([7.0, 11.5], .anatomy("~/brk-arc-reference/P46/P46-b-arc.png: the broom is 14 x 23 px"))
    let tidySeparatorHeight = Metric(10.0, .guess("the bar between Tidy and Clear, about the height of the capitals"))
    /// While Tidy works the divider's hairline becomes a moving wave: Arc's `SquiggleDivider`, built at bin:0x1001ab2e8
    /// as SquiggleDivider(height: 8, amplitudeAnimationDuration: 0.4) (the pair at bin:0x103652850).
    let tidyWaveHeight = Metric(8.0, .anatomy("bin:0x103652850, Arc 1.170: SquiggleDivider.height; the frame's height, half of it the amplitude"))
    let tidyWaveRamp = Metric(0.4, .anatomy("bin:0x103652850 amplitudeAnimationDuration; bin:0x1002b1ec4 the amplitude ramps linearly over it, bin:0x1002b14e0 the end waits as long"))
    let tidyWaveLength = Metric(1.6, .anatomy("bin:0x1002b1fa8: one wave is 1.6 heights long"))
    let tidyWaveSpeed = Metric(5.0, .anatomy("bin:0x1002b1fb0: the phase is the clock's seconds times 5, so five waves pass a point each second, moving left"))
    let tidyWaveControl = Metric(0.3, .anatomy("bin:0x1002b1ffc, bin:0x1002b22e4: each half wave is a cubic with its control points 0.3 and 0.7 of the way along, at the amplitude"))
    let tidyWaveLineWidth = Metric(2.0, .anatomy("bin:0x1002b1f90: StrokeStyle lineWidth 2 while animating, 0.5 at rest (Brk keeps its own resting hairline)"))
    let tidyWaveWidthDuration = Metric(0.2, .anatomy("bin:0x1002b1c14: the line width eases with timingCurve(0.25, 0.1, 0.25, 1, duration: 0.2)"))
    /// The broom swings when Tidy is pressed (Arc's SidebarTidyButton mouseDown, bin:0x100311530 to bin:0x100310908): it
    /// hangs from a point 0.6 across its top edge (bin:0x100310f74), springs 25° clockwise, and 0.4 s later springs back.
    let tidyBroomSwing = Metric(0.436332, .anatomy("bin:0x1003109f8: transform.rotation.z to -0.436332 rad (25° clockwise in Arc's unflipped layer)"))
    let tidyBroomPivot = Metric(0.6, .anatomy("bin:0x100310f74: anchorPoint (0.6, 1), the top edge"))
    let tidyBroomSpring = Metric([1.5, 150.0, 15.0, 8.0], .anatomy("bin:0x1003114b8 to bin:0x1003114e4: CASpringAnimation mass, stiffness, damping, initial velocity; duration its settlingDuration"))
    let tidyBroomHold = Metric(0.4, .anatomy("bin:0x100310aa0: the swing back is dispatched 0.4 s after the press"))
    /// The tab list's motions (Arc's `TablistOutlineView`; recordings in docs/checks/2026-11-13-sidebar-animations.md). A
    /// change of the rows runs in `OutlineViewDiffableDataSource`'s animation group: added rows fade in, one removed row
    /// fades out, several slide up and fade, the others slide to their new places.
    let tablistListMotion = Metric(0.12, .anatomy("bin:0x100969f8c: setDuration 0.12 before beginUpdates; recorded: a new tab, a close, a restore, Clear, a pin all move 0.32, 0.60, 0.79, 0.90, 0.96, 1 in successive 1/60 s frames"))
    let tablistListCurve = Metric([0.25, 0.1, 0.25, 1.0], .anatomy("no timing function set in the group, so Core Animation's default; the frames above fit it at 0.12 s (squared error 0.0002), not ease-out or linear"))
    /// A folder opening: `animator().expandItem` outside any group (bin:0x1002a8798).
    let tablistFolderOpen = Metric(0.2, .anatomy("recorded on a folder of 2 and of 6 rows: the rows below move 24, 36, 57, 67, 75, 83, 90, 95, 98, 100 percent, whatever the count"))
    let tablistFolderOpenCurve = Metric([0.0, 0.0, 0.58, 1.0], .anatomy("those frames fit ease-out at 0.2 s (squared error 0.0001); Core Animation's default curve misses by 60 times more"))
    /// A folder closing: `animator().collapseItem` in its own animation group (bin:0x1002a8720, block bin:0x1002ad290).
    let tablistFolderClose = Metric(0.25, .anatomy("NSAnimationContext's default length; recorded on a folder of 2 and of 6 rows: 6, 17, 31, 46, 59, 70, 78, 84, 89, 93, 96, 98, 99, 100 percent"))
    let tablistFolderCloseCurve = Metric([0.25, 0.1, 0.25, 1.0], .anatomy("those frames fit Core Animation's default curve at 0.25 s (squared error 0.0001)"))
    /// Arc's folder glyph (`FolderIcon.FolderIconView`): the paths of bin:0x10166cc40, the
    /// open state of bin:0x10166c6a8, run as an implicit animation from the representable's update (bin:0x10166e22c).
    /// The divider's Clear, Tidy and cleanup buttons appear while the pointer is over the sidebar or the divider.
    let dividerFade = Metric(0.1, .anatomy("bin:0x1001aca1c: setDuration 0.1 before animator().alphaValue; recorded, Clear reads 32, 54, 75, 100 percent in successive 1/60 s frames"))
    let dividerFadeCurve = Metric([0.0, 0.0, 0.58, 1.0], .anatomy("bin:0x1001ac9e4: functionWithName kCAMediaTimingFunctionEaseOut"))
    let clearArrowPress = Metric(3.0, .anatomy("bin:0x10030f764: the ↓'s centre constraint goes to 3 while Clear is pressed, back to 0 on release (bin:0x10030f924)"))
    let clearArrowPressDuration = Metric(0.175, .anatomy("bin:0x10030f734: setDuration 0.175 with implicit animation allowed"))
    /// The Space name strip (Arc's `SidebarSectionHeaderView`): hovered, its chevron fades in as its slot opens and pushes
    /// the name right; a click turns the chevron a quarter.
    let spaceHeaderSlide = Metric(0.1, .anatomy("bin:0x1001c673c, bin:0x1001c77fc: setDuration 0.1, kCAMediaTimingFunctionEaseOut, for the chevron's width constraint and alpha; recorded, the chevron turns in 6 frames"))
    let spaceHeaderPillFade = Metric(0.07, .anatomy("bin:0x1001c7980, bin:0x1001c7adc: setDuration 0.07, ease-out, for the hover's alpha"))
    /// The tab row's hover button glyph (Arc's `XMarkOrHyphenIcon`): two bars, crossed for ×, level for −.
    let rowButtonBar = Metric([14.0, 2.0, 1.0], .anatomy("bin:0x100af3ef0: RoundedRectangle(cornerSize 1 x 1, continuous) framed 14 x 2, rotated ±π/4 about its centre unless isHyphen"))
    let rowButtonSpring = Metric([0.3, 0.6], .anatomy("bin:0x100af4214: spring(response 0.3, dampingFraction 0.6) on isHyphen"))
    /// The tab row's speaker (Arc's `SpeakerIcon`, in `SidebarCellSpeakerIconWrapperView`).
    let rowSpeakerSymbol = Metric(14.0, .anatomy("bin:0x100aed1ec: Image(systemName: \"speaker\") in system 14 medium"))
    let rowSpeakerWaveFrame = Metric([8.0, 12.0], .anatomy("bin:0x100aed838: each wave framed 8 x 12"))
    let rowSpeakerWaveShift = Metric([5.0, 2.0, 3.0, 4.0], .anatomy("bin:0x100aed80c: the waves sit 5 right of the icon's centre, muted 2, 3 and 4 (faded out); Q18-media-a: the third wave's ink ends at x 62"))
    let rowSpeakerBodyShift = Metric(4.0, .anatomy("bin:0x100aed4c4: the speaker sits 4 left of the centre while it plays, in the middle muted"))
    let rowSpeakerSlashSide = Metric(14.0, .anatomy("~/brk-arc-reference/Q18/Q18-media-g-arc.png: the slash runs x 47 to 60.5, y 459.5 to 473.5, centred on the speaker's middle"))
    let rowSpeakerSlashWidth = Metric(0.0875, .anatomy("bin:0x100aedfb0: the slash is the square's width x 3.5 / 40 thick, its cut x 3.5 / 20"))
    let rowSpeakerCutReach = Metric(4.5, .anatomy("bin:0x100aedfc4: the cut reaches its thickness / 4.5 past both ends of the slash"))
    let rowSpeakerSpeedup = Metric(0.6, .anatomy("bin:0x10369d0e0: SpeakerIcon's speedup, slashStart, waveIncrement, waveReappearStart = 0.6, 0.12, 0.05, 0.1"))
    let rowSpeakerSlashStart = Metric(0.12, .anatomy("bin:0x10369d0e8: the slash and the speaker's move start 0.12 x speedup after muting"))
    let rowSpeakerWaveIncrement = Metric(0.05, .anatomy("bin:0x10369d0f0: each next wave 0.05 x speedup later"))
    let rowSpeakerWaveReappear = Metric(0.1, .anatomy("bin:0x10369d0f8: unmuting, the first wave comes back 0.1 x speedup later"))
    let rowSpeakerSpring = Metric([0.3, 0.6], .anatomy("bin:0x100aed4e8, bin:0x100aed870: spring(0.3, 0.6) for the speaker's move and the waves"))
    let rowSpeakerSlashInSpring = Metric([0.3, 0.65], .anatomy("bin:0x100aed6a8: the slash draws in on spring(0.3, 0.65)"))
    let rowSpeakerSlashOutSpring = Metric([0.25, 0.7], .anatomy("bin:0x100aed690: and goes on spring(0.25, 0.7)"))
    let folderIconSide = Metric(17.0, .anatomy("bin:0x1003eef90: the sidebar's folder cell makes its FolderIconView 17 x 17 (the SwiftUI representable's 16 x 16 at bin:0x10166e1c4 is used elsewhere); recorded, Arc's closed glyph is 38 px across at 2x, as 17 + the 1.5 outline"))
    let folderIconRadiusDivisor = Metric(7.0, .anatomy("bin:0x10166cc78: corner radius = (width / 7) rounded"))
    let folderIconLine = Metric(1.25, .anatomy("bin:0x10166cc84: the outline is 1.25 rounded to whole device pixels (1.5 at 2x)"))
    let folderIconFrontTop = Metric(0.25, .anatomy("bin:0x10166cd28: the front flap starts a quarter of the height down, rounded, then to device pixels"))
    let folderIconTabDivisor = Metric(1.5, .anatomy("bin:0x10166cd40: the back's tab is the front's top / 1.5, rounded down"))
    let folderIconTabEnd = Metric([0.42, 0.58], .anatomy("bin:0x10166cd58, bin:0x10166cd88: the tab's top ends at 0.42 of the width, its slope at 0.58"))
    let folderIconPerspective = Metric(350.0, .anatomy("bin:0x10166c81c: m34 = -1/350"))
    let folderIconOpenShift = Metric(3.0, .anatomy("bin:0x1037526d8: open, both halves move 3 pt right (1.5 when peeked)"))
    let folderIconOpenTurn = Metric(32.0, .anatomy("bin:0x1037526f8: open, both halves turn 32° about the vertical axis"))
    let folderIconBackTilt = Metric(28.0, .anatomy("bin:0x103752738: open, the back panel tips 28° about its bottom edge (away)"))
    let folderIconFrontTilt = Metric(-30.0, .anatomy("bin:0x103752718: open, the front flap tips -30° about its bottom edge (forward)"))
    let folderIconFrontShade = Metric(0.15, .anatomy("bin:0x10166b7bc: the front's shading is black from 0 to 0.15, shown only open"))
    let folderIconFrontShadeAxis = Metric([0.1, 0.0, 0.9, 1.0], .anatomy("bin:0x10166b838 to bin:0x10166b864: start (0.1, 0), end (0.9, 1)"))
    let folderIconBackShade = Metric(0.36, .anatomy("bin:0x10166bb0c: the back's shading is black from 0 to 0.36, masked by the back's path"))
    let folderIconBackShadeAxis = Metric([0.0, 0.0, 0.6, 1.0], .anatomy("bin:0x10166bb90 to bin:0x10166bbac: start (0, 0), end (0.6, 1)"))
    let folderIconBackLift = Metric(0.16, .anatomy("~/brk-arc-reference/P01/P01-a-arc.png: the open back panel reads 167 at its unshaded corner falling to 145, Brk's with the back ink under the same shading 152 to 132; the ink lifted this far toward white closes it (light themes; no Arc picture of an open folder in a dark theme to measure)"))
    let folderIconClosedBackShading = Metric(0.2, .anatomy("bin:0x10166c6a8: the back's shading at 0.2 while closed, 1 open"))
    let folderIconTurn = Metric(0.25, .anatomy("an implicit Core Animation transition: CATransaction's default 0.25 s; recorded, the glyph turns with the rows of a closing folder"))
    let folderIconTurnCurve = Metric([0.25, 0.1, 0.25, 1.0], .anatomy("an implicit transition's default curve; the recorded glyph frames fit it"))
    let titleTrailing = Metric(8.0, .guess("title end padding inside the selection, mirrors the 8 pt selection inset"))
    let closeTrailing = Metric(7.0, .anatomy("~/brk-arc-reference/Q13/Q13-press-row-arc.png: the × centres 19 from the row's right end"))
    let emptyFavicon = Metric(14.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-a: Arc's empty favicon is a 14 pt square centred 26 from the sidebar edge"))
    let emptyFaviconRadius = Metric(2.5, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-a: the empty favicon's corners round over about 2.5 pt"))
    let folderGlyphWidth = Metric(22.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-a: Arc's open folder spans x 16 to 38 in the 16 pt icon row"))
    let folderClosedSide = Metric(18.0, .anatomy("94e1d686c1:verify/visual-pairs/run-20261103/results.tsv P13-a: Arc's closed folder is about 18 x 18, centred on the row"))
    let folderClosedRadius = Metric(3.0, .guess("corner radius of the closed folder's body in P13-a"))
    let folderGlyphShift = Metric(1.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-a: the folder is centred at x 27, 1 right of the favicon slot's centre"))
    let folderGlyphLine = Metric(1.4, .guess("the folder outline is about 1.4 pt wide in the P01-a capture (3 px at 2x)"))
    // Split rows: each pane a TabCellBackgroundChild box inside the row (measured on the 2026-11-03 Arc capture P23a/b).
    let splitSegmentInset = Metric(4.0, .guess("measured on the 2026-11-03 Arc capture P23a: pane boxes 4 pt inside the row's selection"))
    let splitSegmentGap = Metric(4.0, .guess("measured on the 2026-11-03 Arc capture P23a: 4 pt between pane boxes"))
    let splitSegmentRadius = Metric(8.0, .guess("measured on the 2026-11-03 Arc capture P23a: pane box corners about 8 pt"))
    let splitSegmentIconLeading = Metric(6.0, .anatomy("~/brk-arc-reference/P23/P23-a-arc.png and Q15/Q15-d-arc.png: the pane's icon starts 19 along the row, 7 inside its box at 12, with the 16 pt slot's 1 pt margin"))
    let splitSegmentTitleLeading = Metric(32.0, .anatomy("~/brk-arc-reference/P23/P23-a-arc.png, P23-f-arc.png and Q15/Q15-d-arc.png: the pane's title ink starts 4 pt before where 36 put it"))
    let peekMarkerIcon = Metric(14.0, .guess("measured on the 2026-11-03 Arc capture P22a: a 14 pt icon in the 24 pt Peek marker"))
    let splitSegmentTitleMinWidth = Metric(60.0, .anatomy("2a96a9d7f0:verify/visual-pairs/run-20261103: four pane boxes of about 50 pt show icons only (P23-b), three of 65 pt show titles (Q15-f)"))

    // Title row (cra L1215, Arc 1.170 AX tree).
    let navButton = Metric(32.0, .anatomy("cra L1215: Go back, Go forward and Reload are 32 x 32"))
    let navGap = Metric(2.0, .anatomy("cra L1215: the navigation buttons are 2 pt apart"))
    let toggleGap = Metric(4.0, .anatomy("cra L1215: sidebar toggle at x 77 = the third light's end (73) + 4"))
    let toggleFullScreenLeft = Metric(13.0, .anatomy("~/brk-evidence/fullscreen-titlebar (Arc 1.170 full screen, 2026-11-12): the toggle glyph starts at 20 pt, 7 inside its 32 pt button as in the windowed row (glyph at 84, button at 77); the close light's left inset"))
    let navButtonCompact = Metric(28.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P03-b: at 164 Arc's back, forward and … are centred 28 apart, ending 6 from the edge"))
    let navGlyph = Metric(14.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-c: Arc's back arrow is 14.5 pt wide and its reload 15 pt"))
    let navButtonRadius = Metric(9.0, .guess("hover fill of the title-row buttons; reuses the URL pill accessory radius 9"))

    // Toolbar (P01-b): grey glyphs and host on the white card top.
    let toolbarGlyph = Metric(13.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-b: the toolbar arrows are 13 pt wide, a size under the title row's"))
    let toolbarHostSlack = Metric(2.0, .guess("the host label is a little wider than its cell so a short host never truncates"))
    let toolbarLinkGap = Metric(5.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-b: the host starts 5 after the link glyph"))
    let toolbarGlyphAlpha = Metric(0.5, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-b: toolbar glyphs #7E7E7E on white"))
    let toolbarDisabledAlpha = Metric(0.21, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-b: a disabled arrow is #C9C9C9 on white"))
    let toolbarTextAlpha = Metric(0.56, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-b: the host is #717171 on white"))
    let toolbarHairlineAlpha = Metric(0.045, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-b: the hairline under the toolbar is #F4F4F4 on white"))

    // URL pill.
    /// The label's frame; its cell draws the text 2 further in, at x 21 in the sidebar.
    let shareTextLeading = Metric(32.0, .anatomy("Q09 a: an Easel's \"Share\" starts at x 42 in the pill at x 8 (the label's own 2 pt inset first)"))
    let shareLockGlyph = Metric([10.0, 13.0, 13.0], .anatomy("Q09 a: the pill's lock is 10 x 13 at x 21 (13 into the pill)"))
    let shareEdge = Metric(1.0, .anatomy("Q09 a: an Easel's pill has a 1 pt #CFCFCF edge"))
    let pillTextLeading = Metric(11.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-a: pill at x 8, host text at x 21"))
    /// The pill's second line (Translation Available, Translated): P45-a and P50-b measured in the 36 pt pill.
    let pillSubtitleFont = Metric(12.0, .anatomy("~/brk-arc-reference/P45/P45-a-arc.png: Translation Available's capitals are 17 px (8.5 pt) tall, #272B2C"))
    let pillHostCenter = Metric(9.0, .anatomy("~/brk-arc-reference/P45/P45-a-arc.png: with a second line the host's digits span y 101 to 119 px in the pill at 92 px"))
    let pillSubtitleCenter = Metric(25.5, .anatomy("~/brk-arc-reference/P45/P45-a-arc.png: Translation Available's capitals span y 134 to 151 px in the pill at 92 px"))
    /// The translation popover (P50-d-popover, 2x): body 237 x 101 pt; the Aa disc, the sentence, two buttons.
    let translationPopover = Metric([237.0, 101.0], .anatomy("~/brk-arc-reference/P50/P50-d-popover-arc.png: the body spans x 25 to 499 px and y 25 to 226 px"))
    let translationDisc = Metric([10.5, 10.5, 32.0], .anatomy("~/brk-arc-reference/P50/P50-d-popover-arc.png: the Aa disc spans x and y 46 to 110 px"))
    let translationTextFont = Metric(14.0, .anatomy("~/brk-arc-reference/P50/P50-f-arc.png: 'Translated from French.' is 152.5 points wide"))
    let translationMenuOffset = Metric([2.75, 15.0], .anatomy("~/brk-arc-reference/P50/P50-f-arc.png: the menu's left edge at x 117 pt and its top at y 161 pt"))
    let translationTextLeading = Metric(51.0, .anatomy("~/brk-arc-reference/P50/P50-d-popover-arc.png: Translated from French. starts at x 134 px"))
    let translationButtons = Metric([10.5, 58.5, 104.0, 32.0, 8.0], .anatomy("~/brk-arc-reference/P50/P50-d-popover-arc.png: Options x 46 to 254 px, Use Original x 270 to 478 px, both y 142 to 206 px"))
    let pillSearchTextLeading = Metric(0.0, .anatomy("3d604e37a3:verify/visual-pairs/run-20261103/Q23/NOTES.md: in Q02-b-arc.png the placeholder's S starts 42.5 pt from the window's edge, 34.5 into the pill; a label draws 2 pt inside its frame"))
    let pillSearchGlyph = Metric(12.5, .anatomy("3d604e37a3:verify/visual-pairs/run-20261103/Q23/NOTES.md: in Q02-b-arc.png the magnifier is 12 pt across; SF's magnifyingglass at 14 draws 13.5"))
    let pillSearchGlyphInk = Metric(0.4, .anatomy("3d604e37a3:verify/visual-pairs/run-20261103/Q23/NOTES.md: in Q02-b-arc.png the magnifier's line reads 140 on the pill's 236, black at 0.41; the placeholder beside it reads 164 (0.3) and an address 93 (0.6)"))
    let pillAccessoryInset = Metric(4.0, .guess("accessory button inset: (pill 36 - button 28) / 2"))
    let pillAccessoryGap = Metric(1.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-c: copy link and site controls centred 29 apart (cra L1222-1223)"))
    let pillAccessoryGlyph = Metric(15.0, .guess("copy-link and site-control glyph size inside the 28 pt accessory"))

    // Favorites.
    let tileFavicon = Metric(16.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-a: Arc's favicons are 16 pt in the 47 pt tiles"))
    let tileRingWidth = Metric(2.0, .anatomy("cra L475: the active favorite has a 2 pt rim inside the edge"))
    let tileWashSource = Metric(24.0, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md: with the icon at 24 px the chain computes #FE747C for YouTube (Arc #FF7A7E), #9D9C9E for MDN (Arc #9E9E9E), #CCCDCD for GitHub (Arc #B6B9BA to #D9DADA); at 32 px #FF777C, #A8A8A9, #E0E1E2"))
    let tileWashBlur = Metric(5.0, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md, AppTrayVisualEffectImageProvider bin:0x101cfe4f4: CIGaussianBlur radius"))
    let tileWashSaturation = Metric(1.5, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md, AppTrayVisualEffectImageProvider bin:0x101cfe5a8: CIColorControls saturation"))
    let tileWashBrightness = Metric(0.05, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md, AppTrayVisualEffectImageProvider bin:0x101cfe5f4: CIColorControls brightness"))
    let tileWashContrast = Metric(0.85, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md, AppTrayVisualEffectImageProvider bin:0x101cfe63c: CIColorControls contrast"))
    let tileWashDivisor = Metric(5.0, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md, AppTrayVisualEffectImageProvider bin:0x101cfe894: the picture is drawn tray width / 5 x the icon's size across"))
    let tileWashDark = Metric(0.2, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md, AppTrayItemBackgroundView bin:0x101cf26d4: the picture over a resting tile, dark theme"))
    let tileWashDarkHover = Metric(0.3, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md, AppTrayItemBackgroundView bin:0x101cf26bc: the picture over a hovered tile, dark theme"))
    let tileWashLightHover = Metric(0.1, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md, AppTrayItemBackgroundView bin:0x101cf26b0: the picture over a hovered tile, light theme (none at rest)"))
    let tileCurrentLight = Metric(0.8, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md, AppTrayItemBackgroundView bin:0x101cf2a40: the current tile's white, light theme"))
    let tileCurrentDark = Metric(0.45, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md, AppTrayItemBackgroundView bin:0x101cf2a50: the current tile's white, dark theme"))
    let tileRenameInset = Metric(4.0, .guess("side padding of the rename field across a favorites tile; Arc's favorite rename was not recovered"))
    let emptyDash = Metric([5.0, 5.0], .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P07-b: the empty favorites box is dashed 5 on, 5 off"))
    let emptyBoxFillAlpha = Metric(0.35, .guess("the empty favorites box is a shade lighter than the sidebar (#F3EEEB over #F0EBE6 in P07-b)"))
    let emptyBadge = Metric(16.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P07-b: a 16 pt star badge 12.5 below the box top"))
    let emptyBadgeTop = Metric(12.5, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P07-b: the badge spans y 101.5 to 117.5 in a box starting at 89"))
    let emptyTitleFont = Metric(13.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P07-b: Drag to add Favorites is bold, about 132 pt wide"))
    let emptyTitleGap = Metric(6.0, .guess("space between the star badge and the bold title in the empty favorites box"))
    let emptySubtitleGap = Metric(3.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P07-b: the subtitle's first line is centred 18 under the title's"))
    let emptyTextInset = Metric(26.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P07-b: the subtitle wraps after \"most\", its first line about 136 wide; 26 keeps that break at every scale down to 164 (P05-f), where a label's fixed padding makes the text relatively wider"))
    let emptySubtitleFont = Metric(11.5, .anatomy("~/brk-arc-reference/P07/P07-b-arc.png: \"Favorites keep your most\" is 136.5 pt and \"used sites and apps close\" 140.5 pt wide, SF 11.5 (12 measures 141.6 and 146.2)"))
    let emptyCloseSize = Metric(18.0, .guess("hit size of the × on the empty favorites box"))
    let emptyCloseInset = Metric(15.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P07-b: the × is centred 15 in from the box's top-right corner"))

    // Dock.
    let dockGlyph = Metric(15.0, .guess("space emoji or symbol size in a 34 x 32 dock cell (cra L115: tiny emoji)"))
    let dockDot = Metric(8.0, .guess("dot for a space without an icon, measured on P25-a-arc.png (16 px at 2x)"))
    let dockActiveInk = Metric(0.47, .guess("black (white in dark) over the sidebar for the current space's icon or dot, sampled on P25 a (#817E7C on #EFEAE6)"))
    let dockInactiveInk = Metric(0.22, .guess("the same for the other spaces, sampled on P25 a (#BAB6B2)"))
    let dockRingWidth = Metric(1.5, .guess("Brk's own: the ring around a Space's dot while a conversation there waits for the user (docs/design/ai-threads-library-mockup.html draws 1.5)"))
    let dockRingGap = Metric(2.0, .guess("Brk's own: between the dot and its ring, as the mockup's 2 pt of sidebar color"))
    let dockRingLuminance = Metric(0.15, .guess("Brk's own: the ring's shade of the Space's color on a light sidebar, about the mockup's #3D6FB6"))
    let dockPlusGlyph = Metric(17.0, .anatomy("2a96a9d7f0:verify/visual-pairs/run-20261103 Q11-b-arc: the + spans x 394 to 422 px"))
    let dockPlusInk = Metric(0.53, .anatomy("2a96a9d7f0:verify/visual-pairs/run-20261103 Q11-a-arc, Q11-b-arc: + and × read #717878 and #6B6F70 on #EFFAFB"))
    let dockGlyphInkDark = Metric(0.62, .anatomy("~/brk-arc-reference/Q18/Q18-navy-row-hover-arc.png: the Library glyph and the + read white at this strength over the theme"))
    let dockButtonGlyph = Metric(15.0, .guess("Library and + glyph size in their 32 pt buttons"))
    let dockPlusBars = Metric([14.0, 2.0], .anatomy("bin:0x100af2384: PlusMenuIcon is two RoundedRectangles, the size wide and 2 high, one turned 90°; 2a96a9d7f0:verify/visual-pairs/run-20261103 Q11-b-arc: the + spans 28 px at 2x"))
    let copyFeedbackDuration = Metric(1.0, .anatomy("~/brk-evidence/hover-animations-2/scratch/copy-link.mov: click collapses the link, the check appears and holds for about one second before the link returns"))
    let toolbarPressSpring = Metric([0.2, 0.6], .anatomy("~/brk-evidence/hover-animations-2: real Arc's sidebar toggle held down reaches its pressed look in 0.13 s with an 8% overshoot, settled by 0.27 s, a spring of response 0.2 and damping 0.6 (the same numbers ReloadIcon's wrapper names, bin:0x100af27d4)"))
    let toolbarPressedInk = Metric(0.94, .anatomy("~/brk-evidence/hover-animations-2: the held sidebar toggle's ink reads 13 on the 236 hover fill (0.6 at rest, 89)"))
    let toolbarToggleScale = Metric(0.95, .anatomy("bin:0x100af2054: SidebarIcon scaleEffect(isArcButtonPressed ? 0.95 : 1) about its centre"))
    let toolbarArrowShift = Metric(3.0, .anatomy("bin:0x100af21d8: ArrowIcon offset x isArcButtonPressed ? -3 (left) or 3 (right) : 0"))
    let toolbarReloadTurn = Metric(90.0, .anatomy("bin:0x100af2aa0: ReloadIcon's arrow rotationEffect(isArcButtonPressed ? π/2 : 0)"))
    let toolbarGlyphSwap = Metric([0.7, 0.1, 0.2], .anatomy("bin:0x100af2aa0, bin:0x100af27d4: reload ↔ stop: the leaving glyph scales to 0.7 and fades, the coming one from 0.7, on spring(0.2, 0.6) delayed 0.1 s (to stop) or 0.2 s (back to reload)"))
    let dockPlusSpring = Metric([0.2, 0.5], .anatomy("bin:0x100af267c: rotationEffect(isOpen ? 45° : 0) with .spring(response: 0.2, dampingFraction: 0.5)"))

    // The Library button's picture and its hover motion (Arc 1.170: ARCUI `BoxOfThingsIcon`, body bin:0x100ae93b4,
    // hover handler bin:0x100aeaab4). Offsets are points from the button's centre, y down; angles in degrees, clockwise.
    let libraryIconSpring = Metric([0.5, 1.0], .anatomy("bin:0x100aefbe4: BoxOfThingsIcon(animation: .spring(response: 0.5, dampingFraction: 1)); every piece animates with it on `isHovered`"))
    let libraryIconTwinkle = Metric([0.15, 0.3], .anatomy("bin:0x100aeaab4: on each hover change (in and out) isHovered is set and twinkle1 toggled; asyncAfter 0.15 toggles twinkle1 and twinkle2 (bin:0x100aeb00c), asyncAfter 0.3 toggles twinkle2 (bin:0x100aeb11c); those two land without animation; nothing at all happens with Reduce Motion on"))
    let libraryIconBox = Metric([0.0, 3.5, 0.9], .anatomy("bin:0x100aea9a8: Image(box).offset(0, 3.5).opacity(0.9); ~/brk-arc-reference/Q19/Q19-edge-210-arc.png puts the box 750 to 758.5 in the 735 to 767 button"))
    let libraryIconStar = Metric([-2.5, -3.0, -9.0, -2.5, -4.5, 105.0], .anatomy("bin:0x100ae9850 to bin:0x100ae99ac: rest offset (-2.5, -3) turned -0.15708 rad, hovered (-2.5, -4.5) turned 1.8326 rad"))
    let libraryIconStarMask = Metric([0.0, -8.0, 28.0, 11.0], .anatomy("bin:0x100ae9a74, bin:0x10369d0c0: the star is masked by a 28 x 11 rectangle moved (0, -8), so it shows only above the box"))
    let libraryIconTriangle = Metric([4.5, -3.5, 225.0, 6.5, -5.0, 85.0, 0.15, 0.2], .anatomy("bin:0x100ae9e74 to bin:0x100ae9fa0: rest (4.5, -3.5) turned 3.927 rad, hovered (6.5, -5) turned 1.4835 rad; twinkle1 scales it to 0.15 and fades it to 0.2"))
    let libraryIconDot = Metric([2.0, -7.5, 3.0, -10.0, 0.1, 0.2], .anatomy("bin:0x100aea434 to bin:0x100aea490: rest (2, -7.5), hovered (3, -10); twinkle2 scales it to 0.1 and fades it to 0.2"))
    let libraryIconGlow = Metric([0.0, -7.0, 0.275, 0.4, 0.3, 0.875, 0.56], .anatomy("bin:0x100ae9548 to bin:0x100ae973c, bin:0x10369d0a0: Image(glow) 81 x 27 scaled (0.275, 0.4), moved (0, -7), white at 0.3 while hovered, blur 0.875, shown in a dark scheme only; ARCUI's glow.pdf foot is 0.56 of its top"))
    let libraryIconShine = Metric([1.0, 1.0, 2.0, 0.2, 2.0], .anatomy("bin:0x100ae99b4, bin:0x100aea0b8, bin:0x100aea500, bin:0x100ae9254: in a dark scheme while hovered the star, triangle and dot get a white shadow of radius 1, 1 and 2, and the whole picture one at 0.2 of radius 2"))
    let inactiveSpaceAlpha = Metric(0.45, .anatomy("cra L115: inactive space icons in the dock are dimmed; amount guessed"))

    // States and motion.
    let busyAlpha = Metric(0.5, .guess("the Tidy button while a tidy runs; amount guessed"))
    let dragThreshold = Metric(3.0, .guess("pointer travel before a press becomes a drag (AppKit's own threshold)"))
    let dragPreviewAlpha = Metric(0.8, .anatomy("~/brk-arc-reference/Q13/Q13-g-arc.png: the row image reads #E6E6E7 over the #A7ABAD strip and #F5 over the #EF sidebar"))
    let dragPreviewShadowOffset = Metric(1.0, .anatomy("~/brk-arc-reference/Q13/Q13-c-arc.png: a little darker under the tile than beside it"))
    let dragPreviewShadowOpacity = Metric(0.25, .anatomy("~/brk-arc-reference/Q13/Q13-c-arc.png: black at about 8% at the tile's edge, under the image's own 0.8"))
    let dragTileRingOpacity = Metric(0.5, .anatomy("~/brk-arc-reference/Q13/Q13-c-arc.png: the dragged tile's ring reads #EAEAEB against its #F6F7F9 fill"))
    let rowTitleOverButton = Metric(28.0, .anatomy("~/brk-arc-reference/Q15/Q15-e-arc.png: with the × showing the title may reach 28 from the row's right end"))
    let dragRowOverHeaderScale = Metric(0.875, .anatomy("~/brk-arc-reference/Q13/Q13-g-arc.png: the row image over the Space name strip is 186 x 31 for the 212 x 36 row"))
    let dropHintAlpha = Metric(0.475, .anatomy("2a96a9d7f0:verify/visual-pairs/run-20261103: a drop area is the theme's focus color at this strength: Q13-g's strip and Q15-e's band #A7ABAD over #F0F7FC with focus #575757, P23-e's slot #82A9A8 over #FCFCFC with focus #006362"))
    let splitJoinTitleTrailing = Metric(3.0, .anatomy("~/brk-arc-reference/Q15/Q15-a-arc.png and Q15-b-arc.png: the row's own title ends 3 pt before the end of its half"))
    let splitJoinSlotInset = Metric(6.0, .anatomy("~/brk-arc-reference/Q15/Q15-a-arc.png and Q15-b-arc.png: the slots span x 14 to 114 and 120 to 220, each half of the 8 to 220 row less 6 at its left"))
    let dropRingSide = Metric(7.0, .anatomy("~/brk-arc-reference/Q13/Q13-d-arc.png: the ring at the drop line's left end spans 7 pt"))
    let dropRingLeading = Metric(16.0, .anatomy("~/brk-arc-reference/Q13/Q13-d-arc.png: the ring starts 16 from the sidebar's edge"))
    let dropLineTrailing = Metric(11.0, .anatomy("~/brk-arc-reference/Q13/Q13-d-arc.png: the line ends 217 along the 228 sidebar"))
    let favoritesReflow = Metric(0.28, .anatomy("1cc6fa9011:verify/visual-pairs/run-20261103/Q21/NOTES.md: in Q21-arc-reorder-right.mov the neighbouring tile's 55 pt slide reads 10, 40, 53, 65, 74, 81, 86, 91, 94, 96, 98, 99, 100 percent in successive 1/60 s frames, a critically damped spring of response 0.25; this length with `favoritesReflowCurve` stays within 2 percent of it"))
    let favoritesReflowCurve = Metric([0.25, 0.25, 0.15, 1.0], .anatomy("1cc6fa9011:verify/visual-pairs/run-20261103/Q21/NOTES.md: the timing curve fitted to the same frames"))
    let dropLanding = Metric(0.3, .anatomy("1cc6fa9011:verify/visual-pairs/run-20261103/Q21/NOTES.md: let go 23 pt from its cell, Arc's dragged tile glides into it in 17 frames, ease-out (9, 17, 35, 41, 50, 57, 63, 70, 74, 80, 85, 89, 93, 96, 98, 100 percent); 13 pt away it takes 16"))
    let renameHintInk = Metric(0.5, .anatomy("~/brk-arc-reference/Q13/Q13-h-arc.png: its darkest pixels read #858686, the title's #1A1A1A"))
    let currentTileShadow = Metric(2.0, .anatomy("~/brk-arc-reference/Q13/Q13-n5-arc.png: the current tile's shadow fades over about 4 pt"))
    let currentTileShadowOpacity = Metric(0.11, .anatomy("~/brk-arc-reference/Q13/Q13-n5-arc.png: #F2 against the #FD sidebar at the tile's edge"))
    let pressedTileShade = Metric(0.02, .anatomy("~/brk-arc-reference/Q13/Q13-press-favorite-arc.png: a pressed tile reads #F7F7F7, the current tile #FBFBFB"))
    let rowCloseGlyph = Metric(13.5, .anatomy("~/brk-arc-reference/Q13/Q13-press-row-arc.png: the row's × is 10 pt across"))
    let renameHintFont = Metric(11.0, .anatomy("~/brk-arc-reference/Q13/Q13-h-arc.png: \"Double-click to rename\" is 119.5 pt wide"))
    let renameHintTitleShift = Metric(-7.0, .anatomy("~/brk-arc-reference/Q13/Q13-h-arc.png: the title's ink spans 192 to 202.5 in the row at 186...221.5"))
    let renameHintTop = Metric(21.5, .anatomy("~/brk-arc-reference/Q13/Q13-h-arc.png: the hint's ink spans 208 to 216 in that row"))
    let dragSourceAlpha = Metric(0.3, .guess("opacity of the row left behind while it is dragged"))
    let dragPreviewShadow = Metric(14.0, .anatomy("~/brk-arc-reference/Q13/Q13-c-arc.png: the tile's shadow is half gone 5 pt out and nearly gone at 10 (an NSShadow's blur is about twice its spread)"))
    // The card a tab drag shows over the content (P23-d-arc.png: card x 989.5...1158.5, y 273.5...523.5 in the window).
    let dragCardRadius = Metric(18.0, .anatomy("~/brk-arc-reference/P23/P23-d-arc.png: the card's edge is 13 pt in 1 pt below its top and meets the side 17 pt down"))
    let dragCardIcon = Metric(16.0, .anatomy("~/brk-arc-reference/P23/P23-d-arc.png: the empty favicon is a 14 pt square, the row's 16 pt slot"))
    let dragCardTitleFont = Metric(13.0, .anatomy("~/brk-arc-reference/P23/P23-d-arc.png: \"Interface comparison\" is 137 pt wide in bold, SF 13 bold"))
    let dragCardTitleGap = Metric(24.0, .anatomy("~/brk-arc-reference/P23/P23-d-arc.png: 24 from the icon's slot to the title's line; the two sit centred in the card, also with Q17-split-hold's three lines"))
    let dragCardInset = Metric(9.0, .anatomy("~/brk-arc-reference/Q17/Q17-split-hold-1012-330-arc.png: in the 113 pt card the label wraps \"Long title for\" / \"truncation\" / \"and readab…\": an NSTextField of width 93 to 97 does that (it keeps about 4 pt of its own on each side), so 8 to 10 from each edge; \"Interface comparison\" stays on one line in 169 (P23-d)"))
    let dragCardTitleLines = Metric(3, .anatomy("~/brk-arc-reference/Q17/Q17-split-hold-1012-330-arc.png: three lines, the last truncated"))
    let dragCardShadow = Metric(20.0, .anatomy("~/brk-arc-reference/P23/P23-d-arc.png: the card's shadow fades over about 16 pt at the sides and 20 below"))
    let dragCardShadowOpacity = Metric(0.2, .anatomy("~/brk-arc-reference/P23/P23-d-arc.png: #DDDDDD right under the card on the white page"))
    let dropLineWidth = Metric(2.0, .guess("drop indicator thickness (DragHintHighlighted)"))
    // The split preview over a tab row's middle (P23-e-arc.png: capsule x 15...233.5, slot from 15, chip 22...114,
    // "Seconda…" from 150, × centred at 216 in the window).
    /// Saturation (a share of the theme's, capped at 0.5 like `HueInk`) and lightness of the slot and the chip.
    let selectedShadowRadius = Metric(1.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-a: Arc's current tab card has a 1.5 pt shadow line under its lower edge, darkest at the edge"))
    let selectedShadowOffset = Metric(1.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-a: the shadow line sits under the card, not around it"))
    let floatingShadowRadius = Metric(16.0, .guess("floating sidebar shadow blur; not recovered (layout-constants.md, Not recovered)"))
    let floatingDismissPoll = Metric(1.0 / 30, .guess("seconds between pointer checks while the floating sidebar waits to close"))
    let autoScrollStep = Metric(8.0, .guess("points per drag sample when dragging near the list's top or bottom edge"))
    let hairline = Metric(1.0, .anatomy("cra L748: 1 pt hairlines (list edges); also the separator, the floating border and the empty favorites box"))
    let floatingGradientAlpha = Metric(0.92, .guess("opacity of the theme gradient over the blurred page in the floating sidebar"))
}

/// Colors the sidebar needs that `SidebarTokens` does not carry (visual-and-copy.md, section 1). Black or white by
/// scheme, like every sidebar token.
struct Ink {
    let scheme: Scheme
    /// The space's primary color: light titles take its hue (`sidebarInk`).
    var accent = RGBA(0.5, 0.5, 0.5)

    private func bw(_ lightAlpha: Double, _ darkAlpha: Double) -> NSColor {
        scheme == .light ? NSColor(white: 0, alpha: lightAlpha) : NSColor(white: 1, alpha: darkAlpha)
    }

    /// Row titles. Light: the theme's own near-black (`sidebarInk`; Arc writes a #F2EAE4 space's rows in #221910, not
    /// the ForegroundPrimary token #0E0F10 @ 0.9). Dark: #FFFFFF @ 0.8 (Base tokens).
    var text: NSColor {
        guard scheme == .light else { return NSColor(white: 1, alpha: 0.8) }
        let ink = sidebarInk(accent)
        return NSColor(srgbRed: ink.red, green: ink.green, blue: ink.blue, alpha: 1)
    }
    /// CommandBarPlaceholderText @ 0.6: the URL in the pill, and enabled title-row glyphs (cra L1220: ~59%).
    var secondary: NSColor { bw(0.6, 0.6) }
    /// CommandBarPlaceholderPlaceholderText @ 0.3: "Search or Enter URL…".
    var placeholder: NSColor { bw(0.3, 0.3) }
    /// The magnifier before the placeholder (Q23: darker than the placeholder, lighter than an address).
    var searchGlyph: NSColor { bw(Draw.pillSearchGlyphInk.value, Draw.pillSearchGlyphInk.value) }
    /// TabCellSlash: black or white @ 0.3, the stroke between split panes in one row.
    var slash: NSColor { bw(0.3, 0.3) }
    /// LoadingPageBorder: #0C50FF light, #2AB6F6 dark.
    var loading: NSColor {
        scheme == .light ? NSColor(srgbRed: 12 / 255, green: 80 / 255, blue: 1, alpha: 1)
            : NSColor(srgbRed: 42 / 255, green: 182 / 255, blue: 246 / 255, alpha: 1)
    }
    /// PopoverShadow: #151C32 @ 0.3 light, @ 0.8 dark. The floating sidebar's shadow.
    var shadow: NSColor { NSColor(srgbRed: 21 / 255, green: 28 / 255, blue: 50 / 255, alpha: scheme == .light ? 0.3 : 0.8) }
    /// The current favorite's fill, white over the sidebar and the tile's own shadow (`AppTrayItemBackgroundView`).
    var tileCurrent: NSColor { NSColor(white: 1, alpha: scheme == .light ? Draw.tileCurrentLight.value : Draw.tileCurrentDark.value) }
}

extension Palette {
    var ink: Ink { Ink(scheme: scheme, accent: accent) }
    /// Today's Clear and Tidy at rest: the sidebar foreground, lighter on a dark theme.
    var clearInk: NSColor { scheme == .dark ? NSColor(white: 1, alpha: Draw.clearInkDark.value) : color(tokens.foreground) }
}

/// Arc's copy that `Copy` does not hold yet (visual-and-copy.md section 3, unless noted).
enum SidebarCopy {
    /// Arc: "Subtitle shown on tab with hint on how to rename tab." (Q13-h)
    static let renameHint = "Double-click to rename"
    /// Arc's banner title and button, Swift small strings in the code that fills its state (bin:0x1025517b0, 0x102551890).
    static let archiveEducationTitle = "We cleaned up!"
    static let archiveEducationDismiss = "Got it"
    static let closeKeepPinned = "Close and Keep Pinned"
    /// The group header's × (bin:0x10004866c, a Swift small string; its comment: "Tooltip for the button to close a
    /// group of tabs in the sidebar").
    static let closeTabGroup = "Close tab group"
    static let refreshLiveFolder = "Refresh Live Folder"
    static let livePageChanged = "New data since you last looked"
    static let livePageStopped = "The last refresh stopped"

    /// The note in an open Live Folder without rows.
    static func liveFolderNote(_ state: LiveFolderState) -> String {
        switch state {
        case .loading: "Loading pull requests…"
        case .empty, .ready: "No open pull requests"
        case .failed: "Couldn’t refresh. Try Again"
        case .notLoaded: "Not refreshed yet. Refresh"
        case .stale: "Refresh to update"
        }
    }

    /// The Live Folder row's tooltip: its source and how fresh it is.
    static func liveFolderTip(_ live: LiveFolderSnapshot) -> String {
        let state: String = switch live.state {
        case .loading: "Refreshing…"
        case .ready(let n): n == 1 ? "1 open pull request" : "\(n) open pull requests"
        case .empty: "No open pull requests"
        case .stale: "Refresh to update"
        case .notLoaded: "Not refreshed since launch"
        case .failed(let message): message
        }
        return "GitHub · \(live.source)\n\(state)"
    }
    static let collapsePinned = "Collapse Pinned Tabs"
    static let expandPinned = "Expand Pinned Tabs"
    /// cra L1215: the title-row buttons' accessibility names.
    static let goBack = "Go back"
    static let goForward = "Go forward"
    static let reload = "Reload"
    static let stop = "Stop"
    static let showHideSidebar = "Show/Hide Sidebar"
    /// The dock's left button opens the Library (Arc's `HomeButton`, "View Library").
    static let library = "Library"
    static let copyLink = "Copy Link"
    // Arc's tooltips on the speaker and the mini player (bin:0x1002b4f84, bin:0x1002b5038, bin:0x10249b63c, bin:0x10249c1f0,
    // bin:0x10249e37c, bin:0x102495738).
    static let muteThisTab = "Mute this tab"
    static let unmuteThisTab = "Unmute this tab"
    static let closeMiniPlayer = "Close Mini Player"
    static let backToTab = "Back to Tab"
    static let previousTrack = "Previous Track"
    static let nextTrack = "Next Track"
    static let adjustTabVolume = "Adjust Tab Volume"
    static let pauseMedia = "Pause"
    static let playMedia = "Play"
    static let newSpaceMenu = "New…"
    /// Arc's title for a new tab before its first document commits.
    static let untitled = "Untitled"
    static let spaceOptions = "Space Options"
    static let dismiss = "Dismiss"
}

/// The dock's Space dots as another column draws them: the AI panel's page dots (docs/design/ai-threads.md) look the same.
public enum DockDots {
    public static var size: Double { Draw.dockDot.value }
    /// Black (white on dark) at this alpha for the current page's dot, and for the others.
    public static var activeInk: Double { Draw.dockActiveInk.value }
    public static var inactiveInk: Double { Draw.dockInactiveInk.value }
}
