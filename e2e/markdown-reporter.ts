// Writes verify/REPORT.md: one PASS / FAIL / SKIPPED line per test, from Playwright's own results.
import type { FullResult, Reporter, Suite } from '@playwright/test/reporter';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const LABEL = { expected: 'PASS', unexpected: 'FAIL', flaky: 'FLAKY', skipped: 'SKIPPED' } as const;

export default class MarkdownReporter implements Reporter {
  private suite: Suite | undefined;

  onBegin(_config: unknown, suite: Suite): void {
    this.suite = suite;
  }

  onEnd(result: FullResult): void {
    const lines = (this.suite?.allTests() ?? []).map((test) => {
      const last = test.results.at(-1);
      const error = test.outcome() === 'unexpected' && last?.error?.message ? ` — ${last.error.message.split('\n')[0]}` : '';
      return `- ${LABEL[test.outcome()]} ${test.titlePath().filter(Boolean).join(' › ')}${error}`.replace(/\u001b\[[\d;]*m/g, '');
    });
    const header = `# E2E report\n\n${result.startTime.toISOString()} · ${process.platform}/${process.arch} · ${result.status} in ${(result.duration / 1000).toFixed(1)}s\n\n`;
    const dir = join(__dirname, '..', 'verify');
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'REPORT.md'), header + lines.join('\n') + '\n');
  }
}
