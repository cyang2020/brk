/** ResolvedTheme -> CSS custom properties (--arc-fg, --arc-tab-current, --arc-gradient-0..2, --arc-grain, ...). */
import type { CSSProperties } from 'react'
import type { ResolvedTheme } from '../../shared/theme'

export function themeVars(theme: ResolvedTheme): CSSProperties {
  throw new Error('not implemented')
}
