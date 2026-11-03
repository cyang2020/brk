import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// The Icon pane as Arc 1.170 lays it out (P38-h): one card listing the app icons, each row a round radio, the icon
/// and its name; the chosen one says "CURRENT ICON". Choosing one dispatches `.settings(.general(.appIcon(_)))`;
/// BrkApp shows it in the Dock and the About window.
struct IconPane: View {
    let context: PaneContext
    private var current: AppIconChoice { context.settings.general.appIcon ?? .original }

    var body: some View {
        CardPane {
            SettingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(AppIconChoice.allCases.enumerated()), id: \.element) { index, choice in
                        if index > 0 {
                            Rectangle().fill(SettingsStyle.cardBorder).frame(height: CardMetrics.borderWidth.value)
                                .padding(.leading, I.dividerLeading.value).padding(.trailing, I.dividerTrailing.value)
                        }
                        row(choice)
                    }
                }
                .padding(.vertical, I.cardPadding.value)
            }
        }
    }

    private func row(_ choice: AppIconChoice) -> some View {
        HStack(spacing: 0) {
            RadioDot(on: choice == current).frame(width: I.radio.value, height: I.radio.value)
            Image(nsImage: AppIconArt.image(choice, side: I.iconCanvas.value))
                .resizable()
                .frame(width: I.iconCanvas.value, height: I.iconCanvas.value)
                .padding(.leading, I.iconLeading.value)
            VStack(alignment: .leading, spacing: I.badgeGap.value) {
                Text(AppIconArt.name(choice)).font(.system(size: I.nameSize.value, weight: .semibold)).foregroundStyle(.primary)
                if choice == current {
                    Text(IconCopy.current).font(.system(size: I.badgeSize.value, weight: .semibold)).kerning(I.badgeKerning.value)
                        .foregroundStyle(SettingsStyle.link)
                }
            }
            .padding(.leading, I.nameLeading.value)
            Spacer(minLength: 0)
        }
        .padding(.leading, I.radioLeading.value)
        .frame(height: I.rowHeight.value)
        .background(ClickArea(field: "appIcon-\(choice.rawValue)") {
            if choice != current { context.dispatch(.settings(.general(.appIcon(choice)))) }
        })
    }
}

/// Arc's large radio button: a blue ring around a blue dot when chosen, a grey ring otherwise.
struct RadioDot: View {
    let on: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Color(nsColor: .controlAccentColor) : Color.primary.opacity(0.25), lineWidth: I.radioRing.value)
            if on { Circle().fill(Color(nsColor: .controlAccentColor)).padding(I.radioDotInset.value) }
        }
    }
}

enum IconCopy {
    /// Observed (P38-h).
    static let current = "CURRENT ICON"
}

private var I: IconPaneMetricsTable { IconPaneMetrics }

let IconPaneMetrics = IconPaneMetricsTable()

struct IconPaneMetricsTable: MetricGroup {
    private static let capture = "verify/visual-pairs/run-20261103/P38/P38-h-arc.png"
    let cardPadding = Metric(9.5, .anatomy("\(capture): the card starts at y 216 px, the first row is centred at 316 px"))
    let rowHeight = Metric(81.0, .anatomy("\(capture): rows centred at y 316, 478, 640 px"))
    let radioLeading = Metric(16.0, .anatomy("\(capture): the radio starts at x 160 px in a card that starts at 128 px"))
    let radio = Metric(22.0, .anatomy("\(capture): the radio spans x 160 to 204 px"))
    let radioRing = Metric(1.5, .anatomy("\(capture): a 3 px ring"))
    let radioDotInset = Metric(4.0, .anatomy("\(capture): the chosen dot leaves a white ring of about 4 px"))
    /// The icon image includes the macOS grid margin, so the squircle lands where Arc's does (x 256 to 360 px).
    let iconCanvas = Metric(64.0, .anatomy("\(capture): the icon's tile spans x 256 to 360 px; a 64-point canvas has a 51.5-point tile"))
    let iconLeading = Metric(20.0, .anatomy("\(capture): the radio ends at x 204 px, the tile starts at 256 px"))
    let nameLeading = Metric(8.0, .anatomy("\(capture): the tile ends at x 360 px, the name starts at 388 px"))
    let nameSize = Metric(14.0, .guess("the icon names are a bolder, slightly larger line than the rows"))
    let badgeSize = Metric(11.0, .guess("'CURRENT ICON' under the name"))
    let badgeKerning = Metric(0.4, .guess("the small capitals are spaced a little"))
    let badgeGap = Metric(2.0, .anatomy("\(capture): the name centred at y 299 px, CURRENT ICON at 337 px"))
    let dividerLeading = Metric(40.0, .anatomy("\(capture): hairlines start at x 208 px"))
    let dividerTrailing = Metric(40.0, .anatomy("\(capture): hairlines end at x 1160 px of a card ending at 1240 px"))
}

extension AppIconArt {
    /// The drawing for the Icon pane's choice (one to one, by name).
    @MainActor public static func image(_ choice: AppIconChoice, side: CGFloat) -> NSImage { image(Variant(rawValue: choice.rawValue) ?? .original, side: side) }

    public static func name(_ choice: AppIconChoice) -> String { name(Variant(rawValue: choice.rawValue) ?? .original) }
}
