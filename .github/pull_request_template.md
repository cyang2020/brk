<!--
Read CONTRIBUTING.md first. One problem per pull request.
Write the title in plain words, the way a user would notice the change, for example
"Command bar: Tab no longer skips the first result".
-->

## Problem

<!-- What was wrong or missing, for whom, and how to see it. Link the issue if there is one. -->

## Change

<!-- How this fixes it. If it touches several modules, say why the same fix needs them. -->

## Arc evidence

<!-- For Arc parity changes: what Arc 1.170 does, and how you know (a side-by-side screenshot or recording
of Arc and Brk, a measurement, or the place in docs/arc-anatomy/). Write "Not an Arc parity change" otherwise.
Put pictures in this description, not in the repository. -->

## Checks

<!-- What you ran and what you saw. Follow docs/testing-policy.md: the unit tests, plus
`python3 scripts/run-native.py <name> --set smoke,<area>` for the area you changed.
For anything visible, before and after screenshots. Say what you could not check. -->

- [ ] `swift test` passes
- [ ] Native scenarios for the changed area pass (which: …)
- [ ] No test evidence (pictures, logs, run reports) is committed

<!-- If an AI agent wrote the change, name the agent and model here. -->
