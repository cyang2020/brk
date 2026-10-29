/**
 * Bottom row: archive button (TID.dockArchive -> archive/open), space icons (TID.dockSpace(id): the emoji, the
 * named icon's glyph, or a dot in `color` when the icon is `none`; click -> space/focus; right-click -> ui/popup
 * space; drop a row on an icon -> item/move { kind: 'space' }; drag an icon sideways -> space/move), and "+"
 * (TID.dockPlus -> ui/popup plus, anchored at the button). data-testid TID.dock.
 */
import type { ReactElement } from 'react'
import { COPY } from '../../shared/copy'
import { TID } from '../../shared/testids'
import type { DockSpaceView } from '../../shared/view'
import { dispatch } from '../common/bridge'
import { useDrag } from './drag'
import { windowPoint } from './geometry'
import { Glyph, SpaceGlyph, UI_GLYPHS } from './icons'
import { popup } from './Row'

export interface DockProps {
  readonly spaces: readonly DockSpaceView[]
}

export function Dock(props: DockProps): ReactElement {
  const drag = useDrag()
  return (
    <footer data-testid={TID.dock} className="dock">
      <button type="button" data-testid={TID.dockArchive} className="dock-btn" title={COPY.archive.title} onClick={() => dispatch({ type: 'archive/open' })}>
        <Glyph d={UI_GLYPHS.archive} size={16} />
      </button>
      <div className="dock-spaces">
        {props.spaces.map((space, index) => (
          <button
            type="button"
            key={space.id}
            data-testid={TID.dockSpace(space.id)}
            data-active={String(space.active)}
            data-dock-space=""
            data-space-id={space.id}
            data-drop-into={drag.state?.spaceId === space.id ? '' : undefined}
            data-dragging={drag.state?.source.id === space.id ? '' : undefined}
            className="dock-space"
            title={space.title}
            aria-pressed={space.active}
            onClick={() => dispatch({ type: 'space/focus', spaceId: space.id })}
            onContextMenu={(e) => popup(e, { kind: 'space', spaceId: space.id })}
            onPointerDown={(e) => drag.press(e, { type: 'space', id: space.id, index })}
          >
            <SpaceGlyph icon={space.icon} color={space.color} size={16} />
          </button>
        ))}
      </div>
      <button
        type="button"
        data-testid={TID.dockPlus}
        className="dock-btn"
        aria-label={COPY.sidebar.plusButton}
        onClick={(e) => {
          const box = e.currentTarget.getBoundingClientRect()
          dispatch({ type: 'ui/popup', menu: { kind: 'plus' }, at: windowPoint({ clientX: box.left, clientY: box.top }) })
        }}
      >
        <Glyph d={UI_GLYPHS.plus} size={16} />
      </button>
    </footer>
  )
}
