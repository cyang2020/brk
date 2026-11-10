# Candidate handoff

Candidate complete on branch `t3/design-brk-core-interface-1`.

Starting SHA: `ae96ea121a87e23682c25eff1dfe774cb9899eea`. The final commit SHA is in the parent-facing handback. Only `docs/completion/core-candidate/` and `819ecffb9b:verify/completion/core-candidate/` are added. All 1,924 inherited files, including the inventory, plan, audit, source, and prior evidence, match the starting checkout. The worktree is clean after commit. No PR or publication was created.

Read [README.md](README.md) for caller usage, recommendation, rationale, and the structurally different alternative. [Interface.swift](Interface.swift) is the executable typecheck with explicitly unimplemented bodies. [Ownership.md](Ownership.md) defines the behaviors and races; [Migration.md](Migration.md) assigns files, deletions, tests, and later-feature dependencies. [The evidence report](../../../verify/completion/core-candidate/REPORT.md) contains terminal/file/callback proof and unresolved feasibility gates. [COMMANDS.md](../../../verify/completion/core-candidate/COMMANDS.md) records the exact run sequence and failed-attempt disposition.

Recommend window-owned page realizations and engine-owned transfers that retain their initiating browser/context while accepted public downloads run. The decisive observations are:

- Current same-tab selection produces two claims but one native surface. Corrected CEF input tracing reproduced a command bar opening in the other window in one of three launches. Two independent browsers at one URL passed native typing assertions.
- Keeping only a download control callback does not preserve the transfer after browser destruction. Retaining the initiating browser completed the exact 2 MiB file, and cancel after presentation removal stopped the real transfer. Private expiry must explicitly cancel; retained private downloads otherwise complete after their window closes.
- PDF output, MHTML with offline reopening, native PDFKit print-sheet cancellation, find counts/ordinals, and host/profile-isolated cookie deletion have actual CEF or native callback evidence. A Chrome dialog appearing is never counted as completed output.

Validation passed: 460 build tests with three known skips and zero failures; all 46 native scenarios passed on the final prototype bundle; all standalone evidence checks and the interface typecheck passed. The final tested executable SHA-256 is `bc5ad7cc63c5a1195b3d241873b1b78b0777b2bdb9b93e53bd973e535b6faf7d`. The bundle was built from the starting commit plus the exact v4 instrumentation, whose hashes and patch are committed. Production source was restored after the probes.

No external blocker prevents judging this candidate. Remaining implementation gates are explicit: pending destination replies during source/context changes, multiple simultaneous transfer owners, editable selection/replace and undo, actual printer submission, domain-cookie matching, broader site-storage classes, and integration of window-local restoration/split/Peek semantics. Each has a bounded next experiment in the evidence report. Authenticated Arc behavior and visual parity remain unknown. The full inventory is unchanged; this package does not claim the whole Arc replica is complete.
