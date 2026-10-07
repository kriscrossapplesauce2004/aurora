"""Local game details for the library sheet. Read-only: playtime from Steam localconfig.vdf and size from the app manifest."""
import pathlib, re

import game_library


def _ci(mapping, key):
    """Look up a key without caring about letter case. Steam changes the case between versions."""
    if not isinstance(mapping, dict): return {}
    for name, value in mapping.items():
        if name.lower() == key.lower(): return value
    return {}


def steam_playtime(appid, root=None):
    """Return minutes played and the last play time for one Steam app, or None when no config is readable."""
    root = root or game_library.steam_root()
    if not root: return None
    best = None
    for path in sorted(pathlib.Path(root, 'userdata').glob('*/config/localconfig.vdf')):
        try: data = game_library.text_vdf(path.read_text(errors='replace'))
        except (OSError, ValueError): continue
        store = _ci(data, 'UserLocalConfigStore')
        apps = _ci(_ci(_ci(_ci(store, 'Software'), 'Valve'), 'Steam'), 'apps')
        entry = _ci(apps, str(appid))
        if not isinstance(entry, dict) or not entry: continue
        minutes = int(_ci(entry, 'Playtime') or 0) if str(_ci(entry, 'Playtime') or '0').isdigit() else 0
        last = int(_ci(entry, 'LastPlayed') or 0) if str(_ci(entry, 'LastPlayed') or '0').isdigit() else 0
        if best is None or minutes > best['minutes']: best = {'minutes': minutes, 'lastPlayed': last}
    return best


def steam_size(appid, root=None):
    """Return the installed size in bytes from the app manifest, or 0."""
    root = root or game_library.steam_root()
    if not root: return 0
    roots = {pathlib.Path(root)}
    try:
        folders = game_library.text_vdf(pathlib.Path(root, 'steamapps/libraryfolders.vdf').read_text(errors='replace')).get('libraryfolders', {})
        roots.update(pathlib.Path(v['path']) for v in folders.values() if isinstance(v, dict) and v.get('path'))
    except (OSError, ValueError): pass
    for library in roots:
        try: state = game_library.text_vdf((library / ('steamapps/appmanifest_%s.acf' % appid)).read_text(errors='replace')).get('AppState', {})
        except (OSError, ValueError): continue
        size = state.get('SizeOnDisk', '0')
        if size.isdigit(): return int(size)
    return 0


def detail(game_id, root=None):
    """Return the facts for one game. Non-Steam games only report that no local playtime exists."""
    result = {'id': game_id if isinstance(game_id, str) else '', 'playtimeMinutes': None, 'lastPlayed': 0, 'sizeBytes': 0, 'uninstallable': False}
    match = re.fullmatch(r'steam:(\d+)', result['id'])
    if not match: return result
    appid = match.group(1)
    result['uninstallable'] = True
    played = steam_playtime(appid, root)
    if played:
        result['playtimeMinutes'], result['lastPlayed'] = played['minutes'], played['lastPlayed']
    result['sizeBytes'] = steam_size(appid, root)
    return result
