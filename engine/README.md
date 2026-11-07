# Brk's own Chromium build

Brk's second engine: Chromium's `chrome/` layer in one framework, `BrkCore.framework`, the way Arc ships `ArcCore.framework`. The reasoning and the
evidence from Arc's binary are in `docs/chromium/ARC-ENGINE.md`. CEF stays the default; `BRK_ENGINE=core` picks this one. Nothing in this folder runs
in `scripts/build.sh` or `swift test`, so `main` builds and passes with no Chromium tree present.

## Layout

| Where | What |
| --- | --- |
| `~/brk-chromium/` (not in the repo) | `depot_tools`, `chromium/src` at tag 154.0.8037.98, `logs/`, `STATE.md` |
| `engine/config.sh` | the pinned tag and commit, the paths |
| `engine/fetch.sh` | depot_tools and the source. 18 minutes, 30 GB on this machine and connection. Safe to rerun |
| `engine/args/brk.gn` | pinned build arguments |
| `engine/configure.sh` | writes `out/Brk/args.gn`, runs `gn gen` |
| `engine/build.sh <target>` | compiles at low priority, pausing itself (below). `chrome` builds everything |
| `engine/patches/` | the patch series: Brk's commits over the tag, numbered |
| `engine/apply-patches.sh` | makes branch `brk/154.0.8037.98` in the tree from the tag and the series |
| `engine/export-patches.sh` | writes the branch back to `engine/patches/` |
| `engine/sync-header.sh` | copies the one interface header `Sources/CBrkCore/include/BrkCore.h` into the tree |
| `engine/build-demo.sh` | the smallest program on the framework, `engine/demo/main.swift` |
| `engine/assemble-app.sh` | `dist-core/Brk.app`: `dist/Brk.app` plus the framework |
| `engine/run-native-core.py` | e2e scenarios on it, under the native lock, evidence in `verify/chromium/` |
| `engine/tools/check-brk.sh` | syntax-only compile of `brk/` files with a neighbouring file's flags |
| `engine/tools/arc-inspect.sh` | the static inspection of Arc that the notes cite |

## From nothing

    engine/fetch.sh
    engine/apply-patches.sh
    engine/configure.sh
    nohup engine/build.sh chrome >/dev/null 2>&1 &   # many hours; rerunning continues
    engine/build-demo.sh                             # then run the demo
    scripts/build.sh && engine/assemble-app.sh       # then BRK_ENGINE=core dist-core/Brk.app/Contents/MacOS/Brk

## Build arguments

- **Static, not component.** One framework file, the shape Arc ships and the shape the app will load. A component build relinks faster but loads
  hundreds of dylibs and is a different thing to test. A relink of the static framework takes minutes, which is acceptable.
- **Symbols.** `symbol_level = 0` for Chromium's own code: much less disk and link memory. `brk/` gets `minimal_symbols` for backtraces. Function
  names stay in the symbol table of a non-official build.
- **Not official.** No thin LTO and no PGO: both need far more memory and hours than this machine has beside other work. The binary is larger and slower
  than a release build would be. Measure before judging speed from this build.
- **`concurrent_links = 1`.** A framework link takes several GB.
- **`use_siso = false`.** Plain ninja, so the build tool can be paused alone.
- **Codecs: the CEF binary's set.** `proprietary_codecs = false`, `ffmpeg_branding = "Chromium"`. `engine/tools/codec-probe.py` asked the CEF 154.0.34 binary at
  run time: VP8, VP9, AV1, MP3, Opus and FLAC decode; H.264, HEVC, AAC and AC-3 do not. Turning them on is a decision about licensing: the user's.
- **Widevine off**, as it is unavailable in the CEF binary too. The user's decision.
- **No Google API keys.** `use_official_google_api_keys = false`, none in the build. Chromium's sign-in and sync do not work without them, which Brk does not use.

## How the build behaves

`engine/tools/paced-build.py` runs ninja at nice 15 with at most 6 jobs and sends SIGSTOP to ninja alone (its running compilers finish, no new ones start) while
someone holds `/tmp/brk-core-native.lock` or the machine is short of memory, SIGCONT when that ends. It holds no `/tmp/brk-*.lock`. Each state change is a line
in the log's `.pace.log`; `.pace.json` has the current state. A SIGSTOP in the middle of a job costs nothing: ninja continues where it stopped.

## Patch rules

Brk's code lives in `brk/`. Chromium's own files get one-line hooks through `brk/embedding/embedding.h`, which has no dependencies, so that the patches are small and
a Chromium upgrade has little to redo. No edit to a widely included header: one would recompile half the tree. Every hook is empty unless the framework was started by
`BrkCoreApplicationPrepare`, so a plain `chrome` still builds and runs from the same tree.
