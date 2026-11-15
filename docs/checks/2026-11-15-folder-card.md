# 2026-11-15 folder card (Ardia's group box)

## Background

The user asked to copy Ardia's folder highlight into Brk, Tidy's groups included, with the rows under a folder indented. Ardia (github.com/ardia-browser/ardia, read at commit 2fcef9a, GPL: values and behaviour taken, no code copied) draws folders and tab groups with one component, `GroupBlock`. This replaces Arc's look for folders and groups; the rest of the list stays Arc's.

## Ardia's values

| What | Ardia | File in Ardia | Brk |
| --- | --- | --- | --- |
| Child indent, left | 16 | `apps/browser/src/lib/sidebarMetrics.ts` `SIDEBAR_GROUP.indent` | `Metrics.tablist.folderIndent` |
| Card border | 0.5 | same, `border` | `folderCardBorder` |
| Card corner radius | 12, header fill 11.5 | same, `radius`; `GROUP_INNER_RADIUS` in `components/sidebar/geometry.ts` | `folderCardRadius` |
| Rows' right inset, last row to card bottom | 3 | same, `inset`; `GROUP_MEMBERS_PAD_BOTTOM` = 3 - 0.5 | `folderCardInset` |
| Fill, dark / light | white 0.10 / black 0.05 | `components/sidebar/tokens.ts` `groupFill` | `Draw.folderCardFill*` |
| Border, dark / light | white 0.10 / black 0.10 | same, `groupStroke` | `Draw.folderCardStroke*` |
| Fade | 100 ms, bezier(0.25, 0.46, 0.45, 0.94) | `SIDEBAR_MOTION.hoverCardFade`, `components/ui/motion.ts` `curve.fade` | `Draw.folderCardFade*` |

## Ardia's rules, and what Brk does

- When the card shows (`GroupBlock.tsx`, `useBoxOpacity`): on the innermost group under the pointer, on the group a drag drops into, and always on a group with a colour. Brk folders have no colour, so Brk shows the card on the innermost folder or group under the pointer and on the open folder a drag drops into. The user's screenshot has the pointer on a row inside the folder (its × shows), which is this hover state.
- The header row has no hover fill of its own; the card is its hover. A closed folder's card wraps the header only. Brk does the same.
- The rows inside are always indented (16 left, 3 right per level), card or not. Nested groups sit inside the parent's indent and get their own card.
- Tidy makes ordinary groups (`state/pins/tidy.ts`, `newGroups`), so Tidy's groups get the same card.
- Ardia's rows are 34 tall on a 37 pitch; Brk keeps Arc's 40 on 41 with a 36 selection. The card's top is 0.5 above the header's selection, its bottom 3 below the last selection, and the list leaves 3 pt free after each open folder with rows, so the next row's selection stays 5 below the card, as between rows.

## Screenshot against source

The user's screenshot reads a corner radius of about 10; the source says 12, and Brk uses 12. Fill and border match the source (white 0.10 fill, about 0.20 white at the 0.5 pt edge).

## Checks

- `swift test`: 1213 tests, 2 skipped, 0 failures. New: `FolderCardLayoutTests` (3).
- `run-native.py --set smoke,sidebar`: 17 of 19 passed. R57-FolderMotion now expects two rows plus the 3 pt inset and passes alone. TextLayout finds one title at the 164 pt sidebar width: "Fixture Home" inside a folder has 87 pt for 90.2 (base had 90), the 3 pt right inset. Left as is.
- Station P01, P13, P46 on the branch and on base: the differences are the 3 pt shift below open folders, the indented group tabs and the closed folder's hover.
- Scrolling the 560-tab import for 10 s: CPU mean 45.5% on base, 46.0% on the branch.
- Pictures, recording and numbers: `~/brk-evidence/folder-card/`.
