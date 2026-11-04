import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: F2. The Profiles pane as Arc 1.170 lays it out (P38-d): Arc's paragraph; at the left "Your Profiles" (each
/// profile with its space count; + adds one, − deletes the selected one with Arc's type-the-name confirmation, the
/// pencil renames it); at the right the selected profile's settings in three cards: search (engine, the Site Search
/// sub-page, suggestions), Auto-Archive, new documents and downloads, and "Your Data and Settings" (Chromium's
/// privacy, passwords, payment and notification pages open in a tab of that profile; Clear Browsing Data is a
/// sub-page here).
///
/// Every control dispatches a command (`.profile(...)` or `.settings(.profile(...))`); the only local state is the
/// selection, what is being typed, the open sub-page and which confirmation is open. Copy and the delete and name
/// rules are `ProfileCopy`'s, so the pane, the dialogs and the reducer agree.
struct ProfilesPane: View {
    let context: PaneContext
    private var settings: SettingsSnapshot { context.settings }
    private var dispatch: Dispatch { context.dispatch }

    @State private var selection: ProfileID?
    @State private var adding = false
    @State private var newName = ""
    @State private var renaming: ProfileID?
    @State private var renames: [ProfileID: String] = [:]
    @State private var deleting: ProfileRow?
    @State private var typedName = ""
    @State private var deletingUnused = false
    @State private var subpage: ProfileSubpage?
    @State private var explainingProfiles = false

    private var names: [String] { settings.profiles.map(\.profile.name) }
    private var selected: ProfileSettingsRow? {
        settings.profiles.first { $0.profile.id == selection } ?? settings.profiles.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: P.introToColumns.value) {
            LinkedText(parts: [.text(ProfileCopy.paneIntro + " "), .link(SettingsCopy.learnMore + ".", id: "profiles")], underline: true) { _ in explainingProfiles = true }
                .popover(isPresented: $explainingProfiles) {
                    Text(ProfileCopy.paneDetail).font(SettingsStyle.font).fixedSize(horizontal: false, vertical: true)
                        .frame(width: CardMetrics.popoverWidth.value).padding()
                }
            HStack(alignment: .top, spacing: P.columnGap.value) {
                // Half a point wider than its place in the row, to the left (the cards keep their column).
                profileList.frame(width: P.listWidth.value + P.listOverhang.value, height: listHeight)
                    .frame(width: P.listWidth.value).offset(x: -P.listOverhang.value / 2)
                if let row = selected {
                    VStack(alignment: .leading, spacing: CardMetrics.cardSpacing.value) {
                        switch subpage {
                        case .siteSearch?:
                            Subpage(title: ProfilesCopy.searchSettingsTitle, back: { subpage = nil }) {
                                SettingsCard { SiteSearchEditor(profile: row.profile.id, engines: row.settings.siteSearchEngines ?? [], dispatch: dispatch).padding(CardMetrics.rowPadding.value) }
                            }
                        case .clearData?:
                            Subpage(title: ProfilesCopy.clearBrowsingData, back: { subpage = nil }) {
                                ClearProfileData(context: context, row: row)
                            }
                        case nil:
                            ProfileSettingsForm(context: context, row: row) { subpage = $0 }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(width: Metrics.settings.contentWidth.value, alignment: .topLeading)
        .padding(.horizontal, Metrics.settings.horizontalPadding.value)
        .padding(.top, CardMetrics.paneTop.value)
        .onChange(of: selection) { subpage = nil }
        .alert(ProfileCopy.deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            TextField(ProfileCopy.deleteTypePrompt, text: $typedName)
            Button(ProfileCopy.deleteButton, role: .destructive) {
                if let row = deleting, ProfileCopy.trimmed(typedName) == row.name { dispatch(.profile(.delete(row.id))) }
                deleting = nil
            }
            Button(ProfileCopy.cancel, role: .cancel) { deleting = nil }
        } message: {
            Text("\(ProfileCopy.deleteWarning(deleting?.name ?? ""))\n\n\(ProfileCopy.deleteTypePrompt)")
        }
        .alert(ProfileCopy.deleteUnusedTitle, isPresented: $deletingUnused) {
            Button(ProfileCopy.deleteButton, role: .destructive) {
                for row in Self.unused(settings.profiles) { dispatch(.profile(.delete(row.id))) }
            }
            Button(ProfileCopy.cancel, role: .cancel) {}
        } message: {
            Text("\(ProfileCopy.deleteUnusedWarning)\n\n\(ProfileCopy.deleteUnusedList)\(Self.unused(settings.profiles).map(\.name).joined(separator: ", "))")
        }
    }

    /// The list box reaches 12 points above the window's bottom (P38-d).
    private var listHeight: CGFloat {
        let used = CardMetrics.paneTop.value + P.introHeight.value + P.introToColumns.value + P.listBottom.value
        return max(P.listMinHeight.value, context.size.height - used)
    }

    /// Profiles no space uses, which "Delete unused Profiles" removes (never the default one).
    static func unused(_ rows: [ProfileSettingsRow]) -> [ProfileRow] {
        rows.map(\.profile).filter { ProfileCopy.deleteRefusal($0) == nil }
    }

    // MARK: List

    private var profileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ProfilesCopy.yourProfiles).font(.system(size: P.listCaptionFont.value, weight: .semibold)).foregroundStyle(Color.primary.opacity(P.listCaptionOpacity.value))
                .padding(.leading, P.listInset.value).frame(height: P.listHeader.value).offset(y: P.listCaptionDrop.value)
            ListRule()
            ScrollView {
                VStack(alignment: .leading, spacing: P.listRowGap.value) {
                    ForEach(settings.profiles, id: \.profile.id) { row in listRow(row) }
                    if adding { newProfileRow }
                    ForEach(settings.deletingProfiles, id: \.profile) { pending in
                        VStack(alignment: .leading, spacing: CardMetrics.subtitleGap.value) {
                            CardLabel(pending.name)
                            if let failure = pending.failure {
                                Text("Profile deletion could not finish: " + failure).font(.caption).foregroundStyle(SettingsStyle.note)
                                SettingsButton(title: "Retry deletion", field: "retryDeletion-\(pending.profile)") { dispatch(.profile(.delete(pending.profile))) }
                            } else {
                                Text("Stopping this profile's browsers and downloads…").font(.caption).foregroundStyle(SettingsStyle.note)
                            }
                        }
                        .padding(.horizontal, P.rowInset.value)
                    }
                }
                .padding(.horizontal, P.listPadding.value)
                .padding(.vertical, P.listTop.value)
            }
            CardDivider(inset: 0)
            bottomBar
        }
        .background(RoundedRectangle(cornerRadius: CardMetrics.cornerRadius.value, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: CardMetrics.cornerRadius.value, style: .continuous).strokeBorder(Color(nsColor: P.listEdge)))
        .contextMenu {
            Button(ProfileCopy.deleteUnusedTitle + "…") { deletingUnused = true }.disabled(Self.unused(settings.profiles).isEmpty)
        }
    }

    @ViewBuilder
    private func listRow(_ row: ProfileSettingsRow) -> some View {
        let id = row.profile.id, isSelected = id == selected?.profile.id
        let others = settings.profiles.filter { $0.profile.id != id }.map(\.profile.name)
        HStack(spacing: CardMetrics.controlGap.value) {
            if renaming == id {
                SettingsTextField(field: "profileName-\(id)", text: row.profile.name, placeholder: ProfileCopy.renameTitle,
                                  edit: { renames[id] = $0 }) { name in
                    if ProfileCopy.acceptsName(name, among: others) {
                        dispatch(.profile(.rename(id, name: name)))
                        renames[id] = nil
                        renaming = nil
                    }
                }
                .help(ProfileCopy.renameNote)
            } else {
                Text(row.profile.name).font(SettingsStyle.font).foregroundStyle(SettingsStyle.text).lineLimit(1)
                Spacer(minLength: CardMetrics.controlGap.value)
                Text(SettingsCopy.spaceCount(row.profile.spaceTitles.count))
                    .font(.system(size: P.listCaptionFont.value)).foregroundStyle(SettingsStyle.secondaryText).lineLimit(1)
                    .help(ProfileCopy.spaceCount(row.profile.spaceTitles))
            }
        }
        .padding(.horizontal, P.rowInset.value)
        .frame(height: P.rowHeight.value)
        .background(RoundedRectangle(cornerRadius: P.rowRadius.value, style: .continuous).fill(isSelected ? P.selectedFill : Color.clear))
        .background(ClickArea(field: "profileRow-\(id)") { selection = id })
        if renaming == id, ProfileCopy.isTaken(renames[id] ?? row.profile.name, among: others) {
            Text(ProfileCopy.nameTaken).font(.caption).foregroundStyle(.red).padding(.horizontal, P.rowInset.value)
        }
    }

    private var newProfileRow: some View {
        VStack(alignment: .leading, spacing: CardMetrics.subtitleGap.value) {
            HStack(spacing: CardMetrics.controlGap.value) {
                SettingsTextField(field: "newProfileName", text: newName, placeholder: ProfileCopy.namePlaceholder,
                                  edit: { newName = $0 }, submit: create) { newName = $0 }
                SettingsButton(title: ProfilesCopy.create, field: "createProfile") { create(newName) }
                    .disabled(!ProfileCopy.acceptsName(newName, among: names))
            }
            if ProfileCopy.isTaken(newName, among: names) { Text(ProfileCopy.nameTaken).font(.caption).foregroundStyle(.red) }
        }
        .padding(.horizontal, P.rowInset.value)
    }

    private var bottomBar: some View {
        let refusal = selected.flatMap { ProfileCopy.deleteRefusal($0.profile) }
        let id = selected?.profile.id.rawValue ?? ""
        return HStack(spacing: 0) {
            barButton(ProfilesCopy.add, "plus", field: "addProfile") { adding = true; newName = "" }
            Rectangle().fill(SettingsStyle.cardBorder).frame(width: CardMetrics.borderWidth.value)
            barButton(ProfileCopy.deleteTitle, "minus", field: "deleteProfile-\(id)") {
                typedName = ""
                deleting = selected?.profile
            }
            .disabled(refusal != nil)
            .help(refusal ?? ProfileCopy.deleteWarning(selected?.profile.name ?? ""))
            Rectangle().fill(SettingsStyle.cardBorder).frame(width: CardMetrics.borderWidth.value)
            barButton(ProfileCopy.renameTitle, "rectangle.and.pencil.and.ellipsis", field: "editProfile") {
                renaming = selected?.profile.id
            }
            Spacer(minLength: 0)
        }
        .frame(height: P.barHeight.value)
    }

    private func barButton(_ title: String, _ symbol: String, field: String, action: @escaping @MainActor () -> Void) -> some View {
        SettingsButton(title: title, field: field, symbol: symbol, action: action).frame(width: P.barButton.value, height: P.barHeight.value)
    }

    private func create(_ name: String) {
        guard ProfileCopy.acceptsName(name, among: names) else { return }
        dispatch(.profile(.create(name: ProfileCopy.trimmed(name), icon: nil)))
        newName = ""
        adding = false
    }
}

enum ProfileSubpage: Hashable { case siteSearch, clearData }

/// One profile's own settings (Arc: `ProfilePreferences.State`), the right column of the Profiles pane.
struct ProfileSettingsForm: View {
    let context: PaneContext
    let row: ProfileSettingsRow
    let open: @MainActor (ProfileSubpage) -> Void
    private var id: ProfileID { row.profile.id }
    private var settings: ProfileSettings { row.settings }

    private func send(_ setting: ProfileSetting) { context.dispatch(.settings(.profile(id, setting))) }
    private var popUpWidth: PopUpWidth { .selected(minimum: CardMetrics.profilePopUpMinimum.value) }

    var body: some View {
        SettingsCard {
            CardRow(height: P.popUpRow.value, gap: 0) { CardLabel(ProfilesCopy.searchEngine).fixedSize() } trailing: {
                SettingsPopUp(field: "searchEngine-\(id)", entries: (context.settings.engines.map { ($0.name, $0.id) } + (settings.siteSearchEngines ?? []).map { ($0.name, $0.id) }).map { .option($0.0, $0.1) },
                              selected: settings.searchEngine, width: popUpWidth) { send(.searchEngine($0)) }
                    .frame(width: P.popUpColumn.value)
            }
            CardDivider()
            ButtonRow(title: ProfilesCopy.manageSearch, button: ProfilesCopy.searchSettings, field: "searchSettings-\(id)", height: P.popUpRow.value) { open(.siteSearch) }
            CardDivider()
            SwitchRow(title: SettingsCopy.searchSuggestions, field: "searchSuggestions-\(id)", isOn: settings.searchSuggestions) { send(.searchSuggestions($0)) }
        }
        SettingsCard {
            CardRow(height: P.popUpRow.value, gap: 0) {
                HStack(spacing: CardMetrics.subtitleGap.value) {
                    CardLabel(ProfilesCopy.archiveTabsAfter)
                    Image(systemName: "info.circle").foregroundStyle(SettingsStyle.text).help(ProfilesCopy.archiveHelp)
                }
                .fixedSize()
            } trailing: {
                SettingsPopUp(field: "autoArchive-\(id)", entries: AutoArchiveThreshold.allCases.map { .option(SettingsCopy.threshold($0, default: .default), $0) },
                              selected: settings.autoArchive, width: popUpWidth) { send(.autoArchive($0)) }
                    .frame(width: P.popUpColumn.value)
            }
            CardDivider()
            CardRow(height: P.popUpRow.value, gap: 0) { CardLabel(ProfilesCopy.newDocuments).fixedSize() } trailing: {
                // Arc's Default Document App: "——" or a web app; the command bar's New document row opens it.
                SettingsPopUp(field: "newDocuments-\(id)",
                              entries: [PopUpEntry<DocumentApp?>.option(ProfilesCopy.noDocumentApp, nil), .separator]
                                + DocumentApp.allCases.map { .option($0.title, $0) },
                              selected: settings.documentApp) { send(.documentApp($0)) }
                    .frame(width: P.documentsWidth.value).frame(width: P.popUpColumn.value)
            }
            CardDivider()
            CardRow(height: P.popUpRow.value, gap: 0) { CardLabel(ProfilesCopy.downloadLocation).fixedSize() } trailing: {
                SettingsPopUp(field: "downloadLocation-\(id)", entries: downloadEntries,
                              selected: settings.promptForDownloadLocation ? DownloadChoice.prompt : .folder, width: popUpWidth) { choice in
                    send(.promptForDownloadLocation(choice == .prompt))
                }
                .frame(width: P.popUpColumn.value)
            }
        }
        CardHeader(text: ProfilesCopy.yourData).padding(.top, P.dataHeaderTop.value).padding(.bottom, P.dataHeaderBottom.value)
        SettingsCard {
            VStack(spacing: 0) {
                dataRow("lock.fill", P.dataBlue, ProfilesCopy.privacy, "privacy") { context.dispatch(.settings(.openBrowserPage(.privacy, profile: id))) }
                dataRow("key.fill", P.dataGreen, ProfilesCopy.passwords, "passwords") { context.dispatch(.settings(.openBrowserPage(.passwords, profile: id))) }
                dataRow("creditcard.fill", P.dataYellow, ProfilesCopy.creditCards, "creditCards") { context.dispatch(.settings(.openBrowserPage(.paymentMethods, profile: id))) }
                dataRow("bell.fill", P.dataOrange, ProfilesCopy.notifications, "notifications") { context.dispatch(.settings(.openBrowserPage(.notifications, profile: id))) }
                dataRow("trash.fill", P.dataRed, ProfilesCopy.clearBrowsingData, "clearBrowsingData") { open(.clearData) }
            }
            .padding(.vertical, P.dataPadding.value)
        }
    }

    private func dataRow(_ symbol: String, _ color: NSColor, _ title: String, _ name: String, action: @escaping @MainActor () -> Void) -> some View {
        HStack(spacing: CardMetrics.controlGap.value) {
            RowIcon(symbol: symbol, color: Color(nsColor: color), size: P.dataIcon.value)
            Text(title).font(SettingsStyle.font).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: CardMetrics.controlGap.value)
            Image(systemName: "arrow.right").font(.system(size: P.arrowSize.value, weight: .regular)).foregroundStyle(Color(nsColor: P.dataArrow))
        }
        .padding(.horizontal, CardMetrics.rowPadding.value)
        .frame(height: P.dataRow.value)
        .background(ClickArea(field: "profileData-\(name)-\(id)", action: action))
    }

    /// Arc's three kinds of item: the folder, ask each time, and "Other…" (tags `arc.folder`,
    /// `arc.promptForDownload`, `arc.other`).
    private var downloadEntries: [PopUpEntry<DownloadChoice>] {
        let folder = settings.downloadsDirectory
        let title = folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? SettingsCopy.downloadsFolder
        let icon = NSWorkspace.shared.icon(forFile: folder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory())
        icon.size = CGSize(width: Metrics.settings.menuIconSize.value, height: Metrics.settings.menuIconSize.value)
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

/// "Clear Browsing Data" for one profile: what to remove, then Arc's confirmation.
struct ClearProfileData: View {
    let context: PaneContext
    let row: ProfileSettingsRow
    @State private var confirming = false
    @State private var kinds: Set<SiteDataKind> = [.cookies, .cache, .history]
    private var id: ProfileID { row.profile.id }

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: Metrics.settings.rowSpacing.value) {
                SettingsNote(text: ProfilesCopy.clearIntro)
                ForEach([SiteDataKind.cookies, .cache, .history], id: \.self) { kind in
                    Toggle(ProfilesCopy.kind(kind), isOn: Binding(get: { kinds.contains(kind) }, set: { on in
                        if on { kinds.insert(kind) } else { kinds.remove(kind) }
                    }))
                }
                SettingsNote(text: ProfilesCopy.clearLimits)
                SettingsButton(title: ProfilesCopy.clearButton, field: "clearProfileData-\(id)") { confirming = true }
                    .disabled(kinds.isEmpty || row.clearingData == true)
                if row.clearingData == true { ProgressView(ProfilesCopy.clearing) }
                if let result = row.clearDataResult {
                    Text((result.error.map { "Could not finish: " + $0 + "\n" } ?? "") + "Cleared: " + (result.completed.isEmpty ? "none" : result.completed.map(\.rawValue).sorted().joined(separator: ", ")))
                        .font(.caption).textSelection(.enabled)
                }
            }
            .padding(CardMetrics.rowPadding.value)
        }
        .alert("Clear browsing data for \(row.profile.name)?", isPresented: $confirming) {
            Button("Clear selected data", role: .destructive) { context.dispatch(.site(.clearProfile(id, kinds))) }.keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(kinds.map(\.rawValue).sorted().joined(separator: ", ")) from this profile only. Active downloads and document output must finish first. This does not delete the profile or its origin storage.")
        }
    }
}

/// A profile's icon: its emoji, named icon or symbol; a person glyph without one.
struct ProfilePaneGlyph: View {
    let icon: CustomIcon?

    var body: some View {
        switch icon {
        case nil: Image(systemName: "person.crop.circle")
        case .emoji(let emoji)?: Text(emoji)
        case .named(let name)?: Image(systemName: Self.symbol(name))
        case .symbol(let symbol)?: Image(systemName: symbol)
        }
    }

    /// The same SF Symbols the sidebar and the dialogs draw for Arc's named icons.
    static func symbol(_ icon: NamedIcon) -> String {
        icon.systemSymbolName
    }
}

/// The pane's words: Arc's labels (observed in P38-d), Brk's for the sub-pages.
enum ProfilesCopy {
    static let yourProfiles = "Your Profiles"
    static let add = "New Profile"
    static let create = "Create"
    static let searchEngine = "Search engine"
    static let manageSearch = "Manage search"
    static let searchSettings = "Search Settings…"
    static let searchSettingsTitle = "Site Search"
    static let archiveTabsAfter = "Archive tabs after"
    static let archiveHelp = "Today tabs you have not opened for this long move to the Archive. Pinned tabs and Favorites stay."
    static let newDocuments = "New documents"
    static let noDocumentApp = "——"
    static let downloadLocation = "Download location"
    static let yourData = "Your Data and Settings"
    static let privacy = "Privacy and Security"
    static let passwords = "Passwords"
    static let creditCards = "Credit Cards"
    static let notifications = "Notifications"
    static let clearBrowsingData = "Clear Browsing Data"
    static let clearIntro = "These controls affect only this profile, across all its Spaces. Profile settings, tabs, extensions and downloaded files are kept."
    static let clearLimits = "Profile-wide localStorage, IndexedDB, Cache Storage and service-worker removal is unavailable. To remove those, open each website and use Website Controls → Site storage. HTTP cache removal always covers this entire profile."
    static let clearButton = "Clear selected browsing data…"
    static let clearing = "Clearing this profile’s data…"

    static func kind(_ kind: SiteDataKind) -> String {
        switch kind {
        case .cache: "HTTP cache"
        case .history: "\(Product.name) browsing history"
        default: "Cookies (including HttpOnly and domain cookies)"
        }
    }
}

private var P: ProfilesPaneMetricsTable { ProfilesPaneMetrics }

let ProfilesPaneMetrics = ProfilesPaneMetricsTable()

struct ProfilesPaneMetricsTable: MetricGroup {
    private static let capture = "verify/visual-pairs/run-20261103/P38/P38-d-arc.png"
    var selectedFill: Color { ArtColor.rgb(0xEEF2FD) }
    let introHeight = Metric(32.0, .anatomy("\(capture): two 16-point lines"))
    let introToColumns = Metric(20.0, .anatomy("\(capture): the paragraph ends near y 280 px, the columns start at 320 px"))
    let listWidth = Metric(205.5, .anatomy("\(capture): the list spans x 128 to 539 px"))
    let columnGap = Metric(9.5, .anatomy("\(capture): the list ends at x 539 px, the cards start at 558 px"))
    let listOverhang = Metric(0.5, .anatomy("\(capture): the list's left edge is at x 127 px, the cards' column is 128 px"))
    let listCaptionDrop = Metric(0.5, .anatomy("\(capture): 'Your Profiles' spans y 339 to 355 px"))
    let listEdge = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0xE0 / 255.0, alpha: 1)
    }
    let listCaptionOpacity = Metric(0.47, .anatomy("\(capture): 'Your Profiles' is #9E9E9E at its darkest"))
    // The data rows' squares and arrows are lighter than the system colours the Advanced pane's squares use.
    let dataBlue = NSColor(srgbRed: 0x48 / 255.0, green: 0x9A / 255.0, blue: 0xFE / 255.0, alpha: 1)
    let dataGreen = NSColor(srgbRed: 0x63 / 255.0, green: 0xCF / 255.0, blue: 0x74 / 255.0, alpha: 1)
    let dataYellow = NSColor(srgbRed: 1, green: 0xD4 / 255.0, blue: 0x43 / 255.0, alpha: 1)
    let dataOrange = NSColor(srgbRed: 1, green: 0x9F / 255.0, blue: 0x50 / 255.0, alpha: 1)
    let dataRed = NSColor(srgbRed: 1, green: 0x5F / 255.0, blue: 0x5D / 255.0, alpha: 1)
    let dataArrow = NSColor(srgbRed: 0x43 / 255.0, green: 0x8F / 255.0, blue: 0xFE / 255.0, alpha: 1)
    let listBottom = Metric(12.0, .anatomy("\(capture): the list ends at y 1276 px of 1300"))
    let listMinHeight = Metric(200.0, .guess("the list's height on a short screen"))
    let listHeader = Metric(27.0, .anatomy("\(capture): 'Your Profiles' row spans y 320 to 376 px with its 2 px hairline"))
    let listCaptionFont = Metric(11.0, .anatomy("\(capture): 'Your Profiles' is 68.5 pt wide, semibold, and '2 Spaces' 47, regular (13 pt measured 77.5 and 54.5)"))
    let listInset = Metric(16.0, .anatomy("\(capture): 'Your Profiles' starts at x 160 px"))
    let listPadding = Metric(16.0, .anatomy("\(capture): the selected row spans x 160 to 506 px"))
    let listTop = Metric(14.0, .anatomy("\(capture): the header's hairline at y 376 px, the first row at 404 px"))
    let listRowGap = Metric(2.0, .guess("space between profile rows"))
    let rowHeight = Metric(32.0, .anatomy("\(capture): the selected row spans y 404 to 468 px"))
    let rowInset = Metric(6.0, .anatomy("\(capture): 'Default' starts at x 172 px in a row that starts at 160 px"))
    let rowRadius = Metric(8.0, .guess("the selected row's corner"))
    let barHeight = Metric(33.0, .anatomy("\(capture): the bottom bar spans y 1210 to 1276 px"))
    let barButton = Metric(30.0, .anatomy("\(capture): bar separators at x 188 and 249 px"))
    let popUpRow = Metric(44.0, .anatomy("\(capture): Search engine row 320 to 408 px, Manage search 408 to 498 px"))
    let popUpColumn = Metric(180.0, .anatomy("\(capture): every pop-up is centred at x 1040 px"))
    let documentsWidth = Metric(150.0, .anatomy("\(capture): the New documents pop-up spans x 890 to 1190 px"))
    let dataHeaderTop = Metric(4.0, .anatomy("\(capture): the second card ends at y 855 px, the header is centred at 894 px; the column's 8 pt spacing comes first"))
    let dataHeaderBottom = Metric(-4.0, .anatomy("\(capture): the header is centred at y 894 px, the data card starts at 916 px, less than the column's 8 pt spacing leaves"))
    let dataPadding = Metric(5.0, .anatomy("\(capture): the data card starts at y 916 px, its first row is centred at 960 px"))
    let dataRow = Metric(34.0, .anatomy("\(capture): data rows centred at y 960, 1028, 1096, 1164, 1232 px"))
    let dataIcon = Metric(24.0, .anatomy("\(capture): the lock square spans x 578 to 626 px"))
    let arrowSize = Metric(13.0, .anatomy("\(capture): the → spans x 1193 to 1216 px, y 951 to 969 px"))
}
