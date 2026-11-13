import Foundation

/// `brk-e2e --app <Brk.app or executable> --site <dir> --out <dir> [--only 0,4,R6]`.
/// Every run exercises BrkCore.
struct RunnerArguments {
    var app: URL
    var executable: URL
    var site: URL
    var outputDirectory: URL
    var only: Set<String>?
    let engine = Engine.core

    enum Engine: String { case core }

    struct UsageError: Error, CustomStringConvertible {
        let description: String
    }

    static let usage = "usage: brk-e2e --app <Brk.app | executable> --site <Tests/E2ESite> --out <folder> [--only 0,4,R6]"

    init(_ argv: [String], environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        var values: [String: String] = [:]
        var rest = Array(argv.dropFirst())
        while !rest.isEmpty {
            let flag = rest.removeFirst()
            guard ["--app", "--site", "--out", "--only"].contains(flag), !rest.isEmpty else {
                throw UsageError(description: "unexpected argument \(flag)\n\(Self.usage)")
            }
            values[flag] = rest.removeFirst()
        }
        guard let app = values["--app"], let site = values["--site"], let out = values["--out"] else {
            throw UsageError(description: Self.usage)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        self.app = URL(fileURLWithPath: app, relativeTo: cwd).standardizedFileURL
        self.site = URL(fileURLWithPath: site, relativeTo: cwd).standardizedFileURL
        outputDirectory = URL(fileURLWithPath: out, relativeTo: cwd).standardizedFileURL
        only = values["--only"].map { Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }

        if self.app.pathExtension == "app" {
            guard let executable = Bundle(url: self.app)?.executableURL else {
                throw UsageError(description: "\(self.app.path) is not an app bundle with an executable (run scripts/build.sh)")
            }
            self.executable = executable
        } else {
            executable = self.app
        }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw UsageError(description: "no executable at \(executable.path)")
        }
        guard FileManager.default.fileExists(atPath: self.site.appendingPathComponent("index.html").path) else {
            throw UsageError(description: "no fixture site at \(self.site.path) (index.html missing)")
        }
    }
}
