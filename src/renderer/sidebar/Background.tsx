/**
 * Arc's themed window background: a soft multi-color gradient plus tiled grain (WindowThemeUI's Metal shader,
 * approximated with CSS gradients and an SVG noise tile, 155 px like Arc's `grain` texture). On theme change, the
 * previous layer stays on top and fades out over TIMING.themeCrossfadeMs (Arc's `transitioning` background
 * configuration), so the new gradient never flashes in before the fade starts. data-testid TID.background on the
 * full-window background; the floating sidebar paints the same layers inside its own card (`inPanel`).
 */
import { useEffect, useRef, useState } from 'react'
import type { CSSProperties, ReactElement } from 'react'
import { TIMING } from '../../shared/constants'
import { TID } from '../../shared/testids'
import type { ResolvedTheme } from '../../shared/theme'
import { gradientStops } from '../common/theme-vars'

export interface BackgroundProps {
  readonly theme: ResolvedTheme
  readonly inPanel?: boolean
}

/** GUESS: the blend. The primary color owns the top-left (where the sidebar sits), companions the far corners. */
export function gradientStyle(gradient: readonly string[]): CSSProperties {
  const [a, b, c] = gradientStops(gradient)
  return {
    backgroundColor: a,
    backgroundImage: [
      `radial-gradient(120% 90% at 0% 0%, ${a} 0%, transparent 70%)`,
      `radial-gradient(90% 80% at 100% 0%, ${b} 0%, transparent 75%)`,
      `radial-gradient(110% 100% at 100% 100%, ${c} 0%, transparent 70%)`,
      `linear-gradient(160deg, ${a} 0%, ${b} 55%, ${c} 100%)`,
    ].join(', '),
  }
}

function ThemeLayer(props: { readonly theme: ResolvedTheme; readonly leaving: boolean }): ReactElement {
  return (
    <div
      className={props.leaving ? 'bg-layer leaving' : 'bg-layer'}
      style={{ ...gradientStyle(props.theme.gradient), animationDuration: `${TIMING.themeCrossfadeMs}ms` }}
    >
      <div className="bg-grain" style={{ opacity: props.theme.grain }} />
    </div>
  )
}

const themeKey = (theme: ResolvedTheme): string => `${theme.gradient.join(',')}|${theme.grain}`

interface Layer {
  readonly id: number
  readonly theme: ResolvedTheme
}

export function Background(props: BackgroundProps): ReactElement {
  const key = themeKey(props.theme)
  const [shown, setShown] = useState({ key, theme: props.theme, seq: 0 })
  const [leaving, setLeaving] = useState<readonly Layer[]>([])
  const timers = useRef(new Map<number, number>())

  // Derived during render (not in an effect), so the outgoing layer is on screen in the same commit as the new one.
  if (shown.key !== key) {
    setShown({ key, theme: props.theme, seq: shown.seq + 1 })
    setLeaving((layers) => [...layers, { id: shown.seq, theme: shown.theme }])
  }

  useEffect(() => {
    for (const layer of leaving) {
      if (timers.current.has(layer.id)) continue
      const timer = window.setTimeout(() => {
        timers.current.delete(layer.id)
        setLeaving((layers) => layers.filter((l) => l.id !== layer.id))
      }, TIMING.themeCrossfadeMs)
      timers.current.set(layer.id, timer)
    }
  }, [leaving])

  useEffect(() => {
    const pending = timers.current
    return () => {
      for (const timer of pending.values()) window.clearTimeout(timer)
    }
  }, [])

  return (
    <div data-testid={props.inPanel ? undefined : TID.background} className="bg" data-scheme={props.theme.scheme}>
      <ThemeLayer theme={props.theme} leaving={false} />
      {leaving.map((layer) => (
        <ThemeLayer key={layer.id} theme={layer.theme} leaving />
      ))}
    </div>
  )
}
