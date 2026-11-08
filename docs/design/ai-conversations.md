# Conversations as tabs, pages in answers

Slice D of the AI-native round (docs/design/ai-native.md: 对话是 tab, 在回答里显示页面, the 读对话 and 存页面 tool groups,
steps 3 and 4). Built on slice C's MCP server, bridge, approvals and typed tool results (docs/design/ai-agents.md,
"Browser sessions"). T3 Code was read as data for the tool shapes: its `t3_thread_list`, `t3_thread_search`,
`t3_thread_read`, `html_preview` and `html_render`.

## What the user sees

- **Every conversation is saved and is a tab.** When the first message of a conversation goes out, a row appears at the
  top of the Space's Today, where a new tab goes: a two-bubble icon and the first message as its title. The row is an
  ordinary tab. It can be pinned, renamed, moved into a folder, found by its title in the command bar, archived by its ×
  or by auto-archive, and brought back from the archive. While a turn runs, the row shows the loading state.
- **The panel and the tab.** The Max panel stays the quick place: the command bar's question, Ask AI on tabs, a drop of
  tabs. Its header has **Open as Tab**, which moves the conversation into its tab, shown full size in the content area.
  A click on the row does the same. The session and a running turn go on; nothing is asked again. A conversation is in
  one place at a time: showing its tab takes it out of any panel.
- **Close keeps it.** The panel's Close puts a saved conversation away. A running turn goes on out of sight, its answer
  lands in the saved transcript, and the row shows it is still working.
- **Another day.** A conversation tab shown after a relaunch shows its saved transcript. Its next message starts a
  session that continues the agent's own session: Claude `--resume <session id>`, Codex `thread/resume`. If the agent
  no longer has that session, the same message goes to a new session with the transcript ahead of it, and a notice
  says so. Read-only conversations (Ask on Page, Browse for Me) never keep a session, so they always continue this way.
- **Pages in answers.** A page the agent renders shows inline in the transcript where it was made, as wide as the text,
  in the panel and in the conversation tab. Under it is a caption row: the page's title and **Keep as Tab**. The page's
  own context menu has the same item. Once kept, the button reads Show Tab.
- **Kept pages.** A kept page is a row at the top of Today that shows the page in its card. It keeps its HTML, its data,
  and the conversation it came from.
- **Links in pages.** A click on an http(s) link in a page opens it as a tab. If the agent had read page text before it
  wrote that page, and the address is new to the profile, a card asks first: "Open …?" with Open and Cancel. This is
  the same rule as C's `brk_tab_open`.

### UX decisions and why

| Decision | Reason |
|---|---|
| A row appears at the first message, not only on Open as Tab | The user's example expects the conversation tab back after a quit without having asked for it. A row that only appeared on request would lose most conversations. Today's auto-archive keeps the cost low: unused conversation rows archive like tabs and stay findable. |
| The row goes to the top of Today, not shown | That is where a new tab goes. The panel already shows the conversation, so switching the page away would be a surprise. |
| Open as Tab, row click and Close never stop a running turn | A conversation is a tab now, and tabs keep working out of sight. Stop is the only way to stop. |
| One view class for the panel and the tab | Both behave the same: streaming, steps, approvals, chips, @, pages. The tab lays the same parts out in a centred column of at most 720 pt on the card colour of Brk's native pages (History's white or #202124). |
| Keep as Tab is a button under the page, plus the page's context menu | People look for an action next to the thing. The first real run also showed that a text link inside the transcript was hard to target reliably. |
| The agent's `brk_page_save` keeps the page without showing it | The agent works for the user in the background. Taking the user away from the conversation to show the page would be a surprise. |
| No "Delete conversation" yet | Archiving the row is the way out of sight. The record stays, so the read tools can still find it. |

## Storage

- `Doc.conversations[id]` (`StoredConversation`) holds the profile, title, agent, model, the agent's own session id
  (`resume`), whether page text reached it (`readPages`, `flagged`), and its items. Unanswered approvals are not saved.
  The first question is the transcript's first `.user` item. The panel still shows it as its title and skips that row.
- `Doc.aiPages[id]` (`AIPageRecord`) holds the title, height, data (JSON text), conversation, profile, `readPages`, and
  the path of its HTML file.
- Neither is in state.json. `BrkApp/ConversationFiles.swift` writes `<data>/Conversations/<id>.json`,
  `<data>/AI Pages/<id>.json` and `<id>.html`. Folders are 0700, writes are atomic and run off the main thread, and only
  files that changed are written. They are loaded before the first render (`SystemEvent.conversationsLoaded`). A record
  always points at its own HTML file in `AI Pages`, whatever its file says. Records of a deleted profile are skipped.
- Rows are tabs at `brk://conversation/<id>` and `brk://ai-page/<id>`. Like Easels and History, `NativePages` keeps
  them out of every browser, and the codec keeps their addresses on restore.

## Live state

A conversation's live state is an `AIAnswerSnapshot` in one of two places: a window's panel (`AISession.answers`, as
before), or `AISession.tabAnswers[id]` while its tab shows it or a turn of it runs. Every rule that touched the panel's
conversation now takes an `AIAnswerHost` (`.panel(window)` or `.tab(id)`). The tab view's controls send
`.assist(.inTab(id, intent))`. After each input, `reconcileConversations` moves a conversation whose tab is shown out of
any panel, drops idle tab conversations that are not shown (their transcript is already saved), and closes the session
of every conversation that lost its live state. The panel's Stop cancels only the panel's turn.

## Tools (Brk's MCP server, slice C's socket and bridge)

| Tool | What it does |
|---|---|
| `brk_conversation_list` | This profile's conversations, newest first: id, title, when, agent, model, message count, `link`. Paged with `cursor`, at most 50. |
| `brk_conversation_search` | Title matches, then message text (all words, then any word), with a snippet. Not exhaustive. |
| `brk_conversation_read` | Messages oldest first (user, assistant, rendered pages), `afterPosition` paging, `limit` up to 50, `maxCharsPerItem` up to 20,000, cut-off text continued with `itemId` and `textOffset`. |
| `brk_html_preview` | Renders a complete HTML document off screen in the page sandbox. Returns `contentHeight`, console lines and a PNG (MCP image content). The default width is the reply's width where the conversation shows now. |
| `brk_html_render` | Shows the page inline in this conversation with `title`, `height` (80 to 2000) and optional `data`. Returns `pageId`. |
| `brk_page_save` | Keeps one of this conversation's pages as a tab. |

Rules added to the system prompt: read a conversation before answering about it, and name it by its link. Show trends,
comparisons and flows as a chart or diagram even unasked: `brk_html_preview`, then `brk_html_render`. Keep a page only
when asked. The page tools' descriptions carry T3's layout rules and Brk's variable names. Reading conversations counts
as page text, because earlier answers can quote pages, so a later `brk_tab_open` to a new address asks. Only the
conversation's own profile is visible.

## The page sandbox

An agent that may have read hostile pages writes the HTML. It is shown in `PageSandboxView` (BrkContent):

1. **Another engine.** WebKit, not the Chromium of the profiles. No profile's cookies, storage, cache, service workers
   or extensions exist in it. Each view has its own non-persistent data store, discarded with the view.
2. **One resource on a private scheme.** `brk-page://page/` serves the page's document and nothing else, with
   `Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:;
   font-src data:; media-src data: blob:; connect-src 'none'; frame-src 'none'; child-src 'none'; worker-src 'none';
   object-src 'none'; manifest-src 'none'; form-action 'none'; base-uri 'none'; sandbox allow-scripts`, plus
   `X-DNS-Prefetch-Control: off`, `Referrer-Policy: no-referrer` and `Cache-Control: no-store`. The page's own markup can
   add rules but cannot remove these. `sandbox` without `allow-same-origin` gives an opaque origin: `document.cookie`
   stays empty, and localStorage, sessionStorage and IndexedDB throw SecurityError.
3. **A content rule list.** It blocks every load that is not `brk-page:`, `data:`, `blob:` or `about:`. CSP does not
   cover `<link rel=preconnect>`, which opened a TCP connection to a local listener in the test, whether written in the
   page or added by script. The rule list stops it. The page does not load until the list has compiled. (The first
   version's list used `|` in a filter, which WebKit refuses, so it silently did nothing. The test found this.)
4. **No navigation.** The navigation delegate allows the first main-frame load of `brk-page://page/` and cancels
   everything after it: link default actions, `location`, `location.replace`, meta refresh, forms, frames. Window opens
   return nil. Alerts, confirms, prompts, file pickers and camera or microphone requests are answered "no" without
   showing anything.
5. **Links go to Brk only from a real click.** Brk's bridge script runs in an isolated script world that the page
   cannot see (`window.webkit.messageHandlers.brk` is undefined in the page). It takes `click` events with
   `isTrusted`, and only on `a[href]` with an http(s) address. A script's `a.click()` opens nothing. The navigation
   delegate never treats a navigation as a click, because WebKit does not say whether a script started it.
6. **What the page gets.** `window.brk.data` (frozen), theme variables on `:root` from Brk's light, dark and Space
   colours, updated live with a `ui/notifications/host-context-changed` message, and a base sheet that leaves html and
   body without a background. Console lines, errors and CSP violations go back to the agent through the preview, at most
   50 lines of 500 characters each.

Proof (`Tests/BrkContentTests/PageSandboxTests.swift`, which runs real WebKit in the test process):

- A local TCP listener counts connections while a page uses stylesheet, preconnect, dns-prefetch, prefetch, preload,
  icon, `@import`, a CSS background, `@font-face`, a script `src`, img, video, audio, object, embed, iframe, a form
  submit, fetch, XHR, sendBeacon, WebSocket, EventSource, Worker, `new Image`, `window.open`, meta refresh, `location`
  and `location.replace`. It counts 0. The page is still on its first address, and only that one navigation was allowed.
- Cookies are empty, the three storages throw SecurityError, Cache Storage does not open, and `window.origin` is "null".
- A script's click opens nothing. Real mouse events on an http link and on a `target=_blank` link reach Brk. A `file:`
  link does not.
- The page reads its data and the theme, the theme changes live, and the page cannot see the bridge.
- The preview has the right width, content height and console lines.

The engine choice is a security trade-off for the user to know about: pages run in the system's WebKit, which macOS
updates, not in Brk's bundled Chromium.

## The seam for self-updating AI pages (step 5)

A kept page has everything step 5 needs to draw it again. `AIPageRecord.conversation` names the conversation that made
it, and that conversation can be continued (its saved session or its transcript). `data` is the JSON the page reads as
`window.brk.data`, and `html` is the document. Step 5 can add a schedule to the record, continue the conversation with
"refresh the data", and have the agent call a typed tool, for example `brk_page_update(pageId, data)`, that replaces
`data` and re-renders. The page's own edits (ticks, notes) would need a second bridge message, which the page sandbox
does not offer yet.

## Limits

- The panel's drop target and @ work in a conversation tab too, but other menus that act on "the panel" do not know
  about tabs.
- A tab conversation runs in the window it was last typed in. Closing that window cancels its running turn.
- No delete for conversations. No search of conversation text in the command bar: the bar searches row titles, and
  the agent's tools search text.
- Agents' tab tools do not list conversation or page rows; the conversation tools cover them.
