import BrkBase
import XCTest
@testable import BrkDomain

final class IndependentSplitReviewTests: XCTestCase {
    func four(_ d: Driver) {
        for n in 2...4 { d.user(.split(.addPane)); d.user(.commandBar(.submit("https://test.example/\(n)"))); d.commitRequested() }
    }
    func ready(_ d: Driver) {
        for spec in d.snapshot.pages {
            let browser = d.snapshot.observations[spec.id]!.browser!
            let doc = DocumentToken(browser: browser, sequence: 7)
            d.system(.page(browser, .documentChanged(.loading(doc))))
            d.system(.page(browser, .documentChanged(.ready(doc))))
        }
    }
    func testSeparateAllPreservesAllSlotsDocumentsAndHiddenSpaceSelectionMatrix() throws {
        for pin in [false, true] { for selected in 0..<4 { for hidden in [false, true] {
            let d = Driver(); four(d)
            let panes = d.paneIDs, space = d.view.space.id
            if pin { d.user(.tab(.togglePin(.focused))) }
            d.user(.window(.new)); let other = d.snapshot.windows.keys.first { $0 != d.window }!
            d.user(.tab(.focus(panes[selected])), in: other)
            for (i, pane) in panes.enumerated() { d.page(pane, .committed(url("https://other.example/\(i)")), in: other) }
            ready(d)
            if hidden {
                let newSpace = d.newSpace("Away")
                d.user(.space(.focus(newSpace)), in: other)
                d.user(.space(.focus(space)))
            }
            let observations = d.snapshot.observations, pages = d.snapshot.pages
            let t = d.user(.split(.separateAll))
            XCTAssertEqual(d.snapshot.observations, observations)
            let priorVisibility = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0.websitePolicy.visible) })
            let requests = d.snapshot.pages.map { value -> PageSpec in
                var value = value
                value.websitePolicy.visible = priorVisibility[value.id] ?? false
                return value
            }
            XCTAssertEqual(requests, pages, "Separation retains requests and ownership; visibility follows the resulting panes")
            let visible = Set(d.snapshot.windows.values.flatMap { window in
                window.content.presentedPanes.compactMap { pane -> PageID? in
                    if case .page(let id) = pane.content { return id }; return nil
                }
            })
            XCTAssertEqual(Set(d.snapshot.pages.filter { $0.websitePolicy.visible }.map(\.id)), visible)
            XCTAssertTrue(t.effects.isEmpty)
            if hidden { d.user(.space(.focus(space)), in: other) }
            XCTAssertEqual(d.view(of: other).content.panes.map(\.tab), [panes[selected]])
            XCTAssertEqual(pin ? d.pinnedIDs : d.todayIDs, panes)
            let restored = Driver(file: d.savedFile)
            XCTAssertEqual(restored.view(of: other).content.panes.map(\.tab), [panes[selected]])
            for (i, pane) in panes.enumerated() {
                XCTAssertEqual(restored.state.address(of: pane, in: other, for: .savedDocument), url("https://other.example/\(i)"))
            }
        } } }
    }
    func testSeparateOnePreservesOtherWindowSelectedPaneForEveryPair() throws {
        for removed in 0..<4 { for selected in 0..<4 {
            let d = Driver(); four(d); let panes = d.paneIDs
            d.user(.window(.new)); let other = d.snapshot.windows.keys.first { $0 != d.window }!
            d.user(.tab(.focus(panes[selected])), in: other)
            ready(d)
            let observations = d.snapshot.observations
            d.user(.split(.separatePane(.item(panes[removed]))))
            XCTAssertEqual(d.snapshot.observations, observations)
            XCTAssertEqual(d.view(of: other).content.panes.first(where: \.focused)?.tab, panes[selected])
            XCTAssertEqual(d.paneIDs, [panes[removed]])
        } }
    }
    func testDropsPreserveSourceAndTargetSelectionsAcrossWindowsAndDocuments() throws {
        for edge in SplitEdge.allCases { for sourceSelected in [true, false] {
            let d = Driver(); let target=d.paneIDs[0], source=d.open("https://source.example/")
            d.user(.window(.new)); let other=d.snapshot.windows.keys.first { $0 != d.window }!
            let selected=sourceSelected ? source : target
            d.user(.tab(.focus(selected)), in: other)
            d.page(selected, .committed(url("https://other.example/local")), in: other)
            d.user(.tab(.focus(target))); ready(d)
            let offer=try XCTUnwrap(d.view.content.drop?.offers[source]); let obs=d.snapshot.observations
            d.user(.split(.dropTab(offer, edge: edge)))
            for (page, observation) in obs { XCTAssertEqual(d.snapshot.observations[page], observation) }
            XCTAssertEqual(d.view(of: other).content.panes.first(where: \.focused)?.tab, selected)
            XCTAssertEqual(d.state.address(of: selected, in: other, for: .savedDocument),url("https://other.example/local"))
            XCTAssertEqual(d.paneIDs,edge.isLeading ? [source,target] : [target,source])
        } }
    }
    func testPinnedCloseDoesNotDestroyOtherWindowExplicitDocument() throws {
        let d=Driver(); four(d); let panes=d.paneIDs
        d.user(.tab(.togglePin(.focused)))
        d.user(.window(.new)); let other=d.snapshot.windows.keys.first { $0 != d.window }!
        d.user(.tab(.focus(panes[3])), in: other)
        d.page(panes[3], .committed(url("https://other.example/retained")), in: other)
        d.user(.split(.closePane))
        XCTAssertNotNil(d.state.tab(panes[3]))
        XCTAssertEqual(d.state.address(of: panes[3], in: other, for: .savedDocument),url("https://other.example/retained"))
        XCTAssertEqual(Driver(file:d.savedFile).state.address(of:panes[3], in:other,for:.savedDocument),url("https://other.example/retained"))
    }
    func testForgedDropCannotCrossSpaceProfileOrPrivateOwnership() throws {
        let d=Driver(); let target=d.paneIDs[0], source=d.open("https://source.example/")
        d.user(.tab(.focus(target))); let valid=try XCTUnwrap(d.view.content.drop?.offers[source])
        let away=d.newSpace("Away"); let alien=d.open("https://alien.example/")
        d.user(.tab(.focus(target)))
        let tree=d.state.tree(of:d.window)!
        let forged=SplitDropOffer(window:d.window,source:alien,target:target,sourceParent:tree[alien]!.parent!,targetParent:valid.targetParent,panes:valid.panes,orientation:valid.orientation,context:valid.context)
        assertUnchanged(d.state,d.user(.split(.dropTab(forged,edge:.left))))
        d.user(.window(.newIncognito)); let owner=d.snapshot.windows.values.first { $0.kind == .incognito }!.id
        d.user(.commandBar(.submit("https://private.example/one")),in:owner)
        d.user(.commandBar(.open(.newTab)),in:owner); d.user(.commandBar(.submit("https://private.example/two")),in:owner)
        let privates=d.state.tree(of:owner)!.allTabs()
        d.user(.tab(.focus(privates[0])),in:owner)
        let privateOffer=try XCTUnwrap(d.view(of:owner).content.drop?.offers[privates[1]])
        assertUnchanged(d.state,d.user(.split(.dropTab(privateOffer,edge:.left))))
        d.user(.split(.dropTab(privateOffer,edge:.left)),in:owner)
        XCTAssertEqual(d.view(of:owner).content.panes.count,2)
        XCTAssertFalse(String(decoding:d.savedFile,as:UTF8.self).contains("private.example"))
        XCTAssertEqual(d.state.role(of:alien)?.space,away)
    }
    func testOriginalDownloadOwnerAndLateCompletionSurviveSplitMutations() throws {
        let d=Driver(); four(d); let tab=d.paneIDs[0], page=PageID(window:d.window,item:d.paneIDs[0])
        ready(d)
        let owner=DownloadOwner(browser:d.snapshot.observations[page]!.browser!,context:ContextEpoch(context:.profile(.default),generation:1),policy:.default)
        let id=DownloadID("independent-split-transfer")
        let details=DownloadDetails(url:url("https://test.example/original-post"),suggestedName:"original.bin")
        d.system(.download(DownloadUpdate(id:id,owner:owner,details:details,revision:1,stage:.receiving(TransferProgress(received:4,total:10)))))
        let downloads=d.state.doc.downloads, obs=d.snapshot.observations[page]
        d.user(.tab(.focus(tab)))
        for command in [SplitCommand.toggleExpanded,.restore,.separatePane(.focused)] {
            let t=d.user(.split(command))
            XCTAssertTrue(t.effects.isEmpty)
            XCTAssertEqual(d.state.doc.downloads,downloads)
            XCTAssertEqual(d.snapshot.observations[page],obs)
        }
        let receipt=FileReceipt(url:URL(fileURLWithPath:"/tmp/independent-original.bin"),bytes:10)
        d.system(.download(DownloadUpdate(id:id,owner:owner,details:details,revision:2,stage:.terminal(.completed(receipt)))))
        XCTAssertEqual(d.state.doc.downloads.first?.id,id)
        XCTAssertEqual(d.state.doc.downloads.first?.state,.finished)
        XCTAssertEqual(d.snapshot.observations[page],obs)
    }
}
