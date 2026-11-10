import AppKit
import BrkBase
import BrkDomain
import Foundation
import os

/// Finds files for the command bar by name (Spotlight's index); files by what they are about come from `FileMeaningIndex`.
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
    /// Ordinary typing also looks in the file index (off, the `file` prefix does). See `live`.
    private let filesWhileTyping: Bool
    private var pending: [WindowID: Task<Void, Never>] = [:]
    /// Files by meaning for the `file` mode (`FileMeaningIndex`, started by the first file search); merged with the
    /// names Spotlight found by `LocalSources.merge`.
    var fileMeaning: (@MainActor (String) async -> [LocalHit])?

    init(send: @escaping @MainActor (Input) -> Void, finder: (any LocalFileFinder)?, applicationRoots: [URL], filesWhileTyping: Bool = true,
         debounce: Duration = .seconds(Metrics.commandBar.suggestionDebounce.value)) {
        self.send = send
        self.finder = finder
        self.applicationRoots = applicationRoots
        self.filesWhileTyping = filesWhileTyping
        self.debounce = debounce
    }

    /// The real home folder, or under the control socket only the fixture folder.
    ///
    /// On the real path ordinary typing does not reach the file index, only the `file` prefix does. The first real search
    /// made macOS ask for the Desktop folder (324e78837a:verify/visual-pairs/run-20261103/cmdt/NOTES.md), and a question that comes up
    /// while typing a web search is one nobody asked for. Whether the home scope asks anything is not checked yet.
    static func live(send: @escaping @MainActor (Input) -> Void, options: LaunchOptions = LaunchOptions()) -> LocalSearch {
        if options.controlSocket != nil {
            guard let fixture = options.localSearchFixture else { return LocalSearch(send: send, finder: nil, applicationRoots: []) }
            let finder: any LocalFileFinder = options.localSearchSpotlight
                ? SpotlightFinder(home: fixture, scopes: [fixture])
                : FolderFinder(home: fixture)
            return LocalSearch(send: send, finder: finder, applicationRoots: [fixture.appendingPathComponent("Applications", isDirectory: true)])
        }
        let home = FileManager.default.homeDirectoryForCurrentUser, applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        return LocalSearch(send: send, finder: SpotlightFinder(home: home, scopes: [NSMetadataQueryUserHomeScope, applications]),
                           applicationRoots: [applications, URL(fileURLWithPath: "/System/Applications", isDirectory: true), home.appendingPathComponent("Applications", isDirectory: true)],
                           filesWhileTyping: false)
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
        let wantsFiles = request.scope == .files || (request.scope == .filesAndApps && filesWhileTyping)
        let meaning = request.scope == .files ? fileMeaning : nil
        pending[window] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let apps = request.scope != .files ? await Task.detached(priority: .userInitiated) { Self.apps(named: request.name, in: roots) }.value : []
            guard !Task.isCancelled else { return }
            var files = wantsFiles ? LocalSources.rank(await finder.find(request.name), needle: request.name) : []
            guard !Task.isCancelled else { return }
            if let meaning { files = LocalSources.merge(names: files, meaning: await meaning(request.name)) }
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

/// The real source: the Spotlight index, by file name only (`kMDItemFSName`), newest first. It asks the index and never
/// touches a folder or file itself: macOS asks the user before an app reads the Desktop, Documents or Downloads folder.
/// `~/Library` and hidden folders are in the home scope, so hits go through `LocalSources.isExcluded`.
@MainActor
final class SpotlightFinder: LocalFileFinder {
    private let home: URL
    private let scopes: [Any]
    private let timeout: Duration
    private let log = Logger(subsystem: "brk", category: "local-search")
    /// How many hits are kept for one question, and how many are looked at to find them: an index query can match a great
    /// many, and the newest of them can all be in `~/Library`.
    static let readLimit = 300, scanLimit = 3000

    init(home: URL, scopes: [Any], timeout: Duration = .seconds(1.5)) {
        self.home = home.resolvingSymlinksInPath()
        self.scopes = scopes
        self.timeout = timeout
    }

    func find(_ name: String) async -> [LocalHit] {
        let homePath = home.path
        let run = SpotlightRun(predicate: Self.predicate(for: name), scopes: scopes, timeout: timeout) { !LocalSources.isExcluded($0, home: homePath) }
        let began = ContinuousClock.now
        let found = await withTaskCancellationHandler {
            await run.results()
        } onCancel: {
            Task { @MainActor in run.stop() }
        }
        log.info("spotlight: \(found.count) hits read in \(String(describing: began.duration(to: .now)), privacy: .public)")
        return found
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
    private let keeps: (String) -> Bool

    init(predicate: NSPredicate, scopes: [Any], timeout: Duration, keeps: @escaping (String) -> Bool = { _ in true }) {
        self.keeps = keeps
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
        for index in 0..<min(query.resultCount, SpotlightFinder.scanLimit) where hits.count < SpotlightFinder.readLimit {
            guard let item = query.result(at: index) as? NSMetadataItem, let path = item.value(forAttribute: NSMetadataItemPathKey) as? String, keeps(path) else { continue }
            hits.append(LocalHit(path: path, name: (path as NSString).lastPathComponent, contentType: item.value(forAttribute: NSMetadataItemContentTypeKey) as? String))
        }
        query.stop()
        waiter.resume(returning: hits)
    }
}
