import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Owner: F2. Profiles and incognito: records, per-profile Favorites and settings, a space's profile, the browsing
/// context of pages, the URL pill's badge, the dialogs.
final class ProfilesSpecTests: XCTestCase {
    func test_escapeClosesTheProfileDialogWithoutLeavingFullScreen() {
        let d = Driver()
        d.user(.profile(.openDialog(.create)))
        XCTAssertNotNil(d.view.profileDialog)

        let result = d.key(KeyChord([], .escape), stage: .menu, pressID: 1)

        XCTAssertNil(d.view.profileDialog)
        XCTAssertFalse(result.effects.contains(.window(d.window, .leaveFullScreen)))
    }

    /// .profile(.create) adds a profile with its own Favorites root and default settings; a duplicate or blank name is refused
    func test_createAddsAProfileWithFavoritesAndSettings() {
        let d = Driver()
        d.user(.profile(.create(name: "Work", icon: .named(.briefcase))))
        let rows = d.snapshot.settings.profiles
        XCTAssertEqual(rows.map(\.profile.name), ["Default", "Work"])
        let work = rows[1].profile.id
        XCTAssertEqual(rows[1].settings, .default)
        assertUnchanged(d.state, d.user(.profile(.create(name: " work ", icon: nil))))
        assertUnchanged(d.state, d.user(.profile(.create(name: "  ", icon: nil))))
        d.user(.profile(.assign(.current, to: work)))
        XCTAssertNotEqual(d.view.favorites.root, Driver().view.favorites.root, "the space shows its profile's Favorites root")
        XCTAssertEqual(d.view.urlPill.profile, ProfileBadge(name: "Work", icon: .named(.briefcase), incognito: false))
        let r = Driver(file: d.savedFile)
        XCTAssertEqual(r.snapshot.settings.profiles.map(\.profile.name), ["Default", "Work"])
        XCTAssertEqual(r.view.urlPill.profile?.name, "Work")
    }

    /// pages of a space browse in its profile's context; incognito windows browse off the record
    func test_pagesCarryTheirBrowsingContext() throws {
        let d = Driver()
        d.user(.profile(.create(name: "Work", icon: nil)))
        let work = try XCTUnwrap(d.snapshot.settings.profiles.last?.profile.id)
        d.user(.profile(.assign(.current, to: work)))
        let t = d.open("http://127.0.0.1:9/work")
        XCTAssertEqual(d.snapshot.pages.first { $0.id == PageID(window: d.window, item: t) }?.context, .profile(work))
        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito })
        d.user(.commandBar(.submit("http://127.0.0.1:9/secret")), in: incognito.id)
        let secret = try XCTUnwrap(d.view(of: incognito.id).scratch?.rows.first?.id)
        XCTAssertEqual(d.snapshot.pages.first { $0.id == PageID(window: incognito.id, item: secret) }?.context, .incognito(d.state.session.privateSession!))
        XCTAssertEqual(d.view(of: incognito.id).urlPill.profile, ProfileBadge(name: "Incognito", icon: nil, incognito: true))
        d.page(secret, .committed(url("http://127.0.0.1:9/secret")), in: incognito.id)
        XCTAssertFalse((d.savedDoc["history"] as? [[String: Any]] ?? []).contains { ($0["url"] as? String) == "http://127.0.0.1:9/secret" },
                       "incognito visits are never history")
    }

    /// .profile(.delete) is refused for the default profile and a profile with spaces; otherwise its Favorites are archived and the engine forgets it
    func test_deleteRules() throws {
        let d = Driver()
        assertUnchanged(d.state, d.user(.profile(.delete(.default))))
        d.user(.profile(.create(name: "Work", icon: nil)))
        let work = try XCTUnwrap(d.snapshot.settings.profiles.last?.profile.id)
        d.user(.profile(.assign(.current, to: work)))
        assertUnchanged(d.state, d.user(.profile(.delete(work))))
        d.user(.profile(.assign(.current, to: .default)))
        d.user(.profile(.rename(work, name: "Side")))
        XCTAssertEqual(d.snapshot.settings.profiles.last?.profile.name, "Side")
        let t = d.user(.profile(.delete(work)))
        guard case .disposeContext(let disposal)? = t.effects.first else { return XCTFail("missing disposal") }
        XCTAssertEqual(disposal.context, .profile(work))
        XCTAssertEqual(d.state.doc.deletingProfiles[work]?.id, disposal.id)
        d.system(.contextDisposed(.completed(disposal.id, disposal.context, .deletionScheduledForNextLaunch)))
        XCTAssertNil(d.state.doc.deletingProfiles[work])
        XCTAssertEqual(d.snapshot.settings.profiles.map(\.profile.id), [.default])
        XCTAssertEqual(Driver(file: d.savedFile).outcome, .restored(repairs: []))
    }

    /// closing the last incognito window asks the engine to forget the off-the-record context
    func test_closingTheLastIncognitoWindowForgetsTheContext() throws {
        let d = Driver()
        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito })
        let t = d.user(.window(.close), in: incognito.id)
        guard case .disposeContext(let disposal)? = t.effects.first, case .incognito = disposal.context else { return XCTFail("missing private disposal") }
        XCTAssertNil(d.state.session.privateSession)
        XCTAssertNil(d.snapshot.windows[incognito.id])
    }

    /// .profile(.assign) changes the context of the space's pages: off-screen loaded tabs are unloaded (they reopen
    /// in the new context when focused), the shown tab stays loaded and its spec names the new context (the engine
    /// replaces the page), tabs of other spaces keep theirs; assigning the same profile again changes nothing
    func test_changingASpacesProfileReopensItsPagesInTheNewContext() throws {
        let d = Driver()
        let first = d.view.space.id
        let behind = d.open("http://127.0.0.1:9/behind"), shown = d.open("http://127.0.0.1:9/shown")
        XCTAssertTrue(d.loadedIDs.isSuperset(of: [behind, shown]))
        d.newSpace("Other")
        let other = d.open("http://127.0.0.1:9/other")
        d.user(.profile(.create(name: "Work", icon: nil)))
        let work = try XCTUnwrap(d.snapshot.settings.profiles.last?.profile.id)
        d.user(.tab(.focus(shown)))
        XCTAssertEqual(d.view.space.id, first)
        func context(_ tab: ItemID) -> BrowsingContext? { d.snapshot.pages.first { $0.id == PageID(window: d.window, item: tab) }?.context }
        XCTAssertEqual(context(shown), .profile(.default))

        d.user(.profile(.assign(.current, to: work)))
        XCTAssertFalse(d.loadedIDs.contains(behind), "an off-screen tab of the space is unloaded")
        XCTAssertEqual(context(shown), .profile(work), "the shown tab's page is respecified in the new context")
        XCTAssertEqual(context(other), .profile(.default), "another space's tab keeps its page")
        XCTAssertEqual(d.view.urlPill.profile?.name, "Work")
        d.user(.tab(.focus(behind)))
        XCTAssertEqual(context(behind), .profile(work), "an unloaded tab reopens in the new context")
        assertUnchanged(d.state, d.user(.profile(.assign(.current, to: work))))
        assertUnchanged(d.state, d.user(.profile(.assign(.current, to: ProfileID("ghost")))))
    }

    /// an incognito window is session-only: its tab, visit and window are not in state.json and nothing of it is
    /// restored; its pages record no history (deleting a profile also drops its own history); the pill shows the
    /// incognito badge even over a space with another profile
    func test_incognitoWindowsRestoreNothingAndUseArcsIncognitoLook() throws {
        let d = Driver()
        d.user(.profile(.create(name: "Work", icon: nil)))
        let work = try XCTUnwrap(d.snapshot.settings.profiles.last?.profile.id)
        d.user(.profile(.assign(.current, to: work)))
        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        XCTAssertEqual(d.view(of: incognito).urlPill.profile, ProfileBadge(name: "Incognito", icon: nil, incognito: true))
        let secret = "http://127.0.0.1:9/secret-incognito"
        d.user(.commandBar(.submit(secret)), in: incognito)
        let tab = try XCTUnwrap(d.view(of: incognito).scratch?.rows.first?.id)
        d.page(tab, .committed(url(secret)))
        d.page(tab, .titleChanged("Secret"))
        XCTAssertEqual(d.view(of: incognito).scratch?.rows.count, 1)
        XCTAssertTrue(d.view(of: incognito).space.today.rows.isEmpty && d.view(of: incognito).favorites.tiles.isEmpty,
                      "the incognito sidebar shows only its own tabs")
        XCTAssertFalse(d.state.doc.history.contains { $0.url == url(secret) })

        let file = d.savedFile
        XCTAssertFalse(String(decoding: file, as: UTF8.self).contains("secret-incognito"), "nothing of the incognito tab is saved")
        XCTAssertEqual((d.savedDoc["windows"] as? [String: Any])?.keys.sorted(), [d.window.rawValue], "only the standard window is saved")
        let r = Driver(file: file)
        XCTAssertEqual(r.snapshot.windows.values.map(\.kind), [.standard])
        XCTAssertNil(r.view.scratch)

        let visit = d.open("http://127.0.0.1:9/work-visit")
        d.page(visit, .committed(url("http://127.0.0.1:9/work-visit")))
        XCTAssertTrue(d.state.doc.history.contains { $0.url == url("http://127.0.0.1:9/work-visit") && $0.profile == work })
        d.user(.profile(.assign(.current, to: .default)))
        d.user(.profile(.delete(work)))
        XCTAssertFalse(d.state.doc.history.contains { $0.profile == work }, "a deleted profile's history goes with it")
    }
}
