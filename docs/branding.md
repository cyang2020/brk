# Icon assets

The app uses the approved uppercase B dog with a large vertical ear, a nose and two bark arcs. The mark has no eye.

`Sources/BrkSettings/Resources/AppIcons/` contains six 1024-pixel PNG masters with transparent outer corners.
The existing icon choices remain Original, Candy, Neon, Graphite, Schoolbook and Colorful.
Settings, the running Dock icon, the About window and the Dock plug-in load these same files.
The packaged app uses Original as its Finder icon.

`assets/branding/` contains the transparent color logo and black and white marks.
The black mark can be used as a template image. The color logo keeps a white keyline for use on dark backgrounds.
`prompts.json` records the built-in imagegen prompts and the approved reference.

## Export

`scripts/export-icons.sh [output-directory]` exports the pack. The default directory is `artifacts/brk-icon-pack`.
The script also updates `assets/icon.png`, validates the files and writes a ZIP beside the output directory.
It requires macOS, the Swift command-line tools and Python 3. Python is used only to create the ZIP.

| Directory | Contents |
| --- | --- |
| `png/<style>/` | PNG sizes 16, 24, 32, 48, 64, 128, 256, 512 and 1024 |
| `icns/` | One macOS ICNS per style |
| `iconsets/` | macOS iconsets with 1x and 2x members |
| `macos/` | macOS AppIcon asset catalogs |
| `web/` | ICO favicon, PNG favicons, 180-pixel touch icon, 192-pixel and 512-pixel icons |
| `logos/` | Transparent color, black and white logos |

`verification.json` records the checks for image dimensions, alpha channels, ICNS representations,
ICO frames and monochrome logo pixels. Re-run `.build/brk-icon-verify <output-directory>` to check an existing pack.

`scripts/build.sh` bundles the same masters, exports the default ICNS and copies all six masters into the Dock plug-in.
