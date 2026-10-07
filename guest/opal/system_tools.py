"""System adapters for Opal settings: app theme export, sun times, updates, health, monitors and night light.

Standard library only. Every external command uses an argument list.
"""
import datetime, json, math, os, pathlib, re, shutil, signal, subprocess

HOME = pathlib.Path.home()
HEX = re.compile(r'#[0-9a-fA-F]{6}')
OPAL_MARK = '/* Opal theme */'

def run(args, timeout=20):
    try: return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError): return None

# ---------- App theme export ----------

ROLES = ('primary', 'onPrimary', 'primaryContainer', 'onPrimaryContainer', 'secondary', 'tertiary', 'base', 'surface', 'surfaceHigh', 'text', 'subtext', 'error')

def valid_colors(colors):
    return isinstance(colors, dict) and all(isinstance(colors.get(r), str) and HEX.fullmatch(colors[r]) for r in ROLES)

def mix(a, b, amount):
    x, y = int(a[1:], 16), int(b[1:], 16)
    channels = [round(((x >> s) & 255) + (((y >> s) & 255) - ((x >> s) & 255)) * amount) for s in (16, 8, 0)]
    return '#%02x%02x%02x' % tuple(channels)

def gtk_css(c):
    names = {'accent_color': c['primary'], 'accent_bg_color': c['primary'], 'accent_fg_color': c['onPrimary'],
             'window_bg_color': c['base'], 'window_fg_color': c['text'], 'view_bg_color': c['base'], 'view_fg_color': c['text'],
             'headerbar_bg_color': c['surface'], 'headerbar_fg_color': c['text'], 'sidebar_bg_color': c['surface'], 'sidebar_fg_color': c['text'],
             'card_bg_color': c['surface'], 'card_fg_color': c['text'], 'popover_bg_color': c['surfaceHigh'], 'popover_fg_color': c['text'],
             'dialog_bg_color': c['surfaceHigh'], 'dialog_fg_color': c['text'], 'theme_selected_bg_color': c['primary'], 'theme_selected_fg_color': c['onPrimary'],
             'destructive_bg_color': c['error'], 'destructive_color': c['error']}
    return OPAL_MARK + '\n' + ''.join('@define-color %s %s;\n' % item for item in names.items())

def kitty_conf(c):
    dark = int(c['base'][1:3], 16) < 128
    ansi = [c['base'], c['error'], c['primary'], mix(c['tertiary'], '#ffcc00', .35), c['secondary'], c['tertiary'], mix(c['primary'], '#00ffff', .3), c['subtext']]
    bright = [mix(x, '#ffffff' if dark else '#000000', .25) for x in ansi[:7]] + [c['text']]
    lines = ['# Opal theme', 'foreground ' + c['text'], 'background ' + c['base'], 'selection_foreground ' + c['onPrimary'], 'selection_background ' + c['primary'],
             'cursor ' + c['primary'], 'cursor_text_color ' + c['onPrimary'], 'url_color ' + c['tertiary'], 'active_border_color ' + c['primary'],
             'inactive_border_color ' + c['surfaceHigh'], 'active_tab_background ' + c['primaryContainer'], 'active_tab_foreground ' + c['onPrimaryContainer'],
             'inactive_tab_background ' + c['surface'], 'inactive_tab_foreground ' + c['subtext']]
    lines += ['color%d %s' % (i, v) for i, v in enumerate(ansi + bright)]
    return '\n'.join(lines) + '\n'

def qt_colors(c):
    # qt6ct palette order: window text, button, light, midlight, dark, mid, text, bright text, button text, base, window, shadow, highlight, highlighted text, link, visited link, alternate base, default, tooltip base, tooltip text, placeholder text
    row = [c['text'], c['surface'], c['surfaceHigh'], c['surfaceHigh'], c['base'], c['surface'], c['text'], '#ffffff', c['text'], c['base'], c['base'],
           '#000000', c['primary'], c['onPrimary'], c['primary'], c['tertiary'], c['surface'], c['base'], c['surfaceHigh'], c['text'], c['subtext']]
    joined = ', '.join(('#ff' + v[1:]) for v in row)
    return '[ColorScheme]\nactive_colors=%s\ndisabled_colors=%s\ninactive_colors=%s\n' % (joined, joined, joined)

def ensure_line(path, line):
    """Add one include line to a user config file, once. The file is created when missing."""
    path.parent.mkdir(parents=True, exist_ok=True)
    text = path.read_text() if path.exists() else ''
    if line not in text.splitlines():
        path.write_text(text + ('' if text.endswith('\n') or not text else '\n') + line + '\n')

def remove_line(path, line):
    try: lines = path.read_text().splitlines()
    except OSError: return
    if line in lines: path.write_text('\n'.join(l for l in lines if l != line) + '\n')

def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.tmp'); temp.write_text(text); temp.replace(path)

TARGETS = ('gtk', 'kitty', 'qt', 'hyprland', 'kde', 'sync', 'flatpak')

def export_theme(colors, targets, home=None, runner=run, options=None):
    """Write Opal colours for the chosen apps. The work is in theme_export. Returns the targets that were written."""
    import theme_export
    return theme_export.export(colors, targets, home=home or HOME, runner=runner, options=options)

def remove_export(targets, home=None, runner=run):
    """Undo the export for the chosen apps."""
    import theme_export
    theme_export.revert(targets, home=home or HOME, runner=runner)

# ---------- Sun times from the time zone ----------

def zone_coordinates(zone=None, table=pathlib.Path('/usr/share/zoneinfo/zone1970.tab')):
    """Approximate latitude and longitude from the system time zone's reference city."""
    if zone is None:
        try: zone = os.path.realpath('/etc/localtime').split('zoneinfo/', 1)[1]
        except IndexError: return None
    try: rows = table.read_text().splitlines()
    except OSError: return None
    for row in rows:
        fields = row.split('\t')
        if len(fields) >= 3 and fields[2] == zone:
            match = re.fullmatch(r'([+-]\d{4,6})([+-]\d{5,7})', fields[1])
            if not match: return None
            def degrees(text, width):
                sign = -1 if text[0] == '-' else 1
                digits = text[1:]
                d, rest = int(digits[:width]), digits[width:]
                m = int(rest[:2]) if rest else 0; s = int(rest[2:4]) if len(rest) > 2 else 0
                return sign * (d + m / 60 + s / 3600)
            return degrees(match.group(1), 2), degrees(match.group(2), 3)
    return None

def sun_times(latitude, longitude, day=None):
    """Sunrise and sunset in local time (NOAA approximation). None during polar day or night."""
    day = day or datetime.date.today()
    n = day.timetuple().tm_yday
    gamma = 2 * math.pi / 365 * (n - 1)
    equation = 229.18 * (0.000075 + 0.001868 * math.cos(gamma) - 0.032077 * math.sin(gamma) - 0.014615 * math.cos(2 * gamma) - 0.040849 * math.sin(2 * gamma))
    declination = 0.006918 - 0.399912 * math.cos(gamma) + 0.070257 * math.sin(gamma) - 0.006758 * math.cos(2 * gamma) + 0.000907 * math.sin(2 * gamma) - 0.002697 * math.cos(3 * gamma) + 0.00148 * math.sin(3 * gamma)
    lat = math.radians(latitude)
    cos_hour = math.cos(math.radians(90.833)) / (math.cos(lat) * math.cos(declination)) - math.tan(lat) * math.tan(declination)
    if not -1 <= cos_hour <= 1: return None
    hour = math.degrees(math.acos(cos_hour))
    offset = datetime.datetime.now().astimezone().utcoffset().total_seconds() / 60
    def local(minutes_utc):
        minutes = (minutes_utc + offset) % 1440
        return '%02d:%02d' % (int(minutes // 60), int(minutes % 60))
    return local(720 - 4 * (longitude + hour) - equation), local(720 - 4 * (longitude - hour) - equation)

# ---------- Updates and health ----------

def updates():
    result = {'pacman': None, 'flatpak': None}
    if shutil.which('checkupdates'):
        out = run(['checkupdates'], timeout=120)
        if out is not None and out.returncode in (0, 2): result['pacman'] = len([l for l in out.stdout.splitlines() if l.strip()])
    if shutil.which('flatpak'):
        out = run(['flatpak', 'remote-ls', '--updates', '--columns=application'], timeout=120)
        if out is not None and out.returncode == 0: result['flatpak'] = len([l for l in out.stdout.splitlines() if l.strip()])
    return result

def temperatures(root=pathlib.Path('/sys/class/hwmon')):
    """Highest reading per sensor chip, in degrees Celsius."""
    found = {}
    for chip in sorted(root.glob('hwmon*')):
        try: name = (chip / 'name').read_text().strip()
        except OSError: continue
        for sensor in chip.glob('temp*_input'):
            try: value = int(sensor.read_text().strip()) / 1000
            except (OSError, ValueError): continue
            if 0 < value < 150: found[name] = max(found.get(name, 0), round(value))
    return found

def health():
    disks = []
    for label, path in (('System', '/'), ('Home', str(HOME))):
        try: usage = shutil.disk_usage(path)
        except OSError: continue
        if disks and usage.total == disks[0]['total'] and usage.used == disks[0]['used']: continue
        disks.append({'label': label, 'total': usage.total, 'used': usage.used, 'percent': round(usage.used * 100 / usage.total) if usage.total else 0})
    temps = temperatures()
    return {'disks': disks, 'temperatures': temps, 'hottest': max(temps.values(), default=0)}

UPDATE_SCRIPT = 'sudo pacman -Syu; command -v flatpak >/dev/null && flatpak update; printf "\\nDone. Press Enter to close."; read _'
def update_command():
    for terminal, flag in (('kitty', '-e'), ('foot', ''), ('alacritty', '-e'), ('wezterm', 'start')):
        if shutil.which(terminal): return [terminal] + ([flag] if flag else []) + ['sh', '-c', UPDATE_SCRIPT]
    return None

# ---------- Monitors ----------

OUTPUT = re.compile(r'[A-Za-z0-9._-]{1,64}')
MODE = re.compile(r'\d{3,5}x\d{3,5}@\d{2,3}(\.\d{1,3})?(Hz)?')

def monitors(runner=run):
    out = runner(['hyprctl', '-j', 'monitors', 'all'])
    if out is None or out.returncode: return []
    try: data = json.loads(out.stdout)
    except ValueError: return []
    return [{'name': m.get('name', ''), 'description': m.get('description', ''), 'width': m.get('width', 0), 'height': m.get('height', 0),
             'refresh': round(m.get('refreshRate', 0), 2), 'x': m.get('x', 0), 'y': m.get('y', 0), 'scale': m.get('scale', 1), 'transform': m.get('transform', 0),
             'disabled': bool(m.get('disabled')), 'mirror': m.get('mirrorOf', 'none'), 'modes': [x for x in m.get('availableModes', []) if MODE.fullmatch(x)][:40]}
            for m in data if OUTPUT.fullmatch(m.get('name', ''))]

def monitor_lua(spec):
    """One hl.monitor call from a validated spec."""
    name = spec.get('name')
    if not isinstance(name, str) or not OUTPUT.fullmatch(name): raise ValueError('Invalid output')
    if spec.get('disabled') is True: return 'hl.monitor({output="%s",disabled=true})' % name
    mode = spec.get('mode', 'preferred')
    if mode != 'preferred' and (not isinstance(mode, str) or not MODE.fullmatch(mode)): raise ValueError('Invalid mode')
    x, y = spec.get('x', 0), spec.get('y', 0)
    if type(x) is not int or type(y) is not int or not -32768 <= x <= 32768 or not -32768 <= y <= 32768: raise ValueError('Invalid position')
    scale = spec.get('scale', 1)
    if type(scale) not in (int, float) or not .5 <= scale <= 4: raise ValueError('Invalid scale')
    transform = spec.get('transform', 0)
    if type(transform) is not int or not 0 <= transform <= 7: raise ValueError('Invalid rotation')
    parts = ['output="%s"' % name, 'mode="%s"' % mode.replace('Hz', ''), 'position="%dx%d"' % (x, y), 'scale=%s' % round(scale, 3), 'transform=%d' % transform]
    mirror = spec.get('mirror')
    if mirror and mirror != 'none':
        if not isinstance(mirror, str) or not OUTPUT.fullmatch(mirror): raise ValueError('Invalid mirror')
        parts.append('mirror="%s"' % mirror)
    return 'hl.monitor({%s})' % ','.join(parts)

MONITOR_FILE = HOME / '.config/hypr/opal-monitors.lua'
def apply_monitors(specs, keep=False, runner=run, path=None):
    if not isinstance(specs, list) or not 0 < len(specs) <= 8: raise ValueError('Invalid displays')
    code = '; '.join(monitor_lua(s) for s in specs)
    if not any(s.get('disabled') is not True for s in specs): raise ValueError('At least one display must stay on')
    out = runner(['hyprctl', 'eval', code])
    if out is None or out.returncode: raise ValueError('Hyprland rejected the display settings')
    if keep: atomic(path or MONITOR_FILE, '-- Written by Opal display settings.\n' + code.replace('; ', '\n') + '\n')
    return code

# ---------- Night light ----------

class NightLight:
    def __init__(self):
        self.process, self.temperature = None, 0
    def set(self, enabled, temperature=4000):
        temperature = max(2500, min(6500, int(temperature)))
        if enabled and self.process and self.process.poll() is None and temperature == self.temperature: return True
        self.stop()
        if not enabled: return True
        if not shutil.which('hyprsunset'): return False
        try: self.process = subprocess.Popen(['hyprsunset', '-t', str(temperature)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError: return False
        self.temperature = temperature
        return True
    def stop(self):
        if self.process and self.process.poll() is None:
            try: os.killpg(self.process.pid, signal.SIGTERM)
            except OSError: pass
        self.process = None
