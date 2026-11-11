# 2026-11-12 首次引导和从其他浏览器导入

查了什么：新的首次引导窗口（取代原来的 Welcome 对话框）和"从其他浏览器导入"能不能用真实输入走完，导入的数据是否真的进了 Brk，重复导入会不会重复。截图和日志在 `~/brk-evidence/onboarding-build/`，不进仓库。

## 单元测试

`swift test`：1028 个，0 失败，2 个跳过（原来就跳过）。新增 6 个：

- `BrkImportTests`（5 个，测试时在临时目录里现做假数据）：Chrome 的 Bookmarks JSON 和 History（只取 90 天、不要子框架访问）；Chrome 的密码和 cookie 用钥匙串密码解开，写进 Brk 的 Login Data 只写一次，Login Data 被占用时加密后暂存、下次启动前合并（表结构用 Brk 的 Chromium 154 实际的第 43 版）；Safari 导出的 ZIP；Firefox 的 places.sqlite；Arc 的侧边栏文件对应成 Space、Pinned、Today、文件夹、分屏、Favorites。
- `ImportSyncTests.testBrowserImportMapsArcSpacesOnceAndImportingAgainAddsNothing`：Arc 导入落地，再导一次不多任何东西，重启后 Space 对应表还在。

## 原生场景

- `Onboarding-Import`（登记在 library 组）：`python3 scripts/run-native.py <名字> --only Onboarding-Import`。真实点击和键盘走完欢迎、名字、选浏览器、选 profile、钥匙串说明、进度、挑书签、Favorites、主题、广告拦截、Max、默认浏览器、结束页；假的 Chrome profile 带来 4 个书签、2 条历史、1 个密码、1 个 cookie；cookie 被网页读到；重启后 CEF 的密码管理在登录页自动填上导入的密码。通过。
- `Onboarding-RealArc`（不登记，要 `BRK_E2E_REAL_IMPORT=1`）：把这台 Mac 上真实的 Arc profile 导进测试自己的数据目录。导入 2 个 Space、11 个 pinned 和 Today 标签、4 个 Favorites、184 条 90 天内的历史；再导一次结果是"Nothing new"。密码和 cookie 关掉了，因为钥匙串弹窗要人输电脑密码。通过。
