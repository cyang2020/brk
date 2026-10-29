/**
 * Command bar ranking, pure. Sources (Arc's ASE2.SourceType subset): searchOrNavigateWhatYouTyped, open tabs
 * (sidebar), history, and actions (Arc's "type travel": menu items searchable by name).
 */
import type { Platform } from '../../shared/base'
import type { ActionId } from '../../shared/actions'
import type { UiCommand } from '../../shared/commands'
import type { TypedInput } from '../../shared/url'
import type { CommandBarView, HistoryCandidate, SwitchCandidate } from '../../shared/view'

export type Suggestion =
  | { readonly kind: 'open'; readonly input: string; readonly typed: TypedInput }
  | { readonly kind: 'switch'; readonly tab: SwitchCandidate }
  | { readonly kind: 'history'; readonly entry: HistoryCandidate }
  | { readonly kind: 'action'; readonly actionId: ActionId; readonly shortcut: string | null }

/**
 * Empty query: open tabs by recency (focused excluded), then a few history entries. Otherwise: "open what you
 * typed" first (resolveTypedInput), then switch-to-tab, history and palette actions matched by case-insensitive
 * substring on title/url/label, word-start matches ranked first. At most 8 rows. shortcut = formatAccelerator.
 */
export function suggest(query: string, bar: CommandBarView, platform: Platform): readonly Suggestion[] {
  throw new Error('not implemented')
}

/**
 * The one place a suggestion becomes a command:
 * open -> commandBar/submit { input }, history -> commandBar/submit { input: url },
 * switch -> tab/focus { tabId }, action -> ACTIONS[actionId].command (the reducer closes the overlay first).
 */
export function commandFor(suggestion: Suggestion): UiCommand {
  throw new Error('not implemented')
}
