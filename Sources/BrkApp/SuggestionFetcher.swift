import BrkBase
import BrkDomain
import Foundation
import os

/// Owner: F4. Fetches the default engine's suggestions for the command bar (`Effect.fetchSuggestions`), debounced by
/// Metrics.commandBar.suggestionDebounce so typing does not fire a request per key, and answers with
/// `SystemEvent.suggestions(window, query:, results, verbatimRelevance:)`. Every engine answers in the OpenSearch JSON
/// form, `["query", ["s1", "s2", ...]]`; Google, asked the way Chromium's omnibox asks it (`client=chrome-omni`), adds what
/// Chromium ranks with (`parse`). A newer request for the same window cancels the older one.
@MainActor
public final class SuggestionFetcher {
    private let send: @MainActor (Input) -> Void
    private struct Eligibility: Equatable {
        let profileRoot: ItemID
        let opening: Int
        let engine: SearchEngineCandidate
    }
    private struct Pending {
        let id: UUID
        let query: String
        let endpoint: URL
        let eligibility: Eligibility?
        let task: Task<Void, Never>
    }
    private var pending: [WindowID: Pending] = [:]
    private var eligible: [WindowID: Eligibility] = [:]
    let session: URLSession
    /// `LaunchOptions.suggestOverride`: the e2e fixture's endpoint instead of the engine's.
    private let override: URL?
    private let log = Logger(subsystem: "brk", category: "suggest")

    public init(send: @escaping @MainActor (Input) -> Void, session: URLSession = SuggestionFetcher.privateSession,
                override: URL? = LaunchOptions().suggestOverride) {
        self.send = send
        self.session = session
        self.override = override
    }

    /// The store's: no cookies, cache or saved credentials, like the other fetchers here. A cookie the engine sets would
    /// otherwise go back with every profile's typing (pages keep cookies per profile), and typed queries would be cached
    /// on disk out of reach of clearing browsing data.
    public static let privateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()

    public func cancel(_ window: WindowID) { pending.removeValue(forKey: window)?.task.cancel() }

    public func reconcile(_ snapshot: AppSnapshot) {
        eligible = snapshot.windows.compactMapValues { window in
            guard case .commandBar(let bar)? = window.overlay, bar.suggestionsEnabled else { return nil }
            return Eligibility(profileRoot: window.favorites.root, opening: bar.openID, engine: bar.engine)
        }
        for window in Array(pending.keys) {
            guard let request = pending[window], let current = eligible[window] else { cancel(window); continue }
            if let captured = request.eligibility {
                if captured != current { cancel(window) }
            } else if SearchEngine.builtIn(current.engine.id)?.suggestURL(request.query) != request.endpoint {
                cancel(window)
            }
        }
    }

    public func fetch(_ window: WindowID, query: String, url engineURL: URL) {
        cancel(window)
        let id = UUID(), eligibility = eligible[window]
        var url = engineURL
        if let override, var components = URLComponents(url: override, resolvingAgainstBaseURL: false) {
            // The engine's own host rides along, so a test sees which engine would have been asked.
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "q", value: query), URLQueryItem(name: "engine", value: engineURL.host ?? "")]
            url = components.url ?? engineURL
        }
        let session = session, send = send
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Metrics.commandBar.suggestionDebounce.value))
            guard !Task.isCancelled, self.pending[window]?.id == id else { return }
            do {
                let (data, _) = try await session.data(from: url)
                guard !Task.isCancelled, self.pending[window]?.id == id,
                      eligibility == nil || self.eligible[window] == eligibility else { return }
                let answer = Self.parse(data)
                self.pending[window] = nil
                send(.system(.suggestions(window, query: query, answer.rows, verbatimRelevance: answer.verbatimRelevance)))
            } catch {
                guard !Task.isCancelled, self.pending[window]?.id == id else { return }
                self.pending[window] = nil
                self.log.notice("suggestions failed: \(error)")
            }
        }
        pending[window] = Pending(id: id, query: query, endpoint: engineURL, eligibility: eligibility, task: task)
    }

    /// The answer's suggestions and the relevance of the search as typed. `["q", ["a", "b"]]` gives two searches without a
    /// relevance. Google's Chromium form adds, in the fifth element, `google:suggesttype` (QUERY; NAVIGATION, a site whose
    /// text is its address and whose page title is in the third element; ENTITY, a search shown by the thing's name),
    /// `google:suggestrelevance`, `google:verbatimrelevance` and `google:suggestdetail` (an entity's name is field 7 of its
    /// `google:entityinfo`). Types Chromium does not list as rows here (a calculator result, a personal answer) are left
    /// out. A leading `)]}'` line (Chromium's `xssi=t`) is skipped. Anything else: nothing.
    public static func parse(_ data: Data) -> (rows: [EngineSuggestion], verbatimRelevance: Int?) {
        var data = data
        if data.starts(with: Array(")]}'".utf8)) {
            let newline = data.firstIndex(of: UInt8(ascii: "\n")).map { data.index(after: $0) } ?? data.index(data.startIndex, offsetBy: 4)
            data = data.suffix(from: newline)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any], json.count >= 2,
              let texts = json[1] as? [String] else { return ([], nil) }
        let titles = json.count > 2 ? json[2] as? [String] : nil
        let meta = json.count > 4 ? json[4] as? [String: Any] : nil
        let types = meta?["google:suggesttype"] as? [String]
        let relevances = (meta?["google:suggestrelevance"] as? [NSNumber])?.map(\.intValue)
        let details = meta?["google:suggestdetail"] as? [Any]
        var rows: [EngineSuggestion] = []
        for (index, text) in texts.enumerated() {
            let type = types.flatMap { index < $0.count ? $0[index] : nil } ?? "QUERY"
            let relevance = relevances.flatMap { $0.count == texts.count ? $0[index] : nil }
            switch type {
            case "QUERY":
                rows.append(EngineSuggestion(text, relevance: relevance))
            case "NAVIGATION":
                let title = titles.flatMap { index < $0.count && !$0[index].isEmpty ? $0[index] : nil }
                rows.append(EngineSuggestion(text, kind: .navigation, relevance: relevance, title: title))
            case "ENTITY":
                let detail = details.flatMap { index < $0.count ? $0[index] as? [String: Any] : nil }
                let name = (detail?["google:entityinfo"] as? String).flatMap { Data(base64Encoded: $0) }.flatMap { entityName($0) }
                rows.append(EngineSuggestion(text, relevance: relevance, title: name))
            default:
                continue
            }
        }
        return (rows, (meta?["google:verbatimrelevance"] as? NSNumber)?.intValue)
    }

    /// Field 7 (the name) of Google's `EntityInfo` message, read off the protocol-buffer wire format.
    static func entityName(_ bytes: Data) -> String? {
        let bytes = [UInt8](bytes)
        var at = 0
        func varint() -> Int? {
            var value = 0, shift = 0
            while at < bytes.count, shift < 64 {
                let byte = bytes[at]; at += 1
                value |= Int(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
            return nil
        }
        while at < bytes.count, let key = varint() {
            switch key & 7 {
            case 0: guard varint() != nil else { return nil }
            case 1: at += 8
            case 5: at += 4
            case 2:
                guard let length = varint(), length >= 0, at + length <= bytes.count else { return nil }
                if key >> 3 == 7 { return String(bytes: bytes[at..<at + length], encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 } }
                at += length
            default: return nil
            }
        }
        return nil
    }
}
