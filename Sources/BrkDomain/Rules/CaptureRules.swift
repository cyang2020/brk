import BrkBase
import Foundation

extension Work {
    mutating func captures(_ command: CaptureCommand, in window: WindowID) {
        switch command {
        case .begin(let mode):
            guard let tab = state.resolveTab(.focused, in: window), let value = state.displayedTab(tab, in: window),
                  let url = value.url, let live = state.session.live[PageID(window: window, item: tab)],
                  case .ready(let document) = live.document, live.requestedURL == nil, let context = live.requestContext else { return }
            state.session.windows[window]?.captureMessage = nil
            state.session.windows[window]?.copiedCapture = nil
            let request = CaptureRequest(id: ctx.newID(), document: document, context: context, mode: mode, title: value.displayTitle, url: url, createdAt: ctx.now)
            state.session.windows[window]?.capture = CaptureSnapshot(request: request)
            if mode == .fullPage {
                state.session.windows[window]?.capture?.rendering = true
                effects.append(.capture(.render(request)))
                toast(ToastCopy.captureInProgress, in: window)
            }
        case .select(let region):
            guard region.valid, var capture = state.session.windows[window]?.capture, !capture.rendering, capture.image == nil else { return }
            capture.request.region = region; capture.rendering = true
            state.session.windows[window]?.capture = capture
            effects.append(.capture(.render(capture.request)))
        case .cancel: state.session.windows[window]?.capture = nil
        case .act(let action):
            if let capture = state.session.windows[window]?.capture {
                guard let image = capture.image, !capture.rendering, capture.action == nil else { return }
                switch action {
                case .retake:
                    state.session.windows[window]?.capture?.image = nil
                    state.session.windows[window]?.capture?.request.region = nil
                case .copy:
                    effects.append(.capture(.copy(image)))
                    copied(CaptureSnapshot(request: capture.request, image: image), in: window)
                    state.session.windows[window]?.capture = nil
                case .file:
                    effects.append(.capture(.saveFile(capture.request, image, window)))
                    state.session.windows[window]?.capture = nil
                case .library, .edit:
                    // A private window's captures stay in memory: Copy and Save… only.
                    guard case .profile(let profile) = capture.request.context, state.doc.profiles[profile] != nil else { return }
                    state.session.windows[window]?.capture?.action = action
                    effects.append(.capture(.store(capture.request, image)))
                }
            } else if let copied = state.session.windows[window]?.copiedCapture, let image = copied.image, copied.action == nil {
                // The "Screenshot Copied to Clipboard" toast's Save: the Library for a profile, a file in a private window.
                switch action {
                case .library where copied.canSaveToLibrary:
                    state.session.windows[window]?.copiedCapture?.action = .library
                    effects.append(.capture(.store(copied.request, image)))
                case .file, .library:
                    state.session.windows[window]?.copiedCapture = nil
                    effects.append(.capture(.saveFile(copied.request, image, window)))
                default: break
                }
            }
        case .open(let id), .preview(let id), .export(let id), .remove(let id), .insertInEasel(let id):
            guard case .profile(let profile) = state.libraryContext(in: window),
                  let record = state.session.captures.records.first(where: { $0.id == id && $0.profile == profile }) else { return }
            switch command {
            case .open: effects.append(.capture(.open(record, window)))
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
            state.session.captures.errors[profile] = error
        case .rendered(let request, let image):
            let window = request.document.browser.page.window
            guard let capture = state.session.windows[window]?.capture, capture.request == request,
                  capture.rendering, state.session.live[request.document.browser.page]?.document == .ready(request.document),
                  state.session.live[request.document.browser.page]?.requestContext == request.context else { return }
            if case .profile(let profile) = request.context, state.doc.profiles[profile] == nil { return }
            if capture.image == nil { playSound(.captureCompleted) }
            if request.mode == .fullPage {
                // Arc copies a full-page capture at once and offers Save on the toast; the page stays put (P33-d).
                effects.append(.capture(.copy(image)))
                copied(CaptureSnapshot(request: request, image: image), in: window)
                state.session.windows[window]?.capture = nil
            } else {
                // A selection keeps its pixels in memory and opens the menu card beside it (P33-c).
                state.session.windows[window]?.capture?.image = image
                state.session.windows[window]?.capture?.rendering = false
            }
        case .stored(let request, let record, let file):
            guard state.doc.profiles[record.profile] != nil else { effects.append(.capture(.remove(record))); return }
            if !state.session.captures.records.contains(where: { $0.id == record.id }) { state.session.captures.records.insert(record, at: 0) }
            state.session.captures.files[record.id] = file
            offerLibraryBadge(.capture(record.id), profile: record.profile, date: record.createdAt)
            let window = request.document.browser.page.window
            if let capture = state.session.windows[window]?.capture, capture.request == request {
                state.session.windows[window]?.capture = nil
                if capture.action == .edit {
                    state.session.windows[window]?.capturePreview = record.id
                    library(.open(.media), in: window)
                } else { toast("Saved to Library", in: window) }
            } else if state.session.windows[window]?.copiedCapture?.request == request {
                state.session.windows[window]?.copiedCapture = nil
                toast("Saved to Library", in: window)
            }
        case .removed(_, let id):
            state.session.captures.records.removeAll { $0.id == id }; state.session.captures.files[id] = nil
            for window in state.session.windows.keys where state.session.windows[window]?.capturePreview == id { state.session.windows[window]?.capturePreview = nil }
        case .failed(let window, let id, let error):
            let pending = state.session.windows[window]?.capture?.request.id == id
            let copied = state.session.windows[window]?.copiedCapture?.request.id == id
            guard pending || copied || state.session.captures.records.contains(where: { $0.id == id }) || id.isEmpty else { return }
            if pending { state.session.windows[window]?.capture = nil }
            if copied { state.session.windows[window]?.copiedCapture?.action = nil }
            state.session.windows[window]?.captureMessage = error
            toast("Capture failed: " + error, in: window)
        case .exported(let window, let message):
            state.session.windows[window]?.captureMessage = message
            toast(message, in: window)
        }
    }
    /// Keeps the copied pixels for the toast's Save while the toast is up.
    mutating func copied(_ capture: CaptureSnapshot, in window: WindowID) {
        state.session.windows[window]?.copiedCapture = capture
        toast("Screenshot Copied to Clipboard", in: window, action: ToastAction(title: "Save", command: .capture(.act(.library))))
    }

    mutating func reconcileCaptures(from before: AppState) {
        for profile in before.doc.profiles.keys where state.doc.profiles[profile] == nil {
            state.session.captures.records.removeAll { $0.profile == profile }; state.session.captures.loaded.remove(profile)
            effects.append(.capture(.forget(profile)))
        }
        for window in state.session.windows.keys {
            guard let capture = state.session.windows[window]?.capture else { continue }
            let page = capture.request.document.browser.page
            if state.session.live[page]?.requestedURL != nil || state.session.live[page]?.document != .ready(capture.request.document)
                || state.session.live[page]?.requestContext != capture.request.context
                || state.resolveTab(.focused, in: window) != page.item {
                state.session.windows[window]?.capture = nil
            }
        }
    }
}
