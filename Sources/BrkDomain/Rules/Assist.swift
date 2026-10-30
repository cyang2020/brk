import BrkBase
import Foundation

// Owner: later wave (Max stand-ins); the seam is wave 2's. AI requests leave as `Effect.ai` with the task and the
// Max provider choice; BrkApp's `AIProvider` runs the user's local `claude` or `codex` command-line tool and answers
// with `SystemEvent.aiResult`. The reducer applies the answer to the item the task named and forgets the request.

extension Work {
    /// Which tools launch found on PATH (`AIProviderSeam.detect`), for the Max pane and `.auto`.
    mutating func aiProvidersDetected(_ kinds: [AIProviderKind]) {
        if state.session.detectedAI != kinds { state.session.detectedAI = kinds }
    }

    /// Applies an answer: a renamed tab gets the text as its custom title (trimmed, one line, at most 60
    /// characters); other tasks are TODO(later wave). Unknown or already answered requests are ignored.
    mutating func aiResult(_ id: AIRequestID, _ outcome: AIOutcome) {
        guard let task = state.session.pendingAI[id] else { return }
        state.session.pendingAI[id] = nil
        guard case .text(let text) = outcome else { return }
        switch task {
        case .renameTab(let tab, _, _):
            let title = String(text.split(whereSeparator: \.isNewline).first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)
            guard !title.isEmpty, let scope = state.locate(tab) else { return }
            state.withTree(scope) { $0.updateTab(tab) { if $0.customTitle != String(title) { $0.customTitle = String(title) } } }
        case .tidyToday, .ask:
            break
        }
    }

    /// Sends a task to the provider, remembering it until the answer arrives.
    mutating func requestAI(_ task: AITask) {
        let id = AIRequestID(ctx.newID())
        state.session.pendingAI[id] = task
        effects.append(.ai(id, task, choice: state.doc.settings.max.provider))
    }

    /// The engine's suggestions for the bar's query, kept only while the bar is open (stale answers for another
    /// query are dropped by the projection, which checks the query).
    mutating func suggestions(_ window: WindowID, query: String, _ results: [String]) {
        guard state.session.windows[window] != nil else { return }
        guard case .commandBar? = state.session.windows[window]!.overlay else { return }
        let next = Suggestions(query: query, results: Array(results.prefix(Metrics.commandBar.maxSearchSuggestions.value)))
        if state.session.windows[window]!.suggestions != next { state.session.windows[window]!.suggestions = next }
    }
}
