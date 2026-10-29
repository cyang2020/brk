import { describe, expect, it } from 'vitest'
import type { Instant } from '../shared/base'
import { createTestClock, systemClock } from './clock'

describe('clocks', () => {
  it('systemClock reads real time', () => {
    const before = Date.now()
    const now = systemClock.now()
    expect(now).toBeGreaterThanOrEqual(before)
    expect(now).toBeLessThanOrEqual(Date.now())
  })

  it('the test clock is the base clock plus an offset that only grows', () => {
    let base = 1000
    const clock = createTestClock({ now: () => base as Instant })
    expect(clock.now()).toBe(1000)
    expect(clock.advance(500)).toBe(1500)
    expect(clock.now()).toBe(1500)
    expect(clock.advance(-200)).toBe(1500) // never backwards
    expect(clock.advance(Number.NaN)).toBe(1500)
    base = 1010 // real time keeps moving underneath the offset
    expect(clock.now()).toBe(1510)
  })
})
