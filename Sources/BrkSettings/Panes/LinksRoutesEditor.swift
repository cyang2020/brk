import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: F3. Air Traffic Control inside the Links pane (anatomy-m 4.2 "Links", visual-and-copy.md "Air Traffic
/// Control"): the default destination for links from other apps, the routes in priority order (pattern, destination,
/// move up and down, remove) and a row that adds one. Every control dispatches a `.settings(.links(...))` command
/// and keeps no state of its own except the text being typed for a new route; the reducer normalizes the pattern
/// (`LinkRoute.normalizedPattern`) and refuses a destination naming a missing space, so what the list shows is what
/// `LinkRoute.matches` compares. F1's `SettingsHost` mounts it in the Links pane:
///
///     LinksRoutesEditor(routes: s.routes, spaces: s.spaces, links: s.links, dispatch: model.dispatch)
public struct LinksRoutesEditor: View {
    let routes: [LinkRouteRow]
    let spaces: [SpaceCandidate]
    let links: LinkSettings
    let dispatch: Dispatch
    @State private var newPattern = ""
    @State private var newDestination: LinkDestination = .mostRecentSpace

    public init(routes: [LinkRouteRow], spaces: [SpaceCandidate], links: LinkSettings, dispatch: @escaping Dispatch) {
        self.routes = routes
        self.spaces = spaces
        self.links = links
        self.dispatch = dispatch
    }

    public var body: some View {
        Section(LinksRoutesCopy.title) {
            Text(LinksRoutesCopy.explanation).font(.callout).foregroundStyle(.secondary)
            destinationPicker(LinksRoutesCopy.defaultDestination, selection: Binding(
                get: { links.defaultRoute ?? .mostRecentSpace },
                set: { dispatch(.settings(.links(.defaultRoute($0 == .mostRecentSpace ? nil : $0)))) }
            ))
            .accessibilityIdentifier(ViewID.settingsField("defaultRoute").identifier)
            ForEach(Array(routes.enumerated()), id: \.element.route.id) { index, row in
                routeRow(index: index, row: row)
            }
            HStack {
                TextField(LinksRoutesCopy.patternPlaceholder, text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .accessibilityIdentifier(ViewID.settingsField("route-add-pattern").identifier)
                destinationPicker("", selection: $newDestination)
                    .labelsHidden()
                    .accessibilityIdentifier(ViewID.settingsField("route-add-destination").identifier)
                Button(LinksRoutesCopy.add, action: add)
                    .disabled(LinkRoute.normalizedPattern(newPattern) == nil)
                    .accessibilityIdentifier(ViewID.settingsField("route-add").identifier)
            }
        }
    }

    private func routeRow(index: Int, row: LinkRouteRow) -> some View {
        HStack {
            TextField(LinksRoutesCopy.patternPlaceholder, text: Binding(
                get: { row.route.pattern },
                set: { text in
                    guard LinkRoute.normalizedPattern(text) != nil, text != row.route.pattern else { return }
                    dispatch(.settings(.links(.updateRoute(LinkRoute(id: row.route.id, pattern: text, destination: row.route.destination)))))
                }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier(ViewID.settingsField("route-\(row.route.id.rawValue)-pattern").identifier)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            destinationPicker("", selection: Binding(
                get: { row.route.destination },
                set: { dispatch(.settings(.links(.updateRoute(LinkRoute(id: row.route.id, pattern: row.route.pattern, destination: $0))))) }
            ))
            .labelsHidden()
            .accessibilityIdentifier(ViewID.settingsField("route-\(row.route.id.rawValue)-destination").identifier)
            Button { dispatch(.settings(.links(.moveRoute(row.route.id, index: index - 1)))) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
                .help(LinksRoutesCopy.moveUp)
            Button { dispatch(.settings(.links(.moveRoute(row.route.id, index: index + 1)))) } label: { Image(systemName: "chevron.down") }
                .disabled(index == routes.count - 1)
                .help(LinksRoutesCopy.moveDown)
            Button(role: .destructive) { dispatch(.settings(.links(.removeRoute(row.route.id)))) } label: { Image(systemName: "minus.circle") }
                .help(LinksRoutesCopy.remove)
                .accessibilityIdentifier(ViewID.settingsField("route-\(row.route.id.rawValue)-remove").identifier)
        }
        .buttonStyle(.borderless)
    }

    /// Every space in dock order, then Little Arc and Most Recent Space, as Arc's route destinations.
    private func destinationPicker(_ title: String, selection: Binding<LinkDestination>) -> some View {
        Picker(title, selection: selection) {
            ForEach(spaces, id: \.id) { space in Text(space.title).tag(LinkDestination.space(space.id)) }
            Divider()
            Text(LinksRoutesCopy.littleArc).tag(LinkDestination.littleArc)
            Text(LinksRoutesCopy.mostRecentSpace).tag(LinkDestination.mostRecentSpace)
        }
    }

    private func add() {
        guard LinkRoute.normalizedPattern(newPattern) != nil else { return }
        dispatch(.settings(.links(.addRoute(LinkRoute(id: LinkRouteID(UUID().uuidString), pattern: newPattern, destination: newDestination)))))
        newPattern = ""
    }
}

/// Arc's Air Traffic Control copy (visual-and-copy.md "Air Traffic Control", `bin:0x1039f8420`, `0x1039f8240`,
/// `0x1039f82d0`), with the app's name in place of Arc's.
public enum LinksRoutesCopy {
    public static let title = "Air Traffic Control"
    public static let explanation = "Routes let you choose where specific sites open inside \(Product.name). For example, you can route Spotify links to always open inside your Personal space."
    public static let defaultDestination = "Links from other apps open in"
    public static let patternPlaceholder = "spotify.com or *.spotify.com"
    public static let add = "Add Route"
    public static let remove = "Remove route"
    public static let moveUp = "Move up (matched earlier)"
    public static let moveDown = "Move down (matched later)"
    public static let littleArc = "Little Arc"
    public static let mostRecentSpace = "Most Recent Space"
}
