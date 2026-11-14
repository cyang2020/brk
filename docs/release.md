# Releases

Brk releases start at 0.0.1. `VERSION` is the marketing version, and `releases/<version>.md` is the curated source for GitHub notes and the bundled **Help > Release Notes** history. Keep older entries in the repository.

Older 0.1.0 copies have no updater. Install the first updater-equipped release from its disk image once. Later copies download a signed update from the sidebar and restart through Sparkle.

## Publish a version

1. Bump the patch version in `VERSION` before shipping changed code after a published release.
2. Add `releases/<version>.md`. Start with `# Brk <version>`, then describe changes users can notice. The supported format is paragraphs, headings, bullet lists, inline code, and bold text.
3. Validate and inspect the notes locally.

   ```sh
   python3 scripts/release.py validate
   python3 scripts/release.py markdown --signed true --build 43 --commit local
   python3 scripts/release.py html --history > /tmp/brk-release-history.html
   python3 -m unittest discover -s scripts/tests -p 'test_release.py'
   ```

4. Commit and push to `main`. The Release workflow creates the normal release `v<VERSION>` with permanent downloads, notes, and appcasts. A pushed `v*` tag must agree with `VERSION` and target the same commit.

A version tag is never moved. A published version's assets and notes are never overwritten. Validation rejects an existing tag that targets different code before downloading engines or compiling. Rerunning the exact published commit reuses its public artifacts and can repair the `latest` aliases without rebuilding. An interrupted draft can be completed at the same commit. If publication races with a new build, that build stops rather than publishing different bytes under existing URLs.

Manual runs on other branches create a draft `ci-test-<run id>` release. They do not change the stable updater or `latest`. Stable runs are serialized across `main` and version tags. The publisher also refuses to replace a newer `latest` build with an older one.

## Versions and notes

`scripts/release.py` owns validation and rendering.

| Command | Output |
| --- | --- |
| `version` | The validated stable SemVer in `VERSION`. |
| `validate --tag v0.0.1` | Validates version, nonempty curated entry, and optional tag agreement. |
| `validate --check-published --repository owner/repo --commit <sha>` | Also rejects a version tied to different code and reports an already published commit. API errors fail validation. |
| `markdown --signed true --build <number> --commit <sha>` | The current curated entry with installation and build information. |
| `html` | The current version's permanent `release-notes.html` asset. |
| `html --history` | All entries through the current version, newest first, for the app's offline Help page. |
| `appcast --repository owner/repo --arch arm64 --build <number> --archive Brk-arm64.dmg --signature-file <file>` | A feed that refers only to this version's permanent assets. The signature file contains the base64 Ed25519 signature from `sign_update -p`. |

`CFBundleShortVersionString` and `sparkle:shortVersionString` use `VERSION`. `CFBundleVersion` and `sparkle:version` use `GITHUB_RUN_NUMBER`. Build numbers must keep increasing even though the display version resets from the old 0.1.0 to 0.0.1. `BRK_VERSION`, when supplied to a local build, must agree with `VERSION`. `BRK_BUILD_NUMBER` defaults to 1 locally.

`scripts/declare-scripting.sh` writes the Help history and current marketing version before signing. `scripts/release-notes.sh <signed: true|false>` renders the GitHub entry. Neither uses commit subjects as release notes. Build provenance still appears in the plist and GitHub notes.

## Downloads and updater feeds

Each permanent `v<VERSION>` release keeps these assets.

- `Brk-arm64.dmg` and `Brk-x86_64.dmg` contain the signed and notarized app for that architecture.
- `release-notes.html` contains that version's curated changes. `notes.md` preserves the GitHub text.
- `appcast-arm64.xml` and `appcast-x86_64.xml` use immutable download and release-note URLs under `releases/download/v<VERSION>/`.
- `release.json` records version, build, source commit, and Developer ID signing status.

The compatibility prerelease `latest` keeps the existing manual download links working.

- https://github.com/cyang2020/brk/releases/download/latest/Brk-arm64.dmg
- https://github.com/cyang2020/brk/releases/download/latest/Brk-x86_64.dmg

The updater reads `releases/download/latest/appcast-arm64.xml` or `appcast-x86_64.xml`. Native hardware detection chooses arm64 on Apple silicon, including Rosetta. The publisher makes the permanent release public before refreshing the compatibility downloads, then uploads the appcasts last. A feed therefore never points to a mutable `latest` disk image.

`scripts/make-dmg.sh <app> <dmg>` creates an APFS image compressed with LZFSE. Hash-pinned dmgbuild dependencies write the Finder layout without opening Finder. Packaging must preserve the signed app and verify its signature inside the finished disk image.

## Build and signing

The macOS build job has a read-only repository token and receives signing secrets only in the steps that need them. It validates the release, runs the focused release checks and Swift unit tests, builds both architectures, and then signs and notarizes both apps and disk images.

Sparkle is pinned to 2.10.1. `scripts/bundle-app.py` calls `scripts/embed-sparkle.py <bin-dir> <app>` before app signing. Nested framework code, helper apps, and XPC services must be signed inside out by `scripts/sign-developer-id.sh`. The app contains the public key from `assets/updates/ed25519.pub`, the architecture feed URL, an eight-hour check interval, and no system-profile reporting.

The workflow downloads the [official Sparkle 2.10.1 tools](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1) and checks the archive against SHA-256 `1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27`. After notarization and stapling finish, `sign_update` signs the final disk-image bytes. CryptoKit verifies each signature against the committed public key before feed generation. This follows Sparkle's [archive signing and internal build-number format](https://sparkle-project.org/documentation/publishing/).

Stable publication fails if any required signing secret or archive signature is unavailable.

| Secret | Contents |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | Developer ID Application certificate and private key exported as base64 .p12. |
| `MACOS_CERT_PASSWORD` | Password for the .p12. |
| `APPLE_API_KEY_P8_BASE64` | Base64 App Store Connect API key with Developer role. |
| `APPLE_API_KEY_ID` | API key ID. |
| `APPLE_API_ISSUER_ID` | API issuer ID. |
| `SPARKLE_ED_PRIVATE_KEY` | Base64 Sparkle Ed25519 private key matching the committed public key. |

The private update key is written only to a protected temporary file and passed with `--ed-key-file`. It is never an argument value or a release asset. Signing diagnostics are withheld because malformed-key diagnostics can contain key material. Cleanup deletes temporary key files and the temporary Developer ID keychain even on failure. Keep the private update key for future releases.

## Workflow security and operations

The Linux publish job has the write token. It downloads artifacts and runs only the inline publisher in the workflow. It checks out no source, executes no repository code, and receives no signing secrets. All actions are pinned by full commit SHA. Fork pull requests do not trigger this workflow.

The separate download-count job reads counts before replacing `latest`, then writes only the `stats` branch. Its failure does not prevent publication. The daily job also records counts. Details are in `.github/workflows/download-stats.yml` and `scripts/download-stats.py`.

The previous path exclusions still apply to documentation, unrelated Markdown, Swift tests, the site, and `.gitignore`. The ordered `paths` filter adds `releases/**` back because those files are bundled. `VERSION` and release scripts also trigger builds. Tags bypass path filtering.

SwiftPM and llama.cpp archives are cached. BrkCore comes from `engine/artifacts.json` with checksum, architecture, revision, and interface checks. To use an Intel runner when arm64 capacity is unavailable, set `BRK_MACOS_RUNNER=macos-26-intel`; remove it to restore the default arm64 runner.

Before shipping, follow `docs/testing-policy.md` and inspect the final signed, notarized archives and published immutable URLs. Script fixtures prove metadata and publication behavior. They do not prove the native update and relaunch path.
