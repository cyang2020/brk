import CCef
import Foundation

public enum CefAuxiliaryKind: Sendable, Equatable {
    case popup(CefWindowOpenRequest)
    case devTools
}

extension CefBrowser {
    public var nativeAuxiliaries: [(browser: CefBrowser, kind: CefAuxiliaryKind)] { client?.auxiliaryBrowsers ?? [] }
    public var nativeAuxiliaryCount: Int { client?.auxiliaryCount ?? 0 }
    public func closeNativeAuxiliaries() { client?.closeNativeAuxiliaries() }
    public func closeNativeAuxiliaries(matching include: (CefAuxiliaryKind) -> Bool) { client?.closeNativeAuxiliaries(matching: include) }
}

extension BrowserClient {
    var auxiliaryRoot: BrowserClient {
        var root = self
        while let parent = root.auxiliaryParent { root = parent }
        return root
    }
    var auxiliaryCount: Int { nativeAuxiliaries.values.reduce(0) { $0 + 1 + $1.auxiliaryCount } }
    var auxiliaryBrowsers: [(browser: CefBrowser, kind: CefAuxiliaryKind)] {
        nativeAuxiliaries.values.flatMap { child in
            let own = child.browser.flatMap { browser in child.auxiliaryKind.map { [(browser: browser, kind: $0)] } } ?? []
            return own + child.auxiliaryBrowsers
        }
    }

    func installNativeAuxiliary(_ kind: CefAuxiliaryKind, replacing pointer: UnsafeMutablePointer<UnsafeMutablePointer<cef_client_t>?>) {
        let child = BrowserClient(), key = UUID()
        child.auxiliaryParent = self; child.auxiliaryKey = key; child.auxiliaryKind = kind
        child.pendingOSRBrowser = CefBrowser(raw: nil, client: child, delegate: nil)
        nativeAuxiliaries[key] = child
        // Incoming ref-counted in/out arguments carry a +1; CEF consumes our replacement on return.
        cefRelease(pointer.pointee.map(UnsafeMutableRawPointer.init))
        pointer.pointee = child.makeClient()
        notifyAuxiliaryChange()
    }

    func didCreateNativeAuxiliary(_ browser: CefBrowser) {
        guard let kind = auxiliaryKind, let parent = auxiliaryParent else { return }
        var root = parent
        while let next = root.auxiliaryParent { root = next }
        if auxiliaryCancelled || root.browser == nil { browser.close(force: true) }
        else if let owner = root.browser { owner.delegate?.browser(owner, didCreateAuxiliary: browser, kind: kind) }
    }

    func didCloseNativeAuxiliary() {
        guard let parent = auxiliaryParent, let key = auxiliaryKey else { return }
        parent.nativeAuxiliaries[key] = nil
        auxiliaryParent = nil
        parent.notifyAuxiliaryChange()
    }

    func notifyAuxiliaryChange() {
        if let parent = auxiliaryParent { parent.notifyAuxiliaryChange() }
        else if let browser { browser.delegate?.browser(browser, auxiliaryCountChanged: auxiliaryCount) }
    }

    func closeNativeAuxiliaries() { closeNativeAuxiliaries(matching: { _ in true }) }
    func closeNativeAuxiliaries(matching include: (CefAuxiliaryKind) -> Bool) {
        for child in Array(nativeAuxiliaries.values) {
            if let kind = child.auxiliaryKind, include(kind) {
                child.auxiliaryCancelled = true
                child.closeNativeAuxiliaries()
                child.browser?.close(force: true)
            } else { child.closeNativeAuxiliaries(matching: include) }
        }
    }

    func abortNativePopup(_ id: Int) {
        for (key, child) in nativeAuxiliaries {
            guard case .popup(let request) = child.auxiliaryKind, request.popupID == id, child.browser == nil else { continue }
            nativeAuxiliaries[key] = nil
            child.pendingOSRBrowser = nil
            child.releaseHandlers()
        }
        notifyAuxiliaryChange()
    }
}
