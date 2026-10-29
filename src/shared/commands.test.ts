import { describe, expect, it } from 'vitest'
import { parseUiCommand } from './commands'

describe('parseUiCommand', () => {
  it('accepts a valid command and returns it', () => {
    expect(parseUiCommand({ type: 'tab/toggle-pin', target: 'focused' })).toEqual({ ok: true, command: { type: 'tab/toggle-pin', target: 'focused' } })
  })

  it('strips unknown keys', () => {
    expect(parseUiCommand({ type: 'sidebar/toggle', extra: 1 })).toEqual({ ok: true, command: { type: 'sidebar/toggle' } })
  })

  it('rejects an unknown type, a wrong field and a non-object with a message', () => {
    for (const raw of [{ type: 'tab/explode' }, { type: 'sidebar/resize', width: 'wide' }, null, 'tab/close']) {
      const parsed = parseUiCommand(raw)
      expect(parsed.ok).toBe(false)
      if (!parsed.ok) expect(parsed.error.length).toBeGreaterThan(0)
    }
  })
})
