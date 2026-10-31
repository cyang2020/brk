import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class MediaSoundTests: XCTestCase {
    func testArchiveAtRetentionCapacityStillEmitsItsAcceptedEventSound() throws {
        let d = Driver()
        d.user(.tab(.close(.focused)))
        let template = try XCTUnwrap(d.state.doc.archive.first)
        d.open("https://example.com/capacity")
        var state = d.state
        let cap = Metrics.persistence.archiveCap.value
        state.doc.archive = (0..<cap).map { n in
            ArchivedTab(id: ArchiveID("retained-\(n)"), tabID: ItemID("old-\(n)"), tab: template.tab,
                        archivedAt: template.archivedAt, reason: template.reason, fromSpace: template.fromSpace, fromSection: template.fromSection)
        }
        let result = reduce(state, .user(d.window, .tab(.close(.focused))), d.ctx)
        XCTAssertEqual(result.state.doc.archive.count, cap)
        XCTAssertTrue(result.effects.contains(.sound(.tabsArchived)))
    }

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
