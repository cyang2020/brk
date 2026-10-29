<img src="assets/icon.svg" width="64" height="64" alt="">

# Brk

An Arc-style browser on Electron 45. Created in [T3 Code](https://t3.codes).

The design (`docs/design/rationale.md`, `docs/design/module-map.md`) and the typed skeleton under `src/` are the
contract four implementation workers fill in; function bodies are `throw new Error('not implemented')` until then.

## Develop and verify

```sh
npm install
npm run dev          # open the app with hot reload (needs a desktop session)
npm run typecheck    # strict tsc for main + preload + domain, renderers, e2e (three composite projects)
npm test             # vitest unit tests (src/**/*.test.ts): architecture rules now, domain tests as W1 fills them
npm run build        # electron-vite -> out/
npm run e2e          # Playwright against out/ (run npm run build first)
npm run e2e:docker   # build + e2e on Linux/Xvfb in Docker; writes verify/REPORT.md and verify/shots/
```

`e2e/arc.spec.ts` holds the ten scenarios as `test.skip` stubs until the main process can launch; the report lists
them as SKIPPED.
