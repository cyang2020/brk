import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { TIMING } from '../shared/constants'
import { openDocStore } from './store'

let dir: string

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'arc-store-'))
  vi.useFakeTimers()
})

afterEach(() => {
  vi.useRealTimers()
  rmSync(dir, { recursive: true, force: true })
})

describe('openDocStore', () => {
  it('reads null when there is no file, and the text once one was written', () => {
    const store = openDocStore(dir)
    expect(store.read()).toBeNull()
    store.save('{"a":1}')
    vi.advanceTimersByTime(TIMING.saveDebounceMs)
    expect(store.read()).toBe('{"a":1}')
    expect(readdirSync(dir)).toEqual(['state.json']) // no temp file left behind
  })

  it('debounces and writes only the latest text', () => {
    const store = openDocStore(dir)
    store.save('one')
    store.save('two')
    vi.advanceTimersByTime(TIMING.saveDebounceMs - 1)
    expect(existsSync(store.path)).toBe(false)
    store.save('three')
    vi.advanceTimersByTime(1)
    expect(readFileSync(store.path, 'utf8')).toBe('three')
  })

  it('flush writes the pending text now; a later flush with nothing pending changes nothing', async () => {
    const store = openDocStore(dir)
    store.save('pending')
    await store.flush()
    expect(readFileSync(store.path, 'utf8')).toBe('pending')
    writeFileSync(store.path, 'external')
    await store.flush()
    expect(readFileSync(store.path, 'utf8')).toBe('external')
    vi.advanceTimersByTime(TIMING.saveDebounceMs)
    expect(readFileSync(store.path, 'utf8')).toBe('external') // the timer was cleared by flush
  })

  it('flushSync writes the pending text synchronously', () => {
    const store = openDocStore(dir)
    store.save('sync')
    store.flushSync()
    expect(readFileSync(store.path, 'utf8')).toBe('sync')
  })

  it('creates the directory when it is missing', () => {
    const store = openDocStore(join(dir, 'nested', 'profile'))
    store.save('x')
    store.flushSync()
    expect(readFileSync(store.path, 'utf8')).toBe('x')
  })

  it('quarantine moves the file aside and a fresh save does not touch the moved copy', () => {
    const store = openDocStore(dir)
    writeFileSync(store.path, 'garbage')
    const error = vi.spyOn(console, 'error').mockImplementation(() => {})
    store.quarantine('not JSON')
    expect(existsSync(store.path)).toBe(false)
    const bad = readdirSync(dir).filter((name) => name.startsWith('state.json.bad-'))
    expect(bad).toHaveLength(1)
    expect(readFileSync(join(dir, bad[0]!), 'utf8')).toBe('garbage')
    expect(error).toHaveBeenCalledOnce()
    store.save('fresh')
    store.flushSync()
    expect(readFileSync(store.path, 'utf8')).toBe('fresh')
    expect(readFileSync(join(dir, bad[0]!), 'utf8')).toBe('garbage')
    error.mockRestore()
  })

  it('quarantine of a missing file only logs', () => {
    const store = openDocStore(dir)
    const error = vi.spyOn(console, 'error').mockImplementation(() => {})
    store.quarantine('nothing there')
    expect(error).toHaveBeenCalledOnce()
    expect(readdirSync(dir)).toEqual([])
    error.mockRestore()
  })
})
