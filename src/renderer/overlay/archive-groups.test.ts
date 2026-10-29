import { describe, expect, it } from 'vitest'
import type { ArchiveId, Instant } from '../../shared/base'
import type { ArchiveEntryView } from '../../shared/view'
import { archivedWhen, bucketOf, groupArchive } from './archive-groups'

/** Local wall-clock time, so the cases hold in every time zone. Month is 1-based here. */
const at = (y: number, mo: number, d: number, h = 0, mi = 0): Instant => new Date(y, mo - 1, d, h, mi).getTime() as Instant

// 2026-10-29 is a Thursday; that week started on Monday 2026-10-26.
const THURSDAY = at(2026, 10, 29, 15, 0)

describe('bucketOf', () => {
  it.each([
    ['local midnight today', at(2026, 10, 29, 0, 0), 'today'],
    ['a minute before now', at(2026, 10, 29, 14, 59), 'today'],
    ['later today (future)', at(2026, 10, 29, 16, 0), 'today'],
    ['tomorrow (future)', at(2026, 10, 30, 10, 0), 'today'],
    ['one minute before midnight', at(2026, 10, 28, 23, 59), 'yesterday'],
    ['midnight yesterday', at(2026, 10, 28, 0, 0), 'yesterday'],
    ['the day before yesterday', at(2026, 10, 27, 23, 59), 'past-week'],
    ['Monday midnight, start of the week', at(2026, 10, 26, 0, 0), 'past-week'],
    ['Sunday before the week', at(2026, 10, 25, 23, 59), 'past-month'],
    ['local midnight 30 days ago', at(2026, 9, 29, 0, 0), 'past-month'],
    ['just before 30 days ago', at(2026, 9, 28, 23, 59), 'beyond'],
    ['last year', at(2025, 10, 29, 15, 0), 'beyond'],
  ] as const)('%s on Thursday 15:00 -> %s', (_, archivedAt, bucket) => {
    expect(bucketOf(archivedAt, THURSDAY)).toBe(bucket)
  })

  it('on a Monday, Sunday is yesterday and Saturday is past-month (the week has no earlier days)', () => {
    const monday = at(2026, 10, 26, 9, 0)
    expect(bucketOf(at(2026, 10, 25, 12, 0), monday)).toBe('yesterday')
    expect(bucketOf(at(2026, 10, 24, 12, 0), monday)).toBe('past-month')
  })

  it('on a Tuesday, Monday is yesterday and Sunday is past-month', () => {
    const tuesday = at(2026, 10, 27, 9, 0)
    expect(bucketOf(at(2026, 10, 26, 12, 0), tuesday)).toBe('yesterday')
    expect(bucketOf(at(2026, 10, 25, 12, 0), tuesday)).toBe('past-month')
  })
})

function entry(id: string, archivedAt: Instant): ArchiveEntryView {
  return { id: id as ArchiveId, title: id, url: null, faviconUrl: null, archivedAt, reason: 'manual', fromSpaceTitle: null }
}

describe('groupArchive', () => {
  it('returns non-empty groups in bucket order with labels, entries newest first', () => {
    const entries = [
      entry('old', at(2026, 1, 2, 10, 0)),
      entry('today-early', at(2026, 10, 29, 8, 0)),
      entry('yesterday', at(2026, 10, 28, 12, 0)),
      entry('today-late', at(2026, 10, 29, 14, 0)),
      entry('three-weeks', at(2026, 10, 8, 12, 0)),
    ]
    const groups = groupArchive(entries, THURSDAY)
    expect(groups.map((g) => [g.bucket, g.label, g.entries.map((e) => e.id)])).toEqual([
      ['today', 'Today', ['today-late', 'today-early']],
      ['yesterday', 'Yesterday', ['yesterday']],
      ['past-month', 'Past Month', ['three-weeks']],
      ['beyond', 'Beyond', ['old']],
    ])
  })

  it('labels the past-week group "Earlier This Week"', () => {
    expect(groupArchive([entry('tue', at(2026, 10, 27, 9, 0))], THURSDAY).map((g) => g.label)).toEqual(['Earlier This Week'])
  })

  it('returns no groups for no entries', () => {
    expect(groupArchive([], THURSDAY)).toEqual([])
  })
})

describe('archivedWhen', () => {
  it.each([
    ['today, afternoon', at(2026, 10, 29, 15, 5), '3:05 PM'],
    ['today, just after midnight', at(2026, 10, 29, 0, 7), '12:07 AM'],
    ['yesterday, noon', at(2026, 10, 28, 12, 0), '12:00 PM'],
    ['earlier this week', at(2026, 10, 26, 9, 30), 'Mon 9:30 AM'],
    ['this month', at(2026, 10, 12, 18, 0), 'Oct 12'],
    ['another year', at(2025, 12, 31, 18, 0), 'Dec 31, 2025'],
  ] as const)('%s -> %s', (_, archivedAt, text) => {
    expect(archivedWhen(archivedAt, THURSDAY)).toBe(text)
  })
})
