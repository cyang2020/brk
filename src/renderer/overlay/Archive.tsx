/**
 * The archive page. It fills the overlay surface, whose rect is the content card (`archive.anchor`, see
 * OverlayApp.tsx), so it reads as a page in the content area while the sidebar and dock stay usable. Entries grouped
 * by groupArchive(entries, now); each shows favicon, title, display URL, when it was archived, why, and the source
 * space, with restore (TID.archiveRestore(id) -> archive/restore; the overlay stays open). Filter field
 * (COPY.archive.filter) filters locally; Escape in it clears it first. Threshold picker (TID.archiveThreshold) over
 * AUTO_ARCHIVE_AFTER -> settings/auto-archive. Clear (TID.archiveClear) asks inline with COPY.archive.clearConfirm;
 * its confirm (TID.archiveClearConfirm) -> archive/clear, Cancel or Escape backs out. Empty: COPY.archive.empty.
 * Close (TID.archiveClose) and Escape -> overlay/close (Escape is OverlayApp's).
 * data-testid TID.archive, TID.archiveGroup(bucket), TID.archiveEntry(id).
 */
import { useState, type KeyboardEvent, type ReactElement } from 'react'
import type { Instant } from '../../shared/base'
import { AUTO_ARCHIVE_AFTER } from '../../shared/constants'
import { COPY } from '../../shared/copy'
import { TID } from '../../shared/testids'
import { displayUrl } from '../../shared/url'
import type { ArchiveEntryView, ArchiveView } from '../../shared/view'
import { dispatch } from '../common/bridge'
import { archivedWhen, groupArchive } from './archive-groups'
import { CloseIcon, Favicon } from './icons'

export interface ArchiveProps {
  readonly archive: ArchiveView
  readonly now: Instant
}

function matchesFilter(entry: ArchiveEntryView, needle: string): boolean {
  return [entry.title, entry.url ?? '', entry.fromSpaceTitle ?? ''].some((text) => text.toLowerCase().includes(needle))
}

/** Escape inside a control that has its own use for it: run `undo` and keep OverlayApp from closing the archive. */
function escapeTo(undo: () => void) {
  return (e: KeyboardEvent): void => {
    if (e.key !== 'Escape') return
    e.preventDefault()
    undo()
  }
}

function Entry({ entry, now }: { readonly entry: ArchiveEntryView; readonly now: Instant }): ReactElement {
  const meta = [archivedWhen(entry.archivedAt, now), COPY.archive.reasons[entry.reason], entry.fromSpaceTitle].filter(Boolean).join(' · ')
  return (
    <li className="archive-entry" data-testid={TID.archiveEntry(entry.id)}>
      <Favicon url={entry.faviconUrl} />
      <span className="archive-entry-text" title={entry.url ?? undefined}>
        <span className="archive-entry-title">{entry.title}</span>
        {entry.url && <span className="archive-entry-url">{displayUrl(entry.url)}</span>}
      </span>
      <span className="archive-entry-meta">{meta}</span>
      <button
        type="button"
        className="archive-button"
        data-testid={TID.archiveRestore(entry.id)}
        onClick={() => dispatch({ type: 'archive/restore', entryId: entry.id })}
      >
        {COPY.archive.restore}
      </button>
    </li>
  )
}

export function Archive({ archive, now }: ArchiveProps): ReactElement {
  const [filter, setFilter] = useState('')
  const [confirming, setConfirming] = useState(false)
  const needle = filter.trim().toLowerCase()
  const groups = groupArchive(needle === '' ? archive.entries : archive.entries.filter((e) => matchesFilter(e, needle)), now)

  return (
    <div className="archive" data-testid={TID.archive}>
      <header className="archive-header">
        <h1 className="archive-title">{COPY.archive.title}</h1>
        <button
          type="button"
          className="archive-close"
          aria-label={COPY.archive.close}
          title={COPY.archive.close}
          data-testid={TID.archiveClose}
          onClick={() => dispatch({ type: 'overlay/close' })}
        >
          <CloseIcon />
        </button>
      </header>

      <div className="archive-toolbar">
        <input
          type="text"
          className="archive-filter"
          placeholder={COPY.archive.filter}
          aria-label={COPY.archive.filter}
          spellCheck={false}
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          onKeyDown={filter === '' ? undefined : escapeTo(() => setFilter(''))}
        />
        <label className="archive-threshold">
          {COPY.archive.threshold}
          <select
            data-testid={TID.archiveThreshold}
            value={archive.autoArchiveAfter}
            onChange={(e) => {
              const after = AUTO_ARCHIVE_AFTER.find((option) => option === e.target.value)
              if (after) dispatch({ type: 'settings/auto-archive', after })
            }}
          >
            {AUTO_ARCHIVE_AFTER.map((option) => (
              <option key={option} value={option}>
                {COPY.archive.thresholds[option]}
              </option>
            ))}
          </select>
        </label>
        {confirming ? (
          <span className="archive-confirm" role="alertdialog" aria-label={COPY.archive.clearConfirm} onKeyDown={escapeTo(() => setConfirming(false))}>
            <span className="archive-confirm-text">{COPY.archive.clearConfirm}</span>
            <button type="button" className="archive-button" autoFocus onClick={() => setConfirming(false)}>
              {COPY.archive.cancel}
            </button>
            <button
              type="button"
              className="archive-button archive-button-danger"
              data-testid={TID.archiveClearConfirm}
              onClick={() => {
                setConfirming(false)
                dispatch({ type: 'archive/clear' })
              }}
            >
              {COPY.archive.clear}
            </button>
          </span>
        ) : (
          <button
            type="button"
            className="archive-button"
            data-testid={TID.archiveClear}
            disabled={archive.entries.length === 0}
            onClick={() => setConfirming(true)}
          >
            {COPY.archive.clear}
          </button>
        )}
      </div>

      <div className="archive-list">
        {archive.entries.length === 0 ? (
          <p className="archive-empty">{COPY.archive.empty}</p>
        ) : groups.length === 0 ? (
          <p className="archive-empty">{COPY.archive.noMatch}</p>
        ) : (
          groups.map((group) => (
            <section key={group.bucket} className="archive-group" data-testid={TID.archiveGroup(group.bucket)}>
              <h2 className="archive-group-title">{group.label}</h2>
              <ul className="archive-entries">
                {group.entries.map((entry) => (
                  <Entry key={entry.id} entry={entry} now={now} />
                ))}
              </ul>
            </section>
          ))
        )}
      </div>
    </div>
  )
}
