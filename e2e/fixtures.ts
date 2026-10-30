// Playwright fixtures: a static http server for e2e/site/ and the built app, driven through the main process's
// test API (src/shared/test-api.ts: `globalThis.__arc`, installed when ARC_E2E=1). Rules the spike established
// (/tmp/arc-spike/REPORT.md section 5): never pick Playwright pages by index (map Page -> webContents id with CDP
// Target.getTargetInfo + webContents.fromDevToolsTargetId); app shortcuts go through `press` (page.keyboard fires
// neither menu accelerators nor before-input-event); a closed tab is gone when its 'destroyed' event was recorded.
import { _electron, test as base, type ElectronApplication, type Page } from '@playwright/test';
import { existsSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { extname, join } from 'node:path';
import type { Instant, ItemId } from '../src/shared/base';
import type { SurfaceKind } from '../src/shared/bridge';
import type { UiCommand } from '../src/shared/commands';
import { TEST_ENV, type LayerCapture, type NativeLayer, type NativeWindowFacts } from '../src/shared/test-api';
import type { WindowView } from '../src/shared/view';

export { expect } from '@playwright/test';

const ROOT = join(__dirname, '..');
const SITE = join(__dirname, 'site');
const SHOTS = join(ROOT, 'verify', 'shots');
const MIME: Record<string, string> = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.png': 'image/png' };

export type Rgba = readonly [number, number, number, number];

export interface Arc {
  /** The running app; `restart()` replaces it. */
  readonly electronApp: ElectronApplication;
  /** The profile directory (ARC_USER_DATA), kept across `restart()`. */
  readonly userData: string;
  /** The renderer page of one of the first window's surfaces, found by webContents id from `native()`. Waits for the layer to be attached. */
  surface(kind: SurfaceKind): Promise<Page>;
  /** The page of a loaded tab's view. */
  tabPage(tabId: ItemId): Promise<Page>;
  /** The Playwright page whose main-process webContents has this id. */
  pageForWebContentsId(id: number): Promise<Page>;
  /** The WindowView the first window's renderers receive. */
  view(): Promise<WindowView>;
  /** Attached native layers bottom to top, content size, focused webContents. */
  native(): Promise<NativeWindowFacts>;
  /** Same parse-and-dispatch path as a renderer message. */
  dispatch(command: UiCommand): Promise<void>;
  /** A real key press ("CmdOrCtrl+T") through sendInputEvent into the focused webContents. */
  press(accelerator: string): Promise<void>;
  /** Moves the test clock forward and runs the auto-archive sweep; returns the new time. */
  advanceClock(ms: number): Promise<Instant>;
  /** Resolves once the tab webContents' 'destroyed' event was recorded (webContents.close() is asynchronous). */
  waitForDestroyed(webContentsId: number): Promise<void>;
  /**
   * Full-window PNG at verify/shots/<name>.png: every attached layer's capturePage() drawn bottom to top, each
   * inside a rounded clip of its own radius (spike section 6: pixel-equal to the real screen on Linux; excludes what
   * the OS draws, such as traffic lights). Returns the file path.
   */
  compositeScreenshot(name: string): Promise<string>;
  /** [r, g, b, a] at window point (x, y) of one attached layer's capture, e.g. 'chrome' for gradient checks. */
  layerPixel(role: NativeLayer['role'], x: number, y: number): Promise<Rgba>;
  /** [r, g, b, a] at window point (x, y) of a composite written by `compositeScreenshot` (its width is contentSize.width × scale). */
  compositePixel(path: string, x: number, y: number): Promise<Rgba>;
  /**
   * [r, g, b, a] of the REAL X screen at a point in the window's content, captured with desktopCapturer (no permission
   * under Xvfb). Unlike `layerPixel`/`compositePixel` (which read a layer's own capture, or a harness composite) this
   * is what is actually on screen, so it catches a square corner that bookkeeping claims is rounded, or a detached
   * pane that is still drawn.
   */
  screenPixel(x: number, y: number): Promise<Rgba>;
  /** How many views are really attached to the window (win.contentView.children.length). */
  attachedViewCount(): Promise<number>;
  /** flush() state.json, close the app, relaunch on the same profile directory. */
  restart(): Promise<void>;
}

export const test = base.extend<{ arc: Arc }, { siteUrl: string }>({
  siteUrl: [
    async ({}, use) => {
      const server = createServer((req, res) => {
        const path = new URL(req.url ?? '/', 'http://localhost').pathname;
        if (path === '/fail') return req.socket.destroy(); // did-fail-load, for the restore-tolerates-failure check
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
    const userData = await mkdtemp(join(tmpdir(), 'arc-e2e-')); // fresh profile per test; restart() reuses it

    const launch = async (): Promise<ElectronApplication> => {
      const app = await _electron.launch({
        cwd: ROOT,
        args: [...(process.platform === 'linux' ? ['--no-sandbox'] : []), 'out/main/index.js'],
        // env replaces the inherited environment, so keep it (DISPLAY under Xvfb, HOME, PATH).
        env: { ...process.env, [TEST_ENV.enable]: '1', [TEST_ENV.userData]: userData, [TEST_ENV.startUrl]: siteUrl },
      });
      await waitFor(() => app.evaluate(() => globalThis.__arc !== undefined), 'globalThis.__arc');
      await waitFor(() => app.evaluate(() => globalThis.__arc!.native().layers.some((l) => l.role === 'chrome')), 'the chrome layer');
      return app;
    };
    let app = await launch();

    const webContentsIdOf = async (page: Page): Promise<number | null> => {
      try {
        const session = await app.context().newCDPSession(page);
        const { targetInfo } = await session.send('Target.getTargetInfo');
        await session.detach();
        return await app.evaluate(({ webContents }, id) => webContents.fromDevToolsTargetId(id)?.id ?? null, targetInfo.targetId);
      } catch {
        return null; // the page closed while we asked
      }
    };
    // electronApp.windows() lists every view's page in no stable order, so match by webContents id.
    const pageForWebContentsId = (id: number): Promise<Page> =>
      waitFor(async () => {
        for (const page of app.windows()) if ((await webContentsIdOf(page)) === id) return page;
        return undefined;
      }, `a page for webContents ${id}`);

    const native = (): Promise<NativeWindowFacts> => app.evaluate(() => globalThis.__arc!.native());
    const layerFor = (role: NativeLayer['role']): Promise<NativeLayer> =>
      waitFor(async () => (await native()).layers.find((l) => l.role === role), `an attached '${role}' layer`);
    const surface = async (kind: SurfaceKind): Promise<Page> =>
      pageForWebContentsId((await layerFor(kind === 'sidebar' ? 'chrome' : kind)).webContentsId);
    const captureLayers = (): Promise<readonly LayerCapture[]> => app.evaluate(() => globalThis.__arc!.captureLayers());

    // capturePage() of one view never includes the others and BaseWindow has no capturePage, so each layer is
    // captured in main and they are drawn together on a canvas in the chrome page, bottom to top, rounded clips.
    const compositeScreenshot = async (name: string): Promise<string> => {
      const [captures, { contentSize }] = await Promise.all([captureLayers(), native()]);
      const dataUrl = await (await surface('sidebar')).evaluate(async ({ captures, contentSize }) => {
        const load = (src: string) =>
          new Promise<HTMLImageElement>((resolve, reject) => {
            const img = new Image();
            img.onload = () => resolve(img);
            img.onerror = reject;
            img.src = src;
          });
        const k = captures.find((c) => c.layer.role === 'chrome')?.scale ?? 1; // device pixels per window point
        const canvas = document.createElement('canvas');
        canvas.width = Math.round(contentSize.width * k);
        canvas.height = Math.round(contentSize.height * k);
        const g = canvas.getContext('2d')!;
        for (const { layer, pngBase64 } of captures) {
          const img = await load(`data:image/png;base64,${pngBase64}`);
          const b = layer.bounds;
          g.save();
          g.beginPath();
          g.roundRect(b.x * k, b.y * k, b.width * k, b.height * k, layer.radius * k);
          g.clip();
          g.drawImage(img, b.x * k, b.y * k, b.width * k, b.height * k);
          g.restore();
        }
        return canvas.toDataURL('image/png');
      }, { captures, contentSize });
      await mkdir(SHOTS, { recursive: true });
      const path = join(SHOTS, `${name}.png`);
      await writeFile(path, Buffer.from(dataUrl.slice(dataUrl.indexOf(',') + 1), 'base64'));
      return path;
    };

    // Decodes a PNG on a canvas in the chrome page (no PNG decoder in the harness) and reads one device pixel.
    const pngPixel = async (pngBase64: string, deviceX: number, deviceY: number): Promise<Rgba> => {
      const rgba = await (await surface('sidebar')).evaluate(async ({ pngBase64, deviceX, deviceY }) => {
        const img = await new Promise<HTMLImageElement>((resolve, reject) => {
          const el = new Image();
          el.onload = () => resolve(el);
          el.onerror = reject;
          el.src = `data:image/png;base64,${pngBase64}`;
        });
        const canvas = document.createElement('canvas');
        canvas.width = img.width;
        canvas.height = img.height;
        const g = canvas.getContext('2d')!;
        g.drawImage(img, 0, 0);
        return Array.from(g.getImageData(deviceX, deviceY, 1, 1).data);
      }, { pngBase64, deviceX, deviceY });
      return [rgba[0] ?? 0, rgba[1] ?? 0, rgba[2] ?? 0, rgba[3] ?? 0];
    };

    const layerPixel = async (role: NativeLayer['role'], x: number, y: number): Promise<Rgba> => {
      const capture = (await captureLayers()).find((c) => c.layer.role === role);
      if (!capture) throw new Error(`no attached '${role}' layer to read a pixel from`);
      const k = capture.scale;
      return pngPixel(capture.pngBase64, Math.round((x - capture.layer.bounds.x) * k), Math.round((y - capture.layer.bounds.y) * k));
    };

    const compositePixel = async (path: string, x: number, y: number): Promise<Rgba> => {
      const png = await readFile(path);
      const k = png.readUInt32BE(16) / (await native()).contentSize.width; // IHDR width / window width = device pixels per point
      return pngPixel(png.toString('base64'), Math.round(x * k), Math.round(y * k));
    };

    const arc: Arc = {
      get electronApp() {
        return app;
      },
      userData,
      surface,
      tabPage: async (tabId) => {
        const id = await app.evaluate((_, tabId) => globalThis.__arc!.tabWebContentsId(tabId), tabId);
        if (id === null) throw new Error(`tab ${tabId} has no webContents (not loaded)`);
        return pageForWebContentsId(id);
      },
      pageForWebContentsId,
      view: () => app.evaluate(() => globalThis.__arc!.view()),
      native,
      dispatch: (command) => app.evaluate((_, command) => globalThis.__arc!.dispatch(command), command),
      press: (accelerator) => app.evaluate((_, accelerator) => globalThis.__arc!.press(accelerator), accelerator),
      advanceClock: (ms) => app.evaluate((_, ms) => globalThis.__arc!.advanceClock(ms), ms),
      waitForDestroyed: (webContentsId) =>
        waitFor(
          () => app.evaluate((_, id) => globalThis.__arc!.destroyedWebContentsIds().includes(id) || undefined, webContentsId),
          `'destroyed' of webContents ${webContentsId}`,
        ).then(() => undefined),
      compositeScreenshot,
      layerPixel,
      compositePixel,
      screenPixel: (x, y) =>
        app.evaluate(async ({ desktopCapturer, BaseWindow, screen }, { x, y }) => {
          const win = BaseWindow.getAllWindows()[0]!;
          const content = win.getContentBounds();
          const [source] = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: screen.getPrimaryDisplay().size });
          const b = source!.thumbnail.crop({ x: content.x + x, y: content.y + y, width: 1, height: 1 }).toBitmap();
          return [b[2] ?? 0, b[1] ?? 0, b[0] ?? 0, b[3] ?? 0] as const; // BGRA -> RGBA
        }, { x, y }),
      attachedViewCount: () => app.evaluate(({ BaseWindow }) => BaseWindow.getAllWindows()[0]!.contentView.children.length),
      restart: async () => {
        await app.evaluate(() => globalThis.__arc!.flush());
        await app.close();
        app = await launch();
      },
    };

    await use(arc);
    await app.close();
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
