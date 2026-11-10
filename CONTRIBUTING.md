# Contributing to Brk

Thanks for helping. Brk is a native macOS rebuild of the Arc browser (Swift 6, AppKit, Chromium through CEF) with
upgrades on top. It is a small project with one maintainer, so focused changes with clear evidence get reviewed
fastest.

Brk is released under the [MIT license](LICENSE). By sending a pull request you agree that your change is released
under the same license. Brk is an independent project and is not affiliated with The Browser Company; "Arc" is a
trademark of The Browser Company.

## Where things go

- **Bugs:** an issue from the [bug report form](https://github.com/cyang2020/brk/issues/new?template=bug_report.yml).
  In Brk, **Help › Report a Bug…** opens it with the version, macOS, Mac and engine filled in.
- **Brk differs from Arc:** the [Arc parity form](https://github.com/cyang2020/brk/issues/new?template=arc_parity.yml),
  with Arc and Brk side by side.
- **Ideas and feedback:** the [feature request form](https://github.com/cyang2020/brk/issues/new?template=feature_request.yml)
  (**Help › Send Feedback…**), or [Discussions › Ideas](https://github.com/cyang2020/brk/discussions/categories/ideas)
  to talk it through first.
- **Questions:** [Discussions › Q&A](https://github.com/cyang2020/brk/discussions/categories/q-a).
- **Security problems:** privately, as described in [SECURITY.md](.github/SECURITY.md). Never in a public issue.

Before starting on a feature or a behaviour change, open an issue or an Ideas discussion and wait for a reply on
the direction. Small fixes for an obvious bug can go straight to a pull request.

## Build and run

You need a Mac with Apple silicon, macOS 14 or later, and Xcode with Swift 6. The first build downloads CEF
(about 132 MB) into `.cef/`.

```sh
scripts/build.sh                 # release build, unit tests, CEF bundle and ad-hoc signature: dist/Brk.app
SKIP_TESTS=1 scripts/build.sh    # the same without the unit tests
open dist/Brk.app
```

After the first full build, `scripts/station/refresh-app.sh` rebuilds only the app and helper binaries into the
existing `dist/Brk.app`, which is much faster while you iterate.

`BRK_ENGINE=stub swift run Brk` runs the whole interface without Chromium (pages are placeholders). It is handy
for sidebar, command bar and theme work.

Where the code lives:

- `Sources/BrkDomain`: the state and its rules. Every user action is a command; the rules turn commands into a new
  state and effects. Most behaviour fixes belong here and are unit-testable.
- `Sources/BrkSidebar`, `BrkContent`, `BrkOverlays`, `BrkLibrary`, `BrkSettings`: the interface.
- `Sources/BrkApp`: the app delegate, menus, windows and the glue to the engine.
- `Sources/BrkCEF`: the CEF engine. `engine/` is Brk's own Chromium build, experimental.
- `docs/design/`: design notes. `docs/arc-anatomy/`: facts measured from Arc 1.170.

## Tests

Read [docs/testing-policy.md](docs/testing-policy.md) before adding tests. The short version:

- Add a test only if it catches a problem a user would notice and no other test already catches it.
- A bug fix comes with one test that fails before the fix. Prefer a unit test; use a native scenario only when the
  bug lives in real input, windows or the Chromium embedding.
- A new feature gets a few unit tests and at most one native scenario that uses real keyboard, mouse or trackpad
  input, registered in `scripts/native-sets.txt`.
- Never commit test evidence (screenshots, logs, run reports). Put pictures in the pull request description.

Before you open a pull request, run:

```sh
swift test
swift build -c release --product brk-e2e
python3 scripts/run-native.py <a-new-name> --set smoke,<area>
```

`<area>` is the group for the code you changed; the table in the testing policy lists them. Native scenarios
launch Brk and drive it with real input, so leave the Mac alone while they run.

## Arc parity fixes

Brk follows Arc 1.170's behaviour and look unless a difference is deliberate (the README's "Arc, pixel for pixel"
and "Not in Brk yet" sections list them). A parity fix needs evidence of what Arc does, because "I remember Arc
doing this" is often wrong in the details:

1. **Show Arc.** A screenshot or short recording of Arc 1.170 doing the thing, and the same steps in Brk, at the same
   window size and appearance. For sizes, colours and timings, give the numbers you measured and how.
2. **Point at the anatomy.** If `docs/arc-anatomy/` already describes the behaviour, link the place. If your
   evidence contradicts it, say so; the document gets corrected along with the code.
3. **Keep Arc's pictures out of the repository.** Attach them to the issue or the pull request. The repository keeps
   only text and Brk's own media.
4. **Fix the rule, not the symptom.** Most parity bugs are a rule in `BrkDomain` or a measurement in the layout
   code. Add the unit test for the rule; for something visible, before and after screenshots of Brk next to Arc.

Use the [Arc parity issue form](https://github.com/cyang2020/brk/issues/new?template=arc_parity.yml) to report a
difference without fixing it.

## Pull requests

- One problem per pull request. Unrelated clean-ups go in their own.
- Fill in the template: the problem, the change, the Arc evidence if any, and what you ran.
- Write commit messages in plain words that describe what changes for the user.
- If an AI agent wrote the change, say which one in the description. That is fine; the evidence matters more than
  who typed it.

## Labels

Maintainers sort issues with these labels: `bug`, `enhancement`, `arc-parity`, `ai`, `needs-repro` (we could not
reproduce it yet and need more detail), `good first issue` and `triage` (not looked at yet). New issues from the
forms start with `triage`.
