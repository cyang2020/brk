import BrkControl
import Foundation

/// `Brk --brk-tools <base>`: what an agent CLI starts as Brk's MCP server. It is only a pipe: stdin to the running Brk's
/// socket for this conversation, the socket to stdout. It starts nothing else, so it runs before Chromium or AppKit load.
public enum BrkToolBridge {
    /// Runs the bridge and exits when `arguments` ask for it; returns at once otherwise.
    public static func runIfAsked(_ arguments: [String] = CommandLine.arguments) {
        guard arguments.count == 3, arguments[1] == BrkToolEndpoint.bridgeFlag else { return }
        exit(run(base: arguments[2]))
    }

    static func run(base: String) -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        func fail(_ text: String) -> Int32 {
            FileHandle.standardError.write(Data("Brk's tab tools are not available: \(text)\n".utf8))
            return 1
        }
        guard let token = try? String(contentsOfFile: base + ".token", encoding: .utf8), !token.isEmpty else {
            return fail("this conversation has ended in Brk.")
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return fail("no socket.") }
        guard (try? withSocketAddress(base + ".sock") { address, length in connect(fd, address, length) }) == 0 else {
            return fail("Brk is not running this conversation any more.")
        }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let hello = try! JSONSerialization.data(withJSONObject: ["brkToolsToken": token]) + Data([0x0A])
        guard pump(hello, to: fd) else { return fail("Brk closed the connection.") }
        // The agent closing stdin ends the bridge; Brk closing the socket does too.
        let input = Thread {
            copy(from: 0, to: fd)
            exit(0)
        }
        input.start()
        copy(from: fd, to: 1)
        return 0
    }

    private static func copy(from source: Int32, to destination: Int32) {
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(source, &chunk, chunk.count)
            if n < 0, errno == EINTR { continue }
            guard n > 0, pump(Data(chunk[0..<n]), to: destination) else { return }
        }
    }

    private static func pump(_ data: Data, to fd: Int32) -> Bool {
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
