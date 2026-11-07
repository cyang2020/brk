import BrkBase
import BrkDomain
import Foundation
import os

/// Owner: the exchange rates behind the command bar's currency answers (`Effect.needCurrencyRates`), Brk's own addition
/// beyond Arc. Only a currency question asks. The European Central Bank's daily file is fetched at most once a day, kept
/// as is on disk, and read back on the next question; the request carries no cookies and nothing about the user, not
/// even the amount. A failed fetch keeps the last file and waits an hour. With no file and no network there are no rates,
/// so the bar has no row. Under the control socket the rates come only from `LaunchOptions.currencyRatesFile`.
@MainActor
final class CurrencyRatesStore {
    typealias Fetch = @Sendable () async throws -> Data

    static let source = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    private static let day = Duration.seconds(24 * 60 * 60), retry = Duration.seconds(60 * 60)

    private let file: URL
    private let fetch: Fetch?
    private let clock: any Clock
    private let send: @MainActor (Input) -> Void
    private let log = Logger(subsystem: "brk", category: "currency")
    private var busy = false
    private var shownFileDate: Instant?
    private var failedAt: Instant?

    /// `fetch` nil: `file` is all there is.
    init(file: URL, fetch: Fetch?, clock: any Clock, send: @escaping @MainActor (Input) -> Void) {
        self.file = file
        self.fetch = fetch
        self.clock = clock
        self.send = send
    }

    static func live(dataDirectory: URL, clock: any Clock, send: @escaping @MainActor (Input) -> Void, options: LaunchOptions = LaunchOptions()) -> CurrencyRatesStore {
        if options.controlSocket != nil {
            return CurrencyRatesStore(file: options.currencyRatesFile ?? dataDirectory.appendingPathComponent("no-currency-rates.xml"), fetch: nil, clock: clock, send: send)
        }
        return CurrencyRatesStore(file: dataDirectory.appendingPathComponent("currency-rates.xml"), fetch: fetchFromSource, clock: clock, send: send)
    }

    @Sendable private static func fetchFromSource() async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: source)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    func need() {
        guard !busy else { return }
        let now = clock.now(), saved = fileDate()
        if let saved {
            if shownFileDate != saved, let data = try? Data(contentsOf: file), let rates = CurrencyRates.parseECB(data) {
                shownFileDate = saved
                send(.system(.currencyRates(rates)))
            }
            if now.since(saved) < Self.day { return }
        }
        guard let fetch else { return }
        if let failedAt, now.since(failedAt) < Self.retry { return }
        busy = true
        Task { @MainActor [weak self] in
            let answer = await Task.detached(priority: .utility) { () -> Result<Data, any Error> in
                do { return .success(try await fetch()) } catch { return .failure(error) }
            }.value
            self?.finished(answer)
        }
    }

    private func finished(_ answer: Result<Data, any Error>) {
        busy = false
        switch answer {
        case .success(let data):
            guard let rates = CurrencyRates.parseECB(data) else {
                failedAt = clock.now()
                log.notice("exchange rates: the file could not be read")
                return
            }
            do {
                try data.write(to: file, options: .atomic)
                // The file's own date says when it was fetched: the clock's, so a test clock agrees with `need`.
                let stamp = Double(clock.now().milliseconds) / 1000
                try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: stamp)], ofItemAtPath: file.path)
                shownFileDate = fileDate()
            } catch {
                log.notice("exchange rates: could not keep the file: \(error.localizedDescription)")
            }
            failedAt = nil
            send(.system(.currencyRates(rates)))
        case .failure(let error):
            failedAt = clock.now()
            log.notice("exchange rates: fetch failed: \(error.localizedDescription)")
        }
    }

    private func fileDate() -> Instant? {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date else { return nil }
        return Instant(milliseconds: Int64(date.timeIntervalSince1970 * 1000))
    }
}
