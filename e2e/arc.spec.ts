/**
 * The done predicate's nine scenarios (docs/plan.md, 完成标准 2) plus a launch smoke. Every test is `test.skip`
 * until W2 fills the main-process bodies: the app cannot launch yet, so verify/REPORT.md must list them as
 * SKIPPED, never PASS. Each body's comment is the exact driving steps and assertions, in terms of the harness in
 * ./fixtures.ts (the e2e hook contract in docs/design/module-map.md), the TID selectors (src/shared/testids.ts)
 * and LAYOUT (src/shared/constants.ts). `siteUrl` is the local static server (e2e/site/, plus /fail).
 */
import { test } from './fixtures';

test.skip('0. launch smoke: test API answers, one window, chrome layer attached, sidebar DOM rendered', async ({ arc }) => {
  // facts = await arc.native(): facts.layers[0].role === 'chrome', its bounds === { x: 0, y: 0, ...facts.contentSize }
  // sidebar = await arc.surface('sidebar'); await expect(sidebar.getByTestId(TID.sidebar)).toBeVisible()
  // view = await arc.view(): view.dock.length === 1, view.space.today.rows.length === 1 (the ARC_START_URL tab, status 'current')
  // await arc.compositeScreenshot('0-launch-smoke')  (a PNG at least contentSize wide and high)
  void arc;
});

test.skip('1. launch: sidebar view and one tab view are attached; content card is inset and rounded', async ({ arc }) => {
  // facts = await arc.native(): layers[0].role === 'chrome' (full window); exactly one layer with role 'pane'
  // pane.bounds.x === LAYOUT.sidebar.defaultWidth + LAYOUT.contentInset; pane.bounds.y === LAYOUT.contentInset
  // pane.bounds.width === contentSize.width - pane.bounds.x - LAYOUT.contentInset; pane.radius === LAYOUT.contentRadius
  // await arc.compositeScreenshot('1-launch'): pixel at (pane.x + 1, pane.y + 1) equals the chrome layer's pixel there
  //   (corner is cut), and the pixel at the pane's top-edge midpoint (pane.x + width/2, pane.y + 2) is the page's background
  void arc;
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

test.skip('5. Cmd+S hides the sidebar: content fills the window with inset and radius kept; again restores', async ({ arc }) => {
  // { contentSize: { width: W, height: H } } = await arc.native(); inset = LAYOUT.contentInset
  // await arc.press('CmdOrCtrl+S'); expect.poll(view().sidebar.visible).toBe(false)
  // pane = native().layers.find(role === 'pane'): pane.bounds === { x: inset, y: inset, width: W - 2*inset, height: H - 2*inset }
  // pane.radius === LAYOUT.contentRadius; await arc.compositeScreenshot('5-sidebar-hidden')
  // await arc.press('CmdOrCtrl+S'); expect.poll(view().sidebar.visible).toBe(true); pane.bounds.x === LAYOUT.sidebar.defaultWidth + inset
  void arc;
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

test.skip('8. closing a tab destroys its webContents (destroyed event)', async ({ arc, siteUrl }) => {
  // open a second Today tab T (Cmd+T, siteUrl + 'page2.html', Enter); T is focused
  // wc = (await arc.native()).layers.find(l => l.tabId === T).webContentsId
  // await arc.press('CmdOrCtrl+W'); await arc.waitForDestroyed(wc)
  // (await arc.view()).space.today.rows has no row T (archived); (await arc.native()).layers has no layer with webContentsId wc
  void [arc, siteUrl];
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
