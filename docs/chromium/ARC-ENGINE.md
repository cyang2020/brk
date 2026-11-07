# What ArcCore is, and the design of BrkCore

Part 1 records what `/Applications/Arc.app/Contents/Frameworks/ArcCore.framework` (Arc 1.170.0) is, from static inspection
only. Part 2 is the design of Brk's own framework. Part 3 says what could not be determined. Arc was never run or driven.

Labels: **[seen]** is printed by a command on the binary; **[inferred]** is my reading of what was seen. The commands are
in `engine/tools/arc-inspect.sh`; its output lands in `~/brk-chromium/arc-notes/`.

## Part 1: ArcCore

### It is Chromium's full chrome layer in one framework file

- [seen] `Resources/Info.plist`: `CFBundleShortVersionString` 156.0.8078.48, `SCMRevision`
  `2882d35e33aa53b680cc76da4dab51fd88b5af9a-refs/branch-heads/8078@{#1314}`, `DTSDKName` macosx26.5, `DTXcode` 2650. So
  Arc 1.170 is on Chromium 156. Brk's CEF is 154.0.8037.98, two milestones behind, and this work stays on 154 as asked.
- [seen] `Versions/A/ArcCore` is a universal dylib of 501,736,400 bytes (about 250 MB per architecture). Install name
  `@executable_path/../Frameworks/ArcCore.framework/Versions/A/ArcCore`, minimum macOS 13.0. Version folder `A`, not the
  Chromium version as in Chrome's own bundle.
- [seen] `strings` finds 7,389 distinct source paths of the form `../../dir/file.cc`: third_party 2,355, chrome 1,407,
  components 1,273, content 713, net 300, ui 211, services 207, media 178, extensions 149, arc 109, base 105, device 76,
  gpu 71, v8 54 and the rest.
- [seen] These are in the binary: `chrome/app/chrome_main_delegate.cc`, `chrome/browser/chrome_browser_main.cc`,
  `chrome/browser/chrome_content_browser_client.cc`, `chrome/browser/profiles/profile_manager.cc`,
  `chrome/browser/ui/browser.cc`, `chrome/browser/ui/tabs/tab_strip_model.cc`,
  `chrome/browser/ui/startup/startup_browser_creator.cc`, `chrome/browser/app_controller_mac.mm`,
  `chrome/browser/ui/extensions/extension_action_view_model.cc`, `chrome/browser/ui/toolbar/toolbar_actions_model.cc`.
- [inferred] So the layer Arc builds on is `chrome/`, the same layer as Google Chrome. It is not `content_shell`, not
  `content/` with an own browser, and not CEF (no `cef_` exports, no `libcef` paths).

### Arc's own code is a folder inside the Chromium tree

- [seen] 109 of those paths start with `arc/`: `arc/browser/browser_application_impl.cc`, `arc/browser/browser_impl.cc`,
  `arc/browser/arc_browser_runner.cc`, `arc/browser/arc_content_browser_client.cc`,
  `arc/browser/extensions/arc_extensions_browser_client.cc`, `arc/browser/browser_context/{browser_context,downloads,effects,extensions,preferences}_impl.cc`,
  `arc/browser/web_contents/{web_contents,navigation_controller,devtools,media_session,pdf_controller,thumbnails_generator}_impl.cc`,
  `arc/renderer/render_frame_agent_impl.cc`, `arc/blink/core/top_band_color_tracker.cc`, and 46 files in `arc/browser/ui/`.
- [seen] The `arc/browser/ui/` files carry the names of Chrome's own UI entry points: `permission_prompt_impl.cc`,
  `sad_tab.cc`, `location_bar.cc`, `extensions_container.cc`, `exclusive_access_context.cc`, `browser_dialogs.cc`,
  `extension_install_prompt.cc`, `javascript_app_modal_dialog_view_impl.cc`, `javascript_tab_modal_dialog_view_impl.cc`,
  `autofill_popup_view.cc`, `chrome_web_contents_view_delegate.cc`, `status_tray.cc`, `window.cc`.
- [inferred] Arc replaces Chrome's Views implementation of those entry points with its own, which report to Swift.

### Chrome's window UI is gone; a custom BrowserWindow takes its place

- [seen] Strings with full signatures, 63 of them under `arc::browser::ui::Window::`: `AsBrowserView`, `CreateFindBar`,
  `GetLocationBar`, `GetWebContentsModalDialogHost`, `PreHandleKeyboardEvent`, `ShowAppMenu`, `UpdateToolbar`,
  `OnActiveTabChanged`, `SetContentsSize`, and so on; example: `virtual BrowserView *arc::browser::ui::Window::AsBrowserView()`.
  Also `arc::browser::ui::LocationBar` (24), `ExclusiveAccessContext` (6), `ExtensionsContainer` (3: `OnPopupShown`,
  `OnPopupClosed`, `CollapseConfirmation`), `NativeWindowObserver` (2).
- [inferred] Those names are the virtual methods of Chrome's `BrowserWindow`. `arc::browser::ui::Window` is a
  `BrowserWindow` subclass and the strings are "not implemented" log lines of the methods that do nothing.
- [seen] These class names have no string in the binary: `ToolbarView`, `ExtensionsToolbarContainer`, `ExtensionPopup`,
  `TabStripRegionView`, `OmniboxViewViews`, `LocationBarView`, `BrowserFrame`, `BrowserNonClientFrameView`. Paths under
  `chrome/browser/ui/views/`: toolbar 0, omnibox 0, download 0, page_info 0, translate 0, infobars 0; frame 7, tabs 3.
- [seen] The Views toolkit itself stays for some dialogs: 106 `ui/views/` paths, and `chrome/browser/ui/views/` still has
  autofill 38, webauthn 31, payments 19, desktop_capture 19, media_router 8. `BridgedContentView`, `NativeWidgetMacNSWindow`,
  `ViewsCompositorSuperview` are ObjC classes in it.
- [inferred] Arc keeps `Browser` and `TabStripModel` (extensions and much of chrome/ need them), gives each `Browser` its
  own window object with no Views behind it, and shows Views only for dialogs it did not bother to replace.

### How the Swift shell talks to it

- [seen] Exports, arm64: 259 symbols. 146 ObjC classes named `Arc*` (class and metaclass), plus `ChromeMain`,
  `ChromeAppModeStart_v8`, `ChromeWebAppShortcutCopierMain`, `CallWithEHFrame`, `SetLogMessageHandler`, `ArcErrorDomain`,
  `arcCategoryEnabledFlag`, `emitTraceEvent`. No C++ symbols. The interface is Objective-C.
- [seen] `MacOS/Arc` links the framework directly (`otool -L`) and imports 63 of those classes by name. `ChromeMain` is not
  among its imports: the helpers use it.
- [seen] Main classes and calls:
  - `ArcBrowserApplicationConfiguration init:argv:profilePath:applicationID:isProduction:sessionRestorationPolicy:…`;
    `ArcBrowserApplication init:`, `initialize:`, `run`, `quit`, `tryToTerminate:`, `createBrowser:withDelegate:forWindow:`,
    `createPopupBrowser:withDelegate:`, `createBrowserContext:isHidden:type:completion:error:`, `getBrowserContext:type:`.
  - `ArcBrowser createWebContents:`, `takeOwnershipOfWebContents:`, `setWindow:`, `executeExtensionAction:`,
    `pinExtension:`, `showExtensionContextMenu:`, `tryToCloseSkipBeforeUnloadHandlers:callback:`, `type`, `context`.
  - `ArcWebContents` (163 methods): `nativeView`, `createPaneHostView`, `attachToPaneHostView:`, `detachFromPaneHostView:`,
    `executeJavascript:completion:`, `find:forward:matchCase:findMatch:completion:`, `captureViewport:`, `print`, `save`,
    `setZoomFactor:`, `discard`, `setNavigationDelegate:`, `setUIDelegate:`, `setActionsDelegate:`.
  - `ArcBrowserContextExtensions listExtensions`, `enableExtension:`, `installExtensionFromUnpackedPath:completion:`,
    `executeExtensionCommand:commandName:`, `getPinnedExtensionOrder`.
  - `ArcExtensionToolbarAction id`, `accessibleName`, `tooltipText`, `icon`, `enabled`, `pinnedPosition`.
- [seen] Callbacks are ObjC selectors bridged from C++ delegates: `&arc::BrowserApplicationDelegate::DidInitializeBrowserProcess`,
  `&arc::BrowserDelegate::DidOpenExtensionPopup`, `browser:didCreateNewWebContents:isActive:`,
  `webContents:didCommitNavigation:`, `webContents:decidePolicyForNavigationAction:`,
  `webContents:didConsumeKey:withModifierFlags:underlyingEventType:`, `webContents:showWebUIDialog:`.
- [seen] On the Swift side, in `MacOS/Arc`: `ADKApplication`, `ADKClient`, `ADKBrowserDelegate`, `ADKClientLive`, and the text
  "Failed to initialize ADKApplication. A common cause is when another instance of the app is running".
- [inferred] Layers: Swift UI, Swift `ADKClient`, ObjC `Arc*`, C++ `arc::`, Chromium. `run` starts Chromium's main and blocks.

### Its NSApplication and its page views

- [seen] `NSPrincipalClass` is `Arc.BrowserApp`, an `NSApplication` subclass written in Swift (`_TtC3Arc10BrowserApp`) that
  conforms to `CrAppProtocol` and `CrAppControlProtocol`. `BrowserCrApplication` is also in ArcCore.
- [seen] `WebContentsHostView : NSView` (`replaceContentWith:`, `addOverlayView:`, `renderWidgetHostView`,
  `onWindowWillEnterFullscreen:`, `setViewObserver:`), `WebContentsPaneHostView : NSView` (`attachWebContentsHostView:`,
  `detachWebContentsHostView`, `syncHostedWebContentsState`), `PaneHostCompositorOverlayView`, and
  `arc/content/public/browser/content_layer_glue_helper.cc`.
- [inferred] A page is an NSView that Swift places directly in its own view tree. There is no hidden Chromium host window
  and no moving of views out of one, which is what Brk does on CEF (`EmbeddedSurface`, `HostWindows`).

### Helpers

- [seen] `Versions/A/Helpers/`: `Browser Helper`, `(GPU)`, `(Renderer)`, `(Alerts)`, and the same four as
  `(Aperitif …)`, about 170 KB each, plus `app_mode_loader`. They link only `libsandbox` and `libSystem`; they load the
  framework and call `ChromeMain`. Entitlements: GPU and Renderer `allow-jit`, plain helper `disable-library-validation`.
- [seen] `Libraries/`: `libvk_swiftshader.dylib`, `libvulkan.dylib`, `libaperitif.dylib` (exports `AperitifCheckInitialized`;
  strings: seatbelt sandbox client, `--seatbelt-client=`), and component data for `MEIPreload`,
  `PrivacySandboxAttestationsPreloaded`, `IwaKeyDistribution`.
- [seen, in Chromium's source] The Aperitif helpers are Chromium's, not Arc's: `chrome/BUILD.gn` builds them (`_is_aperitif_helper`,
  `//content/public/app:aperitif`), behind the feature `kAperitifHelpers`, off by default at 154.
- [seen] `Resources/`: 234 entries, `chrome_100_percent.pak`, `.lproj` folders, bundled DevTools, `ArcCore.sig`, `arc/`.

### How an extension popup opens in Arc

- [seen] `ArcBrowser executeExtensionAction:` asks for it. `chrome/browser/ui/extensions/extension_action_view_model.cc`
  stays. `ExtensionPopup` (Chrome's Views bubble) is not in the binary.
- [seen] The result comes back through `arc::BrowserDelegate::DidOpenExtensionPopup`, `DidResizeExtensionPopup`,
  `DidCloseExtensionPopup`, as `browser:didOpenExtensionPopup:webContents:`, `browser:didResizeExtensionPopup:size:`,
  `browser:didCloseExtensionPopup:`. `arc::browser::ui::ExtensionsContainer::OnPopupShown(const extensions::ExtensionId &, bool)`
  and `OnPopupClosed` stand in for Chrome's toolbar container.
- [seen] Swift side: `ADKClient._browserExtensionPopupWebContents`, `ADKClientLive/BrowserExtensionsPopUpManager.swift`,
  `Arc/BrowserExtensionWindow.swift`, `Arc/BrowserExtensionWindowController.swift`.
- [inferred] Chromium makes the popup's web contents as usual, so `activeTab`, `chrome.tabs` and `currentWindow` behave as in
  Chrome. Instead of Chrome's bubble, the shell gets the web contents and hosts its view in its own window.

### Codecs

- [seen] The CEF 154.0.34 binary Brk ships, asked at run time by `engine/tools/codec-probe.py` (saved in
  `~/brk-chromium/arc-notes/cef154-codecs.json`): decodes VP8, VP9, AV1, MP3, Opus, FLAC. Does not decode H.264, HEVC, AAC, AC-3.
  Widevine is unavailable (`NotSupportedError`).
- Arc's set could not be asked: it needs running Arc. `strings` cannot tell, because Chromium's FFmpeg leaves out its logs.

## Part 2: BrkCore design

### Decision: which route

The user asked for the route closest to Arc, so BrkCore follows Arc's shape:

- It builds on Chromium's `chrome/` layer, in one framework file with helpers inside it.
- Brk's own code is a folder `brk/` in the Chromium tree, carried by a numbered patch series. Chromium's files get as few
  edits as possible, and no edits to widely included headers, so rebasing to a later Chromium stays small and an edit does
  not recompile half the tree.
- Each Brk window has a Chrome `Browser` per profile. That `Browser` has a `BrowserWindow` of Brk's own (`BrkBrowserWindow`)
  with no Views UI. Pages are `WebContents` in that `Browser`'s `TabStripModel`, and the page's NSView sits directly in
  Brk's card. No host windows, no moved views.

Why this and not less: a page in a real `Browser` in a real `TabStripModel` is what extension code expects.
`ExtensionActionViewModel::ExecuteUserAction` reads the active tab from the `Browser`, `ExtensionActionRunner::RunAction`
grants `activeTab` to it, `chrome.tabs.query({active: true, currentWindow: true})` walks `BrowserList` and `TabStripModel`.

The cheaper route, not taken: build CEF itself from source with a popup patch, as cra does (`scripts/cef-patches/`, seven
patches). Almost all of `Sources/BrkCEF` would keep working and M3 would be nearly free. It keeps everything this work wants
to leave: `CefBrowserView` forces `Browser::TYPE_POPUP`, the page stays in a hidden host window with its views moved out,
extensions see each page as a one-tab popup window, and Chromium's internals stay behind CEF's own API and CEF's patches.

One difference from Arc, on purpose for now: Chrome's Views UI code stays linked. Popups a page opens with window features and
DevTools windows can stay real Chrome windows. Chrome's dialogs still appear where they find a usable parent; where they need a
`BrowserView` they do not (see the list at the end). Arc has replaced 46 such entry points; Brk replaces them as they are needed.

### Interface Swift calls

ObjC, as in Arc, but Swift does not link the framework: `main` must build and pass without any Chromium tree. So:

- `Sources/CBrkCore/include/BrkCore.h` is a header-only C module with ObjC **protocols** (`BrkCoreApplication`, `BrkCoreBrowser`,
  `BrkCoreWebContents`, `BrkCoreExtensionAction`, delegates). Protocols need no symbols at link time.
- `BrkCore.framework` exports C entry points found by `dlsym`: `BrkCoreApplicationPrepare` (installs Chromium's NSApplication
  class before anything touches NSApp), `BrkCoreApplicationShared` (returns the object conforming to `BrkCoreApplication`), and
  `ChromeMain` for the helpers.
- The same header is copied into the Chromium tree as `brk/public/BrkCore.h` by `engine/apply-patches.sh`. The repo copy is the
  one to edit.

Calls the first version has, by Arc's model:

| Protocol | Calls |
| --- | --- |
| `BrkCoreApplication` | `runWithArguments:` (blocks in Chromium's main loop), `quit`, `profile…`, `createBrowserForProfile:window:delegate:`, version |
| `BrkCoreBrowser` | `createWebContentsWithURL:delegate:…`, `setActive:`, `setWindow:`, `extensionActions`, `executeExtensionAction:`, close |
| `BrkCoreWebContents` | `nativeView`, `loadURL:`, back/forward/reload/stop, zoom, focus, `executeJavaScript:completion:`, DevTools-protocol call, MHTML, print to PDF, editing commands, mute, close |
| delegates | navigation, title, favicon, progress, load failure, renderer gone, closed, pre-page and post-page key events, new contents, extension popup opened, resized, closed |

### How it maps onto `Sources/BrkEngine`

- A new target `BrkCoreEngine` implements `WebEngine`, the same boundary the app already sees; `BrkApp`'s code does not change.
  Nothing outside the target imports `CBrkCore`.
- `BRK_ENGINE=core` picks it, in the composition root `Sources/Brk/main.swift`. CEF stays the default. It starts Chromium's main
  loop, which runs `[NSApp run]` itself, so `Lifecycle.applicationDidFinishLaunching` arrives after the browser process is up and
  the existing launch order holds.
- `surface(for:)` returns a `PageSurfaceView` holding the `WebContents` NSView directly. There is nothing to give back at close,
  which removes the shutdown step that made CEF crash on quit.
- Engine-neutral helpers (`MainDocumentState`, `DocumentOutputs`, `TransferFiles`, `ReloadSequence`) are used as they are, through
  file links into the new target, so no other agent's work on `BrkCEF` conflicts with a move today.
- `scripts/build.sh` and CEF's download are untouched. A separate `engine/assemble-app.sh` makes `dist-core/Brk.app`.

### How extension popups open

1. Site controls call `WebEngine.invokeExtension(id, target)`.
2. `BrkCoreEngine` makes the page the active tab of its `Browser` (the model reads it there) and calls `executeExtensionAction:`.
3. BrkCore has an `ExtensionActionViewModel` for that extension with a `BrkExtensionActionDelegate` of its own (this interface is
   exactly where Chrome's Views bubble plugs in). `ExecuteUserAction` runs `ExtensionActionRunner::RunAction` with
   `grant_tab_permissions = true`, so `activeTab` is real, then `CreatePopupHost` and `delegate->TriggerPopup(host, …)`.
4. `TriggerPopup` keeps the `ExtensionViewHost`, gives it a `BrkExtensionView` (the `ExtensionView` interface) for size changes and
   keys, and tells Swift `didOpenExtensionPopup` with the host's `WebContents` view.
5. Swift hosts that view in a native panel next to the site controls. Size follows `didResizeExtensionPopup`, limits as in Chrome
   (25x25 to 800x600). Losing key status or `window.close()` closes it, `didCloseExtensionPopup` reports it.

## Part 3: What could not be determined

- Arc's patch count, and how much of `chrome/` it edited. The binary shows results only.
- The exact content of `arc::browser::ui::Window`. The strings cover the methods that log; the ones that do work leave no name.
- Whether Arc makes one `Browser` per window or per Space. `createBrowser:withDelegate:forWindow:` and `ArcBrowser context` fit one per
  window and profile, which is what BrkCore does.
- What `PaneHostCompositorOverlayView` and `content_layer_glue_helper.cc` are for. Brk starts without an equivalent.
- Arc's codec set and whether it ships Widevine: needs running Arc. Not done, as the task forbids driving it.
