"""Check the actual Finder layout stored in the mounted release image."""
import sys
from pathlib import Path
from ds_store import DSStore

volume = Path(sys.argv[1])
assert (volume / 'Applications').is_symlink()
assert (volume / 'Applications').readlink() == Path('/Applications')
assert (volume / '.background.tiff').stat().st_size > 0
with DSStore.open(str(volume / '.DS_Store'), 'r') as store:
    assert store['Keep My Speakers Awake.app']['Iloc'] == (160, 190)
    assert store['Applications']['Iloc'] == (480, 190)
    view = store['.']['icvp']
    assert view['iconSize'] == 96
    assert view['backgroundType'] == 2
print('Verified Finder layout: app → Applications, background and fixed icon positions.')
