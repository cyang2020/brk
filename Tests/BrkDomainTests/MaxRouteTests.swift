import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// What a person meets on the way to each Max feature (found by driving a real launch with real input, 2026-11-07,
/// 8dc9260d6a:verify/completion/max-ui-20261107): where a switch that is off is said to be, what Turn Off Max leaves, and what a
/// feature working in the background says when it fails or succeeds.
final class MaxRouteTests: XCTestCase {
    private func request(_ transition: Transition) throws -> (AIRequestID, AITask) {
        for case .ai(let id, let task, _) in transition.effects { return (id, task) }
        throw NSError(domain: "no request", code: 0)
    }
    private func allOn() -> Driver {
        let d = Driver()
        d.user(.settings(.max(.enable(true))))
        return d
    }

    /// Turn Off Max: no feature acts or offers itself, the switches read off (P38-b), Turn On Max brings the choices
    /// back. One switch turned on while Max is off turns Max on with that feature alone.
    func testTurnOffMaxStopsEveryFeatureAndASwitchTurnsItBackOn() throws {
        let d = allOn()
        while d.todayIDs.count < 7 { _ = d.open("https://example.com/\(d.todayIDs.count)") }
        XCTAssertTrue(d.view.space.today.canTidy)
        d.user(.settings(.max(.enable(false))))
        let max = d.snapshot.settings.max.settings
        XCTAssertFalse(max.isOn)
        XCTAssertFalse(d.view.space.today.canTidy, "Tidy is not offered while Max is off")
        XCTAssertFalse(AIFeature.allCases.contains { max.enabled($0) })
        XCTAssertTrue(AIFeature.allCases.allSatisfy { max.switched($0) }, "the choices are kept for Turn On Max")
        d.user(.assist(.organizeToday))
        XCTAssertEqual(d.view.tabTools.toast?.text, "Max is off. Turn it on in Settings → Max.")
        d.user(.settings(.max(.enable(true))))
        XCTAssertTrue(d.view.space.today.canTidy)
        XCTAssertTrue(AIFeature.allCases.allSatisfy { d.snapshot.settings.max.settings.enabled($0) })

        d.user(.settings(.max(.enable(false))))
        d.user(.settings(.max(.tidyTabs(true))))
        let only = d.snapshot.settings.max.settings
        XCTAssertTrue(only.isOn && only.tidyOn)
        XCTAssertFalse(only.titlesOn)
        XCTAssertFalse(AIFeature.allCases.contains { only.enabled($0) }, "only the switched feature came on")

        // Every switch off: Turn On Max turns them all on, or the button would do nothing.
        d.user(.settings(.max(.tidyTabs(false))))
        d.user(.settings(.max(.enable(false))))
        d.user(.settings(.max(.enable(true))))
        let all = d.snapshot.settings.max.settings
        XCTAssertTrue(all.tidyOn && all.titlesOn && AIFeature.allCases.allSatisfy(all.enabled))
    }

    /// Brk's own three are switched in Advanced → More Settings…: their notices say so and their link opens Advanced.
    /// A bar that only leads to a feature that is off does not open.
    func testAFeatureThatIsOffSaysWhereItsSwitchIs() throws {
        let d = allOn()
        d.user(.settings(.max(.feature(.translation, false))))
        d.user(.assist(.translate("English")))
        XCTAssertEqual(d.view.tabTools.toast?.text, "Enable Translate Pages in Settings → Advanced → More Settings…")
        XCTAssertEqual(d.view.tabTools.toast?.link, ToastLink(title: "Advanced Settings ↗", command: .settings(.openPane(.advanced))))

        d.user(.settings(.max(.feature(.askPage, false))))
        d.user(.assist(.open(.page)))
        XCTAssertNil(d.bar, "the Ask on Page bar did not open")
        XCTAssertEqual(d.view.ai?.text, "Enable Ask on Page in Settings → Advanced → More Settings…")

        d.user(.assist(.dismiss))
        d.user(.settings(.max(.feature(.browse, false))))
        d.user(.assist(.browse(question: "a question", sources: [URL(string: "https://example.com/")!])))
        XCTAssertEqual(d.view.ai?.text, "Enable Browse for Me in Settings → Advanced → More Settings…", "not the format hint")

        d.user(.settings(.max(.feature(.linkPreviews, false))))
        d.user(.settings(.max(.feature(.instantLinks, false))))
        d.user(.assist(.instant("weather")))
        XCTAssertEqual(d.view.tabTools.toast?.text, "Enable Instant Links in Settings → Max.")
        XCTAssertEqual(d.view.tabTools.toast?.link, ToastLink(title: "Max Preferences ↗", command: .settings(.openPane(.max))))
        XCTAssertEqual(AIFeature.linkPreviews.title, "5-Second Previews", "the pane's own name for the switch")
        XCTAssertEqual(AIFeature.downloadRename.title, "Tidy Downloads")
    }

    /// Tidy Downloads renames a finished download by itself; the window it came from says so and names the file. A
    /// failure says why there too.
    func testAnAutomaticDownloadRenameIsToldInItsWindow() throws {
        let d = allOn(), tab = try XCTUnwrap(d.current?.id), download = DownloadID("auto-download")
        d.download(tab, download, .receiving(TransferProgress(received: 0, total: nil)))
        let finished = d.download(tab, download, .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/scan_0001_FINAL.txt"), bytes: 8))))
        let (id, _) = try request(finished)
        d.system(.aiResult(id, .reply(.text("Travel report.txt"))))
        d.system(.aiDownloadRenamed(download, originalPath: "/tmp/scan_0001_FINAL.txt", newPath: "/tmp/Travel report.txt", error: nil))
        XCTAssertEqual(d.view.tabTools.toast?.text, "Download renamed to:")
        XCTAssertEqual(d.view.tabTools.toast?.subtitle, "Travel report.txt")

        let other = DownloadID("auto-download-2")
        d.download(tab, other, .receiving(TransferProgress(received: 0, total: nil)))
        let (second, _) = try request(d.download(tab, other, .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/b.txt"), bytes: 8)))))
        d.system(.aiResult(second, .unavailable))
        XCTAssertTrue(d.view.tabTools.toast?.text.hasPrefix("Tidy Downloads: No selected local AI tool") == true, "\(String(describing: d.view.tabTools.toast?.text))")
    }

    /// Instant Links keeps Arc's "Oops, something went wrong." row; what went wrong goes in a notice beside it.
    func testInstantLinksSaysWhyItFailed() throws {
        let d = allOn()
        let (id, _) = try request(d.user(.assist(.instant("weather in paris"))))
        d.system(.aiResult(id, .failed("Gemini is not signed in. Run gemini in Terminal to sign in, then try again.")))
        guard case .tab(let row)? = d.view.space.today.rows.first else { return XCTFail("no row") }
        XCTAssertEqual(row.title, AICopy.instantFailed)
        XCTAssertEqual(d.view.tabTools.toast?.text, "Instant Links: Gemini is not signed in. Run gemini in Terminal to sign in, then try again.")
    }
}
