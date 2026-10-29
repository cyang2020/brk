import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  outputDir: '../test-results',
  workers: 1,
  timeout: 60_000,
  reporter: [['list'], ['./markdown-reporter.ts']],
});
