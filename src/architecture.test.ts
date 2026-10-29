/**
 * Dependency rules that tsconfig project boundaries cannot express (docs/design/module-map.md). Scans import
 * specifiers of every source file; the build's typecheck covers the renderer -> node boundary (TS6307).
 */
import { describe, it } from 'vitest'

describe('architecture', () => {
  it.todo('src/shared imports only src/shared and zod')
  it.todo('src/domain imports only src/domain, src/shared, immer and zod (no electron, no node:*)')
  it.todo('outside src/domain, imports of src/domain go through src/domain/index.ts')
  it.todo('only src/domain/tree.ts assigns parentId or children')
  it.todo('src/renderer/sidebar and src/renderer/overlay never import each other')
  it.todo('only src/main/tab-runtime.ts and src/main/window-host.ts construct WebContentsView')
  it.todo('Date.now() appears only in src/main/clock.ts')
  it.todo('domain handler groups in src/domain/ops are disjoint')
})
