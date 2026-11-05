import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// R5-6 (the user's report Q18): the Library takes the window's theme, Today's Clear says what it will archive, and the
/// current Favorite's rim takes its site icon's colors. Read off real window screenshots and the native view tree.
enum LibraryThemeScenarios {
    static let all = [
        Scenario("R56-LibraryNavy", "under Arc's navy preset each of the five Library pages shows the theme in its icon and list columns with light labels; the white theme keeps them near-white", cefOnly: "real window screenshots", libraryNavy),
        Scenario("R56-ClearLabel", "Today's Clear has the ↓ before the word while the current tab is pinned or a Favorite, and none while it is in Today; the word keeps its place", cefOnly: "native view tree", clearLabel),
        Scenario("R56-Rim", "the current Favorite's rim is red for a red site icon and grey for a black one", cefOnly: "real favicons in a real window", rim),
    ]

    private typealias S = SidebarReviewScenarios
    private typealias E = SidebarEvidenceScenarios

    private static let navy = SpaceTheme(colors: [ThemePresets.drab[8]], texture: .grain, intensity: 0.25, appearance: .auto)
    private static let white = SpaceTheme(colors: [ThemePresets.greyscale[0]], texture: .grain, intensity: 0.25, appearance: .auto)

    private static func mean(_ bytes: [UInt8]) -> [Double] {
        var sum = [0.0, 0.0, 0.0]
        for i in stride(from: 0, to: bytes.count, by: 4) { for c in 0..<3 { sum[c] += Double(bytes[i + c]) } }
        let n = max(1, Double(bytes.count / 4))
        return sum.map { $0 / n }
    }
    /// The mean of each pixel's three channels, for every pixel.
    private static func levels(_ bytes: [UInt8]) -> [Double] {
        var out: [Double] = []
        var i = 0
        while i + 2 < bytes.count {
            let sum = Double(bytes[i]) + Double(bytes[i + 1]) + Double(bytes[i + 2])
            out.append(sum / 3)
            i += 4
        }
        return out
    }
    private static func brightest(_ bytes: [UInt8]) -> Double { levels(bytes).max() ?? 0 }
    private static func darkest(_ bytes: [UInt8]) -> Double { levels(bytes).min() ?? 0 }

    @Sendable static func libraryNavy(_ app: AppUnderTest) throws {
        let space = try app.view().space.id
        try app.dispatch(.space(.update(space, title: nil, icon: nil, theme: navy)))
        try app.waitUntil("the navy theme") { try app.view().theme.scheme == .dark }
        Thread.sleep(forTimeInterval: 0.6)
        let sidebarFrame = try visible(app.native(), .sidebar).frame
        let sidebar = mean(try S.pixels(app, "r56-sidebar", CGRect(x: 4, y: sidebarFrame.maxY - 120, width: 3, height: 40)))
        try expect(sidebar[2] > sidebar[0] + 20 && sidebar[0] < 170, "the navy sidebar reads \(sidebar)")
        for page in [LibraryPage.media, .downloads, .easelsAndNotes, .spaces, .archive] {
            try app.dispatch(.library(.open(page)))
            try app.waitUntil("the \(page) page") {
                if case .library(let library)? = try app.view().overlay { return library.page == page }
                return false
            }
            Thread.sleep(forTimeInterval: 0.5)
            let n = try app.native()
            let panel = try visible(n, .library).frame
            let nav = mean(try S.pixels(app, "r56-\(page)-nav", CGRect(x: 4, y: panel.maxY - 120, width: 3, height: 40)))
            guard let frames = n.computed.library else { throw Check(description: "no Library frames on \(page)") }
            let column = mean(try S.pixels(app, "r56-\(page)-column", CGRect(x: frames.page.minX + 2, y: panel.maxY - 40, width: 2, height: 20)))
            for (name, value) in [("icon column", nav), ("list column", column)] {
                for c in 0..<3 { try expect(abs(value[c] - sidebar[c]) < 22, "\(page): the \(name) reads \(value), the sidebar \(sidebar)") }
            }
            // Another page's label: light ink, nothing darker than the column.
            let other: LibraryPage = page == .downloads ? .media : .downloads
            let cell = try visible(n, .libraryPage(other)).frame
            let label = try S.pixels(app, "r56-\(page)-label", CGRect(x: cell.minX + 8, y: cell.maxY - 26, width: cell.width - 16, height: 16))
            try expect(brightest(label) > nav.reduce(0, +) / 3 + 50, "\(page): \(other)'s label is not light: brightest \(brightest(label)), column \(nav)")
            try expect(darkest(label) > nav.reduce(0, +) / 3 - 30, "\(page): \(other)'s label has dark ink: darkest \(darkest(label)), column \(nav)")
            // The open page's cell: a lighter block than the column.
            let open = try visible(n, .libraryPage(page)).frame
            let block = mean(try S.pixels(app, "r56-\(page)-cell", CGRect(x: open.minX + 6, y: open.midY - 20, width: 3, height: 12)))
            try expect(block[0] > nav[0] + 6, "\(page): the open cell reads \(block), the column \(nav)")
            try app.screenshot("r56-navy-\(page)")
        }
        try app.dispatch(.space(.update(space, title: nil, icon: nil, theme: white)))
        try app.waitUntil("the white theme") { try app.view().theme.scheme == .light }
        Thread.sleep(forTimeInterval: 0.6)
        let panel = try visible(app.native(), .library).frame
        let nav = mean(try S.pixels(app, "r56-white-nav", CGRect(x: 4, y: panel.maxY - 120, width: 3, height: 40)))
        try expect(nav.allSatisfy { $0 > 238 }, "under the white theme the icon column reads \(nav)")
    }

    @Sendable static func clearLabel(_ app: AppUnderTest) throws {
        let tile = try E.loadReady(app, "page2.html?fav=1")
        let pin = try E.loadReady(app, "page2.html?pin=1")
        let today = try E.loadReady(app, "page2.html?today=1")
        try app.dispatch(.item(.move(tile, to: .into(parent: try app.view().favorites.root, index: 0))))
        try app.dispatch(.item(.move(pin, to: .into(parent: try app.view().space.pinned.root, index: 0))))
        func frame(current: ItemID, _ name: String) throws -> CGRect {
            try app.dispatch(.tab(.focus(current)))
            try app.waitUntil("\(name) shown") { try E.shown(app.view()) == current }
            Thread.sleep(forTimeInterval: 0.3)
            return try visible(app.native(), .todayClear).frame
        }
        let inToday = try frame(current: today, "the Today tab")
        let pinned = try frame(current: pin, "the pinned tab")
        let favorite = try frame(current: tile, "the Favorite")
        let back = try frame(current: today, "the Today tab again")
        try expect(pinned.width > inToday.width + 10, "a pinned current tab: Clear is \(pinned.width) wide, \(inToday.width) in Today")
        try expect(abs(favorite.width - pinned.width) < 0.5, "a Favorite: Clear is \(favorite.width) wide, \(pinned.width) for a pinned tab")
        try expect(abs(pinned.maxX - inToday.maxX) < 0.5, "the word moved: \(pinned.maxX) against \(inToday.maxX)")
        try expect(abs(back.width - inToday.width) < 0.5, "back in Today Clear is \(back.width) wide, \(inToday.width) before")
    }

    @Sendable static func rim(_ app: AppUnderTest) throws {
        let red = try E.loadReady(app, "rim-red.html")
        let black = try E.loadReady(app, "rim-black.html")
        let root = try app.view().favorites.root
        try app.dispatch(.item(.move(red, to: .into(parent: root, index: 0))))
        try app.dispatch(.item(.move(black, to: .into(parent: root, index: 1))))
        func rimColor(_ tile: ItemID, _ name: String) throws -> [Double] {
            try app.dispatch(.tab(.focus(tile)))
            try app.waitUntil("\(name) shown") { try E.shown(app.view()) == tile }
            Thread.sleep(forTimeInterval: 1)
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            let frame = try visible(app.native(), .favorite(tile)).frame
            return mean(try S.pixels(app, "r56-rim-\(name)", CGRect(x: frame.midX - 10, y: frame.minY + 0.5, width: 20, height: 1)))
        }
        try app.waitUntil("the red icon loaded", timeout: 15) {
            try app.view().favorites.tiles.first { $0.id == red }?.favicon != nil
        }
        let redRim = try rimColor(red, "red")
        try expect(redRim[0] > redRim[1] + 60 && redRim[0] > redRim[2] + 60, "the red icon's rim reads \(redRim)")
        let blackRim = try rimColor(black, "black")
        try expect(abs(blackRim[0] - blackRim[1]) < 14 && abs(blackRim[1] - blackRim[2]) < 14, "the black icon's rim is not grey: \(blackRim)")
        try expect(blackRim[0] < 215, "the black icon's rim is too light: \(blackRim)")
        // The user's own case: a red icon under the navy theme, a red rim on a reddish fill (Q18-user-arc-sidebar.png).
        try app.dispatch(.space(.update(try app.view().space.id, title: nil, icon: nil, theme: navy)))
        try app.waitUntil("the navy theme") { try app.view().theme.scheme == .dark }
        Thread.sleep(forTimeInterval: 0.5)
        let navyRim = try rimColor(red, "red-navy")
        try expect(navyRim[0] > 190 && navyRim[1] < 150, "the red icon's rim under navy reads \(navyRim)")
        let tile = try visible(app.native(), .favorite(red)).frame
        let fill = mean(try S.pixels(app, "r56-rim-fill", CGRect(x: tile.minX + 5, y: tile.midY - 4, width: 3, height: 8)))
        try expect(fill[0] > fill[1] + 5, "the red icon's fill under navy is not reddish: \(fill)")
    }
}
