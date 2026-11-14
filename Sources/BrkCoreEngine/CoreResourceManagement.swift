import AppKit
import BrkBase
import BrkEngine
import CBrkCore
import Foundation
import os

@MainActor
final class CoreResourceManagement {
    private weak var engine: CoreEngine?
    private let policy = PageResourcePolicy()
    private var timer: Timer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var pressure: PageResourcePolicy.Pressure = .normal
    private var nextReclaim: TimeInterval = 0
    private var nextMaintenance: TimeInterval = 0
    private var reconciling = false
    private let log = Logger(subsystem: "brk", category: "page-resources")

    init(engine: CoreEngine) {
        self.engine = engine
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let flags = self.pressureSource?.data ?? []
                self.pressure = flags.contains(.critical) ? .critical : flags.contains(.warning) ? .warning : .normal
                self.reconcile()
            }
        }
        pressureSource = source
        source.resume()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pressureSource?.cancel()
        pressureSource = nil
    }

    func reconcile() {
        guard !reconciling, let engine, engine.isRunning else { return }
        reconciling = true
        defer { reconciling = false }
        let now = ProcessInfo.processInfo.systemUptime
        let pages = engine.livePages
        let snapshots = pages.map { page -> PageResourcePolicy.Page in
            page.noteVisibility(now: now)
            return .init(id: page.incarnation, lastUsed: page.lastResourceUse, hiddenSince: page.resourceHiddenSince,
                         protected: page.resourceProtected, discarded: page.contents.discarded)
        }
        let available = Self.availableMemory()
        let floor = min(UInt64(512 * 1024 * 1024), ProcessInfo.processInfo.physicalMemory / 20)
        let target = (floor > available ? floor - available : 0) + 128 * 1024 * 1024
        let activePressure: PageResourcePolicy.Pressure = now >= nextReclaim ? pressure : .normal
        let actions = policy.actions(for: snapshots, now: now, pressure: activePressure)
        var remainingTarget = target
        var estimated: UInt64 = 0
        var discarded = 0
        for page in pages.sorted(by: { $0.lastResourceUse == $1.lastResourceUse ? $0.id < $1.id : $0.lastResourceUse < $1.lastResourceUse }) {
            guard let action = actions[page.incarnation] else { continue }
            switch action {
            case .active: page.setAutomaticFreezing(false)
            case .freeze: page.setAutomaticFreezing(true)
            case .discard:
                guard activePressure != .normal || now >= nextMaintenance else { continue }
                if activePressure == .normal && discarded > 0 {
                    page.setAutomaticFreezing(true)
                    continue
                }
                if activePressure != .normal && remainingTarget == 0 {
                    page.setAutomaticFreezing(true)
                    continue
                }
                guard !page.resourceProtected else { continue }
                let bytes = page.contents.estimatedMemoryBytes
                if page.contents.discardIfEligible() {
                    discarded += 1
                    estimated += bytes
                    remainingTarget -= min(remainingTarget, max(bytes, 16 * 1024 * 1024))
                } else {
                    page.setAutomaticFreezing(true)
                }
            }
        }
        if discarded > 0 { nextMaintenance = now + 15 }
        if activePressure != .normal {
            nextReclaim = now + (discarded > 0 ? 30 : 60)
            log.notice("memory reclaim: target=\(target) estimated=\(estimated) pages=\(discarded) availableBefore=\(available)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.log.notice("memory reclaim: availableAfter=\(Self.availableMemory())")
            }
        }
    }

    private static func availableMemory() -> UInt64 {
        let host = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, host) }
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return ProcessInfo.processInfo.physicalMemory }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return ProcessInfo.processInfo.physicalMemory }
        return (UInt64(statistics.free_count) + UInt64(statistics.inactive_count)) * UInt64(pageSize)
    }
}

extension CorePage {
    var resourceProtected: Bool {
        websiteOperationProtected() || contents.isLoading || openDialog != nil || surface.containsFirstResponder
            || contents.hasDeveloperTools
            || contents.committedURL?.scheme != "http" && contents.committedURL?.scheme != "https"
            || contents.committedURL?.host == "chromewebstore.google.com"
    }

    func noteVisibility(now: TimeInterval) {
        if websitePolicy.visible {
            lastResourceUse = now
            resourceHiddenSince = nil
        } else if resourceHiddenSince == nil {
            resourceHiddenSince = now
        }
    }

    func setAutomaticFreezing(_ value: Bool) {
        automaticFreezing = value
        reconcileFreezing()
    }

    func reconcileFreezing() {
        let mode: BrkCoreFreezingMode
        if websitePolicy.visible || resourceProtected { mode = .active }
        else if siteFreezing { mode = .userRequested }
        else if automaticFreezing { mode = .automatic }
        else { mode = .active }
        _ = contents.setFreezingMode(mode)
    }

    @objc(webContentsWasDiscarded:)
    func webContentsWasDiscarded(_ contents: any BrkCoreWebContents) {
        settlePermissionGrants(keeping: nil)
        find.invalidate()
        reportedSelection = false
        policyWorld = nil
        websiteStyleOwner = nil
        requestFilterPatterns = []
        requestFilterEnabled = false
        automaticFreezing = false
        siteFreezing = false
        for event in mainDocument.rendererGone() { engine.pageDidEmit(self, event) }
    }

    @objc(webContentsProtocolStateInvalidated:)
    func webContentsProtocolStateInvalidated(_ contents: any BrkCoreWebContents) {
        policyWorld = nil
        requestFilterPatterns = []
        requestFilterEnabled = false
        configureRequestFilter(navigatingTo ?? contents.committedURL)
        refreshWebsitePolicy()
    }
}
