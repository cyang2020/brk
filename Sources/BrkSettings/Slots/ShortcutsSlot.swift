import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// SLOT for F4 (command bar, menu, remapping): the Shortcuts pane's list under "Custom Shortcuts" (Arc:
/// `ShortcutsPane`: "Customized Shortcuts", "Default Shortcuts", the recorder, the priority picker with its three
/// subtitles, "Reset Shortcut to Default", "Remove Conflicting Shortcut", "Reset All Shortcuts", the
/// "is already in use by" lines). Replace the body; keep the signature, which the pane calls.
///
/// Contract:
/// - `context.settings.shortcuts` is the resolved table (`ShortcutRow`: action, title with `{app}`, menu, state,
///   source, priority); edits are `.settings(.shortcuts(.setChord | .setPriority | .reset | .resetAll))`.
/// - The pane closes on Cmd+W and Esc only when no view inside took the key first (`SettingsHost`
///   offers key equivalents to its subviews before it closes), so a recorder that is listening can take both.
/// - Rows carry `settings-field-shortcut-<action>`; the reset-all button `settings-field-resetAllShortcuts`.
///
/// F1's first pass: the rows, customized ones first, each with its chord or conflict line, a per-row reset and
/// Reset All.
struct ShortcutsSlot: View {
    let context: PaneContext

    private var S: SettingsMetrics { Metrics.settings }

    var body: some View {
        let rows = context.settings.shortcuts
        let customized = rows.filter { $0.source == .userDefined }
        VStack(alignment: .leading, spacing: S.rowSpacing.value) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: S.rowSpacing.value) {
                    if !customized.isEmpty {
                        Text(SettingsCopy.customizedShortcuts).font(.subheadline.weight(.semibold))
                        ForEach(customized, id: \.action) { row($0) }
                    }
                    Text(SettingsCopy.defaultShortcuts).font(.subheadline.weight(.semibold))
                    ForEach(rows.filter { $0.source == .default }, id: \.action) { row($0) }
                }
                .padding(.trailing, S.columnSpacing.value)
            }
            .frame(height: S.shortcutsListHeight.value)
            SettingsButton(title: SettingsCopy.resetAllShortcuts, field: "resetAllShortcuts") {
                context.dispatch(.settings(.shortcuts(.resetAll)))
            }
            .disabled(customized.isEmpty)
        }
    }

    private func row(_ row: ShortcutRow) -> some View {
        HStack(spacing: S.columnSpacing.value) {
            Text(row.title.replacingOccurrences(of: "{app}", with: Product.name))
            Spacer(minLength: S.columnSpacing.value)
            Text(SettingsCopy.state(row.state)).foregroundStyle(row.source == .userDefined ? .primary : .secondary)
            if row.source == .userDefined {
                SettingsButton(title: SettingsCopy.resetShortcut, field: "shortcut-\(row.action.rawValue)-reset", symbol: "arrow.counterclockwise") {
                    context.dispatch(.settings(.shortcuts(.reset(row.action))))
                }
            }
        }
        .background(IdentifiedRegion(id: .settingsField("shortcut-\(row.action.rawValue)")))
    }
}
