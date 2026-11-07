import BrkBase
import BrkDomain
import CoreServices
import Foundation

/// Owner: the command bar's prefix lookups that wait for a pause in typing, one per window: a translation (asks a local
/// agent, which takes seconds, so not at every key) and a word in macOS's offline dictionary, which never uses the
/// network. A newer one cancels the older one.
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

    func define(_ window: WindowID, word: String) {
        cancel(window)
        let send = send
        pending[window] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Metrics.commandBar.suggestionDebounce.value))
            guard !Task.isCancelled else { return }
            let text = await Task.detached(priority: .userInitiated) { Self.definition(of: word) }.value
            guard !Task.isCancelled else { return }
            self?.pending[window] = nil
            send(.system(.definition(window, BarDefinition(word: word, text: text))))
        }
    }

    /// The dictionary's text for the whole word, one line, its first lines at most: nil when it has nothing.
    nonisolated static func definition(of word: String) -> String? {
        let text = word as CFString
        guard let found = DCSCopyTextDefinition(nil, text, CFRangeMake(0, CFStringGetLength(text)))?.takeRetainedValue() as String? else { return nil }
        let line = found.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : String(line.prefix(400))
    }

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
