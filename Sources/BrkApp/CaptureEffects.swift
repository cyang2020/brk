import AppKit
import BrkBase
import BrkDomain
import Foundation

extension AppStore {
    private func captureRemainsListed(_ record: CaptureRecord, in window: WindowID) -> Bool {
        guard case .library(let library)? = snapshot.windows[window]?.overlay else { return false }
        return library.captures.contains { $0.id == record.id && $0.profile == record.profile }
    }
    func runCapture(_ effect: CaptureEffect) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            func trace(_ value: String) {
                if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil { fputs("[capture] \(value)\n",stderr) }
            }
            @MainActor func fail(_ window: WindowID, _ id: String, _ error: Error) {
                trace("failed \(id): \(error)")
                self.dispatch(.system(.capture(.failed(window, id, error.localizedDescription))))
            }
            switch effect {
            case .load(let profile):
                do { let (rows, files) = try await captureFiles.load(profile); dispatch(.system(.capture(.loaded(profile, rows, files, error: nil)))) }
                catch { dispatch(.system(.capture(.loaded(profile, [], [:], error: "Cannot read captures: " + error.localizedDescription)))) }
            case .render(let request):
                trace("render \(request.id) \(request.mode)")
                do {
                    let pixels = try await engine.capture(request)
                    trace("pixels \(pixels.width)x\(pixels.height) scale \(pixels.scale); pending \(snapshot.windows[request.document.browser.page.window]?.capture?.request == request)")
                    dispatch(.system(.capture(.rendered(request, pixels))))
                    trace("render accepted: pending \(snapshot.windows[request.document.browser.page.window]?.capture?.request == request)")
                }
                catch { fail(request.document.browser.page.window, request.id, error) }
            case .store(let request, let image):
                let window = request.document.browser.page.window
                trace("store \(request.id); pending \(snapshot.windows[window]?.capture?.request == request)")
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
                    guard captureWindow(window)?.isVisible == true, captureRemainsListed(record,in:window) else { return }
                    if let insertCaptureInEasel { insertCaptureInEasel(EaselCaptureInsertion(capture: record, png: bytes), window) }
                    else { dispatch(.system(.capture(.exported(window, "Open an Easel to insert this capture.")))) }
                } catch { fail(window, record.id, error) }
            case .open(let record, let window):
                guard let owner = captureWindow(window) else { return }
                do {
                    let bytes = try await captureFiles.bytes(record)
                    guard captureWindow(window) === owner, owner.isVisible, captureRemainsListed(record,in:window) else { return }
                    try captureSheets.open(record,png:bytes,in:owner,id:window)
                }
                catch { fail(window,record.id,error) }
            case .export(let record, let window):
                guard let owner = captureWindow(window) else { return }
                captureSheets.choose(name:"Capture-" + record.id + ".png", capture:record.id, in:owner, id:window) { [weak self, weak owner] url in
                    guard let self, let url, owner?.isVisible == true,
                          self.captureWindow(window) === owner, self.captureRemainsListed(record,in:window) else { return }
                    Task { @MainActor in
                        do {
                            let bytes = try await self.captureFiles.bytes(record)
                            try await Task.detached { try bytes.write(to:url,options:.atomic) }.value
                            self.dispatch(.system(.capture(.exported(window,"Exported " + url.lastPathComponent))))
                        } catch { self.dispatch(.system(.capture(.failed(window,record.id,error.localizedDescription)))) }
                    }
                }
            }
        }
    }
}
