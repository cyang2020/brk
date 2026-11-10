import BrkBase
import BrkDomain
import BrkLayout
import CoreGraphics
import XCTest

/// Arc's rules for the grid, as seen on Arc 1.170 on 2026-11-05 (verify/visual-pairs/run-20261103/Q13).
final class FavoritesGridTests: XCTestCase {
    private func ids(_ count: Int) -> [ItemID] { (0..<count).map { ItemID("t\($0)") } }

    /// The tiles per row, top to bottom.
    private func shape(count: Int, width: Double) -> [Int] {
        let tiles = FavoritesGrid.tiles(count: count, width: width).tiles
        return Dictionary(grouping: tiles, by: \.minY).sorted { $0.key < $1.key }.map(\.value.count)
    }

    /// Counts 0...12 at the widths Arc was checked at, and the widths on either side of a change in the most columns.
    func testEveryCountAtEveryWidthBalancesLikeArc() {
        let table: [Double: [[Int]]] = [
            228: [[], [1], [2], [3], [4], [3, 2], [3, 3], [4, 3], [4, 4], [3, 3, 3], [4, 4, 2], [4, 4, 3], [4, 4, 4]],
            500: [[], [1], [2], [3], [4], [3, 2], [3, 3], [4, 3], [4, 4], [3, 3, 3], [4, 4, 2], [4, 4, 3], [4, 4, 4]],
            200: [[], [1], [2], [3], [2, 2], [3, 2], [3, 3], [3, 3, 1], [3, 3, 2], [3, 3, 3], [3, 3, 3, 1], [3, 3, 3, 2], [3, 3, 3, 3]],
            166: [[], [1], [2], [2, 1], [2, 2], [2, 2, 1], [2, 2, 2], [2, 2, 2, 1], [2, 2, 2, 2], [2, 2, 2, 2, 1], [2, 2, 2, 2, 2], [2, 2, 2, 2, 2, 1], [2, 2, 2, 2, 2, 2]],
            164: [[], [1], [2], [2, 1], [2, 2], [2, 2, 1], [2, 2, 2], [2, 2, 2, 1], [2, 2, 2, 2], [2, 2, 2, 2, 1], [2, 2, 2, 2, 2], [2, 2, 2, 2, 2, 1], [2, 2, 2, 2, 2, 2]],
        ]
        for (width, shapes) in table {
            for (count, expected) in shapes.enumerated() {
                XCTAssertEqual(shape(count: count, width: width), expected, "\(count) favorites at \(width)")
            }
        }
    }

    /// A tab held over four tiles: the grid is 3+2 at once with the empty cell under the pointer (Q13-a), and the tray
    /// takes the second row.
    func testATabOverTheGridMakesRoomForItself() {
        let four = ids(4)
        let layout = FavoritesGrid.layout(four, width: 228, drag: .incoming(slot: 1))
        let cells = FavoritesGrid.tiles(count: 5, width: 228)
        XCTAssertEqual(layout.tray, cells.tray)
        XCTAssertEqual(layout.gap, cells.tiles[1])
        XCTAssertEqual(layout.tiles, [four[0]: cells.tiles[0], four[1]: cells.tiles[2], four[2]: cells.tiles[3], four[3]: cells.tiles[4]])
        // The empty box stays while a tab is over it.
        let empty = FavoritesGrid.layout([], width: 228, drag: .incoming(slot: 0))
        XCTAssertEqual(empty.tray, FavoritesGrid.tiles(count: 0, width: 228).tray)
        XCTAssertNil(empty.gap)
    }
}
