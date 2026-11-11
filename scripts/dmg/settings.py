# dmgbuild settings for the Brk disk image (scripts/make-dmg.sh passes app, background and icon with -D).
# The window shows Brk on the left and a link to /Applications on the right, over the arrow drawn by
# scripts/dmg/background.swift; the icon places below must match the ones that script draws around.
import os.path

app = defines['app']
app_name = os.path.basename(app)

format = 'ULFO'                 # LZFSE: smaller than zlib, opens on macOS 10.11 and later
filesystem = 'APFS'
size = None                     # dmgbuild measures the contents
files = [app]
symlinks = {'Applications': '/Applications'}
icon = defines.get('icon')      # the volume's icon in Finder's sidebar and on the desktop
badge_icon = None

background = defines['background']
window_rect = ((200, 120), (660, 400))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {
    app_name: (170, 190),
    'Applications': (490, 190),
}
hide_extensions = [app_name]
