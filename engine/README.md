# Brk's own Chromium build

BrkCore is Brk's only browser engine: Chromium's `chrome/` layer in `BrkCore.framework`. Its WebContents views attach directly to Brk's page cards, without a separate host window per tab. The reasoning is in `docs/chromium/ARC-ENGINE.md`.

App releases use the ARM64 and x86_64 archives pinned in `engine/artifacts.json`. The checksum, source revision and public interface must all match. Swift unit tests need no Chromium tree; running the app requires the packaged framework. There is no CEF fallback or engine selector.

## Layout

| Where | What |
| --- | --- |
| `~/brk-chromium/` (not in the repo) | `depot_tools`, `chromium/src` at tag 156.0.8078.88 (154.0.8037.98 until 2026-11-12, kept on branch `brk/154.0.8037.98`), `logs/`, `STATE.md` |
| `engine/config.sh` | the pinned tag and commit, the paths |
| `engine/fetch.sh` | depot_tools and the source. 18 minutes, 30 GB on this machine and connection. Safe to rerun |
| `engine/artifacts.json` | Release tag, filenames, checksums, source revision and interface hashes for both architectures |
| `engine/args/brk.gn`, `engine/args/release.gn` | development and official release build arguments |
| `engine/configure.sh [release arm64\|x64]` | writes build arguments, fetches the matching PGO profiles for release builds, runs `gn gen` |
| `engine/build.sh <target>` | compiles at low priority, pausing itself (below). `chrome` builds everything |
| `engine/patches/` | the patch series: Brk's commits over the tag, numbered |
| `engine/apply-patches.sh` | makes branch `brk/156.0.8078.88` in the tree from the tag and the series (three-way, so a patch whose context moved in a new Chromium still applies) |
| `engine/export-patches.sh` | writes the branch back to `engine/patches/` |
| `engine/sync-header.sh` | copies the one interface header `Sources/CBrkCore/include/BrkCore.h` into the tree |
| `engine/build-demo.sh` | the smallest program on the framework, `engine/demo/main.swift` |
| `scripts/build.sh`, `engine/assemble-app.sh` | package the Swift app and BrkCore into `dist/Brk.app` |
| `engine/run-native-core.py` | standard native runner, under the native lock; reports in `~/brk-evidence/native/` |
| `engine/package-artifact.py` | archive a completed, clean official engine build and print its checksum record |
| `engine/download-artifact.py` | verify and extract the pinned release engine |
| `engine/tools/check-brk.sh` | syntax-only compile of `brk/` files with a neighbouring file's flags |
| `engine/tools/arc-inspect.sh` | the static inspection of Arc that the notes cite |

## From nothing

    engine/fetch.sh
    engine/apply-patches.sh
    engine/incremental.py                            # first build takes hours; rerunning keeps the cache
    engine/build-demo.sh                             # then run the demo
    scripts/build.sh                               # dist/Brk.app uses out/Brk by default

## Incremental builds

For normal Core development, run one command:

```sh
engine/incremental.py
```

The command synchronizes the interface, configures `out/Brk` when needed, and runs Ninja against the existing objects. It keeps `args.gn` and the generated configuration unchanged on repeat runs. Ninja tracks source and header dependencies and regenerates its manifest when GN source files change. An unchanged tree finishes with `no work to do`; a local source edit rebuilds its affected objects and links the result.

The default uses the development preset, which disables PGO and ThinLTO. To incrementally build one official architecture, choose it explicitly:

```sh
engine/incremental.py --release arm64
engine/incremental.py --release x64
```

Each mode keeps its own output directory: `out/Brk`, `out/BrkRelease-arm64`, or `out/BrkRelease-x64`. Keep these directories between builds. The first invocation with an existing cache runs GN once to record the successful configuration and retains the compiled objects. Later invocations skip GN and profile downloads unless the preset, PGO reference, V8 revision, or profile scripts change, or the manifest is missing. Use `engine/configure.sh --force dev` to explicitly regenerate the development configuration.

The entry point serializes incremental invocations within a Chromium tree. If another bundled Ninja is already running there, it exits with code 75 before changing the header or build configuration. Use a separate `BRK_CHROMIUM_ROOT` for another source branch, with that branch's matching public interface. The command does not reset or reapply Chromium patches.

Changing global GN flags, Chromium versions, or widely included headers can still invalidate many objects. Reusing a cache does not make those changes local. For Swift-only changes, run `scripts/build.sh` and reuse the Core framework directly.

Run the incremental workflow integration checks with Ninja and Clang on PATH:

```sh
python3 -m unittest discover -s engine/tests -v
```

## Measured on this machine (Apple M1, 8 cores, 16 GB)

| Step | Time | Disk |
| --- | --- | --- |
| `fetch.sh` | 18 min | 30 GB source and toolchains, 0.8 GB depot_tools |
| first `build.sh chrome` | 8 h 43 min wall, 2 h 3 min of it paused for other agents | `out/Brk` 10 GB |
| a change in `brk/` | 1 to 2 min (compile and relink) | |
| a change in a widely used Chromium file | not measured; avoid it | |

Total under `~/brk-chromium`: 42 GB. The development framework is copied into `dist/Brk.app` using APFS clones.

## Development build arguments

- **Static, not component.** One framework file, the shape Arc ships and the shape the app will load. A component build relinks faster but loads
  hundreds of dylibs and is a different thing to test. A relink of the static framework takes minutes, which is acceptable.
- **Symbols.** `symbol_level = 0` for Chromium's own code: much less disk and link memory. `brk/` gets `minimal_symbols` for backtraces. Function
  names stay in the symbol table of a non-official build.
- **Not official.** No thin LTO and no PGO: both need far more memory and hours than this machine has beside other work. The binary is larger and slower
  than a release build would be. Measure before judging speed from this build.
- **`concurrent_links = 1`.** A framework link takes several GB.
- **`use_siso = false`.** Plain ninja, so the build tool can be paused alone.
- **Codecs: H.264 and AAC on** (the user's decision, 2026-11-08): `proprietary_codecs = true`, `ffmpeg_branding = "Chrome"`, as Arc and Chrome play them
  and many sites need them. The CEF 154.0.34 binary Brk ships decodes VP8, VP9, AV1, MP3, Opus and FLAC only (`engine/tools/codec-probe.py`). This build
  is local and not distributed. **Publishing it would need a licensing check first** (H.264 and AAC are patent-licensed codecs).
- **Widevine off.** It needs Google's signed component, which a self-built Chromium cannot get. The user's decision.
- **No Google API keys.** `use_official_google_api_keys = false`, none in the build. Chromium's sign-in and sync do not work without them, which Brk does not use.

## Official release builds

Run the two architectures serially on this machine:

```sh
engine/configure.sh release arm64
BRK_OUT=out/BrkRelease-arm64 JOBS=4 engine/build.sh chrome
engine/configure.sh release x64
BRK_OUT=out/BrkRelease-x64 JOBS=4 engine/build.sh chrome
```

`is_official_build` enables Chromium's PGO and ThinLTO. Binaries are stripped; line tables remain in separate dSYMs. Release codecs match the previously distributed app (VP8, VP9, AV1, MP3, Opus and FLAC); H.264/AAC and Widevine are disabled. No Google API keys are embedded. Brk starts Chromium with background networking, component updates, sync and domain reliability disabled.

After committing and exporting source changes, package each completed build with `engine/package-artifact.py`. Upload the two archives to a versioned GitHub release and record the printed metadata in `engine/artifacts.json`. A changed `BrkCore.h` requires new engine archives before app CI can build.

## How the build behaves

`engine/tools/paced-build.py` runs ninja at nice 15 with at most 6 jobs and sends SIGSTOP to ninja alone (its running compilers finish, no new ones start) while
someone holds `/tmp/brk-core-native.lock` or the machine is short of memory, SIGCONT when that ends. It holds no `/tmp/brk-*.lock`. Each state change is a line
in the log's `.pace.log`; `.pace.json` has the current state. A SIGSTOP in the middle of a job costs nothing: ninja continues where it stopped.

## Patch rules

Brk's code lives in `brk/`. Chromium's own files get one-line hooks through `brk/embedding/embedding.h`, which has no dependencies, so that the patches are small and
a Chromium upgrade has little to redo. No edit to a widely included header: one would recompile half the tree. Every hook is empty unless the framework was started by
`BrkCoreApplicationPrepare`, so a plain `chrome` still builds and runs from the same tree.
