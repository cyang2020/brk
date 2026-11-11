# Releases

Every push to `main` that changes the app builds Brk for Apple silicon (arm64) and Intel (x86_64) on GitHub Actions and publishes both. The workflow is `.github/workflows/release.yml`.

## Where builds appear

All builds are on the [Releases page](https://github.com/cyang2020/brk/releases).

- **Latest build** (tag `latest`) is a pre-release that always holds the newest build of `main`. Each push moves the tag to its commit and replaces the two disk images. Its notes list the commits since the previous build.
- **v\* releases** (`v1.0.0` and so on) are normal releases, one per tag. Their notes list the commits since the previous `v*` tag.

Each build has two disk images, `Brk-arm64.dmg` and `Brk-x86_64.dmg`. Opening one shows Brk next to a link to the Applications folder, over an arrow and the line "Drag Brk into Applications"; dragging Brk onto the folder installs it, as with most Mac apps. The file names carry no version, so these links always download the newest build of `main`, and the website, the README and the release notes use them:

- https://github.com/cyang2020/brk/releases/download/latest/Brk-arm64.dmg
- https://github.com/cyang2020/brk/releases/download/latest/Brk-x86_64.dmg

`scripts/make-dmg.sh <app> <dmg>` builds an image. It uses [dmgbuild](https://github.com/dmgbuild/dmgbuild), which writes the window's layout (Finder's `.DS_Store`) itself, so no Finder or AppleScript is needed on the runner. dmgbuild and its two dependencies are installed into a throwaway virtual environment, pinned by hash in `scripts/dmg/requirements.txt`; they need Python 3.10 or later from `PATH` (Xcode's `/usr/bin/python3` is 3.9). The layout is `scripts/dmg/settings.py` (a 660 by 400 window, 128-point icons, the app at x 170 and Applications at x 490). The background is drawn by `scripts/dmg/background.swift`, which writes `background.png` and `background@2x.png`; rerun it after changing the picture. The image is APFS, compressed with LZFSE (`ULFO`).

The version is:

- for `main`, `<last v tag, or 0.1.0>-<run number>.<commit>`, for example `0.1.0-57.1a2b3c4`;
- for a tag, the tag without its `v`.

Inside the app, `CFBundleShortVersionString` is the tag's version (or the last tag's on `main`), `CFBundleVersion` is the workflow run number and `BrkGitCommit` is the commit.

## What a run does

A run has two jobs. The `build` job runs on one `macos-26` runner (Apple silicon, Xcode 26.6), in this order:

1. If all five signing secrets are set (see below), signing is on. Otherwise the apps are signed ad hoc; if only some are set, the run says which are missing.
2. `scripts/build.sh` runs the unit tests and builds the arm64 app.
3. `ARCH=x86_64 scripts/build.sh` builds the Intel app. It is cross-compiled on the same machine: the Swift products are built with `--triple x86_64-apple-macosx14.0` and bundled with the `macosx64` CEF, the Intel Dock tile plug-in and llama.cpp's Intel runtime. The unit tests run only once, in step 2.
4. With signing on, both apps are signed with the Developer ID, notarized and stapled.
5. The job packs each app into its disk image (signed and notarized too when signing is on), writes the notes (`scripts/release-notes.sh`) and hands them on as a workflow artifact (kept three days).

When GitHub has no Apple-silicon runner free (it happens: a job can wait 15 minutes and be cancelled with "not acquired by Runner"), set the repository variable `BRK_MACOS_RUNNER` to `macos-26-intel` (Settings > Secrets and variables > Actions > Variables). The job then runs the tests and builds the Intel app natively and cross-compiles the arm64 one. Delete the variable to go back.

The `publish` job then runs on a Linux runner. It takes the artifact and puts the disk images and notes on the release with `gh`, and deletes files the build no longer makes (the zips of earlier builds). It moves the `latest` tag through the GitHub API.

Three caches keep later runs fast: SwiftPM's `.build` (saved per commit, restored from the newest one), the CEF downloads (`.cef/dist`, per CEF version) and the llama.cpp archives (`~/.cache/brk-llama`). A fresh checkout gives every file a new modification time, and SwiftPM would rebuild everything because of it. To avoid that, the workflow sets each file's time from its git content hash, so unchanged files look unchanged to the cached build.

Pushes that only touch `docs/`, `Tests/`, the website (`site/`), Markdown files or `.gitignore` build nothing, because they cannot change the app. A newer push to `main` cancels a run that is still going. Tag runs always finish.

## Cutting a release

```sh
git tag v1.0.0 <commit on main>
git push origin v1.0.0
```

The run builds that commit and creates the release "Brk 1.0.0" with both disk images. A manual run (Actions > Release > Run workflow) on `main` refreshes Latest build. On any other branch it makes a draft release named `ci-test-<run id>` and creates no tag.

## Signing and notarization

Without signing secrets the apps are signed ad hoc, as `scripts/build.sh` does locally. macOS then refuses to open a downloaded copy at first. The release notes tell the user to run `xattr -dr com.apple.quarantine /Applications/Brk.app`, or to right-click > Open. On macOS 15 and later, right-click > Open is gone: they open the app once, then click Open Anyway in System Settings > Privacy & Security.

Signing turns on when all five repository secrets are set (Settings > Secrets and variables > Actions):

| Secret | What it holds |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | The "Developer ID Application" certificate with its private key, exported from Keychain Access as .p12, then base64 (`base64 -i cert.p12 \| pbcopy`). |
| `MACOS_CERT_PASSWORD` | The password given when exporting the .p12. |
| `APPLE_API_KEY_P8_BASE64` | An App Store Connect API key (.p8, role Developer), base64. Create it under App Store Connect > Users and Access > Integrations > Team Keys. |
| `APPLE_API_KEY_ID` | That key's ID. |
| `APPLE_API_ISSUER_ID` | The issuer ID shown above the keys list. |

The team ID comes from the certificate, so it needs no secret. With signing on:

- the .p12 goes into a temporary keychain that is deleted at the end of the job;
- `scripts/sign-developer-id.sh` signs every piece of code inside-out, with the hardened runtime and a secure timestamp. It starts with the CEF framework's libraries and the llama.cpp runtime, then the framework, the Dock tile plug-in and the five helpers, and ends with the app. Notarization rejects nested code that was signed only through `codesign --deep`;
- the entitlements follow Chromium's own Mac build. The renderer, GPU and plugin helpers get `com.apple.security.cs.allow-jit` (`scripts/signing/helper-jit.entitlements`). The app gets camera, microphone, location, Bluetooth, USB, printing and Photos (`scripts/signing/app.entitlements`), because under the hardened runtime macOS refuses those devices to an app signed without them;
- `scripts/notarize.sh` submits each app with `xcrun notarytool` and the API key, waits for Apple's answer, staples the ticket and checks it with `spctl`. Only then is the app packed into its disk image;
- `scripts/make-dmg.sh` signs the disk image with the same identity, and `scripts/notarize.sh` notarizes and staples the image as well, so neither opening the image nor the app copied out of it needs a network check.

The hardened runtime's library validation means a signed Brk loads only frameworks signed by the same team. That includes Brk's own Chromium build (`BRK_ENGINE=core`), so that engine only works in local, ad hoc builds.

## Security

The repository may become public, so the workflow is written to be safe with the signing secrets in a public repository:

- **Triggers.** Only `push` (to `main`, tags `v*`) and `workflow_dispatch` start it. There is no `pull_request` and no `pull_request_target`, so code from a fork never runs with the secrets or a write token. Pushing and manual runs need write access to the repository.
- **Permissions.** The workflow's token is read-only (`permissions: contents: read`). Two jobs get `contents: write`, and neither receives a signing secret: `publish`, which runs no code from the repository, and `downloads` (download-stats.yml), which runs `scripts/download-stats.py` from `main` and pushes only the `stats` branch. The `build` job checks out with `persist-credentials: false`, so the build scripts cannot find a token in `.git/config`.
- **Pinned actions.** Every action is pinned to a full commit SHA, with its version in a comment: `actions/checkout`, `actions/cache`, `actions/upload-artifact` and `actions/download-artifact`, all from GitHub. There are no third-party actions. Signing, notarization and the release upload are plain shell, `security`, `codesign`, `xcrun` and `gh`.
- **Secrets stay hidden.** The secrets reach only the steps that use them, through `env` on those steps, never at job or workflow level. The step that decides whether signing is on receives only whether each secret is set, not its value. Nothing echoes a secret. The decoded .p12 and .p8 are written under `$RUNNER_TEMP` with `umask 077`. The .p12 is deleted right after the import, and the temporary keychain's password is registered with `::add-mask::`. A cleanup step that runs whatever happens (`if: always()`) deletes the keychain and both files. Apple's Developer ID G2 intermediate, downloaded from apple.com, is checked against a pinned SHA-256.

## Download counts

GitHub counts how often each release file is downloaded, but the count belongs to the file, and every push to `main` replaces the two disk images of Latest build, so their counts would be lost. `.github/workflows/download-stats.yml` reads the counts of every release file every day at 23:50 UTC, and the Release workflow calls it once more right before it publishes, while the old files still exist. It can also be run by hand (Actions > Download stats > Run workflow).

The readings go to the `stats` branch, which holds no code: `downloads.tsv` (time, reason, release, file id, file name, downloads; one row per file per reading), `repo.tsv` (stars and forks) and a `README.md` with the totals, Apple silicon and Intel, and new downloads per day, so [the branch's page](https://github.com/cyang2020/brk/tree/stats) shows them. A file's count only grows while it exists, so the total is the sum of the highest count recorded for each file. Counting began on 2026-11-11; downloads of files replaced before then are not included. If the reading before a publish fails, the publish still runs, and the downloads of the replaced files since the last daily reading are lost.

The script is `scripts/download-stats.py`; it needs only the workflow's own token. GitHub's visitor numbers for the repository page (Insights > Traffic) cover 14 days and are not recorded here: the workflow's token cannot read them.

## Cost and time

The repository is public, and GitHub-hosted standard runners cost nothing for public repositories. On a private repository, macOS minutes are billed at about ten times the Linux rate ($0.062 a minute instead of $0.006), and a plan's included minutes run out ten times as fast. A run of 6 to 19 macOS minutes would then cost $0.37 to $1.18 per merge.

Measured on `macos-26` on 2026-11-10 (build job; the publish job adds about 25 seconds on Linux):

| Step | Cold (no cache) | Warm (no Swift change) |
| --- | --- | --- |
| Checkout and caches | 0:13 | 0:18 |
| Unit tests and the arm64 app | 10:44 | 2:48 |
| The x86_64 app | 4:57 | 0:25 |
| Saving the SwiftPM build | 0:29 | 0:11 |
| Signing and notarizing both apps | 1:50 | 1:36 |
| Zips, notes and the artifact (measured before the switch to disk images) | 0:34 | 0:31 |
| **Whole job** | **about 19 minutes** | **6 minutes** |

Tests that GitHub's runners cannot run are skipped only there (`GITHUB_ACTIONS`): `PageSandboxTests.testAPageCannotReachTheNetworkByAnyWayItHas` loads its page locally in 3 seconds, but on the runners the page's load event never fires, for reasons not yet found. The Little Arc size checks need a bigger screen than the runners' 1024x768.

A merge that changes Swift code rebuilds only the modules it touches and lands between those two. The unit tests themselves take about two minutes. Waiting for a runner is not included: Apple-silicon runners are sometimes short, and a job can wait 15 minutes and be cancelled (see `BRK_MACOS_RUNNER` above).
