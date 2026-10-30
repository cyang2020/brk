/**
 * One BaseWindow and its native view stack. `render(state)` makes the native world match the domain state; it is
 * idempotent and is the only code that adds, removes, orders, sizes or focuses views.
 *
 * Stack, bottom to top (spike sections 1 and 2):
 *   sidebar surface (full window; gradient, sidebar, gutters)             always
 *   tab panes (rounded, inset)                                             0..4
 *   overlay surface as the archive (content card rect, rounded)           while the archive is open
 *   floating-sidebar surface (sidebar-sized, transparent)                  while peeking
 *   overlay surface as the command bar (full window, transparent)         while the command bar is open
 * One overlay surface (one webContents, the overlay bundle) serves both overlays; where it sits depends on which is
 * open: the archive card is content, so a peeked sidebar floats over it; the command bar covers everything. All
 * three surfaces are created with the window and kept for its lifetime, attached only while needed: a surface
 * created on first need would open the command bar only after its bundle had loaded, and keyboard focus given to a
 * webContents before its page exists does not stick.
 *
 * Geometry comes from `win.contentView.getBounds()` and its 'bounds-changed' event, not from the window: on Linux
 * the frame insets arrive after creation and only the root view reports them (phase 3 scaffold).
 */
import { BaseWindow, screen, WebContentsView, type View } from 'electron'
import type { Instant, Platform, Rect, WindowId } from '../shared/base'
import type { SurfaceKind } from '../shared/bridge'
import { DEFAULT_WINDOW_SIZE, LAYOUT } from '../shared/constants'
import type { LayerCapture, NativeLayer, NativeWindowFacts } from '../shared/test-api'
import type { WindowView } from '../shared/view'
import { projectWindow, selectWindow, type AppState, type WindowSelection } from '../domain'
import { CHANNEL, SURFACE_ARG_PREFIX } from '../ipc/channels'
import type { Dispatch, KeyRouter } from './input'
import { computeLayout } from './layout'
import type { TabRuntime } from './tab-runtime'

export interface SurfaceSource {
  /** Absolute path of the built preload. */
  readonly preloadPath: string
  /** URL of a surface's renderer entry (dev server or file://), with `?surface=<kind>`. */
  url(surface: SurfaceKind): string
}

export interface WindowHostDeps {
  readonly tabs: TabRuntime
  readonly keys: KeyRouter
  readonly dispatch: Dispatch
  readonly surfaces: SurfaceSource
  readonly platform: Platform
}

export interface WindowHost {
  readonly windowId: WindowId
  /**
   *   sel = selectWindow(state, id)
   *   layout = computeLayout({ contentSize: sel.contentSize, sidebar: sel.sidebar, fractions: sel.panes.map(p => p.fraction), overlay: sel.overlay })
   *   desired = [sidebar, ...sel.panes.map(p => tabs.viewFor(p.tabId, p.url, id)),
   *              ...(sel.overlay === 'archive' ? [overlay] : []), ...(layout.floatingSidebar ? [floating] : []),
   *              ...(sel.overlay === 'command-bar' ? [overlay] : [])]
   *   if attached order !== desired: remove the extras, put every view at its index
   *   setBounds + setBorderRadius(layout.radius) on panes; setBounds on surfaces; overlay: setBounds(layout.overlay) and
   *     setBorderRadius(sel.overlay === 'archive' ? layout.radius : 0); win.setBackgroundColor(sel.windowColor)
   *   macOS: setWindowButtonVisibility(sel.sidebar.visible || sel.sidebar.peek)
   *   view = projectWindow(state, id, layout, now, platform); push to each surface, coalesced per tick
   *   focus: if key(sel.focus) !== lastFocusKey -> focus that webContents; lastFocusKey = key
   *     ('sidebar' means the floating-sidebar surface while peeking, else the sidebar surface; the overlay key
   *     carries the opening's openId, so every opening is focused, including one that replaces another)
   */
  render(state: AppState, now: Instant): void
  /** Which of this window's surfaces a webContents is, for IPC routing. Tab views are not surfaces. */
  surfaceOf(webContentsId: number): SurfaceKind | null
  /** A surface (re)mounted and asked for the current view. */
  resend(surface: SurfaceKind): void
  window(): BaseWindow
  facts(): NativeWindowFacts
  captureLayers(): Promise<readonly LayerCapture[]>
  /** Where a key press goes: the attached webContents that has focus, else the one `render` last gave focus to. */
  inputTarget(): Electron.WebContents
  /** Detaches tab views (they belong to the tab runtime) and closes the surfaces' webContents (BaseWindow does not). */
  destroy(): void
}

type Role = NativeLayer['role']
const SURFACE_ROLE: Readonly<Record<SurfaceKind, Role>> = { sidebar: 'chrome', 'floating-sidebar': 'floating-sidebar', overlay: 'overlay' }
const SURFACE_KINDS: readonly SurfaceKind[] = ['sidebar', 'floating-sidebar', 'overlay']

const sameRect = (a: Rect, b: Rect): boolean => a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height

const overlaps = (b: Rect, area: Rect): boolean => b.x < area.x + area.width && b.x + b.width > area.x && b.y < area.y + area.height && b.y + b.height > area.y

/**
 * Where to open the window. No saved bounds: the default content size (the OS centers it). Saved bounds that still
 * overlap a display: clamped to that display's work area (a monitor that went away, or a window dragged mostly off
 * screen, cannot restore off screen). Saved bounds that overlap nothing: the default size centered on the nearest
 * display's work area.
 */
function windowPlacement(bounds: Rect | null): { x?: number; y?: number; width: number; height: number; useContentSize?: boolean } {
  if (!bounds) return { width: DEFAULT_WINDOW_SIZE.width, height: DEFAULT_WINDOW_SIZE.height, useContentSize: true }
  const area = screen.getDisplayMatching(bounds).workArea
  const clamp = (value: number, min: number, max: number): number => Math.min(Math.max(value, min), max)
  if (!screen.getAllDisplays().some((d) => overlaps(bounds, d.workArea))) {
    const width = Math.min(DEFAULT_WINDOW_SIZE.width, area.width)
    const height = Math.min(DEFAULT_WINDOW_SIZE.height, area.height)
    return { x: Math.round(area.x + (area.width - width) / 2), y: Math.round(area.y + (area.height - height) / 2), width, height }
  }
  const width = clamp(bounds.width, 480, area.width)
  const height = clamp(bounds.height, 320, area.height)
  return { x: clamp(bounds.x, area.x, area.x + area.width - width), y: clamp(bounds.y, area.y, area.y + area.height - height), width, height }
}

/**
 * capturePage() fails (UnknownVizError) when the view has no compositor frame yet, which is the normal state right
 * after a view was attached or resized. A capture asked for at that moment is legitimate, so wait for the frame:
 * retry at a short interval, bounded.
 */
async function captureWhenPainted(wc: Electron.WebContents): Promise<Electron.NativeImage> {
  const attempts = 60
  const intervalMs = 50
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await wc.capturePage()
    } catch (error) {
      if (attempt >= attempts) throw error
      await new Promise((resolve) => setTimeout(resolve, intervalMs))
    }
  }
}

/**
 * Creates the BaseWindow (bounds from the selection or DEFAULT_WINDOW_SIZE; macOS: titleBarStyle 'hiddenInset',
 * trafficLightPosition LAYOUT.trafficLights; Linux/Windows: frameless) and the surfaces. Wires 'resize', 'move' and
 * the root view's 'bounds-changed' to window/bounds system commands (one is sent at creation), and 'focus' to
 * nothing (focusedWindowId reads BaseWindow focus).
 * Surfaces: sandbox, contextIsolation, preload, additionalArguments [SURFACE_ARG_PREFIX + kind], zoomFactor 1,
 * setBackgroundColor('#00000000'), keys.attach(webContents, { windowId, surface }).
 */
export function createWindowHost(windowId: WindowId, initial: WindowSelection, deps: WindowHostDeps): WindowHost {
  const { tabs, keys, dispatch, surfaces, platform } = deps
  const win = new BaseWindow({
    ...windowPlacement(initial.bounds),
    minWidth: 480,
    minHeight: 320,
    backgroundColor: initial.windowColor,
    ...(platform === 'darwin' ? { titleBarStyle: 'hiddenInset' as const, trafficLightPosition: LAYOUT.trafficLights } : { frame: false }),
  })

  const surfaceViews = new Map<SurfaceKind, WebContentsView>()
  for (const kind of SURFACE_KINDS) {
    const view = new WebContentsView({
      webPreferences: {
        sandbox: true,
        contextIsolation: true,
        preload: surfaces.preloadPath,
        additionalArguments: [SURFACE_ARG_PREFIX + kind],
        zoomFactor: 1,
      },
    })
    view.setBackgroundColor('#00000000')
    view.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
    keys.attach(view.webContents, { windowId, surface: kind })
    void view.webContents.loadURL(surfaces.url(kind)).catch((error: unknown) => console.error(`[arc] ${kind} surface failed to load: ${String(error)}`))
    surfaceViews.set(kind, view)
  }
  const surface = (kind: SurfaceKind): WebContentsView => surfaceViews.get(kind)!

  /** Role and tab of every view `render` last placed, for facts(). */
  let placed = new Map<View, { readonly role: Role; readonly tabId: NativeLayer['tabId'] }>()
  const radii = new Map<View, number>()
  let lastFocusKey: string | null = null
  let lastFocused: Electron.WebContents = surface('sidebar').webContents
  let lastWindowColor = initial.windowColor
  let lastButtonsVisible: boolean | null = null
  let lastView: WindowView | null = null
  let pushScheduled = false
  let gone = false

  const contentSize = (): { width: number; height: number } => {
    const { width, height } = win.contentView.getBounds()
    return { width, height }
  }
  const reportBounds = (): void => {
    if (gone || win.isDestroyed()) return
    const { x, y, width, height } = win.getBounds()
    dispatch({ origin: 'system', command: { type: 'window/bounds', windowId, bounds: { x, y, width, height }, contentSize: contentSize() } })
  }
  win.on('resize', reportBounds)
  win.on('move', reportBounds)
  win.contentView.on('bounds-changed', reportBounds)
  win.on('closed', () => {
    gone = true
  })
  reportBounds()

  const setBounds = (view: View, rect: Rect): void => {
    if (!sameRect(view.getBounds(), rect)) view.setBounds(rect)
  }
  const setRadius = (view: View, radius: number): void => {
    if (radii.get(view) === radius) return
    view.setBorderRadius(radius)
    radii.set(view, radius)
  }

  /** Makes the root view's children equal `desired`, in order, touching only views that are out of place. */
  const reconcile = (desired: readonly View[]): void => {
    const root = win.contentView
    const current = root.children
    if (current.length === desired.length && current.every((view, i) => view === desired[i])) return
    for (const view of current) if (!desired.includes(view)) root.removeChildView(view)
    desired.forEach((view, i) => {
      if (root.children[i] === view) return
      if (root.children.includes(view)) root.removeChildView(view)
      root.addChildView(view, i)
    })
  }

  const push = (): void => {
    if (pushScheduled) return
    pushScheduled = true
    setImmediate(() => {
      pushScheduled = false
      if (lastView === null || gone) return
      for (const view of surfaceViews.values()) if (!view.webContents.isDestroyed()) view.webContents.send(CHANNEL.view, lastView)
    })
  }

  const applyFocus = (key: string, wc: Electron.WebContents): void => {
    lastFocused = wc
    if (key === lastFocusKey) return
    lastFocusKey = key
    wc.focus()
  }

  const attachedLayers = (): NativeLayer[] =>
    win.contentView.children.flatMap((view): NativeLayer[] => {
      const info = placed.get(view)
      if (!info || !(view instanceof WebContentsView)) return []
      return [{ role: info.role, webContentsId: view.webContents.id, tabId: info.tabId, bounds: view.getBounds(), radius: radii.get(view) ?? 0 }]
    })

  return {
    windowId,
    render(state, now): void {
      if (gone || win.isDestroyed()) return
      const sel = selectWindow(state, windowId)
      const layout = computeLayout({ contentSize: sel.contentSize, sidebar: sel.sidebar, fractions: sel.panes.map((p) => p.fraction), overlay: sel.overlay })
      const sidebar = surface('sidebar')
      const overlay = surface('overlay')
      const floating = surface('floating-sidebar')
      const panes = sel.panes.map((p) => tabs.viewFor(p.tabId, p.url, windowId))
      const desired: View[] = [
        sidebar,
        ...panes,
        ...(sel.overlay === 'archive' ? [overlay] : []),
        ...(layout.floatingSidebar ? [floating] : []),
        ...(sel.overlay === 'command-bar' ? [overlay] : []),
      ]
      reconcile(desired)

      setBounds(sidebar, layout.chrome)
      setRadius(sidebar, 0)
      panes.forEach((view, i) => {
        setBounds(view, layout.panes[i]!)
        setRadius(view, layout.radius)
      })
      if (layout.floatingSidebar) {
        setBounds(floating, layout.floatingSidebar)
        setRadius(floating, 0)
      }
      if (layout.overlay) {
        setBounds(overlay, layout.overlay)
        setRadius(overlay, sel.overlay === 'archive' ? layout.radius : 0)
      }
      if (sel.windowColor !== lastWindowColor) {
        lastWindowColor = sel.windowColor
        win.setBackgroundColor(sel.windowColor)
      }
      if (platform === 'darwin') {
        const visible = sel.sidebar.visible || sel.sidebar.peek
        if (visible !== lastButtonsVisible) {
          lastButtonsVisible = visible
          win.setWindowButtonVisibility(visible)
        }
      }

      const next = new Map<View, { role: Role; tabId: NativeLayer['tabId'] }>()
      next.set(sidebar, { role: 'chrome', tabId: null })
      sel.panes.forEach((p, i) => next.set(panes[i]!, { role: 'pane', tabId: p.tabId }))
      next.set(overlay, { role: 'overlay', tabId: null })
      next.set(floating, { role: 'floating-sidebar', tabId: null })
      placed = next

      lastView = projectWindow(state, windowId, layout, now, platform)
      push()

      const focus = sel.focus
      if (focus.kind === 'pane') {
        const index = sel.panes.findIndex((p) => p.tabId === focus.tabId)
        const view = panes[index]
        if (view) applyFocus(`pane:${focus.tabId}`, view.webContents)
      } else if (focus.surface === 'overlay') {
        applyFocus(`overlay:${lastView.overlay?.openId ?? 0}`, overlay.webContents)
      } else if (layout.floatingSidebar) {
        applyFocus('surface:floating-sidebar', floating.webContents)
      } else {
        applyFocus('surface:sidebar', sidebar.webContents)
      }
    },
    surfaceOf(webContentsId): SurfaceKind | null {
      for (const [kind, view] of surfaceViews) if (view.webContents.id === webContentsId) return kind
      return null
    },
    resend(kind): void {
      const view = surfaceViews.get(kind)
      if (!view || view.webContents.isDestroyed() || lastView === null) return
      view.webContents.send(CHANNEL.view, lastView)
      // The page just mounted; if it is the focus target, the focus given before it existed did not stick.
      if (lastFocused === view.webContents) view.webContents.focus()
    },
    window(): BaseWindow {
      return win
    },
    facts(): NativeWindowFacts {
      const layers = attachedLayers()
      const focused = win.contentView.children.find((view) => view instanceof WebContentsView && view.webContents.isFocused()) as WebContentsView | undefined
      return {
        windowId,
        contentSize: contentSize(),
        layers,
        backgroundColor: win.getBackgroundColor(),
        focusedWebContentsId: focused?.webContents.id ?? null,
      }
    },
    async captureLayers(): Promise<readonly LayerCapture[]> {
      const out: LayerCapture[] = []
      for (const layer of attachedLayers()) {
        const view = win.contentView.children.find((v) => v instanceof WebContentsView && v.webContents.id === layer.webContentsId) as WebContentsView | undefined
        if (!view) continue
        const image = await captureWhenPainted(view.webContents)
        const size = image.getSize()
        out.push({ layer, pngBase64: image.toPNG().toString('base64'), scale: layer.bounds.width > 0 ? size.width / layer.bounds.width : 1 })
      }
      return out
    },
    inputTarget(): Electron.WebContents {
      const focused = win.contentView.children.find((view) => view instanceof WebContentsView && view.webContents.isFocused()) as WebContentsView | undefined
      return focused?.webContents ?? lastFocused
    },
    destroy(): void {
      gone = true
      const ours = new Set<View>(surfaceViews.values())
      if (!win.isDestroyed()) for (const view of [...win.contentView.children]) if (!ours.has(view)) win.contentView.removeChildView(view)
      for (const view of surfaceViews.values()) if (!view.webContents.isDestroyed()) view.webContents.close()
      if (!win.isDestroyed()) win.destroy()
    },
  }
}
