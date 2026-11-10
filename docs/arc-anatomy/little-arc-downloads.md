# Arc 1.170: Little Arc's download pills, and no card after a download

## Background

Arc has two download surfaces next to the Library flyout and the flight in `library-flyout.md`. A Little Arc window
has no Library button, so it throws no download icon; it shows its own row of download pills at its bottom left. A
standard window shows no card at all after a download; Brk used to show Chromium's own download card there.

The facts below were found on 2026-11-10. Addresses (`bin:0x…`) are in the arm64 slice of
`/Applications/Arc.app/Contents/MacOS/Arc` 1.170 (build 89123), read with llvm-objdump (ObjC selector stubs named from
`__objc_stubs`, field names from `__swift5_fieldmd`, small strings from mov/movk pairs). Colours are from the asset
catalogs `ARC_LittleBrowser.bundle` and `ARCClients_BaseAssets.bundle` (`assetutil --info`). "Probe" means the user's
signed-in Arc driven with real window-server clicks on a local file server (probes p1 to p7); the scripts, pictures
and frame strips are outside the repo, in `~/brk-evidence/downloads-polish/`.

## No card after a download

- p1: a link click in a standard window downloads a 900-byte file. The recording's last screen change is the Library
  badge 1.7 s after the click; a picture 6 s after the click is the same. Arc shows no card, toast or bubble.
- What Brk showed was Chromium's download bubble ("partial view", `DownloadToolbarUIController::ShowDetails`), which
  Chromium opens when a download finishes; the status line is `IDS_DOWNLOAD_BUBBLE_STATUS_DONE` ("Done") after the
  size. Brk's pages are Chrome-style CEF browsers in frameless windows, so the bubble anchored at the window's top
  left. Its name was "payload", the name of Brk's staging file, because Chromium names a download after the path it
  writes to.
- Brk turns off the profile preference `download_bubble.partial_view_enabled` (Chromium's "Show downloads when
  they're done") in the request context of every browser that starts a download, and names the staged file after the
  destination (`.brk-transfer-<UUID>/file/<name>`), so any other Chromium surface reads the real name too.

## The pills

Arc's code is `LittleBrowser.LittleBrowserDownloadsTrayViewController` (an `NSCollectionView` in a clear
`NSScrollView`, made lazily by `Arc.LittleWindowViewController`) and `LittleBrowserDownloadsTrayItemView`; its
actions are `didClick` and `didClickClose`. Brk rebuilds it in `Sources/BrkDomain/Rules/LittleDownloads.swift` and
`Sources/BrkApp/LittleDownloadsTray.swift`; the numbers are `Metrics.littleDownloads`.

Where and how big:
- Each pill is 250 x 56 (bin:0x1022ae95c, `sizeForItemAt`). The section is inset 20 on all sides (bin:0x1022ae998)
  and pills are 10 apart (bin:0x1022ae9ac); the tray is 96 tall (bin:0x1022ad540). p2: the pill sits 20 from the
  window's left and bottom.
- The row scrolls sideways (`setScrollDirection: 1`, bin:0x1022acff0), oldest on the left, the newest appended on the
  right (p3: slow.bin, a (1).txt, b.png, c.pdf, then the rest off to the right). A new pill appears at once, with no
  slide or fade (p3 frame strip). The tray has no background of its own.

A pill:
- A white card (asset `DownloadItemBackground`; dark 0.05 grey) with corner radius 8 (bin:0x1022a96a4) and a black
  shadow at 0.25, radius 3, 1 down (bin:0x1022a9630, `ARCUI.ShadowView`).
- A row inset 10 with 10 between its parts (bin:0x1022a95b0, 0x1022a95bc): the icon, the title over the subtitle (5
  apart, leading, bin:0x1022a9394), a flexible space and the ×.
- Icon: `ARCUI.IconWithProgressIndicatorView`, 32 x 32 (bin:0x1022a8fe8), ring 2 wide (bin:0x1022a9014), track
  `DownloadProgressBarBackground` (#CED7E7; dark #717782), progress `LoadingPageBorder` (#0C50FF; dark #2AB6F6). The
  ring fills clockwise from the top while the download runs and is gone when it is done. The file's icon shows
  through a 28-point circle, drawn larger than the circle and cropped (p2 pictures: a document's page spans 22.5
  points).
- Title: the file's name, 14 pt (bin:0x1022a913c), `ForegroundPrimary` (black 0.9; dark white 0.8), truncated in the
  middle (line break mode 5): "dlpolish-with…runcation.txt" (p4).
- Subtitle: `ForegroundSecondary` (black 0.5), about 12 pt, truncated at the end. It comes from the same DownloadsUI
  builder as the Library flyout's rows and the Downloads page (bin:0x101cdbc14; called from bin:0x1022aa7f8,
  0x10265f958, 0x1027752fc):
  - running: received/total and the time left, "671 KB/8.4 MB · 23s", "2.2/8.4 MB · 11s", "294 KB/1.0 MB · 12s"
    (p2, p5). Both sizes go through one `ByteCountFormatter` (KB to TB, adaptive, zero-padded fractions,
    bin:0x101cdb9c0), and the received size drops its unit when both units match (bin:0x101cdd0e4). A 900-byte
    file reads "1/1 KB" for a frame before it finishes (p3).
  - done: the file's kind, the first type it conforms to among image, disk image, PDF, movie, audio, zip, archive
    ("Image", "Disk Image", "PDF", "Movie", "Audio", "Zip Archive", "Archive", bin:0x100828ad4 to 0x1008295b4,
    "Sidebar download cell file type copy"), else "Download". p3/p4: .bin "Archive", .txt and .csv "Download",
    .png "Image", .pdf "PDF".
  - cancelled "Cancelled", failed "Failed to Download" (bin:0x101cdc0c8, 0x101cdbfe0).
- Hover: the card turns `DownloadItemBackgroundHovered` (0.96 grey; dark 0.12) and the × shows; it is hidden
  otherwise (bin:0x1022aab44 swaps both). The × is Arc's own 14-point icon (bin:0x1022a9404) in `ForegroundPrimary`;
  its glyph spans 8.6 points with 1.4-point strokes, centred 233 points into the pill.

What it does:
- A click on a finished pill opens the file with its default app (p4: the png opened in Preview). A click on a
  running pill changes nothing, and the file does not open when it finishes (p5).
- The × on a finished pill removes the pill and leaves the file and its Library entry (p4: the files stayed in
  ~/Downloads). The × on a running pill cancels the download (p4: its `.crdownload` went) and removes the pill.
- Pills do not go by themselves: the first pill was still there 15 s after it finished (p2) and about 3 minutes later
  (p4). They go with their × or with the window; the page navigating keeps them (p7).
- A click in the pills' band beside a pill reaches the page (p7: a link under the band, clicked 700 points into the
  window, opened its page).

Light and dark: every colour above has a DarkAqua variant in Arc's asset catalogs. The user's Arc has no dark Space and
switching the system appearance would disturb other tasks' captures on the shared screen, so dark was taken from the
catalogs, not probed. Brk picks the dark variants when the Little window's palette is dark.

## Not rebuilt

- The icon's first frame for a quick download: Arc shows a grey disc in a full ring until its icon fetcher returns
  (p3, one frame); Brk has the icon at once.
