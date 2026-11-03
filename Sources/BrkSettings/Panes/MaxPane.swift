import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// The Max pane as Arc 1.170 lays it out (P38-b, P38-c): the MAX banner, Arc's paragraph, the Enable Max card, one
/// card row per feature with its picture and switch, the note about what is sent. Brk's difference is deliberate:
/// Max runs the local `claude` or `codex` command-line tool, so the Enable card also picks the tool and says what was
/// found on PATH, and the note names the tool instead of Arc's AI partners. The pane scrolls.
struct MaxPane: View {
    let context: PaneContext
    @State private var explaining = false
    private var max: MaxSnapshot { context.settings.max }
    private var on: Bool { max.settings.provider != .off }

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
                SettingsCard { rows(MaxFeature.arcs) }.padding(.top, M.cardGap.value)
                SettingsCard { rows(MaxFeature.brks) }.padding(.top, M.cardGap.value)
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
                    MaxFlower(size: M.enableGlyph.value)
                        .frame(width: M.enableIcon.value, height: M.enableIcon.value)
                        .background(RoundedRectangle(cornerRadius: M.enableIconRadius.value, style: .continuous).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: M.enableIconRadius.value, style: .continuous).strokeBorder(SettingsStyle.cardBorder))
                    CardLabel(MaxCopy.enable)
                }
            } trailing: {
                ProminentButton(title: on ? MaxCopy.turnOff : MaxCopy.turnOn, field: "enableMax", prominent: !on, minimumWidth: M.turnOnWidth.value) {
                    send(.enable(!on))
                }
            }
            CardDivider()
            SwitchRow(title: MaxCopy.autoEnable, field: "autoEnableFutureFeatures", isOn: max.settings.autoEnableFutureFeatures == true,
                      height: M.autoRowHeight.value) { send(.autoEnableFutureFeatures($0)) }
            CardDivider()
            CardRow(height: M.providerRowHeight.value) {
                VStack(alignment: .leading, spacing: CardMetrics.subtitleGap.value) {
                    CardLabel(MaxCopy.provider)
                    SettingsLabel(text: SettingsCopy.detected(max.detected, active: max.active), field: "aiStatus", secondary: true)
                }
            } trailing: {
                SettingsPopUp(field: "aiProvider", entries: AIProviderChoice.allCases.map { .option(SettingsCopy.provider($0), $0) },
                              selected: max.settings.provider) { send(.provider($0)) }
                    .fixedSize()
            }
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
                    Text(SettingsCopy.maxPrivacy).font(SettingsStyle.font).fixedSize(horizontal: false, vertical: true)
                        .frame(width: M.popoverWidth.value).padding()
                }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// A Max feature as the pane lists it: Arc's six in Arc's order, then Brk's three (Ask on Page, Browse for Me,
/// Translate Pages).
enum MaxFeature: String, Hashable, CaseIterable {
    case tidyTabs, instantLinks, linkPreviews, tidyTitles, tidyDownloads, askInCommandBar, askOnPage, browse, translation

    static let arcs: [MaxFeature] = [.tidyTabs, .instantLinks, .linkPreviews, .tidyTitles, .tidyDownloads, .askInCommandBar]
    static let brks: [MaxFeature] = [.askOnPage, .browse, .translation]

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
        case .askOnPage: .askPage
        case .browse: .browse
        case .translation: .translation
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
    static let footer = "Max features send your question and the page text it needs to the tool you choose."
    static let learnMore = "Learn more about what we send"

    static func title(_ feature: MaxFeature) -> String {
        switch feature {
        case .tidyTabs: "Tidy Tabs"
        case .instantLinks: "Instant Links"
        case .linkPreviews: "5-Second Previews"
        case .tidyTitles: "Tidy Tab Titles"
        case .tidyDownloads: "Tidy Downloads"
        case .askInCommandBar: "Ask Max in the Command Bar"
        case .askOnPage: "Ask on Page"
        case .browse: "Browse for Me"
        case .translation: "Translate Pages"
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
        case .askOnPage: "Ask about the page you are reading. The tool receives the page’s text."
        case .browse: "Let the tool read the pages you choose and answer from them."
        case .translation: "Translate the page you are reading. Never-translate choices are kept per site and language."
        }
    }
}

/// A push button; prominent is Arc's filled blue one ("Turn On Max", "Learn the Essential Shortcuts").
struct ProminentButton: NSViewRepresentable {
    let title: String
    let field: String
    var prominent = true
    var symbol: String? = nil
    var accent: NSColor = NSColor(srgbRed: 0x31 / 255.0, green: 0x37 / 255.0, blue: 0xF8 / 255.0, alpha: 1)
    var minimumWidth: CGFloat = 0
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
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: prominent ? .semibold : .regular)
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
    let introTop = Metric(29.0, .anatomy("\(capture): the wave's middle at y 422 px, the paragraph's first line centred at 497 px"))
    let cardGap = Metric(24.0, .anatomy("\(capture): the Enable card ends at y 760 px, the features card starts at 808 px"))
    let enableRowHeight = Metric(45.0, .anatomy("\(capture): the Enable Max row spans y 592 to 682 px"))
    let autoRowHeight = Metric(38.0, .anatomy("\(capture): the Automatically enable row spans y 682 to 758 px"))
    let providerRowHeight = Metric(48.0, .guess("Brk's tool row: a label over the PATH note"))
    let enableIcon = Metric(24.0, .anatomy("\(capture): the white icon square spans x 148 to 196 px"))
    let enableGlyph = Metric(17.0, .anatomy("\(capture): the flower inside spans x 156 to 188 px"))
    let enableIconRadius = Metric(6.0, .guess("the icon square's corner"))
    let turnOnWidth = Metric(117.0, .anatomy("\(capture): Turn On Max spans x 986 to 1220 px"))
    let featureRowHeight = Metric(80.0, .anatomy("\(capture): feature rows 808 to 968 to 1130 px"))
    let thumbInset = Metric(11.5, .anatomy("\(capture): a thumbnail's rim starts at x 151 px"))
    let thumbTop = Metric(10.5, .anatomy("\(capture): the thumbnail starts at y 832 px in a row that starts at 808 px"))
    let thumbGap = Metric(17.0, .anatomy("\(capture): the thumbnail ends at x 330 px, the title starts at 368 px"))
    let titleTop = Metric(10.0, .anatomy("\(capture): the title is centred at y 845 px in a row that starts at 808 px"))
    let titleGap = Metric(3.0, .anatomy("\(capture): title centred at y 845 px, the description's first line at 884 px"))
    let descriptionSize = Metric(12.0, .anatomy("\(capture): the description's P stem is 16 px, the title's T 19 px"))
    let descriptionLeading = Metric(2.0, .anatomy("\(capture): description lines 32 px apart"))
    let footerTop = Metric(22.0, .anatomy("verify/visual-pairs/run-20261103/P38/P38-c-arc.png: the last card ends at y 1174 px, the note is centred at 1224 px"))
    let footerGap = Metric(2.0, .anatomy("verify/visual-pairs/run-20261103/P38/P38-c-arc.png: note and link centred 30 px apart"))
    let footerBottom = Metric(24.0, .anatomy("verify/visual-pairs/run-20261103/P38/P38-c-arc.png: the link is centred at y 1254 px of 1300"))
    let popoverWidth = Metric(320.0, .guess("the privacy note's popover"))
}
