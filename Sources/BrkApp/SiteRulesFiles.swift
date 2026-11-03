import BrkBase
import BrkDomain
import Foundation

/// The user-selected file is read off the UI actor and bounded before parsing. Brk rules JSON replaces the built-in
/// rules; any other text is EasyList syntax and becomes the profile's imported filter list.
enum SiteRulesFiles {
    static func read(_ file: URL) -> WebsiteRulesUpdate {
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: CompiledFilterList.maximumBytes + 1) ?? Data()
            if data.first(where: { ![9, 10, 13, 32].contains($0) }) == 123 { return StateCodec.decodeWebsiteRules(data) }
            let list = try CompiledFilterList.compile(data)
            let key = FilterListStore.key(data)
            try FilterListStore.write(data, key: key)
            return .filterList(key: key, title: list.summary.title ?? file.deletingPathExtension().lastPathComponent, summary: list.summary)
        } catch let error as FilterListError { return .failed(error.description) }
        catch { return .failed(error.localizedDescription) }
    }
}

/// Subscription downloads (EasyList, EasyPrivacy): an ephemeral session without cookies, one download per list at a
/// time. No network is `offline`, not an error. Test launches (`BRK_CONTROL_SOCKET`) never reach the internet: with
/// `BRK_TEST_FILTER_BASE` the list's file name is fetched from that address instead, without it nothing is fetched.
@MainActor
final class FilterListDownloads {
    private var running: Set<String> = []
    private let send: (SystemEvent) -> Void
    init(send: @escaping (SystemEvent) -> Void) { self.send = send }

    func fetch(_ context: BrowsingContext, _ record: FilterListRecord) {
        guard let source = record.source else { return }
        let environment = ProcessInfo.processInfo.environment
        let address: URL?
        if environment["BRK_CONTROL_SOCKET"] != nil {
            address = environment["BRK_TEST_FILTER_BASE"].flatMap(URL.init(string:))?.appendingPathComponent(source.lastPathComponent)
        } else { address = source }
        guard let address else { return }
        let key = "\(context)|\(record.id)"
        guard running.insert(key).inserted else { return }
        let previous = record.key
        Task { @MainActor [weak self] in
            let result = await Self.download(address, previous: previous)
            self?.running.remove(key)
            self?.send(.filterListFetched(context, record.id, result))
        }
    }

    nonisolated static let offlineCodes: Set<URLError.Code> = [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .timedOut,
                                                   .networkConnectionLost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed]

    nonisolated static func download(_ url: URL, previous: String?) async -> FilterListFetch {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return .failed("The server answered \(http.statusCode).") }
            let list = try CompiledFilterList.compile(data)
            let key = FilterListStore.key(data)
            if key == previous { return .unchanged }
            try FilterListStore.write(data, key: key)
            return .updated(key: key, summary: list.summary)
        } catch let error as URLError where offlineCodes.contains(error.code) {
            return .offline
        } catch let error as FilterListError {
            return .failed(error.description)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
