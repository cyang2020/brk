<img src="assets/icon.svg" width="64" height="64" alt="">

# Brk

Created in [T3 Code](https://t3.codes).

## Develop and verify

```sh
npm install
npm run dev          # open the app with hot reload (needs a desktop session)
npm run typecheck    # strict tsc for main + preload, renderer, e2e
npm test             # vitest unit tests (src/**/*.test.ts)
npm run build        # electron-vite -> out/
npm run e2e          # Playwright against out/ (run npm run build first)
npm run e2e:docker   # build + e2e on Linux/Xvfb in Docker; writes verify/REPORT.md and verify/shots/
```
