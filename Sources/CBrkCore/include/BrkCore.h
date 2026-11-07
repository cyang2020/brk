// The interface between Brk's Swift code and BrkCore.framework (Brk's own Chromium build).
//
// This file is the one copy to edit. engine/sync-header.sh copies it into the Chromium tree as brk/public/BrkCore.h.
//
// Everything is a protocol, and the framework is found at run time with dlopen and dlsym, so Swift compiles and links without
// the framework or any Chromium tree: main keeps building with CEF as the default engine. Every call and every delegate
// callback runs on the main thread. Docs and reasons: docs/chromium/ARC-ENGINE.md.

#ifndef BRK_PUBLIC_BRKCORE_H_
#define BRK_PUBLIC_BRKCORE_H_

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// One key event as Chromium's browser process sees it, before or after the page.
typedef struct {
  /// The macOS virtual key code.
  int32_t nativeKeyCode;
  /// NSEventModifierFlags of the event.
  uint64_t modifierFlags;
  /// Key down (raw key down), not key up. Character events are never delivered.
  bool isDown;
  bool isRepeat;
  /// The page's focused element takes text.
  bool editableFocused;
  /// The NSEvent's timestamp; 0 when the event was not made from one.
  double timestamp;
} BrkCoreKeyPress;

/// What the shell did with a key.
typedef struct {
  bool handled;
  /// Not handled, but the key is bound to a shortcut: the page sees it, and Chromium treats it as one.
  bool shortcut;
} BrkCoreKeyAnswer;

typedef NS_ENUM(NSInteger, BrkCoreDisposition) {
  BrkCoreDispositionCurrentTab = 0,
  BrkCoreDispositionForegroundTab = 1,
  BrkCoreDispositionBackgroundTab = 2,
  BrkCoreDispositionPopup = 3,
  BrkCoreDispositionNewWindow = 4,
  BrkCoreDispositionOther = 5,
};

@protocol BrkCoreWebContents;
@protocol BrkCoreBrowser;
@protocol BrkCoreExtension;

NS_SWIFT_UI_ACTOR
@protocol BrkCoreWebContentsDelegate <NSObject>
/// A main-frame navigation is about to start or redirect. NO cancels it.
- (BOOL)webContents:(id<BrkCoreWebContents>)contents
    decideNavigationTo:(NSURL*)url
            isRedirect:(BOOL)isRedirect
           userGesture:(BOOL)userGesture;
- (void)webContents:(id<BrkCoreWebContents>)contents didChangeAddress:(nullable NSURL*)url;
/// A new main document committed (CEF's OnLoadStart).
- (void)webContents:(id<BrkCoreWebContents>)contents didStartDocument:(nullable NSURL*)url;
/// The committed main document finished loading (CEF's OnLoadEnd).
- (void)webContents:(id<BrkCoreWebContents>)contents didFinishDocument:(nullable NSURL*)url;
- (void)webContents:(id<BrkCoreWebContents>)contents
    didChangeLoading:(BOOL)isLoading
           canGoBack:(BOOL)canGoBack
        canGoForward:(BOOL)canGoForward;
- (void)webContents:(id<BrkCoreWebContents>)contents didChangeProgress:(double)progress;
- (void)webContents:(id<BrkCoreWebContents>)contents
      didFailLoadCode:(NSInteger)code
          description:(NSString*)description
                  url:(NSString*)url;
- (void)webContents:(id<BrkCoreWebContents>)contents didChangeTitle:(NSString*)title;
- (void)webContents:(id<BrkCoreWebContents>)contents didChangeFavicon:(nullable NSURL*)url;
/// The URL under the pointer (nil: none), which Chrome shows in its status bubble.
- (void)webContents:(id<BrkCoreWebContents>)contents didHoverLink:(nullable NSURL*)url;
- (void)webContentsRendererGone:(id<BrkCoreWebContents>)contents;
- (void)webContentsDidGainFocus:(id<BrkCoreWebContents>)contents;
- (void)webContents:(id<BrkCoreWebContents>)contents didChangeZoomLevel:(double)level;
/// The page called window.close(). The contents is about to go; -webContentsDidClose: follows.
- (void)webContentsClosedByPage:(id<BrkCoreWebContents>)contents;
/// The contents is gone. No other callback follows for it.
- (void)webContentsDidClose:(id<BrkCoreWebContents>)contents;
- (BrkCoreKeyAnswer)webContents:(id<BrkCoreWebContents>)contents keyBeforePage:(BrkCoreKeyPress)key;
- (BOOL)webContents:(id<BrkCoreWebContents>)contents keyAfterPage:(BrkCoreKeyPress)key;
/// The page or Chromium asks for a new page: target=_blank, window.open without features, a modified click.
- (void)webContents:(id<BrkCoreWebContents>)contents
      requestsOpening:(NSURL*)url
          disposition:(BrkCoreDisposition)disposition
          userGesture:(BOOL)userGesture;
@end

NS_SWIFT_UI_ACTOR
@protocol BrkCoreWebContents <NSObject>
@property(nonatomic, weak, nullable) id<BrkCoreWebContentsDelegate> delegate;
/// The view that shows the page; the caller places it. The same object for the page's life.
@property(nonatomic, readonly) NSView* nativeView;
/// Chromium's input view inside nativeView; nil until the renderer's widget exists.
@property(nonatomic, readonly, nullable) NSView* inputView;
@property(nonatomic, readonly, nullable) NSURL* visibleURL;
@property(nonatomic, readonly) BOOL isLoading;
@property(nonatomic, readonly) BOOL canGoBack;
@property(nonatomic, readonly) BOOL canGoForward;
@property(nonatomic) double zoomLevel;
@property(nonatomic) BOOL audioMuted;
/// SessionTabHelper's id, what chrome.tabs reports.
@property(nonatomic, readonly) int tabID;
- (void)loadURL:(NSURL*)url;
- (void)goBack;
- (void)goForward;
- (void)reloadBypassingCache:(BOOL)bypassCache;
- (void)stopLoading;
- (void)setPageFocused:(BOOL)focused;
- (void)setHidden:(BOOL)hidden;
- (void)evaluateJavaScript:(NSString*)script
                completion:(nullable void (^)(NSString* _Nullable json, NSString* _Nullable error))completion;
/// One DevTools protocol command on this page. `parameters` and the result are JSON objects as text.
- (void)sendDevToolsCommand:(NSString*)method
                 parameters:(NSString*)parameters
                 completion:(void (^)(NSString* _Nullable result, NSString* _Nullable error))completion;
- (void)cutSelection;
- (void)copySelection;
- (void)pasteClipboard;
- (void)pasteAndMatchStyle;
- (void)selectAllContent;
- (void)deleteSelection;
- (void)undoEdit;
- (void)redoEdit;
/// Closes it now, without unload handlers. -webContentsDidClose: follows, possibly before this returns.
- (void)close;
@end

/// What a popup opened by -executeExtensionAction: reports.
NS_SWIFT_UI_ACTOR
@protocol BrkCoreBrowserDelegate <NSObject>
/// An extension's action popup opened. The shell places `view`, sized by the next call, and reports focus loss with
/// -closeExtensionPopup.
- (void)browser:(id<BrkCoreBrowser>)browser
    didOpenExtensionPopup:(NSString*)extensionID
                     view:(NSView*)view;
- (void)browser:(id<BrkCoreBrowser>)browser
    didResizeExtensionPopup:(NSString*)extensionID
                       size:(NSSize)size;
- (void)browser:(id<BrkCoreBrowser>)browser didCloseExtensionPopup:(NSString*)extensionID;
@end

/// A Chrome `Browser` with Brk's own window object: one per Brk window and profile.
NS_SWIFT_UI_ACTOR
@protocol BrkCoreBrowser <NSObject>
@property(nonatomic, weak, nullable) id<BrkCoreBrowserDelegate> delegate;
/// The native window pages of this browser show in. Chrome's window questions are answered from it.
@property(nonatomic, weak, nullable) NSWindow* window;
/// False once Chrome's Browser is gone: Chrome closes one when its last page closes. Make a new one for the next page.
@property(nonatomic, readonly) BOOL isAlive;
/// Makes an empty page in this browser. Set its delegate, then load.
- (id<BrkCoreWebContents>)createWebContents;
/// The page Chromium made by itself for this address (a link with target=_blank), which the shell was told about with
/// -webContents:requestsOpening:disposition:userGesture:. nil when there is none.
- (nullable id<BrkCoreWebContents>)adoptWebContentsWithURL:(NSURL*)url;
/// Makes the page the browser's active tab. What extensions see as the active tab of this window.
- (void)activateWebContents:(id<BrkCoreWebContents>)contents;
/// As a click on the extension's toolbar button, on the active tab. Grants activeTab. nil, or why not.
- (nullable NSString*)executeExtensionAction:(NSString*)extensionID;
- (void)closeExtensionPopup;
/// Gives the popup keyboard focus, once its view is in a key window.
- (void)focusExtensionPopup;
- (void)close;
@end

/// An extension installed in a profile. Component extensions are left out.
NS_SWIFT_UI_ACTOR
@protocol BrkCoreExtension <NSObject>
@property(nonatomic, readonly, copy) NSString* extensionID;
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSString* version;
@property(nonatomic, readonly) BOOL enabled;
/// It has a toolbar action (-executeExtensionAction: can run it).
@property(nonatomic, readonly) BOOL hasAction;
/// Its icon file as it is in the extension, nil when it declares none.
@property(nonatomic, readonly, nullable) NSData* iconData;
@end

/// A Chrome profile. The default one, a named one, or its incognito profile.
NS_SWIFT_UI_ACTOR
@protocol BrkCoreProfile <NSObject>
@property(nonatomic, readonly, copy) NSString* path;
@property(nonatomic, readonly) BOOL isOffTheRecord;
- (id<BrkCoreBrowser>)createBrowserForWindow:(nullable NSWindow*)window
                                    delegate:(nullable id<BrkCoreBrowserDelegate>)delegate;
- (id<BrkCoreProfile>)incognitoProfile;
/// Calls back once Chromium's extension system is ready for this profile.
- (void)whenExtensionsReady:(void (^)(void))completion;
- (NSArray<id<BrkCoreExtension>>*)installedExtensions;
/// Installs an unpacked extension, as "Load unpacked". Calls back with nil, or why not.
- (void)installUnpackedExtensionAtPath:(NSString*)path
                            completion:(void (^)(NSString* _Nullable extensionID, NSString* _Nullable error))completion;
@end

NS_SWIFT_UI_ACTOR
@protocol BrkCoreApplication <NSObject>
/// Chromium's version, 154.0.8037.98.
@property(nonatomic, readonly, copy) NSString* version;
/// Runs Chromium's main with the arguments given to BrkCoreApplicationPrepare. Blocks in Chromium's run loop, which runs -[NSApp run],
/// until Chromium has shut down. Answers its exit code.
- (int)run;
/// The profile named `directory` under the user data folder, loading it if needed; nil when it could not be.
- (void)loadProfile:(NSString*)directory completion:(void (^)(id<BrkCoreProfile> _Nullable profile))completion;
/// Starts Chromium's own shutdown; -runWithArguments: returns when it is done. Close every page first.
- (void)quit;
@end

#ifdef __cplusplus
extern "C" {
#endif

/// C entry points, found with dlsym. Takes Chromium's command line (the first argument is the program) and installs Chromium's
/// NSApplication class. Call once, before anything touches NSApp.
__attribute__((visibility("default"))) void BrkCoreApplicationPrepare(int argc, const char* _Nonnull const* _Nonnull argv);
/// The one application object, conforming to BrkCoreApplication. It is never released.
__attribute__((visibility("default"))) void* BrkCoreApplicationShared(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

#endif  // BRK_PUBLIC_BRKCORE_H_
