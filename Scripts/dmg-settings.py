# dmgbuild settings for the ScreenMint installer window.
# Used by Scripts/package-release.sh: dmgbuild -s dmg-settings.py -D app=... -D background=... -D icon=... ScreenMint out.dmg
# Icon positions must match the arrow in Scripts/make-dmg-background.swift.
import os.path

application = defines["app"]
app_name = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]

background = defines["background"]
window_rect = ((200, 120), (660, 420))
default_view = "icon-view"
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
    app_name: (180, 205),
    "Applications": (480, 205),
}
hide_extensions = [app_name]
