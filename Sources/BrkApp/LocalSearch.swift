import AppKit
import BrkBase
import BrkDomain
import Foundation
import os

/// Finds files for the command bar. File names only, never contents.
@MainActor
protocol LocalFileFinder: AnyObject {
    /// Hits for `name`, the source's best first, without what `LocalSources.isExcluded` leaves out. Ends early on cancellation.
    func find(_ name: String) async -> [LocalHit]
}

/// Owner: the command bar's file and app sources (`Effect.searchLocal`), Brk's own addition beyond Arc: debounced like the
/// engine's suggestions, a newer request for the window cancels the older one, the answer is `SystemEvent.localResults`.
/// Nothing is stored and nothing leaves this Mac. Under the control socket it reads only `LaunchOptions.localSearchFixture`,
/// and finds nothing without one, so scenes stay repeatable.
@MainActor
final class LocalSearch {
    private let send: @MainActor (Input) -> Void
    private let finder: (any LocalFileFinder)?
    private let applicationRoots: [URL]
    private let debounce: Duration
    private var pending: [WindowID: Task<Void, Never>] = [:]

    init(send: @escaping @MainActor (Input) -> Void, finder: (any LocalFileFinder)?, applicationRoots: [URL], debounce: Duration = .seconds(Metrics.commandBar.suggestionDebounce.value)) {
        self.send = send
        self.finder = finder
        self.applicationRoots = applicationRoots
        self.debounce = debounce
    }

    /// The real home folder, or under the control socket only the fixture folder.
    static func live(send: @escaping @MainActor (Input) -> Void, options: LaunchOptions = LaunchOptions()) -> LocalSearch {
        if options.controlSocket != nil {
            guard let fixture = options.localSearchFixture else { return LocalSearch(send: send, finder: nil, applicationRoots: []) }
            let finder: any LocalFileFinder = options.localSearchSpotlight
                ? SpotlightFinder(home: fixture, otherScopes: [])
                : FolderFinder(home: fixture)
            return LocalSearch(send: send, finder: finder, applicationRoots: [fixture.appendingPathComponent("Applications", isDirectory: true)])
        }
        let home = FileManager.default.homeDirectoryForCurrentUser, applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        return LocalSearch(send: send, finder: SpotlightFinder(home: home, otherScopes: [applications]),
                           applicationRoots: [applications, home.appendingPathComponent("Applications", isDirectory: true)])
    }

    func cancel(_ window: WindowID) { pending.removeValue(forKey: window)?.cancel() }

    func reconcile(_ snapshot: AppSnapshot) {
        for window in Array(pending.keys) {
            if case .commandBar? = snapshot.windows[window]?.overlay { continue }
            cancel(window)
        }
    }

    func search(_ window: WindowID, _ request: LocalSearchRequest) {
        cancel(window)
        guard let finder else { return }
        let roots = applicationRoots, debounce = debounce, send = send
        pending[window] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let apps = request.scope != .files ? await Task.detached(priority: .userInitiated) { Self.apps(named: request.name, in: roots) }.value : []
            guard !Task.isCancelled else { return }
            let files = request.scope != .apps ? LocalSources.rank(await finder.find(request.name), needle: request.name) : []
            guard !Task.isCancelled else { return }
            self?.pending[window] = nil
            send(.system(.localResults(window, LocalResults(query: request.query, scope: request.scope, apps: apps, files: files))))
        }
    }

    /// Apps by name, two folders deep so a suite's folder and Utilities count. The folders are read each time: they hold
    /// a few hundred entries at most.
    nonisolated static func apps(named name: String, in roots: [URL]) -> [LocalHit] {
        let files = FileManager.default
        var hits: [LocalHit] = []
        func walk(_ folder: URL, depth: Int) {
            // Names with a dot are hidden; the system's hidden flag is not read here, because macOS sets it on Safari in /Applications.
            for entry in (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? [] where !entry.lastPathComponent.hasPrefix(".") {
                if entry.pathExtension == "app" {
                    hits.append(LocalHit(path: entry.path, name: entry.deletingPathExtension().lastPathComponent))
                } else if depth > 0, (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    walk(entry, depth: depth - 1)
                }
            }
        }
        for root in roots { walk(root, depth: 1) }
        return LocalSources.rank(hits.sorted { $0.name < $1.name }, needle: name)
    }
}

/// The test folder walked by hand: the same rules as Spotlight's results, and no wait for an index.
@MainActor
final class FolderFinder: LocalFileFinder {
    private let home: URL
    init(home: URL) { self.home = home.resolvingSymlinksInPath() }

    func find(_ name: String) async -> [LocalHit] {
        let home = home
        return await Task.detached(priority: .userInitiated) { Self.walk(home, name: name) }.value
    }

    nonisolated private static func walk(_ home: URL, name: String) -> [LocalHit] {
        guard let items = FileManager.default.enumerator(at: home, includingPropertiesForKeys: nil, options: [.skipsPackageDescendants]) else { return [] }
        var hits: [LocalHit] = []
        for case let url as URL in items where LocalSources.match(url.lastPathComponent, needle: name) != nil && !LocalSources.isExcluded(url.path, home: home.path) {
            hits.append(LocalHit(path: url.path, name: url.lastPathComponent))
        }
        return hits.sorted { $0.path < $1.path }
    }
}

/// The real source: the Spotlight index, by file name only (`kMDItemFSName`), newest first. The home folder's own
/// non-hidden folders are the search scopes, so `~/Library` and hidden folders are not searched at all; files lying
/// directly in the home folder are matched from its listing. A hit also goes through `LocalSources.isExcluded`.
@MainActor
final class SpotlightFinder: LocalFileFinder {
    private let home: URL
    private let otherScopes: [URL]
    private let timeout: Duration
    private let log = Logger(subsystem: "brk", category: "local-search")
    /// How many hits are read from the index for one question; an index query can match a great many.
    static let readLimit = 300

    init(home: URL, otherScopes: [URL], timeout: Duration = .seconds(1.5)) {
        self.home = home.resolvingSymlinksInPath()
        self.otherScopes = otherScopes
        self.timeout = timeout
    }

    func find(_ name: String) async -> [LocalHit] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var scopes = otherScopes, direct: [LocalHit] = []
        for entry in entries {
            if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if entry.lastPathComponent != "Library" { scopes.append(entry) }
            } else if LocalSources.match(entry.lastPathComponent, needle: name) != nil {
                direct.append(LocalHit(path: entry.path, name: entry.lastPathComponent))
            }
        }
        let run = SpotlightRun(predicate: Self.predicate(for: name), scopes: scopes, timeout: timeout)
        let began = ContinuousClock.now
        let found = await withTaskCancellationHandler {
            await run.results()
        } onCancel: {
            Task { @MainActor in run.stop() }
        }
        log.info("spotlight: \(found.count) hits read in \(String(describing: began.duration(to: .now)), privacy: .public)")
        return direct + found.filter { !LocalSources.isExcluded($0.path, home: home.path) }
    }

    /// Every word of the name, anywhere in the file's name, case and accents aside; `*` and `?` in the text mean themselves.
    nonisolated static func predicate(for name: String) -> NSPredicate {
        let parts = name.split(whereSeparator: \.isWhitespace).map { word -> NSPredicate in
            var escaped = ""
            for character in word {
                if "*?\\".contains(character) { escaped.append("\\") }
                escaped.append(character)
            }
            return NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\(escaped)*")
        }
        // NSMetadataQuery throws on an AND of one.
        return parts.count == 1 ? parts[0] : NSCompoundPredicate(andPredicateWithSubpredicates: parts)
    }
}

/// One Spotlight question from start to answer. Ends when the index has gathered, at the timeout with what it has so far,
/// or when stopped.
@MainActor
final class SpotlightRun {
    private let query = NSMetadataQuery()
    private let timeout: Duration
    private var observer: (any NSObjectProtocol)?
    private var waiter: CheckedContinuation<[LocalHit], Never>?
    private var clock: Task<Void, Never>?
    private var finished = false

    init(predicate: NSPredicate, scopes: [URL], timeout: Duration) {
        query.predicate = predicate
        query.searchScopes = scopes
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        self.timeout = timeout
    }

    func results() async -> [LocalHit] {
        await withCheckedContinuation { continuation in
            guard !finished else { return continuation.resume(returning: []) }
            waiter = continuation
            observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            }
            let timeout = timeout
            clock = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                if !Task.isCancelled { self?.finish() }
            }
            if !query.start() { finish() }
        }
    }

    func stop() {
        finished = true
        finish()
    }

    private func finish() {
        guard let waiter else { return }
        self.waiter = nil
        clock?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        query.disableUpdates()
        var hits: [LocalHit] = []
        for index in 0..<min(query.resultCount, SpotlightFinder.readLimit) {
            guard let item = query.result(at: index) as? NSMetadataItem, let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            hits.append(LocalHit(path: path, name: (path as NSString).lastPathComponent))
        }
        query.stop()
        waiter.resume(returning: hits)
    }
}
