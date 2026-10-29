/**
 * The archive page. It fills the overlay surface, whose rect is the content card (`archive.anchor`, see
 * OverlayApp.tsx), so it reads as a page in the content area while the sidebar and dock stay usable. Entries grouped
 * by groupArchive(entries, now); each shows favicon, title, source space and time, with restore
 * (TID.archiveRestore(id) -> archive/restore; the overlay stays open). Filter field (COPY.archive.filter) filters
 * locally. Threshold picker (TID.archiveThreshold) over AUTO_ARCHIVE_AFTER -> settings/auto-archive. Clear
 * (TID.archiveClear) confirms with COPY.archive.clearConfirm -> archive/clear. Empty: COPY.archive.empty.
 * data-testid TID.archive, TID.archiveGroup(bucket), TID.archiveEntry(id).
 */
import type { ReactElement } from 'react'
import type { Instant } from '../../shared/base'
import type { ArchiveView } from '../../shared/view'

export interface ArchiveProps {
  readonly archive: ArchiveView
  readonly now: Instant
}

export function Archive(props: ArchiveProps): ReactElement {
  throw new Error('not implemented')
}
