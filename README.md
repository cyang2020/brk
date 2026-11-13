<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/media/readme/banner-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="docs/media/readme/banner-light.svg">
  <img alt="Brk: Arc, but better" src="docs/media/readme/banner-light.svg" width="100%">
</picture>

<p align="center">
  <a href="https://github.com/cyang2020/brk/releases/download/latest/Brk-arm64.dmg"><img src="https://img.shields.io/badge/Download-Apple%20silicon-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download for Apple silicon"></a>
  <a href="https://github.com/cyang2020/brk/releases/download/latest/Brk-x86_64.dmg"><img src="https://img.shields.io/badge/Download-Intel-555555?style=for-the-badge&logo=apple&logoColor=white" alt="Download for Intel"></a>
  <a href="https://cyang2020.github.io/brk/"><img src="https://img.shields.io/badge/Website-cyang2020.github.io%2Fbrk-1a4fe0?style=for-the-badge" alt="Website"></a>
</p>

<p align="center">
  <b><a href="#download">Download</a></b> ·
  <a href="https://cyang2020.github.io/brk/">Website</a> ·
  <a href="https://github.com/cyang2020/brk/issues/new/choose">Report a bug</a> ·
  <a href="https://github.com/cyang2020/brk/issues/2">Bug fixes</a> ·
  <a href="https://github.com/cyang2020/brk/discussions">Discussions</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-Apple%20silicon%20%26%20Intel-555?style=flat-square" alt="Apple silicon and Intel">
  <img src="https://img.shields.io/badge/Swift%206-AppKit-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6, AppKit">
  <img src="https://img.shields.io/badge/engine-Chromium%20156-4285F4?style=flat-square&logo=googlechrome&logoColor=white" alt="Chromium 156">
  <img src="https://img.shields.io/badge/account-none%20needed-2ea44f?style=flat-square" alt="No account">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#t-upgraded">⌘T, upgraded</a> ·
  <a href="#everyday-upgrades">Everyday upgrades</a> ·
  <a href="#ai-on-your-mac">AI on your Mac</a> ·
  <a href="#more-ai-better-than-dia">More AI</a> ·
  <a href="#arc-pixel-for-pixel">Arc, pixel for pixel</a> ·
  <a href="#move-in-from-arc-chrome-or-safari">Move in</a> ·
  <a href="#not-in-brk-yet">Not yet</a> ·
  <a href="#download">Download</a> ·
  <a href="#bug-fixes">Bug fixes</a> ·
  <a href="#feedback-and-bug-reports">Feedback</a>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/media/readme/features-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="docs/media/readme/features-light.svg">
  <img alt="Four things Brk adds: an upgraded ⌘T, AI on your Mac, more AI than Dia, Arc pixel for pixel" src="docs/media/readme/features-light.svg" width="100%">
</picture>

<p align="center">
  <img src="docs/media/ai-panel-answer.png" width="900" alt="Brk with the sidebar, a Wikipedia page and the AI panel answering with a table">
</p>

Everything you know from Arc is here: the sidebar, Spaces, Favorites, Pinned tabs, split view, Little Arc, Peek, Boosts, the Library, the command bar and the shortcuts. Brk rebuilds Arc 1.170 feature by feature, from Arc's own measurements. On top of that it adds the things Arc never had.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/media/readme/divider-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="docs/media/readme/divider-light.svg">
  <img alt="" src="docs/media/readme/divider-light.svg" width="100%">
</picture>

## ⌘T, upgraded

<p align="center">
  <img src="docs/media/cmdt-quick-actions.gif" width="800" alt="Quick actions in the command bar">
</p>

Inspired by Raycast, the command bar does much more than open pages. Type, and the answer is already there. Type a word and press **Tab** to switch the bar into a mode.

| Type | You get |
| --- | --- |
| `2^10 * 3`, `15% of 240` | The answer in the bar. Return copies it. |
| `100 usd in eur`, `5 km in miles`, `time in tokyo` | Currency, unit and time-zone conversions. |
| `file` + Tab, then a name or what the file is about | Files on your Mac, by name or by meaning, from a local index: a query takes about 20 ms. Return opens, ⌘Return reveals in Finder, ⌥Return copies the path. |
| `app` + Tab, or just the app's name | Open any app. |
| `emoji` + Tab | Find an emoji and copy it. |
| `translate` + Tab | Translate text, or the whole page. |
| `define` + Tab | The macOS dictionary. |
| `color` + Tab, or `#ff5500` | A colour in hex, RGB and HSL. |
| `window` + Tab, or `left half` | Put the window on a half, centre it, maximise it or move it to the next display. |
| `split` + Tab | Open a tab or a page beside the current one. |
| `claude`, `gpt`, `gemini`, `cursor` + Tab | Ask that agent, with the current tab attached. |
| `page`, `summarize` + Tab | Ask about the page you are on, or summarise it. |
| A site's name + Tab | Search inside that site. |
| A command, such as `dark mode` or `new space` | Run it. Every menu command is reachable by name. |
| Words from an old AI conversation | Find the conversation and continue it. |

Most modes also answer to Chinese words: 问, 翻译, 查, 分屏, 窗口, 文件, 应用, 表情, 算, 颜色.

The ordinary results (open tabs, history, suggestions, top sites) are ranked by a port of Arc's own scoring, so the first row is the one Arc would pick. It learns from you: pages you type often and commands you run rise to the top.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/media/readme/divider-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="docs/media/readme/divider-light.svg">
  <img alt="" src="docs/media/readme/divider-light.svg" width="100%">
</picture>

## Everyday upgrades

<p align="center">
  <img src="docs/media/library-download-flight.gif" width="800" alt="A download flies into the Library button, and resting on the button lists recent downloads">
</p>

**Downloads where you look.** A new download flies from your click into the Library button. Rest the pointer on the button to see your four newest downloads and captures, with progress, preview and drag-out.

<p align="center">
  <img src="docs/media/side-buttons-spaces.gif" width="800" alt="Mouse side buttons step through Spaces over the sidebar">
</p>

**Your mouse works everywhere.** Back and forward buttons and mouse-driver swipes go back and forward over a page and switch Spaces over the sidebar. ⇧⌘] and ⇧⌘[ step through tabs, and a middle-click on a tab closes it.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/media/readme/divider-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="docs/media/readme/divider-light.svg">
  <img alt="" src="docs/media/readme/divider-light.svg" width="100%">
</picture>

## AI on your Mac

<p align="center">
  <img src="docs/media/local-agents-and-models.png" width="800" alt="Settings: Claude Code as the AI, and the models on this Mac">
</p>

**No new subscription.** Brk uses the Claude Code or Codex already installed on your Mac, signed in to the Claude or ChatGPT plan you already pay for. No API key and no Brk account.

**The small jobs never leave your Mac.** Naming tabs and groups, tidying Today into groups and spotting duplicate tabs can run on small models on your Mac (Settings → Max → On This Mac). They don't call a large model, cost nothing and keep working offline.

<p align="center">
  <img src="docs/media/search-by-meaning.png" width="700" alt="The command bar finding a tab by what it is about">
</p>

**Search by meaning, in milliseconds.** Type what a page or a file is about, not its name, and the command bar finds it: the tab, the page you visited, or the document on your Mac. A local embedding model (EmbeddingGemma) answers in about 20 ms, and the index never leaves your Mac.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/media/readme/divider-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="docs/media/readme/divider-light.svg">
  <img alt="" src="docs/media/readme/divider-light.svg" width="100%">
</picture>

## More AI (better than Dia)

<p align="center">
  <img src="docs/media/ai-drag-tabs.gif" width="800" alt="Dragging tabs into the AI panel">
</p>

**An agent that can see your tabs.** Open the AI panel with ⌥⌘A, or drag a tab to the right edge of the window. Drag in more tabs, or type @ and part of a tab's name. The agent reads them, compares them, and can open, close, group, move and split tabs for you.

<p align="center">
  <img src="docs/media/ai-hover-tabs.gif" width="800" alt="Hovering a conversation lights up the tabs it used">
</p>

**Every conversation is kept, per Space.** Come back tomorrow and carry on. Rest the pointer on a conversation and the tabs it used light up in the sidebar.

<p align="center">
  <img src="docs/media/ai-page.png" width="800" alt="An AI page saved as a tab">
</p>

**Pages that keep themselves up to date.** Ask for a price watch or a weekly reading list. The agent builds a page, you save it as a tab, and it refreshes itself on the schedule you pick. Tick things off and take notes right in it.

<p align="center">
  <img src="docs/media/approval.png" width="700" alt="An approval card in the AI panel">
</p>

**You stay in charge.** Page text is checked for hidden instructions before an agent sees it, and once a conversation has read a page, every tool the agent wants to run waits for your OK.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/media/readme/divider-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="docs/media/readme/divider-light.svg">
  <img alt="" src="docs/media/readme/divider-light.svg" width="100%">
</picture>

## Arc, pixel for pixel

<p align="center">
  <img src="docs/media/arc-brk-window.png" width="900" alt="Arc 1.170 on the left, Brk on the right">
</p>

Arc 1.170 on the left, Brk on the right, same window and same pages: 0.14% of the pixels differ, and the visible one is Arc's update button. Sizes, colours, timings and rules are read from Arc's own app and compared with the real Arc on the same screen. Of the 148 Arc features in the ledger (`docs/completion/features.json`), 124 are verified.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/media/readme/divider-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="docs/media/readme/divider-light.svg">
  <img alt="" src="docs/media/readme/divider-light.svg" width="100%">
</picture>

## Move in from Arc, Chrome or Safari

<p align="center">
  <img src="docs/media/onboarding-import.gif" width="800" alt="Brk's first-run screens: welcome, your name, pick a browser, unlock passwords, progress, bookmarks, Favorites, theme, Max, the summary and Brk 101">
</p>

The first time you open Brk, a full-window setup walks you through it in Arc's order: a welcome, what to call you (kept on your Mac, there is no account), which browser to bring along, your bookmarks, Favorites, a theme, the ad blocker, Max and the default browser. It ends on a summary of what came over, then opens Brk 101. Most steps can be skipped.

<p align="center">
  <img src="docs/media/arc-import.png" width="900" alt="Picking Arc as the browser to import from, and the summary after importing: 2 Spaces, 11 pinned and Today tabs, 4 Favorites, 184 history visits">
</p>

**Brk reads the other browser directly**, with no export step for most of them:

| From | What comes over |
| --- | --- |
| **Arc** | Spaces, pinned tabs, Today, folders, split views and Favorites, one to one, plus history, passwords and site logins |
| **Chrome, Brave, Edge, Vivaldi, Opera, Opera GX** | Bookmarks (into Pinned, in a folder "Imported from Chrome" and so on), history, passwords and site logins, profile by profile |
| **Safari** | Export your browsing data from Safari (File › Export Browsing Data) and drop the ZIP in: bookmarks, history and passwords. Safari 17 and older go through Full Disk Access instead |
| **Firefox** | Bookmarks and history (quit Firefox first) |
| **A file** | An exported HTML, JSON or CSV file |

History covers the last 90 days. Passwords and site logins are encrypted by the other browser, so macOS asks for your Mac's password once per profile; Brk explains this before the prompt appears and you can switch them off. Passwords go into Brk's own Chromium password store, so login forms fill in by themselves; passwords imported while Brk is running start filling in after a restart. Brk copies the other browser's files before reading them, so Arc, Chrome and Safari can stay open, and nothing in them is changed. To import again later, choose **Brk › Import from Another Browser…**; a second import adds only what is new.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/media/readme/divider-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="docs/media/readme/divider-light.svg">
  <img alt="" src="docs/media/readme/divider-light.svg" width="100%">
</picture>

## Download

Download the disk image for your Mac:

| Your Mac | Download |
| --- | --- |
| Apple silicon (M1 and later) | **[Brk-arm64.dmg](https://github.com/cyang2020/brk/releases/download/latest/Brk-arm64.dmg)** |
| Intel | **[Brk-x86_64.dmg](https://github.com/cyang2020/brk/releases/download/latest/Brk-x86_64.dmg)** |

Open it and drag **Brk** into Applications. Builds are signed with a Developer ID and notarized by Apple, so they open with a double-click. Needs macOS 14 Sonoma or later. The links always fetch the newest build: [Latest build](https://github.com/cyang2020/brk/releases/tag/latest) is rebuilt from `main` after every change, and versioned releases appear on the same page when they are tagged. How the pipeline works is in [`docs/release.md`](docs/release.md).

## Bug fixes

**2026-11-13**

- **Site controls reopened after closing, or Command-W closed the tab behind them.** Clicking outside now closes the site controls. Command-W closes the popover while keeping the tab open. Escape closes a Settings explanation and leaves Settings open. Build 40.
- **Some text became unreadable in dark mode.** Little Arc addresses, headings in site controls, dialog fields and keycaps, Library labels, AI conversation details, and Space names now stay readable against their backgrounds. Build 40.
- **Onboarding tiles and badges were hard to read.** Favorites letter tiles keep enough contrast with white letters. The Recommended badge uses a lighter accent in dark mode. Build 40.
- **Settings and menu commands did nothing after the last browser window closed.** Those commands now reopen a browser window and show their page or panel. Build 40.
- **Reload stopped working after choosing Stay.** Refusing a reload now clears the pending reload, so the next Command-R works. Page dialogs identify the site instead of displaying the full address. Build 40.
- **Context menus lost actions near the bottom of the screen.** Page menus and Library download menus now open above the pointer when there is not enough room below it. Build 40.
- **Canceling Print or Save left a status notice on the page.** A cancellation that leaves no file now clears the notice. Successful saves show readable, centered text. Warnings about files that remain on disk stay visible. Build 40.
- **Some Settings controls had no accessible button names.** Profile, app icon, and Air Traffic Control controls now expose named buttons. Disabled controls stay inactive. Build 40.

- **Empty Brk windows appeared in Mission Control.** Chromium’s transparent page hosts were listed as separate windows. Brk now keeps them out of Mission Control and window cycling, including after leaving full screen. Build 38.
- **Dark pages had a pale, rough rim around their rounded corners.** The white card fill and shadow backing showed through the edge pixels. They now stop inside the page edge, so the corner blends with the page and Space. Build 38.

Every fix, newest first, with the first build that has it (Brk › About Brk shows yours). The same list is on GitHub as [Bug fixes](https://github.com/cyang2020/brk/issues/2): click **Subscribe** there to get a notification for each new fix.

**2026-11-12**

- **Four ways to crash Brk.** Importing an ad-block list with an empty option (such as `$domain=`); converting a very large time in the command bar; a history address longer than 64 KB, which crashed Brk again a few seconds after every launch; typing only "|" in Browse for Me. None of them crashes now. Build 34.
- **Brk slowed down or locked up.** Browsing history was never trimmed and was saved in full on every change; the History and Media pages rebuilt every row and loaded every full-size picture on each key press; a page that kept showing alerts locked the whole app; a connected sync folder rewrote the whole state every minute. History now keeps a limited span, the pages load only what they show, and a page's alert stops only that page. Build 34.
- **Tabs, history and settings could be lost.** A Live Folder refresh deleted tabs you had put in it; Delete on the History page could remove different visits from the ones checked; recording a shortcut picked up typing in browser windows and changed the shortcut; an AI message over 2,000 characters vanished with its text; Little Arc's Open in dropped its other tabs; undoing a Space delete flattened its folders; with Restore Windows on Launch off, tabs reopened at old addresses. All fixed. Build 34.
- **Private browsing leaked into normal browsing.** Open Link in Incognito Window and Open in Little Brk from an incognito window opened the link in your normal profile; incognito favicons and command bar suggestions were stored in a shared disk cache and cookie store; a print that timed out left the page's PDF behind; deleting a profile left its Easels and AI conversations on disk. Private windows now keep nothing, and a deleted profile takes its files with it. Build 34.
- **Features that did nothing.** Codex in a tab conversation refused every command without asking you (it now asks); changing the model in the middle of a conversation broke the next message; Stop on a first reply cut off Brk's tab tools; Print and Save Page As dialogs closed themselves after a minute; the Little Arc shortcut sent your typing to the other app; menu items chosen with the keyboard did nothing; Settings buttons acted on a random window; Hide cookie banners hid nothing; Open in Split View on a Favorite; Turn On Max; archiving Easel, History and AI page rows; Share in private and Little windows; Pinyin typed into the command bar being overwritten. All work now. Build 34.
- **About 60 smaller fixes** to hover cards, Escape, Little Arc windows, closing the last window, find keeping its place when a page changes, auto-archive sparing tabs that play sound, Air Traffic Control route order, onboarding Back steps and more. One known issue is still open: closing a tab does not yet ask before throwing away text you typed into the page. Build 34.
- **Scrolling the sidebar up and down, and swiping between Spaces, was still very slow with a large sidebar imported from Arc.** Brk kept a live view for every tab in a Space, including the hundreds out of sight, and macOS worked through all of them on every frame; a swipe also built the full lists of both neighbouring Spaces. The sidebar now keeps views only for the rows near what you see and adds the next ones as you scroll. With 5 Spaces and 560 imported tabs, Brk's main thread went from busy 98% of the time while scrolling and swiping to 40%. Build 33.
- **The sidebar lagged when scrolling, worse with many tabs, folders and Spaces.** Every scroll step, key press and click made Brk recompute the whole window and redraw it, dozens of times a second, and an imported Arc sidebar made each pass slower. Brk now skips that when nothing changed: with 60 tabs, Brk's main thread is busy about half as much while scrolling the sidebar. Build 32.
- **In full screen, the top-left corner was off.** With the menu bar shown, the strip under it started a few points in from the screen's edge, the window buttons were grey circles instead of red, yellow and green, and the sidebar button stayed where it leaves room for those buttons. The strip now starts at the edge, the buttons have their colours, and the sidebar button moves to the left as in Arc. Build 32.
- **Spaces imported from Arc had the wrong colours.** A dark navy Space came out pale grey-lavender: Brk read Arc's colour slider backwards and ignored dark mode. Imported Spaces now keep Arc's colours in light and dark mode, and Spaces imported earlier are corrected the next time Brk opens. Build 32.
- **Hover cards were hard to read in dark mode.** The Gmail "Recent Emails" card and the other Favorite, Pinned and folder cards turned dark in dark mode but kept black text, so they looked dimmed and stuck under the page. Their text and icons now turn light on the dark card. Build 32.
- **The Today line did not move while Tidy worked.** Arc turns the line above Today into a moving wave while Tidy Tabs sorts the tabs; Brk's stayed straight. It now waves the way Arc's does, and the broom swings when you press Tidy. Build 32.
- **Some text in Settings was invisible in dark mode.** The Previews sheet's title and checkbox labels, and the Air Traffic Control sheet's text, were white on a white sheet. They are dark now. Build 32.
- **Dropping a tab group onto a group inside it deleted its tabs.** With a group inside a folder inside another group, dropping the outer group onto the inner one removed every tab in them without archiving them. Brk now refuses that drop. Build 27.
- **A site's permission prompt could stay on screen with buttons that did nothing.** After Escape, a click elsewhere, or the page moving on, the prompt was given up but its card stayed. It now closes. Build 27.
- **Brk kept busy in the background.** With more than eight ad-block lists in use (for example three profiles with three lists each), Brk reloaded them over and over and kept waking hidden tabs, so they never went to sleep. After a failed tab-naming request, it checked again ten times a second for five minutes. Both now wait as they should. Build 27.
- **Importing some Arc sidebars never finished.** A sidebar file that lists an item twice, or inside itself, made the import build it billions of times. Each item is now read once. Build 27.
- **Damaged data could make Brk loop or quit.** A kept AI page whose saved schedule was out of range refreshed nonstop, and a malformed reply from a local model made Brk quit. Both are now treated as invalid. Build 27.
- **Brk quit when the pointer moved onto a row of a folder's hover card.** Hovering a collapsed folder, or a Favorite or Pinned tab that has a preview card, opens a card listing its pages. Putting the pointer on any row of that card closed Brk: highlighting the row redrew it, and the redraw asked for the highlight again, without end. Now the pointer on a row only highlights it, and ↑ and ↓ still move the highlight. Build 25.
- **"Save password?" sat in the top-right corner of the page.** Brk now asks the way Arc does, with a card in the middle of the window: *Save password for (site)?* with Never on this site, No and Save. Saving an address or a card asks the same way (*Save Address?*, *Save this card?*). Build 21.
- **Clicking an autofill suggestion did nothing.** Saved emails, addresses and passwords appeared in the list under a field, but neither a click nor ↓ and Return filled them in. The cause was a bug in the Chromium Embedded Framework 154 that Brk used; Brk now runs CEF 156 (Chromium 156.0.8078.88), where it is fixed. Build 20.
- **Brk quit when a site offered to sign in with a passkey from your phone,** for example Canva's sign-in: Continue another way, then a passkey, then *Use a phone or tablet*. macOS closed Brk because Brk had not said why it might use Bluetooth. Brk now asks for Bluetooth permission instead, and declares every other permission a website can ask for. Build 18.

## Feedback and bug reports

- **From inside Brk:** Help › **Report a Bug…** or **Send Feedback…** opens a GitHub issue with your Brk version, macOS version and Mac type already filled in. Nothing is sent until you submit it. After a crash, Brk offers once to report it on the next launch.
- **On GitHub:** [open an issue](https://github.com/cyang2020/brk/issues/new/choose) and pick **Bug report**, **Feature request or feedback**, or **Arc parity**. The last one is for "Arc does X, Brk does Y", with a screenshot.
- **Questions and ideas:** [Discussions](https://github.com/cyang2020/brk/discussions).
- **What has been fixed:** see [Bug fixes](#bug-fixes) above, or subscribe to the [same list on GitHub](https://github.com/cyang2020/brk/issues/2) to get a notification for each new fix.
- **Security issues:** report them privately through [GitHub's security advisories](https://github.com/cyang2020/brk/security/advisories/new), as described in [`SECURITY.md`](.github/SECURITY.md).
- **Contributing:** see [`CONTRIBUTING.md`](CONTRIBUTING.md). Brk is MIT licensed.

## Not in Brk yet

<details>
<summary><b>The Arc features Brk has not verified yet, and why</b></summary>

These are the 24 Arc features that Brk has not verified, with the reasons recorded in the ledger, followed by two smaller gaps.

**Blocked**

- **Extension buttons and their pop-ups (A097).** BrkCore hosts Chromium's native extension pop-ups, with the owning tab retained for extension APIs.
- **Pixel identity on every screen (A148).** The screens that need a signed-in Arc have no reference pictures yet, so the screen-by-screen comparison is not complete.

**Left out on purpose**

- **Account, sign-in, membership and referrals (A123, A124).** Brk has no account.
- **Send to Dia (A126).** It sends a tab to The Browser Company's other browser.
- **Notes (A100).** Arc 1.170 has no menu or command bar entry for making a note. Arc is retiring them.
- **Menu bar icon (A132).** Arc 1.170 has none either. There is no setting for it and no code that creates one.
- **Ask on Page (A135).** Arc 1.170's desktop app has no entry for it. ⌘F only finds text, and neither the Tabs menu nor the Max settings list it. In Brk, the AI panel can read the page instead.

**Deferred**

- **Software updates and the update banner (A127, A128).** The user deferred these. Brk does not update itself. To get a newer version, download the newest disk image and drag Brk into Applications again; your tabs and settings stay.

**Partly done**

- **Default browser and links from other apps (A112).** Links sent from other apps open and are routed by Air Traffic Control, which was tested with a registered copy of the app. In Settings, though, the default-browser status is read only once, when Settings opens, and a failure to become the default is not reported.
- **Dock tile (A131).** The Dock icon shows download progress, and its menu has New Window and New Incognito Window. The download count badge is set but does not show without notification permission. The Dock plug-in that shows your chosen icon while Brk is closed is built, but its last step, with Brk kept in the Dock, has not been checked.
- **AppleScript (A133).** The scripting dictionary follows Arc's. It covers windows, tabs and Spaces, with the commands make, count, close, select, go back, go forward, reload, stop, execute and focus, and it was tested inside Brk's own process. Running it from `osascript` needs a one-time approval in System Settings, which has not been done.

**Built, not yet verified**

- **Favorite badges (A014).** The GitHub unread dot and the time to the next meeting have no Arc picture to compare against, since that needs GitHub and a calendar signed in to Arc. There is also a known bug. Cancelling Connect GitHub Notifications clears a badge that was working.
- **Tab groups (A035).** There is no Arc picture of a group header to compare against, because Arc's Tidy could not be triggered on the test Mac.
- **Save, print, share and cast (A044).** Casting has not been tried with a real receiver, since there is none near the test Mac. Sending a job to a printer and the Share menu have not been checked with real input.
- **Auto-archive banner (A082).** It is rebuilt from Arc's binary. Arc shows it only on a new account, so there is no Arc picture to compare against.
- **Easels (A101).** Drawing, text, moving, deleting and PNG export work. Resizing with the corner handles, undo and colour choice are missing.
- **Library Media page (A103).** It lists Brk's own captures. There is no Arc picture of the page with content, because Arc lists the screenshot folder only after a permission prompt.
- **Picture in picture (A104).** Picture in picture for Google Meet needs a signed-in Meet call and has not been checked.
- **Site permissions (A108).** Camera, microphone, location and notifications have not been checked through macOS's own permission prompts, since that would change system settings.
- **Per-site rules (A110).** The keep-alive, picture-in-picture and suspension rules work, but the "page is using the camera or microphone" case needs macOS permission and has not been checked.
- **Onboarding (A119).** The full-window setup is driven screen by screen with real clicks and typing in a test. The "make Brk the default browser" step is left off in tests, because it changes the Mac's settings.
- **Import from other browsers (A122).** Importing from a real Arc profile was checked: 2 Spaces with their folders and a split view, 11 pinned and Today tabs, 4 Favorites and 184 history visits, and a second import added nothing. Chrome-family import was checked on a made-up Chrome profile, including a cookie that keeps a site logged in and a password that fills in after a restart. Not yet checked with real data: Arc's own passwords and cookies (they need someone to type the Mac's password at the Keychain prompt), Chrome (not installed on the test Mac), a real Safari export and Firefox. Extensions, open tabs and payment cards are not imported yet.

**Smaller known gaps**

- **Little Arc's download pill.** Being built now.
- **macOS screenshots in the Library list.** Listing them needs permission for the Desktop folder, so the list shows only Brk's own captures.

</details>

<details>
<summary><b>Build from source</b></summary>

Needs macOS 14 or later and Xcode with Swift 6. Download the pinned BrkCore framework for your Mac, or build it using `engine/README.md`.
Ready-built apps for Apple silicon and Intel, from every merge into main, are on the [Releases page](https://github.com/cyang2020/brk/releases); see [docs/release.md](docs/release.md).

```sh
python3 engine/download-artifact.py "$(uname -m)" --out .build/brkcore
export BRK_CORE_DIR="$PWD/.build/brkcore"
scripts/build.sh                 # release build, unit tests, BrkCore bundle and signature: dist/Brk.app
SKIP_TESTS=1 scripts/build.sh    # the same without the unit tests
open dist/Brk.app
```

Tests:

```sh
swift test                                            # unit tests
swift build -c release --product brk-e2e
python3 scripts/run-native.py <name> --set smoke      # native scenarios with real input on a real launch
```

Which tests a change adds, and what runs before a merge, is in `docs/testing-policy.md`.

- `Sources/`: the SwiftPM targets. `Brk` is the app; `BrkDomain` holds the state and its rules; `BrkSidebar`, `BrkContent`, `BrkOverlays`, `BrkLibrary` and `BrkSettings` are the UI; `BrkCoreEngine` connects the app to Chromium.
- `engine/`: BrkCore, Brk's sole browser engine, with its Chromium patch series and pinned release artifacts.
- `docs/`: the design (`docs/design/`), Arc facts (`docs/arc-anatomy/`), the feature ledger and the testing rules.

The first version (October 2026) was an Electron app, kept at the tag `electron-v1`.

</details>

---

<p align="center"><sub>MIT licensed. Brk is an independent project and is not affiliated with The Browser Company. Arc is a trademark of The Browser Company.</sub></p>
