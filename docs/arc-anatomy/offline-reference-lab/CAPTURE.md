# Capture references from your logged-in Arc

Use your own Mac with Arc already running and logged in. The helper does not launch, sign in, activate, resize, or close Arc. It reads application identity and window metadata, captures one selected Arc window, and writes a PNG with a JSON sidecar. It does not read browser databases, preferences, cookies, tokens, or keychain items.

## Build and select a window

Requires macOS 14 or later and Xcode Command Line Tools. From the repository root:

```sh
xcrun swiftc -parse-as-library -O -target "$(uname -m)-apple-macosx14.0" \
	scripts/capture-arc-reference.swift -o /tmp/capture-arc-reference
/tmp/capture-arc-reference --list
```

`--list` prints Arc PIDs, window IDs, geometry, version, and executable hash. It only accepts the `company.thebrowser.Browser` bundle signed by The Browser Company, team `S6N382Y83G`. It does not accept a renamed app or the replica as a reference. It omits window titles from metadata.

Choose the PID and window ID from that output. Arrange the desired UI yourself. Use a new output directory for each capture:

```sh
/tmp/capture-arc-reference --pid 12345 --window-id 6789 \
	--output "$HOME/Desktop/arc-reference-sidebar" --label "Sidebar expanded"
```

Replace the two numbers with the actual listed values. The output directory must not already exist, and its parent must exist. On success it contains `window.png` and `metadata.json`. The helper refuses existing output so it cannot overwrite another capture.

If screen capture access is unavailable, the helper exits without requesting permission or writing a reference. On your Mac, grant Screen & System Audio Recording permission to the terminal or helper through System Settings if you want to use it, then rerun. The cloud investigation makes no TCC changes.

Capture the expanded and collapsed sidebar, command bar, tab switcher, split view, library, and settings as separate real states when available. Use an empty or non-sensitive tab. Menus and separate popovers may be separate windows and are not included automatically. Pick their own listed Arc window if capturable. Do not interpret an absent popover in the parent-window PNG as proof that Arc lacks it.

## Metadata and failure behavior

The sidecar binds the PNG SHA-256 to the selected PID, process launch time, CGWindowID, bundle and executable paths, bundle ID, version, build, code signature requirement, executable SHA-256, capture time, OS version, window bounds before and after capture, ScreenCaptureKit content rectangle, point-to-pixel scale, output pixel dimensions, and display geometry/scales.

The capture uses `SCContentFilter(desktopIndependentWindow:)`, excludes the cursor and window shadow, and uses the filter's pixel scale. It fails if ownership or bounds change, the process exits or restarts, the executable changes, the API returns no image, or the pixels are transparent or uniform. A nonuniform image can still contain an OS privacy placeholder or partially missing content, so inspect the PNG before using it as a reference. The helper does not claim to detect login state or prove production-equivalent UI.

Compilation and negative checks on the cloud Mac do not establish that a logged-in browser window can be captured on your Mac. The report records the validation actually performed here.

## Implementation choice

This standalone helper has three operations: `listWindows()` reads signed Arc identities and CGWindow metadata; `capture(pid, windowID)` uses a single-window ScreenCaptureKit filter; `writeCapture()` commits actual pixels and metadata into a fresh directory after validation.

The alternatives considered were a `screencapture -l` shell wrapper and a Swift ScreenCaptureKit helper. The Swift helper was selected because ownership checks, content scale, returned pixels, and metadata can be validated together. There is no connection to Brk production code. This is a single-agent implementation under the task's explicit constraint.

The capture APIs and scale semantics follow Apple's [single-window filter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)), [screenshot API](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage(contentfilter:configuration:completionhandler:)), and [pointPixelScale](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/pointpixelscale) documentation, plus the installed SDK headers.
