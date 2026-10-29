import { defineConfig } from 'vitest/config';

// Unit tests only; e2e/*.spec.ts belongs to Playwright.
export default defineConfig({
  test: { include: ['src/**/*.test.ts', 'src/**/*.test.tsx'] },
});
