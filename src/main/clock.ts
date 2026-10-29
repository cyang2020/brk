/** The injected clock. Domain time comes only from here, through `Ctx.now` and `projectWindow(now)`. */
import type { Instant } from '../shared/base'

export interface Clock {
  now(): Instant
}

/** Real time plus an offset that only moves forward. Real time keeps page loads and debounces honest during e2e. */
export interface TestClock extends Clock {
  advance(ms: number): Instant
}

export const systemClock: Clock = {
  now: () => Date.now() as Instant,
}

export function createTestClock(base: Clock = systemClock): TestClock {
  let offset = 0
  const now = (): Instant => (base.now() + offset) as Instant
  return {
    now,
    advance(ms: number): Instant {
      if (Number.isFinite(ms) && ms > 0) offset += ms
      return now()
    },
  }
}
