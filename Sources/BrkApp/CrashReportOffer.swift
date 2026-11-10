import BrkBase
import Foundation

/// A crash report macOS wrote for this app, as the bug form's title and Logs field show it.
struct CrashReport: Equatable, Sendable {
    var file: URL
    /// "Crash: EXC_BAD_ACCESS (SIGSEGV)".
    var title: String
    /// The report's header lines and the crashed thread's top frames, the home folder written as ~.
    var summary: String
}

/// The launch after a crash offers once to report it (Help's bug form, `HelpActions.offerCrashReport`).
///
/// "After a crash" means: a report of this app in ~/Library/Logs/DiagnosticReports newer than the previous launch.
/// Each launch records itself in `last-launch` in the data folder (the file's date), so a report is offered on the
/// first launch after it was written and never again. A first launch (no marker) offers nothing. The offer is off when
/// the user ticked "Don't offer again" (`enabledKey`), and under the control socket unless `BRK_CRASH_REPORTS_DIR`
/// names the folder to read (e2e runs crash on purpose and must not stop at an alert).
enum CrashReportOffer {
    static let enabledKey = "BrkOfferCrashReports"
    static let markerName = "last-launch"
    static let frameCount = 12

    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    static var systemDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    /// Reads the previous launch's date and records this launch. Nil on the first launch of a data folder.
    /// Writing the marker stamps it with the file system's time, the clock the crash reports' dates use (the app's
    /// clock may be a test clock).
    static func recordLaunch(dataDirectory: URL) -> Date? {
        let marker = dataDirectory.appendingPathComponent(markerName)
        let previous = (try? FileManager.default.attributesOfItem(atPath: marker.path))?[.modificationDate] as? Date
        try? Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8).write(to: marker)
        return previous
    }

    /// The newest report of this app in `directory` written after `since`: `<name>-<date>.ips` (or `.crash`), so the
    /// helpers' reports ("Brk Helper (Renderer)-…") are not taken, and for an .ips file whose header names a bundle id,
    /// only this app's.
    static func latest(in directory: URL, since: Date, name: String, bundleID: String?) -> CrashReport? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let candidates = files.compactMap { file -> (URL, Date)? in
            let base = file.lastPathComponent
            guard base.hasPrefix(name + "-"), base.dropFirst(name.count + 1).first?.isNumber == true,
                  ["ips", "crash"].contains(file.pathExtension),
                  let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date > since else { return nil }
            return (file, date)
        }
        for (file, _) in candidates.sorted(by: { $0.1 > $1.1 }) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if let bundleID, let header = header(of: text), let id = header["bundleID"] as? String, id != bundleID { continue }
            let (title, summary) = summarize(text, fileName: file.lastPathComponent)
            return CrashReport(file: file, title: title, summary: summary)
        }
        return nil
    }

    private static func header(of text: String) -> [String: Any]? {
        guard let first = text.split(separator: "\n", maxSplits: 1).first else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(first.utf8))) as? [String: Any]
    }

    /// The title and Logs text for a report. An .ips file is a JSON header line and a JSON body: the header's app,
    /// time and macOS, the body's exception, termination and the crashed thread's top frames. Any other text (an old
    /// `.crash` file, a body that does not parse): its first 30 lines.
    static func summarize(_ text: String, fileName: String, home: String = NSHomeDirectory()) -> (title: String, summary: String) {
        var lines = ["Crash report: \(fileName)"]
        var title = "Crash"
        let parts = text.split(separator: "\n", maxSplits: 1).map(String.init)
        if let head = header(of: text), parts.count == 2,
           let body = (try? JSONSerialization.jsonObject(with: Data(parts[1].utf8))) as? [String: Any] {
            func field(_ key: String, in object: [String: Any]) -> String? { (object[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            if let time = field("timestamp", in: head) { lines.append("Time: \(time)") }
            let app = [field("app_name", in: head), field("app_version", in: head), field("build_version", in: head).map { "(\($0))" }].compactMap { $0 }
            if !app.isEmpty { lines.append("App: " + app.joined(separator: " ")) }
            if let os = field("os_version", in: head) { lines.append("macOS: \(os)") }
            if let cpu = field("cpuType", in: body) { lines.append("CPU: \(cpu)" + ((body["translated"] as? Bool) == true ? " (Rosetta)" : "")) }
            if let exception = body["exception"] as? [String: Any], let type = field("type", in: exception) {
                let signal = field("signal", in: exception).map { " (\($0))" } ?? ""
                lines.append("Exception: \(type)\(signal)" + (field("subtype", in: exception).map { " \($0)" } ?? ""))
                title = "Crash: \(type)\(signal)"
            }
            if let termination = body["termination"] as? [String: Any], let indicator = field("indicator", in: termination) {
                lines.append("Termination: " + [field("namespace", in: termination), indicator].compactMap { $0 }.joined(separator: ", "))
                if title == "Crash" { title = "Crash: \(indicator)" }
            }
            if let index = body["faultingThread"] as? Int, let threads = body["threads"] as? [[String: Any]], threads.indices.contains(index) {
                let thread = threads[index]
                let images = body["usedImages"] as? [[String: Any]] ?? []
                let label = [field("name", in: thread), field("queue", in: thread)].compactMap { $0 }.joined(separator: ", ")
                lines.append("Crashed thread \(index)" + (label.isEmpty ? "" : " (\(label))") + ":")
                for (n, frame) in (thread["frames"] as? [[String: Any]] ?? []).prefix(frameCount).enumerated() {
                    let image = (frame["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0] : nil }
                    let imageName = image.flatMap { field("name", in: $0) ?? field("path", in: $0).map { ($0 as NSString).lastPathComponent } } ?? "???"
                    let place = field("symbol", in: frame).map { symbol in "\(symbol) + \(frame["symbolLocation"] as? Int ?? 0)" }
                        ?? "offset \(frame["imageOffset"] as? Int ?? 0)"
                    lines.append("  \(n)  \(imageName)  \(place)")
                }
            }
        } else {
            lines += text.components(separatedBy: "\n").prefix(30)
        }
        let summary = lines.joined(separator: "\n").replacingOccurrences(of: home, with: "~")
        return (title, summary)
    }
}
