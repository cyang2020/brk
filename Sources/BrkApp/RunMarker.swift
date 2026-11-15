import Foundation

/// Whether the last run of a data folder ended without Brk's own quit: a crash, a force quit, a power loss. The file
/// holds the running process's id; it is written at launch and removed once the quit has saved the state
/// (`Lifecycle.orderedQuit`), so a launch that finds it knows that run never got there, and holds the pages it would
/// load (`RestoreSeed.holdShownPages`). A second Brk on the same folder leaves the first one's marker alone.
enum RunMarker {
    static let name = "running"

    /// Records this launch. True when the previous launch of this folder did not finish its quit.
    static func begin(dataDirectory: URL, pid: Int32 = ProcessInfo.processInfo.processIdentifier,
                      isRunningBrk: (Int32) -> Bool = RunMarker.isRunningBrk) -> Bool {
        let file = dataDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else {
            write(pid, to: file, in: dataDirectory)
            return false
        }
        // That run is still going (another copy of Brk on this folder): not a run that ended badly, and its marker stays.
        if let owner = owner(of: file), owner != pid, isRunningBrk(owner) { return false }
        write(pid, to: file, in: dataDirectory)
        return true
    }

    /// The quit has saved everything: the next launch starts as usual. Only the process that wrote the marker removes it.
    static func end(dataDirectory: URL, pid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        let file = dataDirectory.appendingPathComponent(name)
        guard owner(of: file) == pid else { return }
        try? FileManager.default.removeItem(at: file)
    }

    private static func owner(of file: URL) -> Int32? {
        (try? String(contentsOf: file, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func write(_ pid: Int32, to file: URL, in directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data("\(pid)\n".utf8).write(to: file)
    }

    /// A live process running this same executable (an id reused by another program after a crash does not count).
    static func isRunningBrk(_ pid: Int32) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 || errno == EPERM else { return false }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        let path = String(cString: buffer)
        return path == Bundle.main.executablePath || path == ProcessInfo.processInfo.arguments.first
    }
}
