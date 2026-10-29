/**
 * Contract between the main process and Playwright. Main installs an `ArcTestApi` on `globalThis[TEST_API_GLOBAL]`
 * only when `process.env[TEST_ENV.enable] === '1'`; e2e reaches it through `electronApp.evaluate`. Every value is
 * plain data (it crosses the Playwright evaluate boundary).
 */
import type { Instant, ItemId, Rect, Size, WindowId } from './base'
import type { UiCommand } from './commands'
import type { WindowView } from './view'

export const TEST_API_GLOBAL = '__arc'

export const TEST_ENV = {
  /** "1" installs the test API and the offset test clock. */
  enable: 'ARC_E2E',
  /** Overrides app.getPath('userData') before ready, so each test gets a fresh profile and a restart reuses it. */
  userData: 'ARC_USER_DATA',
  /** URL of the single tab a fresh profile starts with (e2e points it at the local test server). */
  startUrl: 'ARC_START_URL',
} as const

/**
 * One attached native view, bottom to top. `overlay` is the full window while the command bar is open and exactly
 * the content card (with the card's radius) while the archive is open (src/main/layout.ts).
 */
export interface NativeLayer {
  readonly role: 'chrome' | 'pane' | 'floating-sidebar' | 'overlay'
  readonly webContentsId: number
  readonly tabId: ItemId | null
  readonly bounds: Rect
  /** The radius last passed to setBorderRadius (Electron has no getter). */
  readonly radius: number
}

export interface NativeWindowFacts {
  readonly windowId: WindowId
  readonly contentSize: Size
  readonly layers: readonly NativeLayer[]
  readonly backgroundColor: string
  readonly focusedWebContentsId: number | null
}

/** One layer's capturePage() as PNG. The fixture composites them with rounded clips (spike section 6). */
export interface LayerCapture {
  readonly layer: NativeLayer
  readonly pngBase64: string
  /** Device pixels per window point for this capture. */
  readonly scale: number
}

export interface ArcTestApi {
  windowIds(): readonly WindowId[]
  /** Exactly what the window's renderers last received (or would receive now). Defaults to the first window. */
  view(windowId?: WindowId): WindowView
  native(windowId?: WindowId): NativeWindowFacts
  /** Same path as a renderer dispatch (parsed with UiCommandSchema). */
  dispatch(command: UiCommand, windowId?: WindowId): void
  /**
   * Press an accelerator ("CmdOrCtrl+T") into the window's focused webContents with sendInputEvent. Playwright's
   * page.keyboard reaches the page but fires neither menu accelerators nor before-input-event (spike section 5).
   */
  press(accelerator: string, windowId?: WindowId): void
  /** Moves the test clock forward and runs the auto-archive sweep. */
  advanceClock(ms: number): Instant
  tabWebContentsId(tabId: ItemId): number | null
  /** webContents ids of tab views whose 'destroyed' event has fired, in order. */
  destroyedWebContentsIds(): readonly number[]
  captureLayers(windowId?: WindowId): Promise<readonly LayerCapture[]>
  /** Writes state.json now and resolves when it is on disk. */
  flush(): Promise<void>
  userDataPath(): string
}

declare global {
  /**
   * `globalThis[TEST_API_GLOBAL]`. Present in the main process only while TEST_ENV.enable is "1" (installed by
   * src/main/test-api.ts); e2e/fixtures.ts reads it inside `electronApp.evaluate` callbacks.
   */
  // eslint-disable-next-line no-var
  var __arc: ArcTestApi | undefined
}
