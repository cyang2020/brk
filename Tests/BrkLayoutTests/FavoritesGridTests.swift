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

    /// Every tile is 47 tall; a full row reaches the tray's 8 pt inset on both sides; an incomplete last row keeps the
    /// same tile width and starts at the left; rows are 55 apart; the tray holds them with 8 above and below.
    func testTilesFillTheirRow() {
        for width in [164.0, 166, 200, 228, 500] {
            for count in 1...12 {
                let grid = FavoritesGrid.tiles(count: count, width: width)
                let columns = FavoritesGrid.columns(count: count, width: width), rows = FavoritesGrid.rows(count: count, width: width)
                XCTAssertEqual(grid.tiles.count, count)
                XCTAssertEqual(grid.tray.width, width)
                XCTAssertEqual(grid.tray.height, 16 + Double(rows) * 47 + Double(rows - 1) * 8, "\(count) at \(width)")
                for (i, tile) in grid.tiles.enumerated() {
                    XCTAssertEqual(tile.height, 47)
                    XCTAssertEqual(tile.width, grid.tiles[0].width, accuracy: 1e-9)
                    XCTAssertEqual(tile.minY, 8 + Double(i / columns) * 55, "\(count) at \(width), tile \(i)")
                    if i % columns == 0 { XCTAssertEqual(tile.minX, 8, "\(count) at \(width), tile \(i)") }
                    if i % columns == columns - 1 { XCTAssertEqual(tile.maxX, width - 8, accuracy: 1e-9, "\(count) at \(width), tile \(i)") }
                }
            }
        }
        // Arc's sizes: one tile 212 wide, two 102, three 65.33, four 47 at 228; 56 for three at 200; 71 for two at 166.
        XCTAssertEqual(FavoritesGrid.tileSize(count: 1, width: 228), CGSize(width: 212, height: 47))
        XCTAssertEqual(FavoritesGrid.tileSize(count: 2, width: 228), CGSize(width: 102, height: 47))
        XCTAssertEqual(FavoritesGrid.tileSize(count: 3, width: 228).width, 196.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(FavoritesGrid.tileSize(count: 4, width: 228), CGSize(width: 47, height: 47))
        XCTAssertEqual(FavoritesGrid.tileSize(count: 5, width: 200), CGSize(width: 56, height: 47))
        XCTAssertEqual(FavoritesGrid.tileSize(count: 5, width: 166), CGSize(width: 71, height: 47))
    }

    /// The cell under the pointer, in the grid as it would be with the item: Q13-a and Q13-b (a fifth tile at 228).
    func testTheSlotIsTheCellUnderThePointer() {
        func slot(_ x: Double, _ y: Double, count: Int = 5, width: Double = 228) -> Int { FavoritesGrid.slot(at: CGPoint(x: x, y: y), count: count, width: width) }
        XCTAssertEqual(slot(114, 31), 1, "Q13-a: x 114 is the second of three")
        XCTAssertEqual(slot(196, 31), 2, "Q13-b: x 196 is the third")
        XCTAssertEqual(slot(30, 31), 0)
        XCTAssertEqual(slot(30, 86), 3, "the second row's first cell")
        XCTAssertEqual(slot(100, 86), 4)
        XCTAssertEqual(slot(200, 86), 4, "the empty end of the last row appends")
        XCTAssertEqual(slot(77, 31), 0, "half a gap belongs to each side")
        XCTAssertEqual(slot(78, 31), 1)
        XCTAssertEqual(slot(0, 0), 0, "outside the tiles counts as the nearest cell")
        XCTAssertEqual(slot(300, 300), 4)
        XCTAssertEqual(slot(0, 0, count: 0), 0)
        // Every cell's own middle falls in that cell, at every count and width.
        for width in [164.0, 166, 200, 228, 500] {
            for count in 1...12 {
                for (i, tile) in FavoritesGrid.tiles(count: count, width: width).tiles.enumerated() {
                    XCTAssertEqual(slot(tile.midX, tile.midY, count: count, width: width), i, "\(i) of \(count) at \(width)")
                }
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

    /// A favorite moved inside the grid: same cells, the others around the empty one (Q13-c: the first over the third).
    func testAFavoriteOverTheGridSlidesTheOthers() {
        let four = ids(4)
        let layout = FavoritesGrid.layout(four, width: 228, drag: .reordering(four[0], slot: 2))
        let cells = FavoritesGrid.tiles(count: 4, width: 228)
        XCTAssertEqual(layout.tray, cells.tray)
        XCTAssertEqual(layout.gap, cells.tiles[2])
        XCTAssertEqual(layout.tiles, [four[1]: cells.tiles[0], four[2]: cells.tiles[1], four[3]: cells.tiles[3]])
    }

    /// A favorite out of the grid: its cell is empty and the rest keep their size and place (Q13-d).
    func testAFavoriteOutOfTheGridLeavesItsCellEmpty() {
        let four = ids(4)
        let layout = FavoritesGrid.layout(four, width: 228, drag: .leaving(four[3]))
        let cells = FavoritesGrid.tiles(count: 4, width: 228)
        XCTAssertEqual(layout.tray, cells.tray)
        XCTAssertEqual(layout.gap, cells.tiles[3])
        XCTAssertEqual(layout.tiles, [four[0]: cells.tiles[0], four[1]: cells.tiles[1], four[2]: cells.tiles[2]])
        let rest = FavoritesGrid.layout(four, width: 228)
        XCTAssertEqual(rest.tiles, Dictionary(uniqueKeysWithValues: zip(four, cells.tiles)))
        XCTAssertNil(rest.gap)
    }
}
