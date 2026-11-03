import BrkBase
import CCef
import CefKit
import Foundation

/// Compiled filter lists by store key, read and compiled off the main thread the first time a page needs one. Until a
/// list is ready the page blocks with the others; `loaded` lets the engine reapply when it is. A few recent lists are
/// kept: a profile has at most three, and an updated list arrives under a new key.
@MainActor
final class FilterListCache {
    private var lists: [String: CompiledFilterList] = [:]
    private var recent: [String] = []
    private var loading: Set<String> = []
    private var unreadable: Set<String> = []
    var loaded: (() -> Void)?

    func lists(_ keys: [String]) -> [CompiledFilterList] {
        keys.compactMap { key in
            if let list = lists[key] { touch(key); return list }
            load(key); return nil
        }
    }

    private func touch(_ key: String) {
        recent.removeAll { $0 == key }; recent.append(key)
        while recent.count > 8 { lists[recent.removeFirst()] = nil }
    }

    private func load(_ key: String) {
        guard FilterListStore.isKey(key), !loading.contains(key), !unreadable.contains(key) else { return }
        loading.insert(key)
        Task { @MainActor [weak self] in
            let list = await Task.detached(priority: .utility) { () -> CompiledFilterList? in
                guard let data = try? Data(contentsOf: FilterListStore.url(key)) else { return nil }
                return try? CompiledFilterList.compile(data)
            }.value
            guard let self else { return }
            self.loading.remove(key)
            guard let list else { self.unreadable.insert(key); return }
            self.lists[key] = list; self.touch(key)
            self.loaded?()
        }
    }
}

enum FilterResourceTypes {
    /// The request filter's decision for one document's requests (a new top-level page judges itself).
    static func matcher(_ lists: [CompiledFilterList], document: URL?) -> CefRequestFilter.Matcher {
        let flags = FilterLists.pageFlags(lists, documentURL: document)
        return { request, raw in
            let kind = type(raw)
            if kind == .document {
                return FilterLists.match(lists, url: request, type: kind, documentURL: request, pageFlags: FilterLists.pageFlags(lists, documentURL: request)).blocks
            }
            return FilterLists.match(lists, url: request, type: kind, documentURL: document, pageFlags: flags).blocks
        }
    }

    /// CEF's `cef_resource_type_t` as the filter type options name it.
    static func type(_ raw: Int32) -> FilterResourceType {
        switch UInt32(bitPattern: raw) {
        case RT_MAIN_FRAME.rawValue, RT_NAVIGATION_PRELOAD_MAIN_FRAME.rawValue: .document
        case RT_SUB_FRAME.rawValue, RT_NAVIGATION_PRELOAD_SUB_FRAME.rawValue: .subdocument
        case RT_STYLESHEET.rawValue: .stylesheet
        case RT_SCRIPT.rawValue, RT_WORKER.rawValue, RT_SHARED_WORKER.rawValue, RT_SERVICE_WORKER.rawValue: .script
        case RT_IMAGE.rawValue, RT_FAVICON.rawValue: .image
        case RT_FONT_RESOURCE.rawValue: .font
        case RT_OBJECT.rawValue, RT_PLUGIN_RESOURCE.rawValue: .object
        case RT_MEDIA.rawValue: .media
        case RT_XHR.rawValue: .xmlhttprequest
        case RT_PING.rawValue, RT_CSP_REPORT.rawValue: .ping
        default: .other
        }
    }
}
