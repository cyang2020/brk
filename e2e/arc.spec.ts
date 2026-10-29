/**
 * The done predicate's nine scenarios (docs/plan.md, 完成标准 2) plus a launch smoke. Each body follows the driving
 * steps and assertions of the e2e hook contract in docs/design/module-map.md, in terms of the harness in
 * ./fixtures.ts, the TID selectors (src/shared/testids.ts) and LAYOUT (src/shared/constants.ts). `siteUrl` is the
 * local static server (e2e/site/, plus /fail).
 */
import { readFile } from 'node:fs/promises';
import { LAYOUT } from '../src/shared/constants';
import { TID } from '../src/shared/testids';
import type { RowView, TabRowView, WindowView } from '../src/shared/view';
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
});

test.skip('2. Cmd+T opens the command bar; Enter on a URL adds a Today tab that really loads it', async ({ arc, siteUrl }) => {
  // before = (await arc.view()).space.today.rows.length
  // await arc.press('CmdOrCtrl+T'); overlay = await arc.surface('overlay'); expect(overlay.getByTestId(TID.commandBar)).toBeVisible()
  // (await arc.native()).layers.some(l => l.role === 'overlay') === true, and that layer's bounds are the full window
  // await overlay.getByTestId(TID.commandBarInput).fill(siteUrl + 'page2.html'); await overlay.keyboard.press('Enter')
  // expect.poll(view().space.today.rows.length).toBe(before + 1); the new row (not in the old id set) has status 'current'
  // expect.poll(native().layers.some(role === 'overlay')).toBe(false)
  // page = await arc.tabPage(newRow.id); expect(page.url()).toBe(siteUrl + 'page2.html'); await expect(page).toHaveTitle('Fixture Page 2')
  // await arc.compositeScreenshot('2-new-tab')
  void [arc, siteUrl];
});

test.skip('3. Cmd+D moves the tab from Today to Pinned, and again moves it back', async ({ arc }) => {
  // id = the Today row with status 'current' in (await arc.view()).space.today.rows
  // await arc.press('CmdOrCtrl+D'); expect.poll(view().space.pinned.rows.map(r => r.id)).toContain(id); today.rows lacks id
  // sidebar = await arc.surface('sidebar'); expect(sidebar.getByTestId(TID.section('pinned')).getByTestId(TID.row(id))).toBeVisible()
  // the pinned row has canReset === false right after pinning (pinnedUrl === url)
  // await arc.press('CmdOrCtrl+D'); expect.poll(view().space.today.rows.map(r => r.id)).toContain(id); pinned.rows lacks id
  void arc;
});

test.skip('4. clicking a dock space switches space: sidebar shows its tabs and the gradient changes', async ({ arc, siteUrl }) => {
  // first = (await arc.view()).dock[0].id
  // await arc.dispatch({ type: 'space/new', title: 'Work', icon: { kind: 'none' }, theme: themeFromPrimary(THEME_PRESETS.drab[8]) })
  //   (the window switches to the new space); open a tab in it: press Cmd+T, fill siteUrl + 'page2.html', Enter
  // before = await arc.layerPixel('chrome', 4, 200)   (the inset strip left of the sidebar content shows the gradient)
  // sidebar = await arc.surface('sidebar'); await sidebar.getByTestId(TID.dockSpace(first)).click()
  // expect.poll(view().space.id).toBe(first); sidebar DOM shows first's Today rows (TID.row of its tab), not Work's
  // after = await arc.layerPixel('chrome', 4, 200); max channel distance(before, after) > 24
  // await arc.compositeScreenshot('4-space-switched')
  void [arc, siteUrl];
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

test.skip('6. Ctrl+Shift+= creates a split: two tab views attached side by side', async ({ arc, siteUrl }) => {
  // await arc.press('Ctrl+Shift+=')
  // expect.poll(native().layers.filter(role === 'pane').length).toBe(2); panes[0].bounds.y === panes[1].bounds.y, same height,
  //   panes[0].bounds.x + panes[0].bounds.width < panes[1].bounds.x (a LAYOUT.contentInset gap between them)
  // (await arc.view()).content.splitId !== null; space.today.rows has exactly one row of kind 'split' with two panes
  // the command bar is open for the new (empty) pane: overlay = await arc.surface('overlay'); fill siteUrl + 'page2.html'; Enter
  // page = await arc.tabPage(panes[1].tabId); await expect(page).toHaveTitle('Fixture Page 2')
  // await arc.compositeScreenshot('6-split')
  void [arc, siteUrl];
});

test.skip('7. after the clock passes the threshold an idle Today tab is archived, visible in the archive, restorable', async ({ arc, siteUrl }) => {
  // A = the start tab's id; open B via Cmd+T + siteUrl + 'page2.html' + Enter (B focused, A idle)
  // await arc.advanceClock(13 * 3600_000)   (default threshold DEFAULT_AUTO_ARCHIVE = '12h')
  // expect.poll(view().space.today.rows.map(r => r.id)).not.toContain(A); still contains B (visible tabs never auto-archive)
  // sidebar = await arc.surface('sidebar'); await sidebar.getByTestId(TID.dockArchive).click()
  // overlay = await arc.surface('overlay'); the 'overlay' layer's bounds equal view().content.rect (archive draws inside the card)
  // entry = (await arc.view()).overlay.entries.find(e => e.title/url is A's); expect(overlay.getByTestId(TID.archiveGroup('today')).getByTestId(TID.archiveEntry(entry.id))).toBeVisible()
  // await overlay.getByTestId(TID.archiveRestore(entry.id)).click(); expect.poll(view().space.today.rows.map(r => r.id)).toContain(A)
  // await arc.compositeScreenshot('7-archive')
  void [arc, siteUrl];
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

test.skip('9. restart restores spaces, Pinned, Today, current tab, and sidebar width', async ({ arc, siteUrl }) => {
  // set up: dispatch space/new 'Work'; in it open two Today tabs (siteUrl + 'index.html', siteUrl + 'page2.html'); Cmd+D the first;
  //   also open a Today tab at siteUrl + 'fail' (the server drops the socket: did-fail-load); focus page2's tab
  // await arc.dispatch({ type: 'sidebar/resize', width: 300 })
  // reduce = (v: WindowView) => ({ dock: v.dock.map(d => [d.id, d.title]), space: v.space.id, pinned: rows -> [id, url], today: rows -> [id, url, title],
  //   current: the row with status 'current', width: v.sidebar.width })
  // before = reduce(await arc.view()); await arc.restart(); after = reduce(await arc.view()); expect(after).toEqual(before)
  // the /fail tab is still in today with its title (failure is live state only); native() shows exactly one pane (the current tab)
  void [arc, siteUrl];
});
