/**
 * The command vocabulary.
 *
 * Every user intent, from every source (menu, shortcut, sidebar click, command bar, native popup menu, e2e test
 * API), is one `UiCommand`. Every main-process observation (page events, clock ticks, window geometry) is one
 * `SystemCommand`. The domain reducer (src/domain/reduce.ts) is the only interpreter of both, so there is one way
 * to do each thing no matter where the input came from.
 *
 * `UiCommandSchema` is the single source: the `UiCommand` type is derived from it, and main parses every renderer
 * message with it before anything else looks at it (renderers are untrusted, per boundary-discipline). Adding a
 * command means one schema entry here plus one handler in src/domain/ops/*; the `Handlers` mapped type in
 * src/domain/reduce.ts fails the build until both exist.
 *
 * UI commands carry no window id: the window is whoever sent it (main knows the sender), and the reducer receives
 * it in the `Input` envelope. Targets default to "what the user is looking at" through `'focused'` / `'current'`.
 *
 * Overlay rule (enforced once, in `reduce` by `keepsOverlay`, derived from the type prefix): every UiCommand except
 * `commandBar/*` and `overlay/*` first closes an open command bar; `archive/*` and `settings/*` additionally keep an
 * open archive page (they are its own controls). Picking an action or a tab
 * in the command bar is therefore just dispatching that action's command. Name new overlay-local commands with
 * one of those prefixes.
 *
 * What is a command: anything that reads or changes app state, or targets a tab by id. Pure page-local
 * affordances with no state (copy link address, inspect element at a point) call webContents directly.
 */
import { z } from 'zod'
import {
  ArchiveIdSchema,
  ItemIdSchema,
  PointSchema,
  SpaceIdSchema,
  type ItemId,
  type Rect,
  type Size,
  type WindowId,
} from './base'
import { AUTO_ARCHIVE_AFTER } from './constants'
import { SpaceIconSchema, SpaceThemeSchema } from './theme'

const DeltaSchema = z.union([z.literal(1), z.literal(-1)])

/** `'focused'` = the focused pane's tab in the dispatching window. */
export const ItemRefSchema = z.union([z.literal('focused'), ItemIdSchema])
export type ItemRef = z.infer<typeof ItemRefSchema>

/** `'current'` = the dispatching window's space. */
export const SpaceRefSchema = z.union([z.literal('current'), SpaceIdSchema])
export type SpaceRef = z.infer<typeof SpaceRefSchema>

/**
 * Where a moved item lands. `into.index` counts the destination's children after the item is detached, so
 * applying the same move twice is a no-op. `space` = dropped on a dock icon: top of that space's Today, or the
 * end of its Pinned if the item came from Pinned.
 */
export const DestinationSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('into'), parentId: ItemIdSchema, index: z.number().int().nonnegative() }),
  z.object({ kind: z.literal('space'), spaceId: SpaceIdSchema }),
])
export type Destination = z.infer<typeof DestinationSchema>

/** Native popup menus the renderer may ask for; main builds the entries from domain state (see `menu/popup`). */
export const PopupMenuSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('item'), itemId: ItemIdSchema }),
  z.object({ kind: z.literal('space'), spaceId: SpaceIdSchema }),
  z.object({ kind: z.literal('plus') }),
])
export type PopupMenu = z.infer<typeof PopupMenuSchema>

export const SidebarDialogRequestSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('new-space') }),
  z.object({ kind: z.literal('edit-space'), spaceId: SpaceRefSchema }),
])
export type SidebarDialogRequest = z.infer<typeof SidebarDialogRequestSchema>

export const UiCommandSchema = z.discriminatedUnion('type', [
  // --- Command bar, archive, settings (these keep an open overlay open) ---
  /** Cmd+T: centered bar that creates a tab. Cmd+L / URL pill click: bar over the pill that navigates the focused tab. */
  z.object({ type: z.literal('commandBar/open'), mode: z.enum(['new-tab', 'edit-current']) }),
  /** Typed text or a history URL; main resolves it with `resolveTypedInput` and applies it per the open bar's target. */
  z.object({ type: z.literal('commandBar/submit'), input: z.string().min(1).max(8192) }),
  z.object({ type: z.literal('overlay/close') }),
  z.object({ type: z.literal('archive/open') }),
  z.object({ type: z.literal('archive/restore'), entryId: ArchiveIdSchema }),
  /** Cmd+Shift+T. */
  z.object({ type: z.literal('archive/restore-last') }),
  z.object({ type: z.literal('archive/clear') }),
  z.object({ type: z.literal('settings/auto-archive'), after: z.enum(AUTO_ARCHIVE_AFTER) }),

  // --- Tabs and browsing ---
  /** Sidebar click, favorite click, command bar "switch to tab". Switches space when needed. */
  z.object({ type: z.literal('tab/focus'), tabId: ItemIdSchema }),
  /** Cmd+Opt+Down / Up: next or previous item in sidebar order. */
  z.object({ type: z.literal('tab/step'), delta: DeltaSchema }),
  /** Ctrl+Tab / Ctrl+Shift+Tab: walk the recent-tab order; committed when Ctrl is released. */
  z.object({ type: z.literal('tab/cycle-recent'), delta: DeltaSchema }),
  /**
   * Cmd+W and the hover ×. A Today tab is archived. A Pinned or Favorites tab stays in the sidebar and is unloaded
   * (its webContents closes), which is Arc's "Close and Keep Pinned".
   */
  z.object({ type: z.literal('tab/close'), target: ItemRefSchema }),
  /** Cmd+D: Today -> end of Pinned; Pinned or Favorites -> top of Today. */
  z.object({ type: z.literal('tab/toggle-pin'), target: ItemRefSchema }),
  /** "Reset Tab to Original URL": navigate a pinned tab back to the URL it was pinned with. */
  z.object({ type: z.literal('tab/reset'), target: ItemRefSchema }),
  /** Cmd+Shift+C. */
  z.object({ type: z.literal('tab/copy-url') }),
  /** Shortcuts target 'focused'; the page context menu targets the right-clicked pane's tab. */
  z.object({ type: z.literal('nav/history'), direction: z.enum(['back', 'forward']), target: ItemRefSchema }),
  z.object({ type: z.literal('nav/reload'), hard: z.boolean(), target: ItemRefSchema }),
  z.object({ type: z.literal('view/zoom'), step: z.enum(['in', 'out', 'reset']) }),
  z.object({ type: z.literal('view/devtools') }),
  z.object({ type: z.literal('view/fullscreen') }),

  // --- Sidebar structure ---
  /** Double-click a row, or "Rename Current Item". The row turns into an input in the sidebar. */
  z.object({ type: z.literal('item/begin-rename'), target: ItemRefSchema }),
  /** Ends a rename. `null` cancels; `''` on a tab clears its custom title. */
  z.object({ type: z.literal('item/rename'), itemId: ItemIdSchema, title: z.string().max(500).nullable() }),
  /** Drag and drop, within or across sections, into folders, or onto a dock space icon. */
  z.object({ type: z.literal('item/move'), itemId: ItemIdSchema, to: DestinationSchema }),
  /** Cmd+Shift+N and the "+" menu: new folder at the top of the current space's Pinned, in rename mode. */
  z.object({ type: z.literal('folder/new') }),
  z.object({ type: z.literal('folder/toggle'), folderId: ItemIdSchema }),
  /** "Deleting this folder will archive the tabs inside it." */
  z.object({ type: z.literal('folder/delete'), folderId: ItemIdSchema }),
  /** Cmd+Shift+K and the Today header's Clear: archive every Today item that is not on screen. */
  z.object({ type: z.literal('today/clear') }),

  // --- Spaces ---
  z.object({ type: z.literal('space/new'), title: z.string().max(100), icon: SpaceIconSchema, theme: SpaceThemeSchema }),
  z.object({
    type: z.literal('space/update'),
    spaceId: SpaceIdSchema,
    title: z.string().max(100).optional(),
    icon: SpaceIconSchema.optional(),
    theme: SpaceThemeSchema.optional(),
  }),
  /** Archives every tab in the space. Refused for the last space. */
  z.object({ type: z.literal('space/delete'), spaceId: SpaceIdSchema }),
  z.object({ type: z.literal('space/move'), spaceId: SpaceIdSchema, index: z.number().int().nonnegative() }),
  /** Dock icon click. */
  z.object({ type: z.literal('space/focus'), spaceId: SpaceIdSchema }),
  /** Cmd+Opt+Right / Left. */
  z.object({ type: z.literal('space/step'), delta: DeltaSchema }),
  z.object({ type: z.literal('space/toggle-pinned'), spaceId: SpaceRefSchema }),

  // --- Split view ---
  /**
   * Ctrl+Shift+=. A tab becomes a split of [tab, new empty pane]; an existing split gains a pane (max 4). The
   * new pane is a tab with no URL, and the command bar opens to fill it.
   */
  z.object({ type: z.literal('split/add') }),
  /** Ctrl+Shift+-. Closes the focused pane's tab; a split left with one pane dissolves into that tab. */
  z.object({ type: z.literal('split/close-pane') }),
  /** Divider drag. Fractions are relative; the domain normalizes them and enforces LAYOUT.minPaneFraction. */
  z.object({
    type: z.literal('split/resize'),
    splitId: ItemIdSchema,
    fractions: z.array(z.object({ tabId: ItemIdSchema, fraction: z.number().positive() })).min(2).max(4),
  }),

  // --- Window chrome ---
  /** Cmd+S. */
  z.object({ type: z.literal('sidebar/toggle') }),
  /** Resize-handle drag; clamped to LAYOUT.sidebar min/max by the domain. */
  z.object({ type: z.literal('sidebar/resize'), width: z.number() }),
  /** Hidden sidebar: pointer reaches the left edge (open) or leaves the floating sidebar (close). */
  z.object({ type: z.literal('sidebar/peek'), open: z.boolean() }),
  /** Open or close the space dialog (new space, or edit name/icon/theme). */
  z.object({ type: z.literal('sidebar/dialog'), dialog: SidebarDialogRequestSchema.nullable() }),
  /** Right-click a row or space, or click "+". `at` is in window coordinates. */
  z.object({ type: z.literal('ui/popup'), menu: PopupMenuSchema, at: PointSchema }),
])
export type UiCommand = z.infer<typeof UiCommandSchema>
export type UiCommandType = UiCommand['type']

/** Fields a page event may change. Written by main's tab runtime only. */
export interface PagePatch {
  /** Committed URL (did-navigate / did-navigate-in-page). Never set by a failed load. */
  readonly url?: string
  readonly title?: string
  readonly faviconUrl?: string | null
  readonly loading?: boolean
  readonly canGoBack?: boolean
  readonly canGoForward?: boolean
  /** Set by did-fail-load (aborts excluded), cleared by the next commit. Touches live state only, never url or title. */
  readonly failure?: { readonly code: number; readonly description: string } | null
  /** render-process-gone. The tab stays; its view is recreated the next time it is shown. */
  readonly crashed?: boolean
}

/** Observations from the main process. Constructed in main only; never parsed from a renderer. */
export type SystemCommand =
  | { readonly type: 'page/updated'; readonly tabId: ItemId; readonly patch: PagePatch }
  /** target=_blank, window.open, Cmd+click (setWindowOpenHandler). Opens in the opener's space's Today. */
  | { readonly type: 'page/open'; readonly openerId: ItemId; readonly url: string; readonly background: boolean }
  /** Ctrl released after Ctrl+Tab cycling (before-input-event keyUp). No-op when no cycle is running. */
  | { readonly type: 'tab/cycle-recent-commit'; readonly windowId: WindowId }
  /**
   * A tab view's webContents gained keyboard focus (its 'focus' event: the user clicked into another split pane).
   * The reducer sets that pane's split `focusedId`, so 'focused' targets (Cmd+L, Cmd+W, Cmd+D) resolve to the pane
   * the user is in. Ignored when the tab is not a split pane.
   */
  | { readonly type: 'pane/focused'; readonly tabId: ItemId }
  /** BaseWindow resize/move. `bounds` is persisted for restore; `contentSize` drives layout. */
  | { readonly type: 'window/bounds'; readonly windowId: WindowId; readonly bounds: Rect; readonly contentSize: Size }
  /** Auto-archive sweep. Sent on an interval and by the e2e test clock after it moves. */
  | { readonly type: 'clock/tick' }

/** The reducer's input envelope. `ui` commands are scoped to the window whose surface or shortcut produced them. */
export type Input =
  | { readonly origin: 'ui'; readonly windowId: WindowId; readonly command: UiCommand }
  | { readonly origin: 'system'; readonly command: SystemCommand }

export type ParsedCommand = { readonly ok: true; readonly command: UiCommand } | { readonly ok: false; readonly error: string }

/** Boundary parse for renderer and test-API messages. `UiCommandSchema.safeParse`, flattened to a message on failure. */
export function parseUiCommand(raw: unknown): ParsedCommand {
  const parsed = UiCommandSchema.safeParse(raw)
  if (parsed.success) return { ok: true, command: parsed.data }
  const error = parsed.error.issues.map((issue) => `${issue.path.length > 0 ? issue.path.map(String).join('.') : '(root)'}: ${issue.message}`).join('; ')
  return { ok: false, error }
}
