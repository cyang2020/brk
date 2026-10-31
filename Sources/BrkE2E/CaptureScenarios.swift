import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum CaptureScenarios {
    static let all = [Scenario("CaptureProbe", "embedded Chrome capture and separate video/document PiP probes", cefOnly: "embedded DevTools", probe)]
    @Sendable static func probe(_ app: AppUnderTest) throws {
        let url = app.site.url("capture-media.html")
        let item = try app.load(url)
        let page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: url)
        let directory = app.dataDirectory.appendingPathComponent("capture-probe")
        guard case .text(let report) = try app.send(.captureProbe(page: page, directory: directory), timeout: 30) else { throw Check(description: "no probe response") }
        app.note(report)
        for name in ["area", "full", "portrait"] {
            let data = try Data(contentsOf: directory.appendingPathComponent(name + ".png"))
            try expect(data.count > 24 && Array(data.prefix(8)) == [137,80,78,71,13,10,26,10], "invalid probe PNG")
            func dimension(_ offset: Int) -> Int { data[offset..<(offset + 4)].reduce(0) { $0 * 256 + Int($1) } }
            try expect(dimension(16) > 100 && dimension(20) > 100, "empty capture")
            try data.write(to: app.shotsDirectory.appendingPathComponent("probe-" + name + ".png"))
        }
        try FileManager.default.copyItem(at: directory.appendingPathComponent("probe.json"), to: app.shotsDirectory.appendingPathComponent("probe.json"))
        try FileManager.default.copyItem(at: directory.appendingPathComponent("metrics.json"), to: app.shotsDirectory.appendingPathComponent("metrics.json"))
        _ = try app.screenshot("probe-embedded-page")
    }
}
