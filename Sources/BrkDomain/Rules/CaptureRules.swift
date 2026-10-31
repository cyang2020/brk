import BrkBase
import Foundation

extension Work {
    mutating func captures(_ command: CaptureCommand, in window: WindowID) {
        switch command {
        case .begin(let mode):
            guard let tab = state.resolveTab(.focused, in: window), let value = state.displayedTab(tab, in: window),
                  let url = value.url, let live = state.session.live[PageID(window: window, item: tab)],
                  case .ready(let document) = live.document, let context = live.requestContext else { return }
            let request = CaptureRequest(id: ctx.newID(), document: document, context: context, mode: mode, title: value.displayTitle, url: url, createdAt: ctx.now)
            state.session.windows[window]?.capture = CaptureSnapshot(request: request)
            if mode == .fullPage { state.session.windows[window]?.capture?.rendering = true; effects.append(.capture(.render(request))) }
        case .select(let region):
            guard region.valid, var capture = state.session.windows[window]?.capture, !capture.rendering, capture.image == nil else { return }
            capture.request.region = region; capture.rendering = true
            state.session.windows[window]?.capture = capture
            effects.append(.capture(.render(capture.request)))
        case .cancel: state.session.windows[window]?.capture = nil
        case .preview(let id), .export(let id), .remove(let id), .insertInEasel(let id):
            guard case .profile(let profile) = state.libraryContext(in: window),
                  let record = state.session.captures.records.first(where: { $0.id == id && $0.profile == profile }) else { return }
            switch command {
            case .preview: state.session.windows[window]?.capturePreview = id
            case .export: effects.append(.capture(.export(record, window)))
            case .remove: effects.append(.capture(.remove(record)))
            case .insertInEasel: effects.append(.capture(.insertInEasel(record, window)))
            default: break
            }
        }
    }
    mutating func captureEvent(_ event: CaptureEvent) {
        switch event {
        case .loaded(let profile, let rows, let files, let error):
            guard state.doc.profiles[profile] != nil else { return }
            state.session.captures.loaded.insert(profile)
            state.session.captures.records.removeAll { $0.profile == profile }
            state.session.captures.records += rows.filter { $0.profile == profile }
            state.session.captures.files.merge(files) { _, new in new }
            if let error { state.session.captureError = error }
        case .rendered(let request, let image):
            let window = request.document.browser.page.window
            guard let capture = state.session.windows[window]?.capture, capture.request == request,
                  capture.rendering, state.session.live[request.document.browser.page]?.document == .ready(request.document),
                  state.session.live[request.document.browser.page]?.requestContext == request.context else { return }
            switch request.context {
            case .incognito:
                if capture.image == nil { playSound(.captureCompleted) }
                state.session.windows[window]?.capture?.image = image
                state.session.windows[window]?.capture?.rendering = false
            case .profile(let profile):
                guard state.doc.profiles[profile] != nil else { return }
                effects.append(.capture(.store(request, image)))
            }
        case .stored(let request, let record, let file):
            guard state.doc.profiles[record.profile] != nil else { effects.append(.capture(.remove(record))); return }
            if !state.session.captures.records.contains(where: { $0.id == record.id }) { state.session.captures.records.insert(record, at: 0); playSound(.captureCompleted) }
            state.session.captures.files[record.id] = file
            let window = request.document.browser.page.window
            if state.session.windows[window]?.capture?.request == request {
                state.session.windows[window]?.capture = nil
                state.session.windows[window]?.capturePreview = record.id
                library(.open(.media), in: window)
            }
        case .removed(_, let id):
            state.session.captures.records.removeAll { $0.id == id }; state.session.captures.files[id] = nil
            for window in state.session.windows.keys where state.session.windows[window]?.capturePreview == id { state.session.windows[window]?.capturePreview = nil }
        case .failed(let window, let id, let error):
            let pending = state.session.windows[window]?.capture?.request.id == id
            guard pending || state.session.captures.records.contains(where: { $0.id == id }) || id.isEmpty else { return }
            if pending { state.session.windows[window]?.capture = nil }
            state.session.captureError = error
            toast("Capture failed: " + error, in: window)
        case .exported(_, let message): state.session.captureError = message
        }
    }
    mutating func reconcileCaptures(from before: AppState) {
        for profile in before.doc.profiles.keys where state.doc.profiles[profile] == nil {
            state.session.captures.records.removeAll { $0.profile == profile }; state.session.captures.loaded.remove(profile)
            effects.append(.capture(.forget(profile)))
        }
        for window in state.session.windows.keys {
            guard let capture = state.session.windows[window]?.capture else { continue }
            let page = capture.request.document.browser.page
            if state.session.live[page]?.document != .ready(capture.request.document)
                || state.session.live[page]?.requestContext != capture.request.context
                || state.resolveTab(.focused, in: window) != page.item {
                state.session.windows[window]?.capture = nil
            }
        }
    }
}
