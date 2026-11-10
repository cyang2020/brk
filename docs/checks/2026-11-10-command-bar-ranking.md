# 2026-11-10 检查：⌘T / ⌘L 按 Arc 的打分排序

## 查了什么

这次合进 main 的是分支 `t3/arc-command-bar-ranking`（合并提交 b319e601）。⌘T 和 ⌘L 原来按写死的先后顺序排，这次换成了 Arc 1.170 的 ASE2 打分：

- 用 Arc 的 21 项特征、各类权重和 14 条加分项给每一行打分，显示 5 行，同一个网页或同一个搜索只出现一次；
- 输入框里的自动补全跟着第一行走；
- 每个 profile 会记下：哪些访问是在地址栏亲手输入或选中的、每个网页的访问次数、Brk 自己算的网站活跃度，以及在 ⌘T 里执行过的命令和切换过的 tab（每样记最近 15 次）。

Arc 的数字来自 `docs/research/arc-command-bar-ranking/`，代码在 `Sources/BrkOverlays/ArcRanking.swift`。

## 怎么查的

- **单元测试**：在 b319e601 上跑 `swift test`，1000 个，跳过 2 个，失败 0 个。其中 `ArcRankingTests` 有一张表，列了 9 个查询在真 Arc 里的排序。
- **原生场景**：跑 `python3 scripts/run-native.py cbr-merge-1 --set smoke,commandbar`，13 个全部通过。新加的 `Ranking-CmdT` 在 ⌘T 和 ⌘L 里用真实按键打字，核对每一行的顺序。
- **和真 Arc 对比**：在真 Arc 里只用按键打了 39 组查询，用编了词的测试网页、不同的访问次数和输入次数，再用 Arc 自己的历史库核对次数。大部分排序和 Arc 一致。
- **截图对比（station）**：命令栏相关的画面和 main 的差别在 0.02 个百分点以内。

## 还不一样的地方

下面几处会接着改：

- Arc 会列出当前正在看的 tab；
- 打一个已经开着的网址时，Arc 把打的网址排第一；
- 有些只是开头对上的命令，Arc 排在联想词下面；
- 场景 P02-c 里收藏和搜索的先后与 Arc 相反；
- 谷歌的网站推荐行和补全词，要换成 Chromium 的联想词请求格式才能拿到；
- 开着 Max 时"问 AI"那一行的位置，还没在真 Arc 上确认。
