import BrkDomain
import Foundation

/// The environment an agent runs in. A GUI app starts with a short PATH (launchd's), so a wrapper script or a
/// `#!/usr/bin/env node` tool that works in Terminal fails when Brk starts it. The user's login shell says what PATH
/// really is; it is asked once, off the main actor, with a limit on how long it may take.
enum AgentEnvironment {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var shellPath: String?

    /// The directories to look in: the login shell's PATH, this process's, then the usual install folders.
    static func searchPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        let shell = lock.withLock { shellPath } ?? ""
        return merged([shell, environment["PATH"] ?? ""] + [AIProviderSeam.fallbackDirectories.joined(separator: ":")])
    }

    static func merged(_ paths: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for path in paths {
            for entry in path.split(separator: ":").map(String.init) where !entry.isEmpty && seen.insert(entry).inserted { out.append(entry) }
        }
        return out
    }

    /// What an agent's process gets: this process's environment with the full PATH, without API keys (the user's
    /// decision: agents run on the account they are signed in to) and without what a parent agent set for itself.
    static func forAgent(_ kind: AIProviderKind, base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base.filter { key, _ in
            if ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "CLAUDECODE"].contains(key) { return false }
            if key.hasPrefix("CLAUDE_") { return key == "CLAUDE_CONFIG_DIR" }
            return true
        }
        environment["PATH"] = searchPath(environment: base).joined(separator: ":")
        // Brk never starts a sign-in: an agent that would open a browser to sign in reports that instead.
        switch kind {
        case .cursor: environment["NO_OPEN_BROWSER"] = "1"
        case .gemini: environment["NO_BROWSER"] = "true"
        default: break
        }
        return environment
    }

    /// Reads PATH from the user's login shell. The shell may print anything while it starts, so the value is between
    /// two markers; a shell that takes longer than five seconds is ended and the short PATH stays.
    static func loadShellPath(shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") async {
        let start = "__BRK_PATH_START__", end = "__BRK_PATH_END__"
        let directory = FileManager.default.temporaryDirectory
        let process = AgentProcess(executable: URL(fileURLWithPath: shell),
                                   arguments: ["-ilc", "printf '%s\\n' '\(start)'; printenv PATH; printf '%s\\n' '\(end)'"],
                                   directory: directory, environment: ProcessInfo.processInfo.environment)
        let output = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            let collected = StringBox()
            do {
                try process.start(output: { collected.append($0) }, exit: { _, _ in continuation.resume(returning: collected.text) })
            } catch { continuation.resume(returning: ""); return }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { process.stop() }
        }
        guard let from = output.range(of: start + "\n"), let to = output.range(of: end, range: from.upperBound..<output.endIndex) else { return }
        let value = output[from.upperBound..<to.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { lock.withLock { shellPath = value } }
    }
}

/// Collects a process's stdout on the main queue.
@MainActor final class StringBox: Sendable {
    private var data = Data()
    nonisolated init() {}
    func append(_ chunk: Data) { data.append(chunk) }
    var text: String { String(decoding: data, as: UTF8.self) }
}
