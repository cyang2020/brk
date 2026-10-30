import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// SLOT for F2 (profiles): the profile list at the top of the Profiles pane (Arc: "Profiles help keep your data
/// separate…" list, "Rename your Profile", "Delete this Profile", "Delete unused", "Create a new Profile"; the
/// ProfilePicker colors). Replace the body; keep the signature, which the pane calls.
///
/// Contract:
/// - `context.settings.profiles` is the list, default first (`ProfileSettingsRow.profile` has the name, icon, the
///   titles of its spaces and `isDefault`); `context.dispatch` sends `.profile(...)` commands.
/// - `selection` is the profile whose settings the pane shows under the list (auto-archive, search engine,
///   suggestions, download location: F1's `ProfileSettingsForm`). Set it when the user picks a profile.
/// - Clickable rows carry `settings-field-profile-<id>` (`ViewID.settingsField("profile-\(id)")`).
///
/// F1's first pass: one pill per profile with its space count (Arc's ProfilePicker); a click picks it.
struct ProfilesListSlot: View {
    let context: PaneContext
    @Binding var selection: ProfileID

    private var S: SettingsMetrics { Metrics.settings }

    var body: some View {
        HStack(spacing: S.profilePillSpacing.value) {
            ForEach(context.settings.profiles, id: \.profile.id) { row in
                let picked = row.profile.id == selection
                Button { selection = row.profile.id } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.profile.name).foregroundStyle(picked ? .primary : .secondary)
                        Text(SettingsCopy.spaceCount(row.profile.spaceTitles.count)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, S.profilePillPadding.value.width)
                    .padding(.vertical, S.profilePillPadding.value.height)
                    .background(RoundedRectangle(cornerRadius: S.profilePillCornerRadius.value, style: .continuous)
                        .fill(picked ? Color(nsColor: .quaternaryLabelColor) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(IdentifiedRegion(id: .settingsField("profile-\(row.profile.id)"), label: row.profile.name))
            }
        }
    }
}
