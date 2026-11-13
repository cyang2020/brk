import BrkBase
import Foundation
import PDFKit

/// Document output owns its callbacks and browser lease until the actual renderer/writer has drained.
@MainActor final class DocumentOutputs {
    private final class Operation {
        let request: OutputRequest
        let context: ContextEpoch
        var files: TransferFiles?
        var stage: OutputStage = .choosingDestination
        var cancelRequested = false
        var terminal = false
        var rendering = false
        var printing = false
        var leased = true
        var timedOut = false
        var timeout: Timer?
        var printDirectory: URL?
        init(_ request: OutputRequest, context: ContextEpoch) { self.request = request; self.context = context }
    }
    private var operations: [OutputID: Operation] = [:]
    private var seen: Set<OutputID> = []
    var acquire: (OutputID, BrowserToken) -> Bool = { _, _ in false }
    var release: (OutputID, BrowserToken) -> Void = { _, _ in }
    var available: (OutputRequest, ContextEpoch) -> Bool = { _, _ in false }
    var render: (OutputRequest, URL, @escaping (Result<Void, Error>) -> Void) -> Void = { _, _, done in done(.failure(CocoaError(.featureUnsupported))) }
    var publish: (OutputUpdate) -> Void = { _ in }
    var destination: (OutputDestinationPrompt, @escaping @MainActor (DestinationAnswer) -> Void) -> Void = { _, done in done(.ownerGone) }
    var print: (OutputRequest, URL, @escaping @MainActor (PrintAnswer) -> Void) -> Void = { _, _, done in done(.ownerGone) }
    var dismiss: (OutputID) -> Void = { _ in }
    /// How long the native rendering may take before the output is reported failed.
    var timeLimit: TimeInterval = 60
    var isEmpty: Bool { operations.isEmpty }
    func contains(_ id: OutputID) -> Bool { operations[id] != nil }
    func permitsRender(_ id: OutputID) -> Bool {
        guard let operation = operations[id] else { return false }
        return current(operation) && operation.rendering && !operation.cancelRequested
            && available(operation.request, operation.context)
    }
    func contains(context: BrowsingContext) -> Bool { operations.values.contains { $0.context.context == context } }

    func start(_ request: OutputRequest, context: ContextEpoch) {
        guard seen.insert(request.id).inserted else { return }
        guard available(request, context), acquire(request.id, request.document.browser) else {
            publish(OutputUpdate(id: request.id, document: request.document, stage: .terminal(.failed("Document is no longer available", .absent))))
            return
        }
        let operation = Operation(request, context: context)
        operations[request.id] = operation
        if request.intent == .print {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-output-" + UUID().uuidString, isDirectory: true)
            operation.printDirectory = directory
            answer(.accepted(directory.appendingPathComponent("document.pdf")), operation)
        } else {
            update(operation, .choosingDestination)
            guard current(operation) else { return }
            destination(OutputDestinationPrompt(request: request)) { [weak self, weak operation] answer in
                guard let self, let operation else { return }; self.answer(answer, operation)
            }
        }
    }

    private func answer(_ answer: DestinationAnswer, _ operation: Operation) {
        guard current(operation), !operation.rendering, operation.files == nil else { return }
        guard available(operation.request, operation.context), case .accepted(let url) = answer else {
            finish(operation, .cancelled(.absent)); return
        }
        do { operation.files = try TransferFiles(destination: url, chooseUnused: false) }
        catch { finish(operation, .failed(error.localizedDescription, .absent)); return }
        operation.rendering = true
        update(operation, .rendering)
        // Publication may synchronously revoke the context or close the owner.
        guard current(operation), !operation.cancelRequested, available(operation.request, operation.context) else {
            operation.rendering = false
            finish(operation, .cancelled(cleanup(operation))); return
        }
        // Only the native rendering is timed: the save and print panels wait for the person as long as they take.
        let id = operation.request.id
        operation.timeout = Timer.scheduledTimer(withTimeInterval: timeLimit, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportTimeout(id) }
        }
        render(operation.request, operation.files!.staging) { [weak self, weak operation] result in
            guard let self, let operation, self.current(operation) else { return }
            operation.rendering = false
            operation.timeout?.invalidate()
            self.rendered(result, operation)
        }
    }

    private func rendered(_ result: Result<Void, Error>, _ operation: Operation) {
        guard current(operation), let files = operation.files else { return }
        if operation.cancelRequested || !available(operation.request, operation.context) {
            finish(operation, .cancelled(cleanup(operation))); return
        }
        if case .failure(let error) = result {
            finish(operation, .failed(error.localizedDescription, cleanup(operation))); return
        }
        do {
            try Self.validate(files.staging, intent: operation.request.intent)
            if operation.request.intent == .print {
                releaseLease(operation)
                operation.printing = true
                update(operation, .printing)
                guard current(operation), !operation.cancelRequested, available(operation.request, operation.context) else {
                    finish(operation, .cancelled(cleanup(operation))); return
                }
                print(operation.request, files.staging) { [weak self, weak operation] answer in
                    guard let self, let operation, self.current(operation) else { return }
                    operation.printing = false
                    let partial = self.cleanup(operation)
                    switch answer {
                    case .submitted: self.finish(operation, .submittedToPrintSystem)
                    case .cancelled, .ownerGone: self.finish(operation, .cancelled(partial))
                    case .failed(let error): self.finish(operation, .failed(error, partial))
                    }
                }
            } else {
                let receipt = try files.commit()
                finish(operation, .saved(receipt))
            }
        } catch let error as TransferFiles.CommitCleanupError {
            // A committed file is saved even when removal of its private staging directory failed.
            finish(operation, .failed("Saved at \(error.receipt.url.path); cleanup failed: \(error.reason)", .retained(error.directory, reason: error.reason)))
        } catch {
            // Validation/commit failure may include an intervening destination change. Preserve evidence/recovery.
            finish(operation, .failed(error.localizedDescription, .retained(files.directory, reason: "Output retained for recovery")))
        }
    }

    func cancel(_ id: OutputID) {
        guard let operation = operations[id], !operation.terminal, !operation.cancelRequested else { return }
        operation.cancelRequested = true
        update(operation, .cancelling)
        guard current(operation) else { return }
        dismiss(id)
        guard current(operation) else { return }
        // print_to_pdf has no cancellation call. Hold its lease and files until the real callback drains.
        if !operation.rendering && !operation.printing { finish(operation, .cancelled(cleanup(operation))) }
    }
    func sourceGone(_ browser: BrowserToken) { for operation in Array(operations.values) where operation.request.document.browser == browser { cancel(operation.request.id) } }
    func documentChanged(_ document: DocumentToken?) {
        for operation in Array(operations.values) where operation.request.document == document { cancel(operation.request.id) }
    }
    func revoke(_ context: BrowsingContext) { for operation in Array(operations.values) where operation.context.context == context { cancel(operation.request.id) } }
    func stop() { for id in Array(operations.keys) { cancel(id) } }

    private func current(_ operation: Operation) -> Bool { operations[operation.request.id] === operation && !operation.terminal }
    private func update(_ operation: Operation, _ stage: OutputStage) {
        operation.stage = stage
        publish(OutputUpdate(id: operation.request.id, document: operation.request.document, stage: stage))
    }
    private func cleanup(_ operation: Operation) -> PartialFile {
        // A print's PDF is only there for the print panel; nothing is recovered from it, timed out or not.
        if operation.timedOut, operation.printDirectory == nil, let directory = operation.files?.directory {
            return .retained(directory, reason: "Output timed out; retained for recovery")
        }
        let result = operation.files?.cleanup() ?? .absent
        if let directory = operation.printDirectory {
            do { try FileManager.default.removeItem(at: directory) }
            catch { if FileManager.default.fileExists(atPath: directory.path) { return .retained(directory, reason: error.localizedDescription) } }
        }
        return result
    }
    private func finish(_ operation: Operation, _ result: OutputResult) {
        guard current(operation) else { return }
        operation.terminal = true
        operation.timeout?.invalidate()
        operations[operation.request.id] = nil
        dismiss(operation.request.id)
        releaseLease(operation)
        if !operation.timedOut { publish(OutputUpdate(id: operation.request.id, document: operation.request.document, stage: .terminal(result))) }
    }

    func reportTimeout(_ id: OutputID? = nil) {
        for operation in Array(operations.values) where id == nil || operation.request.id == id {
            guard !operation.timedOut else { continue }
            operation.timedOut = true
            operation.cancelRequested = true
            operation.timeout?.invalidate()
            // A print's folder is deleted once the renderer or the print panel answers (cleanup), so it is not named.
            let file: PartialFile = operation.printDirectory != nil ? .absent
                : operation.files.map { .retained($0.directory, reason: "Native output has not drained") } ?? .absent
            dismiss(operation.request.id)
            publish(OutputUpdate(id: operation.request.id, document: operation.request.document, stage: .terminal(.failed("Output did not finish; native resources remain owned until completion", file))))
            if !operation.rendering && !operation.printing { finish(operation, .failed("Output timed out", file)) }
        }
    }

    private func releaseLease(_ operation: Operation) {
        guard operation.leased else { return }
        operation.leased = false
        release(operation.request.id, operation.request.document.browser)
    }

    static func validate(_ url: URL, intent: OutputIntent) throws {
        if intent == .mhtml {
            // The MIME header is at the top. A page's MHTML can run to tens of MB, and this runs on the main thread.
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let text = String(decoding: try handle.read(upToCount: 1_048_576) ?? Data(), as: UTF8.self)
            guard text.lowercased().contains("multipart/related"), text.contains("Content-Location:"), text.contains("boundary=") else { throw CocoaError(.fileReadCorruptFile) }
        } else {
            guard let document = PDFDocument(url: url), document.pageCount > 0,
                  document.page(at: 0)?.bounds(for: .mediaBox).isEmpty == false else { throw CocoaError(.fileReadCorruptFile) }
        }
    }
}
