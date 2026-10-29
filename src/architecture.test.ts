/**
 * Dependency rules from docs/design/module-map.md that tsconfig project boundaries cannot express (the composite
 * projects already stop renderers and e2e from importing node-side files: TS6307). Pure functions over
 * (path, content) pairs, run over the real tree and over synthetic inputs, with node:fs and regular expressions
 * only, so the rules cost nothing to run on every `npm test`.
 */
import { readdirSync, readFileSync } from 'node:fs'
import { join, posix, relative, resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const ROOT = resolve(__dirname, '..')

export interface SourceFile {
  /** Repo-relative posix path, e.g. `src/main/app.ts`. */
  readonly path: string
  readonly content: string
}

function listFiles(dir: string): string[] {
  const out: string[] = []
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name)
    if (entry.isDirectory()) out.push(...listFiles(full))
    else if (/\.tsx?$/.test(entry.name)) out.push(full)
  }
  return out
}

export function readTree(): SourceFile[] {
  return [...listFiles(join(ROOT, 'src')), ...listFiles(join(ROOT, 'e2e'))]
    .sort()
    .map((full) => ({ path: relative(ROOT, full).split(/[\\/]/).join('/'), content: readFileSync(full, 'utf8') }))
}

/** Drops block comments and whole-line `//` comments, so a path quoted in prose is not read as an import. */
function stripComments(content: string): string {
  return content.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^[ \t]*\/\/.*$/gm, '')
}

const SPECIFIER_RES: readonly RegExp[] = [
  /\bfrom\s*['"]([^'"]+)['"]/g, // import ... from 'x', export ... from 'x'
  /\bimport\s*['"]([^'"]+)['"]/g, // import 'x'
  /\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)/g, // import('x')
  /\brequire\s*\(\s*['"]([^'"]+)['"]\s*\)/g, // require('x')
]

export function importsOf(file: SourceFile): string[] {
  const code = stripComments(file.content)
  const found = new Set<string>()
  for (const re of SPECIFIER_RES) for (const match of code.matchAll(re)) found.add(match[1]!)
  return [...found]
}

type Target = { readonly spec: string; readonly pkg: string } | { readonly spec: string; readonly path: string }

/** A relative specifier resolved against the importing file (extension-less); anything else is a package. */
function target(file: SourceFile, spec: string): Target {
  if (!spec.startsWith('.')) return { spec, pkg: spec.startsWith('@') ? spec.split('/').slice(0, 2).join('/') : spec.split('/')[0]! }
  return { spec, path: posix.normalize(posix.join(posix.dirname(file.path), spec)) }
}

const under = (path: string, dir: string): boolean => path === dir || path.startsWith(`${dir}/`)
const isTest = (path: string): boolean => /\.test\.tsx?$/.test(path)

/** Single writers (module-map rule 6), checked on comment-stripped text of files under src/. */
const SINGLE_WRITERS: readonly { readonly re: RegExp; readonly what: string; readonly only: readonly string[] }[] = [
  {
    re: /\.(parentId|children)\s*=[^=]|\.children\.(push|splice|unshift|pop|shift|sort|reverse|fill|copyWithin)\s*\(/,
    what: 'a write to parentId or children',
    only: ['src/domain/tree.ts'],
  },
  { re: /\bnew\s+WebContentsView\s*\(/, what: 'new WebContentsView(...)', only: ['src/main/tab-runtime.ts', 'src/main/window-host.ts'] },
  { re: /\bDate\.now\s*\(/, what: 'Date.now()', only: ['src/main/clock.ts'] },
  { re: /(?<![.\w])reduce\s*\(/, what: 'a call of reduce()', only: ['src/main/app.ts', 'src/domain/reduce.ts'] },
]

/** Violations of the module-map rules in one file. Empty means the file is fine. */
export function checkFile(file: SourceFile): string[] {
  const out: string[] = []
  const p = file.path
  const targets = importsOf(file).map((spec) => target(file, spec))
  const internal = targets.filter((t): t is Extract<Target, { path: string }> => 'path' in t)
  const packages = targets.filter((t): t is Extract<Target, { pkg: string }> => 'pkg' in t)
  const allowPackages = (...names: string[]): void => {
    const allowed = new Set(isTest(p) ? [...names, 'vitest'] : names)
    for (const t of packages) if (!allowed.has(t.pkg)) out.push(`${p}: imports package '${t.spec}' (allowed here: ${[...allowed].join(', ') || 'none'})`)
  }
  const allowDirs = (...dirs: string[]): void => {
    for (const t of internal) if (!dirs.some((d) => under(t.path, d))) out.push(`${p}: imports '${t.spec}' outside ${dirs.join(', ')}`)
  }

  // Rules 1, 2, 4, 5: who may import what.
  if (under(p, 'src/shared')) {
    allowPackages('zod')
    allowDirs('src/shared')
  } else if (under(p, 'src/domain')) {
    allowPackages('immer', 'zod')
    allowDirs('src/domain', 'src/shared')
  } else if (under(p, 'src/renderer')) {
    allowPackages('react', 'react-dom')
    allowDirs('src/renderer/common', 'src/shared', p.split('/').slice(0, 3).join('/')) // own bundle directory
  } else if (under(p, 'e2e')) {
    allowDirs('e2e', 'src/shared')
  }

  // Rule 3: outside the domain, only its index is importable.
  if (!under(p, 'src/domain'))
    for (const t of internal)
      if (under(t.path, 'src/domain') && t.path !== 'src/domain' && t.path !== 'src/domain/index')
        out.push(`${p}: imports domain internals '${t.spec}' (only src/domain/index.ts is public)`)

  // Rule 6: single writers.
  if (under(p, 'src') && !isTest(p)) {
    const code = stripComments(file.content)
    for (const { re, what, only } of SINGLE_WRITERS) if (re.test(code) && !only.includes(p)) out.push(`${p}: ${what} may only appear in ${only.join(', ')}`)
  }
  return out
}

describe('architecture', () => {
  const tree = readTree()

  it('scans the real tree under src/ and e2e/', () => {
    expect(tree.length).toBeGreaterThan(50)
    expect(tree.map((f) => f.path)).toContain('src/domain/index.ts')
  })

  it('finds no violation in the real tree', () => {
    expect(tree.flatMap(checkFile)).toEqual([])
  })

  it('flags a main-process file importing domain internals', () => {
    expect(checkFile({ path: 'src/main/foo.ts', content: "import x from '../domain/tree'\n" })).toEqual([
      "src/main/foo.ts: imports domain internals '../domain/tree' (only src/domain/index.ts is public)",
    ])
    expect(checkFile({ path: 'src/main/foo.ts', content: "import type { AppState } from '../domain'\n" })).toEqual([])
  })

  it('flags the domain importing electron or node, and shared importing immer', () => {
    expect(checkFile({ path: 'src/domain/ops/x.ts', content: "import { app } from 'electron'\nimport { join } from 'node:path'\n" })).toHaveLength(2)
    expect(checkFile({ path: 'src/shared/x.ts', content: "import { produce } from 'immer'\n" })).toHaveLength(1)
    expect(checkFile({ path: 'src/shared/x.ts', content: "import { z } from 'zod'\nimport type { Rect } from './base'\n" })).toEqual([])
  })

  it('flags the sidebar and overlay bundles importing each other, or a renderer importing main', () => {
    expect(checkFile({ path: 'src/renderer/sidebar/Row.tsx', content: "import { suggest } from '../overlay/suggest'\n" })).toHaveLength(1)
    expect(checkFile({ path: 'src/renderer/overlay/CommandBar.tsx', content: "import { Row } from '../sidebar/Row'\n" })).toHaveLength(1)
    expect(checkFile({ path: 'src/renderer/overlay/x.ts', content: "import { computeLayout } from '../../main/layout'\n" })).toHaveLength(1)
    expect(checkFile({ path: 'src/renderer/overlay/x.ts', content: "import { useWindowView } from '../common/bridge'\nimport { TID } from '../../shared/testids'\n" })).toEqual([])
  })

  it('flags e2e importing anything but e2e and src/shared', () => {
    expect(checkFile({ path: 'e2e/x.spec.ts', content: "import { createTestApi } from '../src/main/test-api'\n" })).toHaveLength(1)
  })

  it('flags single-writer breaches: parentId, WebContentsView, Date.now, reduce', () => {
    expect(checkFile({ path: 'src/domain/ops/x.ts', content: 'draft.doc.items[id].parentId = other\n' })).toHaveLength(1)
    expect(checkFile({ path: 'src/domain/ops/x.ts', content: 'folder.children.push(id)\n' })).toHaveLength(1)
    expect(checkFile({ path: 'src/domain/tree.ts', content: 'item.parentId = other\nparent.children.splice(0, 1)\n' })).toEqual([])
    expect(checkFile({ path: 'src/main/x.ts', content: 'const v = new WebContentsView()\n' })).toHaveLength(1)
    expect(checkFile({ path: 'src/renderer/common/x.ts', content: 'const t = Date.now()\n' })).toHaveLength(1)
    expect(checkFile({ path: 'src/main/x.ts', content: "const t = reduce(state, input, ctx)\n" })).toHaveLength(1)
    expect(checkFile({ path: 'src/main/x.ts', content: 'const n = list.reduce((a, b) => a + b, 0)\n' })).toEqual([])
  })

  it('ignores specifiers that only appear in comments', () => {
    const content = "/** Imported from '../domain/tree' in prose. */\n// import x from '../domain/tree'\nimport type { AppState } from '../domain'\n"
    expect(checkFile({ path: 'src/main/x.ts', content })).toEqual([])
  })
})
