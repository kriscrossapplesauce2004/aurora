"""Local game library for console mode: Steam, Steam shortcuts, Prism Launcher, Heroic, Lutris and RetroArch.

Read-only. Only local files are read, and art comes from caches that the launchers already keep.
"""
import json, os, pathlib, re, sqlite3, struct

HOME = pathlib.Path.home()
STEAM_ROOTS = [HOME / '.local/share/Steam', HOME / '.steam/steam']
TOOL_NAMES = re.compile(r'^(Proton|Steam Linux Runtime|Steamworks Common|SteamVR|Steam Runtime)', re.I)
ART_SUFFIXES = ('.png', '.jpg', '.jpeg', '.webp')


def uri(path):
    return pathlib.Path(path).resolve().as_uri() if path and pathlib.Path(path).is_file() else ''


def text_vdf(text):
    """Parse Valve's text KeyValues format into nested dicts."""
    tokens = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', text)
    def block(index):
        result = {}
        while index < len(tokens):
            string, brace = tokens[index]
            if brace == '}': return result, index + 1
            key = string; index += 1
            if index >= len(tokens): break
            value, brace = tokens[index]
            if brace == '{':
                result[key], index = block(index + 1)
            else:
                result[key] = value; index += 1
        return result, index
    return block(0)[0]


def binary_vdf(data):
    """Parse Valve's binary KeyValues format (shortcuts.vdf)."""
    def cstring(offset):
        end = data.index(b'\0', offset)
        return data[offset:end].decode('utf-8', 'replace'), end + 1
    def block(offset):
        result = {}
        while offset < len(data):
            kind = data[offset]; offset += 1
            if kind == 0x08: return result, offset
            key, offset = cstring(offset)
            if kind == 0x00: result[key], offset = block(offset)
            elif kind == 0x01: result[key], offset = cstring(offset)
            elif kind == 0x02: result[key] = struct.unpack_from('<i', data, offset)[0]; offset += 4
            else: raise ValueError('Unknown binary VDF type %d' % kind)
        return result, offset
    return block(0)[0]


def steam_root():
    for root in STEAM_ROOTS:
        if (root / 'steamapps').is_dir(): return root.resolve()
    return None


def steam_games(art):
    root = steam_root()
    if not root: return []
    libraries = {root}
    try:
        folders = text_vdf((root / 'steamapps/libraryfolders.vdf').read_text(errors='replace')).get('libraryfolders', {})
        libraries.update(pathlib.Path(v['path']) for v in folders.values() if isinstance(v, dict) and v.get('path'))
    except (OSError, ValueError): pass
    games, seen = [], set()
    for library in libraries:
        for manifest in sorted((library / 'steamapps').glob('appmanifest_*.acf')):
            try: state = text_vdf(manifest.read_text(errors='replace')).get('AppState', {})
            except (OSError, ValueError): continue
            appid, name = state.get('appid', ''), state.get('name', '')
            if not appid.isdigit() or not name or appid in seen or TOOL_NAMES.match(name): continue
            seen.add(appid)
            pictures = art.get(appid, {})
            games.append({'id': 'steam:' + appid, 'title': name, 'source': 'Steam', 'cover': pictures.get('cover', ''), 'hero': pictures.get('hero', ''),
                          'launch': ['steam', 'steam://rungameid/' + appid], 'windowClass': 'steam_app_' + appid,
                          'lastPlayed': int(state.get('LastPlayed', 0) or 0)})
    return games


def steam_shortcuts():
    root = steam_root()
    if not root: return []
    games = []
    for path in (root / 'userdata').glob('*/config/shortcuts.vdf'):
        try: shortcuts = binary_vdf(path.read_bytes()).get('shortcuts', {})
        except (OSError, ValueError, IndexError, struct.error): continue
        grid = path.parent / 'grid'
        for entry in shortcuts.values():
            if not isinstance(entry, dict): continue
            name = entry.get('AppName') or entry.get('appname') or ''
            appid = entry.get('appid')
            if not name or not isinstance(appid, int): continue
            unsigned = appid & 0xffffffff
            def picture(stem):
                return next((uri(grid / (stem + s)) for s in ART_SUFFIXES if (grid / (stem + s)).is_file()), '')
            games.append({'id': 'shortcut:%d' % unsigned, 'title': name, 'source': 'Steam shortcut',
                          'cover': picture('%dp' % unsigned), 'hero': picture('%d_hero' % unsigned),
                          'launch': ['steam', 'steam://rungameid/%d' % ((unsigned << 32) | 0x02000000)], 'windowClass': '',
                          'lastPlayed': int(entry.get('LastPlayTime', 0) or 0)})
    return games


def prism_instances():
    roots = [HOME / '.local/share/PrismLauncher', HOME / '.var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher']
    games = []
    for root in roots:
        for config in sorted((root / 'instances').glob('*/instance.cfg')):
            values = {}
            try:
                for line in config.read_text(errors='replace').splitlines():
                    if '=' in line: key, value = line.split('=', 1); values[key.strip()] = value.strip()
            except OSError: continue
            folder = config.parent.name
            icon = values.get('iconKey', '')
            icon_file = next((root / 'icons' / (icon + s) for s in ART_SUFFIXES if (root / 'icons' / (icon + s)).is_file()), None)
            games.append({'id': 'prism:' + folder, 'title': values.get('name', folder), 'source': 'Minecraft', 'cover': '', 'hero': '',
                          'icon': uri(icon_file) if icon_file else '', 'launch': ['prismlauncher', '--launch', folder], 'windowClass': 'Minecraft',
                          'lastPlayed': int(values.get('lastLaunchTime', 0) or 0) // 1000})
    return games


def heroic_games():
    root = HOME / '.config/heroic'
    games = []
    try:
        installed = json.loads((root / 'legendaryConfig/legendary/installed.json').read_text())
        for name, entry in installed.items():
            games.append({'id': 'heroic:' + name, 'title': entry.get('title', name), 'source': 'Epic', 'cover': '', 'hero': '',
                          'launch': ['xdg-open', 'heroic://launch?appName=%s&runner=legendary' % name], 'windowClass': '', 'lastPlayed': 0})
    except (OSError, ValueError, AttributeError): pass
    try:
        installed = json.loads((root / 'gog_store/installed.json').read_text()).get('installed', [])
        library = {}
        try: library = {g.get('app_name'): g for g in json.loads((root / 'store_cache/gog_library.json').read_text()).get('games', [])}
        except (OSError, ValueError, AttributeError): pass
        for entry in installed:
            name = entry.get('appName')
            if not name: continue
            games.append({'id': 'gog:' + name, 'title': library.get(name, {}).get('title', name), 'source': 'GOG', 'cover': '', 'hero': '',
                          'launch': ['xdg-open', 'heroic://launch?appName=%s&runner=gog' % name], 'windowClass': '', 'lastPlayed': 0})
    except (OSError, ValueError, AttributeError): pass
    return games


def lutris_games():
    database = HOME / '.local/share/lutris/pga.db'
    if not database.is_file(): return []
    games = []
    try:
        connection = sqlite3.connect('file:%s?mode=ro' % database, uri=True)
        try: rows = connection.execute('SELECT slug, name, runner, lastplayed FROM games WHERE installed = 1').fetchall()
        finally: connection.close()
    except sqlite3.Error: return []
    for slug, name, runner, last in rows:
        if not slug: continue
        cover = next((HOME / '.local/share/lutris/coverart' / (slug + s) for s in ('.jpg', '.png') if (HOME / '.local/share/lutris/coverart' / (slug + s)).is_file()), None)
        games.append({'id': 'lutris:' + slug, 'title': name or slug, 'source': 'Lutris', 'cover': uri(cover) if cover else '', 'hero': '',
                      'launch': ['lutris', 'lutris:rungame/' + slug], 'windowClass': '', 'lastPlayed': int(last or 0)})
    return games


def retroarch_games(limit=400):
    root = HOME / '.config/retroarch'
    games = []
    for playlist in sorted((root / 'playlists').glob('*.lpl')):
        try: items = json.loads(playlist.read_text()).get('items', [])
        except (OSError, ValueError, AttributeError): continue
        system = playlist.stem
        for item in items:
            path, label, core = item.get('path', ''), item.get('label', ''), item.get('core_path', '')
            if not path or not label: continue
            boxart = root / 'thumbnails' / system / 'Named_Boxarts' / (re.sub(r'[&*/:`<>?\\|]', '_', label) + '.png')
            launch = ['retroarch', '-L', core, path] if core and core != 'DETECT' else ['retroarch', path]
            games.append({'id': 'retroarch:%s:%s' % (system, label), 'title': label, 'source': system.split(' - ')[-1], 'cover': uri(boxart), 'hero': '',
                          'launch': launch, 'windowClass': 'retroarch', 'lastPlayed': 0})
            if len(games) >= limit: return games
    return games


def library(art=None):
    """Every local game, newest played first, then by title."""
    art = art or {}
    games = []
    for source in (lambda: steam_games(art), steam_shortcuts, prism_instances, heroic_games, lutris_games, retroarch_games):
        try: games.extend(source())
        except Exception:
            continue
    return sorted(games, key=lambda g: (-g.get('lastPlayed', 0), g['title'].lower()))
