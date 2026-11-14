# macOS 退出线程池饥饿

CPU 被普通 QoS 工作占满时，Chromium 的退出线程等待后台 worker，worker 却需要先得到运行机会才能自行提升优先级。原 R3/PB3 dump 中的启动线程正在请求 BACKGROUND QoS；本次 PB3 重现中，NetworkService 已消失，主线程仍停在 `TaskTracker::CompleteShutdown`，后台任务包含已开始的 SKIP_ON_SHUTDOWN SQLite 操作。

`0034-Prevent-macOS-thread-pool-shutdown-starvation.patch` 由关闭方提升低优先级 worker，覆盖 pooled/shared/dedicated，处理 Start 与 shutdown 的交错，并在 Join/Destroy 释放 override。正常运行的 QoS、持久化语义和看门狗期限不变。Chromium 源码提交：`8001a459ae6aaf3b75f748e89e5ab66fd481a997`，基线 `6dca5a74b4ecfede44c75ab794f43c0cb7d6be5d`。

## 验证

- 同一 Swift 程序和测试 runner，只替换引擎并重新签名。8 个显式 DEFAULT QoS 的有界 CPU 进程下，旧发布引擎及旧开发引擎的 PB3 均退出失败；修复版 PB3 两次、R3 一次均 exit 0，负载持续至退出。首次 PB3 和 R3 在页面关闭后约 0.6 秒的进程检查中已消失。最终 Join 修正后重新编译的引擎再跑 PB3 通过，首次进程消失检查为关页后 0.649 秒。去除签名后的 Swift 二进制 SHA256 完全相同。
- Chromium worker 相关单测 **21/21 通过**（不自动重试），包括 WorkerCleanupDuringJoin 与新增优先级回归。首次测试发现 Join 等待期间对象自毁后成员访问，已改成等待前转移 token 到局部变量，并经独立复核。
- 新增 Chromium 单测 `ThreadPoolWorkerTest.ShutdownBoostsWorkerBeforeInitializationCompletes`：worker 阻塞于初始化，关闭方提高其内核优先级，不依赖 worker 自行执行 shutdown 检查。
- 运行命令：`engine/incremental.py`；`engine/incremental.py --target base_unittests`；`python3 scripts/with-batch-locks.py --lock /tmp/brk-batch-build.lock -- swift test --jobs 2`；`engine/run-native-core.py quit-worker-smoke-sites --set smoke,sites --app <fixed-app>`。
- Swift 全量单测 **1195 项，2 项跳过，零失败**。smoke/sites 首轮 **14/15**，唯一失败由同时运行的 xctest 窗口遮挡；结束单测后单独重跑 SiteControls-Real 通过。重启恢复场景通过。
- 独立审查最终未发现阻断问题；尚未复现的 dedicated worker 注销边界记录于外部审查报告，不能据此宣称所有退出等待均已消除。

完整日志、采样、负载源码及产物哈希：`~/brk-evidence/quit-fix-20261114/`。本次只交付源码补丁；正式 ARM64/x86_64 引擎须重新构建、验证并更新 `engine/artifacts.json` 后，后续发布才会包含修复。
