# 复刻 Arc 浏览器：执行方案

这份文档是整个工作的"剧本"。按 pstack 的 figure-it-out 流程写：先定完成标准，再定范围和严格程度，再列阶段。决策记录在 `.audit/arc-clone.tsv`，一行一个决定。

## 背景

Arc（The Browser Company 出品，2025 年被 Atlassian 收购）在 2026-10-22 宣布停运：即日起不开新账号，2026-11-23 停 iOS/Android，2026-12-22 起 macOS/Windows 无法使用，账号数据 30 天内删除。本机没装 Arc，所以把官方最新安装包 Arc 1.170.0（build 89123，2026-10-21 发布）下载到 `~/.cache/arc-target/Arc.app`，用 REA（Reverse Engineer Anything）做纯静态分析，产出两份解剖报告：

- `docs/arc-anatomy/model-and-shortcuts.md`：数据模型（AppleScript 字典 + Swift 类型）、完整菜单和快捷键表（189 项）、功能清单、设置项。
- `docs/arc-anatomy/visual-and-copy.md`：519 个命名颜色、主题系统、图标字体动效、英文文案（11816 条）。

没有反编译器，所以编进机器码里的数字（侧边栏宽度、圆角、动画时长、默认快捷键里不在菜单的那部分）拿不到，报告里标为 unknown。这些数字由我们自己定，并在设计文档里写明是推测。

## 完成标准（可证伪）

下面每条都能跑脚本判真假。全部为真才算完成。

1. `npm run typecheck`、`npm run test`（纯逻辑单元测试）、`npm run build` 三个命令退出码为 0。
2. `npm run e2e` 在 Docker 里的 Linux 虚拟显示上跑通 Playwright 对 Electron 的端到端测试，覆盖下列场景，每条有断言：
   - 启动后窗口里同时有侧边栏视图和一个标签页视图，内容面板有圆角并留有内边距。
   - Cmd+T 打开命令栏；输入网址回车后，当前 Space 的 Today 区多一个标签，并且标签页视图真的加载了那个网址（用本地 http 测试服务器，不依赖外网）。
   - Cmd+D 把标签从 Today 移到 Pinned，再按一次移回来。
   - 点击底部 Space 图标切换 Space：侧边栏显示该 Space 的标签，窗口背景渐变颜色变了（对侧边栏视图截图取像素比较）。
   - Cmd+S 隐藏侧边栏后，内容视图的 bounds 占满窗口并保留圆角；再按一次恢复。
   - Ctrl+Shift+= 创建分屏：两个标签页视图同时挂在窗口上，左右并排。
   - 把时钟拨快超过自动归档阈值后，闲置的 Today 标签进入归档；归档页里能看到并能恢复。
   - 关闭标签后，对应 webContents 被销毁（`destroyed` 事件）。
   - 重启应用后 Space、Pinned、Today、当前标签、侧边栏宽度全部恢复。
3. e2e 过程里保存合成截图到 `verify/shots/`，并生成 `verify/REPORT.md`，逐条列出上面的断言和 PASS/FAIL。
4. 代码合进 `main`，用户在自己的 Mac 桌面上 `npm install && npm run dev` 能打开窗口。

## 范围

做的是 Arc 的核心使用体验，不是整个产品。

**v1 做：**

- 窗口：每个 Space 一套主题（多色混合渐变 + 颗粒纹理），hiddenInset 标题栏（红绿灯在侧边栏上方），内容面板圆角 + 内边距，侧边栏可拖宽。
- 侧边栏：Space 名和图标；网址胶囊（显示当前网址，占位文案 "Search or Enter URL…"，点击等于 Cmd+L）；Favorites 网格（跨 Space 共享）；Pinned 区（可折叠）；分隔线；Today 区（含 "New Tab" 行，悬停区头出现 Clear）；底部一排 Space 图标 + 归档入口 + "+" 菜单（New Tab / New Folder / New Space）。
- 标签：新建、归档（Cmd+W 或悬停 ×；Today 标签进归档，Pinned/Favorites 标签只卸载页面、保留条目，即 Arc 的 "Close and Keep Pinned"）、点击切换、Ctrl+Tab 最近标签轮换、Cmd+Opt+↑/↓ 上下一个、固定/取消固定（Cmd+D）、双击重命名、拖拽排序和跨区移动、文件夹（嵌套、展开折叠）、恢复最近归档（Cmd+Shift+T）、清空 Today（Cmd+Shift+K）、固定标签重置回原始网址、加载指示、favicon。
- Space：新建（名字、emoji/图标、从 4 套 9 色预设里选主题色）、重命名、改图标、改主题、删除（标签进归档）、排序、切换（点底部图标，Cmd+Opt+←/→）。每个 Space 有自己的 Pinned 和 Today。
- 命令栏：Cmd+T 居中新建模式，Cmd+L 在网址胶囊上编辑当前标签；建议项包括打开中的标签（切换）、"搜索/打开你输入的"、历史、少量命令（切换侧边栏、新建 Space、固定、分屏）。方向键选择，回车执行，Esc 关闭。
- 分屏：Ctrl+Shift+= 加一格，Ctrl+Shift+- 关一格，拖中缝调宽，最多 4 格；分屏作为一个侧边栏条目保存，子项是各格。
- 隐藏侧边栏：Cmd+S；隐藏时鼠标靠左边缘浮出侧边栏。
- 自动归档：Today 标签闲置超过阈值进归档（阈值 1h/6h/12h/24h/7d/30d/never，默认 12h）；归档页按 Today / Yesterday / Earlier this week / Past month / Beyond 分组，可恢复，可清空。
- 持久化：所有状态存成一个 JSON（原子写），启动恢复 Space、标签、当前标签、侧边栏宽度、窗口位置。
- 浏览基础：后退/前进/刷新、缩放、全屏、开发者工具、复制网址（Cmd+Shift+C）、Cmd+点击和 target=_blank 开新标签、基础右键菜单。
- 明暗：由主题颜色亮度推出 light/dark，侧边栏文字颜色按 Arc 的语义色板取值。

**v1 不做：** Easel、Note、Boost、Peek、Little Arc、Air Traffic Control、多 Profile、同步、扩展、Ask Arc 等 AI、Live Folder、画中画、截图捕获、站点控制中心、翻译、新手引导视频、Chromium 设置页、无痕窗口。

**规模估计（推测）：** 约 12 个模块，6k 到 9k 行 TypeScript 含测试，6 到 10 个子 agent 并行，一次多小时的无人值守运行。

## 技术选择

Electron 45 + TypeScript strict + React（侧边栏和命令栏界面）+ electron-vite + vitest + Playwright。理由：Arc 本身就是 Chromium 内核，Electron 自带 Chromium，网页表现一致；spike（`/tmp/arc-spike/REPORT.md`）已经验证 `BaseWindow` + 多个 `WebContentsView` 能画出"渐变底 + 透明侧边栏 + 圆角内容面板"的布局，Playwright 能拿到每个视图的 Page 句柄。备选 Swift + WKWebView 更贴近 Arc 的原生手感，但缺 Chromium 特性、自动化难，而且并行开发的 agent 对 TypeScript 更熟练，放弃。

## 环境限制

这台 Mac 有人登录在图形会话，但本会话是 SSH 进来的，没有 root，`open` 和直接启动 Electron 都挂不上窗口服务（`NSScreen.screens.count` 为 0）。所以所有带窗口的验证在 Docker 里的 Linux 虚拟显示上跑。macOS 独有的部分（红绿灯位置、vibrancy、菜单键位和网页抢键的先后顺序、`setBounds` 动画是否流畅）我这边验证不了，交付时明确标为未验证，由用户在桌面上看一眼。

## 严格程度

偏高。原因：多小时无人值守；架构决策（视图栈、状态所有权、IPC 契约）是单向门；并行子 agent 多。具体做法：

- 先建验证脚手架再写功能。
- 一次 architect 竞赛（两个不同模型各出一套设计，第三家模型做裁判），定下类型、签名、模块边界后再写代码；之后不再二次竞赛。
- 每个并行 worker 各用自己的 git worktree 和分支，只在合并时汇合。
- 每个 worker 配一个独立判官看真实产物，不信自述。
- 最后做一轮对抗式评审（interrogate），只认跑出来的证据。

## 阶段清单

1. **Frame（本文档）。** 完成标准、范围、限制、严格程度。
2. **Architect 竞赛。** 输入：两份解剖报告、spike 报告、本文档。输出：`docs/design/`（模块图、类型草图、取舍理由）和 `src/` 里只有类型和 `not implemented` 的骨架。裁判用 Codex 系模型。
3. **脚手架和验证基座。** electron-vite 工程、strict TypeScript、vitest、Playwright e2e、Docker 里跑 e2e 的脚本、合成截图工具。冒烟测试：启动、两个视图、截图。这是"旧值"基线。
4. **并行实现（各自 worktree）。**
   - W1 领域模型：侧边栏树、Space、变更操作、归档和自动归档、会话状态、JSON 存取。纯函数，单元测试。
   - W2 主进程：窗口和视图布局（侧边栏显隐浮出、分屏布局、圆角）、标签生命周期、菜单和快捷键、类型化 IPC、主题到窗口背景。
   - W3 侧边栏界面：按解剖报告的分区和颜色做 React 界面，拖拽、右键菜单、重命名、Space 底栏、渐变和颗粒背景。
   - W4 命令栏和归档页界面。
   每个 worker 对照第 2 步的骨架实现，偏离骨架要在报告里说明。
5. **集成和 e2e 扩展。** 合并四个分支，按完成标准第 2 条补齐 e2e，跑 Docker 验证，生成 `verify/REPORT.md`。
6. **对抗评审和修复。** interrogate 一轮，修掉被证实的问题，再跑一遍 e2e。
7. **验收和交付。** 对照完成标准逐条核对，审计决策记录，跨模型复核记录，合进 `main`。
