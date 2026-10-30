// swift-tools-version: 6.0
// Brk: a native macOS Arc-style browser. AppKit shell, Chromium through CEF (Chrome runtime, embedded views).
// Module map and dependency rules: docs/design/swift/module-map.md. Rationale: docs/design/swift/rationale.md.
import PackageDescription

/// The product name lives here and nowhere else. The executable, the .app bundle and its five helpers
/// ("Brk Helper (GPU).app", named by the CEF plugin from the executable), the bundle identifier
/// (scripts/build.sh reads it from `swift package dump-package`), the Application Support folder and the
/// menu titles (BrkBase/Product.swift reads the running bundle or process name) all derive from it.
let productName = "Brk"

/// Swift 6 language mode: complete strict concurrency checking in every first-party target.
let strict: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: productName,
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: productName, targets: [productName]),
        .executable(name: "brk-e2e", targets: ["BrkE2E"]),
    ],
    dependencies: [
        // Vendored CefSwift at ba6ebff (CEF 154.0.34, C API 14800). Its CefKit is the only Chromium API we
        // call, and only from BrkCEF. Its `cef` command plugin downloads the SHA-1-pinned CEF and assembles
        // the .app with helpers (scripts/build.sh). Vendored because upstream has had no human commit since June
        // and we must own CEF bumps; its dlopen loader means `swift build`/`swift test` need no CEF download.
        .package(path: "Vendor/CefSwift"),
    ],
    targets: [
        // Vocabulary shared by every layer: ids, time, keys, the page vocabulary, the constants file.
        .target(name: "BrkBase", swiftSettings: strict),
        // The one state owner's logic: model, commands, pure reducer, projection, codec, shortcut table.
        .target(name: "BrkDomain", dependencies: ["BrkBase"], swiftSettings: strict),
        // Pure geometry: every frame in a window, computed from a snapshot and the constants.
        .target(name: "BrkLayout", dependencies: ["BrkBase", "BrkDomain"], swiftSettings: strict),
        // The hosting interface for web pages, plus a stub engine that needs no Chromium.
        .target(name: "BrkEngine", dependencies: ["BrkBase"], swiftSettings: strict),
        // The Chrome-runtime embed engine. The only target that imports CefKit.
        .target(
            name: "BrkCEF",
            dependencies: ["BrkBase", "BrkEngine", .product(name: "CefKit", package: "CefSwift")],
            swiftSettings: strict
        ),
        // Themed window background: Metal gradient, procedural textures, crossfade.
        .target(name: "BrkTheme", dependencies: ["BrkBase", "BrkDomain"], swiftSettings: strict),
        // AppKit views. They render snapshots at computed frames and send commands; they hold no app state.
        .target(name: "BrkUI", dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkTheme"], swiftSettings: strict),
        // The control-socket protocol, shared by the app's server and the e2e runner.
        .target(name: "BrkControl", dependencies: ["BrkBase", "BrkDomain", "BrkLayout"], swiftSettings: strict),
        // The running app: the state owner, windows, key routing, menu, persistence, clock, control server.
        .target(
            name: "BrkApp",
            dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkEngine", "BrkTheme", "BrkUI", "BrkControl"],
            swiftSettings: strict
        ),
        // Composition root: picks the engine, starts CEF before NSApp exists, runs the app.
        .executableTarget(
            name: productName,
            dependencies: ["BrkBase", "BrkApp", "BrkEngine", "BrkCEF"],
            path: "Sources/Brk",
            swiftSettings: strict
        ),
        // E2E scenario runner: launches the built .app, drives it over the control socket, writes the report.
        .executableTarget(
            name: "BrkE2E",
            dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkControl"],
            swiftSettings: strict
        ),

        .testTarget(name: "BrkDomainTests", dependencies: ["BrkBase", "BrkDomain"], swiftSettings: strict),
        .testTarget(name: "BrkLayoutTests", dependencies: ["BrkBase", "BrkDomain", "BrkLayout"], swiftSettings: strict),
        .testTarget(name: "BrkUITests", dependencies: ["BrkBase", "BrkDomain", "BrkUI"], swiftSettings: strict),
        .testTarget(name: "BrkControlTests", dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkControl"], swiftSettings: strict),
        .testTarget(name: "BrkThemeTests", dependencies: ["BrkDomain", "BrkTheme"], swiftSettings: strict),
        .testTarget(name: "BrkEngineTests", dependencies: ["BrkBase", "BrkEngine"], swiftSettings: strict),
        .testTarget(name: "BrkAppTests", dependencies: ["BrkBase", "BrkDomain", "BrkApp"], swiftSettings: strict),
        // Scans every `import` under Sources/ against the dependency rules in module-map.md.
        .testTarget(name: "ArchitectureTests", dependencies: ["BrkBase"], swiftSettings: strict),
    ]
)
