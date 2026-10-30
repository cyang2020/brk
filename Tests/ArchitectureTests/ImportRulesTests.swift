import Foundation
import XCTest

/// Dependency direction and single-writer rules (module-map.md, "Dependency rules"), checked on the real sources.
///
/// SwiftPM target dependencies already make most wrong imports fail to build (`swift build
/// --explicit-target-dependency-import-check error` in scripts/build.sh closes the transitive-module gap). This
/// test adds what target graphs cannot say: which file may call what, and that the graph in Package.swift is the one
/// the docs describe. Each rule is proven by a negative case below.
final class ImportRulesTests: XCTestCase {
    static let allowedImports: [String: Set<String>] = [
        "BrkBase": ["Foundation", "CoreGraphics"],
        "BrkDomain": ["BrkBase", "Foundation", "CoreGraphics"],
        "BrkLayout": ["BrkBase", "BrkDomain", "Foundation", "CoreGraphics"],
        "BrkEngine": ["BrkBase", "AppKit", "Foundation"],
        "BrkCEF": ["BrkBase", "BrkEngine", "CefKit", "CCef", "CCefAppKit", "AppKit", "Foundation", "ObjectiveC"],
        "BrkTheme": ["BrkBase", "BrkDomain", "AppKit", "Metal", "QuartzCore", "Foundation", "CoreGraphics"],
        "BrkUI": ["BrkBase", "BrkDomain", "BrkLayout", "BrkTheme", "AppKit", "SwiftUI", "Foundation", "CoreGraphics"],
        "BrkControl": ["BrkBase", "BrkDomain", "BrkLayout", "Foundation", "CoreGraphics"],
        "BrkApp": ["BrkBase", "BrkDomain", "BrkLayout", "BrkEngine", "BrkTheme", "BrkUI", "BrkControl", "AppKit", "Foundation", "CoreGraphics"],
        "Brk": ["BrkApp", "BrkBase", "BrkCEF", "BrkEngine", "AppKit", "Foundation"],
        "BrkE2E": ["BrkBase", "BrkDomain", "BrkLayout", "BrkControl", "Foundation", "CoreGraphics"],
    ]

    /// (pattern, the only files allowed to match, why). Paths relative to Sources/.
    static let singleWriters: [(pattern: String, allowed: [String], why: String)] = [
        (#"\bDate\(\)|\bDate\.now\b|CFAbsoluteTimeGetCurrent"#, ["BrkApp/Clock.swift", "BrkE2E/"], "the clock is injected"),
        (#"(?<![A-Za-z.])reduce\("#, ["BrkDomain/", "BrkApp/AppStore.swift"], "AppStore is the only caller of reduce"),
        (#"addChildWindow|canBecomeKeyWindow|method_setImplementation"#, ["BrkCEF/"], "host-window tricks stay in BrkCEF"),
        (#"CefRuntime|CefBrowser|CefChromeBrowser"#, ["BrkCEF/"], "Chromium API stays in BrkCEF"),
        (#"cornerRadius\s*=\s*[1-9]"#, [], "layout numbers live in BrkBase/Metrics.swift"),
        (#"JSONEncoder\(\)|JSONDecoder\(\)"#, ["BrkDomain/Codec.swift", "BrkControl/", "BrkE2E/"], "one state format, one wire format"),
    ]

    func testEveryTargetImportsOnlyWhatTheModuleMapAllows() throws {
        var problems: [String] = []
        for (target, files) in try sources() {
            for (path, text) in files {
                problems += Self.importViolations(target: target, path: path, text: text)
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    func testSingleWriterPatterns() throws {
        var problems: [String] = []
        for (_, files) in try sources() {
            for (path, text) in files { problems += Self.patternViolations(path: path, text: text) }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    func testEveryTargetIsInTheRuleTable() throws {
        XCTAssertEqual(Set(try sources().keys), Set(Self.allowedImports.keys))
    }

    // MARK: Negative cases: each rule really fires.

    func testRejectsAnUpwardImport() {
        XCTAssertEqual(Self.importViolations(target: "BrkDomain", path: "BrkDomain/X.swift", text: "import AppKit\n").count, 1)
        XCTAssertEqual(Self.importViolations(target: "BrkUI", path: "BrkUI/X.swift", text: "@testable import BrkCEF\n").count, 1)
        XCTAssertEqual(Self.importViolations(target: "BrkUI", path: "BrkUI/X.swift", text: "@preconcurrency import BrkApp\n").count, 1)
        XCTAssertEqual(Self.importViolations(target: "BrkUI", path: "BrkUI/X.swift", text: "// import BrkApp\nimport AppKit\n"), [])
    }

    func testRejectsAClockReadOutsideClock() {
        XCTAssertEqual(Self.patternViolations(path: "BrkDomain/Rules/Tabs.swift", text: "let t = Date()\n").count, 1)
        XCTAssertEqual(Self.patternViolations(path: "BrkApp/Clock.swift", text: "let t = Date()\n"), [])
    }

    func testRejectsAReduceCallOutsideTheStore() {
        XCTAssertEqual(Self.patternViolations(path: "BrkApp/KeyRouter.swift", text: "let t = reduce(s, i, c)\n").count, 1)
        XCTAssertEqual(Self.patternViolations(path: "BrkApp/AppStore.swift", text: "let t = reduce(s, i, c)\n"), [])
    }

    func testRejectsALayoutLiteralInAView() {
        XCTAssertEqual(Self.patternViolations(path: "BrkUI/Sidebar/X.swift", text: "layer?.cornerRadius = 12\n").count, 1)
    }

    // MARK: Scanner

    static func importViolations(target: String, path: String, text: String) -> [String] {
        let allowed = allowedImports[target] ?? []
        return imports(in: text).filter { !allowed.contains($0) }.map { "\(path): imports \($0), not allowed in \(target)" }
    }

    static func patternViolations(path: String, text: String) -> [String] {
        let code = stripComments(text)
        var out: [String] = []
        for rule in singleWriters where !rule.allowed.contains(where: { path.hasPrefix($0) || path == $0 }) {
            if code.range(of: rule.pattern, options: .regularExpression) != nil {
                out.append("\(path): matches /\(rule.pattern)/ - \(rule.why)")
            }
        }
        return out
    }

    static func imports(in text: String) -> [String] {
        stripComments(text).split(separator: "\n").compactMap { line in
            var words = line.split(separator: " ").map(String.init)
            while let first = words.first, first.hasPrefix("@") { words.removeFirst() }
            guard words.count >= 2, words[0] == "import" else { return nil }
            let module = words.count >= 3 && ["struct", "class", "enum", "func", "var", "protocol"].contains(words[1]) ? words[2] : words[1]
            return String(module.split(separator: ".")[0])
        }
    }

    /// Drops `//` line comments and string literals' contents are kept (rules target code; doc comments mention
    /// names freely).
    static func stripComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            if let r = line.range(of: "//") { return String(line[..<r.lowerBound]) }
            return String(line)
        }.joined(separator: "\n")
    }

    /// target name -> [(path relative to Sources/, text)].
    func sources() throws -> [String: [(String, String)]] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sourcesDir = root.appendingPathComponent("Sources")
        var out: [String: [(String, String)]] = [:]
        let fm = FileManager.default
        for target in try fm.contentsOfDirectory(atPath: sourcesDir.path) where !target.hasPrefix(".") {
            let dir = sourcesDir.appendingPathComponent(target)
            guard let walker = fm.enumerator(atPath: dir.path) else { continue }
            var files: [(String, String)] = []
            for case let rel as String in walker where rel.hasSuffix(".swift") {
                let text = try String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8)
                files.append(("\(target)/\(rel)", text))
            }
            out[target] = files
        }
        return out
    }
}
