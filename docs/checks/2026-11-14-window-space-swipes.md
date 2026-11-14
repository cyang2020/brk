# Window edges and Space swipes

The native titlebar container stays aligned with the window. Its inner titlebar retains the traffic-light offset. A hidden sidebar stays revealed through a Space change until pointer tracking dismisses it. Theme requests coalesce through AppKit's backing layer, with Metal in a transparent sublayer.

## Verification

- `python3 scripts/with-batch-locks.py --lock /tmp/brk-batch-build.lock -- swift test` passed 1,185 tests, with two designed skips and no failures, in 133 seconds. The floating-sidebar regression failed its two reveal assertions before the fix.
- `python3 scripts/run-native.py window-spaces-verified-20261114 --set smoke,windows,spaces,core --app <verified-app>` ran all 27 requested scenarios. R56 initially exceeded its 500 ms response check. Its one prescribed isolated retry passed in 35 seconds. The other 26 passed in the grouped run.
- Station P01 and P04 ran on base `0976f5f49` and the fix on the same display. The corrected renderer preserves the gradient and texture. Native hover, resize and fullscreen-return checks retain button positions. A physical hover/swipe/exit reproduction confirms the floating sidebar remains open after switching and closes on pointer exit.

## Responsiveness comparison

Both sides used release Swift binaries and the verified engine pinned in `engine/artifacts.json`, Chromium revision `26767050dcbe3df0450ca54eb632be3719bcdd2f`. Each side ran five times in alternating order on a Mac mini M1 with two Spaces, local pages updating their titles, and 4 ms physical scroll events. All 60 switches per side succeeded.

The median of each run's largest control-response sample was 517 ms before and 416 ms after. Per-run peaks ranged from 500–537 ms before and 299–477 ms after. Samples above 500 ms fell from nine to zero. These measure main-thread control responsiveness during the stress workload, not animation FPS. Background Chromium compilation was active throughout the comparison.

Runtime sampling located synchronous drawable waits in the old gesture path. The fix consumes drawables only in AppKit display passes. An initial implementation produced no texture; a native probe established that a custom Metal backing layer did not invoke `updateLayer`. The final implementation retains AppKit's backing layer and passed the visual comparison.
