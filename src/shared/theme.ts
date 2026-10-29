/**
 * Space themes: the stored shape, Arc's observed preset palettes and sidebar tokens, and the pure resolution
 * from a stored theme to the CSS-ready values every surface paints with.
 *
 * Simplified from Arc's `WindowTheme` (model-and-shortcuts.md 1.13): one blended gradient of 1 to 3 colors, a
 * grain amount, and an appearance. Light or dark is derived from the primary color's luminance unless forced
 * (plan: "由主题颜色亮度推出 light/dark").
 */
import { z } from 'zod'
import type { Brand } from './base'

/** `#rrggbb`, uppercase or lowercase. */
export type Hex = Brand<string, 'Hex'>
export const HexSchema = z.custom<Hex>(
  (value) => typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value),
  'expected #rrggbb',
)

export const SpaceThemeSchema = z.object({
  /** First entry is the primary color. Arc: `BlendedGradientConfiguration.baseColors`. */
  colors: z.array(HexSchema).min(1).max(3).readonly(),
  /** 0..1. Arc: `BlendedBackgroundModifiers.noiseFactor` with the `grain` overlay. */
  grain: z.number().min(0).max(1),
  /** `auto` = derive from luminance. Arc: translucency `light` | `dark` | `auto`. */
  appearance: z.enum(['auto', 'light', 'dark']),
})
export type SpaceTheme = z.infer<typeof SpaceThemeSchema>

/** Arc: `SidebarCustomIcon`. v1 supports an emoji or Arc's default space icon. */
export const SpaceIconSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('emoji'), emoji: z.string().min(1).max(16) }),
  z.object({ kind: z.literal('none') }),
])
export type SpaceIcon = z.infer<typeof SpaceIconSchema>

export type PresetSet = 'brand' | 'drab' | 'greyscale' | 'pastel'

/**
 * Observed: `ColorPickerBrand1-9`, `ColorPickerDrab1-9`, `ColorPickerGreyscale1-9`, `ColorPickerPastel1-9`
 * (visual-and-copy.md, "Space theme preset palette"). Brand5 uses the rendered value #FF8558 (inferred from its
 * extended-linear-sRGB components). Page order in Arc's editor is unknown; this order is ours.
 */
export const THEME_PRESETS = {
  brand: ['#F2EAE4', '#F29BBB', '#A6729D', '#F25E6B', '#FF8558', '#F2D66D', '#73E59C', '#7EB8D6', '#666786'],
  drab: ['#4B3B58', '#623856', '#854444', '#A77048', '#D1B46A', '#CDCCA8', '#84A885', '#34604B', '#2D4468'],
  greyscale: ['#FFFFFF', '#E5E5E5', '#CCCCCC', '#B2B2B2', '#808080', '#666666', '#333333', '#1A1A1A', '#000000'],
  pastel: ['#FDFBFA', '#FBEAF3', '#ECD2EA', '#F7CDD2', '#FAE1D5', '#FEF9E7', '#E4FCEC', '#E0F2FB', '#C5C6E2'],
} as unknown as Readonly<Record<PresetSet, readonly Hex[]>>

export type SidebarToken =
  | 'foreground'
  | 'foregroundStrong'
  | 'itemBackground'
  | 'itemHover'
  | 'separator'
  | 'border'
  | 'tabCurrent'
  | 'tabVisible'
  | 'tabPrevious'
  | 'tabPreviousHover'
  | 'tabPressed'
  | 'tabChild'
  | 'tabShadow'
  | 'dragHint'
  | 'dragHintStrong'

/**
 * Observed (visual-and-copy.md, "Sidebar and tab colors"): translucent black or white over the theme, so the
 * gradient shows through. `Record` over `SidebarToken`: a token without both values fails the build.
 */
export const SIDEBAR_TOKENS: Readonly<Record<'light' | 'dark', Readonly<Record<SidebarToken, string>>>> = {
  light: {
    foreground: 'rgba(0,0,0,0.3)',
    foregroundStrong: 'rgba(0,0,0,0.45)',
    itemBackground: 'rgba(14,15,16,0.05)',
    itemHover: 'rgba(14,15,16,0.1)',
    separator: 'rgba(0,0,0,0.15)',
    border: 'rgba(255,255,255,0.3)',
    tabCurrent: 'rgba(255,255,255,0.85)',
    tabVisible: 'rgba(255,255,255,0.7)',
    tabPrevious: 'rgba(255,255,255,0.32)',
    tabPreviousHover: 'rgba(255,255,255,0.5)',
    tabPressed: 'rgba(14,15,16,0.065)',
    tabChild: 'rgba(0,0,0,0.07)',
    tabShadow: 'rgba(0,0,0,0.2)',
    dragHint: 'rgba(0,0,0,0.2)',
    dragHintStrong: 'rgba(0,0,0,0.5)',
  },
  dark: {
    foreground: 'rgba(255,255,255,0.45)',
    foregroundStrong: 'rgba(255,255,255,0.45)',
    itemBackground: 'rgba(250,251,255,0.1)',
    itemHover: 'rgba(250,251,255,0.15)',
    separator: 'rgba(255,255,255,0.15)',
    border: 'rgba(255,255,255,0.3)',
    tabCurrent: 'rgba(250,251,255,0.2)',
    tabVisible: 'rgba(250,251,255,0.15)',
    tabPrevious: 'rgba(250,251,255,0.08)',
    tabPreviousHover: 'rgba(250,251,255,0.12)',
    tabPressed: 'rgba(250,251,255,0.065)',
    tabChild: 'rgba(255,255,255,0.07)',
    tabShadow: 'rgba(0,0,0,0)',
    dragHint: 'rgba(255,255,255,0.2)',
    dragHintStrong: 'rgba(255,255,255,0.5)',
  },
}

/** What surfaces paint with. Derived, never stored. */
export interface ResolvedTheme {
  readonly scheme: 'light' | 'dark'
  /** CSS colors, primary first, 1 to 3 entries. The sidebar renderer blends them into Arc's soft gradient. */
  readonly gradient: readonly string[]
  /** 0..1 grain overlay opacity. */
  readonly grain: number
  readonly tokens: Readonly<Record<SidebarToken, string>>
  /** Solid color for `BaseWindow.setBackgroundColor`; visible only before the chrome view first paints. */
  readonly windowColor: string
}

/** GUESS: Arc's default theme for a new space is not in static data. */
export const DEFAULT_THEME: SpaceTheme = { colors: ['#7EB8D6' as Hex], grain: 0.25, appearance: 'auto' }

/** WCAG relative luminance, 0..1. */
export function relativeLuminance(color: Hex): number {
  throw new Error('not implemented')
}

/**
 * Pure. Scheme: forced by `appearance`, else `light` when the primary color's luminance is above a threshold
 * (GUESS 0.45). Gradient: the stored colors as CSS. Tokens: SIDEBAR_TOKENS[scheme].
 */
export function resolveTheme(theme: SpaceTheme): ResolvedTheme {
  throw new Error('not implemented')
}

/**
 * The theme a new space gets when the user picks one preset color: the primary plus two analogous companions
 * (Arc's `wheel: analogous`), grain 0.25, appearance auto. Pure; the space dialog uses it for its live preview.
 */
export function themeFromPrimary(primary: Hex): SpaceTheme {
  // TODO: rotate hue ±20°, nudge lightness, return { colors: [primary, a, b], grain: 0.25, appearance: 'auto' }
  throw new Error('not implemented')
}
