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

/// The connection of the page's visible navigation entry, the input of Chrome's own security indicator (content's SSLStatus).
typedef struct {
  /// The entry has a valid address; false: nothing to say yet.
  bool known;
  /// The document came over TLS (the entry has a certificate).
  bool secureConnection;
  /// A certificate error Chromium holds against the page (net::IsCertStatusError), and it was loaded anyway.
  bool certificateError;
  /// The page displayed or ran plain HTTP content, or content with a certificate error.
  bool insecureContent;
  /// A form on the page submits to a plain HTTP address.
  bool insecureForm;
  /// net's CertStatus bits.
  uint32_t certStatus;
  /// content's SSLStatus::ContentStatusFlags bits.
  uint32_t contentStatus;
} BrkCoreSecurity;

/// One download a page started, as Chromium's DownloadItem reports it now. Kept by the framework until Chromium drops the item.
NS_SWIFT_UI_ACTOR
@protocol BrkCoreDownload <NSObject>
/// Chromium's id, stable across updates.
@property(nonatomic, readonly) uint32_t downloadID;
@property(nonatomic, readonly, nullable) NSURL* url;
/// The file name Chromium would give it (Content-Disposition, the address, the MIME type), without a folder.
@property(nonatomic, readonly, copy) NSString* suggestedName;
@property(nonatomic, readonly) int64_t receivedBytes;
/// 0 when the server did not say.
@property(nonatomic, readonly) int64_t totalBytes;
@property(nonatomic, readonly) BOOL isComplete;
@property(nonatomic, readonly) BOOL isCanceled;
@property(nonatomic, readonly) BOOL isInterrupted;
/// download::DownloadInterruptReason, 0 for none.
@property(nonatomic, readonly) NSInteger interruptionReason;
/// Where Chromium writes it, once it has a destination.
@property(nonatomic, readonly, nullable) NSString* fullPath;
/// Answers -webContents:willDownload:. Chromium writes the file at exactly `path` and renames nothing; nil cancels. Only the first answer counts.
- (void)continueToPath:(nullable NSString*)path;
- (void)cancel;
@end

/// What a site asks for. One request can ask for several (camera and microphone).
typedef NS_OPTIONS(uint32_t, BrkCorePermissionKind) {
  BrkCorePermissionKindCamera = 1 << 0,
  BrkCorePermissionKindMicrophone = 1 << 1,
  BrkCorePermissionKindGeolocation = 1 << 2,
  BrkCorePermissionKindNotifications = 1 << 3,
  BrkCorePermissionKindClipboard = 1 << 4,
  BrkCorePermissionKindMidi = 1 << 5,
  BrkCorePermissionKindWindowManagement = 1 << 6,
  BrkCorePermissionKindStorageAccess = 1 << 7,
  BrkCorePermissionKindSensors = 1 << 8,
  /// "This site wants to download multiple files" (Chrome's DownloadRequestLimiter).
  BrkCorePermissionKindMultipleDownloads = 1 << 9,
  BrkCorePermissionKindPointerLock = 1 << 10,
  /// Anything else Chromium asks about (local fonts, idle detection, protocol handlers…).
  BrkCorePermissionKindOther = 1u << 31,
};

typedef NS_ENUM(NSInteger, BrkCorePermissionAnswer) {
  /// Chromium remembers the allow for the origin.
  BrkCorePermissionAnswerAllow = 0,
  /// Chromium remembers the block.
  BrkCorePermissionAnswerDeny = 1,
  /// Closed without a choice; the site may ask again.
  BrkCorePermissionAnswerDismiss = 2,
};

/// A permission prompt Chromium's PermissionRequestManager wants shown for a page (Chrome shows its bubble here).
NS_SWIFT_UI_ACTOR
@protocol BrkCorePermissionRequest <NSObject>
/// Unique in the process.
@property(nonatomic, readonly) uint64_t promptID;
@property(nonatomic, readonly) BrkCorePermissionKind kinds;
/// The origins as URLs ("https://site.test/").
@property(nonatomic, readonly, copy) NSString* requestingOrigin;
@property(nonatomic, readonly, copy) NSString* embeddingOrigin;
/// Only the first answer counts, and none after Chromium took the request back.
- (void)answer:(BrkCorePermissionAnswer)answer;
@end

typedef NS_ENUM(NSInteger, BrkCoreDialogKind) {
  BrkCoreDialogKindAlert = 0,
  BrkCoreDialogKindConfirm = 1,
  BrkCoreDialogKindPrompt = 2,
  /// beforeunload: leave or stay.
  BrkCoreDialogKindBeforeUnload = 3,
};

/// A JavaScript dialog a page opened: alert, confirm, prompt, or the leave-page question.
NS_SWIFT_UI_ACTOR
@protocol BrkCoreDialog <NSObject>
@property(nonatomic, readonly) BrkCoreDialogKind kind;
@property(nonatomic, readonly, copy) NSString* message;
@property(nonatomic, readonly, copy) NSString* defaultPromptText;
/// The frame's origin as Chrome titles the dialog ("site.test says").
@property(nonatomic, readonly, copy) NSString* originTitle;
/// For BrkCoreDialogKindBeforeUnload: the page is being reloaded, not left.
@property(nonatomic, readonly) BOOL isReload;
/// OK / Leave (YES) or Cancel / Stay (NO). Only the first answer counts.
- (void)answer:(BOOL)accepted text:(nullable NSString*)text;
@end

typedef NS_ENUM(NSInteger, BrkCoreSaveKind) {
  BrkCoreSaveKindPassword = 0,
  BrkCoreSaveKindAddress = 1,
  BrkCoreSaveKindCard = 2,
};

typedef NS_ENUM(NSInteger, BrkCoreSaveAnswer) {
  BrkCoreSaveAnswerSave = 0,
  BrkCoreSaveAnswerNotNow = 1,
  /// Never for this site (passwords only; the others take it as Not now).
  BrkCoreSaveAnswerNever = 2,
};

/// Chromium offers to keep what a page's form just sent: the login (ManagePasswordsUIController), the address or the card
/// (autofill). Chrome would show its bubble; Brk asks with its own card and answers here.
NS_SWIFT_UI_ACTOR
@protocol BrkCoreSaveOffer <NSObject>
@property(nonatomic, readonly) BrkCoreSaveKind kind;
/// The page's host; nil when it has none.
@property(nonatomic, readonly, copy, nullable) NSString* site;
/// Only the first answer counts; an offer Chromium withdrew (the page navigated) ignores it.
- (void)answer:(BrkCoreSaveAnswer)answer;
@end

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
@optional
/// A download of this page needs a destination (CEF's OnBeforeDownload). Answer with -continueToPath:, now or later.
- (void)webContents:(id<BrkCoreWebContents>)contents willDownload:(id<BrkCoreDownload>)download;
/// It changed: progress, completion, cancellation, interruption (CEF's OnDownloadUpdated).
- (void)webContents:(id<BrkCoreWebContents>)contents downloadDidUpdate:(id<BrkCoreDownload>)download;
/// A site asks for a permission (CEF's OnShowPermissionPrompt). Unanswered, it stays open until Chromium takes it back.
- (void)webContents:(id<BrkCoreWebContents>)contents requestsPermission:(id<BrkCorePermissionRequest>)request;
/// Chromium took the request back: navigation, the page closed, the request was answered another way.
- (void)webContents:(id<BrkCoreWebContents>)contents didDismissPermission:(uint64_t)promptID;
/// The visible entry's connection changed (a new document, insecure content, a certificate decision). Read -security.
- (void)webContentsDidChangeSecurity:(id<BrkCoreWebContents>)contents;
/// The page opened a JavaScript dialog. NO: the shell shows none, and the page sees it dismissed.
- (BOOL)webContents:(id<BrkCoreWebContents>)contents runDialog:(id<BrkCoreDialog>)dialog;
/// Chromium offers to save a login, an address or a card from this page (see BrkCoreSaveOffer).
- (void)webContents:(id<BrkCoreWebContents>)contents offersToSave:(id<BrkCoreSaveOffer>)offer;
/// The open dialogs of this page are gone (navigation, close); answers to them are ignored.
- (void)webContentsCancelDialogs:(id<BrkCoreWebContents>)contents;
/// The page started or stopped making sound (Chromium's audible state, what Chrome's tab speaker shows).
- (void)webContents:(id<BrkCoreWebContents>)contents didChangeAudible:(BOOL)audible;
/// The page's audio and video elements, its frames' included, changed. A JSON array of objects with `frame` (0: the main frame), `document`,
/// `element`, `kind` ("audio", "video"), `paused`, `ended`, `silent` (the element is muted) and `pictureInPicture`.
- (void)webContents:(id<BrkCoreWebContents>)contents didChangeMediaPlayers:(NSString*)json;
/// Chrome's context menu for the page: its rows (dictionaries with `title`, `command`, `enabled`, `checked`, `children`, or `separator`) and
/// what was clicked (`x`, `y` in the page's view, top-left origin; `linkURL`; `editable`; `mediaType` "none", "image", "video", "audio",
/// "other"; `selection`). Show it now and answer the chosen row's `command`, or -1. Chrome runs the command.
- (NSInteger)webContents:(id<BrkCoreWebContents>)contents
          runContextMenu:(NSArray<NSDictionary<NSString*, id>*>*)items
                    info:(NSDictionary<NSString*, id>*)info;
@end

NS_SWIFT_UI_ACTOR
@protocol BrkCoreWebContents <NSObject>
@property(nonatomic, weak, nullable) id<BrkCoreWebContentsDelegate> delegate;
/// The view that shows the page; the caller places it. The same object for the page's life.
@property(nonatomic, readonly) NSView* nativeView;
/// Chromium's input view inside nativeView; nil until the renderer's widget exists.
@property(nonatomic, readonly, nullable) NSView* inputView;
@property(nonatomic, readonly, nullable) NSURL* visibleURL;
/// The main frame's committed document address (CEF's main frame URL); nil before the first commit.
@property(nonatomic, readonly, nullable) NSURL* committedURL;
@property(nonatomic, readonly) BOOL isLoading;
@property(nonatomic, readonly) BOOL canGoBack;
@property(nonatomic, readonly) BOOL canGoForward;
@property(nonatomic) double zoomLevel;
@property(nonatomic) BOOL audioMuted;
/// Chromium's audible state now.
@property(nonatomic, readonly) BOOL isAudible;
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
/// The visible entry's connection now.
@property(nonatomic, readonly) BrkCoreSecurity security;
/// Plays, pauses ("play", "pause"), sets the volume of ("setVolume", 0 to 1) or moves into or out of picture in picture
/// ("enterPictureInPicture", "exitPictureInPicture") one element -webContents:didChangeMediaPlayers: named. NO when its frame is gone.
- (BOOL)controlMediaPlayerInFrame:(int)frame
                          element:(NSString*)element
                        operation:(NSString*)operation
                           volume:(double)volume;
/// Writes a remembered choice into the profile's content settings for `requesting` embedded in `topLevel`: an allow (YES), a block
/// (NO), or back to asking (nil).
- (void)setPermission:(BrkCorePermissionKind)kinds
     requestingOrigin:(NSURL*)requesting
       topLevelOrigin:(NSURL*)topLevel
              allowed:(nullable NSNumber*)allowed;
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
/// Deletes every cookie of the profile (its network context's cookie manager). Calls back with how many went.
- (void)clearCookiesWithCompletion:(void (^)(NSUInteger deleted))completion;
/// Empties the profile's HTTP cache. Calls back when done.
- (void)clearCacheWithCompletion:(void (^)(void))completion;
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
