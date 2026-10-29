/**
 * Test-only. Keeps the sidebar's tests running before W1's shared bodies land: each wrapper calls the real
 * function and falls back to a stand-in only while the real one still throws "not implemented". Once W1 merges,
 * the real code runs and the stand-ins are dead; delete this file and the `vi.mock` lines that use it then.
 *
 * Only type imports: a `vi.mock` factory calls these with the real module, and a runtime import of a shared module
 * from here would wait on the very factory that is running.
 */
import type * as Constants from '../../shared/constants'
import type * as Placement from '../../shared/placement'
import type * as Theme from '../../shared/theme'

function implementedOr<A extends unknown[], R>(real: (...args: A) => R, standIn: (...args: A) => R): (...args: A) => R {
  return (...args) => {
    try {
      return real(...args)
    } catch (error) {
      if (error instanceof Error && error.message === 'not implemented') return standIn(...args)
      throw error
    }
  }
}

/** urlPillRect per the formula in its TODO. */
export function withConstantStandIns(real: typeof Constants): typeof Constants {
  const { LAYOUT } = real
  return {
    ...real,
    urlPillRect: implementedOr(real.urlPillRect, (sidebarWidth) => ({
      x: LAYOUT.contentInset + LAYOUT.urlPill.sideInset,
      y: LAYOUT.titlebarHeight,
      width: sidebarWidth - 2 * LAYOUT.urlPill.sideInset,
      height: LAYOUT.urlPill.height,
    })),
  }
}

/** canPlace per the v1 rules in its doc comment. */
export function withPlacementStandIns(real: typeof Placement): typeof Placement {
  return {
    ...real,
    canPlace: implementedOr(real.canPlace, (item, section, insideFolder) => {
      if (section === 'favorites') return item === 'tab' && !insideFolder
      if (section === 'today') return item !== 'folder' && !insideFolder
      return true
    }),
  }
}

/** themeFromPrimary: the primary alone; resolveTheme: light tokens over the stored colors. */
export function withThemeStandIns(real: typeof Theme): typeof Theme {
  return {
    ...real,
    themeFromPrimary: implementedOr(real.themeFromPrimary, (primary) => ({ colors: [primary], grain: 0.25, appearance: 'auto' })),
    resolveTheme: implementedOr(real.resolveTheme, (theme) => ({
      scheme: 'light',
      gradient: [...theme.colors],
      grain: theme.grain,
      tokens: real.SIDEBAR_TOKENS.light,
      windowColor: theme.colors[0] ?? '#808080',
    })),
  }
}
