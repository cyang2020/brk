/**
 * The one shortcut table. It drives three things, all derived from this list:
 * - the application menu (src/main/input.ts groups entries by `menu`, in declaration order, separators between `group`s),
 * - key matching in before-input-event on every webContents (src/shared/accelerator.ts `createKeymap`),
 * - the command bar's action rows (src/renderer/overlay/suggest.ts reads entries with `palette: true`).
 *
 * Labels and keys are Arc's menu nib (model-and-shortcuts.md 2.3). Priorities follow the nib's `Priority`:
 * `overrideWebView` and `promptAfterConsumedByWebView` map to `app` (intercepted before the page sees the key; the
 * spike showed a menu accelerator alone loses to a page that handles the key), unset maps to `page` (the page may
 * consume it; the menu accelerator fires otherwise). Arc's press-twice prompt is not reproduced in v1.
 *
 * Accelerators use Electron syntax. `CmdOrCtrl` is Cmd on macOS and Ctrl elsewhere; a key spec using bare
 * `Command` applies on macOS only. Edit-menu roles (undo, cut, copy, paste, select all) are not actions: they
 * stay native and are never intercepted.
 */
import type { UiCommand } from './commands'

export type MenuName = 'File' | 'Edit' | 'View' | 'Spaces' | 'Tabs' | 'Archive' | 'Window'
export type KeyPriority = 'app' | 'page'

export interface ActionSpec {
  /** Menu title, also the command bar row text. */
  readonly label: string
  /**
   * The first entry that applies on the platform is shown in the menu; the rest are alternates that
   * before-input-event also matches. (Zoom In's `Command+Plus` is macOS-only because Ctrl+Plus on Linux is the
   * same physical chord as Add Split View's Ctrl+Shift+=.)
   */
  readonly keys: readonly string[]
  readonly menu: MenuName
  /** Separators fall between different groups within one menu. */
  readonly group: number
  /** Listed among the command bar's actions. */
  readonly palette: boolean
  readonly priority: KeyPriority
  /** What the action does. Always an argument-free command resolved against the dispatching window. */
  readonly command: UiCommand
}

export const MENU_ORDER: readonly MenuName[] = ['File', 'Edit', 'View', 'Spaces', 'Tabs', 'Archive', 'Window']

export const ACTIONS = {
  // File
  newTab: { label: 'New Tab…', keys: ['CmdOrCtrl+T'], menu: 'File', group: 0, palette: false, priority: 'app', command: { type: 'commandBar/open', mode: 'new-tab' } },
  openCommandBar: { label: 'Open Command Bar', keys: ['CmdOrCtrl+L'], menu: 'File', group: 0, palette: false, priority: 'app', command: { type: 'commandBar/open', mode: 'edit-current' } },
  restoreLastTab: { label: 'Restore Last Closed Tab', keys: ['CmdOrCtrl+Shift+T'], menu: 'File', group: 1, palette: true, priority: 'app', command: { type: 'archive/restore-last' } },
  archiveTab: { label: 'Archive Tab', keys: ['CmdOrCtrl+W'], menu: 'File', group: 1, palette: true, priority: 'app', command: { type: 'tab/close', target: 'focused' } },
  // Edit (native roles are added around this by the menu builder)
  copyUrl: { label: 'Copy URL', keys: ['CmdOrCtrl+Shift+C'], menu: 'Edit', group: 1, palette: true, priority: 'app', command: { type: 'tab/copy-url' } },
  // View
  toggleSidebar: { label: 'Show/Hide Sidebar', keys: ['CmdOrCtrl+S'], menu: 'View', group: 0, palette: true, priority: 'app', command: { type: 'sidebar/toggle' } },
  togglePinnedSection: { label: 'Expand/Collapse Pinned Section', keys: [], menu: 'View', group: 0, palette: true, priority: 'page', command: { type: 'space/toggle-pinned', spaceId: 'current' } },
  reload: { label: 'Refresh the Page', keys: ['CmdOrCtrl+R'], menu: 'View', group: 1, palette: true, priority: 'page', command: { type: 'nav/reload', hard: false, target: 'focused' } },
  forceReload: { label: 'Force Refresh the Page', keys: ['CmdOrCtrl+Shift+R'], menu: 'View', group: 1, palette: false, priority: 'page', command: { type: 'nav/reload', hard: true, target: 'focused' } },
  addSplit: { label: 'Add Split View', keys: ['Ctrl+Shift+='], menu: 'View', group: 2, palette: true, priority: 'app', command: { type: 'split/add' } },
  closeSplitPane: { label: 'Close this Split Pane', keys: ['Ctrl+Shift+-'], menu: 'View', group: 2, palette: true, priority: 'app', command: { type: 'split/close-pane' } },
  zoomReset: { label: 'Zoom to Actual Size', keys: ['CmdOrCtrl+0'], menu: 'View', group: 3, palette: false, priority: 'page', command: { type: 'view/zoom', step: 'reset' } },
  zoomIn: { label: 'Zoom In', keys: ['Command+Plus', 'CmdOrCtrl+='], menu: 'View', group: 3, palette: false, priority: 'page', command: { type: 'view/zoom', step: 'in' } },
  zoomOut: { label: 'Zoom Out', keys: ['CmdOrCtrl+-'], menu: 'View', group: 3, palette: false, priority: 'page', command: { type: 'view/zoom', step: 'out' } },
  devTools: { label: 'Developer Tools', keys: ['Alt+CmdOrCtrl+I', 'F12'], menu: 'View', group: 4, palette: true, priority: 'app', command: { type: 'view/devtools' } },
  fullscreen: { label: 'Enter/Exit Full Screen', keys: ['Control+Command+F', 'F11'], menu: 'View', group: 4, palette: false, priority: 'app', command: { type: 'view/fullscreen' } },
  // Spaces
  newSpace: { label: 'New Space…', keys: [], menu: 'Spaces', group: 0, palette: true, priority: 'page', command: { type: 'sidebar/dialog', dialog: { kind: 'new-space' } } },
  editSpace: { label: 'Edit Theme…', keys: [], menu: 'Spaces', group: 0, palette: true, priority: 'page', command: { type: 'sidebar/dialog', dialog: { kind: 'edit-space', spaceId: 'current' } } },
  nextSpace: { label: 'Next Space', keys: ['Alt+CmdOrCtrl+Right'], menu: 'Spaces', group: 1, palette: true, priority: 'page', command: { type: 'space/step', delta: 1 } },
  previousSpace: { label: 'Previous Space', keys: ['Alt+CmdOrCtrl+Left'], menu: 'Spaces', group: 1, palette: true, priority: 'page', command: { type: 'space/step', delta: -1 } },
  // Tabs
  pinTab: { label: 'Pin/Unpin Tab', keys: ['CmdOrCtrl+D'], menu: 'Tabs', group: 0, palette: true, priority: 'app', command: { type: 'tab/toggle-pin', target: 'focused' } },
  newFolder: { label: 'New Folder…', keys: ['CmdOrCtrl+Shift+N'], menu: 'Tabs', group: 0, palette: true, priority: 'page', command: { type: 'folder/new' } },
  renameItem: { label: 'Rename Current Item', keys: [], menu: 'Tabs', group: 0, palette: true, priority: 'page', command: { type: 'item/begin-rename', target: 'focused' } },
  nextTab: { label: 'Next Tab', keys: ['Alt+CmdOrCtrl+Down'], menu: 'Tabs', group: 1, palette: false, priority: 'app', command: { type: 'tab/step', delta: 1 } },
  previousTab: { label: 'Previous Tab', keys: ['Alt+CmdOrCtrl+Up'], menu: 'Tabs', group: 1, palette: false, priority: 'app', command: { type: 'tab/step', delta: -1 } },
  cycleRecentForward: { label: 'Tab Switcher (forward)', keys: ['Ctrl+Tab'], menu: 'Tabs', group: 1, palette: false, priority: 'app', command: { type: 'tab/cycle-recent', delta: 1 } },
  cycleRecentBackward: { label: 'Tab Switcher (backward)', keys: ['Ctrl+Shift+Tab'], menu: 'Tabs', group: 1, palette: false, priority: 'app', command: { type: 'tab/cycle-recent', delta: -1 } },
  clearToday: { label: 'Clear Unpinned Tabs', keys: ['CmdOrCtrl+Shift+K'], menu: 'Tabs', group: 2, palette: true, priority: 'page', command: { type: 'today/clear' } },
  resetTab: { label: 'Reset Tab to Original URL', keys: [], menu: 'Tabs', group: 2, palette: true, priority: 'page', command: { type: 'tab/reset', target: 'focused' } },
  // Archive (Arc's Archive menu also holds history navigation)
  goBack: { label: 'Go Back', keys: ['CmdOrCtrl+['], menu: 'Archive', group: 0, palette: false, priority: 'app', command: { type: 'nav/history', direction: 'back', target: 'focused' } },
  goForward: { label: 'Go Forward', keys: ['CmdOrCtrl+]'], menu: 'Archive', group: 0, palette: false, priority: 'app', command: { type: 'nav/history', direction: 'forward', target: 'focused' } },
  viewArchive: { label: 'View Archive', keys: [], menu: 'Archive', group: 1, palette: true, priority: 'page', command: { type: 'archive/open' } },
  clearArchive: { label: 'Clear Archive', keys: [], menu: 'Archive', group: 1, palette: true, priority: 'page', command: { type: 'archive/clear' } },
} as const satisfies Record<string, ActionSpec>

export type ActionId = keyof typeof ACTIONS

/** Ids with `palette: true`, in table order. */
export function paletteActions(): readonly ActionId[] {
  throw new Error('not implemented')
}
