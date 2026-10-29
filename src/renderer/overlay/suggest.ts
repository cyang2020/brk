/**
 * Command bar ranking, pure. Sources (Arc's ASE2.SourceType subset): open tabs (sidebar), searchOrNavigateWhatYouTyped,
 * history, and actions (Arc's "type travel": menu items searchable by name).
 */
import { ACTIONS, paletteActions, type ActionId, type ActionSpec } from '../../shared/actions'
import { formatAccelerator } from '../../shared/accelerator'
import type { Platform } from '../../shared/base'
import type { UiCommand } from '../../shared/commands'
import { resolveTypedInput, type TypedInput } from '../../shared/url'
import type { CommandBarView, HistoryCandidate, SwitchCandidate } from '../../shared/view'

export type Suggestion =
  | { readonly kind: 'open'; readonly input: string; readonly typed: TypedInput }
  | { readonly kind: 'switch'; readonly tab: SwitchCandidate }
  | { readonly kind: 'history'; readonly entry: HistoryCandidate }
  | { readonly kind: 'action'; readonly actionId: ActionId; readonly shortcut: string | null }

/** Our choice. Rows the bar shows at most. */
export const MAX_SUGGESTIONS = 8
/** Our choice. Per-source caps, so one source cannot push the others out of the rows. */
const CAP = { tabs: 3, history: 3, actions: 3, emptyTabs: 5, emptyHistory: 3 } as const

/** 0 = `needle` starts a word somewhere in one of the texts, 1 = it appears only mid-word, null = no match. */
function matchRank(needle: string, texts: readonly string[]): 0 | 1 | null {
  let rank: 0 | 1 | null = null
  for (const text of texts) {
    const hay = text.toLowerCase()
    for (let i = hay.indexOf(needle); i >= 0; i = hay.indexOf(needle, i + 1)) {
      if (i === 0 || !/[\p{L}\p{N}]/u.test(hay[i - 1] ?? '')) return 0
      rank = 1
    }
  }
  return rank
}

/** Items matching `needle`, word-start matches first, otherwise in their given order. */
function matching<T>(items: readonly T[], needle: string, texts: (item: T) => readonly string[]): T[] {
  return items
    .map((item) => ({ item, rank: matchRank(needle, texts(item)) }))
    .filter((m): m is { item: T; rank: 0 | 1 } => m.rank !== null)
    .sort((a, b) => a.rank - b.rank)
    .map((m) => m.item)
}

/** Newest visit first, one entry per URL, skipping URLs in `exclude`. */
function recentHistory(history: readonly HistoryCandidate[], exclude: ReadonlySet<string>): HistoryCandidate[] {
  const seen = new Set(exclude)
  const out: HistoryCandidate[] = []
  for (const entry of [...history].sort((a, b) => b.visitedAt - a.visitedAt)) {
    if (seen.has(entry.url)) continue
    seen.add(entry.url)
    out.push(entry)
  }
  return out
}

const switchRow = (tab: SwitchCandidate): Suggestion => ({ kind: 'switch', tab })
const historyRow = (entry: HistoryCandidate): Suggestion => ({ kind: 'history', entry })

/**
 * Empty query: open tabs in the view's order (focused first, then most recent; the focused tab is left out), then
 * a few history entries. Otherwise, in this order: open tabs whose title or URL matches ("Switch to Tab"), the
 * "open what you typed" row (resolveTypedInput), history, palette actions by label. Matching is a case-insensitive
 * substring; within each source, word-start matches come first. History never repeats an open tab's URL or the
 * typed URL. At most MAX_SUGGESTIONS rows. An action's shortcut is formatAccelerator of its first key.
 */
export function suggest(query: string, bar: CommandBarView, platform: Platform): readonly Suggestion[] {
  const text = query.trim()
  const tabs = bar.tabs.filter((tab) => !tab.isFocused)
  const openUrls = new Set(bar.tabs.map((tab) => tab.url))
  if (text === '') {
    const history = recentHistory(bar.history, openUrls).slice(0, CAP.emptyHistory)
    return [...tabs.slice(0, CAP.emptyTabs).map(switchRow), ...history.map(historyRow)].slice(0, MAX_SUGGESTIONS)
  }
  const needle = text.toLowerCase()
  const typed = resolveTypedInput(text)
  if (typed?.kind === 'url') openUrls.add(typed.url)
  const switches = matching(tabs, needle, (tab) => [tab.title, tab.url]).slice(0, CAP.tabs)
  const history = matching(recentHistory(bar.history, openUrls), needle, (entry) => [entry.title, entry.url]).slice(0, CAP.history)
  const actions = matching(paletteActions(), needle, (id) => [ACTIONS[id].label]).slice(0, CAP.actions)
  return [
    ...switches.map(switchRow),
    ...(typed ? [{ kind: 'open', input: text, typed } as const] : []),
    ...history.map(historyRow),
    ...actions.map((actionId): Suggestion => {
      const spec: ActionSpec = ACTIONS[actionId]
      const key = spec.keys[0]
      return { kind: 'action', actionId, shortcut: key === undefined ? null : formatAccelerator(key, platform) }
    }),
  ].slice(0, MAX_SUGGESTIONS)
}

/**
 * The one place a suggestion becomes a command:
 * open -> commandBar/submit { input }, history -> commandBar/submit { input: url },
 * switch -> tab/focus { tabId }, action -> ACTIONS[actionId].command (the reducer closes the overlay first).
 */
export function commandFor(suggestion: Suggestion): UiCommand {
  switch (suggestion.kind) {
    case 'open':
      return { type: 'commandBar/submit', input: suggestion.input }
    case 'history':
      return { type: 'commandBar/submit', input: suggestion.entry.url }
    case 'switch':
      return { type: 'tab/focus', tabId: suggestion.tab.tabId }
    case 'action':
      return ACTIONS[suggestion.actionId].command
  }
}
