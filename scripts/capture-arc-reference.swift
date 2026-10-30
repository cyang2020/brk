import AppKit
import CryptoKit
import Darwin
import Foundation
import ImageIO
import ScreenCaptureKit
import Security
import UniformTypeIdentifiers

private let arcID = "company.thebrowser.Browser"
private let arcRequirement = "anchor apple generic and identifier \"company.thebrowser.Browser\" and certificate leaf[subject.OU] = \"S6N382Y83G\""

private struct CaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CaptureError(message: message) }
}

private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func fileDigest(_ url: URL) throws -> String {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var hash = SHA256()
    while let bytes = try file.read(upToCount: 1_048_576), !bytes.isEmpty { hash.update(data: bytes) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

private func rectangle(_ rect: CGRect) -> [String: Double] {
    ["x": rect.origin.x, "y": rect.origin.y, "width": rect.width, "height": rect.height]
}

private func json(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}

private struct ArcIdentity: Equatable {
    let pid: pid_t
    let bundle: URL
    let executable: URL
    let launchDate: Date
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    let version: String
    let build: String
    let sha256: String

    var metadata: [String: Any] {
        ["pid": pid, "bundlePath": bundle.path, "executablePath": executable.path,
         "bundleIdentifier": arcID, "processLaunchTime": ISO8601DateFormatter().string(from: launchDate),
         "processStartUnixSeconds": startSeconds, "processStartMicroseconds": startMicroseconds,
         "version": version, "build": build, "executableSHA256": sha256,
         "verifiedCodeRequirement": arcRequirement]
    }
}

@MainActor private func identifyArc(_ pid: pid_t) throws -> ArcIdentity {
    var process = proc_bsdinfo()
    try require(proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &process, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
                "Cannot read the process start time for PID \(pid).")
    var requirement: SecRequirement?
    try require(SecRequirementCreateWithString(arcRequirement as CFString, [], &requirement) == errSecSuccess,
                "Cannot construct Arc code requirement.")
    guard let requirement else { throw CaptureError(message: "Missing code requirement.") }
    var runningCode: SecCode?
    let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
    try require(SecCodeCopyGuestWithAttributes(nil, attributes, [], &runningCode) == errSecSuccess,
                "Cannot resolve running code for PID \(pid).")
    guard let runningCode else { throw CaptureError(message: "Missing running code identity.") }
    try require(SecCodeCheckValidity(runningCode, [], requirement) == errSecSuccess,
                "Running process does not satisfy the original Arc signature requirement.")
    var diskCode: SecStaticCode?
    try require(SecCodeCopyStaticCode(runningCode, [], &diskCode) == errSecSuccess,
                "Cannot resolve the bundle of the signed running process.")
    guard let diskCode else { throw CaptureError(message: "Missing bundle code identity.") }
    try require(SecStaticCodeCheckValidity(diskCode, [], requirement) == errSecSuccess,
                "Arc bundle signature is invalid or has changed.")
    var bundlePath: CFURL?
    var signingInfo: CFDictionary?
    try require(SecCodeCopyPath(diskCode, [], &bundlePath) == errSecSuccess &&
                SecCodeCopySigningInformation(diskCode, [], &signingInfo) == errSecSuccess,
                "Cannot read the signed executable path.")
    guard let bundlePath, let signing = signingInfo as? [String: Any],
          let executable = signing[kSecCodeInfoMainExecutable as String] as? URL else {
        throw CaptureError(message: "Signed Arc path metadata is unavailable.")
    }
    let bundle = bundlePath as URL
    var processPath = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    try require(proc_pidpath(pid, &processPath, UInt32(processPath.count)) > 0,
                "Cannot read the running executable path.")
    try require(URL(fileURLWithPath: String(cString: processPath)).resolvingSymlinksInPath() == executable.resolvingSymlinksInPath(),
                "Kernel process path does not match the signed executable.")
    let data = try Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
    guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          info["CFBundleIdentifier"] as? String == arcID,
          let version = info["CFBundleShortVersionString"] as? String,
          let build = info["CFBundleVersion"] as? String,
          let name = info["CFBundleExecutable"] as? String else {
        throw CaptureError(message: "Arc version or executable metadata is missing.")
    }
    try require(executable.resolvingSymlinksInPath() == bundle.appendingPathComponent("Contents/MacOS/\(name)").resolvingSymlinksInPath(),
                "Running executable does not match the Arc bundle.")
    var after = proc_bsdinfo()
    try require(proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &after, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size &&
                process.pbi_start_tvsec == after.pbi_start_tvsec && process.pbi_start_tvusec == after.pbi_start_tvusec,
                "Process exited or restarted during identity verification.")
    let launch = Date(timeIntervalSince1970: Double(process.pbi_start_tvsec) + Double(process.pbi_start_tvusec) / 1_000_000)
    return ArcIdentity(pid: pid, bundle: bundle, executable: executable, launchDate: launch,
                       startSeconds: process.pbi_start_tvsec, startMicroseconds: process.pbi_start_tvusec,
                       version: version, build: build, sha256: try fileDigest(executable))
}

private struct Window {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect
    let layer: Int
    let ownerName: String
    var metadata: [String: Any] {
        ["windowID": id, "ownerPID": pid, "boundsPoints": rectangle(frame), "layer": layer]
    }
}

private func visibleWindows() throws -> [Window] {
    guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        throw CaptureError(message: "Window metadata is unavailable.")
    }
    return rows.compactMap { row in
        guard let id = row[kCGWindowNumber as String] as? NSNumber,
              let pid = row[kCGWindowOwnerPID as String] as? NSNumber,
              let bounds = row[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              let layer = row[kCGWindowLayer as String] as? Int,
              rect.width > 1, rect.height > 1 else { return nil }
        return Window(id: id.uint32Value, pid: pid.int32Value, frame: rect, layer: layer,
                      ownerName: row[kCGWindowOwnerName as String] as? String ?? "")
    }
}

private func selectedWindow(pid: pid_t, id: CGWindowID) throws -> Window {
    guard let window = try visibleWindows().first(where: { $0.pid == pid && $0.id == id }) else {
        throw CaptureError(message: "Window \(id) is not an on-screen window owned by Arc PID \(pid).")
    }
    return window
}

@MainActor private func displays() -> [[String: Any]] {
    NSScreen.screens.compactMap { screen in
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let displayID = id.uint32Value
        return ["displayID": displayID, "boundsPoints": rectangle(CGDisplayBounds(displayID)),
                "appKitFramePoints": rectangle(screen.frame), "backingScaleFactor": screen.backingScaleFactor,
                "pixelWidth": CGDisplayPixelsWide(displayID), "pixelHeight": CGDisplayPixelsHigh(displayID)]
    }
}

@MainActor private func listWindows() throws {
    let windows = try visibleWindows()
    let candidatePIDs = Set(windows.filter { $0.ownerName == "Arc" }.map(\.pid))
        .union(NSRunningApplication.runningApplications(withBundleIdentifier: arcID).map(\.processIdentifier))
    let identities = try candidatePIDs.sorted().map { try identifyArc($0) }
    let apps = identities.map { identity -> [String: Any] in
        var item = identity.metadata
        item["windows"] = windows.filter { $0.pid == identity.pid }.map(\.metadata)
        return item
    }
    let output = try json(["schemaVersion": 1, "screenCaptureAccess": CGPreflightScreenCaptureAccess(), "applications": apps])
    FileHandle.standardOutput.write(output + Data("\n".utf8))
}

private func validatePixels(_ image: CGImage) throws {
    try require(image.width > 1 && image.height > 1, "Capture returned empty image dimensions.")
    let rowBytes = image.width * 4
    guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
          let data = context.data else { throw CaptureError(message: "Cannot inspect captured pixels.") }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    var opaqueCount = 0
    var firstColor: UInt32?
    var varied = false
    for offset in stride(from: 0, to: rowBytes * image.height, by: 4) where bytes[offset + 3] > 0 {
        opaqueCount += 1
        let color = UInt32(bytes[offset]) << 16 | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2])
        if let firstColor { if color != firstColor { varied = true } } else { firstColor = color }
    }
    try require(opaqueCount > image.width * image.height / 20 && varied,
                "Captured pixels are transparent or uniform. No reference was saved.")
}

private final class CaptureDeadline: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let timer: DispatchSourceTimer

    init(seconds: TimeInterval = 30) {
        timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.withLock {
                guard !self.finished else { return }
                FileHandle.standardError.write(Data("capture-arc-reference: screenshot service did not finish before the deadline; no reference was saved.\n".utf8))
                _exit(124)
            }
        }
        timer.resume()
    }

    func cancel() {
        lock.withLock { finished = true }
        timer.cancel()
    }

    deinit { timer.cancel() }
}

@available(macOS 14.0, *) @MainActor
private func capture(pid: pid_t, id: CGWindowID, output: URL, label: String) async throws {
    let fm = FileManager.default
    try require(!fm.fileExists(atPath: output.path), "Output already exists. Select a new capture directory.")
    let beforeIdentity = try identifyArc(pid)
    let before = try selectedWindow(pid: pid, id: id)
    try require(CGPreflightScreenCaptureAccess(), "Screen capture access is unavailable. No permission was requested and no capture was written.")
    let started = Date()
    let deadline = CaptureDeadline()
    defer { deadline.cancel() }
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    guard let target = content.windows.first(where: {
        $0.windowID == id && $0.owningApplication?.processID == pid
    }) else { throw CaptureError(message: "Selected Arc window is unavailable to ScreenCaptureKit.") }
    let reportedID = target.owningApplication?.bundleIdentifier ?? ""
    try require(reportedID.isEmpty || reportedID == arcID, "ScreenCaptureKit reports a conflicting application identity.")
    try require(target.frame == before.frame, "Window moved before capture. Retry with a stable window.")
    let filter = SCContentFilter(desktopIndependentWindow: target)
    let scale = Double(filter.pointPixelScale)
    let width = Int((filter.contentRect.width * scale).rounded())
    let height = Int((filter.contentRect.height * scale).rounded())
    try require(scale > 0 && width > 1 && height > 1 && width <= 16384 && height <= 16384 && width * height <= 67_108_864,
                "Capture dimensions or scale are invalid or exceed the 64-megapixel limit.")
    let config = SCStreamConfiguration()
    config.width = width
    config.height = height
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    config.scalesToFit = false
    if #available(macOS 14.2, *) { config.includeChildWindows = false }
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    try require(image.width == width && image.height == height, "Returned pixel dimensions differ from the requested scale.")
    try validatePixels(image)
    let after = try selectedWindow(pid: pid, id: id)
    try require(before.frame == after.frame && before.layer == after.layer, "Window changed geometry during capture. Retry.")
    try require(beforeIdentity == identifyArc(pid), "Arc restarted or its executable changed during capture.")
    let png = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
        throw CaptureError(message: "Cannot create PNG encoder.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    try require(CGImageDestinationFinalize(destination), "PNG encoding failed.")
    let data = png as Data
    let metadata: [String: Any] = [
        "schemaVersion": 1, "label": label, "source": "actual Arc window pixels via ScreenCaptureKit",
        "captureStartedUTC": ISO8601DateFormatter().string(from: started),
        "captureCompletedUTC": ISO8601DateFormatter().string(from: Date()),
        "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
        "application": beforeIdentity.metadata, "windowBefore": before.metadata, "windowAfter": after.metadata,
        "screenCaptureKitReportedBundleIdentifier": reportedID,
        "contentRectPoints": rectangle(filter.contentRect), "pointPixelScale": scale,
        "pixelWidth": image.width, "pixelHeight": image.height, "displays": displays(),
        "cursorIncluded": false, "shadowIncluded": false, "separateChildWindowsIncluded": false,
        "pngSHA256": digest(data), "loginState": "not inspected", "testMode": "not inspected",
        "limitations": ["Human inspection is required to reject partial or privacy-placeholder pixels.",
                        "A window may change contents without changing its ID or bounds."]
    ]
    let sidecar = try json(metadata)
    deadline.cancel()
    try fm.createDirectory(at: output, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    var complete = false
    defer { if !complete { try? fm.removeItem(at: output) } }
    try data.write(to: output.appendingPathComponent("window.png"), options: .withoutOverwriting)
    try sidecar.write(to: output.appendingPathComponent("metadata.json"), options: .withoutOverwriting)
    for name in ["window.png", "metadata.json"] {
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.appendingPathComponent(name).path)
    }
    complete = true
    print(output.path)
}

@main private struct Main {
    @MainActor static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args == ["--help"] {
                print("capture-arc-reference --list\ncapture-arc-reference --pid PID --window-id ID --output NEW_DIRECTORY [--label TEXT]")
                return
            }
            if args == ["--list"] { try listWindows(); return }
            var options: [String: String] = [:]
            try require(args.count % 2 == 0, "Options need values. Use --help.")
            for index in stride(from: 0, to: args.count, by: 2) {
                let key = args[index]
                try require(["--pid", "--window-id", "--output", "--label"].contains(key) && options[key] == nil,
                            "Unknown or duplicate option: \(key)")
                options[key] = args[index + 1]
            }
            guard let rawPID = options["--pid"], let pid = Int32(rawPID), pid > 0,
                  let rawID = options["--window-id"], let id = UInt32(rawID), id > 0,
                  let path = options["--output"], !path.isEmpty else {
                throw CaptureError(message: "Specify --pid, --window-id, and --output. Use --list to find actual Arc windows.")
            }
            if #available(macOS 14.0, *) {
                try await capture(pid: pid, id: id, output: URL(fileURLWithPath: path), label: options["--label"] ?? "")
            } else { throw CaptureError(message: "Capture requires macOS 14 or later.") }
        } catch {
            FileHandle.standardError.write(Data("capture-arc-reference: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
