/**
 * state.json on disk: one file, atomic writes, nothing else. Knows bytes and paths, not the format (src/domain/codec.ts
 * owns that). Writes go to `state.json.tmp`, are fsynced, then renamed over `state.json`, so a crash leaves either
 * the old or the new file, never a torn one.
 */

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
  throw new Error('not implemented')
}
