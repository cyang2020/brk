import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { PANEL_INSET, SIDEBAR_WIDTH } from '../src/shared/layout';
import { expect, test } from './fixtures';

const SHOT = join(__dirname, '..', 'verify', 'shots', 'smoke.png');
const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

test('chrome view shows the sidebar at its full width', async ({ arc }) => {
  const sidebar = (await arc.chromePage()).getByTestId('sidebar');
  await expect(sidebar).toBeVisible();
  expect((await sidebar.boundingBox())?.width).toBe(SIDEBAR_WIDTH);
});

test('preload bridge answers ping through ipcMain', async ({ arc }) => {
  const chrome = await arc.chromePage();
  expect(await chrome.evaluate(() => window.arc.ping())).toBe('pong');
});

test('tab view loads the fixture page', async ({ arc }) => {
  await expect(await arc.activeTabPage()).toHaveTitle('Fixture Home');
});

test('tab view sits right of the sidebar, inset 8px on every side', async ({ arc }) => {
  const { tab, content } = await arc.electronApp.evaluate(() => {
    const { win, tabViews } = globalThis.__arcTest!;
    return { tab: tabViews()[0]!.getBounds(), content: win.getContentBounds() };
  });
  expect(tab.x).toBeGreaterThanOrEqual(260);
  expect(tab).toEqual({
    x: SIDEBAR_WIDTH + PANEL_INSET,
    y: PANEL_INSET,
    width: content.width - SIDEBAR_WIDTH - 2 * PANEL_INSET,
    height: content.height - 2 * PANEL_INSET,
  });
});

test('composite screenshot is written as a full-window PNG', async ({ arc }) => {
  await expect(await arc.activeTabPage()).toHaveTitle('Fixture Home');
  await arc.compositeScreenshot(SHOT);
  const png = await readFile(SHOT);
  const content = await arc.electronApp.evaluate(() => globalThis.__arcTest!.win.getContentBounds());
  expect(png.subarray(0, 8).equals(PNG_SIGNATURE)).toBe(true);
  // IHDR width and height; captures are in device pixels, so at least the window's CSS size.
  expect(png.readUInt32BE(16)).toBeGreaterThanOrEqual(content.width);
  expect(png.readUInt32BE(20)).toBeGreaterThanOrEqual(content.height);
});
