import BrkBase
import BrkEngine
import CBrkCore
import Foundation

/// What a BrkCoreDownload says now, for `Transfers` (CEF's `CefDownload` snapshot).
struct CoreDownloadItem: TransferItem {
    let id: UInt32
    let url: URL?
    let suggestedName: String
    let receivedBytes: Int64
    let totalBytes: Int64
    let isComplete: Bool
    let isCanceled: Bool
    let isInterrupted: Bool
    let interruptionReason: Int

    @MainActor init(_ download: any BrkCoreDownload) {
        id = download.downloadID
        url = download.url
        suggestedName = download.suggestedName
        receivedBytes = download.receivedBytes
        totalBytes = download.totalBytes
        isComplete = download.isComplete
        isCanceled = download.isCanceled
        isInterrupted = download.isInterrupted
        interruptionReason = download.interruptionReason
    }
}

/// The destination answer and the cancel of one Chromium download.
@MainActor
final class CoreDownloadHandle: TransferDecision, TransferControl {
    private let download: any BrkCoreDownload
    init(_ download: any BrkCoreDownload) { self.download = download }
    func resolve(_ destination: URL?) { download.continue(toPath: destination?.path) }
    func cancel() { download.cancel() }
    func release() {}
}

extension CoreEngine {
    func downloadOwner(_ page: CorePage) -> DownloadOwner {
        DownloadOwner(browser: page.incarnation, context: contexts.epoch(for: page.context), policy: page.downloadPolicy)
    }

    func download(_ page: CorePage, _ download: any BrkCoreDownload, decide: Bool) {
        let owner = delegate?.engine(self, ownerWindow: page.id.window)
        let available: () -> Bool = { [weak self, weak page, weak owner] in
            guard let self, let page, let owner else { return false }
            return self.isLive(page) && owner.isStillOpen
        }
        let handle = CoreDownloadHandle(download)
        if decide {
            transfers.decision(CoreDownloadItem(download), name: download.suggestedName, owner: downloadOwner(page), available: available, callback: handle)
        } else {
            transfers.update(CoreDownloadItem(download), owner: downloadOwner(page), available: available, control: handle)
        }
    }
}
