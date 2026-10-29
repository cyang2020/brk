/**
 * Arc's themed window background: a soft multi-color gradient plus tiled grain (WindowThemeUI's Metal shader,
 * approximated with CSS gradients and an SVG noise tile). On theme change, the previous layer fades out over
 * TIMING.themeCrossfadeMs (Arc's `transitioning` background configuration). data-testid TID.background.
 */
import type { ReactElement } from 'react'
import type { ResolvedTheme } from '../../shared/theme'

export interface BackgroundProps {
  readonly theme: ResolvedTheme
}

export function Background(props: BackgroundProps): ReactElement {
  throw new Error('not implemented')
}
