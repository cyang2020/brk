import type { BaseWindow, WebContentsView } from 'electron';

/** What main exposes on globalThis.__arcTest when ARC_TEST=1, for Playwright's electronApp.evaluate. */
export interface ArcTestHooks {
  win: BaseWindow;
  chromeView: WebContentsView;
  tabViews: () => WebContentsView[];
}

declare global {
  var __arcTest: ArcTestHooks | undefined;
}
