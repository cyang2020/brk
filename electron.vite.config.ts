import { resolve } from 'node:path';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'electron-vite';

// Output: out/main/index.js, out/preload/index.js (CommonJS, required by sandbox: true),
// out/renderer/chrome/index.html. Add more renderer pages as extra inputs.
export default defineConfig({
  main: {},
  preload: {},
  renderer: {
    plugins: [react()],
    build: {
      rolldownOptions: {
        input: { chrome: resolve('src/renderer/chrome/index.html') },
      },
    },
  },
});
