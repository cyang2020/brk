import CCef
import Foundation
import Testing
@testable import CefKit

/// ABI fixtures check reference/callback ownership, never stand in for a real receiver in native acceptance.
@MainActor struct MediaRoutingOwnershipTests {
    private static func loadStrings() throws {
        if ccef_is_framework_loaded() == 1 { return }
        let path = try #require(LoaderTests.frameworkBinaryPath())
        try #require(ccef_load_framework(path) == 1)
        _ = cef_api_hash(CCEF_API_VERSION_VALUE, 0)
    }
    final class Registration {
        let observer: UnsafeMutablePointer<cef_media_observer_t>
        init(_ observer: UnsafeMutablePointer<cef_media_observer_t>) { self.observer = observer }
        deinit { cefRelease(UnsafeMutableRawPointer(observer)) }
    }
    final class Native {
        var observer: UnsafeMutablePointer<cef_media_observer_t>?
        var callback: UnsafeMutablePointer<cef_media_route_create_callback_t>?
        var owned: UnsafeMutablePointer<cef_media_route_t>?
        var foreign: UnsafeMutablePointer<cef_media_route_t>?
        var terminations: [String] = []
        var creates = 0
    }
    final class Route {
        let name: String
        let native: Native
        init(_ name: String, native: Native) { self.name = name; self.native = native }
    }
    nonisolated static func string(_ text: String) -> cef_string_userfree_t {
        let raw = malloc(MemoryLayout<cef_string_t>.stride)!.assumingMemoryBound(to: cef_string_t.self)
        raw.initialize(to: cef_string_t()); CefStringUtil.set(text, into: &raw.pointee); return raw
    }
    static func route(_ name: String, _ native: Native) -> UnsafeMutablePointer<cef_media_route_t> {
        let raw = cefAllocate(cef_media_route_t.self, owner: Route(name, native: native))
        raw.pointee.get_id = { raw in MediaRoutingOwnershipTests.string(cefOwner(Route.self, raw.map(UnsafeMutableRawPointer.init))!.name) }
        raw.pointee.terminate = { raw in
            let owner = cefOwner(Route.self, raw.map(UnsafeMutableRawPointer.init))!
            owner.native.terminations.append(owner.name)
        }
        return raw
    }
    static func router(_ native: Native) -> CefMediaRouting {
        let raw = cefAllocate(cef_media_router_t.self, owner: native)
        raw.pointee.add_observer = { raw, observer in
            let native = cefOwner(Native.self, raw.map(UnsafeMutableRawPointer.init))!
            native.observer = observer
            return cefAllocate(cef_registration_t.self, owner: Registration(observer!))
        }
        raw.pointee.notify_current_sinks = { raw in
            let observer = cefOwner(Native.self, raw.map(UnsafeMutableRawPointer.init))!.observer!
            observer.pointee.on_sinks?(observer, 0, nil)
        }
        raw.pointee.notify_current_routes = { raw in
            let observer = cefOwner(Native.self, raw.map(UnsafeMutableRawPointer.init))!.observer!
            observer.pointee.on_routes?(observer, 0, nil)
        }
        raw.pointee.create_route = { raw, source, sink, callback in
            let native = cefOwner(Native.self, raw.map(UnsafeMutableRawPointer.init))!
            native.creates += 1; native.callback = callback
            cefRelease(source.map(UnsafeMutableRawPointer.init)); cefRelease(sink.map(UnsafeMutableRawPointer.init))
        }
        return CefMediaRouting(taking: raw)
    }
    @Test(.enabled(if: LoaderTests.frameworkAvailable, "Set CEF_FRAMEWORK_PATH for native CEF string ownership"))
    func observerEnumeratesAndOnlyTerminatesItsOwnRoutes() throws {
        try Self.loadStrings()
        let native = Native(), router = Self.router(native)
        router.refresh()
        #expect(router.sinkNotifications == 1 && router.routeNotifications == 1)
        router.probeUnavailableRoute()
        #expect(native.creates == 1)
        let owned = Self.route("owned", native), foreign = Self.route("foreign", native)
        let callback = native.callback!
        cefAddRef(UnsafeMutableRawPointer(owned))
        callback.pointee.on_media_route_create_finished?(callback, CEF_MRCR_OK, nil, owned)
        cefRelease(UnsafeMutableRawPointer(callback)); native.callback = nil
        let observer = native.observer!
        cefAddRef(UnsafeMutableRawPointer(owned)); cefAddRef(UnsafeMutableRawPointer(foreign))
        let routes: [UnsafeMutablePointer<cef_media_route_t>?] = [owned, foreign]
        routes.withUnsafeBufferPointer { observer.pointee.on_routes?(observer, routes.count, $0.baseAddress) }
        router.stop(); router.stop()
        #expect(native.terminations == ["owned"])
        cefRelease(UnsafeMutableRawPointer(owned)); cefRelease(UnsafeMutableRawPointer(foreign))
    }
    @Test(.enabled(if: LoaderTests.frameworkAvailable, "Set CEF_FRAMEWORK_PATH for native CEF string ownership"))
    func lateRouteAfterSourceCloseIsImmediatelyTerminated() throws {
        try Self.loadStrings()
        let native = Native(), router = Self.router(native)
        router.probeUnavailableRoute(); router.stop()
        let owned = Self.route("late", native), callback = native.callback!
        cefAddRef(UnsafeMutableRawPointer(owned))
        callback.pointee.on_media_route_create_finished?(callback, CEF_MRCR_OK, nil, owned)
        #expect(native.terminations == ["late"])
        cefRelease(UnsafeMutableRawPointer(callback)); native.callback = nil
        cefRelease(UnsafeMutableRawPointer(owned))
    }
}
