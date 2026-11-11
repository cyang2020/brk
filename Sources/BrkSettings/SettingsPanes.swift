import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

// The General, Links and Advanced panes, laid out as Arc 1.170 shows them (P38-a, P38-f, P38-g): rows in rounded
// cards with switches. What Brk has and Arc's pane does not show stays reachable one level down: the "…Settings…"
// buttons open a sub-page in the same pane.
//
// Field names (`settings-field-<name>`) are the ones the control socket clicks; per-profile fields end in the
// profile id.

private var S: SettingsMetrics { Metrics.settings }
private var C: SettingsCardMetricsTable { CardMetrics }

// MARK: - General

struct GeneralPane: View {
    let context: PaneContext
    @State private var showingPreviews = false
    private var s: SettingsSnapshot { context.settings }

    var body: some View {
        CardPane {
            // Arc's first card also has "Automatically update my Arc"; Brk's updater is a later wave.
            SettingsCard {
                SwitchRow(title: SettingsCopy.warnBeforeQuitting, field: "warnBeforeQuitting", isOn: s.general.warnBeforeQuitting) {
                    context.dispatch(.settings(.general(.warnBeforeQuitting($0))))
                }
            }
            SettingsCard {
                ButtonRow(title: SettingsCopy.previews, button: SettingsCopy.previewsSettingsButton, field: "previewsSettings") {
                    showingPreviews = true
                }
                CardDivider()
                CardRow(height: C.twoLineRowHeight.value) {
                    CardLabel(SettingsCopy.profileSettingsHint).frame(maxWidth: C.wrappedLabelWidth.value, alignment: .leading)
                } trailing: {
                    SettingsButton(title: SettingsCopy.profileSettingsButton, field: "profileSettings") {
                        context.dispatch(.settings(.openPane(.profiles)))
                    }
                }
            }
        }
        .sheet(isPresented: $showingPreviews) {
            PreviewsSheet(context: context) { showingPreviews = false }
        }
    }
}

/// "Previews Settings…" (P13-settings-arc.png): Arc's sheet "Show Arc Previews:" with what previews on hover and a
/// blue Done. Arc lists seven sources (its folders and six sites' own previews); Brk previews folders, Pinned and
/// Favorited tabs and links in one switch, and Max's 5-Second Previews in another, so those are the boxes here.
struct PreviewsSheet: View {
    let context: PaneContext
    let done: @MainActor () -> Void
    @State private var explaining = false
    private var tabs: TabPreferenceSnapshot { context.settings.tabPreferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(SettingsCopy.showPreviews).font(.system(size: C.fontSize.value, weight: .bold))
            Text(SettingsCopy.previewsExplanation).font(SettingsStyle.font).foregroundStyle(ArtColor.rgb(0x4F5669))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, C.sheetTitleGap.value)
            LinkedText(parts: [.link(SettingsCopy.learnMore, id: "previews")], color: SettingsStyle.link) { _ in explaining = true }
                .popover(isPresented: $explaining) {
                    Text(SettingsCopy.previewsDetail).font(SettingsStyle.font).fixedSize(horizontal: false, vertical: true)
                        .frame(width: C.popoverWidth.value).padding()
                }
            VStack(alignment: .leading, spacing: C.sheetRowGap.value) {
                SettingsCheckbox(title: SettingsCopy.folderAndTabPreviews, field: "tabHoverPreviews", isOn: tabs.hoverPreviews, size: .large) {
                    context.dispatch(.tabTools(.preferences(includeFavorites: tabs.includeFavoritesInNumbers, previews: $0)))
                }
                SettingsCheckbox(title: SettingsCopy.maxLinkPreviews, field: "previews-\(AIFeature.linkPreviews.rawValue)",
                                 isOn: context.settings.max.settings.enabled(.linkPreviews), size: .large) {
                    context.dispatch(.settings(.max(.feature(.linkPreviews, $0))))
                }
            }
            .controlSize(.large)
            .padding(.top, C.sheetListTop.value)
            HStack {
                Spacer()
                Button(action: done) {
                    HStack(spacing: C.controlGap.value) {
                        Text(SettingsCopy.done)
                        Image(systemName: "return").font(.system(size: C.fontSize.value, weight: .semibold))
                            .padding(.horizontal, C.keyGlyphPadding.value)
                            .background(RoundedRectangle(cornerRadius: C.keyGlyphRadius.value, style: .continuous).strokeBorder(Color.white.opacity(0.6)))
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: C.doneRadius.value))
                .tint(ArtColor.maxInk)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(ViewID.settingsField("previewsDone").identifier)
            }
            .padding(.top, C.sheetDoneTop.value)
        }
        .padding(.horizontal, C.sheetPadding.value)
        .padding(.top, C.sheetTop.value)
        .padding(.bottom, C.sheetBottom.value)
        // Arc's seven boxes make its sheet 372 points tall; Brk's two make it shorter, the width stays Arc's.
        .frame(width: C.sheetSize.value.width, alignment: .topLeading)
        .background(ArtColor.rgb(0xFBFBFF))
    }
}

// MARK: - Links

struct LinksPane: View {
    let context: PaneContext
    @State private var showingRoutes = false
    @State private var explainingRoutes = false
    private var links: LinkSettings { context.settings.links }

    private func send(_ setting: LinkSetting) { context.dispatch(.settings(.links(setting))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LittleBrkBanner()
            VStack(alignment: .leading, spacing: 0) {
                Intro(text: SettingsCopy.littleArcDescription).padding(.top, C.introTop.value)
                SettingsCard {
                    SwitchRow(title: SettingsCopy.globalLittleArcShortcut(context.settings.shortcuts), field: "globalLittleArcShortcut",
                              isOn: links.globalLittleArcShortcut != false) { send(.globalLittleArcShortcut($0)) }
                    if let note = SettingsCopy.globalShortcutNote(context.settings.littleArcShortcut) {
                        Text(note).font(.system(size: C.noteFontSize.value)).foregroundStyle(.secondary)
                            .accessibilityIdentifier("globalLittleArcShortcutNote")
                            .padding(.horizontal, C.rowPadding.value).padding(.bottom, C.rowPadding.value / 2)
                    }
                    CardDivider()
                    SwitchRow(title: SettingsCopy.optionCommandClickLittleArc, field: "optionCommandClickLittleArc",
                              isOn: links.optionCommandClickLittleArc) { send(.optionCommandClickLittleArc($0)) }
                    CardDivider()
                    SwitchRow(title: SettingsCopy.externalLinksInLittleArc, field: "externalLinksInLittleArc",
                              isOn: links.externalLinksInLittleArc) { send(.externalLinksInLittleArc($0)) }
                    CardDivider()
                    CardRow(height: C.popUpRowHeight.value - C.popUpRowBottom.value) { CardLabel(SettingsCopy.littleArcAutoArchive) } trailing: {
                        SettingsPopUp(field: "littleArcAutoArchive",
                                      entries: AutoArchiveThreshold.allCases.map { .option(SettingsCopy.threshold($0, default: LinkSettings.default.littleArcAutoArchive), $0) },
                                      selected: links.littleArcAutoArchive, width: .selected(minimum: 0)) { send(.littleArcAutoArchive($0)) }
                            .padding(.trailing, C.popUpTrailing.value)
                    }
                    .padding(.bottom, C.popUpRowBottom.value)
                }
                .padding(.top, C.introToCard.value)
                Rectangle().fill(SettingsStyle.cardBorder).frame(height: C.borderWidth.value)
                    .padding(.top, C.sectionRule.value).padding(.bottom, C.sectionRuleBelow.value)
                Intro(text: SettingsCopy.peekDescription)
                SettingsCard {
                    SwitchRow(title: SettingsCopy.shiftClickPeek, field: "shiftClickPeek", isOn: links.shiftClickPeek) { send(.shiftClickPeek($0)) }
                    CardDivider()
                    CardRow(height: C.peekNoteRowHeight.value) {
                        VStack(alignment: .leading, spacing: C.peekNoteGap.value) {
                            CardLabel(SettingsCopy.peekFromPinnedAndFavorites)
                            Text(SettingsCopy.peekNote).font(.system(size: C.peekNoteFontSize.value).italic()).foregroundStyle(SettingsStyle.italicNote)
                        }
                        .offset(y: -C.peekNoteRaise.value)
                    } trailing: {
                        SettingsSwitch(field: "peekFromPinnedAndFavorites", isOn: links.peekFromPinnedAndFavorites) { send(.peekFromPinnedAndFavorites($0)) }
                    }
                }
                .padding(.top, C.introToCard.value)
                Rectangle().fill(SettingsStyle.cardBorder).frame(height: C.borderWidth.value)
                    .padding(.top, C.sectionRule.value).padding(.bottom, C.sectionRuleBelow.value)
                SettingsCard {
                    CardRow(height: C.routesRowHeight.value) {
                        HStack(spacing: C.infoGap.value) {
                            CardLabel(SettingsCopy.routesSummary)
                            Image(systemName: "info.circle").font(.system(size: C.infoSize.value)).foregroundStyle(SettingsStyle.text)
                                .overlay(ClickArea(field: "airTrafficControlInfo") { explainingRoutes = true })
                                .popover(isPresented: $explainingRoutes) {
                                    Text(LinksRoutesCopy.explanation).font(SettingsStyle.font).fixedSize(horizontal: false, vertical: true)
                                        .frame(width: C.popoverWidth.value).padding()
                                }
                        }
                    } trailing: {
                        SettingsButton(title: SettingsCopy.airTrafficControlButton, field: "airTrafficControl") { showingRoutes = true }
                    }
                }
            }
            .frame(width: S.contentWidth.value, alignment: .leading)
            .padding(.horizontal, S.horizontalPadding.value)
            .padding(.bottom, C.linksBottom.value)
        }
        .sheet(isPresented: $showingRoutes) {
            AirTrafficControlSheet(routes: context.settings.routes, spaces: context.settings.spaces, links: links, dispatch: context.dispatch) {
                showingRoutes = false
            }
        }
    }
}

/// A paragraph above a card, inset like the card's labels.
struct Intro: View {
    let text: String

    var body: some View {
        Text(text).font(SettingsStyle.font).foregroundStyle(SettingsStyle.text).fixedSize(horizontal: false, vertical: true)
            .lineSpacing(C.introLineSpacing.value)
            .padding(.horizontal, C.rowPadding.value)
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    let context: PaneContext
    @State private var showingMore = false
    private var a: AdvancedSettings { context.settings.advanced }

    private func row(_ symbol: String, _ color: NSColor, _ title: String, _ field: String, _ value: Bool, note: String? = nil,
                     _ setting: @escaping (Bool) -> AdvancedSetting) -> some View {
        CardRow(height: note == nil ? C.iconRowHeight.value : C.iconTwoLineRowHeight.value) {
            HStack(spacing: C.rowIconGap.value) {
                RowIcon(symbol: symbol, color: Color(nsColor: color))
                VStack(alignment: .leading, spacing: 0) {
                    CardLabel(title)
                    if let note { Text(note).font(.system(size: C.noteFontSize.value)).foregroundStyle(SettingsStyle.note) }
                }
            }
        } trailing: {
            SettingsSwitch(field: field, isOn: value) { context.dispatch(.settings(.advanced(setting($0)))) }
        }
    }

    var body: some View {
        CardPane(spacing: C.advancedCardSpacing.value) {
            if showingMore {
                Subpage(title: SettingsCopy.moreSettingsTitle, back: { showingMore = false }) {
                    MoreSettings(context: context)
                }
            } else {
                SettingsCard {
                    row("speaker.wave.2.fill", .systemBlue, SettingsCopy.soundEffects, "soundEffects", a.soundEffects) { .soundEffects($0) }
                    CardDivider()
                    row("hand.tap.fill", .systemBlue, SettingsCopy.hapticsOnReorder, "hapticsOnReorder", a.hapticsOnReorder) { .hapticsOnReorder($0) }
                }
                SettingsCard {
                    row("macwindow", .systemGreen, SettingsCopy.restoreWindowsOnLaunch, "restoreWindowsOnLaunch", a.restoreWindowsOnLaunch) { .restoreWindowsOnLaunch($0) }
                    CardDivider()
                    row("rectangle.topthird.inset.filled", .systemGreen, SettingsCopy.windowDraggingFromPages, "windowDraggingFromPages",
                        a.windowDraggingFromPages) { .windowDraggingFromPages($0) }
                    CardDivider()
                    row("ellipsis.rectangle", .systemRed, SettingsCopy.showFullURLInToolbar, "showFullURLInToolbar", a.showFullURLInToolbar) { .showFullURLInToolbar($0) }
                    CardDivider()
                    row("quote.opening", .systemRed, SettingsCopy.sharedQuotes, "sharedQuotes", a.sharedQuotes, note: SettingsCopy.sharedQuotesNote) { .sharedQuotes($0) }
                }
                SettingsCard {
                    row("play.rectangle", .systemPurple, SettingsCopy.autoPictureInPicture, "autoPictureInPicture", a.autoPictureInPicture) { .autoPictureInPicture($0) }
                    CardDivider()
                    row("paintpalette.fill", .systemPurple, SettingsCopy.themeToCSS, "themeToCSS", a.themeToCSS) { .themeToCSS($0) }
                    CardDivider()
                    row("paintbrush.pointed.fill", .systemPurple, SettingsCopy.boostsEnabled, "boostsEnabled", a.boostsEnabled) { .boostsEnabled($0) }
                }
                HStack(spacing: C.buttonGap.value) {
                    SettingsButton(title: SettingsCopy.moreSettings, field: "moreSettings") { showingMore = true }
                    SettingsButton(title: SettingsCopy.resetTranslatedSitePrompts, field: "resetTranslationExclusions") {
                        context.dispatch(.settings(.max(.resetTranslationExclusions)))
                    }
                    Spacer(minLength: 0)
                    SettingsButton(title: SettingsCopy.exportData, field: "exportData") { context.dispatch(.sidebarData(.syncSettings)) }
                }
            }
        }
    }
}

/// Advanced's "More Settings…": what Brk has beyond Arc's Advanced cards (the default browser, the local AI tool and
/// Brk's own three AI features, numbered favorites, sidebar data, importing a browser file, the tour). Previews are
/// General's "Previews Settings…".
struct MoreSettings: View {
    let context: PaneContext
    private var tabs: TabPreferenceSnapshot { context.settings.tabPreferences }
    private var max: MaxSnapshot { context.settings.max }

    private func send(_ setting: MaxSetting) { context.dispatch(.settings(.max(setting))) }

    var body: some View {
        SettingsCard {
            CardRow(height: C.buttonRowHeight.value) {
                SettingsLabel(text: context.isDefaultBrowser ? SettingsCopy.isDefaultBrowser : SettingsCopy.notDefaultBrowser, field: "defaultBrowserNotice")
            } trailing: {
                SettingsButton(title: SettingsCopy.setAsDefaultBrowser, field: "setAsDefaultBrowser") { context.dispatch(.app(.setAsDefaultBrowser)) }
                    .disabled(context.isDefaultBrowser)
            }
        }
        // Max runs a command-line tool on this Mac (Arc's Max pane has no such choice); Brk's three AI features that
        // Arc 1.170's Max pane does not list are switched here too.
        SettingsCard {
            CardRow(height: C.twoLineRowHeight.value) {
                VStack(alignment: .leading, spacing: C.subtitleGap.value) {
                    CardLabel(MaxCopy.provider)
                    SettingsLabel(text: SettingsCopy.detected(max.detected, active: max.active), field: "aiStatus", secondary: true)
                }
            } trailing: {
                SettingsPopUp(field: "aiProvider", entries: AIProviderChoice.allCases.map { .option(SettingsCopy.provider($0), $0) },
                              selected: max.settings.provider) { send(.provider($0)) }
                    .fixedSize()
            }
            ForEach([AIFeature.askPage, .browse, .translation], id: \.self) { feature in
                CardDivider()
                SwitchRow(title: feature.title, field: feature.rawValue, isOn: max.settings.enabled(feature)) { send(.feature(feature, $0)) }
            }
        }
        // Arc's General pane carries these when its ad blocker is available (anatomy-m 4.2); Arc 1.170's General
        // (P38-a) shows neither, so Brk keeps them here. A site's own choice in Website Controls wins.
        SettingsCard {
            SwitchRow(title: SettingsCopy.blockAds, field: "blockAds", isOn: context.settings.general.blockAds != false) {
                context.dispatch(.settings(.general(.blockAds($0))))
            }
            CardDivider()
            SwitchRow(title: SettingsCopy.hideCookieBanners, field: "hideCookieBanners", isOn: context.settings.general.hideCookieBanners == true) {
                context.dispatch(.settings(.general(.hideCookieBanners($0))))
            }
        }
        SettingsCard {
            SwitchRow(title: SettingsCopy.numberedFavorites, field: "numberedFavorites", isOn: tabs.includeFavoritesInNumbers) {
                context.dispatch(.tabTools(.preferences(includeFavorites: $0, previews: tabs.hoverPreviews)))
            }
        }
        SettingsCard {
            CardRow(height: C.buttonRowHeight.value) {
                VStack(alignment: .leading, spacing: C.subtitleGap.value) {
                    CardLabel(SettingsCopy.sidebarData)
                    Text(context.settings.sidebarData?.status ?? "Not connected.").font(SettingsStyle.font).foregroundStyle(SettingsStyle.note)
                }
            } trailing: {
                SettingsButton(title: SettingsCopy.exportData, field: "sidebarData") { context.dispatch(.sidebarData(.syncSettings)) }
            }
            CardDivider()
            ButtonRow(title: SettingsCopy.importBrowserTitle, button: SettingsCopy.importBrowser, field: "importBrowser") {
                context.dispatch(.sidebarData(.importBrowser))
            }
            CardDivider()
            ButtonRow(title: SettingsCopy.importBrowserFileTitle, button: SettingsCopy.importBrowserFile, field: "importBrowserFile") {
                context.dispatch(.sidebarData(.importFile))
            }
            CardDivider()
            ButtonRow(title: SettingsCopy.tourTitle, button: SettingsCopy.tour, field: "brk101") { context.dispatch(.sidebarData(.tour)) }
        }
    }
}
