/**
 * Arc's command bar. placement 'center' (Cmd+T, new split pane): a card LAYOUT.commandBar.width wide, centered in
 * `anchor` at topFraction. placement 'pill' (Cmd+L): the card's input row sits on the URL pill (`anchor`'s origin and
 * height) and the card widens to the right toward LAYOUT.commandBar.width so results stay readable, with
 * initialQuery selected.
 *
 * Query text is local state (single writer: this input). Results = suggest(query, bar, platform); Up/Down move the
 * highlight with wraparound, the pointer moves it too, Enter or a click dispatches commandFor(highlighted). Escape
 * and clicks outside the card are OverlayApp's. The query starts as `bar.initialQuery`, selected, with the input
 * focused, on mount; OverlayApp keys this component by `bar.openId`, so a new opening (including Cmd+L replacing an
 * open Cmd+T bar) mounts a fresh one, and page events and clock ticks, which re-project with the same openId, never
 * clobber what the user typed. `rev` is not consulted. data-testid TID.commandBar, TID.commandBarInput,
 * TID.commandBarResult(i).
 */
import { useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type KeyboardEvent, type ReactElement, type ReactNode } from 'react'
import { ACTIONS } from '../../shared/actions'
import type { Platform } from '../../shared/base'
import { LAYOUT } from '../../shared/constants'
import { COPY } from '../../shared/copy'
import { TID } from '../../shared/testids'
import { displayUrl } from '../../shared/url'
import type { CommandBarView } from '../../shared/view'
import { dispatch } from '../common/bridge'
import { ClockIcon, CommandIcon, Favicon, GlobeIcon, SearchIcon } from './icons'
import { commandFor, suggest, type Suggestion } from './suggest'

export interface CommandBarProps {
  readonly bar: CommandBarView
  readonly platform: Platform
}

/** GUESS. Space kept between a centered card and the content card's edges, and below any card. */
const EDGE = 24

function cardStyle(bar: CommandBarView): CSSProperties {
  const { anchor } = bar
  if (bar.placement === 'pill') {
    const room = window.innerWidth - anchor.x - LAYOUT.contentInset
    const width = Math.max(anchor.width, Math.min(LAYOUT.commandBar.width, room))
    return { left: anchor.x, top: anchor.y, width, maxHeight: `calc(100vh - ${anchor.y + LAYOUT.contentInset}px)` }
  }
  const width = Math.max(0, Math.min(LAYOUT.commandBar.width, anchor.width - 2 * EDGE))
  const top = anchor.y + anchor.height * LAYOUT.commandBar.topFraction
  return { left: anchor.x + (anchor.width - width) / 2, top, width, maxHeight: `calc(100vh - ${top + EDGE}px)` }
}

interface RowParts {
  readonly icon: ReactNode
  readonly title: ReactNode
  readonly detail: string | null
  readonly hint: ReactNode
}

const urlText = (url: string): string => (url === '' ? '' : displayUrl(url))

function rowParts(s: Suggestion): RowParts {
  switch (s.kind) {
    case 'switch': {
      const where = s.tab.inCurrentSpace ? null : s.tab.spaceTitle
      return {
        icon: <Favicon url={s.tab.faviconUrl} />,
        title: s.tab.title,
        detail: [where, urlText(s.tab.url)].filter(Boolean).join(' · ') || null,
        hint: <span className="result-hint result-hint-switch">{COPY.commandBar.switchToTab}</span>,
      }
    }
    case 'open':
      return s.typed.kind === 'search'
        ? { icon: <SearchIcon />, title: <><span className="result-verb">{COPY.commandBar.searchVerb}</span> {s.typed.query}</>, detail: null, hint: null }
        : { icon: <GlobeIcon />, title: <><span className="result-verb">{COPY.commandBar.openVerb}</span> {urlText(s.typed.url)}</>, detail: null, hint: null }
    case 'history':
      return { icon: <ClockIcon />, title: s.entry.title || urlText(s.entry.url), detail: urlText(s.entry.url), hint: null }
    case 'action':
      return {
        icon: <CommandIcon />,
        title: ACTIONS[s.actionId].label,
        detail: null,
        hint: s.shortcut === null ? null : <kbd className="result-hint">{s.shortcut}</kbd>,
      }
  }
}

export function CommandBar({ bar, platform }: CommandBarProps): ReactElement {
  const [query, setQuery] = useState(bar.initialQuery)
  const [highlight, setHighlight] = useState(0)
  const input = useRef<HTMLInputElement>(null)
  const results = useMemo(() => suggest(query, bar, platform), [query, bar, platform])
  const active = Math.min(highlight, results.length - 1)

  useLayoutEffect(() => {
    input.current?.focus()
    input.current?.select()
  }, [])

  const run = (s: Suggestion): void => dispatch(commandFor(s))

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>): void => {
    if (e.nativeEvent.isComposing) return
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      if (results.length === 0) return
      const step = e.key === 'ArrowDown' ? 1 : -1
      setHighlight((active + step + results.length) % results.length)
    } else if (e.key === 'Enter') {
      e.preventDefault()
      const s = results[active]
      if (s && !e.repeat) run(s)
    }
  }

  return (
    <div
      className="command-bar"
      data-testid={TID.commandBar}
      data-placement={bar.placement}
      style={cardStyle(bar)}
      // Keep the caret in the input when the card's padding or a row is pressed.
      onMouseDown={(e) => {
        if (e.target !== input.current) e.preventDefault()
      }}
    >
      <input
        ref={input}
        className="command-bar-input"
        data-testid={TID.commandBarInput}
        style={bar.placement === 'pill' ? { height: bar.anchor.height } : undefined}
        type="text"
        role="combobox"
        aria-expanded={results.length > 0}
        aria-controls="command-bar-results"
        aria-activedescendant={active >= 0 ? TID.commandBarResult(active) : undefined}
        placeholder={COPY.urlPlaceholder}
        spellCheck={false}
        autoComplete="off"
        value={query}
        onChange={(e) => {
          setQuery(e.target.value)
          setHighlight(0)
        }}
        onKeyDown={onKeyDown}
      />
      {results.length > 0 && (
        <ul className="command-bar-results" id="command-bar-results" role="listbox">
          {results.map((s, i) => {
            const parts = rowParts(s)
            return (
              <li
                key={i}
                id={TID.commandBarResult(i)}
                className="result"
                role="option"
                aria-selected={i === active}
                data-testid={TID.commandBarResult(i)}
                data-kind={s.kind}
                data-selected={i === active}
                onMouseMove={() => {
                  if (i !== active) setHighlight(i)
                }}
                onClick={() => run(s)}
              >
                <span className="result-icon">{parts.icon}</span>
                <span className="result-title">{parts.title}</span>
                {parts.detail && <span className="result-detail">{parts.detail}</span>}
                {parts.hint}
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
