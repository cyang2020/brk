import AppKit
import BrkBase
import BrkDomain
import Foundation
import UniformTypeIdentifiers

extension AppStore {
    func runCapture(_ effect: CaptureEffect) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            @MainActor func fail(_ window: WindowID, _ id: String, _ error: Error) { self.dispatch(.system(.capture(.failed(window, id, error.localizedDescription)))) }
            switch effect {
            case .load(let profile):
                do { let (rows, files) = try await captureFiles.load(profile); dispatch(.system(.capture(.loaded(profile, rows, files, error: nil)))) }
                catch { dispatch(.system(.capture(.loaded(profile, [], [:], error: "Cannot read captures: " + error.localizedDescription)))) }
            case .render(let request):
                do { let pixels = try await engine.capture(request); dispatch(.system(.capture(.rendered(request, pixels)))) }
                catch { fail(request.document.browser.page.window, request.id, error) }
            case .store(let request, let image):
                let window = request.document.browser.page.window
                guard snapshot.windows[window]?.capture?.request == request else { return }
                do {
                    let (record, file) = try await captureFiles.store(request, image: image)
                    guard snapshot.windows[window]?.capture?.request == request else { try await captureFiles.remove(record); return }
                    dispatch(.system(.capture(.stored(request, record, file))))
                } catch { fail(window, request.id, error) }
            case .remove(let record):
                do { try await captureFiles.remove(record); dispatch(.system(.capture(.removed(record.profile, record.id)))) }
                catch { if let window = snapshot.windows.keys.sorted().first { fail(window, record.id, error) } }
            case .forget(let profile):
                do { try await captureFiles.forget(profile) } catch { if let window = snapshot.windows.keys.sorted().first { fail(window, "", error) } }
            case .insertInEasel(let record, let window):
                do {
                    let bytes = try await captureFiles.bytes(record)
                    if let insertCaptureInEasel { insertCaptureInEasel(EaselCaptureInsertion(capture: record, png: bytes), window) }
                    else { dispatch(.system(.capture(.exported(window, "Open an Easel to insert this capture.")))) }
                } catch { fail(window, record.id, error) }
            case .export(let record, let window):
                guard let owner = captureWindow(window) else { return }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "Capture-" + record.id + ".png"
                panel.beginSheetModal(for: owner) { [weak self, weak owner] answer in
                    guard answer == .OK, let url = panel.url, owner?.isVisible == true, let self else { return }
                    Task { @MainActor in
                        do {
                            let bytes = try await self.captureFiles.bytes(record)
                            try await Task.detached { try bytes.write(to: url, options: .atomic) }.value
                            self.dispatch(.system(.capture(.exported(window, "Exported " + url.lastPathComponent))))
                        } catch { self.dispatch(.system(.capture(.failed(window, record.id, error.localizedDescription)))) }
                    }
                }
            }
        }
    }
}
