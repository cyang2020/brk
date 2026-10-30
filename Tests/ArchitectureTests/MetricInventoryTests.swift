import BrkBase
import Foundation
import XCTest

/// The constants file is checked against its grounding. Reflection walks `Metrics`: every stored property is a
/// `Metric` or a `MetricGroup`; every `.arc` source is the start of a row of docs/arc-anatomy/layout-constants.md,
/// states a confidence that row has, and has a value the row's Value cell holds (`valueProblem`; the exceptions are
/// `variants`); every `.derived` rule names rows; every `.guess` gives a reason. A bare number added to any group
/// fails `testEveryStoredPropertyIsASourcedMetric` (the judge's probe, kept below as a negative case), and so does an
/// Arc number changed away from its row (the wave 1 review's 0.08 -> 8.0 mutation, also kept below).
final class MetricInventoryTests: XCTestCase {
    struct Row { let constant: String; let value: String; let unit: String; let confidence: String }

    /// Arc metrics whose value the row does not spell out, and why. Each entry must be needed
    /// (`testEveryVariantIsNeeded`), so the list cannot outlive the reason.
    static let variants: [String: String] = [
        "Metrics.window.trafficLightHoverZone": "the row gives x -50, 140 wide and 50 tall; y 0 (the zone starts at the window top) is ours",
    ]

    func testEveryStoredPropertyIsASourcedMetric() throws {
        let rows = try Self.constantRows()
        let problems = Self.problems(in: Metrics, path: "Metrics", rows: rows)
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
        XCTAssertGreaterThan(Self.metricCount(in: Metrics), 100)
    }

    func testTheConstantsTableIsReadable() throws {
        let rows = try Self.constantRows()
        XCTAssertGreaterThan(rows.count, 70)
        XCTAssertTrue(rows.contains { $0.constant.hasPrefix("Sidebar minimum width while dragging") })
        let toggle = try XCTUnwrap(rows.first { $0.constant == "Sidebar show/hide animation duration" })
        XCTAssertEqual([toggle.value, toggle.unit, toggle.confidence], ["0.08", "s", "high"])
        XCTAssertEqual(Self.numbers(inCell: "x from -50, 140 wide, 50 tall"), [-50, 140, 50])
        XCTAssertEqual(Self.numbers(inCell: "light: white; dark: black at 35%"), [0.35])
        XCTAssertEqual(Self.numbers(inCell: "cubic-bezier(0.25, 0.46, 0.45, 0.94)"), [0.25, 0.46, 0.45, 0.94])
    }

    /// The value check reaches every Arc metric: each one, moved off its value, is rejected (so no row is matched only
    /// because it is long, and no value type slips past the comparison).
    func testEveryArcMetricMovedOffItsValueIsRejected() throws {
        let rows = try Self.constantRows()
        func moved(_ value: Any) -> Any {
            switch value {
            case let v as Bool: !v
            case let v as Double: v * 1000 + 0.123
            case let v as Int: v * 1000 + 7
            case let v as CGSize: CGSize(width: v.width * 1000 + 0.123, height: v.height)
            case let v as CGRect: CGRect(x: v.minX, y: v.minY, width: v.width * 1000 + 0.123, height: v.height)
            case let v as [Double]: [v[0] * 1000 + 0.123] + v.dropFirst()
            default: value
            }
        }
        var checked = 0
        func walk(_ group: Any, _ path: String) {
            for child in Mirror(reflecting: group).children {
                let name = "\(path).\(child.label ?? "?")"
                if let metric = child.value as? AnyMetric {
                    guard Self.variants[name] == nil, case .arc(let constant, _, _) = metric.source,
                          let row = rows.first(where: { $0.constant.hasPrefix(constant) }) else { continue }
                    checked += 1
                    XCTAssertNil(Self.valueProblem(Self.value(of: metric), at: name, row: row))
                    XCTAssertNotNil(Self.valueProblem(moved(Self.value(of: metric)), at: name, row: row), "\(name) moved off its value passes")
                } else if child.value is MetricGroup {
                    walk(child.value, name)
                }
            }
        }
        walk(Metrics, "Metrics")
        XCTAssertGreaterThan(checked, 90)
    }

    func testEveryVariantIsNeeded() throws {
        let rows = try Self.constantRows()
        var found: Set<String> = []
        func walk(_ group: Any, _ path: String) {
            for child in Mirror(reflecting: group).children {
                let name = "\(path).\(child.label ?? "?")"
                if let metric = child.value as? AnyMetric, Self.variants[name] != nil {
                    found.insert(name)
                    guard case .arc(let constant, _, _) = metric.source, let row = rows.first(where: { $0.constant.hasPrefix(constant) }) else {
                        XCTFail("\(name): a variant must have an Arc row")
                        continue
                    }
                    XCTAssertNotNil(Self.valueProblem(Self.value(of: metric), at: name, row: row), "\(name) matches its row: drop the variant")
                } else if child.value is MetricGroup {
                    walk(child.value, name)
                }
            }
        }
        walk(Metrics, "Metrics")
        XCTAssertEqual(found, Set(Self.variants.keys), "every variant names a metric")
    }

    /// Reflection cannot see a free global, so the file itself is also read: every `let`/`var` in Metrics.swift
    /// is a `Metric(...)` or a group instance. This is the judge's probe (`public let judgeUnsourcedLayoutNumber =
    /// 123.0` at file scope).
    func testTheConstantsFileDeclaresOnlyMetricsAndGroups() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/BrkBase/Metrics.swift"), encoding: .utf8)
        let problems = Self.declarationProblems(in: text)
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    func testRejectsAFreeNumberInTheConstantsFile() {
        XCTAssertEqual(Self.declarationProblems(in: "public let judgeUnsourcedLayoutNumber = 123.0\n").count, 1)
        XCTAssertEqual(Self.declarationProblems(in: "    public static let x = 12.0\n").count, 1)
        XCTAssertEqual(Self.declarationProblems(in: "    public let x = Metric(12.0, .guess(\"why\"))\n"), [])
        XCTAssertEqual(Self.declarationProblems(in: "    public let dock = DockMetrics()\npublic let Metrics = MetricsTable()\n"), [])
    }

    static func declarationProblems(in text: String) -> [String] {
        text.split(separator: "\n").enumerated().compactMap { index, line in
            let code = line.split(separator: "//", maxSplits: 1).first.map(String.init) ?? ""
            guard let range = code.range(of: #"^\s*(public\s+)?(static\s+)?(let|var)\s+\w+\s*=\s*"#, options: .regularExpression) else { return nil }
            let rhs = code[range.upperBound...]
            if rhs.hasPrefix("Metric(") || rhs.hasPrefix("MetricsTable()") || rhs.range(of: #"^\w+Metrics\(\)"#, options: .regularExpression) != nil {
                return nil
            }
            return "Metrics.swift:\(index + 1): \(code.trimmingCharacters(in: .whitespaces)) is not a Metric or a group"
        }
    }

    // MARK: Negative cases: the gate really fires.

    struct BareNumber: MetricGroup { let judgeUnsourcedLayoutNumber = 123.0 }
    struct WrongRow: MetricGroup { let x = Metric(1.0, .arc("No such row in the table")) }
    struct WrongConfidence: MetricGroup { let x = Metric(164.0, .arc("Sidebar minimum width while dragging", .low)) }
    struct EmptyGuess: MetricGroup { let x = Metric(1.0, .guess("")) }
    struct NestedBare: MetricGroup { let inner = BareNumber() }
    /// The review's mutation: Arc's 0.08 s sidebar animation written as 8.0 under the same row.
    struct WrongValue: MetricGroup { let sidebarToggle = Metric(8.0, .arc("Sidebar show/hide animation duration")) }
    struct WrongSize: MetricGroup { let x = Metric(CGSize(width: 1280, height: 777), .arc("Main window default size")) }
    struct WrongCurve: MetricGroup { let x = Metric([0.25, 0.46, 0.45, 0.95], .arc("Sidebar show/hide timing curve")) }
    struct OneOfSeveral: MetricGroup { let x = Metric(11.0, .arc("Resize hit area", .medium, note: "starts 11 below the top")) }

    func testRejectsABareNumber() throws {
        let rows = try Self.constantRows()
        XCTAssertEqual(Self.problems(in: BareNumber(), path: "T", rows: rows).count, 1)
        XCTAssertEqual(Self.problems(in: NestedBare(), path: "T", rows: rows).count, 1)
    }

    func testRejectsAValueTheRowDoesNotHave() throws {
        let rows = try Self.constantRows()
        XCTAssertEqual(Self.problems(in: WrongValue(), path: "T", rows: rows).count, 1)
        XCTAssertEqual(Self.problems(in: WrongSize(), path: "T", rows: rows).count, 1)
        XCTAssertEqual(Self.problems(in: WrongCurve(), path: "T", rows: rows).count, 1)
        XCTAssertEqual(Self.problems(in: OneOfSeveral(), path: "T", rows: rows), [], "a row with several values: the metric takes one")
    }

    func testRejectsASourceTheGroundingDoesNotHave() throws {
        let rows = try Self.constantRows()
        XCTAssertEqual(Self.problems(in: WrongRow(), path: "T", rows: rows).count, 1)
        XCTAssertEqual(Self.problems(in: WrongConfidence(), path: "T", rows: rows).count, 1)
        XCTAssertEqual(Self.problems(in: EmptyGuess(), path: "T", rows: rows).count, 1)
    }

    // MARK: Checker

    static func problems(in group: Any, path: String, rows: [Row]) -> [String] {
        var out: [String] = []
        for child in Mirror(reflecting: group).children {
            let name = "\(path).\(child.label ?? "?")"
            if let metric = child.value as? AnyMetric {
                out += problems(with: metric, at: name, rows: rows)
            } else if child.value is MetricGroup {
                out += problems(in: child.value, path: name, rows: rows)
            } else {
                out.append("\(name) is not a Metric (\(type(of: child.value)))")
            }
        }
        return out
    }

    static func problems(with metric: AnyMetric, at name: String, rows: [Row]) -> [String] {
        switch metric.source {
        case .arc(let constant, let confidence, _):
            guard let row = rows.first(where: { $0.constant.hasPrefix(constant) }) else {
                return ["\(name): no row of layout-constants.md starts with \"\(constant)\""]
            }
            guard row.confidence.contains(confidence.rawValue) else {
                return ["\(name): states \(confidence.rawValue) but the row says \"\(row.confidence)\""]
            }
            if variants[name] != nil { return [] }
            return valueProblem(value(of: metric), at: name, row: row).map { [$0] } ?? []
        case .derived(let rule, let from):
            var out: [String] = []
            if rule.isEmpty { out.append("\(name): derived without a rule") }
            if from.isEmpty { out.append("\(name): derived from no rows") }
            for constant in from where !rows.contains(where: { $0.constant.hasPrefix(constant) }) {
                out.append("\(name): derived from \"\(constant)\", which is not a row")
            }
            return out
        case .anatomy(let section):
            return section.contains(".md") ? [] : ["\(name): anatomy source \"\(section)\" names no file"]
        case .guess(let why):
            return why.count >= 12 ? [] : ["\(name): a guess needs a reason"]
        }
    }

    static func value(of metric: AnyMetric) -> Any {
        Mirror(reflecting: metric).descendant("value") ?? ()
    }

    /// The row's Value cell holds the metric's value when the metric's numbers appear in the cell consecutively and in
    /// order: "0.08" holds 0.08; "1280 × 776" holds a 1280 x 776 size; a row with several values ("8 wide, ...,
    /// starts 11 below the top") holds each metric that takes one of them (its note says which). A Bool must appear as
    /// a word.
    static func valueProblem(_ value: Any, at name: String, row: Row) -> String? {
        let wanted: [Double]
        switch value {
        case let v as Bool: return row.value.contains("\(v)") ? nil : "\(name): \(v) is not in the row's value \"\(row.value)\""
        case let v as Double: wanted = [v]
        case let v as Int: wanted = [Double(v)]
        case let v as CGFloat: wanted = [Double(v)]
        case let v as CGSize: wanted = [v.width, v.height].map(Double.init)
        case let v as CGRect: wanted = [v.minX, v.minY, v.width, v.height].map(Double.init)
        case let v as [Double]: wanted = v
        default: return "\(name): a \(type(of: value)) cannot be compared with the row's value"
        }
        let have = numbers(inCell: row.value)
        let found = have.count >= wanted.count && (0...(have.count - wanted.count)).contains { start in
            zip(have[start...], wanted).allSatisfy { abs($0 - $1) <= 1e-9 * max(1, abs($1)) }
        }
        return found ? nil : "\(name): \(wanted) is not in the row's value \"\(row.value)\" (\(row.unit))"
    }

    /// Every number in a Value cell, in order; a percentage as a fraction.
    static func numbers(inCell cell: String) -> [Double] {
        let pattern = try! NSRegularExpression(pattern: #"-?\d+(?:\.\d+)?%?"#)
        return pattern.matches(in: cell, range: NSRange(cell.startIndex..., in: cell)).compactMap { match in
            let token = String(cell[Range(match.range, in: cell)!])
            return token.hasSuffix("%") ? Double(token.dropLast()).map { $0 / 100 } : Double(token)
        }
    }

    static func metricCount(in group: Any) -> Int {
        Mirror(reflecting: group).children.reduce(0) { n, child in
            if child.value is AnyMetric { return n + 1 }
            if child.value is MetricGroup { return n + metricCount(in: child.value) }
            return n
        }
    }

    /// The "Constant", "Value", "Unit" and "Confidence" cells of every row of the constants table.
    static func constantRows() throws -> [Row] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("docs/arc-anatomy/layout-constants.md"), encoding: .utf8)
        return text.split(separator: "\n").compactMap { line -> Row? in
            guard line.hasPrefix("| "), !line.hasPrefix("| Constant"), !line.hasPrefix("|---") else { return nil }
            let cells = line.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 6 else { return nil }
            return Row(constant: cells[0], value: cells[1], unit: cells[2], confidence: cells[cells.count - 1])
        }
    }
}
