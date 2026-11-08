# Live AI pages

Slice E of the AI-native round (docs/design/ai-native.md: 会自己更新的 AI 页面, 安全与权限, step 5). It builds on slice D's
kept pages (docs/design/ai-conversations.md): a kept page has its HTML file, its data (`window.brk.data`) and the
conversation that made it. Muse Spaces (Meta, 2026-11-06) was the reference, from press coverage only: a page made in
chat, refined by asking, that the user ticks and notes in, that keeps itself up to date in the background, and that can be
pinned, hidden or shown on chosen days. Brk takes the page, not an agent persona.

## What the user sees

- **Asking for one.** "盯着这三个商品页的价格，每小时更新一次" in a conversation: the agent reads the tabs, draws the page with
  its data, the shape of that data and the addresses it came from, and keeps it as a tab that refreshes every hour. The
  row says so in its tooltip ("Refreshes every hour · last refresh brought new data").
- **The row's menu.** After Arc's items and Ask AI: **Refresh ▸** Never, Every Hour, Every Day at 9:00, Every Monday at
  9:00 (and the page's own schedule when it is another one); **Refresh Now**; **Refresh With ▸** the small model of the
  basic features (Haiku 5.5, GPT-6 Luna) or the conversation's own model; **Show in Today ▸** Every Day, Weekdays,
  Weekends, and each day.
- **The mark.** When a refresh changed the data since the user last looked, the row shows a dot in the Space's colour at
  its trailing end; a refresh that was stopped or failed shows the warning sign. Showing the page clears both. A refresh
  in progress shows the row's loading state.
- **The conversation hears of it.** A refresh that changed the data, or was stopped, adds one line to the conversation
  ("Refreshed “Price Watch”: new data."). One that found nothing new adds nothing.
- **Ticks and notes stay.** A page the user ticks or notes in saves that itself; it is there after a relaunch and after
  every refresh.
- **Changing the page.** Asked in the conversation ("加一个备注框"), the agent changes the kept page with
  `brk_page_update`; its tab shows the change. A refresh never changes the HTML.
- **Shown on chosen days.** A page shown on Mondays only is out of Today on other days (unless the window shows it), is
  still found by the command bar, and is not auto-archived while it waits for its day.
- **Conversations.** Closing a conversation's row archives it like a tab. The archive's context menu on a conversation or
  a kept page has **Delete Conversation…** / **Delete Page…**, which asks first and then deletes the transcript, every page
  it made and their rows. The command bar finds conversations by title and by what was said (and by meaning, through
  slice B2's index, when the search model is on this Mac); choosing one opens its tab.

### UX decisions and why

| Decision | Reason |
|---|---|
| The schedule is set by the agent from the user's words, and shown and changed in the row's menu | People ask in words ("每小时"); the menu is where a person looks to change or stop it later, and it states what will run. |
| Four schedules: never, hourly, daily at a time, weekly on a day and time; presets in the menu | Covers the examples (prices hourly, a weekly list) without a scheduling UI. The agent can set any time; the menu offers 9:00. |
| The first refresh is at the next slot, not at once | The page was just made from fresh data. |
| A missed slot runs once at the next launch | The user wants current data, not seventy-two catch-up runs. |
| The small basic model by default, the conversation's model as a choice | A refresh is a narrow task; it runs unattended and often, so it should cost little. |
| A dot for new data, the warning sign for a stopped refresh | Arc's rows have no unread mark; a dot in the Space's colour is the smallest addition, the size of Arc's dot on a Favorite. The warning sign is the one Live Folders already use for a failed refresh. |
| Looking at the page clears the mark | Same as reading an unread item. |
| Only refreshes that changed something, or stopped, write into the conversation | An hourly page would otherwise fill its conversation with "nothing new". |
| Ticks and notes are a separate `saved` object, never part of `data` | A refresh replaces `data` whole; keeping the user's edits apart means a small model cannot lose them. The page keys them by item id. |
| Show in Today hides the row; it stays findable and is not archived | Muse's "scheduled to appear". Archiving it on its off days would lose it from Today on its day. |
| Delete for good only from the archive, with a sheet that says what goes | Closing a row stays reversible; deleting a transcript and its pages is not, so it is one step further away and asks. |
| Conversation rows in the command bar: title matches first, then what was said, at most two, after the typed row | Like history: found by content, never above what the user typed. |

## A refresh: what it can and cannot do

A refresh runs with nobody there to answer an approval, so nothing in it asks; what it may not do is refused.

**It can:**
- read this profile's tabs, archive and history (`brk_tab_list`, `brk_tab_search`, `brk_tab_read`), with archive and visit
  dates;
- read an address the page listed as a source when it was made, and only if the profile has visited exactly that address
  (`brk_page_source_read`): loaded fresh in a hidden reader in the profile, as slice C reads unloaded tabs;
- write the page's data once it fits the page's shape and the 100 KB cap (`brk_page_update_data`);
- see what the user saved in the page (in its message), and the conversation so far.

**It cannot:**
- run a command, read or write a file, fetch or search the web, use a skill, a plugin, a hook or another MCP server:
  Claude runs with `--tools ""`, `--setting-sources ""`, `--disable-slash-commands`, `--strict-mcp-config` with Brk's
  server only, `--permission-mode dontAsk` and `--allowedTools` naming the five tools; Codex runs `app-server` in the
  read-only sandbox with `approval_policy="never"`, `web_search="disabled"`, `mcp_servers` = Brk's only, and its tool
  features off (shell, unified exec, view image, apps, plugins, hooks, helpers, browser and computer use, skill search,
  image generation, goals, tool suggestions, sleep, code mode);
- open, show, close, move, group or split a tab, read a conversation, preview, render, keep or change a page: Brk's
  server lists only the five tools to a refresh and refuses any other name;
- load an address the page did not list, or one the profile has not visited (an address with something added to it is
  another address);
- change what the user saved in the page, or the page's HTML;
- continue the conversation's own agent session, which has the conversation's tools: the refresh starts a fresh session
  with the transcript as text.

**What stops it:** everything it reads (page text, and the titles a list or search returns) goes through the injection
check (slice B2's phrase patterns, then the decision model). A flag ends the refresh at once: the tool result carries no
text, every later call is refused, the data stays as it was, the row gets the warning sign and the conversation a line
saying why. A refresh that has not finished in four minutes is stopped the same way.

**When it runs:** only while Brk runs, only for a kept page whose row is in the sidebar (not archived), only with Max on,
only once its agent has said it is ready, and with a standard window of the page's profile open. A slot that passed while
Brk was closed runs once at the next launch.

**What it costs:** the account the user chose for that agent in the Max pane (subscription or API key), on the page's
refresh model. Its tokens are their own line in the Usage card, "Live Page Refresh". A refresh stopped in the middle is
asked to stop first so the agent can still report its tokens.

## Data shapes

The page declares the shape of its data with `dataSchema` when it is rendered (a small part of JSON Schema: `type`,
`properties`, `required`, `additionalProperties`, `items`, `enum`, `minimum`, `maximum`, `maxLength`, `minItems`,
`maxItems`; `AIPageShape` in BrkDomain/LivePages.swift). Without one, the shape of its first data stands for it: the same
types, every key it had required, extra keys allowed, a null allowing anything. `saveSchema` is the shape of what the page
saves; without one, any JSON object. A shape is at most 20 KB and 16 levels deep.

## The page's own saves

`window.brk.save(object)` in the page world posts one message to the `brkSave` handler, which answers so the promise
settles. The view checks it (a JSON object, at most 64 KB, fitting the save shape, at most 60 a minute) and the reducer
checks it again before it is kept in the page's record (`saved`, read back as `window.brk.saved` at the next load). A
preview (`brk_html_preview`) saves nothing. Nothing else crosses: there is no other page-world handler that changes
anything, and the save neither navigates nor loads.

## Storage

`AIPageRecord` gains `schema`, `saveSchema`, `saved`, `sources`, `live` (schedule, model, weekdays, last run, last outcome,
when the data changed, when the user last looked) and `revision` (goes up when the data or the HTML is replaced, so
views load the page again; a save does not). All are optional, so slice D's files load unchanged.

## Code

- BrkDomain: `LivePages.swift` (schedules, weekdays, shapes, the refresh run and its events), `Rules/LivePageRules.swift`
  (saves, schedule checks on the clock tick, refresh events, the row's mark and menu, delete for good).
- BrkApp: `AgentAccess.refresh` (Claude and Codex command lines), `BrkToolService.Mode.refresh` (tool list, refusals,
  source reads, the data tool, the flag), `AIServices.refreshPage`, `Agents/LivePageRefresh.swift` (the one message).
- BrkContent: `PageSandboxView` `saved`, `saveSchema`, `onSave`; page views reload on `revision`.
- BrkSidebar: the row's mark. BrkLibrary: Delete for good. BrkOverlays: conversation rows in the command bar.
