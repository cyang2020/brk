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
  now: () => {
    throw new Error('not implemented')
  },
}

export function createTestClock(base: Clock = systemClock): TestClock {
  throw new Error('not implemented')
}
