import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

// The six panes. Each shows what anatomy-m 4.2 lists for the pane and the model has; options whose features are
// later waves (ad blocker, previews, translation, auto-update, the global Little Arc hotkey, Default Document App,
// Clear Browsing Data, the capture and ninth-tab switches) are not shown until they exist.
//
// Field names (`settings-field-<name>`) are the ones the control socket clicks; per-profile fields end in the
// profile id.

private var S: SettingsMetrics { Metrics.settings }

// MARK: - General

struct GeneralPane: View {
    let context: PaneContext
    private var s: SettingsSnapshot { context.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !context.isDefaultBrowser && !s.general.defaultBrowserPromptDismissed {
                DefaultBrowserNotice(dispatch: context.dispatch)
                SettingsDivider()
            }
            SettingsSection {
                SettingsNote(text: SettingsCopy.profileSettingsHint)
                SettingsButton(title: SettingsCopy.profileSettingsButton, field: "profileSettings") {
                    context.dispatch(.settings(.openPane(.profiles)))
                }
            }
            SettingsDivider()
            SettingsSection {
                SettingsCheckbox(title: SettingsCopy.warnBeforeQuitting, field: "warnBeforeQuitting", isOn: s.general.warnBeforeQuitting) {
                    context.dispatch(.settings(.general(.warnBeforeQuitting($0))))
                }
            }
            SettingsDivider()
            SettingsSection {
                SettingsButton(title: "Sidebar Data: Import, Sync and Export", field: "sidebarData") {
                    context.dispatch(.sidebarData(.syncSettings))
                }
                SettingsNote(text: s.sidebarData?.status ?? "Not connected.")
                SettingsButton(title: "Import an exported browser file…", field: "importBrowserFile") {
                    context.dispatch(.sidebarData(.importFile))
                }
                SettingsButton(title: "Open Brk 101", field: "brk101") {
                    context.dispatch(.sidebarData(.tour))
                }
            }
            SettingsDivider()
            SettingsSection(.text(SettingsCopy.appearanceLabel)) {
                Text(SettingsCopy.webAppearance)
                SettingsPopUp(field: "webAppearance", entries: WebAppearance.allCases.map { .option(SettingsCopy.appearance($0), $0) },
                              selected: s.general.webAppearance) { context.dispatch(.settings(.general(.webAppearance($0)))) }
                    .frame(width: S.popUpWidth.value)
            }
        }
    }
}

/// " is not your default web browser." with the two ways out (Arc: MakeDefaultView). Shown until the app is the
/// default browser or the notice is dismissed.
struct DefaultBrowserNotice: View {
    let dispatch: Dispatch

    var body: some View {
        HStack(spacing: S.columnSpacing.value) {
            SettingsLabel(text: SettingsCopy.notDefaultBrowser, field: "defaultBrowserNotice")
            Spacer(minLength: 0)
            SettingsButton(title: SettingsCopy.dismissNotice, field: "dismissDefaultBrowserPrompt") {
                dispatch(.settings(.general(.dismissDefaultBrowserPrompt)))
            }
            SettingsButton(title: SettingsCopy.setAsDefaultBrowser, field: "setAsDefaultBrowser") { dispatch(.app(.setAsDefaultBrowser)) }
        }
        .padding(S.noticePadding.value)
        .background(RoundedRectangle(cornerRadius: S.noticeCornerRadius.value, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: S.noticeCornerRadius.value, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

// MARK: - Max

struct MaxPane: View {
    let context: PaneContext
    private var max: MaxSnapshot { context.settings.max }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection {
                SettingsNote(text: SettingsCopy.maxIntro)
            }
            SettingsDivider()
            SettingsSection(.text(SettingsCopy.aiProvider)) {
                SettingsPopUp(field: "aiProvider", entries: AIProviderChoice.allCases.map { .option(SettingsCopy.provider($0), $0) },
                              selected: max.settings.provider) { context.dispatch(.settings(.max(.provider($0)))) }
                    .frame(width: S.popUpWidth.value)
                SettingsLabel(text: SettingsCopy.detected(max.detected, active: max.active), field: "aiStatus", secondary: true)
                SettingsNote(text: SettingsCopy.maxPrivacy)
            }
            SettingsDivider()
            SettingsSection(.text(SettingsCopy.maxFeatures)) {
                SettingsCheckbox(title: SettingsCopy.renamePinnedTabs, field: "renamePinnedTabs", isOn: max.settings.renamePinnedTabs) {
                    context.dispatch(.settings(.max(.renamePinnedTabs($0))))
                }
                SettingsNote(text: SettingsCopy.renamePinnedTabsDescription, underCheckbox: true)
                SettingsCheckbox(title: SettingsCopy.tidyTabs, field: "tidyTabs", isOn: max.settings.tidyTabs) {
                    context.dispatch(.settings(.max(.tidyTabs($0))))
                }
                SettingsNote(text: SettingsCopy.tidyTabsDescription, underCheckbox: true)
                ForEach(AIFeature.allCases, id: \.self) { feature in
                    SettingsCheckbox(title: feature.title, field: feature.rawValue, isOn: max.settings.enabled(feature)) {
                        context.dispatch(.settings(.max(.feature(feature, $0))))
                    }
                }
                SettingsNote(text: "Use the Tabs menu or Command Bar to ask, organize, find links, browse selected URLs or translate. Hover a link deliberately for a short preview. The tool receives requested page text from regular windows; private windows are excluded.")
                SettingsButton(title: "Reset Never-Translate Choices", field: "resetTranslationExclusions") { context.dispatch(.settings(.max(.resetTranslationExclusions))) }
            }
        }
    }
}

/// One profile's own settings (Arc: `ProfilePreferences.State`).
struct ProfileSettingsForm: View {
    let context: PaneContext
    let row: ProfileSettingsRow
    private var id: ProfileID { row.profile.id }
    private var settings: ProfileSettings { row.settings }

    private func send(_ setting: ProfileSetting) { context.dispatch(.settings(.profile(id, setting))) }

    var body: some View {
        VStack(alignment: .leading, spacing: S.sectionSpacing.value) {
            SettingsSection(.text(SettingsCopy.autoArchive)) {
                SettingsPopUp(field: "autoArchive-\(id)", entries: AutoArchiveThreshold.allCases.map { .option(SettingsCopy.threshold($0), $0) },
                              selected: settings.autoArchive) { send(.autoArchive($0)) }
                    .frame(width: S.popUpWidth.value)
            }
            SettingsSection(.text(SettingsCopy.searchEngine)) {
                SettingsPopUp(field: "searchEngine-\(id)", entries: (context.settings.engines.map { ($0.name, $0.id) } + (settings.siteSearchEngines ?? []).map { ($0.name, $0.id) }).map { .option($0.0, $0.1) },
                              selected: settings.searchEngine) { send(.searchEngine($0)) }
                    .frame(width: S.popUpWidth.value)
                SettingsCheckbox(title: SettingsCopy.searchSuggestions, field: "searchSuggestions-\(id)", isOn: settings.searchSuggestions) {
                    send(.searchSuggestions($0))
                }
            }
            SiteSearchEditor(profile: id, engines: settings.siteSearchEngines ?? [], dispatch: context.dispatch)
            SettingsSection(.text(SettingsCopy.downloadLocation)) {
                SettingsPopUp(field: "downloadLocation-\(id)", entries: downloadEntries,
                              selected: settings.promptForDownloadLocation ? DownloadChoice.prompt : .folder) { choice in
                    send(.promptForDownloadLocation(choice == .prompt))
                }
                .frame(width: S.popUpWidth.value)
            }
        }
    }

    /// Arc's three kinds of item: the folder, ask each time, and "Other…" (tags `arc.folder`,
    /// `arc.promptForDownload`, `arc.other`).
    private var downloadEntries: [PopUpEntry<DownloadChoice>] {
        let folder = settings.downloadsDirectory
        let title = folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? SettingsCopy.downloadsFolder
        let icon = folder.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        icon?.size = CGSize(width: S.menuIconSize.value, height: S.menuIconSize.value)
        var entries: [PopUpEntry<DownloadChoice>] = [
            .option(title, .folder, image: icon),
            .option(SettingsCopy.promptForDownloadLocation, .prompt),
            .separator,
            .action(SettingsCopy.otherFolder) { [context, settings, id] in
                guard let path = context.chooseFolder(settings.downloadsDirectory) else { return }
                context.dispatch(.settings(.profile(id, .downloadsDirectory(path))))
                if settings.promptForDownloadLocation { context.dispatch(.settings(.profile(id, .promptForDownloadLocation(false)))) }
            },
        ]
        if folder != nil {
            entries.append(.action(SettingsCopy.useDownloadsFolder) { [context, settings, id] in
                context.dispatch(.settings(.profile(id, .downloadsDirectory(nil))))
                if settings.promptForDownloadLocation { context.dispatch(.settings(.profile(id, .promptForDownloadLocation(false)))) }
            })
        }
        return entries
    }
}

enum DownloadChoice: Hashable { case folder, prompt }

// MARK: - Links

struct LinksPane: View {
    let context: PaneContext
    private var links: LinkSettings { context.settings.links }

    private func send(_ setting: LinkSetting) { context.dispatch(.settings(.links(setting))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinksRoutesEditor(routes: context.settings.routes, spaces: context.settings.spaces,
                              links: links, dispatch: context.dispatch)
            SettingsDivider()
            SettingsSection(.text(SettingsCopy.peekLabel)) {
                SettingsNote(text: SettingsCopy.peekDescription)
                SettingsCheckbox(title: SettingsCopy.peekFromPinnedAndFavorites, field: "peekFromPinnedAndFavorites", isOn: links.peekFromPinnedAndFavorites) {
                    send(.peekFromPinnedAndFavorites($0))
                }
                SettingsNote(text: SettingsCopy.peekNote, underCheckbox: true)
                SettingsCheckbox(title: SettingsCopy.shiftClickPeek, field: "shiftClickPeek", isOn: links.shiftClickPeek) { send(.shiftClickPeek($0)) }
            }
            SettingsDivider()
            SettingsSection(.text(SettingsCopy.littleArcLabel)) {
                SettingsNote(text: SettingsCopy.littleArcDescription)
                SettingsCheckbox(title: SettingsCopy.externalLinksInLittleArc, field: "externalLinksInLittleArc", isOn: links.externalLinksInLittleArc) {
                    send(.externalLinksInLittleArc($0))
                }
                SettingsCheckbox(title: SettingsCopy.optionCommandClickLittleArc, field: "optionCommandClickLittleArc",
                                 isOn: links.optionCommandClickLittleArc) { send(.optionCommandClickLittleArc($0)) }
                HStack(alignment: .firstTextBaseline, spacing: S.columnSpacing.value) {
                    Text(SettingsCopy.littleArcAutoArchive)
                    SettingsPopUp(field: "littleArcAutoArchive", entries: AutoArchiveThreshold.allCases.map { .option(SettingsCopy.threshold($0), $0) },
                                  selected: links.littleArcAutoArchive) { send(.littleArcAutoArchive($0)) }
                        .frame(width: S.popUpWidth.value)
                }
            }
        }
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    let context: PaneContext
    private var a: AdvancedSettings { context.settings.advanced }

    private func box(_ title: String, _ field: String, _ value: Bool, _ setting: @escaping (Bool) -> AdvancedSetting) -> SettingsCheckbox {
        SettingsCheckbox(title: title, field: field, isOn: value) { context.dispatch(.settings(.advanced(setting($0)))) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(.symbol(SettingsCopy.advancedWebSymbol)) {
                box(SettingsCopy.boostsEnabled, "boostsEnabled", a.boostsEnabled) { .boostsEnabled($0) }
                box(SettingsCopy.themeToCSS, "themeToCSS", a.themeToCSS) { .themeToCSS($0) }
                box(SettingsCopy.autoPictureInPicture, "autoPictureInPicture", a.autoPictureInPicture) { .autoPictureInPicture($0) }
            }
            SettingsDivider()
            SettingsSection(.symbol(SettingsCopy.advancedWindowSymbol)) {
                box(SettingsCopy.windowDraggingFromPages, "windowDraggingFromPages", a.windowDraggingFromPages) { .windowDraggingFromPages($0) }
                SettingsCheckbox(title: "Show tab and folder hover previews", field: "tabHoverPreviews", isOn: context.settings.tabPreferences.hoverPreviews) {
                    context.dispatch(.tabTools(.preferences(includeFavorites: context.settings.tabPreferences.includeFavoritesInNumbers, previews: $0)))
                }
                SettingsCheckbox(title: "Include Favorites in numbered tab shortcuts", field: "numberedFavorites", isOn: context.settings.tabPreferences.includeFavoritesInNumbers) {
                    context.dispatch(.tabTools(.preferences(includeFavorites: $0, previews: context.settings.tabPreferences.hoverPreviews)))
                }
                box(SettingsCopy.sharedQuotes, "sharedQuotes", a.sharedQuotes) { .sharedQuotes($0) }
                box(SettingsCopy.showFullURLInToolbar, "showFullURLInToolbar", a.showFullURLInToolbar) { .showFullURLInToolbar($0) }
                box(SettingsCopy.restoreWindowsOnLaunch, "restoreWindowsOnLaunch", a.restoreWindowsOnLaunch) { .restoreWindowsOnLaunch($0) }
            }
            SettingsDivider()
            SettingsSection(.symbol(SettingsCopy.advancedFeedbackSymbol)) {
                box(SettingsCopy.hapticsOnReorder, "hapticsOnReorder", a.hapticsOnReorder) { .hapticsOnReorder($0) }
                box(SettingsCopy.soundEffects, "soundEffects", a.soundEffects) { .soundEffects($0) }
            }
        }
    }
}
