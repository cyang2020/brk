import { resolve } from 'node:path';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'electron-vite';

// Output: out/main/index.js, out/preload/index.js (CommonJS, required by sandbox: true), and two renderer pages:
// out/renderer/sidebar/index.html (serves the `sidebar` and `floating-sidebar` surfaces) and
// out/renderer/overlay/index.html (serves the command bar and the archive). See src/shared/bridge.ts.
export default defineConfig({
  main: {},
  preload: {},
  renderer: {
    plugins: [react()],
    build: {
      rolldownOptions: {
        input: {
          sidebar: resolve('src/renderer/sidebar/index.html'),
          overlay: resolve('src/renderer/overlay/index.html'),
        },
      },
    },
  },
});
