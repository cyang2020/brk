import Foundation

/// One llama-server process for one model, outside the browser process: a crash, a hang or a 3 GB allocation stays in
/// the helper. It listens on a socket in a folder only this user can open. It starts on the first request, stops after
/// `idleTimeout` without one (the memory goes back to the system), and starts again when asked. It runs in its own
/// process group under a shell watcher that ends the group if Brk dies, so no helper outlives the browser.
public actor ModelHelper {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case noRuntime
        case noModelFile
        case startFailed(String)
        case notReady(String)
        case keepsStopping

        public var description: String {
            switch self {
            case .noRuntime: "This copy of Brk has no model runtime (llama-server)."
            case .noModelFile: "The model is not downloaded."
            case .startFailed(let why): "The model helper did not start: \(why)"
            case .notReady(let why): "The model helper did not get ready: \(why)"
            case .keepsStopping: "The model helper stopped several times in a row, so Brk is not starting it for now."
            }
        }
    }

    public let model: LocalModel
    private let modelFile: URL
    private let executable: URL
    private let runFolder: URL
    private let idleTimeout: Duration
    private let readyTimeout: Duration
    private var process: HelperProcess?
    private var starting: Task<UnixHTTP, any Error>?
    private var lastUse = ContinuousClock.now
    private var idleCheck: Task<Void, Never>?
    private var exits: [ContinuousClock.Instant] = []
    private var inFlight = 0

    public init(model: LocalModel, modelFile: URL, executable: URL, runFolder: URL,
                idleTimeout: Duration = .seconds(300), readyTimeout: Duration = .seconds(120)) {
        self.model = model
        self.modelFile = modelFile
        self.executable = executable
        self.runFolder = runFolder
        self.idleTimeout = idleTimeout
        self.readyTimeout = readyTimeout
    }

    var socket: URL { runFolder.appendingPathComponent("\(model.role.rawValue).sock") }
    var log: URL { runFolder.appendingPathComponent("\(model.role.rawValue).log") }

    public var isRunning: Bool { process?.isAlive == true }
    public var pid: Int32? { process?.pid }

    /// Runs `work` against a ready helper, starting it when needed; the idle clock starts after the last request ends.
    public func use<T: Sendable>(_ work: @Sendable (UnixHTTP) async throws -> T) async throws -> T {
        let http = try await ready()
        inFlight += 1
        defer { inFlight -= 1; lastUse = .now; scheduleIdleCheck() }
        return try await work(http)
    }

    func ready() async throws -> UnixHTTP {
        if let process, process.isAlive, starting == nil { return UnixHTTP(socket: socket) }
        if let starting { return try await starting.value }
        let recent = exits.filter { ContinuousClock.now - $0 < .seconds(600) }
        guard recent.count < 3 else { throw Failure.keepsStopping }
        let task = Task { try await self.launch() }
        starting = task
        defer { starting = nil }
        return try await task.value
    }

    private func launch() async throws -> UnixHTTP {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw Failure.noRuntime }
        guard FileManager.default.fileExists(atPath: modelFile.path) else { throw Failure.noModelFile }
        try FileManager.default.createDirectory(at: runFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runFolder.path)
        try? FileManager.default.removeItem(at: socket)
        let arguments = ["-m", modelFile.path, "--host", socket.path, "-ngl", "99", "--no-warmup", "-lv", "2"] + model.serverArguments
        let spawned: HelperProcess
        do {
            spawned = try HelperProcess.spawn(executable: executable, arguments: arguments, log: log) { [weak self] status in
                Task { await self?.exited(status) }
            }
        } catch {
            throw Failure.startFailed("\(error)")
        }
        process = spawned
        let http = UnixHTTP(socket: socket, timeout: 5)
        let deadline = ContinuousClock.now + readyTimeout
        while ContinuousClock.now < deadline {
            guard spawned.isAlive else { throw Failure.notReady("it exited; see \(log.path)") }
            if let reply = try? await http.get("/health"), reply.status == 200 { return UnixHTTP(socket: socket) }
            try await Task.sleep(for: .milliseconds(200))
        }
        spawned.stop()
        throw Failure.notReady("no answer in \(readyTimeout)")
    }

    private func exited(_ status: Int32) {
        guard process?.isAlive == false else { return }
        if process?.stopRequested == false { exits.append(.now) }
        process = nil
    }

    /// Ends the helper now (Brk quits, the model is removed, a setting turns local models off).
    public func stop() {
        idleCheck?.cancel()
        process?.stop()
        process = nil
    }

    private func scheduleIdleCheck() {
        idleCheck?.cancel()
        let wait = idleTimeout
        idleCheck = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self?.stopIfIdle()
        }
    }

    private func stopIfIdle() {
        guard inFlight == 0, ContinuousClock.now - lastUse >= idleTimeout else { return }
        stop()
    }
}

/// The spawned helper: its own process group, stdout and stderr to a log file truncated at each start, and a pipe whose
/// closing (Brk ending, by any route) makes the watcher end the group.
final class HelperProcess: @unchecked Sendable {
    let pid: pid_t
    private let lock = NSLock()
    private var watcher: Int32
    private var alive = true
    private var stopping = false

    private static let watcherScript = """
    { trap '' TERM; read -r _ <&3; kill -TERM 0; sleep 2; kill -KILL 0; } </dev/null >/dev/null 2>&1 &
    exec "$@" 3<&-
    """

    private init(pid: pid_t, watcher: Int32) {
        self.pid = pid
        self.watcher = watcher
    }

    var isAlive: Bool { lock.withLock { alive } }
    var stopRequested: Bool { lock.withLock { stopping } }

    static func spawn(executable: URL, arguments: [String], log: URL, exited: @escaping @Sendable (Int32) -> Void) throws -> HelperProcess {
        var watchPipe: [Int32] = [-1, -1]
        guard pipe(&watchPipe) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        _ = fcntl(watchPipe[1], F_SETFD, FD_CLOEXEC)
        _ = fcntl(watchPipe[1], F_SETNOSIGPIPE, 1)
        let logFD = open(log.path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        guard logFD >= 0 else { close(watchPipe[0]); close(watchPipe[1]); throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        let nullFD = open("/dev/null", O_RDONLY | O_CLOEXEC)
        defer { close(logFD); close(nullFD); close(watchPipe[0]) }

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_adddup2(&actions, nullFD, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, logFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, logFD, STDERR_FILENO)
        posix_spawn_file_actions_adddup2(&actions, watchPipe[0], 3)
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaults = sigset_t(), mask = sigset_t()
        sigfillset(&defaults)
        sigemptyset(&mask)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setsigmask(&attributes, &mask)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))
        // The helper's environment is not the browser's: only what it needs to find its libraries and write temp files.
        let environment = ["PATH=/usr/bin:/bin", "TMPDIR=\(NSTemporaryDirectory())", "HOME=\(NSHomeDirectory())"]
        let argv: [UnsafeMutablePointer<CChar>?] = (["/bin/sh", "-c", watcherScript, "brk-model-helper", executable.path] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) } + [nil]
        defer { for pointer in argv + envp { free(pointer) } }
        var child: pid_t = 0
        let status = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { values in
                posix_spawn(&child, "/bin/sh", &actions, &attributes, args.baseAddress!, values.baseAddress!)
            }
        }
        guard status == 0 else { close(watchPipe[1]); throw POSIXError(.init(rawValue: status) ?? .EIO) }
        let process = HelperProcess(pid: child, watcher: watchPipe[1])
        let leader = child
        // A blocking wait on a thread of its own: it reaps the helper and sees an exit however early it comes.
        Thread.detachNewThread { [weak process] in
            var code: Int32 = 0
            while waitpid(leader, &code, 0) < 0 && errno == EINTR {}
            process?.markExited()
            exited(code)
        }
        return process
    }

    private func markExited() {
        let fd = lock.withLock { () -> Int32 in
            alive = false
            let fd = watcher
            watcher = -1
            return fd
        }
        if fd >= 0 { close(fd) }
    }

    /// SIGTERM to the group, SIGKILL two seconds later if anything is left; closing the pipe makes the watcher do the same.
    func stop() {
        let fd = lock.withLock { () -> Int32 in
            stopping = true
            let fd = watcher
            watcher = -1
            return fd
        }
        kill(-pid, SIGTERM)
        if fd >= 0 { close(fd) }
        let pid = pid
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.isAlive != false { kill(-pid, SIGKILL) }
        }
    }

    deinit {
        if watcher >= 0 { close(watcher) }
    }
}
