<img src="assets/icon.svg" width="64" height="64" alt="">

# Brk

A native macOS rebuild of the Arc browser, written in Swift 6 with AppKit on the Chromium Embedded Framework (CEF 154). It follows Arc 1.170 feature by feature and pixel by pixel; Arc's numbers are read from its binary and checked against the real Arc on the same screen. On top of that it adds AI features that run on the user's own local agents (Claude Code, Codex) and local models, without API keys.

The first version (October 2026) was an Electron app. It is kept at the git tag `electron-v1` and is no longer developed.

## Layout

- `Sources/`: the SwiftPM targets. `Brk` is the app; `BrkDomain` holds the state and its rules; `BrkSidebar`, `BrkContent`, `BrkOverlays`, `BrkLibrary` and `BrkSettings` are the UI; `BrkCEF` is the CEF engine; `BrkCoreEngine` runs Brk's own Chromium build; `BrkE2E` drives native scenarios.
- `engine/`: Brk's own Chromium build (BrkCore.framework) and its patch series. CEF stays the default engine.
- `docs/`: the design (`docs/design/`, with the AI plan in `docs/design/ai-native.md`), Arc facts read from the binary (`docs/arc-anatomy/`), the feature ledger (`docs/completion/features.json`) and the testing rules (`docs/testing-policy.md`).
- `scripts/`: the build, the native scenario runner and the station, which compares Brk's screens with Arc's on the same display.

## Build and run

Needs macOS on Apple silicon and Xcode with Swift 6. The first build downloads CEF (132 MB).

```sh
scripts/build.sh                 # release build, unit tests, CEF bundle and signature: dist/Brk.app
SKIP_TESTS=1 scripts/build.sh    # the same without the unit tests
open dist/Brk.app
```

## Test

```sh
swift test                                            # unit tests
swift build -c release --product brk-e2e
python3 scripts/run-native.py <name> --set smoke      # native scenarios with real input on a real launch
```

Which tests a change adds, and what runs before a merge, is in `docs/testing-policy.md`. Test evidence (pictures, logs, reports) stays outside the repository.
