/**
 * The done predicate's nine scenarios (docs/plan.md, 完成标准 2) plus a launch smoke. Each body follows the driving
 * steps and assertions of the e2e hook contract in docs/design/module-map.md, in terms of the harness in
 * ./fixtures.ts, the TID selectors (src/shared/testids.ts) and LAYOUT (src/shared/constants.ts). `siteUrl` is the
 * local static server (e2e/site/, plus /fail).
 */
import { readFile } from 'node:fs/promises';
import { LAYOUT } from '../src/shared/constants';
import { TID } from '../src/shared/testids';
import { THEME_PRESETS, themeFromPrimary } from '../src/shared/theme';
import type { ArchiveView, RowView, TabRowView, WindowView } from '../src/shared/view';
import { expect, test, type Arc, type Rgba } from './fixtures';

/** Width and height from a PNG's IHDR chunk. */
async function pngSize(path: string): Promise<{ width: number; height: number }> {
  const png = await readFile(path);
  return { width: png.readUInt32BE(16), height: png.readUInt32BE(20) };
}

const todayIds = async (arc: Arc): Promise<string[]> => (await arc.view()).space.today.rows.map((r) => r.id);
const tabRows = (rows: readonly RowView[]): TabRowView[] => rows.filter((r): r is TabRowView => r.kind === 'tab');
const current = (view: WindowView): RowView | undefined =>
  [...view.space.today.rows, ...view.space.pinned.rows, ...view.favorites.tiles].find((r) => r.kind !== 'folder' && r.status === 'current');
const maxChannelDistance = (a: Rgba, b: Rgba): number => Math.max(...a.slice(0, 3).map((v, i) => Math.abs(v - (b[i] ?? 0))));

/** Cmd+T, type a URL, Enter: the way a user opens a tab. Resolves with the new Today row once it is current. */
async function openTab(arc: Arc, url: string): Promise<TabRowView> {
  const before = await todayIds(arc);
  await arc.press('CmdOrCtrl+T');
  const overlay = await arc.surface('overlay');
  const input = overlay.getByTestId(TID.commandBarInput);
  await expect(input).toBeVisible();
  await input.fill(url);
  await overlay.keyboard.press('Enter');
  await expect.poll(() => todayIds(arc)).toHaveLength(before.length + 1);
  const row = tabRows((await arc.view()).space.today.rows).find((r) => !before.includes(r.id));
  if (!row) throw new Error('no new Today row');
  expect(row.status).toBe('current');
  return row;
}

test('0. launch smoke: test API answers, one window, chrome layer attached, sidebar DOM rendered', async ({ arc }) => {
  const facts = await arc.native();
  expect(facts.layers[0]?.role).toBe('chrome');
  expect(facts.layers[0]?.bounds).toEqual({ x: 0, y: 0, ...facts.contentSize });
  const sidebar = await arc.surface('sidebar');
  await expect(sidebar.getByTestId(TID.sidebar)).toBeVisible();
  const view = await arc.view();
  expect(view.dock).toHaveLength(1);
  expect(view.space.today.rows).toHaveLength(1);
  expect(view.space.today.rows[0]).toMatchObject({ kind: 'tab', status: 'current' });
  const shot = await arc.compositeScreenshot('0-launch-smoke');
  const size = await pngSize(shot);
  expect(size.width).toBeGreaterThanOrEqual(facts.contentSize.width);
  expect(size.height).toBeGreaterThanOrEqual(facts.contentSize.height);
});

test('1. launch: sidebar view and one tab view are attached; content card is inset and rounded', async ({ arc }) => {
  const facts = await arc.native();
  expect(facts.layers[0]?.role).toBe('chrome');
  expect(facts.layers[0]?.bounds).toEqual({ x: 0, y: 0, ...facts.contentSize });
  const panes = facts.layers.filter((l) => l.role === 'pane');
  expect(panes).toHaveLength(1);
  const pane = panes[0]!;
  expect(pane.bounds.x).toBe(LAYOUT.sidebar.defaultWidth + LAYOUT.contentInset);
  expect(pane.bounds.y).toBe(LAYOUT.contentInset);
  expect(pane.bounds.width).toBe(facts.contentSize.width - pane.bounds.x - LAYOUT.contentInset);
  expect(pane.bounds.height).toBe(facts.contentSize.height - 2 * LAYOUT.contentInset);
  expect(pane.radius).toBe(LAYOUT.contentRadius);
  // let the page paint before the capture, so the midpoint pixel is the page's own background
  await expect(await arc.tabPage(pane.tabId!)).toHaveTitle('Fixture Home');
  const shot = await arc.compositeScreenshot('1-launch');
  const corner = { x: pane.bounds.x + 1, y: pane.bounds.y + 1 };
  expect(await arc.compositePixel(shot, corner.x, corner.y)).toEqual(await arc.layerPixel('chrome', corner.x, corner.y)); // the corner is cut
  const mid = { x: pane.bounds.x + Math.floor(pane.bounds.width / 2), y: pane.bounds.y + 2 };
  const page = await arc.compositePixel(shot, mid.x, mid.y);
  expect(page).toEqual([255, 255, 255, 255]); // the fixture page has no background of its own: white
  expect(maxChannelDistance(page, await arc.layerPixel('chrome', mid.x, mid.y))).toBeGreaterThan(24); // and it is not the gradient
  // The real X screen, not only the harness composite: the corner is actually cut to the gradient (a radius that is
  // recorded but never applied to the view would show the square white page here).
  await new Promise((r) => setTimeout(r, 500));
  const realCorner = await arc.screenPixel(corner.x, corner.y);
  expect(maxChannelDistance(realCorner, await arc.layerPixel('chrome', corner.x, corner.y))).toBeLessThanOrEqual(8);
  const realMid = await arc.screenPixel(pane.bounds.x + Math.floor(pane.bounds.width / 2), pane.bounds.y + 40);
  expect(realMid).toEqual([255, 255, 255, 255]); // the card interior is the white page
});

test('2. Cmd+T opens the command bar; Enter on a URL adds a Today tab that really loads it', async ({ arc, siteUrl }) => {
  const before = await todayIds(arc);
  await arc.press('CmdOrCtrl+T');
  const overlay = await arc.surface('overlay');
  await expect(overlay.getByTestId(TID.commandBar)).toBeVisible();
  const facts = await arc.native();
  const bar = facts.layers.find((l) => l.role === 'overlay');
  expect(bar?.bounds).toEqual({ x: 0, y: 0, ...facts.contentSize });
  expect(facts.layers.at(-1)).toEqual(bar); // on top of the stack
  await overlay.getByTestId(TID.commandBarInput).fill(`${siteUrl}page2.html`);
  await overlay.keyboard.press('Enter');
  await expect.poll(() => todayIds(arc)).toHaveLength(before.length + 1);
  const row = tabRows((await arc.view()).space.today.rows).find((r) => !before.includes(r.id));
  expect(row?.status).toBe('current');
  await expect.poll(async () => (await arc.native()).layers.some((l) => l.role === 'overlay')).toBe(false);
  const page = await arc.tabPage(row!.id);
  expect(page.url()).toBe(`${siteUrl}page2.html`);
  await expect(page).toHaveTitle('Fixture Page 2');
  await expect.poll(async () => tabRows((await arc.view()).space.today.rows).find((r) => r.id === row!.id)?.title).toBe('Fixture Page 2');
  await arc.compositeScreenshot('2-new-tab');
});

test('3. Cmd+D moves the tab from Today to Pinned, and again moves it back', async ({ arc }) => {
  const id = tabRows((await arc.view()).space.today.rows).find((r) => r.status === 'current')!.id;
  const pinnedIds = async () => (await arc.view()).space.pinned.rows.map((r) => r.id);
  await arc.press('CmdOrCtrl+D');
  await expect.poll(pinnedIds).toContain(id);
  expect(await todayIds(arc)).not.toContain(id);
  const sidebar = await arc.surface('sidebar');
  await expect(sidebar.getByTestId(TID.section('pinned')).getByTestId(TID.row(id))).toBeVisible();
  expect(tabRows((await arc.view()).space.pinned.rows).find((r) => r.id === id)?.canReset).toBe(false);
  await arc.press('CmdOrCtrl+D');
  await expect.poll(() => todayIds(arc)).toContain(id);
  expect(await pinnedIds()).not.toContain(id);
  await expect(sidebar.getByTestId(TID.section('today')).getByTestId(TID.row(id))).toBeVisible();
});

test('4. clicking a dock space switches space: sidebar shows its tabs and the gradient changes', async ({ arc, siteUrl }) => {
  const first = (await arc.view()).dock[0]!.id;
  const firstTab = tabRows((await arc.view()).space.today.rows)[0]!.id;
  await arc.dispatch({ type: 'space/new', title: 'Work', icon: { kind: 'none' }, theme: themeFromPrimary(THEME_PRESETS.drab[8]!) });
  await expect.poll(async () => (await arc.view()).space.title).toBe('Work'); // the window switched to the new space
  const workTab = await openTab(arc, `${siteUrl}page2.html`);
  const sidebar = await arc.surface('sidebar');
  await expect(sidebar.getByTestId(TID.row(workTab.id))).toBeVisible();
  // the crossfade to Work's theme has to finish before the "before" sample, or the switch back could read mid-fade
  const settled = async (): Promise<Rgba> => {
    const a = await arc.layerPixel('chrome', 4, 200);
    await new Promise((resolve) => setTimeout(resolve, 150));
    const b = await arc.layerPixel('chrome', 4, 200);
    return maxChannelDistance(a, b) <= 2 ? b : settled();
  };
  const before = await settled();
  await sidebar.getByTestId(TID.dockSpace(first)).click();
  await expect.poll(async () => (await arc.view()).space.id).toBe(first);
  await expect(sidebar.getByTestId(TID.row(firstTab))).toBeVisible();
  await expect(sidebar.getByTestId(TID.row(workTab.id))).toHaveCount(0);
  await expect.poll(async () => maxChannelDistance(before, await arc.layerPixel('chrome', 4, 200))).toBeGreaterThan(24);
  await arc.compositeScreenshot('4-space-switched');
});

test('5. Cmd+S hides the sidebar: content fills the window with inset and radius kept; again restores', async ({ arc }) => {
  const { contentSize: { width: W, height: H } } = await arc.native();
  const inset = LAYOUT.contentInset;
  const pane = async () => (await arc.native()).layers.find((l) => l.role === 'pane')!;
  await arc.press('CmdOrCtrl+S');
  await expect.poll(async () => (await arc.view()).sidebar.visible).toBe(false);
  const hidden = await pane();
  expect(hidden.bounds).toEqual({ x: inset, y: inset, width: W - 2 * inset, height: H - 2 * inset });
  expect(hidden.radius).toBe(LAYOUT.contentRadius);
  await arc.compositeScreenshot('5-sidebar-hidden');
  await arc.press('CmdOrCtrl+S');
  await expect.poll(async () => (await arc.view()).sidebar.visible).toBe(true);
  const shown = await pane();
  expect(shown.bounds.x).toBe(LAYOUT.sidebar.defaultWidth + inset);
  expect(shown.bounds.width).toBe(W - shown.bounds.x - inset);
  expect(shown.radius).toBe(LAYOUT.contentRadius);
});

test('6. Ctrl+Shift+= creates a split: two tab views attached side by side', async ({ arc, siteUrl }) => {
  await arc.press('Ctrl+Shift+=');
  const panes = async () => (await arc.native()).layers.filter((l) => l.role === 'pane');
  await expect.poll(async () => (await panes()).length).toBe(2);
  const [left, right] = await panes();
  expect(left!.bounds.y).toBe(right!.bounds.y);
  expect(left!.bounds.height).toBe(right!.bounds.height);
  expect(left!.bounds.x + left!.bounds.width + LAYOUT.contentInset).toBe(right!.bounds.x);
  const view = await arc.view();
  expect(view.content.splitId).not.toBeNull();
  const splits = view.space.today.rows.filter((r) => r.kind === 'split');
  expect(splits).toHaveLength(1);
  expect(splits[0]!.kind === 'split' && splits[0]!.panes).toHaveLength(2);
  // the command bar is open for the new, empty pane
  expect(view.overlay?.kind).toBe('command-bar');
  const overlay = await arc.surface('overlay');
  await overlay.getByTestId(TID.commandBarInput).fill(`${siteUrl}page2.html`);
  await overlay.keyboard.press('Enter');
  const page = await arc.tabPage(right!.tabId!);
  await expect(page).toHaveTitle('Fixture Page 2');
  await arc.compositeScreenshot('6-split');
});

test('7. after the clock passes the threshold an idle Today tab is archived, visible in the archive, restorable', async ({ arc, siteUrl }) => {
  const a = tabRows((await arc.view()).space.today.rows).find((r) => r.status === 'current')!;
  const b = await openTab(arc, `${siteUrl}page2.html`); // B is on screen, A is idle
  await arc.advanceClock(13 * 3600_000); // default threshold is 12h
  await expect.poll(() => todayIds(arc)).not.toContain(a.id);
  expect(await todayIds(arc)).toContain(b.id); // a visible tab never auto-archives
  const sidebar = await arc.surface('sidebar');
  await sidebar.getByTestId(TID.dockArchive).click();
  const overlay = await arc.surface('overlay');
  await expect(overlay.getByTestId(TID.archive)).toBeVisible();
  const view = await arc.view();
  expect(view.overlay?.kind).toBe('archive');
  const layer = (await arc.native()).layers.find((l) => l.role === 'overlay');
  expect(layer?.bounds).toEqual(view.content.rect); // the archive draws inside the content card
  expect(layer?.radius).toBe(view.content.radius);
  const entry = (view.overlay as ArchiveView).entries.find((e) => e.url === a.url);
  expect(entry?.reason).toBe('auto');
  await expect(overlay.getByTestId(TID.archiveGroup('today')).getByTestId(TID.archiveEntry(entry!.id))).toBeVisible();
  await arc.compositeScreenshot('7-archive');
  await overlay.getByTestId(TID.archiveRestore(entry!.id)).click();
  await expect.poll(() => todayIds(arc)).toContain(a.id);
});

test('8. closing a tab destroys its webContents (destroyed event)', async ({ arc, siteUrl }) => {
  const t = await openTab(arc, `${siteUrl}page2.html`);
  const layer = (await arc.native()).layers.find((l) => l.tabId === t.id);
  expect(layer).toBeDefined();
  const wc = layer!.webContentsId;
  await arc.press('CmdOrCtrl+W');
  await arc.waitForDestroyed(wc);
  expect(await todayIds(arc)).not.toContain(t.id); // archived
  expect((await arc.native()).layers.some((l) => l.webContentsId === wc)).toBe(false);
  expect(await arc.electronApp.evaluate(() => globalThis.__arc!.destroyedWebContentsIds())).toContain(wc);
});

test('9. restart restores spaces, Pinned, Today, current tab, and sidebar width', async ({ arc, siteUrl }) => {
  await arc.dispatch({ type: 'space/new', title: 'Work', icon: { kind: 'none' }, theme: themeFromPrimary(THEME_PRESETS.drab[8]!) });
  await expect.poll(async () => (await arc.view()).space.title).toBe('Work');
  const home = await openTab(arc, `${siteUrl}index.html`);
  const page2 = await openTab(arc, `${siteUrl}page2.html`);
  await arc.dispatch({ type: 'tab/focus', tabId: home.id });
  await expect.poll(async () => current(await arc.view())?.id).toBe(home.id);
  await arc.press('CmdOrCtrl+D');
  await expect.poll(async () => (await arc.view()).space.pinned.rows.map((r) => r.id)).toContain(home.id);
  const fail = await openTab(arc, `${siteUrl}fail`); // the server drops the socket: did-fail-load
  await expect.poll(async () => tabRows((await arc.view()).space.today.rows).find((r) => r.id === fail.id)?.loading).toBe(false);
  await arc.dispatch({ type: 'tab/focus', tabId: page2.id });
  await expect.poll(async () => current(await arc.view())?.id).toBe(page2.id);
  await arc.dispatch({ type: 'sidebar/resize', width: 300 });
  await expect.poll(async () => (await arc.view()).sidebar.width).toBe(300);
  const reduce = (v: WindowView) => ({
    dock: v.dock.map((d) => [d.id, d.title]),
    space: v.space.id,
    pinned: tabRows(v.space.pinned.rows).map((r) => [r.id, r.url]),
    today: tabRows(v.space.today.rows).map((r) => [r.id, r.url, r.title]),
    current: current(v)?.id ?? null,
    width: v.sidebar.width,
  });
  const before = reduce(await arc.view());
  expect(before.dock).toHaveLength(2);
  expect(before.pinned.map(([id]) => id)).toEqual([home.id]);
  expect(before.today.map(([id]) => id)).toContain(fail.id);
  expect(before.current).toBe(page2.id);
  await arc.restart();
  const after = reduce(await arc.view());
  expect(after).toEqual(before);
  const panes = (await arc.native()).layers.filter((l) => l.role === 'pane');
  expect(panes.map((p) => p.tabId)).toEqual([page2.id]); // only the current tab gets a view at launch
});
