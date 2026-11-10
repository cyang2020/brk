import BrkBase
import BrkDomain
import BrkLocalModels
import Foundation
import os
import UniformTypeIdentifiers

/// A file the lister found: where it is, how big, when its content last changed.
struct ListedFile: Hashable, Sendable {
    let path: String
    let size: Int
    let modified: Double
}

/// Lists the files the file index may hold and reports the whole list again whenever it changes.
protocol FileLister: AnyObject, Sendable {
    func start(_ changed: @escaping @Sendable ([ListedFile]) -> Void)
    func stop()
}

/// Owner: files by meaning (the command bar's `file` mode, and rows by meaning while typing). One index per Mac in
/// `<data>/Local Models/Files/files.vectors`: a vector per document of the file's name and the start of its text
/// (`FileText`), read and embedded on this Mac by the local search model; nothing is sent anywhere, and the index file
/// holds vectors and hashes, no text.
///
/// When it runs: from the first `file` search with the search model ready (`begin`), and from then on at every launch
/// (the index file is there). Reading a file in Desktop, Documents or Downloads makes macOS ask once per folder, so the
/// first indexing starts only from an explicit file search, never from ordinary typing; once answered, macOS does not
/// ask again. Ordinary typing only reads this index (`search`), which asks nothing. Removing the search model removes
/// the index.
@MainActor
final class FileMeaningIndex {
    private let models: LocalModels
    private let lister: any FileLister
    private let home: String
    let file: URL
    private let log = Logger(subsystem: "Brk", category: "file-index")
    private lazy var index = SemanticIndex(file: file)
    private var listed: [ListedFile] = []
    private var started = false
    private var pending: Task<Void, Never>?
    private var running: Task<Void, Never>?
    private var again = false
    private var passes = 0
    let debounce: Duration
    /// Files the last pass embedded and the whole index's size, for the log and the tests.
    private(set) var lastPass: (embedded: Int, total: Int) = (0, 0)

    init(models: LocalModels, lister: any FileLister, home: URL, file: URL, debounce: Duration = .seconds(5)) {
        self.models = models
        self.lister = lister
        self.home = home.resolvingSymlinksInPath().path
        self.file = file
        self.debounce = debounce
    }

    /// The real home folder through Spotlight; under the control socket only `LaunchOptions.localSearchFixture`, walked by
    /// hand, and nothing without one.
    static func live(models: LocalModels, options: LaunchOptions = LaunchOptions()) -> FileMeaningIndex? {
        let file = models.root.appendingPathComponent("Files", isDirectory: true).appendingPathComponent("files.vectors")
        if options.controlSocket != nil {
            guard let fixture = options.localSearchFixture else { return nil }
            return FileMeaningIndex(models: models, lister: FolderLister(root: fixture), home: fixture, file: file, debounce: .milliseconds(200))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return FileMeaningIndex(models: models, lister: SpotlightLister(home: home), home: home, file: file)
    }

    var isActive: Bool { started && models.status(.search).usable }

    /// At launch: carries on when an earlier file search made the index.
    func resumeIfIndexed() {
        if FileManager.default.fileExists(atPath: file.path) { begin() }
    }

    /// The user searched files: list and index them from now on (see the type's note on macOS's folder questions).
    func begin() {
        guard !started, models.status(.search).usable else { return }
        started = true
        log.notice("file index: started")
        lister.start { [weak self] files in
            Task { @MainActor in self?.listChanged(files) }
        }
    }

    /// The search model went away: no vectors stay without it.
    func removeAll() {
        started = false
        lister.stop()
        pending?.cancel(); running?.cancel(); running = nil
        listed = []
        let index = index
        Task { await index.removeAll() }
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    private func listChanged(_ files: [ListedFile]) {
        listed = files
        pending?.cancel()
        let wait = debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.startPass()
        }
    }

    /// Drops what is gone or changed, then reads and embeds what is new, in batches, off the main thread.
    private func startPass() {
        guard running == nil else { again = true; return }
        guard let embedder = models.embedder else { return }
        let entries = listed.map(Self.entry)
        let index = index, log = log
        running = Task.detached(priority: .utility) { [weak self] in
            var embedded = 0
            do {
                try await index.reconcile(entries, embedder: nil)
                let todo = await index.missing(entries)
                var start = 0
                while start < todo.count {
                    try Task.checkCancellation()
                    let batch = todo[start..<min(start + 32, todo.count)].map { entry -> IndexEntry in
                        var read = entry
                        let path = String(entry.key.dropFirst("file:".count))
                        read.description = FileText.read(URL(fileURLWithPath: path))
                        return read
                    }
                    embedded += try await index.add(batch, embedder: embedder)
                    start += 32
                }
            } catch is CancellationError {
            } catch {
                log.error("file index: \(String(describing: error), privacy: .public)")
            }
            let total = await index.count
            await self?.passFinished(embedded: embedded, total: total)
        }
    }

    private func passFinished(embedded: Int, total: Int) {
        running = nil
        passes += 1
        lastPass = (embedded, total)
        log.notice("file index pass: \(embedded) embedded, \(total) files")
        if again { again = false; startPass() }
    }

    /// The first file search starts the index and would otherwise ask it while it is still empty (and the bar does not
    /// ask again for the same text): it waits, up to `limit`, until the first pass has finished or holds vectors.
    func firstVectors(within limit: Duration) async {
        let deadline = ContinuousClock.now + limit
        while started, passes == 0, ContinuousClock.now < deadline, await index.count == 0 {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Waits for the indexing under way (tests and the measuring harness).
    func settle() async {
        while pending != nil || running != nil {
            if let pending { await pending.value; self.pending = nil }
            if let running { await running.value }
        }
    }

    nonisolated static func entry(_ file: ListedFile) -> IndexEntry {
        IndexEntry(kind: .file, id: file.path, title: (file.path as NSString).lastPathComponent, url: "", version: "\(file.size)|\(Int(file.modified))")
    }

    /// Files whose name and text are about `text`, best first, passing both checks of `MeaningSearch` over this index;
    /// nil when the index is not running. Reads only Brk's own index file.
    func search(_ text: String, limit: Int = 5) async -> [(hit: LocalHit, score: Float)]? {
        guard isActive, let embedder = models.embedder else { return nil }
        guard let vector = try? await embedder.embed([.query(text)]).first else { return nil }
        let hits = await index.search(vector, limit: limit, kinds: [.file], minimum: Float(MeaningSearch.minimumScore), lead: Float(MeaningSearch.minimumLead))
        return hits.map { hit in
            let path = String(hit.key.dropFirst("file:".count))
            let type = UTType(filenameExtension: (path as NSString).pathExtension)?.identifier
            return (LocalHit(path: path, name: (path as NSString).lastPathComponent, contentType: type), hit.score)
        }
    }
}

// MARK: Which files

enum FileIndexRules {
    /// Documents and source code kept at most, the newest first: a large source tree must not push documents out.
    static let documentLimit = 15_000, sourceLimit = 5_000
    /// Folders whose files are built, fetched or vendored rather than written by the user.
    static let skippedFolders: Set<String> = ["node_modules", "build", "DerivedData", "Pods", "vendor", "target", "dist", "out", "__pycache__",
                                              "venv", "site-packages", "third_party", "Carthage", "bower_components"]
    /// Packages that look like folders to the file system.
    static let skippedPackages: Set<String> = ["app", "photoslibrary", "framework", "bundle", "xcarchive", "xcodeproj", "xcworkspace", "musiclibrary", "photolibrary"]

    /// Whether a listed file may be indexed: readable kind and size, outside `~/Library`, hidden folders, packages and
    /// built or vendored folders (`LocalSources.isExcluded` for the first three).
    static func keeps(_ path: String, size: Int, home: String) -> Bool {
        guard FileText.readable(path, size: size), !LocalSources.isExcluded(path, home: home) else { return false }
        let inside = path.hasPrefix(home + "/") ? String(path.dropFirst(home.count + 1)) : path
        return !inside.split(separator: "/").dropLast().contains { part in
            skippedFolders.contains(String(part)) || skippedPackages.contains((String(part) as NSString).pathExtension.lowercased())
        }
    }

    static func isSource(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return FileText.plain.contains(ext) && !["txt", "text", "md", "markdown", "rst", "org", "tex", "csv", "tsv", "log"].contains(ext)
    }

    /// The newest files first, capped per kind.
    static func capped(_ files: [ListedFile]) -> [ListedFile] {
        var documents = 0, sources = 0
        return files.sorted { $0.modified > $1.modified }.filter { file in
            if isSource(file.path) { sources += 1; return sources <= sourceLimit }
            documents += 1
            return documents <= documentLimit
        }
    }
}

/// The test folder walked by hand: the same rules, listed once.
final class FolderLister: FileLister, @unchecked Sendable {
    private let root: URL
    init(root: URL) { self.root = root }

    func start(_ changed: @escaping @Sendable ([ListedFile]) -> Void) {
        let root = root
        Task.detached(priority: .utility) { changed(Self.walk(root)) }
    }

    static func walk(_ folder: URL) -> [ListedFile] {
        // The enumerator answers real paths (/private/var/…, which Foundation's own resolving shortens to /var/…): the
        // rules must see the folder the same way.
        let root = real(folder)
        var files: [ListedFile] = []
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        for case let url as URL in FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) ?? NSEnumerator() {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let size = values.fileSize ?? 0
            guard FileIndexRules.keeps(url.path, size: size, home: root.path) else { continue }
            files.append(ListedFile(path: url.path, size: size, modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0))
        }
        return FileIndexRules.capped(files)
    }

    func stop() {}

    static func real(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }
}

/// Spotlight's live query over the home folder: documents, PDFs, rich text and source code, newest first. It asks the
/// index for paths, sizes and dates and touches no folder; its update notifications (added, changed, removed) keep the
/// list current. Runs on its own queue.
final class SpotlightLister: NSObject, FileLister, @unchecked Sendable {
    private let home: String
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()
    private var query: NSMetadataQuery?
    private var observers: [any NSObjectProtocol] = []
    private var files: [String: ListedFile] = [:]
    private var changed: (@Sendable ([ListedFile]) -> Void)?
    /// Results looked at, newest first, to find the kept ones.
    static let scanLimit = 80_000
    static let types = ["public.text", "com.adobe.pdf", "public.rtf", "org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc",
                        "org.oasis-open.opendocument.text"]

    init(home: URL) { self.home = home.resolvingSymlinksInPath().path }

    func start(_ changed: @escaping @Sendable ([ListedFile]) -> Void) {
        queue.addOperation { [self] in
            self.changed = changed
            let query = NSMetadataQuery()
            query.operationQueue = queue
            query.searchScopes = [NSMetadataQueryUserHomeScope]
            query.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: Self.types.map { NSPredicate(format: "%K == %@", "kMDItemContentTypeTree", $0) })
            query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
            query.notificationBatchingInterval = 5
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: queue) { [weak self] _ in self?.gathered() },
                center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: queue) { [weak self] note in self?.updated(note) },
            ]
            self.query = query
            query.start()
        }
    }

    func stop() {
        queue.addOperation { [self] in
            query?.stop()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            query = nil
            files = [:]
        }
    }

    private func listed(_ item: NSMetadataItem) -> ListedFile? {
        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
              let size = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.intValue,
              FileIndexRules.keeps(path, size: size, home: home) else { return nil }
        let date = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
        return ListedFile(path: path, size: size, modified: date?.timeIntervalSince1970 ?? 0)
    }

    private func gathered() {
        guard let query else { return }
        query.disableUpdates()
        var found: [ListedFile] = []
        for index in 0..<min(query.resultCount, Self.scanLimit) {
            if let item = query.result(at: index) as? NSMetadataItem, let file = listed(item) { found.append(file) }
        }
        query.enableUpdates()
        files = Dictionary(FileIndexRules.capped(found).map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        changed?(Array(files.values))
    }

    private func updated(_ note: Notification) {
        let info = note.userInfo ?? [:]
        for item in (info[NSMetadataQueryUpdateRemovedItemsKey] as? [NSMetadataItem]) ?? [] {
            if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String { files[path] = nil }
        }
        for key in [NSMetadataQueryUpdateAddedItemsKey, NSMetadataQueryUpdateChangedItemsKey] {
            for item in (info[key] as? [NSMetadataItem]) ?? [] {
                if let file = listed(item) { files[file.path] = file }
            }
        }
        changed?(FileIndexRules.capped(Array(files.values)))
    }
}
