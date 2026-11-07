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
  `PrivacySandboxAttestationsPreloaded`, `IwaKeyDistribution`. `kAperitifHelpers` is a string in ArcCore.
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
