/**
 * ResolvedTheme -> CSS custom properties. Set them on a surface's root element and style with `var(--arc-...)`.
 *
 * - `--arc-gradient-0..2`: the theme colors, primary first; missing entries repeat the last color.
 * - `--arc-grain`: grain overlay opacity, 0..1.
 * - Sidebar tokens (SIDEBAR_TOKENS, observed): `--arc-fg`, `--arc-fg-strong`, `--arc-item-bg`, `--arc-item-hover`,
 *   `--arc-separator`, `--arc-border`, `--arc-tab-current`, `--arc-tab-visible`, `--arc-tab-previous`,
 *   `--arc-tab-previous-hover`, `--arc-tab-pressed`, `--arc-tab-child`, `--arc-tab-shadow`, `--arc-drag-hint`,
 *   `--arc-drag-hint-strong`.
 * - Base text and surface tokens by scheme (visual-and-copy.md "Base tokens" and "Content area", observed):
 *   `--arc-text` (ForegroundPrimary), `--arc-text-secondary` (ForegroundSecondary), `--arc-text-tertiary`
 *   (ForegroundTertiary), `--arc-placeholder` (CommandBarPlaceholderText), `--arc-focus-ring` (FocusRing),
 *   `--arc-loading` (LoadingPageBorder), `--arc-popover` (PopoverBackground), `--arc-preview` (PreviewBackgroundColor),
 *   `--arc-scrim-border` (FloatingScrimBorder).
 */
import type { CSSProperties } from 'react'
import type { ResolvedTheme, SidebarToken } from '../../shared/theme'

/** `Record` over SidebarToken: a new token without a variable name fails the build. */
const TOKEN_VARS: Readonly<Record<SidebarToken, string>> = {
  foreground: '--arc-fg',
  foregroundStrong: '--arc-fg-strong',
  itemBackground: '--arc-item-bg',
  itemHover: '--arc-item-hover',
  separator: '--arc-separator',
  border: '--arc-border',
  tabCurrent: '--arc-tab-current',
  tabVisible: '--arc-tab-visible',
  tabPrevious: '--arc-tab-previous',
  tabPreviousHover: '--arc-tab-previous-hover',
  tabPressed: '--arc-tab-pressed',
  tabChild: '--arc-tab-child',
  tabShadow: '--arc-tab-shadow',
  dragHint: '--arc-drag-hint',
  dragHintStrong: '--arc-drag-hint-strong',
}

/** Observed base tokens. P3 values are used as sRGB hex; the difference is below what this UI needs. */
const BASE_VARS: Readonly<Record<ResolvedTheme['scheme'], Readonly<Record<string, string>>>> = {
  light: {
    '--arc-text': 'rgba(14,15,16,0.9)',
    '--arc-text-secondary': 'rgba(0,0,0,0.5)',
    '--arc-text-tertiary': 'rgba(0,0,0,0.3)',
    '--arc-placeholder': 'rgba(0,0,0,0.6)',
    '--arc-focus-ring': '#458AFF',
    '--arc-loading': '#0C50FF',
    '--arc-popover': '#FAFBFF',
    '--arc-preview': '#FFFFFF',
    '--arc-scrim-border': 'rgba(0,0,0,0.1)',
  },
  dark: {
    '--arc-text': 'rgba(255,255,255,0.8)',
    '--arc-text-secondary': 'rgba(255,255,255,0.5)',
    '--arc-text-tertiary': 'rgba(255,255,255,0.3)',
    '--arc-placeholder': 'rgba(255,255,255,0.6)',
    '--arc-focus-ring': '#458AFF',
    '--arc-loading': '#2AB6F6',
    '--arc-popover': '#151C30',
    '--arc-preview': '#212222',
    '--arc-scrim-border': 'rgba(255,255,255,0.2)',
  },
}

/** The three gradient stops, primary first, padded with the last color. */
export function gradientStops(gradient: readonly string[]): readonly [string, string, string] {
  const first = gradient[0] ?? '#808080'
  const second = gradient[1] ?? first
  return [first, second, gradient[2] ?? second]
}

export function themeVars(theme: ResolvedTheme): CSSProperties {
  const vars: Record<string, string> = { ...BASE_VARS[theme.scheme] }
  for (const token of Object.keys(TOKEN_VARS) as SidebarToken[]) vars[TOKEN_VARS[token]] = theme.tokens[token]
  gradientStops(theme.gradient).forEach((color, i) => {
    vars[`--arc-gradient-${i}`] = color
  })
  vars['--arc-grain'] = String(theme.grain)
  vars.colorScheme = theme.scheme
  return vars as CSSProperties
}
