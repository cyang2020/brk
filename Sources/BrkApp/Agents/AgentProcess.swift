import Foundation

/// The processes in one agent's tree, read from the kernel's process table. A command an agent runs often sits in its
/// own process group, so signalling the agent's group alone would leave it running.
enum ProcessTree {
    struct Entry: Equatable, Sendable {
        let pid: pid_t
        let parent: pid_t
        let group: pid_t
    }

    static func snapshot() -> [Entry] {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&name, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // Room for processes started between the two calls.
        let capacity = size / MemoryLayout<kinfo_proc>.stride + 32
        var table = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        size = capacity * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&name, 4, &table, &size, nil, 0) == 0 else { return [] }
        return table.prefix(size / MemoryLayout<kinfo_proc>.stride).map {
            Entry(pid: $0.kp_proc.p_pid, parent: $0.kp_eproc.e_ppid, group: $0.kp_eproc.e_pgid)
        }
    }

    /// Every process under `root` and every process in its group, `root` included while it lives.
    static func members(root: pid_t, in table: [Entry]) -> Set<pid_t> {
        var found = Set(table.filter { $0.group == root || $0.pid == root }.map(\.pid))
        var children: [pid_t: [pid_t]] = [:]
        for entry in table { children[entry.parent, default: []].append(entry.pid) }
        var queue = Array(found)
        while let next = queue.popLast() {
            for child in children[next] ?? [] where found.insert(child).inserted { queue.append(child) }
        }
        return found
    }
}

/// Bytes split into lines; a partial line waits for the next read.
struct LineSplitter {
    private var pending = Data()
    /// Longer than this is not a protocol line: the agent is stopped rather than Brk's memory filled.
    static let limit = 16 << 20
    var overflowed: Bool { pending.count > Self.limit }

    mutating func feed(_ chunk: Data) -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        while let end = pending.firstIndex(of: 0x0A) {
            lines.append(pending[pending.startIndex..<end])
            pending.removeSubrange(pending.startIndex...end)
        }
        pending = Data(pending)
        return lines
    }
}

/// One agent process: its stdin, its stdout as it arrives, the end of its stderr, and a stop that reaches everything it
/// started. It runs in its own process group under a small shell watcher, which ends the group if Brk itself dies, so
/// a crash leaves no agent working. No blocking read or wait runs on the main actor.
final class AgentProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let executable: URL
    private let arguments: [String]
    private let directory: URL
    private let environment: [String: String]
    private let writes = DispatchQueue(label: "brk.agent.stdin", qos: .utility)
    private var leader: pid_t = 0
    private var input: Int32 = -1
    private var watcher: Int32 = -1
    private var ended = false
    private var stopRequested = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var seen: Set<pid_t> = []
    private var finished = false
    /// Time between the polite signal and the one that cannot be refused.
    static let grace: TimeInterval = 0.5
    private static let errorTail = 16_384

    /// Ends the watcher after the agent is gone, and the group with it, if Brk dies first (the read end is the watcher's).
    private static let watcherScript = """
    { trap '' TERM; read -r _ <&3; kill -TERM 0; sleep 2; kill -KILL 0; } </dev/null >/dev/null 2>&1 &
    exec "$@" 3<&-
    """

    init(executable: URL, arguments: [String], directory: URL, environment: [String: String]) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        self.environment = environment
    }

    var pid: pid_t { lock.withLock { leader } }

    /// Starts the process. `output` gets stdout's bytes on the main queue, in order; `exit` comes after the last of them.
    func start(output: @escaping @MainActor @Sendable (Data) -> Void,
               exit: @escaping @MainActor @Sendable (_ status: Int32, _ stderr: String) -> Void) throws {
        var stdinPipe: [Int32] = [-1, -1], stdoutPipe: [Int32] = [-1, -1], stderrPipe: [Int32] = [-1, -1], watchPipe: [Int32] = [-1, -1]
        for index in 0..<4 {
            let status = index == 0 ? pipe(&stdinPipe) : index == 1 ? pipe(&stdoutPipe) : index == 2 ? pipe(&stderrPipe) : pipe(&watchPipe)
            guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        // Chromium's helpers fork from this process too: none of these may be inherited by anything else.
        for fd in stdinPipe + stdoutPipe + stderrPipe + watchPipe { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        // A write after the agent went away is an error, not a signal that takes Brk down.
        _ = fcntl(stdinPipe[1], F_SETNOSIGPIPE, 1)
        _ = fcntl(watchPipe[1], F_SETNOSIGPIPE, 1)

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_adddup2(&actions, stdinPipe[0], STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_adddup2(&actions, watchPipe[0], 3)
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        posix_spawnattr_setpgroup(&attributes, 0)
        // Brk ignores SIGTERM for its own orderly quit, and children inherit that unless told otherwise.
        var defaults = sigset_t(), mask = sigset_t()
        sigemptyset(&defaults); sigaddset(&defaults, SIGTERM); sigaddset(&defaults, SIGINT); sigaddset(&defaults, SIGPIPE)
        sigemptyset(&mask)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setsigmask(&attributes, &mask)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))
        let argv: [UnsafeMutablePointer<CChar>?] = (["/bin/sh", "-c", Self.watcherScript, "brk-agent", executable.path] + arguments).map { strdup($0) } + [nil]
        defer { for pointer in argv { free(pointer) } }
        let env: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { for pointer in env { free(pointer) } }
        var child: pid_t = 0
        let status = argv.withUnsafeBufferPointer { args in
            env.withUnsafeBufferPointer { values in
                posix_spawn(&child, "/bin/sh", &actions, &attributes, args.baseAddress!, values.baseAddress!)
            }
        }
        close(stdinPipe[0]); close(stdoutPipe[1]); close(stderrPipe[1]); close(watchPipe[0])
        guard status == 0 else {
            close(stdinPipe[1]); close(stdoutPipe[0]); close(stderrPipe[0]); close(watchPipe[1])
            throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EIO)
        }
        lock.withLock { leader = child; input = stdinPipe[1]; watcher = watchPipe[1] }
        let stdoutRead = stdoutPipe[0], stderrRead = stderrPipe[0]

        let readers = DispatchGroup()
        let errors = TailBuffer(limit: Self.errorTail)
        readers.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { readers.leave() }
            pump(stdoutRead) { chunk in
                DispatchQueue.main.async { MainActor.assumeIsolated { output(chunk) } }
            }
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { readers.leave() }
            pump(stderrRead) { errors.append($0) }
        }
        DispatchQueue.global(qos: .utility).async { [self] in
            var raw: Int32 = 0
            while waitpid(child, &raw, 0) == -1 && errno == EINTR {}
            // The leader is gone: nothing it started may outlive it, and only that leaves the pipes to end.
            signal(SIGKILL, including: tree())
            lock.withLock { ended = true }
            // A process that left the group can hold stdout open; the reader gives up on it shortly after.
            readers.wait()
            let code = (raw & 0x7f) == 0 ? (raw >> 8) & 0xff : 128 + (raw & 0x7f)
            let text = String(decoding: errors.value(), as: UTF8.self)
            closeInput()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { exit(code, text) }
                self.finish()
            }
        }
    }

    /// Reads until end of file, or until the leader has been gone for a moment.
    private func pump(_ fd: Int32, _ deliver: (Data) -> Void) {
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var idleAfterEnd = 0
        while true {
            var ready = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let polled = poll(&ready, 1, 200)
            if polled == 0 {
                if lock.withLock({ ended }) { idleAfterEnd += 1; if idleAfterEnd >= 3 { return } }
                continue
            }
            if polled < 0 { if errno == EINTR { continue }; return }
            let count = read(fd, &buffer, buffer.count)
            if count == 0 { return }
            if count < 0 { if errno == EINTR { continue }; return }
            deliver(Data(buffer[0..<count]))
        }
    }

    private func finish() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            finished = true
            let list = waiters; waiters = []; return list
        }
        for waiter in waiting { waiter.resume() }
    }

    /// One write at a time, off the main actor: a full pipe must not stall the browser.
    func write(_ data: Data) {
        writes.async { [self] in
            guard let fd = lock.withLock({ input >= 0 ? input : nil }) else { return }
            data.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let count = writeBytes(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                    if count < 0 { if errno == EINTR { continue }; return }
                    offset += count
                }
            }
        }
    }

    private func closeInput() {
        writes.async { [self] in
            let fds = lock.withLock { () -> [Int32] in
                let list = [input, watcher].filter { $0 >= 0 }
                input = -1; watcher = -1
                return list
            }
            for fd in fds { close(fd) }
        }
    }

    /// What is running under this process now, remembered: after the leader dies its children no longer lead back to it.
    private func tree() -> Set<pid_t> {
        let root = pid
        guard root > 0 else { return [] }
        let found = ProcessTree.members(root: root, in: ProcessTree.snapshot())
        return lock.withLock { seen.formUnion(found); return seen }
    }

    /// Processes under the agent right now, the agent itself left out.
    func descendants() -> Set<pid_t> {
        let root = pid
        guard root > 0 else { return [] }
        var found = ProcessTree.members(root: root, in: ProcessTree.snapshot())
        found.remove(root)
        return found
    }

    /// Ends the given processes (what the agent's own stop left behind), each group's stragglers included.
    func end(_ processes: Set<pid_t>) {
        guard !processes.isEmpty else { return }
        for pid in processes { kill(pid, SIGTERM) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.grace) {
            for pid in processes { kill(pid, SIGKILL) }
        }
    }

    private func signal(_ value: Int32, including members: Set<pid_t>) {
        let root = pid
        if root > 0 { kill(-root, value) }
        for member in members where member > 1 { kill(member, value) }
    }

    /// Ends the whole tree: politely, then for certain. Safe to call more than once.
    func stop() {
        let root = lock.withLock { () -> pid_t in
            if ended || stopRequested { return 0 }
            stopRequested = true
            return leader
        }
        guard root > 0 else { return }
        signal(SIGTERM, including: tree())
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.grace) { [self] in
            // A process that forked while the first signal went out is in this list and not the last one.
            signal(SIGKILL, including: tree())
        }
    }

    /// Returns once the process has exited and its last output was delivered; after `stop()` that is within `grace`
    /// plus a moment.
    func waitForExit() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let done = lock.withLock { () -> Bool in
                if leader == 0 || finished { return true }
                waiters.append(continuation)
                return false
            }
            if done { continuation.resume() }
        }
    }
}

/// The system call, outside the class whose own `write` would hide it.
private func writeBytes(_ fd: Int32, _ pointer: UnsafeRawPointer, _ count: Int) -> Int { write(fd, pointer, count) }

private final class TailBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limit: Int
    init(limit: Int) { self.limit = limit }
    func append(_ next: Data) {
        lock.withLock {
            data.append(next)
            if data.count > limit { data = Data(data.suffix(limit)) }
        }
    }
    func value() -> Data { lock.withLock { data } }
}
