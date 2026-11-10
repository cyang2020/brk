# 2026-11-10 检查：Library 按钮悬停列表、鼠标和按键输入

## 查了什么

这次合进 main 的有两份工作：

- **Library 按钮的悬停列表**（分支 `t3/library-hover-preview`）：照 Arc 的 HomeBadging 做的。鼠标在左下角 Library 按钮上停 0.3 秒，弹出这个 profile 最新的四条下载和截图；新下载还会在按钮上显示角标。Arc 的事实写在 `docs/arc-anatomy/library-flyout.md`。
- **鼠标和按键输入**（分支 `t3/fix-browser-input-handling`），补了三处：
  - 鼠标第 4、5 键和鼠标软件发来的导航滑动，在网页外面也起作用：在侧边栏上是切换 Space，在网页旁边的空白处是前进、后退；
  - ⇧⌘] 和 ⇧⌘[ 切换 tab；
  - 中键点 tab 行会关掉这个 tab。

  规则写在 `docs/design/input-rules.md`。

同一次合并还修了 Library "AI 对话"页上被截断的文字：三个筛选按钮的文字留出了边距，英文搜索框的提示改成 "Search Chats…"。

## 怎么查的

- 单元测试：在 `integration/library` 上运行 `swift test`，结果是 990 个，跳过 2 个，失败 0 个。
- 原生场景：运行 `python3 scripts/run-native.py gate-batch2 --set smoke,downloads,keys,library`，共 34 个，其中 32 个第一次通过。R53-PressOpens 和 R54-Halves 失败时，Brk 的窗口不在最前面（共用屏幕上别的程序被切到了前台）；用 `--only` 单独重跑后两个都通过了。
  - 新加的场景是 LibraryFlyout-Hover、LibraryFlyout-Running、Input-TabKeys、Input-SideButtons、Input-SwipeIndicator 和 Input-MiddleClick。它们都用真实的鼠标、按键和下载，全部通过。
  - TextLayout 也通过了，说明截断的文字已经修好。
- 和真 Arc 对比：
  - 悬停列表：在同一块屏幕上和 Arc 对比过，打开时间是 0.30 秒，Arc 是 0.29 到 0.30 秒。
  - 鼠标和按键：在 Arc 1.170 上用真实输入核对过，Arc 在侧边栏上按侧键也是切换 Space，中键点 tab 行是归档。

## 没做的

- 下载开始时从网页飞进按钮的箭头没做。
- 预览背后的灰色渐变没做。
- macOS 自己的截图不进列表，因为 Brk 的 Media 页不收录它们。
- 双指滑动后退只确认了起手时的指示图标和 Arc 一样，滑完整个手势要真实触控板，这次没法验证。
