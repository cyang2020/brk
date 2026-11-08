import AppKit
import BrkBase
import BrkDomain
import BrkUIKit
import SwiftUI

// Brk's own Max cards (docs/design/ai-native.md): the basic layer's switches under the agent card, and below Arc's six
// rows the accounts (subscription or API key per service, the keys' Save, Remove and Test, who answers decisions) and
// this month's usage. Arc's rows keep their order and look.

/// The basic layer's four switches.
struct BasicFeaturesCard: View {
    let context: PaneContext
    private var max: MaxSettings { context.settings.max.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: MaxBasicMetrics.headerGap.value) {
        CardHeader(text: MaxBasicCopy.featuresTitle)
        SettingsCard {
            ForEach(Array(AIFeature.basicLayer.enumerated()), id: \.element) { index, feature in
                if index > 0 { CardDivider() }
                CardRow(height: MaxBasicMetrics.featureRow.value) {
                    VStack(alignment: .leading, spacing: 2) {
                        CardLabel(feature.title)
                        Text(MaxBasicCopy.description(feature)).font(.system(size: 11)).foregroundStyle(SettingsStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } trailing: {
                    SettingsSwitch(field: feature.rawValue, isOn: max.enabled(feature)) { context.dispatch(.settings(.max(.feature(feature, $0)))) }
                }
            }
        }
        }
    }
}

/// Per service: the subscription or a key; the key's field, Save, Remove and Test; then the decisions backend.
struct AccountsCard: View {
    let context: PaneContext
    private var snapshot: MaxSnapshot { context.settings.max }

    var body: some View {
        VStack(alignment: .leading, spacing: MaxBasicMetrics.headerGap.value) {
        CardHeader(text: MaxBasicCopy.accountsTitle)
        SettingsCard {
            Text(MaxBasicCopy.accountsIntro).font(.system(size: 11)).foregroundStyle(SettingsStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, CardMetrics.rowPadding.value).padding(.vertical, 8)
            ForEach(AIService.allCases, id: \.self) { service in
                CardDivider()
                ServiceRows(context: context, service: service)
            }
            CardDivider()
            CardRow {
                CardLabel(MaxBasicCopy.decisions)
            } trailing: {
                SettingsPopUp<AIDecisionChoice>(field: "decisions", entries: AIDecisionChoice.allCases.map { .option(MaxBasicCopy.decisionTitle($0), $0) },
                                                selected: snapshot.settings.decisions ?? .automatic, width: .selected(minimum: 180)) { context.dispatch(.settings(.max(.decisions($0)))) }
            }
            SettingsLabel(text: MaxBasicCopy.decisionRoute(snapshot.decisionRoute, localReady: snapshot.localDecisions), field: "decisionRoute", secondary: true)
                .padding(.horizontal, CardMetrics.rowPadding.value).padding(.bottom, 8)
        }
        }
    }
}

private struct ServiceRows: View {
    let context: PaneContext
    let service: AIService
    @State private var typed = ""
    /// Bumped by each Save, so the field empties whichever way the key was saved.
    @State private var saves = 0
    private var snapshot: MaxSnapshot { context.settings.max }
    private var status: AIKeyStatus { snapshot.keys[service] ?? AIKeyStatus(stored: false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardRow {
                CardLabel(service.displayName)
            } trailing: {
                if service.agent != nil {
                    SettingsPopUp<AIAccountWay>(field: "account-\(service.rawValue)", entries: AIAccountWay.allCases.map { .option(MaxBasicCopy.way($0, service), $0) },
                                                selected: snapshot.settings.way(service), width: .selected(minimum: 180)) { context.dispatch(.settings(.max(.account(service, $0)))) }
                } else {
                    Text(MaxBasicCopy.decisionsOnly).font(SettingsStyle.font).foregroundStyle(SettingsStyle.secondaryText)
                }
            }
            HStack(spacing: CardMetrics.controlGap.value) {
                KeyField(field: "key-\(service.rawValue)", placeholder: status.stored ? MaxBasicCopy.keySavedPlaceholder : MaxBasicCopy.keyPlaceholder(service), saves: saves) { typed = $0 } submit: { save() }
                SettingsButton(title: MaxBasicCopy.save, field: "key-save-\(service.rawValue)") { save() }
                if status.stored {
                    SettingsButton(title: MaxBasicCopy.test, field: "key-test-\(service.rawValue)") { context.dispatch(.settings(.max(.testKey(service)))) }
                    SettingsButton(title: MaxBasicCopy.remove, field: "key-remove-\(service.rawValue)") { context.storeKey(service, nil) }
                }
            }
            .padding(.horizontal, CardMetrics.rowPadding.value)
            SettingsLabel(text: MaxBasicCopy.keyStatus(status, service: service, way: snapshot.settings.way(service)), field: "key-status-\(service.rawValue)", secondary: true)
                .padding(.horizontal, CardMetrics.rowPadding.value).padding(.vertical, 6)
        }
    }

    private func save() {
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        context.storeKey(service, typed)
        typed = ""
        saves += 1
    }
}

/// A secure field whose text never leaves this view except into the Keychain: Return or Save hands it to `storeKey`,
/// and the field empties.
private struct KeyField: NSViewRepresentable {
    let field: String
    let placeholder: String
    let saves: Int
    let edit: @MainActor (String) -> Void
    let submit: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSSecureTextField {
        let textField = NSSecureTextField(string: "")
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submitted(_:))
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        return textField
    }

    func updateNSView(_ textField: NSSecureTextField, context: NSViewRepresentableContext<Self>) {
        context.coordinator.edit = edit
        context.coordinator.submit = submit
        if context.coordinator.saves != saves {
            // Saved: the key leaves the field, in the field editor too while it is being typed in.
            context.coordinator.saves = saves
            textField.stringValue = ""
            textField.currentEditor()?.string = ""
        }
        textField.identify(.settingsField(field))
        textField.placeholderString = placeholder
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView textField: NSSecureTextField, context: NSViewRepresentableContext<Self>) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: textField.intrinsicContentSize.height)
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var edit: (@MainActor (String) -> Void)?
        var submit: (@MainActor () -> Void)?
        var saves = 0
        @objc func submitted(_ sender: NSSecureTextField) {
            edit?(sender.stringValue)
            submit?()
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSecureTextField else { return }
            edit?(field.stringValue)
        }
    }
}

/// This month's tokens and approximate cost, per feature and route.
struct UsageCard: View {
    let context: PaneContext
    private var ledger: AIUsageLedger? { context.settings.max.settings.usage }

    var body: some View {
        VStack(alignment: .leading, spacing: MaxBasicMetrics.headerGap.value) {
        CardHeader(text: MaxBasicCopy.usageTitle(ledger?.month))
        SettingsCard {
            let rows = (ledger?.rows ?? [:]).sorted { $0.key < $1.key }
            if rows.isEmpty {
                SettingsLabel(text: MaxBasicCopy.noUsage, field: "usage-empty", secondary: true).padding(CardMetrics.rowPadding.value)
            } else {
                ForEach(rows, id: \.key) { key, count in
                    CardDivider()
                    CardRow(height: 30) {
                        CardLabel(key.feature + " · " + MaxBasicCopy.route(key))
                    } trailing: {
                        SettingsLabel(text: MaxBasicCopy.count(count, way: key.way), field: "usage-\(key.feature)-\(key.service.rawValue)-\(key.way.rawValue)", secondary: true)
                    }
                }
                CardDivider()
                CardRow(height: 34) {
                    SettingsLabel(text: MaxBasicCopy.usageTotal(rows.map(\.value).reduce(AIUsageCount(requests: 0), +)), field: "usage-total", secondary: true)
                } trailing: {
                    SettingsButton(title: MaxBasicCopy.reset, field: "usage-reset") { context.dispatch(.settings(.max(.resetUsage))) }
                }
            }
        }
        }
    }
}

enum MaxBasicCopy {
    static let featuresTitle = "Brk Features"
    static let accountsTitle = "Accounts"
    static let accountsIntro = "Each service runs on your subscription (Claude Code or Codex signed in on this Mac) or on your own API key, billed by the service. Keys stay in your Mac's Keychain and go only to their own service."
    static let decisions = "Decisions"
    static let decisionsOnly = "Decisions only"
    static let save = "Save"
    static let test = "Test"
    static let remove = "Remove"
    static let keySavedPlaceholder = "Key saved — type a new one to replace it"
    static let noUsage = "Nothing yet this month."
    static let reset = "Reset"
    static let basicModel = "Basic Features Model"
    static let basicEffort = "Basic Features Effort"

    static func description(_ feature: AIFeature) -> String {
        switch feature {
        case .tabNames: "Short names for your tabs once a page loads, and again when the tab goes to another site. Names you type yourself are never changed."
        case .folderNames: "Groups made by Tidy get names, and Name with AI on a folder's or group's right-click menu names it from its tabs."
        case .tabPlacement: "A new tab joins the group it fits when Brk is sure, with an undo; otherwise it suggests the move under the tab. Another Space is only ever suggested."
        case .tabCleanup: "Beside Tidy, a list of duplicate tabs and tabs you have not opened lately, to close or archive in one click."
        default: ""
        }
    }

    static func keyPlaceholder(_ service: AIService) -> String {
        switch service {
        case .anthropic: "Anthropic API key (sk-ant-…)"
        case .openai: "OpenAI API key (sk-…)"
        case .typesafe: "TypeSafe API key"
        }
    }

    static func way(_ way: AIAccountWay, _ service: AIService) -> String {
        switch way {
        case .subscription: service.agent.map { "\($0.displayName) subscription" } ?? "Subscription"
        case .apiKey: "API key"
        }
    }

    static func keyStatus(_ status: AIKeyStatus, service: AIService, way: AIAccountWay) -> String {
        guard status.stored else {
            if case .failed(let reason)? = status.test { return reason }
            if service.agent == nil { return "No key. Add one to choose Jev under Decisions." }
            return way == .apiKey ? "No key saved yet: the \(service.agent!.displayName) subscription is used until you add one." : "No key saved."
        }
        switch status.test {
        case .testing?: return "Key saved. Testing…"
        case .works(let models)?:
            let shown = models.prefix(6).joined(separator: ", ")
            return "Key saved and it works: \(models.count) models" + (shown.isEmpty ? "." : ", including \(shown)\(models.count > 6 ? "…" : "").")
        case .failed(let reason)?: return "Key saved, but the test failed: \(reason)"
        case nil: return "Key saved in the Keychain. Test checks it with \(service.displayName)."
        }
    }

    static func decisionTitle(_ choice: AIDecisionChoice) -> String {
        switch choice {
        case .automatic: "Automatic"
        case .openai: "OpenAI Decisions (key)"
        case .jev: "TypeSafe Jev (key)"
        case .textModel: "Basic features model"
        }
    }

    static func decisionRoute(_ route: AIDecisionRoute, localReady: Bool = false) -> String {
        let yesNo = localReady && route != .local ? " Yes/no questions (is this a duplicate?) go to JevK5 on this Mac." : ""
        return decisionChoices(route) + yesNo
    }

    private static func decisionChoices(_ route: AIDecisionRoute) -> String {
        switch route {
        case .local: "Decisions are answered by JevK5 on this Mac, with probabilities: sure answers act, others suggest."
        case .openai: "Decisions go to OpenAI's Decisions API with your key, with probabilities: sure answers act, others suggest."
        case .jev: "Decisions go to TypeSafe's Jev with your key, with probabilities: sure answers act, others suggest."
        case .textModel(let basic):
            "Decisions are answered by the basic features model (\(routeText(basic))). It gives no probabilities, so its answers only suggest."
        }
    }

    /// "claude-haiku-5-5" → "Haiku 5.5", "gpt-6-luna" → "GPT-6 Luna"; other ids as they are.
    static func modelName(_ id: String) -> String {
        let parts = id.split(separator: "-").map(String.init)
        if parts.first == "claude", parts.count >= 3, parts.dropFirst(2).allSatisfy({ Int($0) != nil }) {
            return parts[1].capitalized + " " + parts.dropFirst(2).joined(separator: ".")
        }
        if parts.first == "gpt", parts.count >= 3 { return "GPT-" + parts[1] + " " + parts.dropFirst(2).map(\.capitalized).joined(separator: " ") }
        return id
    }

    static func routeText(_ route: AIBasicRoute) -> String {
        switch route {
        case .cli(let kind, let model, _): "\(model.map(modelName) ?? "the default model") on your \(kind.displayName) subscription"
        case .api(let service, let model, _): "\(modelName(model)) with your \(service.displayName) API key"
        case .unavailable(let reason): reason
        }
    }

    static func basicRoute(_ route: AIBasicRoute) -> String {
        if case .unavailable(let reason) = route { return reason }
        return "Basic features run on \(routeText(route))."
    }

    static func route(_ key: AIUsageKey) -> String {
        key.way == .apiKey ? "\(key.service.displayName) key" : "\(key.service.agent?.displayName ?? key.service.displayName) subscription"
    }

    static func usageTitle(_ month: String?) -> String {
        guard let month, let date = ISO8601DateFormatter().date(from: month + "-01T00:00:00Z") else { return "Usage This Month" }
        let format = DateFormatter()
        format.dateFormat = "LLLL yyyy"
        format.timeZone = TimeZone(identifier: "UTC")
        return "Usage in \(format.string(from: date))"
    }

    static func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000) : n >= 1_000 ? String(format: "%.1fK", Double(n) / 1_000) : "\(n)"
    }

    static func count(_ count: AIUsageCount, way: AIAccountWay) -> String {
        let base = "\(count.requests) requests · \(tokens(count.inputTokens)) in · \(tokens(count.outputTokens)) out"
        if way == .subscription { return base + " · on subscription" }
        return base + (count.cost.map { String(format: " · about $%.4f", $0) } ?? " · price unknown")
    }

    static func usageTotal(_ count: AIUsageCount) -> String {
        "Total: \(count.requests) requests, \(tokens(count.inputTokens + count.outputTokens)) tokens" + (count.cost.map { String(format: ", about $%.2f on API keys", $0) } ?? "")
    }
}

let MaxBasicMetrics = MaxBasicMetricsTable()
struct MaxBasicMetricsTable: MetricGroup {
    let featureRow = Metric(58.0, .guess("a Brk feature row: a title and a two-line description in 11 pt"))
    let headerGap = Metric(6.0, .guess("a Brk card's header above the card"))
}
