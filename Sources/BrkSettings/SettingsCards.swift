import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

// Arc 1.170's settings look (the P38 captures in verify/visual-pairs/run-20261103/): every pane is groups of rows in
// light rounded cards, a switch at the right of a row, a push button or pop-up beside a label. These are the pieces
// the panes build from; every number is in `CardMetrics`, measured on the 2x captures.

private var C: SettingsCardMetricsTable { CardMetrics }

/// The window's colours, measured on the captures (light appearance) and given a dark counterpart.
enum SettingsStyle {
    /// Row labels: #505050 on the card.
    static let text = Color.primary.opacity(0.8)
    /// Descriptions under a title (#8C8C8C).
    static let secondaryText = Color.primary.opacity(0.53)
    /// Section headers above a card ("Your Data and Settings", #ADADAD) and list headers (#9E9E9E).
    static let header = Color.primary.opacity(0.42)
    /// The small notes ("Note: This only affects Favorites and Pinned tabs", #9C9C9C).
    static let note = Color.primary.opacity(0.45)
    static let link = Color(nsColor: .linkColor)
    static let cardFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0xFC / 255.0, alpha: 1)
    })
    static let cardBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.1) : NSColor(white: 0xEA / 255.0, alpha: 1)
    })
    static let font = Font.system(size: C.fontSize.value)
}

/// A group of rows in one rounded card. Put `CardDivider()` between the rows.
struct SettingsCard<Content: View>: View {
    var fill: Color = SettingsStyle.cardFill
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: C.cornerRadius.value, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: C.cornerRadius.value, style: .continuous).strokeBorder(SettingsStyle.cardBorder, lineWidth: C.borderWidth.value))
    }
}

/// The hairline between two rows of a card, inset from both edges.
struct CardDivider: View {
    var inset: CGFloat = CardMetrics.dividerInset.value

    var body: some View {
        Rectangle().fill(SettingsStyle.cardBorder).frame(height: C.borderWidth.value).padding(.horizontal, inset)
    }
}

/// One row of a card: a label (or anything) at the left, a control at the right, at least `height` tall.
struct CardRow<Leading: View, Trailing: View>: View {
    var height: CGFloat = CardMetrics.rowHeight.value
    /// The least space between the label and the control.
    var gap: CGFloat = CardMetrics.controlGap.value
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            leading
            Spacer(minLength: gap)
            trailing
        }
        .padding(.horizontal, C.rowPadding.value)
        .frame(minHeight: height)
    }
}

/// A row label in the card text style.
struct CardLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(SettingsStyle.font).foregroundStyle(SettingsStyle.text).fixedSize(horizontal: false, vertical: true)
    }
}

/// A row with a switch at its right, for one Bool setting.
struct SwitchRow: View {
    let title: String
    let field: String
    let isOn: Bool
    var height: CGFloat = CardMetrics.rowHeight.value
    let toggle: @MainActor (Bool) -> Void

    var body: some View {
        CardRow(height: height) { CardLabel(title) } trailing: { SettingsSwitch(field: field, isOn: isOn, toggle: toggle) }
    }
}

/// A row with a push button at its right.
struct ButtonRow: View {
    let title: String
    let button: String
    let field: String
    var height: CGFloat = CardMetrics.buttonRowHeight.value
    let action: @MainActor () -> Void

    var body: some View {
        CardRow(height: height) { CardLabel(title) } trailing: { SettingsButton(title: button, field: field, action: action) }
    }
}

/// The square icon at the start of an Advanced row (Arc: a white SF Symbol on a coloured rounded square).
struct RowIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = CardMetrics.rowIconSize.value

    var body: some View {
        RoundedRectangle(cornerRadius: size * C.rowIconRadiusRatio.value, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * C.rowIconGlyphRatio.value, weight: .medium)).foregroundStyle(.white))
    }
}

/// The pane's header above a card ("Your Data and Settings").
struct CardHeader: View {
    let text: String

    var body: some View {
        Text(text).font(SettingsStyle.font).foregroundStyle(SettingsStyle.header).padding(.leading, C.rowPadding.value)
    }
}

/// Text with one tappable phrase in the link colour (SwiftUI's own links open URLs; these run an action).
struct LinkedText: View {
    let parts: [Part]
    var font: Font = SettingsStyle.font
    var color: Color = SettingsStyle.text
    var underline = false
    let open: @MainActor (String) -> Void

    enum Part {
        case text(String)
        case link(String, id: String)
    }

    var body: some View {
        Text(attributed).font(font).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                MainActor.assumeIsolated { open(url.host ?? url.absoluteString) }
                return .handled
            })
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for part in parts {
            switch part {
            case .text(let text): result += AttributedString(text)
            case .link(let text, let id):
                var link = AttributedString(text)
                link.link = URL(string: "brk-settings://\(id)")
                link.foregroundColor = SettingsStyle.link
                if underline { link.underlineStyle = .single }
                result += link
            }
        }
        return result
    }
}

/// A settings sub-page inside the pane (Arc's "…Settings…" buttons and the Profiles data rows): a back button and a
/// title over the page's own cards.
struct Subpage<Content: View>: View {
    let title: String
    let back: @MainActor () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: C.cardSpacing.value) {
            HStack(spacing: C.controlGap.value) {
                SettingsButton(title: SettingsCopy.back, field: "subpageBack", symbol: "chevron.left", action: back)
                Text(title).font(.system(size: C.fontSize.value, weight: .semibold)).foregroundStyle(SettingsStyle.text)
            }
            content
        }
    }
}

// MARK: - Switch

/// A switch for one Bool setting (SwiftUI's `.switch` toggle is this control underneath), at Arc's size: AppKit's
/// mini switch. `field` names it (`settings-field-<field>`). Like the checkbox, it shows only the snapshot: a click
/// asks for the change and the next render shows the answer.
struct SettingsSwitch: View {
    let field: String
    let isOn: Bool
    let toggle: @MainActor (Bool) -> Void

    // SwiftUI hands its control size to the AppKit control inside a representable, so it is set here.
    var body: some View { SwitchControl(field: field, isOn: isOn, toggle: toggle).controlSize(.mini) }
}

struct SwitchControl: NSViewRepresentable {
    let field: String
    let isOn: Bool
    let toggle: @MainActor (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSSwitch {
        let control = NSSwitch()
        control.target = context.coordinator
        control.action = #selector(Coordinator.clicked(_:))
        control.controlSize = .mini
        return control
    }

    func updateNSView(_ control: NSSwitch, context: NSViewRepresentableContext<Self>) {
        context.coordinator.isOn = isOn
        context.coordinator.toggle = toggle
        control.isEnabled = context.environment.isEnabled
        control.controlSize = .mini
        control.identify(.settingsField(field))
        let state: NSControl.StateValue = isOn ? .on : .off
        if control.state != state { control.state = state }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView control: NSSwitch, context: NSViewRepresentableContext<Self>) -> CGSize? {
        control.intrinsicContentSize
    }

    @MainActor final class Coordinator: NSObject {
        var isOn = false
        var toggle: (@MainActor (Bool) -> Void)?

        @objc func clicked(_ sender: NSSwitch) {
            let wanted = sender.state == .on
            if wanted != isOn { toggle?(wanted) }
            // A synchronous answer already re-rendered `isOn`; otherwise wait for the snapshot.
            let shown: NSControl.StateValue = isOn ? .on : .off
            if sender.state != shown { sender.state = shown }
        }
    }
}

// MARK: - Metrics

extension SettingsCardMetricsTable {
    /// The pane's area before the window has measured its own title bar and toolbar.
    var paneSize: CGSize {
        let window = Metrics.settings.windowSize.value
        return CGSize(width: window.width, height: window.height - toolbarHeight.value)
    }
}

/// The card look's numbers. Measured on Arc 1.170's 2x captures (P38-a/b/d/e/f/g/h), halved to points.
let CardMetrics = SettingsCardMetricsTable()

struct SettingsCardMetricsTable: MetricGroup {
    private static let capture = "verify/visual-pairs/run-20261103/P38"
    let toolbarHeight = Metric(88.0, .anatomy("\(capture)/P38-a-arc.png: the title bar and pane toolbar end at the hairline at y 174 to 176 px"))
    let fontSize = Metric(13.0, .anatomy("\(capture)/P38-a-arc.png: the P stem of 'Previews' is 19 px, the same as a 13 pt label"))
    let paneTop = Metric(20.0, .anatomy("\(capture)/P38-a-arc.png: toolbar hairline at y 174 px, first card at 216 px"))
    let paneInset = Metric(64.0, .anatomy("\(capture)/P38-a-arc.png: cards span x 128 to 1240 px of 1368"))
    let cornerRadius = Metric(7.0, .anatomy("\(capture)/P38-a-arc.png: the card's corner curve spans about 14 px"))
    let borderWidth = Metric(1.0, .anatomy("\(capture)/P38-a-arc.png: 2 px #EAEAEA card edge and row hairline"))
    let cardSpacing = Metric(8.0, .anatomy("\(capture)/P38-a-arc.png: card 1 ends at y 362 px, card 2 starts at 378 px"))
    let rowPadding = Metric(10.0, .anatomy("\(capture)/P38-a-arc.png: labels start at x 148 px, switches end at 1220 px"))
    let dividerInset = Metric(10.0, .anatomy("\(capture)/P38-a-arc.png: the second card's hairline spans x 148 to 1220 px"))
    let controlGap = Metric(8.0, .guess("space between a row's label and its control"))
    let switchSize = Metric(CGSize(width: 36, height: 16), .anatomy("\(capture)/P38-d-arc.png: the switch track spans x 1148 to 1220 px, y 520 to 552 px (AppKit's mini switch)"))
    let popUpChrome = Metric(44.0, .anatomy("\(capture)/P38-f-arc.png: '6 hours (default)' is about 104 pt of text in a 148.5 pt pop-up"))
    let popUpImageGap = Metric(4.0, .guess("space after a pop-up item's icon"))
    let profilePopUpMinimum = Metric(135.0, .anatomy("\(capture)/P38-d-arc.png: the Google and Downloads pop-ups are 135 to 136 pt wide"))
    let rowHeight = Metric(36.0, .anatomy("\(capture)/P38-a-arc.png: switch rows 216 to 288 to 360 px"))
    let buttonRowHeight = Metric(42.0, .anatomy("\(capture)/P38-a-arc.png: the Previews row spans y 378 to 462 px"))
    let iconRowHeight = Metric(40.0, .anatomy("\(capture)/P38-g-arc.png: Advanced rows 216 to 296 to 376 px"))
    let rowIconSize = Metric(20.0, .anatomy("\(capture)/P38-g-arc.png: the speaker square spans x 148 to 188 px"))
    let rowIconRadiusRatio = Metric(0.24, .guess("the Advanced squares' corner, about 5 pt of 20"))
    let rowIconGlyphRatio = Metric(0.55, .guess("the white symbol inside an Advanced square"))
    let rowIconGap = Metric(9.0, .anatomy("\(capture)/P38-g-arc.png: square ends at x 188 px, its label starts at 206 px"))
    let advancedCardSpacing = Metric(10.0, .anatomy("\(capture)/P38-g-arc.png: card 1 ends at y 378 px, card 2 starts at 398 px"))
    let bottomButtonsGap = Metric(10.0, .anatomy("\(capture)/P38-g-arc.png: last card ends near y 1008 px, buttons start at 1028 px"))
    let buttonGap = Metric(8.0, .anatomy("\(capture)/P38-g-arc.png: More Settings… ends at x 366 px, the next button starts at 382 px"))
    let twoLineRowHeight = Metric(48.0, .anatomy("\(capture)/P38-a-arc.png: the two-line Profile Settings row spans y 462 to 558 px"))
    let iconTwoLineRowHeight = Metric(50.0, .anatomy("\(capture)/P38-g-arc.png: the Shared Quotes row spans y 642 to 742 px"))
    let popUpRowHeight = Metric(44.5, .anatomy("\(capture)/P38-f-arc.png: the Archive Little Arcs row spans y 826 to 914 px"))
    let popUpTrailing = Metric(26.0, .anatomy("\(capture)/P38-f-arc.png: the pop-up ends at x 1168 px, the row's switches at 1220 px"))
    let wrappedLabelWidth = Metric(340.0, .anatomy("\(capture)/P38-a-arc.png: 'Manage your default search engine, Auto-Archive, and' wraps at x 806 px"))
    let subtitleGap = Metric(4.0, .anatomy("\(capture)/P38-f-arc.png: the Peek title and its Note are 40 px apart"))
    let noteFontSize = Metric(12.0, .anatomy("\(capture)/P38-g-arc.png: the Shared Quotes subtitle is a size smaller than its title"))
    let introTop = Metric(23.5, .anatomy("\(capture)/P38-f-arc.png: the banner's wave is lowest at y 446 px, the paragraph's first line is centred at 511 px"))
    let introToCard = Metric(24.0, .anatomy("\(capture)/P38-f-arc.png: the paragraph's last line is centred at 543 px, the card starts at 606 px"))
    let sheetSize = Metric(CGSize(width: 422, height: 372), .anatomy("verify/visual-pairs/run-20261103/P13/P13-settings-arc.png: the sheet spans x 263 to 1105 px, y 278 to 1022 px"))
    let sheetPadding = Metric(24.0, .anatomy("verify/visual-pairs/run-20261103/P13/P13-settings-arc.png: the title starts at x 310 px, the Done button ends at 1058 px"))
    let sheetTop = Metric(24.0, .anatomy("verify/visual-pairs/run-20261103/P13/P13-settings-arc.png: the title is centred at y 344 px"))
    let sheetBottom = Metric(22.0, .anatomy("verify/visual-pairs/run-20261103/P13/P13-settings-arc.png: Done ends at y 978 px"))
    let sheetTitleGap = Metric(8.0, .anatomy("verify/visual-pairs/run-20261103/P13/P13-settings-arc.png: title centred at y 344 px, the paragraph at 392 px"))
    let sheetListTop = Metric(16.0, .anatomy("verify/visual-pairs/run-20261103/P13/P13-settings-arc.png: Learn more centred at y 456 px, the first box at 511 px"))
    let sheetRowGap = Metric(12.0, .anatomy("verify/visual-pairs/run-20261103/P13/P13-settings-arc.png: boxes 57 px apart"))
    let keyGlyphPadding = Metric(4.0, .guess("the ↩ box inside Done"))
    let doneRadius = Metric(6.0, .anatomy("verify/visual-pairs/run-20261103/P13/P13-settings-arc.png: Done is a rounded rectangle, not a capsule"))
    let sheetDoneTop = Metric(24.0, .anatomy("verify/visual-pairs/run-20261103/P13/P13-settings-arc.png: the last box is centred at y 852 px, Done starts at 902 px"))
    let keyGlyphRadius = Metric(4.0, .guess("the ↩ box's corner"))
    let popoverWidth = Metric(320.0, .guess("a Learn more popover"))
    let introLineSpacing = Metric(0.0, .anatomy("\(capture)/P38-f-arc.png: paragraph lines 32 px apart, a 13 pt line"))
    let peekNoteRowHeight = Metric(56.5, .anatomy("verify/visual-pairs/run-20261103/Q06/Q06-links-bottom-arc.png: the other-sites Peek row with its Note spans y 913 to 1025 px"))
    let routesRowHeight = Metric(44.5, .anatomy("verify/visual-pairs/run-20261103/Q06/Q06-links-bottom-arc.png: the Air Traffic Control card spans y 1125 to 1211 px"))
    let linksBottom = Metric(43.5, .anatomy("verify/visual-pairs/run-20261103/Q06/Q06-links-bottom-arc.png: scrolled to the end, the Air Traffic Control card ends at y 1211 px of a 1300 px window"))
    let infoGap = Metric(6.0, .anatomy("verify/visual-pairs/run-20261103/Q06/Q06-links-bottom-arc.png: 'Arc.' ends at x 584 px, the ⓘ starts at 596 px"))
    let infoSize = Metric(14.0, .anatomy("verify/visual-pairs/run-20261103/Q06/Q06-links-bottom-arc.png: the ⓘ spans x 596 to 622 px"))
    let sectionRule = Metric(24.0, .anatomy("verify/visual-pairs/run-20261103/Q06/Q06-links-bottom-arc.png: a card ends at y 629 px, the rule spans 678 to 680 px"))
    let sectionRuleBelow = Metric(23.5, .anatomy("verify/visual-pairs/run-20261103/Q06/Q06-links-bottom-arc.png: the second rule ends at y 1076 px, the next card starts at 1124 px"))
}
