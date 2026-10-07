"""Game performance for the Quick Access overlay: Opal-owned MangoHud config, gamemode, power profiles, optional TDP and controller batteries."""
import os, pathlib, re, shutil, subprocess

FPS_LIMITS = (0, 30, 40, 45, 60, 72, 90, 120, 144)
OVERLAY_LEVELS = ('off', 'fps', 'compact', 'full')
GPU_LEVELS = ('auto', 'low', 'high')
# MangoHud options for each overlay level. Only these options belong to Opal.
LEVEL_OPTIONS = {
    'off': ['no_display'],
    'fps': ['fps', 'fps_only'],
    'compact': ['fps', 'frametime', 'cpu_stats', 'gpu_stats', 'hud_compact'],
    'full': ['fps', 'frametime', 'frame_timing', 'cpu_stats', 'cpu_temp', 'gpu_stats', 'gpu_temp', 'ram', 'vram', 'gamemode'],
}
BEGIN, END = '# opal:begin', '# opal:end'
CAPACITY_LEVELS = {'full': 100, 'high': 75, 'normal': 50, 'low': 25, 'critical': 10}
CONTROLLER_WORDS = ('controller', 'gamepad', 'joy', 'xbox', 'dualsense', 'dualshock', 'ps-', 'nintendo', 'stadia', '8bitdo')


def home():
    """Return the home folder. HOME can redirect it for tests."""
    return pathlib.Path(os.environ.get('HOME') or pathlib.Path.home())


def config_path():
    """Return the MangoHud file that Opal owns. The user's own MangoHud config is never touched."""
    return home() / '.local/state/opal/mangohud/MangoHud.conf'


def launch_option(path=None):
    """Return the Steam launch option that makes MangoHud read the Opal file."""
    return 'MANGOHUD_CONFIGFILE=%s mangohud %%command%%' % (path or config_path())


def launch_env():
    """Return an environment for games that Opal starts, or None when no Opal config exists."""
    if not config_path().is_file():
        return None
    return dict(os.environ, MANGOHUD_CONFIGFILE=str(config_path()))


def split_config(text):
    """Split config text into the lines before, inside and after the Opal block."""
    lines = text.splitlines()
    if BEGIN in lines and END in lines and lines.index(BEGIN) < lines.index(END):
        start, stop = lines.index(BEGIN), lines.index(END)
        return lines[:start], lines[start + 1:stop], lines[stop + 1:]
    return lines, [], []


def parse_managed(inner):
    """Read the FPS limit and overlay level from the Opal block."""
    limit, level = 0, 'compact'
    for line in inner:
        line = line.strip()
        if line.startswith('fps_limit='):
            try: limit = int(line.split('=', 1)[1].split(',')[0])
            except ValueError: pass
        elif line.startswith('# opal:level=') and line.split('=', 1)[1] in OVERLAY_LEVELS:
            level = line.split('=', 1)[1]
    return limit if limit in FPS_LIMITS else 0, level


def read_config(path=None):
    """Return the saved FPS limit, overlay level and whether the file exists."""
    path = pathlib.Path(path or config_path())
    try: text = path.read_text()
    except OSError: return {'fpsLimit': 0, 'overlay': 'compact', 'exists': False}
    limit, level = parse_managed(split_config(text)[1])
    return {'fpsLimit': limit, 'overlay': level, 'exists': True}


def write_config(fps_limit=None, overlay=None, path=None):
    """Write the Opal block atomically and keep every other line of the file."""
    path = pathlib.Path(path or config_path())
    try: text = path.read_text()
    except OSError: text = ''
    before, inner, after = split_config(text)
    limit, level = parse_managed(inner)
    if fps_limit is not None:
        if fps_limit not in FPS_LIMITS: raise ValueError('Unsupported frame limit')
        limit = fps_limit
    if overlay is not None:
        if overlay not in OVERLAY_LEVELS: raise ValueError('Unsupported overlay level')
        level = overlay
    block = [BEGIN, '# opal:level=' + level, 'fps_limit=%d' % limit] + LEVEL_OPTIONS[level] + [END]
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + '.tmp')
    temp.write_text('\n'.join(before + block + after) + '\n')
    temp.replace(path)
    return {'fpsLimit': limit, 'overlay': level, 'exists': True}


def _run(command, runner=subprocess.run, timeout=2):
    """Run a command with a time limit. Return its output or None."""
    try:
        result = runner(command, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout if result.returncode == 0 else None


def gamemode_status(runner=subprocess.run, which=shutil.which):
    """Report whether GameMode is installed and whether a game uses it now."""
    if not which('gamemoded'):
        return {'available': False, 'active': False, 'clients': 0}
    out = _run(['gamemoded', '-s'], runner) or ''
    active = 'active' in out and 'inactive' not in out
    clients = re.search(r'(\d+)\s+client', out)
    return {'available': True, 'active': active, 'clients': int(clients.group(1)) if clients else (1 if active else 0)}


def power_profiles(runner=subprocess.run, which=shutil.which):
    """List the profiles that powerprofilesctl offers and the active one."""
    if not which('powerprofilesctl'):
        return {'available': False, 'profiles': [], 'active': ''}
    out = _run(['powerprofilesctl', 'list'], runner) or ''
    profiles, active = [], ''
    for line in out.splitlines():
        match = re.match(r'^([* ]) {0,2}([a-z][a-z-]*):\s*$', line)
        if match:
            profiles.append(match.group(2))
            if match.group(1) == '*': active = match.group(2)
    return {'available': bool(profiles), 'profiles': profiles, 'active': active}


def _number(path):
    """Read an integer from a sysfs file, or None."""
    try: return int(path.read_text().strip())
    except (OSError, ValueError): return None


def _writable(path):
    """Return true when this user can already write the file. Nothing changes permissions."""
    return path.exists() and os.access(path, os.W_OK)


def gpu_interfaces(sysfs='/sys'):
    """Find AMD GPU power cap and performance level files. Hide controls the user cannot write."""
    result = {'tdp': None, 'gpu': None}
    for card in sorted(pathlib.Path(sysfs, 'class/drm').glob('card[0-9]*')):
        device = card / 'device'
        for hwmon in sorted((device / 'hwmon').glob('hwmon*')):
            cap, low, high = _number(hwmon / 'power1_cap'), _number(hwmon / 'power1_cap_min'), _number(hwmon / 'power1_cap_max')
            if result['tdp'] is None and cap is not None and high and _writable(hwmon / 'power1_cap'):
                result['tdp'] = {'watts': round(cap / 1e6), 'min': round((low or 0) / 1e6), 'max': round(high / 1e6), 'path': str(hwmon / 'power1_cap')}
        level = device / 'power_dpm_force_performance_level'
        if result['gpu'] is None and _writable(level):
            try: value = level.read_text().strip()
            except OSError: continue
            result['gpu'] = {'level': value if value in GPU_LEVELS else 'manual', 'path': str(level)}
    return result


def set_tdp(watts, sysfs='/sys'):
    """Set the power cap in watts inside the limits that the driver reports."""
    found = gpu_interfaces(sysfs)['tdp']
    if not found: raise ValueError('This device has no writable power limit')
    watts = max(found['min'], min(found['max'], int(watts)))
    try: pathlib.Path(found['path']).write_text(str(watts * 1000000))
    except OSError as error: raise ValueError('Power limit was refused: %s' % (error.strerror or error))
    return watts


def set_gpu_level(level, sysfs='/sys'):
    """Set the GPU performance level to auto, low or high."""
    found = gpu_interfaces(sysfs)['gpu']
    if not found or level not in GPU_LEVELS: raise ValueError('This device has no writable GPU level')
    try: pathlib.Path(found['path']).write_text(level)
    except OSError as error: raise ValueError('GPU level was refused: %s' % (error.strerror or error))
    return level


def controller_batteries(root='/sys/class/power_supply'):
    """List game controller batteries from the power-supply class."""
    try: devices = sorted(pathlib.Path(root).iterdir())
    except OSError: return []
    found = []
    for device in devices:
        def read(key):
            try: return (device / key).read_text().strip()
            except OSError: return ''
        if read('type').lower() != 'battery' or device.name.upper().startswith(('BAT', 'AC')): continue
        label = read('model_name') or device.name
        if read('scope').lower() != 'device' and not any(w in device.name.lower() + label.lower() for w in CONTROLLER_WORDS): continue
        capacity = read('capacity')
        percent = int(capacity) if capacity.isdigit() and int(capacity) <= 100 else CAPACITY_LEVELS.get(read('capacity_level').lower())
        if percent is None: continue
        state = read('status').lower()
        found.append({'id': device.name, 'name': label, 'percent': percent, 'charging': state in ('charging', 'pending-charge')})
    return found


def snapshot(sysfs='/sys', runner=subprocess.run, which=shutil.which):
    """Gather everything the Quick Access overlay shows about performance."""
    config = read_config()
    gpu = gpu_interfaces(sysfs)
    return {'event': 'gamePerf', 'fpsLimit': config['fpsLimit'], 'overlay': config['overlay'], 'configExists': config['exists'],
            'configPath': str(config_path()), 'launchOption': launch_option(), 'mangohud': bool(which('mangohud')),
            'gamemode': gamemode_status(runner, which), 'profiles': power_profiles(runner, which),
            'tdp': gpu['tdp'], 'gpu': gpu['gpu'], 'controllers': controller_batteries(str(pathlib.Path(sysfs) / 'class/power_supply'))}


def dispatch(command, emit, spawn=None, sysfs='/sys'):
    """Handle perf-get, perf-set, perf-copy and game detail or uninstall commands from the shell."""
    action = command.get('action')
    try:
        if action == 'perf-set':
            key, value = command.get('key'), command.get('value')
            if key == 'fpsLimit' and type(value) is int: write_config(fps_limit=value)
            elif key == 'overlay' and isinstance(value, str): write_config(overlay=value)
            elif key == 'tdp' and type(value) is int: set_tdp(value, sysfs)
            elif key == 'gpuLevel' and isinstance(value, str): set_gpu_level(value, sysfs)
            else: raise ValueError('Unknown performance setting')
        elif action == 'perf-copy':
            if not shutil.which('wl-copy'): raise ValueError('wl-copy is not installed')
            subprocess.run(['wl-copy'], input=launch_option(), text=True, timeout=3, check=False)
            emit({'event': 'message', 'text': 'Steam launch option copied'})
        elif action == 'game-uninstall':
            game_id = command.get('id')
            match = re.fullmatch(r'steam:(\d+)', game_id) if isinstance(game_id, str) else None
            if not match: raise ValueError('Uninstall this game from its own launcher')
            if not shutil.which('steam'): raise ValueError('steam is not installed')
            if spawn: spawn(['steam', 'steam://uninstall/' + match.group(1)])
        elif action == 'game-detail':
            import game_stats
            emit(dict(game_stats.detail(command.get('id')), event='gameDetail'))
            return
    except ValueError as error:
        emit({'event': 'message', 'text': str(error)})
    if str(action).startswith('perf-'): emit(snapshot(sysfs))
