import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class MediaSoundTests: XCTestCase {
    func testSoundSettingConsumesRealArchiveAndDeduplicatedDownloadEvents() throws {
        for enabled in [true, false] {
            let d = Driver()
            d.user(.settings(.advanced(.soundEffects(enabled))))
            let tab = d.todayIDs[0]
            let id = DownloadID("sound-download")
            d.download(tab, id, .receiving(TransferProgress(received: 0, total: 10)))
            let result = d.download(tab, id, .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/owned-sound.txt"), bytes: 10))))
            XCTAssertEqual(result.effects.contains(.sound(.downloadCompleted)), enabled)
            let duplicate = d.download(tab, id, .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/owned-sound.txt"), bytes: 10))))
            XCTAssertFalse(duplicate.effects.contains(.sound(.downloadCompleted)))
            let closed = d.user(.tab(.close(.focused)))
            XCTAssertEqual(closed.effects.contains(.sound(.tabsArchived)), enabled)
            let restored = Driver(file: d.savedFile)
            XCTAssertEqual(restored.snapshot.settings.advanced.soundEffects, enabled)
        }
    }
}
