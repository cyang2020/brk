import BrkDomain
import Foundation

/// A program that takes a prompt on its command line and prints its answer: the test fixtures. One process per turn.
@MainActor final class PlainBackend: AgentBackend {
    var events: (@MainActor (AgentBackendEvent) -> Void)?
    private(set) var process: AgentProcess?
    var resumeID: String? { nil }
    private let spec: AgentSpec
    private let environment: [String: String]
    private var interrupted = false

    init(spec: AgentSpec, environment: [String: String]) {
        self.spec = spec
        self.environment = environment
    }

    func start() throws { events?(.ready(model: nil, effort: nil)) }

    func send(_ text: String) {
        interrupted = false
        let process = AgentProcess(executable: spec.executable, arguments: CLIProvider.arguments(kind: spec.kind, prompt: text), directory: spec.directory, environment: environment)
        self.process = process
        let collected = StringBox()
        var shown = 0
        do {
            try process.start(output: { [weak self] chunk in
                collected.append(chunk)
                let whole = collected.text
                self?.events?(.text(String(whole.dropFirst(shown))))
                shown = whole.count
            }, exit: { [weak self] status, stderr in
                guard let self else { return }
                if self.interrupted { self.events?(.turnEnded(.interrupted)) }
                else if status == 0 { self.events?(.turnEnded(.completed(text: nil))) }
                else { self.events?(.turnEnded(.failed(AIProviderError.failed(status: status, stderr: stderr).description))) }
            })
        } catch { events?(.turnEnded(.failed("\(error)"))) }
    }

    /// A program with no protocol stops by being stopped.
    func interrupt() {
        interrupted = true
        process?.stop()
    }

    func answer(approval: String, option: String) {}
}
