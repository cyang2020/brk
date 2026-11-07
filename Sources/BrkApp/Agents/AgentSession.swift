import BrkBase
import BrkDomain
import Foundation

/// One conversation's process and the turn in it. Stop first asks the agent to stop; a turn that has not ended two
/// seconds later, and whatever a stopped turn left running, is ended by Brk. A process that is gone starts again at the
/// next message, continuing the agent's own session where it keeps one.
@MainActor final class AgentSession {
    enum Output {
        case started(model: String?, effort: String?)
        case partial(AIRequestID, String)
        case finished(AIRequestID, AIOutcome)
        case step(AIAgentStep, AIRequestID)
        case approval(AIAgentApproval, AIRequestID)
        case approvalClosed(String)
        case notice(String)
    }

    let spec: AgentSpec
    private let environment: [String: String]
    private let plain: Bool
    private let output: @MainActor (Output) -> Void
    private var backend: (any AgentBackend)?
    private var resume: String?
    private var ownsDirectory: Bool { spec.access == .readOnly }
    private(set) var currentTurn: AIRequestID?
    private var text = ""
    private var flushScheduled = false
    private var stopTask: Task<Void, Never>?
    private var stopping = false
    private var baseline: Set<pid_t> = []
    private var waiting: (turn: AIRequestID, prompt: String)?
    private var closed = false
    private var startDeadline: Task<Void, Never>?
    private var ready = false
    /// A session that has not said it is ready by then failed; no model turn has been spent.
    private static let startSeconds = 60

    init(spec: AgentSpec, environment: [String: String], plain: Bool, output: @escaping @MainActor (Output) -> Void) {
        self.spec = spec
        self.environment = environment
        self.plain = plain
        self.output = output
    }

    /// Starts the process; a session with tools on does so before its first message, so the panel can say which model.
    func begin() {
        guard backend == nil, !closed else { return }
        var current = spec
        current.resume = resume
        let backend: any AgentBackend
        if plain {
            backend = PlainBackend(spec: current, environment: environment)
        } else {
            switch spec.kind {
            case .claude: backend = ClaudeBackend(spec: current, environment: environment)
            case .codex: backend = CodexBackend(spec: current, environment: environment)
            case .gemini, .cursor, .opencode: backend = ACPBackend(spec: current, environment: environment)
            }
        }
        self.backend = backend
        ready = false
        backend.events = { [weak self] in self?.handle($0) }
        do { try backend.start() } catch { failStart("\(spec.kind.displayName) could not be started: \(error)"); return }
        startDeadline = Task { [weak self, kind = spec.kind] in
            do { try await Task.sleep(for: .seconds(Self.startSeconds)) } catch { return }
            guard let self, !self.ready else { return }
            self.failStart(AgentCopy.noAnswer(kind))
        }
    }

    private func failStart(_ message: String) {
        startDeadline?.cancel()
        let dead = backend
        backend = nil
        dead?.process?.stop()
        if let turn = currentTurn { finish(turn, .failed(message)) }
        else if let waiting { self.waiting = nil; output(.finished(waiting.turn, .failed(message))) }
        else { output(.notice(message)) }
    }

    func send(_ prompt: String, turn: AIRequestID) {
        guard !closed else { output(.finished(turn, .failed("This conversation has ended."))); return }
        // A stop still in progress finishes first; the new message follows on what is left.
        if stopping || currentTurn != nil { waiting = (turn, prompt); return }
        begin()
        guard let backend else { waiting = nil; output(.finished(turn, .failed("\(spec.kind.displayName) could not be started."))); return }
        currentTurn = turn
        text = ""
        baseline = backend.process?.descendants() ?? []
        backend.send(prompt)
    }

    func stop(turn: AIRequestID) {
        guard currentTurn == turn, !stopping else {
            if waiting?.turn == turn { waiting = nil }
            return
        }
        // The turn's outcome is no longer wanted: the domain has already written "Stopped".
        currentTurn = nil
        stopping = true
        backend?.interrupt()
        stopTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.endTurnByForce()
        }
    }

    /// The agent did not stop in time: the whole tree goes. The next message starts a new process.
    private func endTurnByForce() {
        guard stopping else { return }
        let dead = backend
        resume = dead?.resumeID ?? resume
        backend = nil
        dead?.events = nil
        dead?.process?.stop()
        stopping = false
        sendWaiting()
    }

    private func turnEndedDuringStop() {
        stopTask?.cancel()
        stopping = false
        // The agent stopped; a command it started that is still running goes too. What ran before the turn (MCP
        // servers, for instance) stays.
        if let process = backend?.process { process.end(process.descendants().subtracting(baseline)) }
        sendWaiting()
    }

    private func sendWaiting() {
        guard let waiting else { return }
        self.waiting = nil
        send(waiting.prompt, turn: waiting.turn)
    }

    func answer(approval: String, option: String) { backend?.answer(approval: approval, option: option) }

    /// Ends the session for good: its tree, its temporary folder. Returns when the process is gone.
    func close() async {
        closed = true
        startDeadline?.cancel()
        stopTask?.cancel()
        let dead = backend
        backend = nil
        dead?.events = nil
        if let process = dead?.process {
            process.stop()
            await process.waitForExit()
        }
        if ownsDirectory { try? FileManager.default.removeItem(at: spec.directory) }
    }

    private func handle(_ event: AgentBackendEvent) {
        switch event {
        case .ready(let model, let effort):
            ready = true
            startDeadline?.cancel()
            output(.started(model: model, effort: effort))
        case .text(let delta):
            guard currentTurn != nil else { return }
            text += delta
            scheduleFlush()
        case .step(let step):
            if let turn = currentTurn { flush(); output(.step(step, turn)) }
        case .approval(let approval):
            if let turn = currentTurn { flush(); output(.approval(approval, turn)) }
            else { backend?.answer(approval: approval.id, option: approval.options.first { $0.kind == .deny }?.id ?? "") }
        case .approvalClosed(let id): output(.approvalClosed(id))
        case .notice(let message): output(.notice(message))
        case .turnEnded(let end):
            if stopping { turnEndedDuringStop(); return }
            guard let turn = currentTurn else { return }
            switch end {
            case .completed(let final):
                if text.isEmpty, let final { text = final }
                finish(turn, .text(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            case .interrupted: finish(turn, .failed("Request cancelled."))
            case .failed(let message): finish(turn, .failed(message))
            }
        case .exited(let message):
            startDeadline?.cancel()
            ready = false
            resume = backend?.resumeID ?? resume
            backend = nil
            if stopping { turnEndedDuringStop(); return }
            let reason = message ?? "\(spec.kind.displayName) stopped before it answered."
            if let turn = currentTurn { finish(turn, .failed(reason)) }
            else if let waiting { self.waiting = nil; output(.finished(waiting.turn, .failed(reason))) }
            else if message != nil { output(.notice(reason)) }
        }
    }

    private func finish(_ turn: AIRequestID, _ outcome: AIOutcome) {
        flush()
        currentTurn = nil
        output(.finished(turn, outcome))
        sendWaiting()
    }

    /// The panel takes at most about thirty updates a second, however fast the agent writes.
    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(33))
            self?.flushScheduled = false
            self?.flush()
        }
    }

    private func flush() {
        guard let turn = currentTurn, !text.isEmpty else { return }
        output(.partial(turn, text))
    }
}
