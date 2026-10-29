import { app, BaseWindow, ipcMain, WebContentsView } from 'electron';
import { join } from 'node:path';
import { IPC } from '../shared/ipc';
import { PANEL_INSET, PANEL_RADIUS, SIDEBAR_WIDTH } from '../shared/layout';

function createWindow(): void {
  const win = new BaseWindow({ width: 1280, height: 800, titleBarStyle: 'hiddenInset' });

  // The chrome view fills the window at the bottom of the stack: gradient background and sidebar.
  const chromeView = new WebContentsView({
    webPreferences: { preload: join(__dirname, '../preload/index.js'), contextIsolation: true, sandbox: true },
  });
  win.contentView.addChildView(chromeView, 0);
  const devServer = process.env.ELECTRON_RENDERER_URL;
  if (devServer) void chromeView.webContents.loadURL(`${devServer}/chrome/index.html`);
  else void chromeView.webContents.loadFile(join(__dirname, '../renderer/chrome/index.html'));

  // One tab view on top, right of the sidebar, with rounded corners.
  const tabView = new WebContentsView();
  tabView.setBorderRadius(PANEL_RADIUS);
  tabView.setBackgroundColor('#ffffff');
  win.contentView.addChildView(tabView);
  void tabView.webContents.loadURL(process.env.ARC_TEST_URL ?? 'about:blank');

  // Size from the root view, not the window: on Linux the frame insets arrive after creation
  // and only the root view's bounds-changed reports them (the window's resize does not fire).
  const layout = (): void => {
    const { width, height } = win.contentView.getBounds();
    chromeView.setBounds({ x: 0, y: 0, width, height });
    const x = SIDEBAR_WIDTH + PANEL_INSET;
    tabView.setBounds({ x, y: PANEL_INSET, width: width - x - PANEL_INSET, height: height - 2 * PANEL_INSET });
  };
  layout();
  win.contentView.on('bounds-changed', layout);

  if (process.env.ARC_TEST === '1') globalThis.__arcTest = { win, chromeView, tabViews: () => [tabView] };
}

void app.whenReady().then(() => {
  ipcMain.handle(IPC.ping, () => 'pong');
  createWindow();
});
app.on('window-all-closed', () => app.quit());
