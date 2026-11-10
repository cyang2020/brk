import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: F3. Air Traffic Control as Arc 1.170 shows it (Q06-a, Arc's `LinkRoutingDialog`): a sheet over the Links
/// pane with the title, New Route and a close ×, one two-line row per route in priority order ("🔗 URL [Contains ▾]
/// [text] ⊖" over "↳ Open in [Space ▾]"), and under a hairline the Default destination for links from other apps.
/// Every control dispatches a `.settings(.links(...))` command and keeps no state of its own: New Route adds an empty
/// `.contains` route (it matches nothing until the user types), the reducer trims and normalizes the text
/// (`AppState.validRoute`) and refuses a destination naming a missing space, so what the sheet shows is what
/// `LinkRoute.matches` compares. Closing the sheet drops the routes still left empty.
struct AirTrafficControlSheet: View {
    let routes: [LinkRouteRow]
    let spaces: [SpaceCandidate]
    let links: LinkSettings
    let dispatch: Dispatch
    let close: @MainActor () -> Void

    private func send(_ setting: LinkSetting) { dispatch(.settings(.links(setting))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(LinksRoutesCopy.title).font(.system(size: CardMetrics.fontSize.value, weight: .semibold)).foregroundStyle(.primary)
                Spacer(minLength: 0)
                Text(LinksRoutesCopy.newRoute).font(SettingsStyle.font).foregroundStyle(.primary)
                    .frame(width: A.newRouteSize.value.width, height: A.newRouteSize.value.height)
                    .background(RoundedRectangle(cornerRadius: A.newRouteRadius.value, style: .continuous).fill(ArtColor.rgb(0xEAEAEF)))
                    .overlay(ClickArea(field: "route-new") {
                        send(.addRoute(LinkRoute(id: LinkRouteID(UUID().uuidString), pattern: "", destination: .mostRecentSpace, match: .contains)))
                    })
                Image(systemName: "xmark").font(.system(size: A.closeGlyph.value, weight: .regular)).foregroundStyle(ArtColor.rgb(0x4D5568))
                    .frame(width: A.closeSize.value, height: A.closeSize.value)
                    .overlay(ClickArea(field: "routes-close") { finish() })
                    .padding(.leading, A.newRouteToClose.value)
            }
            .frame(height: A.headerHeight.value)
            .padding(.leading, A.padding.value)
            .padding(.trailing, A.closeTrailing.value)
            .padding(.top, A.headerTop.value)
            .padding(.bottom, A.headerToRule.value)
            rule
            ScrollView {
                VStack(alignment: .leading, spacing: A.routeGap.value) {
                    ForEach(routes, id: \.route.id) { row in route(row.route) }
                }
                .padding(.top, A.routesTop.value)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            rule
            HStack(spacing: 0) {
                Text(LinksRoutesCopy.defaultDestination).font(SettingsStyle.font).foregroundStyle(SettingsStyle.text)
                    .frame(width: A.defaultLabelWidth.value, alignment: .leading)
                destinationPopUp(field: "defaultRoute", selected: links.externalDefault) { send(.defaultRoute($0)) }
                    .frame(width: A.destinationWidth.value)
                Spacer(minLength: 0)
            }
            .padding(.leading, A.defaultLeading.value)
            .frame(height: A.footerHeight.value)
            .padding(.bottom, A.footerBottom.value)
        }
        .frame(width: A.size.value.width, height: A.size.value.height, alignment: .topLeading)
        .background(ArtColor.rgb(0xFBFBFF))
        // Esc closes the sheet as × does.
        .background(Button("", action: finish).keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0))
        .background(IdentifiedRegion(id: .settingsField("airTrafficControlSheet")))
        .background(NoInitialFocus())
    }

    private var rule: some View {
        Rectangle().fill(ArtColor.rgb(0xE5E5E9)).frame(height: CardMetrics.borderWidth.value).padding(.horizontal, A.padding.value)
    }

    private func route(_ route: LinkRoute) -> some View {
        let id = route.id.rawValue
        func update(pattern: String? = nil, destination: LinkDestination? = nil, match: LinkMatch? = nil) {
            send(.updateRoute(LinkRoute(id: route.id, pattern: pattern ?? route.pattern, destination: destination ?? route.destination,
                                        match: match ?? route.match ?? .matches)))
        }
        return VStack(alignment: .leading, spacing: A.lineGap.value) {
            HStack(spacing: 0) {
                Image(systemName: "link").font(.system(size: A.symbolSize.value)).foregroundStyle(SettingsStyle.secondaryText)
                    .frame(width: A.symbolWidth.value)
                Text(LinksRoutesCopy.url).font(SettingsStyle.font).foregroundStyle(SettingsStyle.secondaryText)
                    .padding(.leading, A.symbolGap.value)
                SettingsPopUp(field: "route-\(id)-match", entries: LinkMatch.allCases.reversed().map { .option(LinksRoutesCopy.match($0), $0) },
                              selected: route.match ?? .matches) { update(match: $0) }
                    .frame(width: A.matchWidth.value)
                    .padding(.leading, A.labelToControl.value)
                SettingsTextField(field: "route-\(id)-pattern", text: route.pattern, placeholder: LinksRoutesCopy.patternPlaceholder,
                                  edit: { text in update(pattern: text) }) { text in update(pattern: text) }
                    .frame(width: A.patternWidth.value)
                    .padding(.leading, A.controlGap.value)
                Image(systemName: "minus.circle.fill").font(.system(size: A.removeSize.value)).foregroundStyle(ArtColor.rgb(0x88888B))
                    .overlay(ClickArea(field: "route-\(id)-remove") { send(.removeRoute(route.id)) })
                    .help(LinksRoutesCopy.remove)
                    .padding(.leading, A.controlGap.value)
            }
            .padding(.leading, A.routeLeading.value)
            HStack(spacing: 0) {
                Image(systemName: "arrow.turn.down.right").font(.system(size: A.symbolSize.value)).foregroundStyle(SettingsStyle.secondaryText)
                Text(LinksRoutesCopy.openIn).font(SettingsStyle.font).foregroundStyle(SettingsStyle.secondaryText)
                    .padding(.leading, A.arrowGap.value)
                destinationPopUp(field: "route-\(id)-destination", selected: route.destination) { update(destination: $0) }
                    .frame(width: A.destinationWidth.value)
                    .padding(.leading, A.labelToControl.value)
            }
            .padding(.leading, A.openInLeading.value)
        }
    }

    /// Every space in dock order, then Little Arc and Most Recent Space, as Arc's route destinations.
    private func destinationPopUp(field: String, selected: LinkDestination, choose: @escaping @MainActor (LinkDestination) -> Void) -> some View {
        var entries: [PopUpEntry<LinkDestination>] = spaces.map { .option($0.title, .space($0.id)) }
        if !entries.isEmpty { entries.append(.separator) }
        entries += [.option(LinksRoutesCopy.littleArc, .littleArc), .option(LinksRoutesCopy.mostRecentSpace, .mostRecentSpace)]
        return SettingsPopUp(field: field, entries: entries, selected: selected, choose: choose)
    }

    /// Close drops the rows New Route added that were never filled in.
    private func finish() {
        for row in routes where row.route.pattern.isEmpty { send(.removeRoute(row.route.id)) }
        close()
    }
}

/// Arc's sheet opens with nothing focused (Q06-a); left alone, AppKit would put the first text field in the key view
/// loop into editing. This empty view takes the first responder until the user clicks a field.
private struct NoInitialFocus: NSViewRepresentable {
    func makeNSView(context: NSViewRepresentableContext<Self>) -> Sink { Sink() }
    func updateNSView(_ view: Sink, context: NSViewRepresentableContext<Self>) {}

    final class Sink: NSView {
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.initialFirstResponder = self
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
    }
}

/// Arc's Air Traffic Control copy (visual-and-copy.md "Air Traffic Control", `bin:0x1039f8420`, `0x1039f8240`,
/// `0x1039f82d0`; Q06-a), with the app's name in place of Arc's.
public enum LinksRoutesCopy {
    public static let title = "Air Traffic Control"
    public static let explanation = "Routes let you choose where specific sites open inside \(Product.name). For example, you can route Spotify links to always open inside your Personal space."
    /// Observed (Q06-a).
    public static let newRoute = "New Route"
    public static let url = "URL"
    public static let openIn = "Open in"
    public static let defaultDestination = "Default"
    public static let patternPlaceholder = "meet.google.com"
    public static let remove = "Remove route"
    public static let littleArc = "Little Arc"
    public static let mostRecentSpace = "Most Recent Space"

    /// "Contains" is observed (Q06-a); "Matches" is Arc's other case name (`LinkRoutingURLMatchType.matches`).
    public static func match(_ match: LinkMatch) -> String {
        switch match {
        case .contains: "Contains"
        case .matches: "Matches"
        }
    }
}

private var A: AirTrafficControlMetricsTable { AirTrafficControlMetrics }

let AirTrafficControlMetrics = AirTrafficControlMetricsTable()

/// Measured on Arc 1.170's 2x capture of the sheet (sheet x 177 to 1191 px, y 177 to 1175 px), halved to points.
struct AirTrafficControlMetricsTable: MetricGroup {
    private static let capture = "scripts/station/arc-reference/Q06/Q06-a-arc.png"
    let size = Metric(CGSize(width: 508, height: 500), .anatomy("\(capture): the sheet spans x 177 to 1191 px, y 177 to 1175 px"))
    let padding = Metric(24.0, .anatomy("\(capture): the title starts at x 225 px; the hairlines span x 225 to 1143 px"))
    let headerTop = Metric(32.0, .anatomy("\(capture): New Route spans y 241 to 296 px"))
    let headerHeight = Metric(27.5, .anatomy("\(capture): New Route spans y 241 to 296 px; the title is centred at 269 px"))
    let headerToRule = Metric(23.5, .anatomy("\(capture): New Route ends at y 296 px, the hairline is at 343 px"))
    let newRouteSize = Metric(CGSize(width: 121.5, height: 27.5), .anatomy("\(capture): New Route spans x 788 to 1031 px, y 241 to 296 px"))
    let newRouteRadius = Metric(6.0, .anatomy("\(capture): New Route's corner curve spans about 12 px"))
    let newRouteToClose = Metric(30.0, .anatomy("\(capture): New Route ends at x 1031 px, the × box starts near 1091 px"))
    let closeSize = Metric(20.0, .anatomy("\(capture): the × spans x 1099 to 1124 px, centred at 1111 px"))
    let closeGlyph = Metric(16.0, .anatomy("\(capture): the × strokes span about 26 px"))
    let closeTrailing = Metric(30.5, .anatomy("\(capture): the × box ends near x 1131 px of a sheet ending at 1191 px"))
    let routesTop = Metric(24.0, .anatomy("\(capture): the hairline at y 343 px, the URL pop-up starts at 394 px"))
    let routeGap = Metric(16.0, .guess("space between two routes; the capture has one"))
    let lineGap = Metric(4.0, .anatomy("\(capture): the URL row's pop-up ends at y 441 px, the Open in pop-up starts at 450 px"))
    let routeLeading = Metric(56.5, .anatomy("\(capture): the link symbol starts at x 290 px"))
    let symbolWidth = Metric(14.0, .anatomy("\(capture): the link symbol spans x 290 to 318 px"))
    let symbolSize = Metric(13.0, .anatomy("\(capture): the link and arrow symbols are 28 px wide"))
    let symbolGap = Metric(6.0, .anatomy("\(capture): the link symbol ends at x 318 px, URL starts at 330 px"))
    let labelToControl = Metric(9.0, .anatomy("\(capture): URL ends at x 382 px, its pop-up starts at 400 px; Open in ends at 574 px, its pop-up starts at 591 px"))
    let matchWidth = Metric(110.0, .anatomy("\(capture): the Contains pop-up spans x 400 to 619 px"))
    let controlGap = Metric(8.0, .anatomy("\(capture): the pop-up ends at x 619 px, the text field starts at 635 px"))
    let patternWidth = Metric(211.0, .anatomy("\(capture): the text field spans x 635 to 1057 px"))
    let removeSize = Metric(13.0, .anatomy("\(capture): the ⊖ spans x 1074 to 1100 px"))
    let openInLeading = Metric(130.0, .anatomy("\(capture): the turn arrow starts at x 437 px"))
    let arrowGap = Metric(5.0, .anatomy("\(capture): the turn arrow ends at x 465 px, Open in starts at 475 px"))
    let destinationWidth = Metric(165.0, .anatomy("\(capture): the Open in and Default pop-ups span x 591 to 920 px and 505 to 834 px"))
    let footerHeight = Metric(73.0, .anatomy("\(capture): the hairline at y 995 px, Default centred at 1069 px"))
    let footerBottom = Metric(17.0, .anatomy("\(capture): Default centred at y 1069 px, the sheet ends at 1175 px"))
    let defaultLeading = Metric(59.5, .anatomy("\(capture): Default starts at x 296 px"))
    let defaultLabelWidth = Metric(104.5, .anatomy("\(capture): Default starts at x 296 px, its pop-up at 505 px"))
}
