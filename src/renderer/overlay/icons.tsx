/** The overlay's few glyphs, inline SVG in currentColor, and a favicon that falls back to the globe. */
import { useState, type ReactElement } from 'react'

function Glyph({ children }: { readonly children: ReactElement | readonly ReactElement[] }): ReactElement {
  return (
    <svg className="glyph" viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {children}
    </svg>
  )
}

export const GlobeIcon = (): ReactElement => (
  <Glyph>
    <circle cx="8" cy="8" r="6.2" />
    <path d="M1.8 8h12.4M8 1.8c1.7 1.8 2.5 3.9 2.5 6.2S9.7 12.4 8 14.2C6.3 12.4 5.5 10.3 5.5 8S6.3 3.6 8 1.8Z" />
  </Glyph>
)

export const SearchIcon = (): ReactElement => (
  <Glyph>
    <circle cx="7" cy="7" r="4.6" />
    <path d="m10.4 10.4 3.8 3.8" />
  </Glyph>
)

export const ClockIcon = (): ReactElement => (
  <Glyph>
    <circle cx="8" cy="8" r="6.2" />
    <path d="M8 4.6V8l2.3 1.5" />
  </Glyph>
)

/** The ⌘ shape, for action rows. */
export const CommandIcon = (): ReactElement => (
  <Glyph>
    <path d="M6 6V4a2 2 0 1 0-2 2h8a2 2 0 1 0-2-2v8a2 2 0 1 0 2-2H4a2 2 0 1 0 2 2V6Z" />
  </Glyph>
)

export const CloseIcon = (): ReactElement => (
  <Glyph>
    <path d="m4 4 8 8M12 4l-8 8" />
  </Glyph>
)

/** The page's favicon; the globe when there is none or it fails to load. */
export function Favicon({ url }: { readonly url: string | null }): ReactElement {
  const [failed, setFailed] = useState<string | null>(null)
  if (url === null || failed === url) return <GlobeIcon />
  return <img className="glyph favicon" src={url} alt="" width={16} height={16} draggable={false} onError={() => setFailed(url)} />
}
