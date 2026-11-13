import BrkEngine
import Foundation

extension CoreEngine {
    public func beginTrace() async -> Bool {
        isRunning && runtime.application.beginTrace()
    }

    public func endTrace(writingTo file: URL?) async -> URL? {
        guard isRunning else { return nil }
        let target = file ?? FileManager.default.temporaryDirectory.appendingPathComponent("brk-trace-\(UUID().uuidString).json")
        let written = await withCheckedContinuation { continuation in
            runtime.application.endTrace(atPath: target.path) { continuation.resume(returning: $0) }
        }
        if file == nil { try? FileManager.default.removeItem(at: target); return nil }
        return written ? target : nil
    }

    public func tasks() -> [EngineTask] {
        guard isRunning else { return [] }
        return runtime.application.tasks().compactMap { row in
            guard let id = row["id"] as? NSNumber, let title = row["title"] as? String else { return nil }
            return EngineTask(id: id.int64Value, kind: EngineTask.Kind(rawValue: row["kind"] as? String ?? "") ?? .unknown,
                              title: title, cpu: (row["cpu"] as? NSNumber)?.doubleValue,
                              memory: (row["memory"] as? NSNumber)?.int64Value,
                              gpuMemory: (row["gpuMemory"] as? NSNumber)?.int64Value,
                              killable: row["killable"] as? Bool ?? false)
        }
    }

    public func endTask(_ id: Int64) -> Bool {
        isRunning && runtime.application.endTask(id)
    }
}
