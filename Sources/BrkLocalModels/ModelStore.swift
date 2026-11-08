import CryptoKit
import Foundation

/// Where a model stands on this Mac.
public enum ModelInstall: Hashable, Sendable {
    case absent
    case downloading(received: Int64, total: Int64)
    case verifying
    case ready
    case failed(String)

    public var isReady: Bool { self == .ready }
    public var isBusy: Bool {
        switch self {
        case .downloading, .verifying: true
        default: false
        }
    }
}

/// The downloaded models under `<data>/Local Models/<model id>/`. A file is used only after its SHA-256 matched the
/// catalog's; the digest is then written next to it so later launches check the size and the stored digest instead of
/// reading gigabytes again. A stopped download keeps its resume data and continues where it stopped.
@MainActor
public final class ModelStore {
    public let root: URL
    public private(set) var states: [String: ModelInstall] = [:]
    /// Called after every change of a model's state, on the main actor.
    public var onChange: (@MainActor (String, ModelInstall) -> Void)?

    private let fileManager = FileManager.default
    private var transfers: [String: Transfer] = [:]
    private let models: [LocalModel]

    public init(root: URL, models: [LocalModel] = ModelCatalog.all) {
        self.root = root
        self.models = models
        for model in models { states[model.id] = installed(model) ? .ready : .absent }
    }

    public func state(_ model: LocalModel) -> ModelInstall { states[model.id] ?? .absent }

    /// The model's file when it is ready to load.
    public func file(_ model: LocalModel) -> URL? { state(model).isReady ? fileURL(model) : nil }

    public func fileURL(_ model: LocalModel) -> URL { folder(model).appendingPathComponent(model.file.name) }
    func folder(_ model: LocalModel) -> URL { root.appendingPathComponent(model.id, isDirectory: true) }
    private func digestURL(_ model: LocalModel) -> URL { folder(model).appendingPathComponent(model.file.name + ".sha256") }
    private func resumeURL(_ model: LocalModel) -> URL { folder(model).appendingPathComponent("download.resume") }

    func installed(_ model: LocalModel) -> Bool {
        let file = fileURL(model)
        guard let size = (try? fileManager.attributesOfItem(atPath: file.path))?[.size] as? NSNumber, size.int64Value == model.file.bytes,
              let digest = try? String(contentsOf: digestURL(model), encoding: .utf8) else { return false }
        return digest.trimmingCharacters(in: .whitespacesAndNewlines) == model.file.sha256
    }

    /// Bytes this store holds on disk (finished files and partial downloads).
    public var bytesOnDisk: Int64 {
        guard let walker = fileManager.enumerator(at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    /// Starts or continues the download. Only called after the user agreed on the model's card.
    public func download(_ model: LocalModel) {
        guard !state(model).isBusy, !state(model).isReady else { return }
        do {
            try fileManager.createDirectory(at: folder(model), withIntermediateDirectories: true)
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        } catch {
            set(model, .failed("Cannot create \(folder(model).path): \(error.localizedDescription)"))
            return
        }
        if let free = freeBytes(), free < model.file.bytes + 512 * 1_048_576 {
            set(model, .failed("Not enough free disk space: \(Self.size(model.file.bytes)) and some room to spare are needed."))
            return
        }
        let resume = try? Data(contentsOf: resumeURL(model))
        try? fileManager.removeItem(at: resumeURL(model))
        let transfer = Transfer(model: model, destination: fileURL(model).appendingPathExtension("partial")) { [weak self] event in
            Task { @MainActor in self?.handle(event, for: model) }
        }
        transfers[model.id] = transfer
        set(model, .downloading(received: 0, total: model.file.bytes))
        transfer.start(resume: resume)
    }

    /// Stops a download and keeps what arrived, so the next Download continues.
    public func cancel(_ model: LocalModel) {
        guard let transfer = transfers.removeValue(forKey: model.id) else { return }
        transfer.cancel { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                if let data { try? data.write(to: self.resumeURL(model), options: .atomic) }
                self.set(model, .absent)
            }
        }
    }

    /// Deletes the model's folder: the file, its digest and any partial download.
    public func remove(_ model: LocalModel) {
        transfers.removeValue(forKey: model.id)?.cancel { _ in }
        try? fileManager.removeItem(at: folder(model))
        set(model, .absent)
    }

    private func handle(_ event: Transfer.Event, for model: LocalModel) {
        guard transfers[model.id] != nil else { return }
        switch event {
        case .progress(let received, let total):
            set(model, .downloading(received: received, total: total > 0 ? total : model.file.bytes))
        case .failed(let message, let resume):
            transfers[model.id] = nil
            if let resume { try? resume.write(to: resumeURL(model), options: .atomic) }
            set(model, .failed(message))
        case .finished(let partial):
            transfers[model.id] = nil
            set(model, .verifying)
            let expected = model.file.sha256, bytes = model.file.bytes
            let final = fileURL(model), digest = digestURL(model)
            Task.detached(priority: .utility) {
                let outcome = Self.verify(partial, bytes: bytes, sha256: expected, into: final, digest: digest)
                await MainActor.run { self.set(model, outcome) }
            }
        }
    }

    nonisolated static func verify(_ partial: URL, bytes: Int64, sha256: String, into final: URL, digest: URL) -> ModelInstall {
        let fileManager = FileManager.default
        do {
            let size = (try fileManager.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value ?? -1
            guard size == bytes else {
                try? fileManager.removeItem(at: partial)
                return .failed("The download has \(size) bytes, \(bytes) were expected. It was deleted.")
            }
            let found = try Self.sha256(of: partial)
            guard found == sha256 else {
                try? fileManager.removeItem(at: partial)
                return .failed("The downloaded file is not the published one (SHA-256 \(found.prefix(12))…). It was deleted.")
            }
            try? fileManager.removeItem(at: final)
            try fileManager.moveItem(at: partial, to: final)
            try sha256.write(to: digest, atomically: true, encoding: .utf8)
            return .ready
        } catch {
            return .failed("The model could not be saved: \(error.localizedDescription)")
        }
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func freeBytes() -> Int64? {
        let probe = fileManager.fileExists(atPath: root.path) ? root : root.deletingLastPathComponent()
        return (try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    private func set(_ model: LocalModel, _ state: ModelInstall) {
        guard states[model.id] != state else { return }
        states[model.id] = state
        onChange?(model.id, state)
    }

    /// "310 MB", "2.71 GB": decimal units rounded as the model pages print them.
    public static func size(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value >= 1e9 { return String(format: "%.2f GB", value / 1e9) }
        if value >= 1e6 { return String(format: "%.0f MB", value / 1e6) }
        return String(format: "%.0f KB", max(1, value / 1e3))
    }
}

/// One URLSession download with its own session, so progress and resume data stay with it.
final class Transfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case progress(Int64, Int64)
        case finished(URL)
        case failed(String, Data?)
    }

    private let model: LocalModel
    private let destination: URL
    private let report: @Sendable (Event) -> Void
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var lastReport: UInt64 = 0
    private var cancelled = false

    init(model: LocalModel, destination: URL, report: @escaping @Sendable (Event) -> Void) {
        self.model = model
        self.destination = destination
        self.report = report
    }

    func start(resume: Data?) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = resume.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: model.file.url)
        lock.withLock { self.session = session; self.task = task }
        task.resume()
    }

    func cancel(_ done: @escaping @Sendable (Data?) -> Void) {
        let task = lock.withLock { () -> URLSessionDownloadTask? in cancelled = true; return self.task }
        guard let task else { done(nil); return }
        task.cancel { [weak self] data in
            self?.lock.withLock { self?.session }?.finishTasksAndInvalidate()
            done(data)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = DispatchTime.now().uptimeNanoseconds
        let due = lock.withLock { () -> Bool in
            guard now - lastReport > 200_000_000 else { return false }
            lastReport = now
            return true
        }
        if due { report(.progress(totalBytesWritten, totalBytesExpectedToWrite)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            report(.failed("The server answered \(response.statusCode).", nil))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            report(.finished(destination))
        } catch {
            report(.failed("The download could not be kept: \(error.localizedDescription)", nil))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        session.finishTasksAndInvalidate()
        guard let error, !lock.withLock({ cancelled }) else { return }
        let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        report(.failed("The download stopped: \(error.localizedDescription)", resume))
    }
}
