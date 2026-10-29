/** W2 fills these in. Ported from candidate A's layout checklist (arena graft 1); computeLayout is pure. */
import { describe, it } from 'vitest'

describe('computeLayout', () => {
  it.todo('sidebar visible: content.x = sidebar width + inset, inset on the other three sides, radius = LAYOUT.contentRadius')
  it.todo('sidebar hidden: the content card spans the window minus the inset on every side and keeps its radius')
  it.todo('hidden + peek: floatingSidebar is the sidebar column over the content; content unchanged')
  it.todo('two panes: side by side, equal heights, one inset gap between them, integer pixels, last pane absorbs rounding')
  it.todo('overlay command-bar: overlay rect is the full window; overlay archive: overlay rect equals content')
})
