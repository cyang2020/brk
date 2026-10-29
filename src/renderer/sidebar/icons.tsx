/**
 * Inline SVG glyphs. No icon library: one stroked path per glyph on a 24-unit grid, Feather-like (Arc's own icon
 * font is Feather, visual-and-copy.md "What ARCClients_Icons.bundle actually contains"). `NAMED_GLYPHS` is a
 * `Record<NamedIcon, ...>`, so a name added to NAMED_ICONS without a glyph fails the build.
 */
import type { ReactElement } from 'react'
import type { SpaceIcon, NamedIcon } from '../../shared/theme'

export const NAMED_GLYPHS: Readonly<Record<NamedIcon, string>> = {
  star: 'M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01z',
  bookmark: 'M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z',
  heart:
    'M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z',
  flag: 'M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1zM4 22v-7',
  folder: 'M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z',
  calendar: 'M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM16 2v4M8 2v4M3 10h18',
  mail: 'M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM22 6l-10 7L2 6',
  terminal: 'M4 17l6-6-6-6M12 19h8',
  briefcase: 'M4 7h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2zM16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16',
  home: 'M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2zM9 22V12h6v10',
  book: 'M4 19.5A2.5 2.5 0 0 1 6.5 17H20M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z',
  music: 'M9 18V5l12-2v13M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0zM21 16a3 3 0 1 1-6 0 3 3 0 0 1 6 0z',
  camera: 'M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2zM16 13a4 4 0 1 1-8 0 4 4 0 0 1 8 0z',
  globe:
    'M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0zM2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z',
  bolt: 'M13 2L3 14h9l-1 8 10-12h-9l1-8z',
  leaf: 'M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10zM2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12',
}

/** Glyphs for the sidebar's own controls. */
export const UI_GLYPHS = {
  archive: 'M21 8v13H3V8M1 3h22v5H1zM10 12h4',
  plus: 'M12 5v14M5 12h14',
  close: 'M18 6L6 18M6 6l12 12',
  chevron: 'M9 18l6-6-6-6',
  reset: 'M1 4v6h6M3.51 15a9 9 0 1 0 2.13-9.36L1 10',
} as const

export function Glyph(props: { readonly d: string; readonly size?: number; readonly className?: string }): ReactElement {
  const size = props.size ?? 16
  return (
    <svg
      className={props.className}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d={props.d} />
    </svg>
  )
}

/** A space's icon: its emoji, its named glyph, or Arc's default dot in the theme's primary color. */
export function SpaceGlyph(props: { readonly icon: SpaceIcon; readonly color: string; readonly size?: number }): ReactElement {
  const size = props.size ?? 16
  switch (props.icon.kind) {
    case 'emoji':
      return (
        <span className="space-emoji" style={{ fontSize: size - 2, width: size, height: size }} aria-hidden="true">
          {props.icon.emoji}
        </span>
      )
    case 'named':
      return <Glyph d={NAMED_GLYPHS[props.icon.name]} size={size} />
    case 'none':
      return <span className="space-dot" style={{ background: props.color }} aria-hidden="true" />
  }
}
