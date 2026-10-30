# 原版 Arc 的本地免登录入口调查

2026-10-31，云 Mac，Arc 1.170.0，build 89123。

结论：发行包中确有比“跳过注册”更直接的内置测试认证路径。静态证据支持把 `ARC_UI_TESTS=1` 与 `ARC_FAKE_AUTH=1` 作为后续隔离实验的首选候选。它会构造内置测试用户并生成 `signedIn`、`finalized` 动作，测试模式也会跳过一处正常的用户身份一致性检查。**本次没有启动实验，尚未证明能打开完整浏览器窗口，更没有证明它是受官方支持的离线使用方式。**

没有修改 `/Applications/Arc.app`、现有 Arc profile、UserDefaults、凭据、钥匙串或系统保护；没有启动、关闭或重启 Arc；没有请求后端接受任何虚构登录。所有新文件都在本目录。没有打开成功的 REA target，因此没有关闭其他人的 target 或 daemon。

## 目标与证据来源

直接从 `/Applications/Arc.app/Contents/MacOS/Arc` 读取 universal Mach-O 的 arm64 slice，与先前分析缓存 `/Users/administrator/.cache/arc-target-arm64/Arc` 逐字节比较，相等。arm64 SHA-256 为 `77be289e16a139056dd9d0bf145ad4707d4e217289bb279a333949dcfd39c52d`。结果及七处关键 `BL` 指令的原始字节验证见 [identity-and-branch-checks.json](identity-and-branch-checks.json)。这些验证从已安装文件取字节，不把旧字符串命中当作行为证明。

已按 `reverse-engineer-anything` 及 native guide 工作，并用 `unslop` 整理文字。REA `get_evidence_bundle(detail=summary, operation=analyze_function)` 返回零条当前记录。显式 `open_binary` 失败，原因是当前 MCP 没有 `GHIDRA_INSTALL_DIR`，且 universal Mach-O 不能直接用于该 Ghidra 路径。没有更改工具配置或安装软件。

旧 Ghidra 确实安装过，旧 Unix socket 现在返回 `Connection refused`。保留的 `/Users/administrator/.cache/arc-ghidra/arc-arm64-rea-snapshot.json` 含 59 条记录，均不覆盖本次 auth 函数；旧全量导入记录耗时 18.4 分钟，因此没有重跑。其目标概览 Evidence 为 `ev_8ec227f79f898756250a7d51581532151f95c600bc95922b8d5f21f87ddd3a2b`，只用于目标背景，不能充当本次新 auth 结论的 Evidence。

新结论来自匹配目标的现有 `llvm-objdump` 指令缓存、Swift field metadata 和调用索引，相关完整函数已另存为本目录 `.s` 文件。标注由仓库已有 `c/scripts/fnview.py`、`scan.py` 解析；符号恢复与控制流解释是分析判断，没有伪称为本次 Ghidra 反编译或运行观察。地址均为未加 ASLR slide 的 arm64 地址。

## 已追出的条件和分支

| 问题 | 直接证据 | 能下的结论 |
| --- | --- | --- |
| `ARC_UI_TESTS` 如何读取 | [100b2ace8.s](100b2ace8.s)、[100b2aeb8.s](100b2aeb8.s) | 使用 `NSProcessInfo.environment`，值等于字符串 `1` 才为真。它是进程环境变量，不是 `defaults` 项。 |
| 测试总开关 | [100b2adbc.s](100b2adbc.s)、[100b2ae4c.s](100b2ae4c.s) | `ARC_UI_TESTS=1` 足以使测试总开关为真；另外还检查其他测试来源，本次不依赖它们。 |
| `ARC_FAKE_AUTH` 如何读取 | [100b2ae8c.s](100b2ae8c.s)、[100b2afec.s](100b2afec.s) | 使用相同环境读取器，值需为 `1`。此开关独立于 `SKIP_USER_CREATION`。 |
| 更强的本地候选入口 | [102e00cc8.s](102e00cc8.s)，`0x102e00e08` 至 `0x102e00ed4` | SharedAppFeature 相关路径先检查测试总开关，再检查 `ARC_FAKE_AUTH`。两者都为真时，构造两个 app action，并跳过这里的正常 session 获取分支。 |
| 测试 session 是否已完成 onboarding | [100c1fb7c.s](100c1fb7c.s)，`0x100c1fb9c` 起；调用点 `0x102e00e74`、`0x102e00e78` | 构造内置 `Test User` 和编译进程序的 fake user ID，两个布尔输入均为 `1`，写入 `AuthSession._wasExistingUser`、`_finishedOnboarding`。这是程序自带测试值，不是读取任何账户秘密。 |
| 生成哪些动作 | [102e00cc8.s](102e00cc8.s)，`0x102e00e80` 至 `0x102e00ed0`；[1017e98c8.s](1017e98c8.s) | enum tag 0 和 2 对应 metadata 中的 `AuthFeature.AuthFeature.Action.signedIn` 和 `finalized`；后者带有本地 `AuthenticationResult`。这比仅跳过创建用户 publisher 更接近浏览器入口。 |
| 本地用户检查是否仍会拒绝测试用户 | [102e448d0.s](102e448d0.s)，`0x102e448f0` 至 `0x102e44900`，对照 `0x102e44b08` 至 `0x102e44b14` | 测试总开关为真时直接返回 `0`，与正常 Firebase UID 匹配分支相同。非测试模式会检查 fake ID、`currentUser` 和 UID，存在清理不匹配 session 的分支。这里只证明这一处检查。 |
| 为什么不能把 `SKIP_USER_CREATION` 当成整个免登录开关 | [100b2b15c.s](100b2b15c.s)、[100b2b39c.s](100b2b39c.s) | 必须先满足 `ARC_UI_TESTS=1`，`ARC_AUTH_UI_TEST_STARTING_SCREEN` 为 `signUp` 或 `signIn`，并且 `ARC_AUTH_UI_TEST_SKIP_USER_CREATION=1`。单独设置它不起作用。 |
| `SKIP_USER_CREATION` 实际改变哪里 | [101824c90.s](101824c90.s)，`0x1018252a0` 至 `0x1018253a0`，对照 `0x101825824` 起 | 找到一个直接 consumer，位于 `SignUpScreenReducer`。开关真时走 `Combine.Just` 本地结果，普通创建用户 publisher 位于另一分支。它仍在注册表单的 reducer 内，前面存在表单校验；不是直接创建浏览器窗口。未声称这是全部可能 consumer。 |
| `finishedOnboarding` 能否当成 preferences 开关 | [100c1f528.s](100c1f528.s)、[100c22ff4.s](100c22ff4.s) | 这些命中是 `BaseModels.AuthSession.CodingKeys` 的字符串/枚举转换。没有证明 `defaults write ... finishedOnboarding` 会生效，也没有证明它单独足以建立 session。 |
| 是否支持自定义数据目录参数 | [1007e53e8.s](1007e53e8.s)、[1007e59f8.s](1007e59f8.s)、[100d8f218.s](100d8f218.s) | 参数解析器识别 `--user-data-dir=<value>`，但 ApplicationPaths 只在 Dia 判断为真时走这一解析器。不能据此认定原版 Arc 已隔离数据。详细检查见下文。 |

metadata 依据为仓库 `.audit/arc-evidence/b/swift-fieldmd-types.tsv`：2530 行是 `FakeAuthUITestStartingScreen` 的两个枚举值；2720、2724 行是 AuthSession 与 CodingKeys；6508 至 6517 行包含 AuthFeature actions、state 和 AuthWizard；6542 行包含 SignUpScreen 的 `completed` action。原字符串仅用于定位，控制流结论以上表的指令为准。

## 尚未证明的部分

本次已追到 app 级别的本地认证事件和一处 session 身份检查，但没有验证这些事件在完整启动时必然被发送、后续窗口创建一定成功、是否仍有其他门槛，以及断网时 Chromium 是否正常显示页面。也没有检查所有测试开关对窗口布局、动效、配置加载和数据持久化的影响。因此不能报告“已跳过登录”，也不能把测试模式当成生产版 UI 的完全等价参考。

`ARC_AUTH_UI_TEST_STARTING_SCREEN` / `SKIP_USER_CREATION` 是 onboarding UI 测试路线。优先实验的路线是 `ARC_UI_TESTS=1` 与 `ARC_FAKE_AUTH=1`，不要把两组开关混成一个未经验证的命令。本次未执行任何一组。

## 如果进行本地实验，会改变什么

最小候选是仅在新 Arc 进程中设置上述两个环境变量，使用新建的测试用户数据目录。测试逻辑会在本地构造测试 session 和认证完成事件。程序可能将 session、侧栏或偏好持久化，并可能启动后台网络请求；目前不能承诺只改内存或完全离线。

仅指定 `--user-data-dir` 不能满足此次要求的隔离保证。可复核的下一步应在独立 macOS 测试用户或虚拟机里进行，使用全新 profile、独立钥匙串与偏好目录。实验只需观察浏览器窗口、侧栏和工具栏是否出现，并在该隔离环境中记录写入范围及断网行为，不需要凭据、不需要后端接受 fake 登录。当前云 Mac 的现有 Arc profile 保持原样。

在没有建立该隔离前，可以继续用静态资源和用户自己 Mac 上已登录 Arc 的截图做对照，不应向用户宣称无法跳过，也不应宣称已经可以可靠跳过。

## 追加的隔离检查

已检查程序自带的数据目录和 preferences 隔离代码。结果是找到了明确的隔离缺口，没有建立可直接执行的完整隔离启动方案。

- [10059d3dc.s](10059d3dc.s) 读取 `NSBundle.main.bundleIdentifier`，判断是否以 `company.thebrowser.dia` 开头；`__CFBundleIdentifier` 环境值仅在 bundle identifier 为空时作为回退。已安装 Arc 的 bundle identifier 是 `company.thebrowser.Browser`，所以正常从原包启动时该判断为假。没有尝试改 bundle identity。
- [100d8f218.s](100d8f218.s) 在 `0x100d8f350` 至 `0x100d8f388` 先检查上述 Dia 判断，只有为真才解析 `--user-data-dir`。Arc 分支读取 ApplicationPaths 的另一项配置或回退到 application support 目录。
- [1007e56e0.s](1007e56e0.s) 使用同一个 Dia 判断，只有为真才根据 `--user-data-dir` 生成 `com.dia.instance.<hash>` preferences suite；Arc 分支返回空值。[100d865b4.s](100d865b4.s) 在 suite 为空时直接取 `standardUserDefaults`。因此 `ARC_UI_TESTS=1 ARC_FAKE_AUTH=1` 加 `--user-data-dir` 不能保证隔离 Arc 的 Swift preferences。
- `-customApplicationDataBaseURLPath <path>` 是更符合 Arc 的数据目录候选。[102e5122c.s](102e5122c.s) 的程序内重启参数同时包含该项、`-shouldSkipUnboxingVideo` 和 `-cloudKitSyncEnabled false`。这证明应用会组装这组参数，不证明它们重定向了全部 preferences 或钥匙串。没有实际执行重启。
- [1000035a4.s](1000035a4.s) 的确有生成临时唯一目录并加 `--use-mock-keychain` 的分支，但分支条件是全局字节 `0x104651290`；[100003138.s](100003138.s) 的入口把该字节写为 0。该条件不是后面单独读取的 `ARC_UI_TESTS`，所以不能因看见临时目录/模拟钥匙串代码，就认定开 UI tests 会自动进入此分支。没有穷尽所有动态写入者。
- 另找到 `--onboarding-force-complete` 和 `--onboarding-skip-wizard` 的解析函数，但当前直接调用索引未找到其 consumer。这两个名字没有足够行为证据，不能当成有效替代入口。

精确的剩余问题是：如何同时隔离 Arc 的 ApplicationPaths、`standardUserDefaults`、Arc/Chromium 钥匙串访问及可能的 app-group 位置，并确认测试认证完成后真的显示 Big Browser 窗口。当前没有给出可在现有用户下安全照抄的启动命令。复制 bundle 加外部写入限制可以另行评审，但本次没有执行，也没有修改 OS 或安全配置。

## 可复查命令

以下命令只读取已有分析文件，`-B` 避免 Python 在仓库生成 `__pycache__`。

```sh
cd /Users/administrator/.t3/projects/brk
rg -n 'ARC_AUTH_UI_TEST|ARC_FAKE_AUTH|finishedOnboarding' /Users/administrator/.cache/arc-disasm/facts.tsv
python3 -B .audit/arc-evidence/c/scripts/fnview.py 100b2b15c 100b2b39c 101824c90
python3 -B .audit/arc-evidence/c/scripts/fnview.py 100b2adbc 100b2ae8c 102e00cc8 100c1fb7c 1017e98c8 102e448d0
python3 -B .audit/arc-evidence/c/scripts/callers.py 100b2afec 1
python3 -B .audit/arc-evidence/c/scripts/callers.py 100b2b50c 2
```

本次独立的原始字节核验结果为 `cached_matches_installed=true`，关键直接分支检查 `7/7` 通过。它验证了地址与机器指令来源，不能代替完整 UI 运行测试。
