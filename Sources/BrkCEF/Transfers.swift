import BrkBase
import CefKit
import Foundation

@MainActor protocol TransferDecision: AnyObject { func resolve(_ destination: URL?) }
@MainActor protocol TransferControl: AnyObject { func cancel(); func release() }
extension CefDownloadDecisionCallback: TransferDecision {}
extension CefDownloadControl: TransferControl {}

/// Runs the production callback transitions. Native adapters transfer references here on the CEF UI thread.
@MainActor final class Transfers {
    struct Key: Hashable { let browser: BrowserToken; let native: UInt32 }
    final class Operation {
        let id = DownloadID(UUID().uuidString)
        let owner: DownloadOwner
        let sourceAvailable: () -> Bool
        var details: DownloadDetails?
        var progress = TransferProgress(received: 0, total: nil)
        var revision: UInt64 = 0
        var decision: (any TransferDecision)?
        var control: (any TransferControl)?
        var ticket: DestinationTicket?
        var accepted = false
        var cancelling = false
        var failure: String?
        var terminal: DownloadEnd?
        var terminalPublished = false
        var files: TransferFiles?
        init(owner: DownloadOwner, sourceAvailable: @escaping () -> Bool) {
            self.owner = owner; self.sourceAvailable = sourceAvailable
        }
    }
    private(set) var operations: [Key: Operation] = [:]
    private var ids: [DownloadID: Key] = [:]
    private var tombstones: Set<Key> = []
    private var revoked: Set<BrowsingContext> = []
    private var running = true
    var publish: (DownloadUpdate) -> Void = { _ in }
    var prompt: (DownloadDestinationPrompt, @escaping @MainActor (DestinationAnswer) -> Void) -> Void = { _, reply in reply(.ownerGone) }
    var dismiss: (DestinationTicket) -> Void = { _ in }
    var acquire: (DownloadID, BrowserToken) -> Bool = { _, _ in false }
    var release: (DownloadID, BrowserToken) -> Void = { _, _ in }

    var isEmpty: Bool { operations.isEmpty }
    func contains(context: BrowsingContext) -> Bool { operations.values.contains { $0.owner.context.context == context } }

    private func installed(_ op: Operation) -> Bool {
        guard let key = ids[op.id] else { return false }
        return operations[key] === op
    }

    private func operation(_ key: Key, owner: DownloadOwner, sourceAvailable: @escaping () -> Bool) -> Operation? {
        if let existing = operations[key] { return existing }
        guard !tombstones.contains(key) else { return nil }
        let op = Operation(owner: owner, sourceAvailable: sourceAvailable)
        guard running, !revoked.contains(owner.context.context), sourceAvailable(), acquire(op.id, key.browser) else {
            tombstones.insert(key)
            return nil
        }
        operations[key] = op; ids[op.id] = key
        return op
    }

    private func capture(_ item: CefDownload, name: String? = nil, in op: Operation) {
        if op.details == nil, let url = item.url, url.scheme != nil {
            let candidate = name ?? item.suggestedName
            if !candidate.isEmpty { op.details = DownloadDetails(url: url, suggestedName: TransferFiles.safeName(candidate)) }
        }
        op.progress = TransferProgress(received: max(op.progress.received, item.receivedBytes),
                                       total: item.totalBytes > 0 ? item.totalBytes : op.progress.total)
    }

    func decision(_ item: CefDownload, name: String, owner: DownloadOwner,
                  available: @escaping () -> Bool, callback: any TransferDecision) {
        let key = Key(browser: owner.browser, native: item.id)
        guard let op = operation(key, owner: owner, sourceAvailable: available) else { callback.resolve(nil); return }
        capture(item, name: name, in: op)
        guard !op.accepted, op.decision == nil, !op.cancelling, op.terminal == nil else { callback.resolve(nil); return }
        op.decision = callback
        guard op.details != nil else { cancel(op.id); return }
        if item.isComplete || item.isCanceled || item.isInterrupted { terminal(item, key: key, op: op); return }
        emit(op)
        guard installed(op), !op.cancelling, op.terminal == nil else { return }
        switch op.owner.policy {
        case .directory(let folder):
            accept(op, destination: folder.appendingPathComponent(op.details!.suggestedName), chooseUnused: true)
        case .ask(let folder):
            let ticket = DestinationTicket(download: op.id, generation: op.revision)
            op.ticket = ticket
            prompt(DownloadDestinationPrompt(ticket: ticket, window: op.owner.window, directory: folder,
                                             suggestedName: op.details!.suggestedName)) { [weak self] answer in
                self?.answer(ticket, answer)
            }
        }
    }

    func update(_ item: CefDownload, owner: DownloadOwner, available: @escaping () -> Bool, control: (any TransferControl)?) {
        let key = Key(browser: owner.browser, native: item.id)
        if tombstones.contains(key) { control?.release(); return }
        guard let op = operation(key, owner: owner, sourceAvailable: available) else { control?.cancel(); control?.release(); return }
        let oldControl = op.control; op.control = nil
        oldControl?.release()
        guard installed(op) else { control?.release(); return }
        op.control = control
        capture(item, in: op)
        if item.isComplete || item.isCanceled || item.isInterrupted {
            terminal(item, key: key, op: op)
        } else {
            if op.cancelling { op.control?.cancel() }
            emit(op)
        }
    }

    func answer(_ ticket: DestinationTicket, _ answer: DestinationAnswer) {
        guard let key = ids[ticket.download], let op = operations[key], op.ticket == ticket,
              !op.accepted, !op.cancelling, op.terminal == nil else { return }
        op.ticket = nil
        dismiss(ticket)
        guard running, !revoked.contains(op.owner.context.context), op.sourceAvailable() else { cancel(op.id); return }
        switch answer {
        case .accepted(let destination): accept(op, destination: destination, chooseUnused: false)
        case .cancelled, .ownerGone: cancel(op.id)
        }
    }

    private func accept(_ op: Operation, destination: URL, chooseUnused: Bool) {
        guard installed(op) else { return }
        guard running, !revoked.contains(op.owner.context.context), op.sourceAvailable(), !op.cancelling, op.terminal == nil else {
            cancel(op.id); return
        }
        do {
            let files = try TransferFiles(destination: destination, chooseUnused: chooseUnused)
            op.files = files
            op.accepted = true
            let decision = op.decision; op.decision = nil
            decision?.resolve(files.staging)
            emit(op)
        } catch {
            op.failure = "Could not prepare the destination: " + error.localizedDescription
            cancel(op.id)
        }
    }

    func cancel(_ id: DownloadID) {
        guard let key = ids[id], let op = operations[key], op.terminal == nil, !op.cancelling else { return }
        op.cancelling = true
        emit(op)
        guard installed(op) else { return }
        let decision = op.decision; op.decision = nil
        if let ticket = op.ticket { op.ticket = nil; dismiss(ticket) }
        decision?.resolve(nil)
        op.control?.cancel()
    }

    func sourceGone(_ browser: BrowserToken) {
        for op in Array(operations.values) where op.owner.browser == browser && !op.accepted { cancel(op.id) }
    }
    func revoke(_ context: BrowsingContext) {
        revoked.insert(context)
        for op in Array(operations.values) where op.owner.context.context == context { cancel(op.id) }
    }
    func stop() {
        running = false
        for id in Array(ids.keys) { cancel(id) }
    }

    private func terminal(_ item: CefDownload, key: Key, op: Operation) {
        let end: DownloadEnd
        if op.terminal != nil {
            // Retain the recovery directory named by the timeout result, even after the writer stops.
            // This callback permits reference/lease release, not a second terminal result.
            finish(key, op: op, end: op.terminal!)
            return
        }
        if item.isComplete {
            if let files = op.files {
                do { end = .completed(try files.commit()) }
                catch let error as TransferFiles.CommitCleanupError {
                    end = .failed(reason: "The file was saved, but temporary files could not be removed: " + error.reason,
                                  .retained(error.receipt.url, reason: "Temporary files remain at " + error.directory.path))
                }
                catch { end = .failed(reason: "Destination commit failed: " + error.localizedDescription,
                                     .retained(files.directory, reason: "Completed bytes await recovery")) }
            } else { end = .failed(reason: "Completion without an owned destination", .unknown) }
        } else {
            let partial = op.files?.cleanup() ?? .absent
            if let failure = op.failure { end = .failed(reason: failure, partial) }
            else if case .retained = partial { end = .failed(reason: "Partial file cleanup failed", partial) }
            else if item.isInterrupted { end = .interrupted(reason: "Download interrupted (error \(item.interruptionReason))", partial) }
            else { end = .cancelled(partial) }
        }
        finish(key, op: op, end: end)
    }

    private func finish(_ key: Key, op: Operation, end: DownloadEnd) {
        guard operations[key] === op else { return }
        op.terminal = end
        // Set the tombstone before resolving/releasing callbacks, which may synchronously reenter.
        tombstones.insert(key)
        operations[key] = nil; ids[op.id] = nil
        if let ticket = op.ticket { op.ticket = nil; dismiss(ticket) }
        let decision = op.decision; op.decision = nil; decision?.resolve(nil)
        let control = op.control; op.control = nil; control?.release()
        emit(op)
        release(op.id, key.browser)
    }

    func browserClosed(_ browser: BrowserToken) {
        for (key, op) in Array(operations) where key.browser == browser {
            if op.terminal == nil { cancel(op.id) }
            // Mandatory native closure is not proof that a download writer has acknowledged termination.
            // A synchronous terminal callback may have already finished this operation during cancel.
            let recovery = op.files.map { PartialFile.retained($0.directory, reason: "Partial files were kept because download termination could not be confirmed") } ?? .absent
            finish(key, op: op, end: op.terminal ?? .failed(reason: "The page closed before the download finished", recovery))
        }
        tombstones = tombstones.filter { $0.browser != browser }
    }

    /// A timeout is not a writer barrier. Keep callbacks, files and leases for recovery/drain.
    func reportTimeout(context: BrowsingContext? = nil) {
        for op in operations.values where context == nil || op.owner.context.context == context {
            guard op.terminal == nil else { continue }
            op.terminal = .failed(reason: "The download did not finish cancelling",
                                 op.files.map { .retained($0.directory, reason: "Partial files kept for recovery") } ?? .unknown)
            emit(op)
        }
    }

    private func emit(_ op: Operation) {
        guard let details = op.details else { return }
        if op.terminal != nil {
            guard !op.terminalPublished else { return }
            op.terminalPublished = true
        } else {
            guard installed(op) else { return }
        }
        op.revision += 1
        let stage: DownloadStage = if let end = op.terminal { .terminal(end) }
            else if op.cancelling { .cancelling(op.progress) }
            else if op.accepted { .receiving(op.progress) }
            else { .choosingDestination }
        publish(DownloadUpdate(id: op.id, owner: op.owner, details: details, revision: op.revision, stage: stage))
    }
}
