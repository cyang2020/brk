import AppKit
import BrkBase
import BrkDomain
import BrkUIKit
import SwiftUI

@MainActor
public final class SiteControlsHost: NSView {
    private var hosting: NSHostingView<SiteControlsView>?
    public func render(_ value: SiteControlSnapshot, dispatch: @escaping Dispatch) {
        let view = SiteControlsView(value: value, dispatch: dispatch)
        if let hosting { hosting.rootView = view }
        else {
            let hosting = NSHostingView(rootView: view)
            self.hosting = hosting
            addSubview(hosting)
            hosting.frame = bounds
            hosting.autoresizingMask = [.width, .height]
        }
    }
}

private struct SiteControlsView: View {
    let value: SiteControlSnapshot
    let dispatch: Dispatch
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: s.sectionSpacing.value) {
                Text(value.target?.origin.value ?? "Open a website to change site controls").font(.headline).textSelection(.enabled)
                Text(value.profileName).foregroundStyle(.secondary)
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
                        Button("Load rules JSON…") { dispatch(.site(.loadBlockingRules)) }
                        Button("Restore built-in rules") { dispatch(.site(.resetBlockingRules)) }
                    }
                    if let error = value.rulesError { Text(error).font(.caption) }
                    Divider()
                    ForEach([SiteCapability.camera, .microphone, .location, .notifications], id: \.self) { capability in
                        Picker(capability.rawValue.capitalized, selection: Binding(get: { value.rule.permissions[capability] ?? .ask }, set: { answer in change { $0.permissions[capability] = answer } })) {
                            ForEach(SitePermission.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                    }
                    Text("macOS may also require authorization. Screen capture needs a separate source picker.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Toggle("Suspend this site while its tab is hidden", isOn: Binding(get: { value.rule.suspendWhenHidden }, set: { on in change { $0.suspendWhenHidden = on } }))
                    Toggle("Keep this site alive", isOn: Binding(get: { value.rule.keepAlive }, set: { on in change { $0.keepAlive = on } }))
                    Toggle("Exclude this site from suspension", isOn: Binding(get: { value.rule.excludeSuspension }, set: { on in change { $0.excludeSuspension = on } }))
                    Text("Playing audio/video and active downloads keep pages active. Automatic picture in picture is not available yet.").font(.caption).foregroundStyle(.secondary)
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
                    HStack {
                        Button("Copy URL") { dispatch(.page(.copyURL(.plain))) }
                        Button("Export link…") { dispatch(.app(.export(.focusedTab))) }
                    }
                }
                Divider()
                Button("Refresh installed extensions") { dispatch(.site(.nativeExtensions)) }
                if let error = value.extensionError { Text(error).font(.caption) }
                ForEach(value.extensions.sorted { (value.pinnedExtensions.contains($0.id) ? 0 : 1, $0.name) < (value.pinnedExtensions.contains($1.id) ? 0 : 1, $1.name) }) { item in
                    HStack {
                        Toggle("Pin \(item.name)", isOn: Binding(get: { value.pinnedExtensions.contains(item.id) }, set: { dispatch(.site(.pinExtension(item.id, $0))) }))
                        Button("Open action") { dispatch(.site(.invokeExtension(item.id))) }.disabled(!item.enabled || !item.supportsNativeAction || value.target == nil)
                        Button("Remove") { dispatch(.site(.removeExtension(item.id))) }
                    }
                }
                Text("Use the manager to change permissions or enable and disable extensions. Opening action popups is currently unavailable.").font(.caption).foregroundStyle(.secondary)
                Button("Manage extensions…") { dispatch(.site(.extensions)) }
                Button("Extension shortcuts…") { dispatch(.site(.extensionShortcuts)) }
                Text("Boosts and page capture are not available yet.").font(.caption).foregroundStyle(.secondary)
            }.padding(s.sectionSpacing.value)
        }
        .onChange(of: dataScope) { _, scope in if scope == .profile { selectedData.remove(.storage) } }
        .onChange(of: value.context) { _, _ in selectedData = [.cookies]; dataScope = .site; refreshAfterClear = true }
    }
}
