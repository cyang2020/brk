/**
 * state.json on disk: one file, atomic writes, nothing else. Knows bytes and paths, not the format (src/domain/codec.ts
 * owns that). Writes go to `state.json.tmp`, are fsynced, then renamed over `state.json`, so a crash leaves either
 * the old or the new file, never a torn one.
 *
 * Writes are synchronous: the file is a few kilobytes, the debounce bounds them to one per TIMING.saveDebounceMs,
 * and a synchronous write means `flushSync` (before-quit) can never race an asynchronous rename of older text.
 */
import { closeSync, fsyncSync, mkdirSync, openSync, readFileSync, renameSync, writeSync } from 'node:fs'
import { join } from 'node:path'
import { TIMING } from '../shared/constants'

export interface DocStore {
  readonly path: string
  /** File contents, or null when there is no file. */
  read(): string | null
  /** Debounced (TIMING.saveDebounceMs) and coalesced: only the latest text is written; one write in flight at a time. */
  save(json: string): void
  /** Resolves once the latest saved text is on disk. */
  flush(): Promise<void>
  /** Synchronous write of the latest text, for before-quit. */
  flushSync(): void
  /** Renames an unusable file to `state.json.bad-<timestamp>` so a fresh profile does not overwrite it. */
  quarantine(reason: string): void
}

export function openDocStore(directory: string): DocStore {
  const path = join(directory, 'state.json')
  const tmp = `${path}.tmp`
  let pending: string | null = null
  let timer: ReturnType<typeof setTimeout> | null = null

  const writeAtomically = (text: string): void => {
    mkdirSync(directory, { recursive: true })
    const fd = openSync(tmp, 'w')
    try {
      writeSync(fd, text)
      fsyncSync(fd)
    } finally {
      closeSync(fd)
    }
    renameSync(tmp, path)
  }

  const writePending = (): void => {
    if (timer !== null) {
      clearTimeout(timer)
      timer = null
    }
    if (pending === null) return
    const text = pending
    pending = null
    writeAtomically(text)
  }

  return {
    path,
    read(): string | null {
      try {
        return readFileSync(path, 'utf8')
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null
        throw error
      }
    },
    save(json: string): void {
      pending = json
      if (timer === null) timer = setTimeout(writePending, TIMING.saveDebounceMs)
    },
    flush(): Promise<void> {
      writePending()
      return Promise.resolve()
    },
    flushSync(): void {
      writePending()
    },
    quarantine(reason: string): void {
      const stamp = new Date().toISOString().replace(/[:.]/g, '-')
      const target = `${path}.bad-${stamp}`
      try {
        renameSync(path, target)
        console.error(`[arc] state.json could not be used (${reason}); moved to ${target}`)
      } catch (error) {
        console.error(`[arc] state.json could not be used (${reason}) and could not be moved aside: ${String(error)}`)
      }
    },
  }
}
