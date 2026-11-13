import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation

extension CoreScenarios {
    private static func ready(_ app: AppUnderTest) throws -> (PageID, Int32) {
        let url = app.site.url("page2.html")
        let item = try app.load(url)
        let page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: url)
        guard let pid = app.hello?.pid else { throw Check(description: "missing app process") }
        try WindowServerKeys.ensureFrontmost(app, page.window)
        return (page, pid)
    }

    private static func menu(_ pid: Int32, _ top: String, _ item: String) throws {
        try NativeSystemInput.chooseMainMenu(pid: pid, menu: top, item: item)
    }

    private static func action(_ app: AppUnderTest, _ pid: Int32, _ name: String) throws {
        PhysicalKeys.press(KeyChord([.command], .t), pid: pid)
        try app.waitUntil("command bar input") { try app.native().firstResponder.hasSuffix(":" + ViewID.commandBarInput.identifier) }
        PhysicalKeys.type(name, pid: pid)
        var row: Int?
        try app.waitUntil("command \(name)") { row = try CommandBarEvidenceScenarios.rowTexts(app).firstIndex { $0.contains(name) }; return row != nil }
        for _ in 0..<row! { PhysicalKeys.press(KeyChord([], .downArrow), pid: pid) }
        PhysicalKeys.press(KeyChord([], .returnKey), pid: pid)
    }

    @Sendable static func tools(_ app: AppUnderTest) throws {
        let (page, pid) = try ready(app)
        let initial = Set(try app.native().appWindows.map(\.number))
        PhysicalKeys.press(KeyChord([.option, .command], .j), pid: pid)
        try app.waitUntil("the developer console window", timeout: 15) {
            try app.native().pages[page]?.hasDevTools == true && app.native().appWindows.contains { $0.isVisible && $0.isKey && !initial.contains($0.number) }
        }
        app.sleep(1)
        PhysicalKeys.type("document.title='console-receipt'", pid: pid)
        PhysicalKeys.press(KeyChord([], .returnKey), pid: pid)
        try app.waitUntil("the console evaluated code against its page") { try tab(page.item, in: app.view())?.title == "console-receipt" }
        try WindowServerKeys.ensureFrontmost(app, page.window)
        PhysicalKeys.press(KeyChord([.option, .command], .i), pid: pid)
        try app.waitUntil("toggle closes developer tools") { try app.native().pages[page]?.hasDevTools == false }

        let beforeSource = Set(try app.native().appWindows.map(\.number))
        PhysicalKeys.press(KeyChord([.option, .command], .u), pid: pid)
        var source: AppWindowFact?
        try app.waitUntil("the source window") {
            source = try app.native().appWindows.first { $0.isVisible && $0.isKey && !beforeSource.contains($0.number) }
            return source != nil
        }
        guard case .menuItems(let text) = try app.send(.appWindowTexts(number: source!.number)) else { throw Check(description: "missing source text") }
        try expect(text.contains { $0.contains("<!DOCTYPE html>") || $0.contains("<html") }, "source window contains no HTML")
        try NativeSystemInput.closeFocusedWindow(pid: pid)
        try WindowServerKeys.ensureFrontmost(app, page.window)
        let beforeManager = Set(try app.native().appWindows.map(\.number))
        try menu(pid, "Help", "Troubleshooting › Open Task Manager")
        var manager: AppWindowFact?
        try app.waitUntil("task manager with measured memory", timeout: 10) {
            manager = try app.native().appWindows.first { $0.isVisible && $0.isKey && !beforeManager.contains($0.number) }
            guard let manager, case .menuItems(let text) = try app.send(.appWindowTexts(number: manager.number)) else { return false }
            return text.contains { $0.contains("MB") }
        }
        try NativeSystemInput.closeFocusedWindow(pid: pid)
        try WindowServerKeys.ensureFrontmost(app, page.window)
        try menu(pid, "Help", "Troubleshooting › Record Trace")
        app.sleep(1)
        try menu(pid, "Help", "Troubleshooting › Stop Recording Trace")
        let traces = app.dataDirectory.appendingPathComponent("Traces")
        var saved: URL?
        try app.waitUntil("a readable Chromium trace", timeout: 15) {
            saved = try? FileManager.default.contentsOfDirectory(at: traces, includingPropertiesForKeys: nil).first { $0.pathExtension == "json" }
            guard let saved, let data = try? Data(contentsOf: saved), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return (json["traceEvents"] as? [Any])?.isEmpty == false
        }
        let beforeCast = Set(try app.native().appWindows.filter(\.isVisible).map(\.number))
        try menu(pid, "View", "Cast")
        try app.waitUntil("Chromium's casting dialog", timeout: 10) {
            try app.native().appWindows.contains { $0.isVisible && !beforeCast.contains($0.number) }
        }
        PhysicalKeys.press(KeyChord([], .escape), pid: pid)
    }

    @Sendable static func editor(_ app: AppUnderTest) throws {
        let (page, pid) = try ready(app)
        try app.evaluate(page, "document.body.innerHTML='<textarea id=editor autofocus>hello world</textarea>';document.getElementById('editor').focus()")
        app.sleep(0.2)
        PhysicalKeys.press(KeyChord([.command], .a), pid: pid)
        try menu(pid, "Edit", "Transformations › Make Upper Case")
        try app.waitUntil("uppercase in the page") { try PageBrowsingScenarios.pageText(app, page, "document.getElementById('editor').value") == "HELLO WORLD" }
        PhysicalKeys.press(KeyChord([.command], .z), pid: pid)
        try expect(try PageBrowsingScenarios.pageText(app, page, "document.getElementById('editor').value") == "hello world", "transform lost the editor's undo history")
        PhysicalKeys.press(KeyChord([.command], .a), pid: pid)
        PhysicalKeys.type("helllo", pid: pid)
        PhysicalKeys.press(KeyChord([.command], .leftArrow), pid: pid)
        try menu(pid, "Edit", "Spelling and Grammar › Check Document Now")
        try app.waitUntil("misspelled text selected") {
            try PageBrowsingScenarios.pageText(app, page, "(()=>{const e=document.getElementById('editor');return e.value.slice(e.selectionStart,e.selectionEnd)})()") == "helllo"
        }
    }

    @Sendable static func documentPiP(_ app: AppUnderTest) throws {
        let (page, pid) = try ready(app)
        let before = Set(try app.native().appWindows.filter(\.isVisible).map(\.number))
        try action(app, pid, "Page Picture in Picture")
        try app.waitUntil("document picture in picture", timeout: 10) { try tab(page.item, in: app.view())?.documentPictureInPicture == true }
        try expect(try app.native().appWindows.contains { $0.isVisible && !before.contains($0.number) }, "picture in picture has no window")
        try WindowServerKeys.ensureFrontmost(app, page.window)
        try action(app, pid, "Close Picture in Picture")
        try app.waitUntil("picture in picture closed") { try tab(page.item, in: app.view())?.documentPictureInPicture == false }
        try expect(try PageBrowsingScenarios.pageText(app, page, "document.body.innerText.includes('Page 2')") == "true", "closing picture in picture did not restore the DOM")
    }
}
