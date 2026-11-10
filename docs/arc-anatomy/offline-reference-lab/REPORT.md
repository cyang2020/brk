# Original Arc offline reference lab

No reliably isolated login bypass was demonstrated. The containment probe failed its validation gate, so no Arc copy was created or launched. The fake-auth route remains a static candidate. References from the user's already-authenticated local Arc are still required for browser chrome.

The fallback capture helper works on an existing original Arc window. This run preserved a genuine welcome-screen PNG with signed process identity, version, window ID, geometry, scale, and hashes. That capture does not demonstrate successful authentication or browser chrome.

Investigation date: 2026-10-31 in Asia/Shanghai. Start commit: `6d2d6d50694b17d0c5e4ffcaf5b69bff4a30011d`. The final delivery SHA is the commit containing this report, also returned in the handoff. Resolve it with `git log -1 --format=%H -- docs/arc-anatomy/offline-reference-lab/REPORT.md`.

## Findings and their limits

| Status | Finding | Evidence |
| --- | --- | --- |
| Proven, static | Installed Arc is 1.170.0, build 89123, `company.thebrowser.Browser`. Its arm64 slice equals the cached target byte for byte. All seven prior branch checks pass. | [identity.json](evidence/identity.json), [verifier](verify-identity.py) |
| Proven, static | The two test flags lead to construction of an internal Test User and auth actions in the analyzed path. A separate test branch bypasses one identity check. This does not prove startup reaches chrome. | [prior report](../offline-auth/REPORT.md), [auth branch](../offline-auth/102e00cc8.s), [session constructor](../offline-auth/100c1fb7c.s), [identity check](../offline-auth/102e448d0.s) |
| Proven, static | Arc's preferences path uses `standardUserDefaults`. The observed `--user-data-dir` suite applies to the Dia branch. | [suite selection](../offline-auth/1007e56e0.s), [defaults consumer](../offline-auth/100d865b4.s), [ApplicationPaths](../offline-auth/100d8f218.s) |
| Proven, static | The installed signature includes explicit Arc auth and WebAuthn keychain groups and a CloudKit container. Changing only Info.plist's bundle ID would not remove these declarations. | `entitlements` in [identity.json](evidence/identity.json) |
| Proven, runtime probe | The owned sandbox command terminated with signal 6, returned no stdout or stderr, and created no allowed marker. The owned outside sentinel was unchanged. This is not proof that the sandbox worked. | [containment-probe.json](evidence/containment-probe.json) |
| Skipped | Copying, resigning, launching, or applying fake-auth flags to Arc. No backend auth request was made. | Failed prelaunch gate; [decision log](decisions.tsv) |
| Proven, runtime capture | Existing original Arc PID 45596, window 16, yielded a genuine 2560×1600 PNG at 2× scale. Visual inspection shows “A browser for you.” and a forward arrow. | PNG kept outside the repo (`~/brk-arc-reference/offline-reference-lab/cloud-existing-window.png`), [metadata](evidence/cloud-existing-window/metadata.json) |
| Unknown | Whether any compliant same-user isolation configuration can reach browser chrome with fake auth; why this strict probe aborted; all later auth gates; differences caused by test mode. | No Arc runtime experiment was performed. |

The current welcome-screen observation differs from the earlier description of a “Sign In to Arc” screen. This run only read the existing window. It did not click, navigate, activate, resize, restart, or close Arc, and it does not infer who changed the state or when.

## Target identity and reused evidence

The installed universal executable SHA-256 is `25af5f4eaaae5aca25021f2737e90cc4d41fdf195c4a5c4012ea31a1bba4b86a`. The arm64 slice SHA-256 is `77be289e16a139056dd9d0bf145ad4707d4e217289bb279a333949dcfd39c52d`.

The [identity verifier](verify-identity.py) reads `/Applications/Arc.app/Contents/MacOS/Arc`, maps each checked instruction through its actual file-backed Mach-O segment, and compares the bytes and decoded BL target with `offline-auth/identity-and-branch-checks.json`. It also reads public bundle metadata and signing declarations. [identity-after.json](evidence/identity-after.json) equals the initial identity record, including executable and Info.plist hashes. This verifies those artifacts, not an absence of unrelated activity by the already-running Arc.

This investigation followed `reverse-engineer-anything` and its native guide. It reused `/Users/administrator/.cache/arc-disasm` and the prior report's matching `.s` files. No full native import, REA installation, configuration change, or new native REA session was attempted. The prior report records the unavailable `GHIDRA_INSTALL_DIR`; the task also supplied the earlier unrelated adb discovery timeout. These are inherited tool limitations, not newly reproduced errors. All new records here are ordinary shell, file, process, or ScreenCaptureKit observations. No new REA Evidence IDs are claimed.

## Containment experiment recorded before execution

Before the probe ran, this report recorded the command shape, owned paths, denied services, and cleanup contract below. The test executed only the compiled [probe.c](probe.c), never Arc.

The [runner](run-containment-probe.py) creates a fresh `arc-reference-gate.*` directory using `tempfile.mkdtemp` and resolves its physical path. Both `allowed` and `outside` belong to the experiment. The outside sentinel contains only a disposable marker. There are no probes against real preferences, keychains, profiles, or app-group directories.

The exact executed argv and environment are retained in [containment-probe.json](evidence/containment-probe.json). The command shape was:

```sh
/usr/bin/sandbox-exec -D ROOT="$LAB" -D WRITE="$LAB/allowed" \
	-f "$REPO/docs/arc-anatomy/offline-reference-lab/probe.sb" \
	"$LAB/probe" "$LAB/allowed/marker" "$LAB/outside/sentinel"
```

The [profile](probe.sb) denies operations by default. It permits writes only beneath the owned `allowed` directory; reads beneath the owned root, `/System`, and `/usr/lib`, plus `/dev/urandom`; execution of the owned probe; and sysctl reads. It grants no Mach service lookup or networking permission. The broad `/System` read rule was only a diagnostic probe rule, not an audited Arc read-isolation policy. It must not be reused as a claim of protection for user data through mounted paths.

The child receives only `PATH`, `HOME`, `CFFIXED_USER_HOME`, and `TMPDIR`. The home and temporary paths point into `allowed`. These environment variables are redirects, not the containment guarantee. The runner closes other inherited file descriptors, captures standard streams, sets a 15-second timeout on its own child, and removes only its fresh root.

Parent correction after this recorded run: the current probe runner passes only `PATH` and no longer redirects home or temporary-directory environment variables. The original observation above and its JSON record are retained unchanged. This correction does not establish containment, and the parent did not rerun the sandbox or launch Arc.

The intended checks were an allowed marker write, a denied write to the owned outside sentinel, lookup of named preference/security/CloudKit/LaunchServices/WindowServer endpoints, and socket creation without a connection attempt. The run returned `-6`, meaning SIGABRT in Python's subprocess result. It returned no check results and created no marker. The sentinel SHA-256 stayed `bd0e4d0e5dd14d7e196462835bb7d05e6f0565b20c59f9f747fd71636df6baf4`. Cleanup completed. The abort's precise cause was not established. No restriction was relaxed and no Arc launch followed.

Reproduce this bounded probe from the repository root:

```sh
python3 -B docs/arc-anatomy/offline-reference-lab/run-containment-probe.py
```

The script prints `gate: NOT_ESTABLISHED` even if a later OS lets the elementary checks run. Those checks alone cannot establish a GUI application's full containment boundary.

## Exact missing guarantee

There is no demonstrated OS boundary that allows Arc's UI while containing the original process and all helpers before initialization, including direct file access, daemon-mediated preferences and keychain access, app-group data, default-browser registration, and indirect network access. The failed probe establishes neither service denial nor inherited/helper restrictions.

A unique copied-bundle identity would be only one part of that boundary. The installed signature still declares `S6N382Y83G.company.thebrowser.browser.auth`, `S6N382Y83G.company.thebrowser.browser.webauthn`, and `iCloud.net.arc.sidebar`. A copy would require an owned identity, reviewed nested helpers and signing declarations, and a tested deny-by-default OS policy. None was created in this run. No copy was made to identify as Dia.

The observed restart code supplies `-customApplicationDataBaseURLPath` and `-cloudKitSyncEnabled false`, but does not prove complete redirection or network isolation. The conditional `--use-mock-keychain` path depends on another flag, not simply the two auth environment variables. See [restart arguments](../offline-auth/102e5122c.s), [mock-keychain path](../offline-auth/1000035a4.s), and [entry initialization](../offline-auth/100003138.s).

Chromium's [macOS sandbox design](https://chromium.googlesource.com/chromium/src/+/master/sandbox/mac/seatbelt_sandbox_design.md) explains why resources acquired during framework initialization and allowed service endpoints require explicit review. This supports the prelaunch requirement, not a claim that the diagnostic profile isolates Arc.

There is consequently no safe-to-copy Arc launch recipe in this report. This is a bounded failure to establish isolation, not proof that offline browser chrome is impossible. No OS user, VM, SIP, TCC, global security, default-browser registration, profile, preference, or credential change was performed.

## Genuine capture and helper validation

The helper is [scripts/capture-arc-reference.swift](../../../scripts/capture-arc-reference.swift). [CAPTURE.md](CAPTURE.md) provides standalone build and usage instructions for the user's Mac.

A read-only capture command was recorded here before execution:

```sh
/tmp/arc-reference-capture-b785f401 --pid 45596 --window-id 16 \
	--output "$REPO/docs/arc-anatomy/offline-reference-lab/evidence/cloud-existing-window" \
	--label "Existing cloud Arc window; no launch or login interaction"
```

Only the observer ran. It wrote the fresh capture directory, used existing screen-capture permission, and sent no input to Arc. It did not terminate PID 45596 or its helpers. Existing Arc's background activity was outside this experiment; no claim of network isolation applies to that already-running process.

The first helper draft relied on AppKit application enumeration, which returned no Arc despite `ps` and WindowServer identifying it. ScreenCaptureKit also reported an empty bundle identifier for window 16. The final helper uses the kernel executable path, process start timestamp, dynamic code-signing requirement, signed on-disk bundle, and matching window owner PID/ID as the authority. A nonempty conflicting ScreenCaptureKit bundle ID is rejected. The metadata preserves the empty reported ID rather than filling it with invented evidence.

The captured window bounds were `{x:320,y:70,width:1280,height:800}` points. Capture ran at `2026-10-30T18:08:58Z` to `18:08:59Z`. PNG SHA-256 is `baabdd7871b7eb799f0f6b1dd4c187bb2ef7fdd07bc1ce509549c084f301b05d`. The file is the helper's original PNG output, not a reconstruction or edited screenshot. Its hash and IHDR dimensions match the metadata. The recorded display dimensions and backing scale are separate API observations; capture scale comes from ScreenCaptureKit's window filter.

Validation used Swift 6.3.3 with a macOS 14 deployment target on arm64 macOS 26.6.2. [helper-checks.json](evidence/helper-checks.json) records CLI argument rejection, refusal of a non-Arc PID, refusal of existing output with its sentinel preserved, rejection of an unavailable window, signed live-window listing, and pixel checks. Transparent and uniform in-memory pixel fixtures were rejected; varied pixels were accepted. These fixtures produced no reference images. A real welcome-window capture separately exercised the full screenshot path.

Reproduce the helper checks after compiling it as described in CAPTURE.md:

```sh
python3 -B docs/arc-anatomy/offline-reference-lab/verify-capture-helper.py /tmp/capture-arc-reference
python3 -B docs/arc-anatomy/offline-reference-lab/verify-identity.py
```

The identity verifier expects this cloud machine's cached target path. The capture helper itself has no cache or repository dependency.

The remaining local work is to run the helper against the user's already-authenticated Arc and manually select browser states. Logged-in chrome, different macOS/Intel environments, permission-denied capture, and test-mode UI equivalence were not exercised here. The helper refuses absent/transparent/uniform pixels, but human inspection remains necessary for partial content or OS privacy placeholders. Its success does not establish login state.

## Scope and handoff

### Parent integration checks

The parent compiled the helper and independently ran its CLI, identity, output-refusal, and pixel checks. A concurrent real-capture probe did not finish one request within its 60-second caller limit and produced no reference directory. Its other process outcome was not collected; it is inconclusive about concurrency. A later exact-path check found no owned helper still running. Arc was not signaled.

The parent added a 30-second capture deadline that ends only the observer before output creation. The deadline's expiration and cancellation paths pass executable checks, alongside the original helper checks. A separate late-output collision probe preserved the first file and returned the expected existing-file error; its suspected overwrite issue was rejected and the file-writing logic was left unchanged.

The bounded helper then made a successful single capture of the existing Arc window. The parent inspected the actual PNG: it is the welcome screen, not authenticated browser chrome. [Parent checks and capture](evidence/parent/), including the updated helper source digest, preserve these results. The [standalone capture package](../../../artifacts/arc-reference-capture.zip) contains the same current Swift source plus instructions. Neither this validation nor the package establishes fake-auth startup or pixel parity.

The original worker delivered only this lab directory and the standalone capture script. It left Brk production code, the canonical feature inventory, audits, and the prior auth report unchanged and removed its temporary probe/validation files. The parent integration additionally updates the reference status, packages the helper, and records its own checks. No installed Arc bundle or existing browser data was edited by either pass. No Arc process was launched, signaled, or closed.

The report and helper were reviewed in this single agent, as requested. The decision trail follows the show-me-your-work format; its cross-model review step was omitted under the explicit no-subagent constraint. The material limitations are the failed containment gate and the absence of authenticated chrome captures.
