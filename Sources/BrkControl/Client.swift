import Foundation

/// A blocking Unix-socket client for the runner (and tests). One connection per scenario; `send` writes one request
/// line and reads one reply line.
public final class ControlClient {
    private let path: String
    private var fd: Int32 = -1
    private var nextID = 1

    public init(path: String) { self.path = path }

    /// Connects, retrying until `timeout` (the app creates the socket some time after launch: 1.2 s warm, 4.3 s on a
    /// first launch that creates the Chromium profile, spike unknown 7).
    public func connect(timeout: TimeInterval) throws {
        // TODO(W6): socket(AF_UNIX, SOCK_STREAM); sockaddr_un with path; retry connect every 100 ms until timeout.
        fatalError("not implemented")
    }

    public func send(_ op: ControlOp, timeout: TimeInterval = 30) throws -> ControlResult {
        // TODO(W6): ControlWire.encode(ControlRequest(id: nextID, op:)); write all; read until newline; decode
        // ControlReply; check id; return result. A `.failed(message)` result is returned, not thrown.
        fatalError("not implemented")
    }

    public func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
    }
}
