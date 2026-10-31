import CCef
import Foundation

/// One request-context router. Incoming sink/route references and observer registration have explicit owners.
@MainActor public final class CefMediaRouting {
    public struct Sink: Sendable, Equatable { public let id: String; public let name: String }
    public private(set) var sinks: [Sink] = []
    public private(set) var routes: [String] = []
    public private(set) var sinkNotifications = 0
    public private(set) var routeNotifications = 0
    public private(set) var lastResult: Int?
    public private(set) var lastError: String?
    public private(set) var sourceSupported: Bool?
    public var onChange: (() -> Void)?
    public var onPendingChange: ((Bool) -> Void)?
    public var hasPendingRoutes: Bool { pendingCreates > 0 || !ownedRoutes.isEmpty }
    public var ownedRouteCount: Int { ownedRoutes.count }
    private var raw: UnsafeMutablePointer<cef_media_router_t>?
    private var registration: UnsafeMutablePointer<cef_registration_t>?
    private var nativeSinks: [String: UnsafeMutablePointer<cef_media_sink_t>] = [:]
    private var nativeRoutes: [String: UnsafeMutablePointer<cef_media_route_t>] = [:]
    private var ownedRoutes: Set<String> = []
    private var terminatingRoutes: Set<String> = []
    private var stopped = false
    private var pendingCreates = 0
    private var announcedOwnership = false
    private final class Observer { weak var owner: CefMediaRouting?; init(_ owner: CefMediaRouting) { self.owner = owner } }
    private final class Creation { var owner: CefMediaRouting?; init(_ owner: CefMediaRouting) { self.owner = owner } }

    public convenience init?(browser: CefBrowser) {
        var router: UnsafeMutablePointer<cef_media_router_t>?
        browser.withHostInternal { host in
            guard let context = host.pointee.get_request_context?(host) else { return }
            defer { cefRelease(UnsafeMutableRawPointer(context)) }
            router = context.pointee.get_media_router?(context, nil)
        }
        guard let router else { return nil }
        self.init(taking: router)
    }

    init(taking raw: UnsafeMutablePointer<cef_media_router_t>) {
        self.raw = raw
        let observer = cefAllocate(cef_media_observer_t.self, owner: Observer(self))
        observer.pointee.on_sinks = { raw, count, pointers in
            let incoming = (0..<count).compactMap { pointers?[$0] }
            MainActor.assumeIsolated {
                guard let owner = cefOwner(Observer.self, raw.map(UnsafeMutableRawPointer.init))?.owner, !owner.stopped else {
                    incoming.forEach { cefRelease(UnsafeMutableRawPointer($0)) }; return
                }
                owner.nativeSinks.values.forEach { cefRelease(UnsafeMutableRawPointer($0)) }; owner.nativeSinks.removeAll()
                owner.sinks = incoming.map { sink in
                    let id = CefStringUtil.takingUserFree(sink.pointee.get_id?(sink)) ?? ""
                    let name = CefStringUtil.takingUserFree(sink.pointee.get_name?(sink)) ?? id
                    if let duplicate = owner.nativeSinks.updateValue(sink, forKey: id) { cefRelease(UnsafeMutableRawPointer(duplicate)) }
                    return Sink(id: id, name: name)
                }
                owner.sinkNotifications += 1; owner.onChange?()
            }
        }
        observer.pointee.on_routes = { raw, count, pointers in
            let incoming = (0..<count).compactMap { pointers?[$0] }
            MainActor.assumeIsolated {
                guard let owner = cefOwner(Observer.self, raw.map(UnsafeMutableRawPointer.init))?.owner else {
                    incoming.forEach { cefRelease(UnsafeMutableRawPointer($0)) }; return
                }
                owner.nativeRoutes.values.forEach { cefRelease(UnsafeMutableRawPointer($0)) }; owner.nativeRoutes.removeAll()
                owner.routes = incoming.map { route in
                    let id = CefStringUtil.takingUserFree(route.pointee.get_id?(route)) ?? ""
                    if let duplicate = owner.nativeRoutes.updateValue(route, forKey: id) { cefRelease(UnsafeMutableRawPointer(duplicate)) }
                    return id
                }
                owner.ownedRoutes.formIntersection(owner.routes)
                owner.terminatingRoutes.formIntersection(owner.ownedRoutes)
                owner.routeNotifications += 1; owner.onChange?()
                owner.drainIfFinished()
            }
        }
        observer.pointee.on_route_state_changed = { raw, route, state in
            defer { cefRelease(route.map(UnsafeMutableRawPointer.init)) }
            MainActor.assumeIsolated {
                guard state == CEF_MRCS_TERMINATED, let route,
                      let owner = cefOwner(Observer.self, raw.map(UnsafeMutableRawPointer.init))?.owner else { return }
                let id = CefStringUtil.takingUserFree(route.pointee.get_id?(route)) ?? ""
                owner.ownedRoutes.remove(id); owner.terminatingRoutes.remove(id)
                if let held = owner.nativeRoutes.removeValue(forKey: id) { cefRelease(UnsafeMutableRawPointer(held)) }
                owner.routes.removeAll { $0 == id }
                owner.onChange?(); owner.drainIfFinished()
            }
        }
        observer.pointee.on_route_message_received = { _, route, _, _ in cefRelease(route.map(UnsafeMutableRawPointer.init)) }
        if let add = raw.pointee.add_observer { registration = add(raw, observer) }
        else { cefRelease(UnsafeMutableRawPointer(observer)) }
    }

    public func refresh() {
        guard !stopped, let raw else { return }
        raw.pointee.notify_current_sinks?(raw); raw.pointee.notify_current_routes?(raw)
    }

    /// Only Cast/DIAL presentation URNs are supported by the pinned CEF router; arbitrary page mirroring is not.
    public func connect(sourceURN: String, sinkID: String) {
        guard !stopped, let raw else { return }
        guard let sink = nativeSinks[sinkID] else { lastError = "No such receiver is currently available"; onChange?(); return }
        let source = CefStringUtil.withCefString(sourceURN) { raw.pointee.get_source?(raw, $0) }
        sourceSupported = source != nil
        guard let source else { lastError = "The media router does not support this presentation source"; onChange?(); return }
        lastError = nil
        // CEF consumes ref-counted call arguments. Keep the observer's sink reference separately.
        cefAddRef(UnsafeMutableRawPointer(sink))
        create(source: source, sink: sink)
    }

    /// GetSource can reject a presentation without creating a route or borrowing nonexistent receiver hardware.
    @discardableResult public func validateSource(_ urn: String) -> Bool {
        guard !stopped, let raw, !urn.isEmpty else { return false }
        let source = CefStringUtil.withCefString(urn) { raw.pointee.get_source?(raw, $0) }
        sourceSupported = source != nil
        cefRelease(source.map(UnsafeMutableRawPointer.init))
        lastError = source == nil ? "The media router does not support this presentation source" : nil
        onChange?()
        return sourceSupported == true
    }

    private func create(source: UnsafeMutablePointer<cef_media_source_t>, sink: UnsafeMutablePointer<cef_media_sink_t>) {
        guard let raw, let create = raw.pointee.create_route else {
            cefRelease(UnsafeMutableRawPointer(source)); cefRelease(UnsafeMutableRawPointer(sink)); return
        }
        pendingCreates += 1
        if !announcedOwnership { announcedOwnership = true; onPendingChange?(true) }
        guard !stopped else {
            cefRelease(UnsafeMutableRawPointer(source)); cefRelease(UnsafeMutableRawPointer(sink))
            routeCreationDrained(); return
        }
        let callback = cefAllocate(cef_media_route_create_callback_t.self, owner: Creation(self))
        callback.pointee.on_media_route_create_finished = { raw, result, error, route in
            let message = CefStringUtil.string(from: error)
            MainActor.assumeIsolated {
                guard let creation = cefOwner(Creation.self, raw.map(UnsafeMutableRawPointer.init)), let owner = creation.owner else {
                    cefRelease(route.map(UnsafeMutableRawPointer.init)); return
                }
                creation.owner = nil
                defer { owner.routeCreationDrained() }
                owner.lastResult = Int(result.rawValue); owner.lastError = message.isEmpty ? nil : message
                if let route {
                    let id = CefStringUtil.takingUserFree(route.pointee.get_id?(route)) ?? ""
                    owner.ownedRoutes.insert(id)
                    if let previous = owner.nativeRoutes.updateValue(route, forKey: id) { cefRelease(UnsafeMutableRawPointer(previous)) }
                }
                if owner.stopped { owner.terminateOwnedRoutes() }
                owner.onChange?()
            }
        }
        create(raw, source, sink, callback)
    }

    public func terminateOwnedRoutes() {
        for id in ownedRoutes where !terminatingRoutes.contains(id) {
            guard let route = nativeRoutes[id] else { continue }
            terminatingRoutes.insert(id)
            route.pointee.terminate?(route)
        }
    }

    private func routeCreationDrained() {
        pendingCreates -= 1
        drainIfFinished()
    }

    private func drainIfFinished() {
        guard !hasPendingRoutes else { return }
        if stopped {
            if let registration { self.registration = nil; cefRelease(UnsafeMutableRawPointer(registration)) }
            nativeSinks.values.forEach { cefRelease(UnsafeMutableRawPointer($0)) }; nativeSinks.removeAll()
            nativeRoutes.values.forEach { cefRelease(UnsafeMutableRawPointer($0)) }; nativeRoutes.removeAll()
            if let raw { self.raw = nil; cefRelease(UnsafeMutableRawPointer(raw)) }
        }
        if announcedOwnership { announcedOwnership = false; onPendingChange?(false) }
        if stopped { onPendingChange = nil }
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true; onChange = nil
        terminateOwnedRoutes()
        drainIfFinished()
    }
}
