/**
 * Permanent regression scenarios for the interrogate findings, adapted from the adversaries' probes and driven through
 * the same harness as arc.spec.ts. Each asserts the fixed behaviour against the real app on Linux/Xvfb.
 */
import { TID } from '../src/shared/testids';
import { THEME_PRESETS, themeFromPrimary } from '../src/shared/theme';
import type { RowView, TabRowView } from '../src/shared/view';
import { expect, test, type Arc } from './fixtures';

const theme = themeFromPrimary(THEME_PRESETS.drab[8]!);
const HOUR = 3_600_000;
const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));
const tabRows = (rows: readonly RowView[]): TabRowView[] => rows.filter((r): r is TabRowView => r.kind === 'tab');
const todayIds = async (arc: Arc): Promise<string[]> => (await arc.view()).space.today.rows.map((r) => r.id);
const currentId = async (arc: Arc): Promise<string | null> => {
  const v = await arc.view();
  return [...tabRows(v.space.today.rows), ...tabRows(v.space.pinned.rows), ...v.favorites.tiles].find((r) => r.status === 'current')?.id ?? null;
};
const panesConsistent = async (arc: Arc): Promise<boolean> => {
  const [facts, view] = await Promise.all([arc.native(), arc.view()]);
  const n = facts.layers.filter((l) => l.role === 'pane').map((l) => ({ tabId: l.tabId, rect: l.bounds }));
  const v = view.content.panes.map((p) => ({ tabId: p.tabId, rect: p.rect }));
  return JSON.stringify(n) === JSON.stringify(v);
};

async function openTab(arc: Arc, url: string): Promise<TabRowView> {
  const before = await todayIds(arc);
  await arc.press('CmdOrCtrl+T');
  const overlay = await arc.surface('overlay');
  const input = overlay.getByTestId(TID.commandBarInput);
  await expect(input).toBeVisible();
  await input.fill(url);
  await overlay.keyboard.press('Enter');
  await expect.poll(() => todayIds(arc)).toHaveLength(before.length + 1);
  return tabRows((await arc.view()).space.today.rows).find((r) => !before.includes(r.id))!;
}

/**
 * Ctrl+Tab as a real keyboard delivers it: Control+Tab down to the focused page, then the ups to whatever has focus
 * after the switch. Each hold sends its own Control keyDown, which commits any cycle the previous hold left pending
 * (its keyUp can land on a view that is no longer focused and be lost).
 */
async function ctrlTab(arc: Arc): Promise<void> {
  const send = (events: { type: 'keyDown' | 'keyUp'; keyCode: string; modifiers: 'control'[] }[]): Promise<number> =>
    arc.electronApp.evaluate(({ webContents }, events) => {
      const id = globalThis.__arc!.native().focusedWebContentsId!;
      for (const e of events) webContents.fromId(id)!.sendInputEvent(e);
      return id;
    }, events);
  await send([{ type: 'keyDown', keyCode: 'Control', modifiers: ['control'] }, { type: 'keyDown', keyCode: 'Tab', modifiers: ['control'] }]);
  await sleep(300);
  await send([{ type: 'keyUp', keyCode: 'Tab', modifiers: ['control'] }, { type: 'keyUp', keyCode: 'Control', modifiers: [] }]);
  await sleep(200);
}

// Finding 1 is covered by unit tests (the e2e repro spawns a second Electron instance and runs well over 10s).

test('finding 2: with the sidebar hidden, peeking the left edge keeps the archive open', async ({ arc }) => {
  await arc.press('CmdOrCtrl+S');
  await expect.poll(async () => (await arc.view()).sidebar.visible).toBe(false);
  await arc.dispatch({ type: 'archive/open' });
  await expect.poll(async () => (await arc.view()).overlay?.kind).toBe('archive');
  await (await arc.surface('sidebar')).getByTestId(TID.peekZone).hover();
  await expect.poll(async () => (await arc.view()).sidebar.peek).toBe(true);
  expect((await arc.view()).overlay?.kind).toBe('archive'); // not closed by the peek
});

test('finding 3: a Ctrl+click (background) link opens a Today tab that loads', async ({ arc }) => {
  const home = tabRows((await arc.view()).space.today.rows)[0]!;
  const page = await arc.tabPage(home.id);
  await expect(page).toHaveTitle('Fixture Home');
  await page.click('a', { modifiers: ['Control'] });
  await expect.poll(() => todayIds(arc)).toHaveLength(2);
  const row = tabRows((await arc.view()).space.today.rows).find((r) => r.id !== home.id)!;
  expect(await currentId(arc)).toBe(home.id); // focus stays on the opener
  await expect.poll(async () => tabRows((await arc.view()).space.today.rows).find((r) => r.id === row.id)?.loaded).toBe(true);
  await expect(await arc.tabPage(row.id)).toHaveTitle('Fixture Page 2'); // it really loaded in the background
});

test('finding 5: a tab left with Ctrl+Tab after 11h is not archived an hour later', async ({ arc, siteUrl }) => {
  const b = await openTab(arc, `${siteUrl}page2.html`); // the start tab goes idle; B is shown from T0
  await expect(await arc.tabPage(b.id)).toHaveTitle('Fixture Page 2');
  await arc.advanceClock(11 * HOUR);
  await arc.press('Ctrl+Tab'); // back to the start tab: B leaves the screen
  await expect.poll(() => currentId(arc)).not.toBe(b.id);
  await arc.advanceClock(HOUR + 60_000); // the sweep commits the pending walk first, stamping B, so B is only 0 idle
  await sleep(200);
  expect(await todayIds(arc)).toContain(b.id);
});

test('finding 5: a tab dragged to another space after 13h is not archived by the next sweep', async ({ arc, siteUrl }) => {
  const first = (await arc.view()).space.id;
  await arc.dispatch({ type: 'space/new', title: 'Work', icon: { kind: 'none' }, theme });
  const work = (await arc.view()).space.id;
  await arc.dispatch({ type: 'space/focus', spaceId: first });
  const x = tabRows((await arc.view()).space.today.rows)[0]!; // on screen in the first space since launch
  await arc.advanceClock(13 * HOUR);
  await arc.dispatch({ type: 'item/move', itemId: x.id, to: { kind: 'space', spaceId: work } }); // drop on Work's dock icon
  await expect.poll(async () => (await arc.view()).space.today.rows.some((r) => r.id === x.id)).toBe(false);
  await arc.advanceClock(60_000);
  await arc.dispatch({ type: 'space/focus', spaceId: work });
  expect(await todayIds(arc)).toContain(x.id);
});

test('finding 6: Ctrl+Tab, then Ctrl+Tab again, returns to the tab you started in (after app shortcuts in the target)', async ({ arc, siteUrl }) => {
  const b = await openTab(arc, `${siteUrl}page2.html`);
  await arc.press('CmdOrCtrl+D'); // pin
  await expect.poll(async () => (await arc.view()).space.pinned.rows.length).toBe(1);
  await arc.press('CmdOrCtrl+D'); // and unpin again (an app shortcut in the tab before leaving it)
  await expect.poll(async () => (await arc.view()).space.pinned.rows.length).toBe(0);
  const c = await openTab(arc, `${siteUrl}index.html`);
  await ctrlTab(arc);
  await expect.poll(() => currentId(arc)).toBe(b.id);
  await ctrlTab(arc); // a fresh hold: its Control keyDown commits the first walk, so this returns to c
  await expect.poll(() => currentId(arc)).toBe(c.id);
});

test('finding 7: a page that calls window.close() does not leave a blank card behind a "current" row', async ({ arc, siteUrl }) => {
  const t = await openTab(arc, `${siteUrl}close.html`);
  await expect(await arc.tabPage(t.id)).toHaveTitle('Closer');
  // After it closes itself, the content card is restored promptly: native panes match the view's panes again.
  await expect.poll(() => panesConsistent(arc), { timeout: 8000 }).toBe(true);
});

test('finding 7: a crashed tab renderer is replaced without an unrelated event', async ({ arc }) => {
  const pane = (await arc.native()).layers.find((l) => l.role === 'pane')!;
  await expect(await arc.tabPage(pane.tabId!)).toHaveTitle('Fixture Home');
  await arc.electronApp.evaluate(({ webContents }, id) => webContents.fromId(id)!.forcefullyCrashRenderer(), pane.webContentsId);
  // No further command from the test: the runtime re-renders itself and the pane returns.
  await expect.poll(() => panesConsistent(arc), { timeout: 8000 }).toBe(true);
});

test('finding 8: window bounds saved off every display reopen on screen', async ({ arc }) => {
  await arc.electronApp.evaluate(({ BaseWindow }) => BaseWindow.getAllWindows()[0]!.setBounds({ x: 5000, y: 4000, width: 1000, height: 700 }));
  await sleep(300);
  await arc.electronApp.evaluate(() => globalThis.__arc!.flush());
  await arc.restart();
  const visible = await arc.electronApp.evaluate(({ BaseWindow, screen }) => {
    const b = BaseWindow.getAllWindows()[0]!.getBounds();
    return screen.getAllDisplays().some((d) => b.x < d.workArea.x + d.workArea.width && b.x + b.width > d.workArea.x && b.y < d.workArea.y + d.workArea.height && b.y + b.height > d.workArea.y);
  });
  expect(visible).toBe(true);
});

test('finding 9: native() lists every attached view and the screen shows the current space, not a detached pane', async ({ arc, siteUrl }) => {
  const first = (await arc.view()).space.id;
  const home = (await arc.native()).layers.find((l) => l.role === 'pane')!;
  await expect(await arc.tabPage(home.tabId!)).toHaveTitle('Fixture Home');
  await arc.dispatch({ type: 'space/new', title: 'Work', icon: { kind: 'none' }, theme });
  const red = await openTab(arc, `${siteUrl}red.html`);
  await expect(await arc.tabPage(red.id)).toHaveTitle('Red');
  await (await arc.surface('sidebar')).getByTestId(TID.dockSpace(first)).click();
  await expect.poll(async () => (await arc.view()).space.id).toBe(first);
  await sleep(600);
  // native() counts exactly the views really attached, and the real screen shows the white home page, not the red one
  // the other space was showing (a detached pane left on top would make the midpoint red).
  expect((await arc.native()).layers.length).toBe(await arc.attachedViewCount());
  expect(await panesConsistent(arc)).toBe(true);
  const mid = { x: home.bounds.x + Math.floor(home.bounds.width / 2), y: home.bounds.y + 40 };
  expect(await arc.screenPixel(mid.x, mid.y)).toEqual([255, 255, 255, 255]);
});

test('finding 10: the sidebar surface recovers from a renderer crash', async ({ arc }) => {
  const chrome = (await arc.native()).layers.find((l) => l.role === 'chrome')!;
  await (await arc.surface('sidebar')).getByTestId(TID.sidebar).waitFor();
  await arc.electronApp.evaluate(({ webContents }, id) => webContents.fromId(id)!.forcefullyCrashRenderer(), chrome.webContentsId);
  // The surface reloads itself: without any further interaction its webContents is alive and no longer crashed, and it
  // is still the chrome layer. (Unfixed, nothing reloads it and it stays crashed.)
  await expect
    .poll(
      () =>
        arc.electronApp.evaluate(({ webContents }, id) => {
          const wc = webContents.fromId(id);
          return wc !== undefined && !wc.isDestroyed() && !wc.isCrashed() && !wc.isLoading();
        }, chrome.webContentsId),
      { timeout: 8000 },
    )
    .toBe(true);
  expect((await arc.native()).layers.some((l) => l.role === 'chrome' && l.webContentsId === chrome.webContentsId)).toBe(true);
});
