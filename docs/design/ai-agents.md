# How Brk talks to local coding agents

Read from T3 Code (https://github.com/pingdotgg/t3code, MIT, commit 006d7e38, 2026-11-07), cloned to a scratch folder and read as data; none of its scripts ran. Paths below are in that repository. Brk's code is written in Swift from these notes; nothing is pasted.

What each installed agent actually does was checked on this machine on 2026-11-07: claude 2.1.318, codex-cli 0.164.0, gemini 0.46.0, cursor-agent 2026.01.23. opencode is not installed.

## Finding the agents and PATH

A GUI app starts with launchd's short PATH. Asking `which` from it misses Homebrew and npm tools, and even a found tool can fail: on this machine `gemini` is a `node` script and `codex` is a wrapper script, both of which need the real PATH to run.

T3 reads PATH from the login shell with `$SHELL -ilc`, printing the value between two marker lines so that whatever the shell's startup files print does not matter, with a 5 second limit, killed with SIGKILL, in a detached process with stdin closed, and merges it ahead of the inherited PATH (`packages/shared/src/shell.ts`: `readEnvironmentFromLoginShell`, `buildEnvironmentCaptureCommand`, `mergePathEntries`; `apps/server/src/os-jank.ts`).

Brk does the same in `AgentEnvironment.loadShellPath`, and passes the merged PATH to every agent it starts. It does not import API keys from the shell: the user's decision is that agents run on the account they are signed in to.

## Is it installed, is it signed in, what models

T3 runs each CLI's `--version` first, with a timeout, and treats "command not found" apart from "installed but failed" (`apps/server/src/provider/ClaudeProvider.ts`: `checkClaudeProviderStatus`).

| Agent | How T3 learns about it | What this machine shows |
| --- | --- | --- |
| Claude | Starts the session protocol with a prompt that never yields, so `initialize` answers locally and no model request is sent (`ClaudeProvider.ts`: `probeClaudeCapabilities`). The reply has models with `supportedEffortLevels`, the account, the version. | Works. `claude auth status` prints JSON with `loggedIn`. |
| Codex | `codex app-server`: `initialize`, `account/read`, `model/list` with paging (`apps/server/src/provider/CodexProvider.ts`: `probeCodexAppServerProvider`, `requestAllCodexModels`). `model/list` gives `supportedReasoningEfforts`, `isDefault`, `hidden`. | Works. A signed-out Codex has `account: null` and `requiresOpenaiAuth: true`. |
| ACP agents | `initialize`, then `session/new`, whose reply lists `models` and `modes`, or `configOptions` by category (`packages/provider-acp/src/server/sessionConfig.ts`). | Gemini answers `session/new` with an error saying a key is missing when it has no sign-in. Cursor's says authentication is required. |
| Cursor | T3 has moved to Cursor's SDK (`packages/provider-cursor/src/server/CursorAgentSdk.ts`), which Brk cannot use. | The installed `cursor-agent` has a hidden `acp` command that speaks ACP, so Brk uses that. |
| Gemini | T3 has no Gemini CLI driver of its own; it has Antigravity, and any ACP agent through `packages/provider-acp-registry`. | `gemini --acp` speaks ACP. |
| OpenCode | T3 starts `opencode serve` and talks HTTP with events (`packages/provider-opencode/src/server/OpenCodeRuntime.ts`). | Not installed here. It also has an `acp` command upstream, so Brk treats it as ACP. Untested. |

A trap for signed-out checks: Cursor's ACP `authenticate` with `cursor_login` **starts a browser sign-in** when nobody is signed in (run once here with `NO_OPEN_BROWSER=1`: it returned a login address and nothing else happened). Brk runs `cursor-agent status` first and never calls `authenticate` when that says "Not logged in", and always sets `NO_OPEN_BROWSER`. Gemini gets `NO_BROWSER` for the same reason. Brk reads no credential file for any agent.

## Starting a session and talking to it

**Claude** (`apps/server/src/orchestration-v2/Adapters/ClaudeAdapterV2.ts`). T3 uses Anthropic's Agent SDK, which starts `claude -p` with streaming JSON on both pipes. Brk speaks that directly: `-p --input-format stream-json --output-format stream-json --verbose --include-partial-messages`. One process per session; each user message is a JSON line on stdin. Text arrives as `stream_event` with `text_delta`; tool calls as `tool_use` blocks in `assistant` messages; their results as `tool_result` in `user` messages; the turn ends with `result`. `control_request` lines go both ways: `initialize` and `interrupt` from Brk, `can_use_tool` from the agent. The session id is in `system`/`init`, and `--resume` continues it.

**Codex** (`apps/server/src/orchestration-v2/Adapters/CodexAdapterV2.ts`, `packages/effect-codex-app-server`). `codex app-server`, JSON-RPC on stdio without the `jsonrpc` field. `initialize`, the `initialized` notification, `thread/start`, then `turn/start` per message. Text arrives as `item/agentMessage/delta`, steps as `item/started` and `item/completed`, the end as `turn/completed`. Effort and model go on `turn/start`. T3 sends an `initialize` only once per process because Codex refuses a second. `codex app-server generate-json-schema` prints the protocol of the installed version; Brk's parsers were checked against that and a recorded real turn.

**ACP** (`packages/provider-acp/src/server/AcpSessionRuntime.ts`, `packages/effect-acp`). JSON-RPC 2.0 on stdio. `initialize`, `session/new`, `session/prompt` per message whose reply is the end of the turn, `session/update` notifications with `agent_message_chunk`, `tool_call` and `tool_call_update`. T3 declares what the client can do in `initialize`; Brk declares no file or terminal capability, so the agent uses its own tools under its own rules.

## Streaming

Agents can send many small pieces a second. T3 buffers them and flushes on an interval (`apps/server/src/orchestration-v2/Adapters/ProviderTextDeltaCoalescer.ts`). Brk's `AgentSession` keeps the turn's text and hands the panel at most about thirty updates a second.

The old Brk path had no streaming with real agents: `claude -p --output-format text` and `codex exec` print the whole answer at the end (measured: one stdout chunk from each).

## Stopping

T3 asks first: `interrupt` over the control protocol (`ClaudeAdapterV2.ts`), `turn/interrupt` (`CodexAdapterV2.ts`), `session/cancel` (`AcpSessionRuntime.ts`, which writes the cancel before any replacement prompt can reach the agent). Then it ends processes: a discovery pass over the process table, SIGTERM, a grace period, SIGKILL, with several passes because a process can fork between them (`AcpSessionRuntime.ts`, around `signalPhase`). The comment there is worth keeping: parent-chain discovery misses early double-forks; only Linux cgroups guarantee ownership. On macOS that limit stands.

T3 also starts Claude under a small shell watcher (`ClaudeAdapterV2.ts`: `CLAUDE_GROUP_WATCH_SCRIPT`): the CLI keeps working after its pipes close, so a background shell holds a pipe only the server has and kills the process group when it reads end of file, which covers the server crashing.

Brk (`AgentProcess`, `AgentSession`):

- Every agent starts in its own process group, under the same kind of watcher, so a Brk crash leaves no agent working.
- Stop sends the agent's own interrupt. When the turn ends, whatever it started that was not there when the turn began is ended too. What ran before it (an MCP server) stays.
- A turn that has not ended two seconds after Stop is ended by Brk: the process table is read, the whole tree gets SIGTERM, then half a second later SIGKILL, with a fresh read of the table each time. The next message starts a new process, continuing the agent's own session if it keeps one.
- Closing the panel, another agent chosen, and quit all end the whole tree.

A command that double-forked away before Stop and left the process group is the one case this cannot reach on macOS.

## Tool approvals

**Claude**: `--permission-prompt-tool stdio` sends every tool that needs permission to the host as `can_use_tool`, with the tool's input and `permission_suggestions`. T3 answers `allow` with `updatedInput`, or `deny` with a message; "for the session" adds `updatedPermissions` with `destination: "session"` (`ClaudeAdapterV2.ts`: `permissionResultFromDecision`, `toSessionPermissionUpdates`). Brk leaves out a `setMode` suggestion: for `Write`, Claude suggests switching the whole session to accept edits, which is wider than what the user is looking at.

**Codex**: requests from the server, `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, `item/permissions/requestApproval`, and the older `execCommandApproval` and `applyPatchApproval` (`CodexAdapterV2.ts`, around line 5314). The request lists its `availableDecisions`; Brk offers only those. T3's "approval required" mode is `approvalPolicy: "untrusted"` with the read-only sandbox (`codexRuntimeModeTurnDefaults`); Brk's folder sessions use exactly that.

**ACP**: `session/request_permission` with options of kind `allow_once`, `allow_always`, `reject_once`, `reject_always`; the answer selects one by id, or says `cancelled` (`packages/provider-acp/src/server/clientPolicy.ts`, `adapter.ts`).

## Read-only, and what Brk adds to T3

T3 is a coding tool: every session is one the user started on their own project. Brk also feeds agents page text from the web, which may be written to attack them, so it needs a mode T3 does not center on.

Anything carrying page or link text runs in a read-only session, in an empty temporary folder of its own, deleted afterwards:

| Agent | Read-only | Checked on this machine |
| --- | --- | --- |
| Claude | `--tools ""` (no tools at all), `--permission-mode dontAsk`, `--strict-mcp-config`, `--setting-sources ""`, `--no-session-persistence`, `--disable-slash-commands`, and no `--permission-prompt-tool`. | Real run with the injection page; see the report. |
| Codex | On the process: `-c features.shell_tool=false -c web_search="disabled" -c mcp_servers={} -c sandbox_mode="read-only" -c approval_policy="never"`. On the thread: `sandbox: read-only`, `approvalPolicy: never`, `ephemeral: true`. The sandbox refuses a write in the kernel. | Real run with the injection page; see the report. |
| Gemini | `--acp --skip-trust --approval-mode plan --extensions none --allowed-mcp-server-names brk-none`. Gemini silently turns plan mode back into default in a folder that is not trusted (read in its bundle, seen in `gemini -p`), so the trust flag is needed; it holds for this process, and the folder is empty. | Not signed in here: arguments and handshake only. |
| Cursor | ACP mode `ask`. | Not signed in here: handshake only. |
| OpenCode | ACP mode `plan`. | Not installed. |

On top of that, in read-only sessions Brk answers any approval request itself with no, without showing it, for all agents.

A session with tools on starts only from the panel's Work in a Folder…, in the folder the user picks. Brk refuses home and the disk's root, and no page text goes into such a session. No flag that skips approvals is passed anywhere; a unit test checks each agent's arguments.

## What is left out on purpose

- T3 persists threads and can roll them back; Brk's conversations last as long as the panel is open.
- T3 lets the user change model inside a conversation; Brk reads the choice from the Max pane when a session starts.
- T3 shows Codex's reasoning summaries and Claude's thinking; Brk shows the agent's text and steps.
