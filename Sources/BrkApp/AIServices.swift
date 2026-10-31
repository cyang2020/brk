import BrkBase
import BrkDomain
import BrkEngine
import Foundation

/// Effect resources only. Request state and hidden page demand remain in the reducer's session.
@MainActor
final class AIServices {
    private let engine: any WebEngine
    private let send: (SystemEvent) -> Void
    private var tasks: [AIRequestID: [UUID: Task<Void, Never>]] = [:]
    private var deadlines: [AIRequestID: Task<Void, Never>] = [:]
    private var hovers: [WindowID: Task<Void, Never>] = [:]
    private var renames: [DownloadID: Task<Void, Never>] = [:]
    private var stopping = false
    init(engine: any WebEngine, send: @escaping (SystemEvent) -> Void) { self.engine = engine; self.send = send }

    private func start(_ id: AIRequestID, _ operation: @escaping @MainActor () async -> Void) {
        guard !stopping else { return }
        let token = UUID()
        tasks[id, default: [:]][token] = Task { [weak self] in
            await operation()
            self?.tasks[id]?[token] = nil
            if self?.tasks[id]?.isEmpty == true { self?.tasks[id] = nil }
        }
    }
    func answer(_ id: AIRequestID, task: AITask, choice: AIProviderChoice, detected: [AIProviderKind]) {
        start(id) { [weak self] in
            let result = await AIProviderSeam.answer(task, choice: choice, detected: detected, onPartial: { [weak self] text in self?.send(.aiPartial(id, text)) })
            guard !Task.isCancelled else { return }
            self?.send(.aiResult(id, result))
        }
    }
    func read(_ id: AIRequestID, document: DocumentToken) {
        start(id) { [weak self] in
            guard let self else { return }
            let content = try? await engine.readAIPage(document)
            guard !Task.isCancelled else { return }
            send(.aiPageRead(id, document.browser.page, content))
        }
    }
    func translate(_ id: AIRequestID, content: AIPageContent, nodes: [AITextNode]) {
        start(id) { [weak self] in
            guard let self else { return }
            let success = (try? await engine.translateAIPage(content, replacements: nodes)) ?? false
            guard !Task.isCancelled else { return }
            send(.aiTranslated(id, success))
        }
    }
    func watch(_ id: AIRequestID, seconds: Int) {
        deadlines.removeValue(forKey: id)?.cancel()
        guard !stopping else { return }
        deadlines[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.send(.aiDeadline(id))
        }
    }
    func hover(_ window: WindowID, url: URL?) {
        hovers.removeValue(forKey: window)?.cancel()
        guard let url, !stopping else { return }
        hovers[window] = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            self?.send(.aiHoverReady(window, url))
        }
    }
    func cancel(_ id: AIRequestID) {
        for task in tasks[id]?.values ?? [:].values { task.cancel() }
        deadlines.removeValue(forKey: id)?.cancel()
    }
    func cancelAll() {
        stopping = true
        for task in tasks.values.flatMap({ $0.values }) { task.cancel() }
        for task in deadlines.values { task.cancel() }
        for task in hovers.values { task.cancel() }
        deadlines.removeAll(); hovers.removeAll()
    }
    func stop() async {
        let running = tasks.values.flatMap { $0.values }
        cancelAll()
        for task in running { await task.value }
        for task in Array(renames.values) { await task.value }
        tasks.removeAll(); renames.removeAll()
    }
    func rename(_ id: DownloadID, path: String, filename: String) {
        guard renames[id] == nil, !stopping else { return }
        renames[id] = Task { [weak self] in
            defer { self?.renames[id] = nil }
            do {
                let result = try await Task.detached(priority: .utility) { try AIRenameFiles.move(path: path, filename: filename) }.value
                self?.send(.aiDownloadRenamed(id, originalPath: path, newPath: result, error: nil))
            } catch { self?.send(.aiDownloadRenamed(id, originalPath: path, newPath: nil, error: "Could not rename the downloaded file. Check folder permissions and retry.")) }
        }
    }
}

enum AIRenameFiles {
    static func move(path: String, filename: String) throws -> String {
        let source = URL(fileURLWithPath: path)
        guard filename == (filename as NSString).lastPathComponent,
              AIValidation.filename(filename, original: source.lastPathComponent) == filename,
              (try FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeRegular else { throw CocoaError(.fileWriteInvalidFileName) }
        if filename == source.lastPathComponent { return path }
        let name = filename as NSString, ext = name.pathExtension, stem = name.deletingPathExtension
        for suffix in 0..<1000 {
            let next = suffix == 0 ? filename : stem + " (\(suffix))" + (ext.isEmpty ? "" : "." + ext)
            let destination = source.deletingLastPathComponent().appendingPathComponent(next).path
            if renamex_np(path, destination, UInt32(RENAME_EXCL)) == 0 { return destination }
            guard errno == EEXIST else { throw CocoaError(.fileWriteUnknown) }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
