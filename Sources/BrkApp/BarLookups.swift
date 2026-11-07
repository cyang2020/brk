import BrkBase
import BrkDomain
import Foundation

/// Owner: the command bar's prefix lookups that wait for a pause in typing, one per window: a translation (asks a local
/// agent, which takes seconds, so not at every key) and, later, others. A newer one cancels the older one.
@MainActor
final class BarLookups {
    private let send: @MainActor (Input) -> Void
    private var pending: [WindowID: Task<Void, Never>] = [:]
    private let translationPause: Duration

    init(send: @escaping @MainActor (Input) -> Void, translationPause: Duration = .seconds(Metrics.commandBar.translationDebounce.value)) {
        self.send = send
        self.translationPause = translationPause
    }

    func cancel(_ window: WindowID) { pending.removeValue(forKey: window)?.cancel() }

    func translationDue(_ window: WindowID, text: String) {
        cancel(window)
        let pause = translationPause, send = send
        pending[window] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            self?.pending[window] = nil
            send(.system(.barTranslationDue(window, text)))
        }
    }
}
