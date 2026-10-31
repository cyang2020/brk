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
        raw.pointee.get_source = { raw, urn in
            guard CefStringUtil.string(from: urn).hasPrefix("cast:") else { return nil }
            return cefAllocate(cef_media_source_t.self, owner: cefOwner(Native.self, raw.map(UnsafeMutableRawPointer.init))!)
        }
        return CefMediaRouting(taking: raw)
    }
    static func installSink(_ native: Native) -> UnsafeMutablePointer<cef_media_sink_t> {
        let sink = cefAllocate(cef_media_sink_t.self, owner: native)
        sink.pointee.get_id = { _ in MediaRoutingOwnershipTests.string("abi-sink") }
        sink.pointee.get_name = { _ in MediaRoutingOwnershipTests.string("ABI fixture, not receiver hardware") }
        cefAddRef(UnsafeMutableRawPointer(sink))
        let observer = native.observer!
        var incoming: UnsafeMutablePointer<cef_media_sink_t>? = sink
        observer.pointee.on_sinks?(observer, 1, &incoming)
        return sink
    }
    @Test func unsupportedPresentationDoesNotCreateOrAcquirePendingRoute() {
        let native = Native(), router = Self.router(native)
        #expect(!router.validateSource("https://fixture.invalid/no-source"))
        #expect(native.creates == 0, "CEF's generated API rejects null source/sink without a completion callback")
        #expect(!router.hasPendingRoutes, "Unsupported input must not acquire an undrainable route lease")
        router.stop()
        if let callback = native.callback {
            callback.pointee.on_media_route_create_finished?(callback, CEF_MRCR_UNKNOWN_ERROR, nil, nil)
            cefRelease(UnsafeMutableRawPointer(callback)); native.callback = nil
        }
    }
    @Test func observerRefreshAndStopWithoutARouteDoNotReleaseANonexistentLease() {
        let native = Native(), router = Self.router(native)
        var ownership: [Bool] = []
        router.onPendingChange = { ownership.append($0) }
        router.refresh(); router.stop()
        #expect(ownership.isEmpty, "An empty observer must not reenter page closure by releasing a lease it never acquired")
    }
    @Test(.enabled(if: LoaderTests.frameworkAvailable, "Set CEF_FRAMEWORK_PATH for native CEF string ownership"))
    func observerEnumeratesAndOnlyTerminatesItsOwnRoutes() throws {
        try Self.loadStrings()
        let native = Native(), router = Self.router(native)
        router.refresh()
        #expect(router.sinkNotifications == 1 && router.routeNotifications == 1)
        let sink = Self.installSink(native)
        router.connect(sourceURN: "cast:ABI-fixture", sinkID: "abi-sink")
        #expect(native.creates == 1)
        let owned = Self.route("owned", native), foreign = Self.route("foreign", native)
        let callback = native.callback!
        cefAddRef(UnsafeMutableRawPointer(owned))
        callback.pointee.on_media_route_create_finished?(callback, CEF_MRCR_OK, nil, owned)
        cefRelease(UnsafeMutableRawPointer(callback)); native.callback = nil
        let observer = native.observer!
        cefAddRef(UnsafeMutableRawPointer(observer))
        defer { cefRelease(UnsafeMutableRawPointer(observer)) }
        cefAddRef(UnsafeMutableRawPointer(owned)); cefAddRef(UnsafeMutableRawPointer(foreign))
        let routes: [UnsafeMutablePointer<cef_media_route_t>?] = [owned, foreign]
        routes.withUnsafeBufferPointer { observer.pointee.on_routes?(observer, routes.count, $0.baseAddress) }
        #expect(router.hasPendingRoutes, "An active route owns its source until actual termination")
        router.stop(); router.stop()
        #expect(native.terminations == ["owned"])
        #expect(router.hasPendingRoutes, "Terminate is a request, not a completion callback")
        cefAddRef(UnsafeMutableRawPointer(owned))
        observer.pointee.on_route_state_changed?(observer, owned, CEF_MRCS_CLOSED)
        #expect(router.hasPendingRoutes, "Connection closure does not prove receiver termination")
        cefAddRef(UnsafeMutableRawPointer(owned))
        observer.pointee.on_route_state_changed?(observer, owned, CEF_MRCS_TERMINATED)
        #expect(!router.hasPendingRoutes)
        cefRelease(UnsafeMutableRawPointer(owned)); cefRelease(UnsafeMutableRawPointer(foreign))
        cefRelease(UnsafeMutableRawPointer(sink))
    }
    @Test(.enabled(if: LoaderTests.frameworkAvailable, "Set CEF_FRAMEWORK_PATH for native CEF string ownership"))
    func lateRouteAfterSourceCloseIsImmediatelyTerminated() throws {
        try Self.loadStrings()
        let native = Native(), router = Self.router(native)
        let sink = Self.installSink(native)
        let observer = native.observer!
        cefAddRef(UnsafeMutableRawPointer(observer))
        defer { cefRelease(UnsafeMutableRawPointer(observer)) }
        router.connect(sourceURN: "cast:ABI-fixture", sinkID: "abi-sink"); router.stop()
        let owned = Self.route("late", native), callback = native.callback!
        cefAddRef(UnsafeMutableRawPointer(owned))
        callback.pointee.on_media_route_create_finished?(callback, CEF_MRCR_OK, nil, owned)
        #expect(native.terminations == ["late"])
        #expect(router.hasPendingRoutes, "A late success still waits for native termination")
        observer.pointee.on_routes?(observer, 0, nil)
        #expect(!router.hasPendingRoutes)
        cefRelease(UnsafeMutableRawPointer(callback)); native.callback = nil
        cefRelease(UnsafeMutableRawPointer(owned))
        cefRelease(UnsafeMutableRawPointer(sink))
    }
}
