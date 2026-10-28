"""Finder layout, written directly without Finder automation or permissions."""
files = [defines['app']]
symlinks = {'Applications': '/Applications'}
background = defines['background']
format = 'UDZO'
filesystem = 'HFS+'
window_rect = ((160, 160), (640, 400))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 96
text_size = 13
label_pos = 'bottom'
icon_locations = {
    'Keep My Speakers Awake.app': (160, 190),
    'Applications': (480, 190),
}
hide_extensions = ['Keep My Speakers Awake.app']
