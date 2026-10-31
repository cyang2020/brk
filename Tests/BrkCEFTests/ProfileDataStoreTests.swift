import BrkBase
import CCef
import Foundation
import XCTest
@testable import BrkCEF

@MainActor
final class ProfileDataStoreTests: XCTestCase {
    func testDeletionIsAcknowledgedBeforeAFailedFlushAndDoesNotClaimDurability() async throws {
        let fixture = Fixture(flushSucceeds: false)
        let store = ProfileDataStore(context: fixture.makeContext())
        defer { store.release(); fixture.releaseManager() }
        var deleted = false
        do {
            try await store.clearCookies { deleted = true; fixture.events.append("acknowledged") }
            XCTFail("failed flush reported success")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("disk flush failed"))
        }
        XCTAssertTrue(deleted, "already-deleted cookies must appear in partial completion")
        XCTAssertEqual(fixture.events, ["initialize", "manager", "delete", "acknowledged", "flush"])
    }

    func testCookiesFlushAndCacheAwaitTheirOwnNativeCompletions() async throws {
        let fixture = Fixture(flushSucceeds: true)
        let store = ProfileDataStore(context: fixture.makeContext())
        defer { store.release(); fixture.releaseManager() }
        var acknowledgements = 0
        try await store.clearCookies { acknowledgements += 1 }
        try await store.clearCache()
        XCTAssertEqual(acknowledgements, 1)
        XCTAssertEqual(fixture.events, ["initialize", "manager", "delete", "flush", "cache"])
    }

    private final class Fixture {
        var events: [String] = []
        let flushSucceeds: Bool
        var manager: UnsafeMutablePointer<cef_cookie_manager_t>!
        init(flushSucceeds: Bool) { self.flushSucceeds = flushSucceeds }
        func makeContext() -> UnsafeMutablePointer<cef_request_context_t> {
            manager = Fixture.allocate(cef_cookie_manager_t.self, self)
            manager.pointee.delete_cookies = { object, url, name, callback in
                let fixture = Fixture.owner(object!)
                fixture.events.append("delete")
                XCTAssertNil(url); XCTAssertNil(name)
                if let callback { callback.pointee.on_complete?(callback, 3); Fixture.release(callback) }
                return 1
            }
            manager.pointee.flush_store = { object, callback in
                let fixture = Fixture.owner(object!); fixture.events.append("flush")
                if let callback {
                    if fixture.flushSucceeds { callback.pointee.on_complete?(callback) }
                    Fixture.release(callback)
                }
                return fixture.flushSucceeds ? 1 : 0
            }
            let context = Fixture.allocate(cef_request_context_t.self, self)
            context.pointee.get_cookie_manager = { object, callback in
                let fixture = Fixture.owner(object!)
                fixture.events.append(callback == nil ? "manager" : "initialize")
                let manager = fixture.manager!
                manager.pointee.base.add_ref?(&manager.pointee.base)
                if let callback { callback.pointee.on_complete?(callback); Fixture.release(callback) }
                return manager
            }
            context.pointee.clear_http_cache = { object, callback in
                Fixture.owner(object!).events.append("cache")
                if let callback { callback.pointee.on_complete?(callback); Fixture.release(callback) }
            }
            return context
        }
        func releaseManager() { Fixture.release(manager); manager = nil }
        static func owner<T>(_ object: UnsafeMutablePointer<T>) -> Fixture {
            Unmanaged<AnyObject>.fromOpaque(ccef_object_get_swift(object)!).takeUnretainedValue() as! Fixture
        }
        static func allocate<T>(_ type: T.Type, _ owner: Fixture) -> UnsafeMutablePointer<T> {
            let opaque = Unmanaged.passRetained(owner as AnyObject).toOpaque()
            return ccef_object_alloc(MemoryLayout<T>.stride, opaque, { value in
                if let value { Unmanaged<AnyObject>.fromOpaque(value).release() }
            })!.assumingMemoryBound(to: T.self)
        }
        static func release<T>(_ object: UnsafeMutablePointer<T>) {
            let base = UnsafeMutableRawPointer(object).assumingMemoryBound(to: cef_base_ref_counted_t.self)
            _ = base.pointee.release?(base)
        }
    }
}
