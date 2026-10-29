/**
 * Arc's command bar. placement 'center' (Cmd+T, new split pane): a card LAYOUT.commandBar.width wide, centered in
 * `anchor` at topFraction. placement 'pill' (Cmd+L): the input sits exactly over `anchor` (the URL pill) and
 * results drop below it, with initialQuery selected.
 *
 * Query text is local state (single writer: this input). Results = suggest(query, bar, platform); Up/Down move the
 * selection, Enter dispatches commandFor(selected), Esc dispatches overlay/close. The input autofocuses and the
 * query resets to `bar.initialQuery` on mount and whenever `bar.openId` changes (a new opening, including Cmd+L
 * replacing an open Cmd+T bar); page events and clock ticks re-project the view with the same openId, so they never
 * clobber what the user typed. `rev` is not consulted. data-testid TID.commandBar, TID.commandBarInput,
 * TID.commandBarResult(i).
 */
import type { ReactElement } from 'react'
import type { Platform } from '../../shared/base'
import type { CommandBarView } from '../../shared/view'

export interface CommandBarProps {
  readonly bar: CommandBarView
  readonly platform: Platform
}

export function CommandBar(props: CommandBarProps): ReactElement {
  throw new Error('not implemented')
}
