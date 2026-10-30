import BrkBase
import BrkDomain
import Foundation
import os

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

/// Runs `claude -p <prompt>` or `codex exec <prompt>` with no interaction and no network of its own beyond what the
/// tool does; stdin closed, stdout collected, bounded by `timeout`. TODO(later wave): stream partial output.
@MainActor
public final class CLIProvider: AIProvider {
    public let kind: AIProviderKind
    public let executable: URL
    public var timeout: Duration = .seconds(120)
    private let log = Logger(subsystem: "brk", category: "ai")

    public init(kind: AIProviderKind, executable: URL) {
        self.kind = kind
        self.executable = executable
    }

    public func run(_ prompt: String) async throws -> String {
        let arguments: [String] = switch kind {
        case .claude: ["-p", prompt, "--output-format", "text"]
        case .codex: ["exec", "--skip-git-repo-check", prompt]
        }
        let executable = executable, timeout = timeout
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await Self.execute(executable, arguments) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AIProviderError.timedOut
            }
            let text = try await group.next()!
            group.cancelAll()
            return text
        }
    }

    private static func execute(_ executable: URL, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.terminationHandler = { p in
                let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let errors = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if p.terminationStatus == 0 { continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                else { continuation.resume(throwing: AIProviderError.failed(status: p.terminationStatus, stderr: errors)) }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

public enum AIProviderError: Error, CustomStringConvertible {
    case timedOut
    case failed(status: Int32, stderr: String)

    public var description: String {
        switch self {
        case .timedOut: "the AI tool did not answer in time"
        case .failed(let status, let stderr): "the AI tool exited with status \(status): \(stderr.prefix(200))"
        }
    }
}
