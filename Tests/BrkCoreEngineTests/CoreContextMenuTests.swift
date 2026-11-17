import XCTest
@testable import BrkCoreEngine

@MainActor
final class CoreContextMenuTests: XCTestCase {
    /// Chromium titles its rows in the macOS language (issue #14): a Chinese link menu keeps Chrome's link rows and gets Brk's.
    func testLinkMenuInAnotherLanguageKeepsItsRows() {
        let raw: [[String: Any]] = [
            ["title": "在新标签页中打开链接", "command": 50_100, "enabled": true],
            ["title": "在新窗口中打开链接", "command": 50_101, "enabled": true],
            ["separator": true],
            ["title": "复制链接地址", "command": 50_104, "enabled": true],
            ["title": "为此页面创建二维码", "command": 51_034, "enabled": true],
            ["title": "返回", "command": 33_000, "enabled": true],
        ]
        let shown = CoreContextMenu.shown(raw, link: true, translateTo: nil)
        XCTAssertEqual(shown.map(\.command), [50_100, 50_101, CoreContextMenu.splitLinkCommand, CoreContextMenu.littleLinkCommand, -1, 50_104])
    }
}
