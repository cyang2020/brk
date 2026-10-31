import BrkBase
import BrkDomain
import Foundation
import Darwin

// The AI stand-in seam (user decision: AI features run the user's local `claude` or `codex` command-line tool;
// no API keys). The domain asks with `Effect.ai(id, task, choice:)`; this file finds the tools, builds the prompt
// for a task, runs the tool non-interactively, and answers with `SystemEvent.aiResult(id, outcome)`.
//
// Owner: wave 2 contract; the Max features of a later wave fill `AIPrompt` per task. Nothing here reads the tree.

/// Something that answers a prompt with text.
@MainActor
public protocol AIProvider: AnyObject {
    var kind: AIProviderKind { get }
    /// Runs `prompt` to completion and returns the tool's text. Throws when the tool fails or times out.
    func run(_ prompt: String) async throws -> String
    func run(_ prompt: String, onPartial: @escaping @MainActor @Sendable (String) -> Void) async throws -> String
}

/// Which executables the Max pane can offer and `.auto` picks from.
public enum AIProviderSeam {
    /// The usual Homebrew and npm bins, searched after PATH because a GUI app's PATH is short.
    public static var fallbackDirectories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin"]
    }

    /// The tools found on PATH and in `fallbackDirectories`, in `AIProviderKind.allCases` order.
    public static func detect(environment: [String: String] = ProcessInfo.processInfo.environment,
                              alsoIn fallback: [String] = fallbackDirectories) -> [AIProviderKind] {
        AIProviderKind.allCases.filter { executable(for: $0, environment: environment, alsoIn: fallback) != nil }
    }

    /// The executable for a tool, or nil when it is not installed.
    public static func executable(for kind: AIProviderKind, environment: [String: String] = ProcessInfo.processInfo.environment,
                                  alsoIn fallback: [String] = fallbackDirectories) -> URL? {
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = path + fallback
        for directory in candidates {
            let url = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(kind.rawValue)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// The provider a choice resolves to, given what was detected; nil means `.unavailable`.
    @MainActor
    public static func provider(for choice: AIProviderChoice, detected: [AIProviderKind]) -> (any AIProvider)? {
        let kind: AIProviderKind? = switch choice {
        case .off: nil
        case .claude: detected.contains(.claude) ? .claude : nil
        case .codex: detected.contains(.codex) ? .codex : nil
        case .auto: detected.first
        }
        guard let kind, let executable = executable(for: kind) else { return nil }
        return CLIProvider(kind: kind, executable: executable)
    }

    /// Runs one request end to end and returns the outcome the reducer applies.
    @MainActor
    public static func answer(_ task: AITask, choice: AIProviderChoice, detected: [AIProviderKind]) async -> AIOutcome {
        guard let provider = provider(for: choice, detected: detected) else { return .unavailable }
        do { return .text(try await provider.run(AIPrompt.text(for: task))) } catch { return .failed("\(error)") }
    }
}

/// The prompts, one per task. TODO(later wave): Arc's wording per Max feature; tidyToday's JSON plan contract.
public enum AIPrompt {
    public static func text(for task: AITask) -> String {
        switch task {
        case .renameTab(_, let title, let url):
            return "Give a short, tidy title (at most 5 words, no quotes, no trailing punctuation) for this browser tab.\nTitle: \(title)\nURL: \(url.absoluteString)\nAnswer with the title only."
        case .tidyToday(_, let tabs):
            let list = tabs.map { "- \($0.id.rawValue): \($0.title) <\($0.url.absoluteString)>" }.joined(separator: "\n")
            return "Group these browser tabs into a few folders by topic. Answer with JSON only: [{\"folder\": \"name\", \"tabs\": [\"id\", ...]}].\n\(list)"
        case .ask(let question):
            return question
        }
    }
}

/// One process per request. Both pipes drain while it runs; cancellation and the deadline terminate it.
@MainActor
public final class CLIProvider: AIProvider {
    public let kind: AIProviderKind
    public let executable: URL
    public var timeout: Duration = .seconds(120)

    public init(kind: AIProviderKind, executable: URL) {
        self.kind = kind
        self.executable = executable
    }

    public func run(_ prompt: String) async throws -> String {
        try await run(prompt, onPartial: { _ in })
    }

    public func run(_ prompt: String, onPartial: @escaping @MainActor @Sendable (String) -> Void) async throws -> String {
        let arguments: [String] = switch kind {
        case .claude: ["-p", prompt, "--output-format", "text", "--tools", "", "--no-session-persistence", "--disable-slash-commands"]
        case .codex: ["exec", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only", prompt]
        }
        let run = CLIExecution(executable: executable, arguments: arguments, partial: onPartial)
        let deadline = Task {
            do { try await Task.sleep(for: timeout); run.stop(.timedOut) } catch {}
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in run.start(continuation) }
        } onCancel: { run.stop(.cancelled) }
    }
}

/// Foundation's process and pipe handles are confined to this owner. The lock serializes launch/stop/exit;
/// separate readers own their individual pipes. No blocking reads or waits run on the main actor.
private final class CLIExecution: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var stopped: AIProviderError?
    private var finished = false
    private let stdout = Pipe(), stderr = Pipe()
    private let partial: @MainActor @Sendable (String) -> Void
    private static let outputLimit = 1_048_576

    init(executable: URL, arguments: [String], partial: @escaping @MainActor @Sendable (String) -> Void) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        self.partial = partial
    }

    func stop(_ reason: AIProviderError) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        if stopped == nil { stopped = reason }
        if process.isRunning {
            let pid = process.processIdentifier
            // Kill descendants before their parent can exit and orphan them with inherited pipe writers.
            Self.signalDescendants(of: pid, signal: SIGTERM)
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) { [self] in
                lock.lock(); defer { lock.unlock() }
                guard !finished, process.isRunning else { return }
                Self.signalDescendants(of: pid, signal: SIGKILL)
                kill(pid, SIGKILL)
            }
        }
        lock.unlock()
    }

    private static func signalDescendants(of pid: pid_t, signal: Int32) {
        var children = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listchildpids(pid, &children, Int32(children.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return }
        for child in children.prefix(Int(bytes) / MemoryLayout<pid_t>.size) where child > 0 {
            signalDescendants(of: child, signal: signal)
            kill(child, signal)
        }
    }

    func start(_ continuation: CheckedContinuation<String, any Error>) {
        DispatchQueue.global(qos: .utility).async { [self] in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-ai-" + UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                lock.lock()
                if let stopped { finished = true; lock.unlock(); throw stopped }
                process.currentDirectoryURL = directory
                do { try process.run(); lock.unlock() } catch { finished = true; lock.unlock(); throw error }
                let output = CLIBytes(), errors = CLIBytes()
                let readers = DispatchGroup()
                for (pipe, buffer, streams) in [(stdout, output, true), (stderr, errors, false)] {
                    readers.enter()
                    DispatchQueue.global(qos: .utility).async { [self] in
                        defer { readers.leave() }
                        while true {
                            let data = pipe.fileHandleForReading.availableData
                            if data.isEmpty { break }
                            if !buffer.append(data, limit: streams ? Self.outputLimit : 16_384) {
                                if streams { stop(.tooMuchOutput) }
                            }
                            if streams {
                                let text = String(decoding: buffer.value(), as: UTF8.self)
                                Task { @MainActor [partial] in partial(text) }
                            }
                        }
                    }
                }
                process.waitUntilExit()
                readers.wait()
                try? stdout.fileHandleForReading.close()
                try? stderr.fileHandleForReading.close()
                lock.lock()
                finished = true
                let failure = stopped
                lock.unlock()
                if let failure { throw failure }
                guard process.terminationStatus == 0 else {
                    throw AIProviderError.failed(status: process.terminationStatus, stderr: String(decoding: errors.value(), as: UTF8.self))
                }
                continuation.resume(returning: String(decoding: output.value(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
            } catch { continuation.resume(throwing: error) }
        }
    }
}

private final class CLIBytes: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ next: Data, limit: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let fits = next.count <= limit - data.count
        data.append(next.prefix(max(0, limit - data.count)))
        return fits
    }
    func value() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

public enum AIProviderError: Error, CustomStringConvertible, Sendable {
    case timedOut, cancelled, tooMuchOutput
    case failed(status: Int32, stderr: String)

    public var description: String {
        switch self {
        case .timedOut: "The AI tool timed out and was stopped. Try a shorter request."
        case .cancelled: "AI request cancelled."
        case .tooMuchOutput: "The AI tool exceeded the 1 MB answer limit and was stopped."
        case .failed(let status, let stderr): "The AI tool exited with status \(status): \(stderr.prefix(200)). Check its sign-in in Terminal, then retry."
        }
    }
}
