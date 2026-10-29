// Playwright fixtures: a static http server for e2e/site/ and the built app with page helpers.
import { _electron, test as base, type ElectronApplication, type Page } from '@playwright/test';
import { existsSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { dirname, extname, join } from 'node:path';
import { PANEL_RADIUS } from '../src/shared/layout';

export { expect } from '@playwright/test';

const ROOT = join(__dirname, '..');
const SITE = join(__dirname, 'site');
const MIME: Record<string, string> = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.png': 'image/png' };

export interface Arc {
  electronApp: ElectronApplication;
  /** The chrome view's page (gradient background and sidebar). */
  chromePage(): Promise<Page>;
  /** The Playwright page whose main-process webContents has this id. */
  pageForWebContentsId(id: number): Promise<Page>;
  /** The page of the topmost tab view attached to the window. */
  activeTabPage(): Promise<Page>;
  /** Full-window PNG: chrome view capture with each attached tab view drawn on top in a rounded clip. */
  compositeScreenshot(path: string): Promise<void>;
}

export const test = base.extend<{ arc: Arc }, { siteUrl: string }>({
  siteUrl: [
    async ({}, use) => {
      const server = createServer((req, res) => {
        const path = new URL(req.url ?? '/', 'http://localhost').pathname;
        const file = join(SITE, path === '/' ? 'index.html' : path); // URL() already resolved any ../
        readFile(file).then(
          (body) => res.writeHead(200, { 'content-type': MIME[extname(file)] ?? 'application/octet-stream' }).end(body),
          () => res.writeHead(404).end('not found'),
        );
      });
      await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
      await use(`http://127.0.0.1:${(server.address() as AddressInfo).port}/`);
      await new Promise((resolve) => server.close(resolve));
    },
    { scope: 'worker' },
  ],

  arc: async ({ siteUrl }, use) => {
    if (!existsSync(join(ROOT, 'out/main/index.js'))) throw new Error('out/main/index.js is missing: run `npm run build` first');
    const userData = await mkdtemp(join(tmpdir(), 'arc-e2e-')); // fresh profile per launch
    const electronApp = await _electron.launch({
      cwd: ROOT,
      args: [...(process.platform === 'linux' ? ['--no-sandbox'] : []), `--user-data-dir=${userData}`, 'out/main/index.js'],
      // env replaces the inherited environment, so keep it (DISPLAY under Xvfb, HOME, PATH).
      env: { ...process.env, ARC_TEST: '1', ARC_TEST_URL: siteUrl },
    });
    await waitFor(() => electronApp.evaluate(() => globalThis.__arcTest !== undefined), 'globalThis.__arcTest');

    const webContentsIdOf = async (page: Page): Promise<number | null> => {
      try {
        const session = await electronApp.context().newCDPSession(page);
        const { targetInfo } = await session.send('Target.getTargetInfo');
        await session.detach();
        return await electronApp.evaluate(({ webContents }, id) => webContents.fromDevToolsTargetId(id)?.id ?? null, targetInfo.targetId);
      } catch {
        return null; // the page closed while we asked
      }
    };
    // electronApp.windows() lists every view's page in no stable order, so match by webContents id.
    const pageForWebContentsId = (id: number): Promise<Page> =>
      waitFor(async () => {
        for (const page of electronApp.windows()) if ((await webContentsIdOf(page)) === id) return page;
        return undefined;
      }, `a page for webContents ${id}`);
    const chromePage = async (): Promise<Page> =>
      pageForWebContentsId(await electronApp.evaluate(() => globalThis.__arcTest!.chromeView.webContents.id));
    const activeTabPage = async (): Promise<Page> => {
      const id = await electronApp.evaluate(() => {
        const { win, tabViews } = globalThis.__arcTest!;
        const stack = win.contentView.children;
        return tabViews()
          .filter((tab) => stack.includes(tab))
          .sort((a, b) => stack.indexOf(a) - stack.indexOf(b))
          .at(-1)?.webContents.id;
      });
      if (id === undefined) throw new Error('no tab view is attached to the window');
      return pageForWebContentsId(id);
    };

    // capturePage() of one view never includes the others, and BaseWindow has no capturePage,
    // so capture each view in main and draw them together on a canvas in the chrome page.
    const compositeScreenshot = async (path: string): Promise<void> => {
      const shot = await electronApp.evaluate(async () => {
        const { win, chromeView, tabViews } = globalThis.__arcTest!;
        const stack = win.contentView.children;
        const tabs = tabViews()
          .filter((tab) => stack.includes(tab))
          .sort((a, b) => stack.indexOf(a) - stack.indexOf(b));
        const capture = async (view: Electron.WebContentsView) => (await view.webContents.capturePage()).toDataURL();
        return {
          width: chromeView.getBounds().width,
          background: await capture(chromeView),
          layers: await Promise.all(tabs.map(async (tab) => ({ bounds: tab.getBounds(), png: await capture(tab) }))),
        };
      });
      const dataUrl = await (await chromePage()).evaluate(async ({ width, background, layers, radius }) => {
        const load = (src: string) =>
          new Promise<HTMLImageElement>((resolve, reject) => {
            const img = new Image();
            img.onload = () => resolve(img);
            img.onerror = reject;
            img.src = src;
          });
        const bg = await load(background);
        const k = bg.width / width; // device pixels per CSS pixel
        const canvas = document.createElement('canvas');
        canvas.width = bg.width;
        canvas.height = bg.height;
        const g = canvas.getContext('2d')!;
        g.drawImage(bg, 0, 0);
        for (const { bounds: b, png } of layers) {
          const img = await load(png);
          g.save();
          g.beginPath();
          g.roundRect(b.x * k, b.y * k, b.width * k, b.height * k, radius * k);
          g.clip();
          g.drawImage(img, b.x * k, b.y * k, b.width * k, b.height * k);
          g.restore();
        }
        return canvas.toDataURL('image/png');
      }, { ...shot, radius: PANEL_RADIUS });
      await mkdir(dirname(path), { recursive: true });
      await writeFile(path, Buffer.from(dataUrl.slice(dataUrl.indexOf(',') + 1), 'base64'));
    };

    await use({ electronApp, chromePage, pageForWebContentsId, activeTabPage, compositeScreenshot });
    await electronApp.close();
    await rm(userData, { recursive: true, force: true });
  },
});

async function waitFor<T>(probe: () => Promise<T | undefined | false>, what: string, timeoutMs = 10_000): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const value = await probe().catch(() => undefined);
    if (value !== undefined && value !== false) return value;
    if (Date.now() > deadline) throw new Error(`timed out after ${timeoutMs}ms waiting for ${what}`);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}
