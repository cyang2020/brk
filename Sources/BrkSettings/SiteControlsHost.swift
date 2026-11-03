import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// The site controls popover's content: Arc's site control center first (`SiteControlsOverview`), and the full site
/// form (address, copy and export, extensions, website appearance, blocking, permissions, suspension, clearing) as a
/// second page opened from the Extensions or Settings title. `onResize` asks the popover for the page's size.
@MainActor
public final class SiteControlsHost: NSView {
    public var onResize: ((CGSize) -> Void)?
    private let overview = SiteControlsOverview()
    private var hosting: NSHostingView<SiteControlsView>?
    private var value: SiteControlSnapshot?
    private var dispatch: Dispatch?
    public private(set) var showingDetails = false

    public override init(frame: NSRect) {
        super.init(frame: frame)
        overview.openDetails = { [weak self] in self?.show(details: true) }
        addSubview(overview)
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError("not used") }
    public override var isFlipped: Bool { true }

    public var preferredSize: CGSize {
        showingDetails ? Metrics.siteControls.detailsSize.value : CGSize(width: Metrics.siteControls.width.value, height: overview.preferredHeight)
    }

    public func render(_ value: SiteControlSnapshot, dispatch: @escaping Dispatch) {
        let resized = self.value.map { $0.extensions.count != value.extensions.count } ?? false
        self.value = value; self.dispatch = dispatch
        overview.render(value, dispatch: dispatch)
        if showingDetails { renderDetails() }
        if resized { onResize?(preferredSize) }
    }

    public func show(details: Bool) {
        guard details != showingDetails else { return }
        showingDetails = details
        if details { renderDetails() } else { hosting?.removeFromSuperview(); hosting = nil }
        overview.isHidden = details
        onResize?(preferredSize)
        needsLayout = true
    }

    private func renderDetails() {
        guard let value, let dispatch else { return }
        let view = SiteControlsView(value: value, dispatch: dispatch, back: { [weak self] in self?.show(details: false) })
        if let hosting { hosting.rootView = view; return }
        let hosting = NSHostingView(rootView: view)
        self.hosting = hosting
        addSubview(hosting)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
    }

    public override func layout() {
        super.layout()
        overview.frame = bounds
        hosting?.frame = bounds
    }
}

private struct SiteControlsView: View {
    let value: SiteControlSnapshot
    let dispatch: Dispatch
    let back: @MainActor () -> Void
    @State private var selectedData: Set<SiteDataKind> = [.cookies]
    @State private var dataScope: SiteDataScope = .site
    @State private var refreshAfterClear = true
    private var privateSession: Bool { if case .incognito? = value.context { true } else { false } }
    private var s: SettingsMetrics { Metrics.settings }
    private func change(_ edit: (inout SiteRule) -> Void) {
        guard let target = value.target else { return }
        var rule = value.rule; edit(&rule)
        dispatch(.site(.rule(target, rule)))
    }
    private var extensionControls: some View {
        VStack(alignment: .leading, spacing: s.sectionSpacing.value) {
                if privateSession { Text("Extension management and action popups are unavailable in private windows.").font(.caption) }
                Button("Refresh installed extensions") { dispatch(.site(.nativeExtensions)) }.disabled(privateSession)
                if let error = value.extensionError { Text(error).font(.caption) }
                ForEach(value.extensions.sorted { (value.pinnedExtensions.contains($0.id) ? 0 : 1, $0.name) < (value.pinnedExtensions.contains($1.id) ? 0 : 1, $1.name) }) { item in
                    VStack(alignment: .leading) {
                    HStack {
                        SettingsCheckbox(title: "Pin \(item.name)", field: "extension-pin-" + item.id, isOn: value.pinnedExtensions.contains(item.id)) {
                            dispatch(.site(.pinExtension(item.id, $0)))
                        }.disabled(privateSession)
                        Button("Open action") { dispatch(.site(.invokeExtension(item.id))) }.disabled(!item.enabled || !item.supportsNativeAction || value.target == nil)
                        Button("Remove") { dispatch(.site(.removeExtension(item.id))) }.disabled(privateSession)
                    }
                    SettingsCheckbox(title: "Allow in private windows", field: "extension-incognito-" + item.id, isOn: item.incognitoAllowed == true) {
                        dispatch(.site(.extensionIncognito(item.id, $0)))
                    }.disabled(privateSession || item.canChangeIncognito != true)
                    ForEach(item.commands ?? []) { command in
                        ExtensionShortcutEditor(extensionID: item.id, command: command, dispatch: dispatch)
                    }
                    }
                }
                Text("Use the manager to change permissions or enable and disable extensions. Opening action popups is currently unavailable.").font(.caption).foregroundStyle(.secondary)
                Button("Manage extensions…") { dispatch(.site(.extensions)) }.disabled(privateSession)
                Button("Extension shortcuts…") { dispatch(.site(.extensionShortcuts)) }.disabled(privateSession)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: s.columnSpacing.value) {
                SettingsButton(title: "Back", field: "siteControlsBack", symbol: "chevron.left", action: back)
                Text("Site Settings").font(.headline)
            }
            .padding(.horizontal, Metrics.siteControls.inset.value)
            .frame(height: Metrics.siteControls.detailsHeader.value)
            Divider()
            form
        }
    }
    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: s.sectionSpacing.value) {
                Text(value.target?.origin.value ?? "Open a website to change site controls").font(.headline).textSelection(.enabled)
                Text(value.profileName).foregroundStyle(.secondary)
                if value.target != nil {
                    HStack {
                        SettingsButton(title: "Copy URL", field: "siteCopyURL") { dispatch(.page(.copyURL(.plain))) }
                        SettingsButton(title: "Export link…", field: "siteExportLink") { dispatch(.app(.export(.focusedTab))) }
                    }
                }
                extensionControls.id(value.context)
                Picker("Website appearance for this profile", selection: Binding(get: { value.appearance }, set: { dispatch(.site(.appearance($0))) })) {
                    ForEach(WebsiteAppearance.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                if let applied = value.applied {
                    if let error = applied.error { Text("Website policy could not finish: " + error).font(.caption) }
                    else { Text("Applied website appearance: " + applied.appearance.rawValue).font(.caption).foregroundStyle(.secondary) }
                }
                if value.target != nil {
                    Toggle("Block known ads and trackers on this site", isOn: Binding(get: { value.rule.blocking }, set: { on in change { $0.blocking = on } }))
                    Toggle("Hide matching cookie banners", isOn: Binding(get: { value.rule.hideCookieBanners }, set: { on in change { $0.hideCookieBanners = on } }))
                    Text("Rules v\(value.rulesVersion). Hiding a banner does not give consent.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Import blocking rules…") { dispatch(.site(.loadBlockingRules)) }
                        Button("Restore built-in rules") { dispatch(.site(.resetBlockingRules)) }
                    }
                    if let error = value.rulesError { Text(error).font(.caption) }
                    Divider()
                    ForEach([SiteCapability.camera, .microphone, .location, .notifications], id: \.self) { capability in
                        Picker(capability.rawValue.capitalized, selection: Binding(get: { value.rule.permissions[capability] ?? .ask }, set: { answer in change { $0.permissions[capability] = answer } })) {
                            ForEach(SitePermission.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                    }
                    if let authorization = value.applied?.osAuthorization {
                        ForEach([SiteCapability.camera, .microphone, .location, .notifications], id: \.self) { capability in
                            Text("macOS " + capability.rawValue + ": " + (authorization[capability] ?? "unknown")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("macOS may also require authorization. Screen capture needs a separate source picker.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Toggle("Suspend this site while its tab is hidden", isOn: Binding(get: { value.rule.suspendWhenHidden }, set: { on in change { $0.suspendWhenHidden = on } }))
                    Toggle("Keep this site alive", isOn: Binding(get: { value.rule.keepAlive }, set: { on in change { $0.keepAlive = on } }))
                    Toggle("Exclude this site from suspension", isOn: Binding(get: { value.rule.excludeSuspension }, set: { on in change { $0.excludeSuspension = on } }))
                    Text("Playing audio/video, audible WebAudio, picture in picture and active operations keep pages active. Automatic picture in picture is not available yet.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Button("Clear cookies and refresh…") { dispatch(.site(.clear(kinds: [.cookies], scope: .site, reload: true))) }
                    Button("Clear profile HTTP cache and refresh…") { dispatch(.site(.clear(kinds: [.cache], scope: .profile, reload: true))) }
                    Picker("Clear browsing data for", selection: $dataScope) {
                        Text("This website").tag(SiteDataScope.site)
                        Text(privateSession ? "This private session" : "This profile").tag(SiteDataScope.profile)
                    }
                    ForEach(SiteDataKind.allCases, id: \.self) { kind in
                        Toggle(kind == .storage ? "Site storage" : kind.rawValue.capitalized, isOn: Binding(get: { selectedData.contains(kind) }, set: { on in
                            if on { selectedData.insert(kind) } else { selectedData.remove(kind) }
                        })).disabled(kind == .storage && dataScope == .profile)
                    }
                    Toggle("Refresh the same document after completion", isOn: $refreshAfterClear)
                    Text("Profile-wide localStorage, IndexedDB, Cache Storage and service-worker removal is unavailable. Choose This website for site storage. The HTTP cache covers the entire originating profile or private session.").font(.caption).foregroundStyle(.secondary)
                    Button("Clear selected data…") { dispatch(.site(.clear(kinds: selectedData, scope: dataScope, reload: refreshAfterClear))) }
                        .disabled(selectedData.isEmpty || value.clearing)
                    if value.clearing {
                        ProgressView("Clearing website data…")
                        Button("Stop remaining steps") { dispatch(.site(.cancelClearing)) }
                    }
                    if let result = value.result {
                        Text((result.error.map { $0 + "\n" } ?? "") + "Cleared: " + (result.completed.isEmpty ? "none" : result.completed.map(\.rawValue).sorted().joined(separator: ", "))).foregroundStyle(result.error == nil ? .secondary : .primary)
                    }
                    Divider()

                }
            }.padding(s.sectionSpacing.value)
        }
        .onChange(of: dataScope) { _, scope in if scope == .profile { selectedData.remove(.storage) } }
        .onChange(of: value.context) { _, _ in selectedData = [.cookies]; dataScope = .site; refreshAfterClear = true }
    }
}

private struct ExtensionShortcutEditor: View {
    let extensionID: String
    let command: BrowserExtensionCommand
    let dispatch: Dispatch
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading) {
            Text(command.description + (command.active ? "" : " (unassigned)"))
            HStack {
                SettingsTextField(field: "extension-shortcut-" + extensionID + "-" + command.name, text: draft,
                                  placeholder: "cmd+shift+u; empty clears", edit: { draft = $0 }) { draft = $0 }
                SettingsButton(title: "Save shortcut", field: "extension-shortcut-save-" + extensionID + "-" + command.name) {
                    dispatch(.site(.extensionShortcut(extensionID, command.name, draft)))
                }
            }
            Text("Current: " + (command.keybinding.isEmpty ? "None" : command.keybinding)).font(.caption)
        }
        .onAppear { draft = command.keybinding }
        .onChange(of: command.keybinding) { _, value in draft = value }
    }
}
