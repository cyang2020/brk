import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// SLOT for F3 (windows and external links): Air Traffic Control's route editor inside the Links pane (Arc:
/// `LinkRoutingDialog`: a host pattern per route, `arrow.turn.down.right` to its destination, `minus.circle.fill`
/// to remove it, "Most Recent Space"). Replace the body; keep the signature, which the pane calls.
///
/// Contract:
/// - `context.settings.routes` are the routes in priority order with their destination's title;
///   `context.settings.spaces` are the spaces a route can name; `context.settings.links.defaultRoute` is where a
///   link with no matching route lands (nil: Most Recent Space).
/// - Edits are `.settings(.links(.addRoute | .updateRoute | .removeRoute | .moveRoute | .defaultRoute))`; the view
///   mints a new route's id. Validation is the reducer's (Rules/Settings.swift).
/// - Field names, which `SettingsHostTests.testTheLinksPaneEditsAirTrafficControlRoutes` drives:
///   `route-<id>-pattern`, `route-<id>-destination`, `route-<id>-up`, `route-<id>-down`, `route-<id>-remove`,
///   `route-new-pattern`, `route-new-destination`, `route-add`, `defaultRoute`.
///
/// F1's first pass: every route as a pattern field over its destination, with move and remove buttons; a row to add
/// one; where other links open.
struct LinksRoutesSlot: View {
    let context: PaneContext
    @State private var draftPattern = ""
    @State private var draftDestination: LinkDestination = .mostRecentSpace

    private var S: SettingsMetrics { Metrics.settings }
    private func send(_ setting: LinkSetting) { context.dispatch(.settings(.links(setting))) }

    /// Every place a route can send a link: Most Recent Space, Little Arc, then each space.
    private var destinations: [PopUpEntry<LinkDestination>] {
        [.option(SettingsCopy.mostRecentSpace, .mostRecentSpace), .option(SettingsCopy.littleArc, .littleArc), .separator]
            + context.settings.spaces.map { .option($0.title, .space($0.id)) }
    }

    var body: some View {
        let routes = context.settings.routes
        VStack(alignment: .leading, spacing: S.rowSpacing.value) {
            if routes.isEmpty {
                SettingsNote(text: SettingsCopy.noRoutes)
            }
            ForEach(Array(routes.enumerated()), id: \.element.route.id) { index, row in
                routeRow(row.route, index: index, count: routes.count)
            }
            VStack(alignment: .leading, spacing: S.rowSpacing.value) {
                SettingsTextField(field: "route-new-pattern", text: draftPattern, placeholder: SettingsCopy.routePatternPlaceholder) { draftPattern = $0 }
                    .frame(width: S.routePatternWidth.value)
                HStack(spacing: S.columnSpacing.value) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                    SettingsPopUp(field: "route-new-destination", entries: destinations, selected: draftDestination) { draftDestination = $0 }
                        .frame(width: S.popUpWidth.value)
                    SettingsButton(title: SettingsCopy.addRoute, field: "route-add") { add() }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: S.columnSpacing.value) {
                Text(SettingsCopy.otherLinksOpenIn)
                SettingsPopUp(field: "defaultRoute", entries: destinations, selected: context.settings.links.defaultRoute ?? .mostRecentSpace) {
                    send(.defaultRoute($0 == .mostRecentSpace ? nil : $0))
                }
                .frame(width: S.popUpWidth.value)
            }
        }
    }

    private func routeRow(_ route: LinkRoute, index: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: S.rowSpacing.value) {
            HStack(spacing: S.columnSpacing.value) {
                SettingsTextField(field: "route-\(route.id)-pattern", text: route.pattern, placeholder: SettingsCopy.routePatternPlaceholder) { pattern in
                    var changed = route
                    changed.pattern = pattern
                    send(.updateRoute(changed))
                }
                .frame(width: S.routePatternWidth.value)
                SettingsButton(title: SettingsCopy.removeRoute, field: "route-\(route.id)-remove", symbol: "minus.circle.fill") { send(.removeRoute(route.id)) }
            }
            HStack(spacing: S.columnSpacing.value) {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                SettingsPopUp(field: "route-\(route.id)-destination", entries: destinations, selected: route.destination) { destination in
                    var changed = route
                    changed.destination = destination
                    send(.updateRoute(changed))
                }
                .frame(width: S.popUpWidth.value)
                if index > 0 {
                    SettingsButton(title: SettingsCopy.moveRouteUp, field: "route-\(route.id)-up", symbol: "chevron.up") {
                        send(.moveRoute(route.id, index: index - 1))
                    }
                }
                if index < count - 1 {
                    SettingsButton(title: SettingsCopy.moveRouteDown, field: "route-\(route.id)-down", symbol: "chevron.down") {
                        send(.moveRoute(route.id, index: index + 1))
                    }
                }
            }
        }
    }

    private func add() {
        let pattern = draftPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        send(.addRoute(LinkRoute(id: LinkRouteID(UUID().uuidString), pattern: pattern, destination: draftDestination)))
        draftPattern = ""
    }
}
