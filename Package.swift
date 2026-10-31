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
            exclude: ["AudibilityExtension"],
            swiftSettings: strict
        ),
        // Themed window background: Metal gradient, procedural textures, crossfade.
        .target(name: "BrkTheme", dependencies: ["BrkBase", "BrkDomain"], swiftSettings: strict),
        // The view contract shared by every UI target: Dispatch, identify(_:), Palette, Copy. No views of its own.
        .target(name: "BrkUIKit", dependencies: ["BrkBase", "BrkDomain", "BrkLayout"], swiftSettings: strict),
        // W3: the sidebar column (title row, URL pill, favorites, tab list, dock, resize handle).
        .target(name: "BrkSidebar", dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkUIKit"], swiftSettings: strict),
        // W4 / F4: the command bar and its ranking, the archive page (moving to BrkLibrary in F5), the space dialog.
        .target(name: "BrkOverlays", dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkUIKit"], swiftSettings: strict),
        // F5: the Library host inside the content card (downloads, history, archive, media, easels and notes, boosts, spaces).
        .target(name: "BrkLibrary", dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkUIKit"], swiftSettings: strict),
        // F1: the settings window's panes (SwiftUI in an NSHostingView), hosted by BrkApp in its own window.
        .target(name: "BrkSettings", dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkUIKit"], swiftSettings: strict),
        // W2: the window root that composes background, sidebar, cards and overlays; the content cards.
        .target(
            name: "BrkContent",
            dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkTheme", "BrkUIKit", "BrkSidebar", "BrkOverlays", "BrkLibrary"],
            swiftSettings: strict
        ),
        // The control-socket protocol, shared by the app's server and the e2e runner.
        .target(name: "BrkControl", dependencies: ["BrkBase", "BrkDomain", "BrkLayout"], swiftSettings: strict),
        // The running app: the state owner, windows, key routing, menu, persistence, clock, control server.
        .target(
            name: "BrkApp",
            dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkEngine", "BrkTheme", "BrkUIKit", "BrkContent", "BrkControl", "BrkSettings"],
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
        .testTarget(name: "BrkOverlaysTests", dependencies: ["BrkBase", "BrkDomain", "BrkOverlays"], swiftSettings: strict),
        .testTarget(name: "BrkLibraryTests", dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkUIKit", "BrkLibrary"], swiftSettings: strict),
        .testTarget(name: "BrkSettingsTests", dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkUIKit", "BrkSettings"], swiftSettings: strict),
        .testTarget(name: "BrkContentTests", dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkUIKit", "BrkContent"], swiftSettings: strict),
        .testTarget(name: "BrkControlTests", dependencies: ["BrkBase", "BrkDomain", "BrkLayout", "BrkControl"], swiftSettings: strict),
        .testTarget(name: "BrkThemeTests", dependencies: ["BrkDomain", "BrkTheme"], swiftSettings: strict),
        .testTarget(name: "BrkEngineTests", dependencies: ["BrkBase", "BrkEngine"], swiftSettings: strict),
        .testTarget(name: "BrkCEFTests", dependencies: ["BrkBase", "BrkDomain", "BrkCEF", .product(name: "CefKit", package: "CefSwift")], swiftSettings: strict),
        .testTarget(name: "BrkAppTests", dependencies: ["BrkBase", "BrkDomain", "BrkApp"], swiftSettings: strict),
        // Scans every `import` under Sources/ against the dependency rules in module-map.md.
        .testTarget(name: "ArchitectureTests", dependencies: ["BrkBase"], swiftSettings: strict),
    ]
)
