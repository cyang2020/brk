import BrkBase
import BrkDomain
import SwiftUI

/// The Max pane's On This Mac card, Brk's own (Arc has no local models): one row per local model with what it does, how
/// big it is, how much memory it holds while in use, its licence and languages, and the one button that downloads it.
/// Pressing Download is the user's agreement; the row says beforehand what will happen (for the search model: that
/// tab, history and archive titles get indexed on this Mac). Progress shows in the row itself, the only place a
/// download starts from, and goes on with the window closed.
struct LocalModelsCard: View {
    let models: LocalModelsSnapshot
    let send: @MainActor (MaxSetting) -> Void
    private var M: MaxPaneMetricsTable { MaxPaneMetrics }

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: CardMetrics.controlGap.value) {
                CardLabel(LocalModelsCopy.title)
                Text(LocalModelsCopy.intro).font(.system(size: M.descriptionSize.value)).foregroundStyle(SettingsStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(CardMetrics.rowPadding.value)
            ForEach(models.rows, id: \.kind) { row in
                CardDivider()
                LocalModelRowView(row: row, indexed: row.kind == .search ? models.indexed : nil, send: send)
            }
        }
    }
}

private struct LocalModelRowView: View {
    let row: LocalModelRow
    let indexed: Int?
    let send: @MainActor (MaxSetting) -> Void
    private var M: MaxPaneMetricsTable { MaxPaneMetrics }

    var body: some View {
        HStack(alignment: .top, spacing: CardMetrics.controlGap.value) {
            VStack(alignment: .leading, spacing: M.titleGap.value) {
                Text(row.title).font(SettingsStyle.font).foregroundStyle(SettingsStyle.text)
                Text(row.purpose).font(.system(size: M.descriptionSize.value)).foregroundStyle(SettingsStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(LocalModelsCopy.facts(row)).font(.system(size: M.descriptionSize.value)).foregroundStyle(SettingsStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                status
            }
            Spacer(minLength: CardMetrics.controlGap.value)
            VStack(alignment: .trailing, spacing: CardMetrics.controlGap.value) {
                if !row.choices.isEmpty, case .absent = row.stage {
                    SettingsPopUp<String>(field: "localModelFile-\(row.kind.rawValue)",
                                          entries: row.choices.map { .option(LocalModelsCopy.choice($0), $0.id) },
                                          selected: row.chosen, width: .selected(minimum: M.agentPopup.value)) { send(.localModel(.choose(row.kind, file: $0))) }
                }
                action
            }
        }
        .padding(CardMetrics.rowPadding.value)
    }

    @ViewBuilder private var status: some View {
        switch row.stage {
        case .downloading(let received, let total):
            ProgressView(value: Double(received), total: Double(max(total, 1)))
                .progressViewStyle(.linear)
                .frame(width: M.agentPopup.value)
            secondary(LocalModelsCopy.progress(received: received, total: total))
        case .verifying:
            secondary(LocalModelsCopy.verifying)
        case .ready:
            secondary(row.runtimeFound ? LocalModelsCopy.ready(row, indexed: indexed) : LocalModelsCopy.noRuntime)
        case .failed(let message):
            Text(message).font(.system(size: M.descriptionSize.value)).foregroundStyle(Color(nsColor: .systemRed))
                .fixedSize(horizontal: false, vertical: true)
        case .absent:
            if !row.runtimeFound { secondary(LocalModelsCopy.noRuntime) } else { EmptyView() }
        }
    }

    /// An AppKit label, so scenarios read the status by its `settings-field-localModelStatus-<kind>` identifier.
    private func secondary(_ text: String) -> some View {
        SettingsLabel(text: text, field: "localModelStatus-\(row.kind.rawValue)", secondary: true)
    }

    @ViewBuilder private var action: some View {
        let field = "localModel-\(row.kind.rawValue)"
        switch row.stage {
        case .absent:
            ProminentButton(title: LocalModelsCopy.download(row.bytes), field: field) { send(.localModel(.download(row.kind))) }
        case .failed:
            ProminentButton(title: LocalModelsCopy.retry, field: field) { send(.localModel(.download(row.kind))) }
        case .downloading:
            ProminentButton(title: LocalModelsCopy.stop, field: field, prominent: false) { send(.localModel(.cancel(row.kind))) }
        case .verifying:
            EmptyView()
        case .ready:
            ProminentButton(title: LocalModelsCopy.remove, field: field, prominent: false) { send(.localModel(.remove(row.kind))) }
        }
    }
}

enum LocalModelsCopy {
    static let title = "On This Mac"
    static let intro = "Optional models that run on this Mac. What they read never leaves it, and every feature works "
        + "without them; with them, Brk finds tabs by meaning and answers small questions without asking an agent."
    static let retry = "Try Again"
    static let stop = "Stop"
    static let remove = "Remove"
    static let verifying = "Checking the download…"
    static let noRuntime = "This copy of Brk was built without the model runtime, so it cannot use this model."

    static func download(_ bytes: Int64) -> String { "Download (\(size(bytes)))" }

    static func choice(_ file: LocalModelFileChoice) -> String { "\(file.title), \(size(file.bytes))" }

    static func facts(_ row: LocalModelRow) -> String {
        var parts = ["\(size(row.bytes)) download", "about \(memory(row.residentMB)) of memory while in use", row.license, row.languages]
        if row.kind == .search { parts.append("indexes the titles and addresses of your tabs, history and archive on this Mac") }
        return parts.joined(separator: " · ")
    }

    static func progress(received: Int64, total: Int64) -> String { "\(size(received)) of \(size(total))" }

    static func ready(_ row: LocalModelRow, indexed: Int?) -> String {
        guard row.kind == .search else { return "Downloaded. Brk starts it when a feature needs it and stops it after 5 idle minutes." }
        guard let indexed else { return "Downloaded. Indexing…" }
        return "Downloaded. \(indexed.formatted()) \(indexed == 1 ? "item" : "items") indexed. Removing the model deletes the index."
    }

    /// Decimal units rounded as the model pages print them ("310 MB", "2.71 GB").
    static func size(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value >= 1e9 { return String(format: "%.2f GB", value / 1e9) }
        if value >= 1e6 { return String(format: "%.0f MB", value / 1e6) }
        return String(format: "%.0f KB", max(1, value / 1e3))
    }

    static func memory(_ megabytes: Int) -> String {
        megabytes >= 1_000 ? String(format: "%.1f GB", Double(megabytes) / 1_000) : "\(megabytes) MB"
    }
}
