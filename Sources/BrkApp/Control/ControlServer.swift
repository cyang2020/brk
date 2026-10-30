import AppKit
import BrkBase
import BrkControl
import os

/// The app side of the control socket (protocol: BrkControl/Protocol.swift). Accepts on a background queue, serves
/// each connection on its own thread: one `ControlRequest` per line, run on the main actor through `ControlExecutor`,
/// one reply per line with the request's id. Requests on one connection run in order. Started only when
/// BRK_CONTROL_SOCKET is set; never in a normal launch.
///
/// `quit` replies first and then starts the ordered quit, so the reply is on the wire before the process can exit.
/// When the quit completes cleanly (`willTerminate`), the engine's final page log is written to
/// `<data dir>/control-pagelog.json` (ControlWire JSON of `[PageLogEntry]`), because the socket is gone by the time
/// the last OnBeforeClose arrives; the runner reads it after exit (N4).
final class ControlServer: @unchecked Sendable {
    static let finalPageLogName = "control-pagelog.json"

    private let path: String
    private let executor: ControlExecutor
    private let queue = DispatchQueue(label: "brk.control")
    private let lock = NSLock()
    private var source: DispatchSourceRead?
    private let log = Logger(subsystem: "brk", category: "control")

    init(path: String, executor: ControlExecutor) {
        self.path = path
        self.executor = executor
    }

    /// Nonisolated on purpose: the dispatch-source handlers formed here run on the control queue, and a closure
    /// formed in a main-actor method would inherit main-actor isolation and trap there (Swift 6 runtime check).
    func start() throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let bound = try withSocketAddress(path) { address, length in bind(fd, address, length) }
        guard bound == 0, listen(fd, 8) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(fd)
            throw POSIXError(code)
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne(fd) }
        source.setCancelHandler { [path] in
            close(fd)
            unlink(path)
        }
        source.resume()
        lock.withLock { self.source = source }

        let executor = executor
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { executor.writeFinalPageLog(named: Self.finalPageLogName) }
        }
        log.notice("control socket listening at \(self.path, privacy: .public)")
    }

    /// Stops accepting new connections. Open connections stay until their in-flight reply is written and the peer
    /// closes (the runner reads `quit`'s reply on one of them).
    func stopAccepting() {
        lock.withLock {
            source?.cancel()
            source = nil
        }
    }

    // MARK: Connections

    private func acceptOne(_ listener: Int32) {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { return }
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let thread = Thread { [self] in serve(client) }
        thread.name = "brk.control.connection"
        thread.start()
    }

    /// Blocking read loop for one connection.
    private func serve(_ fd: Int32) {
        var buffer = ControlLineBuffer()
        var chunk = [UInt8](repeating: 0, count: 65_536)
        defer { close(fd) }
        while true {
            while let line = buffer.nextLine() {
                let (reply, quitAfter) = handle(line)
                guard let data = try? ControlWire.encode(reply), writeAll(fd, data) else { return }
                if quitAfter { Task { @MainActor [executor] in executor.startQuit() } }
            }
            let n = read(fd, &chunk, chunk.count)
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return }
            buffer.append(Data(chunk[0..<n]))
        }
    }

    /// Decodes and runs one request on the main actor, blocking this connection's thread until the reply exists.
    private func handle(_ line: Data) -> (ControlReply, quitAfter: Bool) {
        switch ControlWire.parseRequest(line) {
        case .failure(let error):
            return (ControlReply(id: error.id ?? -1, result: .failed("bad request: \(error.message)")), false)
        case .success(let request):
            if case .quit = request.op { return (ControlReply(id: request.id, result: .ok), true) }
            let done = DispatchSemaphore(value: 0)
            let box = ResultBox()
            let executor = executor
            Task { @MainActor in
                box.result = await executor.run(request.op)
                done.signal()
            }
            done.wait()
            return (ControlReply(id: request.id, result: box.result ?? .failed("no result")), false)
        }
    }

    private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { raw in write(fd, raw.baseAddress! + offset, raw.count - offset) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return false }
            offset += n
        }
        return true
    }
}

/// Carries one op's result from the main actor to the connection thread (written before the semaphore signals).
private final class ResultBox: @unchecked Sendable {
    var result: ControlResult?
}
