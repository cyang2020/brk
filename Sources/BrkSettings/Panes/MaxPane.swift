import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// The Max pane as Arc 1.170 lays it out (P38-b, P38-c, P38-max-on, P38-max-list): the MAX banner, Arc's paragraph,
/// the Enable Max card, one card row per feature with its picture and switch, the note about what is sent. Max runs
/// the user's local coding agent, so under the Enable Max card there is one card Arc does not have: which agent, its model
/// and effort. It moves Arc's rows down, on purpose: choosing the agent is the first thing Max asks of the user here. Brk's own
/// three AI features (Ask on Page, Browse for Me, Translate Pages) are in Advanced's More Settings…. The pane scrolls.
struct MaxPane: View {
    let context: PaneContext
    @State private var explaining = false
    @State private var note: MaxCopy.Note?
    private var max: MaxSnapshot { context.settings.max }
    /// Max is on when a tool may run and at least one feature uses it, Brk's three in More Settings… included (Turn On
    /// Max with only those on would change nothing); Brk's default (the automatic tool, no feature switched on) shows
    /// "Turn On Max", as Arc's default does.
    private var on: Bool { Self.isOn(max.settings) }

    static func isOn(_ settings: MaxSettings) -> Bool {
        settings.provider != .off && (MaxFeature.allCases.contains { $0.isOn(settings) } || AIFeature.allCases.contains(where: settings.enabled))
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
                agentCard.padding(.top, M.cardGap.value)
                BasicFeaturesCard(context: context).padding(.top, M.cardGap.value)
                SettingsCard { rows(MaxFeature.allCases) }.padding(.top, M.cardGap.value)
                AccountsCard(context: context).padding(.top, M.cardGap.value)
                LocalModelsCard(models: max.localModels ?? LocalModelsSnapshot(), send: send).padding(.top, M.cardGap.value)
                UsageCard(context: context).padding(.top, M.cardGap.value)
                footer.padding(.top, M.footerTop.value)
            }
            .frame(width: Metrics.settings.contentWidth.value, alignment: .leading)
            .padding(.horizontal, Metrics.settings.horizontalPadding.value)
            .padding(.bottom, M.footerBottom.value)
        }
        .escapeCloses(note != nil) { note = nil }
        // The card says what each agent reports about itself: signed in or not, its models and efforts.
        .onAppear { send(.refreshAgents) }
    }

    private var enableCard: some View {
        SettingsCard {
            CardRow(height: M.enableRowHeight.value) {
                HStack(spacing: CardMetrics.controlGap.value) {
                    MaxFlower(size: M.enableGlyph.value, hole: ArtColor.rgb(0x3C3FF6), outline: 1)
                        .frame(width: M.enableIcon.value, height: M.enableIcon.value)
                        .background(RoundedRectangle(cornerRadius: M.enableIconRadius.value, style: .continuous).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: M.enableIconRadius.value, style: .continuous).strokeBorder(SettingsStyle.cardBorder))
                    CardLabel(MaxCopy.enable).padding(.top, M.enableLabelDrop.value)
                }
            } trailing: {
                EnableMaxButton(title: on ? MaxCopy.turnOff : MaxCopy.turnOn, prominent: !on) { send(.enable(!on)) }
                    .padding(.top, M.enableButtonDrop.value)
            }
            CardDivider()
            CardRow(height: M.autoRowHeight.value) {
                CardLabel(MaxCopy.autoEnable).padding(.leading, M.autoLabelInset.value)
            } trailing: {
                SettingsSwitch(field: "autoEnableFutureFeatures", isOn: max.settings.autoEnableFutureFeatures == true) { send(.autoEnableFutureFeatures($0)) }
            }
            .padding(.bottom, M.autoRowBottom.value)
        }
    }

    @ViewBuilder private func rows(_ features: [MaxFeature]) -> some View {
        ForEach(Array(features.enumerated()), id: \.element) { index, feature in
            if index > 0 { CardDivider() }
            // Only the picture keeps the gap from the text: the text runs to within 8.5 points of the switch (P38-c:
            // "…shorter titles when you" ends at x 1131 px, the switch starts at 1148 px).
            HStack(alignment: .top, spacing: 0) {
                MaxThumbnail(feature: feature, provider: max.askProvider).padding(.top, M.thumbTop.value).padding(.trailing, M.thumbGap.value)
                VStack(alignment: .leading, spacing: M.titleGap.value) {
                    Text(MaxCopy.title(feature, provider: max.askProvider)).font(SettingsStyle.font).foregroundStyle(SettingsStyle.text)
                    description(feature)
                }
                .padding(.top, M.titleTop.value)
                Spacer(minLength: M.textToSwitch.value)
                SettingsSwitch(field: feature.field, isOn: feature.isOn(max.settings)) { send(feature.setting($0)) }
                    .frame(height: M.featureRowHeight.value)
            }
            .padding(.leading, M.thumbInset.value)
            .padding(.trailing, CardMetrics.rowPadding.value)
            .frame(minHeight: M.featureRowHeight.value, alignment: .top)
        }
    }

    /// Arc's descriptions: the Tidy Tabs broom inline, the blue parts as links (Arc's open help articles; Brk's say
    /// in a note what the words promise here).
    private func description(_ feature: MaxFeature) -> some View {
        let parts = MaxCopy.description(feature, provider: max.askProvider)
        let body = parts.reduce(Text("")) { result, part in
            switch part {
            case .text(let words): result + Text(words)
            // P38-max-list: its ink is 23 px tall and drops under the line, which pushes the next line 3 points down.
            case .broom: result + Text(Image(nsImage: ArcGlyphs.broom(size: M.broomSize.value))).baselineOffset(M.broomDrop.value).foregroundColor(SettingsStyle.secondaryText)
            case .link(let words, _): result + Text(words).foregroundColor(SettingsStyle.descriptionLink)
            }
        }
        return body.font(.system(size: M.descriptionSize.value)).foregroundStyle(SettingsStyle.secondaryText)
            .lineSpacing(M.descriptionLeading.value)
            .fixedSize(horizontal: false, vertical: true)
            .onTapGesture { if let link = parts.lazy.compactMap({ if case .link(_, let note) = $0 { note } else { nil } }).first { note = link } }
            .popover(isPresented: Binding(get: { note != nil && parts.contains { if case .link(_, let n) = $0 { n == note } else { false } } },
                                          set: { if !$0 { note = nil } })) {
                Text(note?.text ?? "").font(SettingsStyle.font).fixedSize(horizontal: false, vertical: true)
                    .frame(width: M.popoverWidth.value).padding()
            }
    }

    /// Which agent runs Max, read from the agents themselves: signed in or not, the models and efforts they offer.
    private var agentCard: some View {
        let kind = max.active ?? max.settings.provider.kind
        let status = kind.flatMap { wanted in max.agents.first { $0.kind == wanted } }
        let chosen = kind.flatMap { max.settings.agentOptions?[$0] }
        let model = status?.models.first { $0.id == chosen?.model } ?? status?.models.first { $0.isDefault }
        let efforts = model?.efforts ?? []
        return SettingsCard {
            CardRow {
                CardLabel(MaxCopy.provider)
            } trailing: {
                SettingsPopUp(field: "agentChoice", entries: AIProviderChoice.allCases.map { .option(agentTitle($0), $0) },
                              selected: max.settings.provider, width: .selected(minimum: M.agentPopup.value)) { send(.provider($0)) }
            }
            if let kind, let status, !status.models.isEmpty {
                CardDivider()
                CardRow {
                    CardLabel(MaxCopy.model)
                } trailing: {
                    SettingsPopUp<String>(field: "agentModel", entries: [.option(MaxCopy.agentDefault, "")] + status.models.map { .option($0.name, $0.id) },
                                          selected: chosen?.model ?? "", width: .selected(minimum: M.agentPopup.value)) { send(.agentModel(kind, $0.isEmpty ? nil : $0)) }
                }
                if !efforts.isEmpty {
                    CardDivider()
                    CardRow {
                        CardLabel(MaxCopy.effort)
                    } trailing: {
                        SettingsPopUp<String>(field: "agentEffort", entries: [.option(MaxCopy.agentDefault, "")] + efforts.map { .option($0, $0) },
                                              selected: chosen?.effort ?? "", width: .selected(minimum: M.agentPopup.value)) { send(.agentEffort(kind, $0.isEmpty ? nil : $0)) }
                    }
                }
            }
            if let kind, AIAgentOptions.basicDefault(kind) != nil {
                basicRows(kind, status: status)
            }
            if let status {
                CardDivider()
                SettingsLabel(text: SettingsCopy.agentStatus(status), field: "agentStatus-\(status.kind.rawValue)", secondary: true)
                    .padding(CardMetrics.rowPadding.value)
            }
            CardDivider()
            SettingsLabel(text: MaxBasicCopy.basicRoute(max.basicRoute), field: "basicRoute", secondary: true)
                .padding(CardMetrics.rowPadding.value)
        }
    }

    /// The small model for the basic features, apart from the conversation's: Haiku 5.5 or gpt-6-luna unless chosen.
    @ViewBuilder private func basicRows(_ kind: AIProviderKind, status: AIAgentStatus?) -> some View {
        let chosen = max.settings.basic(kind)
        let listed = status?.models ?? []
        // The default small model is offered even before the agent lists its models (or when it does not list it).
        let models = (chosen?.model).map { model in listed.contains { $0.id == model } ? listed : [AIAgentModel(id: model, name: MaxBasicCopy.modelName(model))] + listed } ?? listed
        let efforts = models.first { $0.id == chosen?.model }?.efforts ?? []
        CardDivider()
        CardRow {
            CardLabel(MaxBasicCopy.basicModel)
        } trailing: {
            SettingsPopUp<String>(field: "basicModel", entries: models.map { .option($0.name, $0.id) },
                                  selected: chosen?.model ?? "", width: .selected(minimum: M.agentPopup.value)) { send(.basicModel(kind, $0)) }
        }
        if !efforts.isEmpty {
            CardDivider()
            CardRow {
                CardLabel(MaxBasicCopy.basicEffort)
            } trailing: {
                SettingsPopUp<String>(field: "basicEffort", entries: [.option(MaxCopy.agentDefault, "")] + efforts.map { .option($0, $0) },
                                      selected: chosen?.effort ?? "", width: .selected(minimum: M.agentPopup.value)) { send(.basicEffort(kind, $0.isEmpty ? nil : $0)) }
            }
        }
    }

    /// An agent's name, and why it would not answer if it would not.
    private func agentTitle(_ choice: AIProviderChoice) -> String {
        let name = choice.kind?.displayName ?? SettingsCopy.provider(choice)
        guard let kind = choice.kind, let status = max.agents.first(where: { $0.kind == kind }) else { return name }
        switch status.state {
        case .notSignedIn: return name + MaxCopy.notSignedIn
        case .missing: return name + MaxCopy.notInstalled
        default: return name
        }
    }

    private var footer: some View {
        VStack(spacing: M.footerGap.value) {
            LinkedText(parts: [.text(MaxCopy.footer)], font: .system(size: M.footerSize.value), color: SettingsStyle.secondaryText) { _ in }
            LinkedText(parts: [.link(MaxCopy.learnMore, id: "privacy")], font: .system(size: M.footerSize.value), color: SettingsStyle.link, underline: true) { _ in explaining = true }
                .popover(isPresented: $explaining) {
                    VStack(alignment: .leading, spacing: CardMetrics.controlGap.value) {
                        Text(SettingsCopy.maxPrivacy).font(SettingsStyle.font).fixedSize(horizontal: false, vertical: true)
                        Text(SettingsCopy.detected(max.detected, active: max.active)).font(SettingsStyle.font).foregroundStyle(SettingsStyle.secondaryText)
                        Text(MaxCopy.whereToChoose).font(SettingsStyle.font).foregroundStyle(SettingsStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: M.popoverWidth.value).padding()
                }
                .escapeCloses(explaining) { explaining = false }
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
        case .tidyTabs: settings.tidyOn
        case .tidyTitles: settings.titlesOn
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

    var title: String { MaxCopy.title(self, provider: nil) }
}

/// The Max pane's words: Arc's where Brk does the same thing (observed in P38-b and P38-c), Brk's where the local
/// tool or Brk's own entry points differ.
enum MaxCopy {
    static let enable = "Enable Max"
    static let turnOn = "Turn On Max"
    static let turnOff = "Turn Off Max"
    static var autoEnable: String { "Automatically enable future \(Product.name) Max features" }
    static let provider = "Local AI tool"
    /// Arc: "Max features require that we send data to our AI partners."; Brk sends it to the service the user chose.
    static let footer = "Max features require that we send data to the AI service you chose."
    static let notSignedIn = " (not signed in)"
    static let notInstalled = " (not installed)"
    static let model = "Model"
    static let effort = "Effort"
    static let agentDefault = "Default"
    static let learnMore = "Learn more about what we send"
    static var whereToChoose: String { "Turn \(Product.name)'s Ask on Page, Browse for Me and Translate Pages on or off in Advanced → More Settings…." }

    /// "ChatGPT in the Command Bar" names the local tool (`AppState.askProviderName`: Claude, Codex, Gemini…).
    static func title(_ feature: MaxFeature, provider: String?) -> String {
        switch feature {
        case .tidyTabs: "Tidy Tabs"
        case .instantLinks: "Instant Links"
        case .linkPreviews: "5-Second Previews"
        case .tidyTitles: "Tidy Tab Titles"
        case .tidyDownloads: "Tidy Downloads"
        case .askInCommandBar: "\(provider ?? "Max") in the Command Bar"
        }
    }

    enum Part: Equatable {
        case text(String), broom, link(String, Note)
    }
    /// What a description's blue words lead to in Brk: a short note (Arc's open help-center articles).
    enum Note: String, Identifiable {
        case multipleQueries, previewSites
        var id: String { rawValue }
        var text: String {
            switch self {
            case .multipleQueries: "Ask for several things at once (“weather in Paris and Tokyo”): each top result opens in its own tab."
            case .previewSites: "Without Shift, previews open on Hacker News stories, Google’s news headings and links in posts on X."
            }
        }
    }

    /// Arc's words for the six features Arc has (P38-max-list), the local tool's name for ChatGPT's; Brk's for its own
    /// three.
    static func description(_ feature: MaxFeature, provider: String?) -> [Part] {
        let tool = provider ?? "Max"
        switch feature {
        case .tidyTabs: return [.text("Press the "), .broom, .text(" icon to let your Sidebar organize itself whenever you have more than six Today Tabs.")]
        case .instantLinks: return [.text("Press Shift + Enter for any web search to instantly open the top result. "), .link("You can also search multiple queries!", .multipleQueries)]
        case .linkPreviews: return [.text("Instant summaries appear when you hover over links on "), .link("certain websites.", .previewSites), .text(" Or hold Shift while hovering to preview any link.")]
        case .tidyTitles: return [.text("Have your tabs automatically renamed with tidier, shorter titles when you Pin them.")]
        case .tidyDownloads: return [.text("Keep your many files more organized with smartly renamed downloads — and make them a little easier to find later.")]
        case .askInCommandBar: return [.text("Add \(tool) to your Search suggestions, or start typing “\(tool)”, hit Tab, to ask any question instantly.")]
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
    static let arcBlueColor = Color(nsColor: arcBlue)
    var accent: NSColor = ProminentButton.arcBlue
    var minimumWidth: CGFloat = 0
    /// The prominent title's weight (Arc's "Learn the Essential Shortcuts" is regular).
    var weight: NSFont.Weight = .semibold
    /// A fixed width instead of the title's.
    var width: CGFloat? = nil
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
        let words = NSMutableAttributedString(string: title, attributes: [.font: font, .foregroundColor: color])
        // P38-e: the ⌘ and the words sit left of the button's middle; room after the last letter moves them over.
        if symbol != nil, !title.isEmpty { words.addAttribute(.kern, value: 3.2, range: NSRange(location: (title as NSString).length - 1, length: 1)) }
        button.attributedTitle = words
        if let symbol {
            // A filled symbol keeps its glyph in the button's colour (Arc's ⌘ in a white disc).
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: NSFont.systemFontSize, weight: .regular)
                    .applying(.init(paletteColors: prominent ? [accent, color] : [color])))
            button.imagePosition = .imageLeading
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView button: NSButton, context: NSViewRepresentableContext<Self>) -> CGSize? {
        CGSize(width: width ?? max(button.intrinsicContentSize.width, minimumWidth), height: button.intrinsicContentSize.height)
    }
}

private var M: MaxPaneMetricsTable { MaxPaneMetrics }

let MaxPaneMetrics = MaxPaneMetricsTable()

struct MaxPaneMetricsTable: MetricGroup {
    private static let capture = "~/brk-arc-reference/P38/P38-b-arc.png"
    let introInset = Metric(5.0, .anatomy("\(capture): the paragraph starts at x 138 px, the cards at 128 px"))
    let introTop = Metric(26.5, .anatomy("\(capture): the wave's lowest at y 427 px, the paragraph's first line centred at 497 px"))
    let cardGap = Metric(24.0, .anatomy("\(capture): the Enable card ends at y 760 px, the features card starts at 808 px"))
    let enableRowHeight = Metric(45.0, .anatomy("\(capture): the Enable Max row spans y 592 to 682 px"))
    let autoRowHeight = Metric(32.0, .anatomy("\(capture): the Automatically enable row spans y 684 to 758 px, its switch centred at 716 px"))
    let autoRowBottom = Metric(6.0, .anatomy("\(capture): the row's switch is centred 32 px below its top and 42 px above the card's edge"))
    let autoLabelInset = Metric(3.0, .anatomy("\(capture): 'Automatically enable' starts at x 155 px, the other rows' text at 149 px"))
    let enableLabelDrop = Metric(2.0, .anatomy("\(capture): 'Enable Max' spans y 629 to 649 px, a point lower than the row's middle"))
    let enableIcon = Metric(24.0, .anatomy("\(capture): the white icon square spans x 148 to 196 px"))
    let enableGlyph = Metric(17.0, .anatomy("\(capture): the flower inside spans x 156 to 188 px"))
    let enableIconRadius = Metric(6.0, .guess("the icon square's corner"))
    let enableButtonSize = Metric(CGSize(width: 117.5, height: 28), .anatomy("\(capture): Turn On Max spans x 986 to 1221 px, y 611 to 667 px with its grey edge"))
    let enableButtonRadius = Metric(6.0, .anatomy("\(capture): 4 px in from the button's left edge its corner starts 3 px down"))
    let enableButtonDrop = Metric(2.0, .anatomy("\(capture): the button is centred at y 639 px in a row centred at 638 px"))
    let enableButtonFont = Metric(12.0, .anatomy("\(capture): the Turn On Max lettering spans x 1035 to 1174 px, a 12 pt semibold line (13 pt is 159 px wide)"))
    let featureRowHeight = Metric(80.0, .anatomy("\(capture): feature rows 808 to 968 to 1130 px"))
    let thumbInset = Metric(11.5, .anatomy("\(capture): a thumbnail's rim starts at x 151 px"))
    let thumbTop = Metric(10.5, .anatomy("\(capture): the thumbnail starts at y 832 px in a row that starts at 808 px"))
    let textToSwitch = Metric(8.5, .anatomy("~/brk-arc-reference/P38/P38-c-arc.png: a description line ends at x 1131 px, the switch starts at 1148 px"))
    let thumbGap = Metric(17.5, .anatomy("~/brk-arc-reference/P38/P38-max-list-arc.png: the thumbnail ends at x 329 px, the titles' ink starts at 369 px"))
    let titleTop = Metric(10.0, .anatomy("\(capture): the title is centred at y 845 px in a row that starts at 808 px"))
    let titleGap = Metric(4.0, .anatomy("\(capture): a title's top at y 996 px, the description's first line at 1035 px"))
    let broomSize = Metric(11.0, .anatomy("~/brk-arc-reference/P38/P38-max-list-arc.png: the broom's ink spans y 270 to 293 px"))
    let broomDrop = Metric(-3.0, .anatomy("~/brk-arc-reference/P38/P38-max-list-arc.png: the line after the broom is 6 px further down than in a row without it"))
    let descriptionSize = Metric(11.0, .anatomy("~/brk-arc-reference/P38/P38-c-arc.png: 'Have your tabs automatically renamed with tidier, shorter titles when you' spans x 369 to 1131 px, an 11 pt line (13 pt is 880 px)"))
    let descriptionLeading = Metric(0.0, .anatomy("~/brk-arc-reference/P38/P38-max-list-arc.png: description lines 28 px apart, an 11 pt line's own height"))
    let footerSize = Metric(12.0, .anatomy("~/brk-arc-reference/P38/P38-c-arc.png: 'Learn more about what we send' spans x 505 to 862 px, a 12 pt line (13 pt is 387 px)"))
    let footerTop = Metric(16.0, .anatomy("~/brk-arc-reference/P38/P38-c-arc.png: the last card ends at y 1174 px, the note is centred at 1224 px"))
    let footerGap = Metric(0.0, .anatomy("~/brk-arc-reference/P38/P38-c-arc.png: note and link centred 30 px apart"))
    let footerBottom = Metric(16.0, .anatomy("~/brk-arc-reference/P38/P38-c-arc.png: the link is centred at y 1254 px of 1300"))
    let popoverWidth = Metric(320.0, .guess("the privacy note's popover"))
    let agentPopup = Metric(150.0, .guess("the Local AI agent card's pop-ups"))
}
