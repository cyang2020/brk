import AppKit
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
    private var conversations: [AIRequestID: AgentSession] = [:]
    /// A turn's conversation, while it can still be stopped.
    private var turns: [AIRequestID: AIRequestID] = [:]
    private var closing: [Task<Void, Never>] = []
    private var refreshing: [AIProviderKind: Task<Void, Never>] = [:]
    /// The basic layer: one-shot tasks in a schema, on the subscription or a key (AIBasic.swift).
    let basic = AIBasicChannel(keys: .shared)
    private var wakeTask: Task<Void, Never>?
    init(engine: any WebEngine, send: @escaping (SystemEvent) -> Void) {
        self.engine = engine
        self.send = send
        basic.keys.onChange = { [weak self] statuses in self?.send(.aiKeys(statuses, localDecisions: self?.basic.localDecisions?.isAvailable == true)) }
        basic.onUsage = { [weak self] key, count in self?.send(.aiUsage(key, count)) }
    }

    /// The reducer's pause (Name Tabs waits for pages to settle).
    func wake(after milliseconds: Int) {
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(milliseconds)) } catch { return }
            self?.send(.aiBasicTick)
        }
    }

    private func start(_ id: AIRequestID, _ operation: @escaping @MainActor () async -> Void) {
        guard !stopping else { return }
        let token = UUID()
        tasks[id, default: [:]][token] = Task { [weak self] in
            await operation()
            self?.tasks[id]?[token] = nil
            if self?.tasks[id]?.isEmpty == true { self?.tasks[id] = nil }
        }
    }
    /// `choice` picks this request's agent. An agent named explicitly runs or says why it cannot; only `.auto` chooses.
    func answer(_ id: AIRequestID, task: AITask, choice: AIProviderChoice, max: MaxSnapshot) {
        // The first turn of a conversation makes its session, with the agent this request names. Everything else is one
        // prompt in a session of its own.
        if opening.remove(id) != nil {
            if let failure = makeSession(id, folder: nil, choice: choice, max: max) { send(.aiResult(id, failure)); return }
            turn(conversation: id, turn: id, task: task)
            return
        }
        if task.isBasic {
            start(id) { [weak self] in
                guard let self else { return }
                let result = await basic.answer(task, context: AIBasicContext(max: max, choice: choice))
                guard !Task.isCancelled else { return }
                send(.aiResult(id, result))
            }
            return
        }
        start(id) { [weak self] in
            let result = await AIProviderSeam.answer(task, choice: choice, detected: max.detected, active: max.active, options: max.settings.agentOptions ?? [:],
                                                     onPartial: { [weak self] text in self?.send(.aiPartial(id, text)) })
            guard !Task.isCancelled else { return }
            self?.send(.aiResult(id, result))
        }
    }

    /// A read-only conversation waits for its first request, which says which agent. A session with tools on starts at
    /// once, so the panel can say which model before the first message.
    func openConversation(_ id: AIRequestID, folder: String?, choice: AIProviderChoice, max: MaxSnapshot) {
        guard !stopping else { return }
        guard let folder else { opening.insert(id); return }
        guard let failure = makeSession(id, folder: folder, choice: choice, max: max) else {
            conversations[id]?.begin()
            return
        }
        if case .failed(let message) = failure { send(.aiConversation(id, .notice(message))) }
        else { send(.aiConversation(id, .notice("No local AI tool is available. Choose an installed agent in Settings → Max."))) }
    }
    private var opening: Set<AIRequestID> = []

    /// The session for a conversation, or why there can be none. Read-only ones work in an empty folder of their own,
    /// deleted when they close; a session with tools on works in the folder the user chose.
    private func makeSession(_ id: AIRequestID, folder: String?, choice: AIProviderChoice, max: MaxSnapshot) -> AIOutcome? {
        guard let resolved = agent(for: choice, max: max) else {
            return choice.kind.map { AIProviderSeam.mode == .real ? .failed(AgentCopy.missing($0)) : .unavailable } ?? .unavailable
        }
        let directory: URL
        if let folder { directory = URL(fileURLWithPath: folder, isDirectory: true) }
        else {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-ai-" + UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let options = max.settings.agentOptions?[resolved.kind]
        let spec = AgentSpec(kind: resolved.kind, executable: resolved.executable, model: options?.model, effort: options?.effort, access: folder == nil ? .readOnly : .tools, directory: directory)
        conversations[id] = AgentSession(spec: spec, environment: AgentEnvironment.forAgent(resolved.kind), plain: resolved.plain) { [weak self] in self?.report($0, conversation: id, kind: resolved.kind) }
        return nil
    }

    /// The executable and how to talk to it for this instance: the fixture stands in for every agent in a test instance.
    private func agent(for choice: AIProviderChoice, max: MaxSnapshot) -> (kind: AIProviderKind, executable: URL, plain: Bool)? {
        switch AIProviderSeam.mode {
        case .none: return nil
        case .fixture(let fixture, let protocols):
            guard choice != .off else { return nil }
            return (choice.kind ?? .claude, fixture, !protocols)
        case .real:
            guard let kind = AIProviderSeam.resolve(choice, active: max.active, detected: max.detected), max.detected.contains(kind),
                  let executable = AIProviderSeam.executable(for: kind) else { return nil }
            return (kind, executable, false)
        }
    }

    func turn(conversation: AIRequestID, turn: AIRequestID, task: AITask, max: MaxSnapshot? = nil) {
        guard var session = conversations[conversation] else {
            send(.aiResult(turn, .failed("This conversation has ended. Ask again from the command bar.")))
            return
        }
        // A model or effort picked in the Max pane since the session started (the panel's Agent… button leads there,
        // and an agent out of quota says to switch model) applies from this message on.
        if let max, !session.plain {
            let wanted = max.settings.agentOptions?[session.spec.kind]
            if wanted?.model != session.spec.model || wanted?.effort != session.spec.effort {
                session = renew(conversation, session, model: wanted?.model, effort: wanted?.effort)
            }
        }
        turns[turn] = conversation
        session.send(AIPrompt.text(for: task), turn: turn)
    }

    /// The conversation's session again with another model or effort. A session with tools on continues the agent's
    /// own session; a read-only one keeps nothing, so the new model starts without the earlier messages, and says so.
    private func renew(_ id: AIRequestID, _ old: AgentSession, model: String?, effort: String?) -> AgentSession {
        let readOnly = old.spec.access == .readOnly
        var directory = old.spec.directory
        if readOnly {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-ai-" + UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let kind = old.spec.kind
        let spec = AgentSpec(kind: kind, executable: old.spec.executable, model: model, effort: effort, access: old.spec.access, directory: directory,
                             resume: readOnly ? nil : old.resumeID)
        let session = AgentSession(spec: spec, environment: AgentEnvironment.forAgent(kind), plain: old.plain) { [weak self] in self?.report($0, conversation: id, kind: kind) }
        conversations[id] = session
        for (turn, owner) in turns where owner == id { turns[turn] = nil }
        closing.append(Task { await old.close() })
        send(.aiConversation(id, .notice(readOnly ? AgentCopy.modelChangedFresh : AgentCopy.modelChanged)))
        return session
    }

    func approve(conversation: AIRequestID, approval: String, option: String) {
        conversations[conversation]?.answer(approval: approval, option: option)
    }

    func closeConversation(_ id: AIRequestID) {
        opening.remove(id)
        guard let session = conversations.removeValue(forKey: id) else { return }
        for (turn, owner) in turns where owner == id { turns[turn] = nil }
        closing.append(Task { await session.close() })
        closing.removeAll { $0.isCancelled }
    }

    private func report(_ output: AgentSession.Output, conversation id: AIRequestID, kind: AIProviderKind) {
        switch output {
        case .started(let model, let effort): send(.aiConversation(id, .started(agent: kind, name: kind.displayName, model: model, effort: effort)))
        case .partial(let turn, let text): send(.aiPartial(turn, text))
        case .finished(let turn, let outcome):
            turns[turn] = nil
            send(.aiResult(turn, outcome))
        case .step(let step, let turn): send(.aiConversation(id, .step(step, turn: turn)))
        case .approval(let approval, let turn): send(.aiConversation(id, .approval(approval, turn: turn)))
        case .approvalClosed(let approval): send(.aiConversation(id, .approvalClosed(approval)))
        case .notice(let text): send(.aiConversation(id, .notice(text)))
        }
    }

    /// Asks each installed agent about itself: signed in or not, version, models and efforts. Nothing goes to a model.
    func refreshAgents(detected: [AIProviderKind]) {
        basic.keys.report()
        guard !stopping, refreshing.isEmpty else { return }
        let mode = AIProviderSeam.mode
        guard mode != .none else { return }
        for kind in AIProviderKind.allCases {
            refreshing[kind] = Task { [weak self] in
                let status: AIAgentStatus
                switch mode {
                case .real:
                    if detected.contains(kind), let executable = AIProviderSeam.executable(for: kind) {
                        status = await AgentCatalog.status(kind, executable: executable, environment: AgentEnvironment.forAgent(kind))
                    } else { status = AIAgentStatus(kind: kind, state: .missing) }
                case .fixture(let fixture, let protocols):
                    if protocols { status = await AgentCatalog.status(kind, executable: fixture, environment: AgentEnvironment.forAgent(kind)) }
                    else { status = AIAgentStatus(kind: kind, state: kind == .claude ? .ready : .missing) }
                case .none: status = AIAgentStatus(kind: kind, state: .missing)
                }
                self?.send(.aiAgents([status]))
                self?.refreshing[kind] = nil
            }
        }
    }
    func read(_ id: AIRequestID, document: DocumentToken) {
        start(id) { [weak self] in
            guard let self else { return }
            var content: AIPageContent?
            do { content = try await engine.readAIPage(document) }
            catch { FileHandle.standardError.write(Data("AI page read failed: \(error)\n".utf8)) }
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
    /// Arc's 5-Second Previews (P45-a): Shift held over the same link for about two seconds opens the card under it.
    /// The keyboard state is polled (Shift may go down before or after the pointer reaches the link); letting go
    /// starts the wait again.
    func hover(_ window: WindowID, url: URL?, document: DocumentToken?) {
        hovers.removeValue(forKey: window)?.cancel()
        guard let url, !stopping else { return }
        hovers[window] = Task { [weak self] in
            var held = 0, waited = 0, siteChecked = false
            while held < Self.previewHold {
                do { try await Task.sleep(for: .milliseconds(Self.previewPoll)) } catch { return }
                held = NSEvent.modifierFlags.contains(.shift) ? held + Self.previewPoll : 0
                waited += Self.previewPoll
                // "Instant summaries appear when you hover over links on certain websites": the same wait without Shift.
                if !siteChecked, waited >= Self.previewHold, held < Self.previewHold, let document, let self {
                    siteChecked = true
                    if let link = await self.engine.hoveredLink(document, url: url), link.previewSite, !Task.isCancelled {
                        self.send(.aiHoverReady(window, url, link.frame)); return
                    }
                }
            }
            guard let self, !Task.isCancelled else { return }
            var link: HoveredLink?
            if let document { link = await self.engine.hoveredLink(document, url: url) }
            guard !Task.isCancelled else { return }
            self.send(.aiHoverReady(window, url, link?.frame))
        }
    }
    private static let previewHold = 2000, previewPoll = 100
    func showTranslation(_ document: DocumentToken, translated: Bool) {
        Task { [engine] in _ = await engine.showAITranslation(document, translated: translated) }
    }
    func cancel(_ id: AIRequestID) {
        for task in tasks[id]?.values ?? [:].values { task.cancel() }
        deadlines.removeValue(forKey: id)?.cancel()
        // Every finished request comes here too; only a turn that still runs stops.
        if let conversation = turns.removeValue(forKey: id) { conversations[conversation]?.stop(turn: id) }
    }
    func cancelAll() {
        stopping = true
        wakeTask?.cancel()
        basic.stop()
        for task in tasks.values.flatMap({ $0.values }) { task.cancel() }
        for task in deadlines.values { task.cancel() }
        for task in hovers.values { task.cancel() }
        deadlines.removeAll(); hovers.removeAll()
        for task in refreshing.values { task.cancel() }
        for id in Array(conversations.keys) { closeConversation(id) }
        opening.removeAll()
    }
    func stop() async {
        let running = tasks.values.flatMap { $0.values }
        cancelAll()
        for task in running { await task.value }
        for task in closing { await task.value }
        for task in Array(renames.values) { await task.value }
        tasks.removeAll(); renames.removeAll(); closing.removeAll()
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
