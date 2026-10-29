/** Archive time buckets, pure. Uses the view's `now` (the injected clock), never Date.now(). */
import type { Instant } from '../../shared/base'
import type { ArchiveBucket, ArchiveEntryView } from '../../shared/view'

export interface ArchiveGroup {
  readonly bucket: ArchiveBucket
  /** COPY.archive.buckets[bucket]. */
  readonly label: string
  readonly entries: readonly ArchiveEntryView[]
}

/**
 * Local calendar days: today; yesterday; past-week = earlier in the current week (Monday start) but before
 * yesterday; past-month = within 30 days; beyond = older. A future archivedAt counts as today.
 */
export function bucketOf(archivedAt: Instant, now: Instant): ArchiveBucket {
  throw new Error('not implemented')
}

/** Non-empty groups in bucket order, entries newest first. */
export function groupArchive(entries: readonly ArchiveEntryView[], now: Instant): readonly ArchiveGroup[] {
  throw new Error('not implemented')
}
