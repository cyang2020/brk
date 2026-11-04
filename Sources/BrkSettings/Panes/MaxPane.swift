import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// The Max pane as Arc 1.170 lays it out (P38-b, P38-c, P38-max-on, P38-max-list): the MAX banner, Arc's paragraph,
/// the Enable Max card, one card row per feature with its picture and switch, the note about what is sent. Max runs
/// the local `claude` or `codex` command-line tool; which one, and Brk's own three AI features (Ask on Page, Browse
/// for Me, Translate Pages), are in Advanced's More Settings…, so this pane keeps Arc's six rows. The pane scrolls.
struct MaxPane: View {
    let context: PaneContext
    @State private var explaining = false
    private var max: MaxSnapshot { context.settings.max }
    /// Max is on when a tool may run and at least one feature uses it; Brk's default (the automatic tool, no
    /// feature switched on) shows "Turn On Max", as Arc's default does.
    private var on: Bool { Self.isOn(max.settings) }

    static func isOn(_ settings: MaxSettings) -> Bool {
        settings.provider != .off && MaxFeature.allCases.contains { $0.isOn(settings) }
    }

    private func send(_ setting: MaxSetting) { context.dispatch(.settings(.max(setting))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MaxBanner()
            VStack(alignment: .leading, spacing: 0) {
                Text(SettingsCopy.maxIntro).font(SettingsStyle.font).foregroundStyle(SettingsStyle.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, M.introInset.value)
                    .padding(.top, M.introTop.value)
                enableCard.padding(.top, CardMetrics.introToCard.value)
                SettingsCard { rows(MaxFeature.allCases) }.padding(.top, M.cardGap.value)
                footer.padding(.top, M.footerTop.value)
            }
            .frame(width: Metrics.settings.contentWidth.value, alignment: .leading)
            .padding(.horizontal, Metrics.settings.horizontalPadding.value)
            .padding(.bottom, M.footerBottom.value)
        }
    }

    private var enableCard: some View {
        SettingsCard {
            CardRow(height: M.enableRowHeight.value) {
                HStack(spacing: CardMetrics.controlGap.value) {
                    MaxFlower(size: M.enableGlyph.value, hole: ArtColor.rgb(0x3C3FF6), outline: 1)
                        .frame(width: M.enableIcon.value, height: M.enableIcon.value)
                        .background(RoundedRectangle(cornerRadius: M.enableIconRadius.value, style: .continuous).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: M.enableIconRadius.value, style: .continuous).strokeBorder(SettingsStyle.cardBorder))
                    CardLabel(MaxCopy.enable)
                }
            } trailing: {
                EnableMaxButton(title: on ? MaxCopy.turnOff : MaxCopy.turnOn, prominent: !on) { send(.enable(!on)) }
            }
            CardDivider()
            SwitchRow(title: MaxCopy.autoEnable, field: "autoEnableFutureFeatures", isOn: max.settings.autoEnableFutureFeatures == true,
                      height: M.autoRowHeight.value) { send(.autoEnableFutureFeatures($0)) }
                .padding(.bottom, M.autoRowBottom.value)
        }
    }

    @ViewBuilder private func rows(_ features: [MaxFeature]) -> some View {
        ForEach(Array(features.enumerated()), id: \.element) { index, feature in
            if index > 0 { CardDivider() }
            HStack(alignment: .top, spacing: M.thumbGap.value) {
                MaxThumbnail(feature: feature).padding(.top, M.thumbTop.value)
                VStack(alignment: .leading, spacing: M.titleGap.value) {
                    Text(feature.title).font(SettingsStyle.font).foregroundStyle(SettingsStyle.text)
                    Text(feature.description).font(.system(size: M.descriptionSize.value)).foregroundStyle(SettingsStyle.secondaryText)
                        .lineSpacing(M.descriptionLeading.value)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, M.titleTop.value)
                Spacer(minLength: CardMetrics.controlGap.value)
                SettingsSwitch(field: feature.field, isOn: feature.isOn(max.settings)) { send(feature.setting($0)) }
                    .frame(height: M.featureRowHeight.value)
            }
            .padding(.leading, M.thumbInset.value)
            .padding(.trailing, CardMetrics.rowPadding.value)
            .frame(minHeight: M.featureRowHeight.value, alignment: .top)
        }
    }

    private var footer: some View {
        VStack(spacing: M.footerGap.value) {
            Text(MaxCopy.footer).font(SettingsStyle.font).foregroundStyle(SettingsStyle.secondaryText)
            LinkedText(parts: [.link(MaxCopy.learnMore, id: "privacy")], color: SettingsStyle.link, underline: true) { _ in explaining = true }
                .popover(isPresented: $explaining) {
                    VStack(alignment: .leading, spacing: CardMetrics.controlGap.value) {
                        Text(SettingsCopy.maxPrivacy).font(SettingsStyle.font).fixedSize(horizontal: false, vertical: true)
                        Text(SettingsCopy.detected(max.detected, active: max.active)).font(SettingsStyle.font).foregroundStyle(SettingsStyle.secondaryText)
                        Text(MaxCopy.whereToChoose).font(SettingsStyle.font).foregroundStyle(SettingsStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: M.popoverWidth.value).padding()
                }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// A Max feature as the pane lists it: Arc's six in Arc's order.
enum MaxFeature: String, Hashable, CaseIterable {
    case tidyTabs, instantLinks, linkPreviews, tidyTitles, tidyDownloads, askInCommandBar

    /// The `settings-field-<name>` of the feature's switch (the model's names, which the scenarios click).
    var field: String {
        switch self {
        case .tidyTabs: "tidyTabs"
        case .tidyTitles: "renamePinnedTabs"
        default: aiFeature!.rawValue
        }
    }

    var aiFeature: AIFeature? {
        switch self {
        case .tidyTabs, .tidyTitles: nil
        case .instantLinks: .instantLinks
        case .linkPreviews: .linkPreviews
        case .tidyDownloads: .downloadRename
        case .askInCommandBar: .commandBar
        }
    }

    func isOn(_ settings: MaxSettings) -> Bool {
        switch self {
        case .tidyTabs: settings.tidyTabs
        case .tidyTitles: settings.renamePinnedTabs
        default: settings.enabled(aiFeature!)
        }
    }

    func setting(_ on: Bool) -> MaxSetting {
        switch self {
        case .tidyTabs: .tidyTabs(on)
        case .tidyTitles: .renamePinnedTabs(on)
        default: .feature(aiFeature!, on)
        }
    }

    var title: String { MaxCopy.title(self) }
    var description: String { MaxCopy.description(self) }
}

/// The Max pane's words: Arc's where Brk does the same thing (observed in P38-b and P38-c), Brk's where the local
/// tool or Brk's own entry points differ.
enum MaxCopy {
    static let enable = "Enable Max"
    static let turnOn = "Turn On Max"
    static let turnOff = "Turn Off Max"
    static var autoEnable: String { "Automatically enable future \(Product.name) Max features" }
    static let provider = "Local AI tool"
    /// Arc: "Max features require that we send data to our AI partners."; Brk sends it to the local tool.
    static let footer = "Max features require that we send data to your local AI tool."
    static let learnMore = "Learn more about what we send"
    static var whereToChoose: String { "Choose the tool, and turn \(Product.name)'s Ask on Page, Browse for Me and Translate Pages on or off, in Advanced → More Settings…." }

    static func title(_ feature: MaxFeature) -> String {
        switch feature {
        case .tidyTabs: "Tidy Tabs"
        case .instantLinks: "Instant Links"
        case .linkPreviews: "5-Second Previews"
        case .tidyTitles: "Tidy Tab Titles"
        case .tidyDownloads: "Tidy Downloads"
        case .askInCommandBar: "Ask Max in the Command Bar"
        }
    }

    static func description(_ feature: MaxFeature) -> String {
        switch feature {
        case .tidyTabs: "Choose Organize Today Tabs in the Tabs menu to let your Sidebar sort your Today Tabs into folders by topic."
        case .instantLinks: "Choose Instant Links… in the Tabs menu or the Command Bar and describe a page to open the top result."
        case .linkPreviews: "A short summary appears when you hover over a link deliberately. Never in private windows."
        case .tidyTitles: "Have your tabs automatically renamed with tidier, shorter titles when you Pin them."
        case .tidyDownloads: "Keep your many files more organized with smartly renamed downloads — and make them a little easier to find later."
        case .askInCommandBar: "Type “Ask Max” in the Command Bar, or press ⌥⌘G, to ask your local AI tool any question instantly."
        }
    }
}

/// Arc's Enable Max button (P38-b "Turn On Max", P38-max-on "Turn Off Max"): a rounded rectangle with a grey hairline
/// edge, filled blue with white text while Max is off, white with dark text while it is on. An NSButton, so it is
/// clicked and identified like the pane's other controls.
struct EnableMaxButton: NSViewRepresentable {
    let title: String
    let prominent: Bool
    let action: @MainActor () -> Void

    func makeCoordinator() -> SettingsButton.Coordinator { SettingsButton.Coordinator() }

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(SettingsButton.Coordinator.clicked(_:)))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = M.enableButtonRadius.value
        button.layer?.cornerCurve = .continuous
        button.layer?.borderWidth = 0.5
        return button
    }

    func updateNSView(_ button: NSButton, context: NSViewRepresentableContext<Self>) {
        context.coordinator.action = action
        button.identify(.settingsField("enableMax"))
        button.isEnabled = context.environment.isEnabled
        button.layer?.backgroundColor = (prominent ? ProminentButton.arcBlue : NSColor.white).cgColor
        button.layer?.borderColor = NSColor(white: 0xB4 / 255.0, alpha: 1).cgColor
        let font = NSFont.systemFont(ofSize: M.enableButtonFont.value, weight: .semibold)
        let color: NSColor = prominent ? .white : NSColor(white: 0x2B / 255.0, alpha: 1)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView button: NSButton, context: NSViewRepresentableContext<Self>) -> CGSize? {
        M.enableButtonSize.value
    }
}

/// A push button; prominent is Arc's filled blue one ("Turn On Max", "Learn the Essential Shortcuts").
struct ProminentButton: NSViewRepresentable {
    let title: String
    let field: String
    var prominent = true
    var symbol: String? = nil
    static let arcBlue = NSColor(srgbRed: 0x31 / 255.0, green: 0x37 / 255.0, blue: 0xF8 / 255.0, alpha: 1)
    var accent: NSColor = ProminentButton.arcBlue
    var minimumWidth: CGFloat = 0
    /// The prominent title's weight (Arc's "Learn the Essential Shortcuts" is regular).
    var weight: NSFont.Weight = .semibold
    let action: @MainActor () -> Void

    func makeCoordinator() -> SettingsButton.Coordinator { SettingsButton.Coordinator() }

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(SettingsButton.Coordinator.clicked(_:)))
        button.controlSize = .large
        return button
    }

    func updateNSView(_ button: NSButton, context: NSViewRepresentableContext<Self>) {
        context.coordinator.action = action
        button.identify(.settingsField(field))
        button.isEnabled = context.environment.isEnabled
        button.bezelColor = prominent ? accent : nil
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: prominent ? weight : .regular)
        let color: NSColor = prominent ? .white : .labelColor
        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: color])
        if let symbol {
            // A filled symbol keeps its glyph in the button's colour (Arc's ⌘ in a white disc).
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: NSFont.systemFontSize, weight: .regular)
                    .applying(.init(paletteColors: prominent ? [accent, color] : [color])))
            button.imagePosition = .imageLeading
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView button: NSButton, context: NSViewRepresentableContext<Self>) -> CGSize? {
        CGSize(width: max(button.intrinsicContentSize.width, minimumWidth), height: button.intrinsicContentSize.height)
    }
}

private var M: MaxPaneMetricsTable { MaxPaneMetrics }

let MaxPaneMetrics = MaxPaneMetricsTable()

struct MaxPaneMetricsTable: MetricGroup {
    private static let capture = "verify/visual-pairs/run-20261103/P38/P38-b-arc.png"
    let introInset = Metric(5.0, .anatomy("\(capture): the paragraph starts at x 138 px, the cards at 128 px"))
    let introTop = Metric(26.5, .anatomy("\(capture): the wave's lowest at y 427 px, the paragraph's first line centred at 497 px"))
    let cardGap = Metric(24.0, .anatomy("\(capture): the Enable card ends at y 760 px, the features card starts at 808 px"))
    let enableRowHeight = Metric(45.0, .anatomy("\(capture): the Enable Max row spans y 592 to 682 px"))
    let autoRowHeight = Metric(32.0, .anatomy("\(capture): the Automatically enable row spans y 684 to 758 px, its switch centred at 716 px"))
    let autoRowBottom = Metric(5.0, .anatomy("\(capture): the row's switch is centred 32 px below its top and 42 px above the card's edge"))
    let enableIcon = Metric(24.0, .anatomy("\(capture): the white icon square spans x 148 to 196 px"))
    let enableGlyph = Metric(17.0, .anatomy("\(capture): the flower inside spans x 156 to 188 px"))
    let enableIconRadius = Metric(6.0, .guess("the icon square's corner"))
    let enableButtonSize = Metric(CGSize(width: 117.5, height: 28), .anatomy("\(capture): Turn On Max spans x 986 to 1221 px, y 611 to 667 px with its grey edge"))
    let enableButtonRadius = Metric(6.0, .anatomy("\(capture): 4 px in from the button's left edge its corner starts 3 px down"))
    let enableButtonFont = Metric(12.0, .anatomy("\(capture): the Turn On Max lettering spans x 1035 to 1174 px, a 12 pt semibold line (13 pt is 159 px wide)"))
    let featureRowHeight = Metric(80.0, .anatomy("\(capture): feature rows 808 to 968 to 1130 px"))
    let thumbInset = Metric(11.5, .anatomy("\(capture): a thumbnail's rim starts at x 151 px"))
    let thumbTop = Metric(10.5, .anatomy("\(capture): the thumbnail starts at y 832 px in a row that starts at 808 px"))
    let thumbGap = Metric(17.0, .anatomy("\(capture): the thumbnail ends at x 330 px, the title starts at 368 px"))
    let titleTop = Metric(10.0, .anatomy("\(capture): the title is centred at y 845 px in a row that starts at 808 px"))
    let titleGap = Metric(4.5, .anatomy("\(capture): title centred at y 845 px, the description's first line at 884 px"))
    let descriptionSize = Metric(11.0, .anatomy("verify/visual-pairs/run-20261103/P38/P38-c-arc.png: 'Have your tabs automatically renamed with tidier, shorter titles when you' spans x 369 to 1131 px, an 11 pt line (13 pt is 880 px)"))
    let descriptionLeading = Metric(2.0, .anatomy("\(capture): description lines 32 px apart"))
    let footerTop = Metric(15.5, .anatomy("verify/visual-pairs/run-20261103/P38/P38-c-arc.png: the last card ends at y 1174 px, the note is centred at 1224 px"))
    let footerGap = Metric(-1.0, .anatomy("verify/visual-pairs/run-20261103/P38/P38-c-arc.png: note and link centred 30 px apart"))
    let footerBottom = Metric(15.5, .anatomy("verify/visual-pairs/run-20261103/P38/P38-c-arc.png: the link is centred at y 1254 px of 1300"))
    let popoverWidth = Metric(320.0, .guess("the privacy note's popover"))
}
