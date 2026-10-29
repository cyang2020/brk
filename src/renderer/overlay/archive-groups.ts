/** Archive time buckets, pure. Uses the view's `now` (the injected clock), never Date.now(). */
import type { Instant } from '../../shared/base'
import { COPY } from '../../shared/copy'
import type { ArchiveBucket, ArchiveEntryView } from '../../shared/view'

export interface ArchiveGroup {
  readonly bucket: ArchiveBucket
  /** COPY.archive.buckets[bucket]. */
  readonly label: string
  readonly entries: readonly ArchiveEntryView[]
}

/** Display order. COPY.archive.buckets is a `Record` over ArchiveBucket, so this lists every bucket. */
const BUCKETS = Object.keys(COPY.archive.buckets) as readonly ArchiveBucket[]

/** Local midnight `daysBack` calendar days before `t`'s day. setDate keeps the wall clock, so DST days stay whole. */
function localDayStart(t: number, daysBack: number): number {
  const d = new Date(t)
  d.setHours(0, 0, 0, 0)
  d.setDate(d.getDate() - daysBack)
  return d.getTime()
}

/**
 * Local calendar days: today; yesterday; past-week = earlier in the current week (Monday start) but before
 * yesterday; past-month = since local midnight 30 days ago; beyond = older. A future archivedAt counts as today.
 */
export function bucketOf(archivedAt: Instant, now: Instant): ArchiveBucket {
  if (archivedAt >= localDayStart(now, 0)) return 'today'
  if (archivedAt >= localDayStart(now, 1)) return 'yesterday'
  const daysSinceMonday = (new Date(now).getDay() + 6) % 7
  if (archivedAt >= localDayStart(now, daysSinceMonday)) return 'past-week'
  if (archivedAt >= localDayStart(now, 30)) return 'past-month'
  return 'beyond'
}

/** Non-empty groups in bucket order, entries newest first. */
export function groupArchive(entries: readonly ArchiveEntryView[], now: Instant): readonly ArchiveGroup[] {
  const newestFirst = [...entries].sort((a, b) => b.archivedAt - a.archivedAt)
  return BUCKETS.map((bucket) => ({
    bucket,
    label: COPY.archive.buckets[bucket],
    entries: newestFirst.filter((entry) => bucketOf(entry.archivedAt, now) === bucket),
  })).filter((group) => group.entries.length > 0)
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const

/**
 * When an entry was archived, worded for the group it sits in: "3:05 PM" under Today and Yesterday, "Mon 3:05 PM"
 * under Earlier This Week, "Oct 12" further back, "Oct 12, 2025" in another year. Formatted by hand, not with
 * Intl, so the text does not change with the ICU version.
 */
export function archivedWhen(archivedAt: Instant, now: Instant): string {
  const d = new Date(archivedAt)
  const hours = d.getHours() % 12 === 0 ? 12 : d.getHours() % 12
  const time = `${hours}:${String(d.getMinutes()).padStart(2, '0')} ${d.getHours() < 12 ? 'AM' : 'PM'}`
  const bucket = bucketOf(archivedAt, now)
  if (bucket === 'today' || bucket === 'yesterday') return time
  if (bucket === 'past-week') return `${WEEKDAYS[d.getDay()]} ${time}`
  const date = `${MONTHS[d.getMonth()]} ${d.getDate()}`
  return d.getFullYear() === new Date(now).getFullYear() ? date : `${date}, ${d.getFullYear()}`
}
