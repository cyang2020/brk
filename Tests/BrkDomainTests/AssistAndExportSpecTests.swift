import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Owner: wave 2 contract (the AI seam and the export codec); a later wave fills the Max features.
final class AssistAndExportSpecTests: XCTestCase {

    /// with 'renamed pinned tabs' on, pinning asks the provider; the answer becomes the tab's custom title; an unknown request is ignored
    func test_pinningAsksForATidyTitleAndTheAnswerRenames() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.page(a, .titleChanged("Fixture Home - the very long page title of a fixture"))
        d.user(.settings(.max(.renamePinnedTabs(true))))
        let t = d.user(.tab(.togglePin(.item(a))))
        guard case .ai(let id, let task, let choice)? = t.effects.first else { return XCTFail("\(t.effects)") }
        XCTAssertEqual(choice, .auto)
        XCTAssertEqual(task, .renameTab(a, title: "Fixture Home - the very long page title of a fixture", url: start))
        assertUnchanged(d.state, d.system(.aiResult(AIRequestID("ghost"), .text("x"))))
        d.system(.aiResult(id, .reply(.text("Fixture Home\nignored second line"))))
        XCTAssertEqual(d.row(a)?.title, "Fixture Home")
        assertUnchanged(d.state, d.system(.aiResult(id, .reply(.text("again")))))
        d.user(.tab(.togglePin(.item(a))))
        let again = d.user(.tab(.togglePin(.item(a))))
        XCTAssertEqual(again.effects, [], "a tab with a custom title is not renamed again")
    }

    /// "Share…" builds an export document from state: a space with its folders, the focused tab, chosen items
    func test_exportDocumentsComeFromState() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.page(a, .titleChanged("Home"))
        d.user(.item(.newFolder))
        let folder = d.pinnedIDs[0]
        d.user(.item(.rename(folder, title: "Reading")))
        let b = d.open("http://127.0.0.1:9/b")
        d.user(.item(.move(b, to: .into(parent: folder, index: 0))))
        let space = d.user(.app(.export(.space(.current))))
        guard case .export(let document, _)? = space.effects.first else { return XCTFail("\(space.effects)") }
        XCTAssertEqual(document.title, "Space 1")
        XCTAssertEqual(document.entries, [.folder(title: "Reading", children: [.link(title: "127.0.0.1:9/b", url: url("http://127.0.0.1:9/b"))]),
                                          .link(title: "Home", url: start)])
        let tab = d.user(.app(.export(.focusedTab)))
        guard case .export(let one, _)? = tab.effects.first else { return XCTFail("\(tab.effects)") }
        XCTAssertEqual(one.entries, [.link(title: "127.0.0.1:9/b", url: url("http://127.0.0.1:9/b"))])
        XCTAssertEqual(d.user(.app(.export(.items([ItemID("ghost")])))).effects, [])
    }

    /// the export codec writes JSON with sorted keys and a Netscape bookmark file every browser imports
    func test_exportCodecFormats() throws {
        let document = ExportDocument(title: "Work <1>", entries: [
            .folder(title: "Reading", children: [.link(title: "Swift & Co", url: url("https://swift.org/?a=1&b=2"))]),
            .link(title: "Home", url: url("https://example.com/")),
        ])
        let json = String(decoding: ExportCodec.encode(document, as: .json), as: UTF8.self)
        XCTAssertTrue(json.contains("\"title\" : \"Work <1>\""))
        XCTAssertTrue(json.contains("https://swift.org/?a=1&b=2"))
        let html = String(decoding: ExportCodec.encode(document, as: .html), as: UTF8.self)
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE NETSCAPE-Bookmark-file-1>"))
        XCTAssertTrue(html.contains("<H3>Reading</H3>"))
        XCTAssertTrue(html.contains("<A HREF=\"https://swift.org/?a=1&amp;b=2\">Swift &amp; Co</A>"))
        XCTAssertTrue(html.contains("<TITLE>Work &lt;1&gt;</TITLE>"))
        XCTAssertEqual(ExportCodec.filename(document, as: .html), "Work -1-.html", "angle brackets are unsafe in file names")
        XCTAssertEqual(ExportCodec.filename(ExportDocument(title: "a/b:c", entries: []), as: .json), "a-b-c.json")
    }

}
