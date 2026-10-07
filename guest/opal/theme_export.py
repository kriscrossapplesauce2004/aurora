"""Opal theme export for Qt, KDE, GTK, Kitty, Flatpak and the cursor, font and icon settings.

Standard library only. Every external command uses an argument list.
Every change is recorded in a state file, so revert() can restore the prior values.
Portal note: xdg-desktop-portal answers org.freedesktop.appearance from a backend.
On Hyprland that backend is xdg-desktop-portal-gtk, and it reads gsettings.
KDE apps that use xdg-desktop-portal-kde read kdeglobals, and Opal writes both.
"""
import colorsys, json, os, pathlib, re, shutil, threading

import system_tools as base_tools

TARGETS = ('gtk', 'kitty', 'qt', 'hyprland', 'kde', 'sync', 'flatpak')
IFACE = 'org.gnome.desktop.interface'
OPAL_MARK = '/* Opal theme */'
SHAPES = {'xs': 8, 'sm': 12, 'md': 16, 'lg': 24, 'xl': 32}
ACCENTS = {'blue': '#3584e4', 'teal': '#2190a4', 'green': '#3a944a', 'yellow': '#c88800', 'orange': '#ed5b00',
           'red': '#e62d42', 'pink': '#d56199', 'purple': '#9141ac', 'slate': '#6f8396'}
FLATPAK_PATHS = ('xdg-config/kdeglobals:ro', 'xdg-config/gtk-3.0:ro', 'xdg-config/gtk-4.0:ro', 'xdg-config/Kvantum:ro', 'xdg-config/qt6ct:ro',
                 '~/.themes:ro', '~/.icons:ro', 'xdg-data/icons:ro', 'xdg-data/themes:ro')
STATE_REL = '.local/state/opal/theme-export-state.json'

# ---------- Context and state ----------

class Ctx:
    """Holds the home folder, the command runner and the tool lookup."""
    def __init__(self, home=None, runner=None, which=None, kvantum=None):
        self.home = pathlib.Path(home or base_tools.HOME)
        self.run = runner or base_tools.run
        self.which = which or shutil.which
        self.kvantum = kvantum if kvantum is not None else self._kvantum
        self.state_path = self.home / STATE_REL
        try: self.state = json.loads(self.state_path.read_text())
        except (OSError, ValueError): self.state = {}
        if not isinstance(self.state, dict): self.state = {}

    def _kvantum(self):
        return bool(self.which('kvantummanager') or pathlib.Path('/usr/share/Kvantum').is_dir() or list(pathlib.Path('/usr/lib').glob('qt*/plugins/styles/libkvantum.so')) or list(pathlib.Path('/usr/lib64').glob('qt*/plugins/styles/libkvantum.so')))

    def target(self, name):
        return self.state.setdefault(name, {})

    def save(self):
        self.state = {k: v for k, v in self.state.items() if v}
        if self.state: atomic(self.state_path, json.dumps(self.state, indent=1))
        else: self.state_path.unlink(missing_ok=True)

    def out(self, args):
        result = self.run(args)
        if result is None or result.returncode: return None
        return (result.stdout or '').strip()

def atomic(path, text):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + '.opal-tmp')
    temp.write_text(text); temp.replace(path)

def read(path):
    try: return pathlib.Path(path).read_text()
    except OSError: return None

def ensure_line(path, line):
    """Add one include line to a user file, once, with an atomic write."""
    text = read(path) or ''
    if line in text.splitlines(): return False
    atomic(path, text + ('' if text.endswith('\n') or not text else '\n') + line + '\n')
    return True

def remove_line(path, line):
    text = read(path)
    if text is None or line not in text.splitlines(): return
    atomic(path, '\n'.join(l for l in text.splitlines() if l != line) + '\n')

# ---------- Colour helpers ----------

mix = base_tools.mix

def rgb(c): return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))
def rgb_text(c): return '%d,%d,%d' % rgb(c)
def luminance(c): r, g, b = rgb(c); return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255

def is_light(colors, options=None):
    if options and isinstance(options.get('light'), bool): return options['light']
    return luminance(colors['base']) > .5

def hue(c):
    h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in rgb(c)))
    return h * 360, s

def accent_name(primary):
    """Pick the nearest GNOME accent by hue. Grey colours give slate."""
    h, s = hue(primary)
    if s < .12: return 'slate'
    return min((n for n in ACCENTS if n != 'slate'), key=lambda n: min(abs(hue(ACCENTS[n])[0] - h), 360 - abs(hue(ACCENTS[n])[0] - h)))

def palette(c, light):
    """Return the extra roles that the generators share."""
    p = dict(c)
    p['outline'] = mix(c['base'], c['text'], .30)
    p['outlineVariant'] = mix(c['base'], c['text'], .16)
    p['disabled'] = mix(c['base'], c['text'], .42)
    p['lowest'] = mix(c['base'], '#ffffff' if light else '#000000', .55 if light else .35)
    p['positive'] = '#1e8e3e' if light else '#7fd99a'
    p['neutral'] = '#b06a00' if light else '#f5c26b'
    return p

# ---------- Ini editing with recorded prior values ----------

def ini_get(text, section, key):
    current = None
    for line in (text or '').splitlines():
        s = line.strip()
        if s.startswith('[') and s.endswith(']'): current = s[1:-1]; continue
        if current == section and '=' in s and not s.startswith(('#', ';')) and s.split('=', 1)[0].strip() == key:
            return s.split('=', 1)[1].strip()
    return None

def ini_set(text, section, key, value):
    """Set or delete one key. All other lines stay as they are."""
    lines = (text or '').splitlines()
    current, found, last = None, None, None
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith('[') and s.endswith(']'): current = s[1:-1]; continue
        if current == section:
            # New keys go after the last real line, not after trailing blank lines.
            if s: last = i
            if '=' in s and not s.startswith(('#', ';')) and s.split('=', 1)[0].strip() == key: found = i
    if value is None:
        if found is not None: del lines[found]
        out = lines
    elif found is not None:
        lines[found] = '%s=%s' % (key, value); out = lines
    elif last is not None:
        lines.insert(last + 1, '%s=%s' % (key, value)); out = lines
    else:
        if lines and lines[-1].strip(): lines.append('')
        out = lines + ['[%s]' % section, '%s=%s' % (key, value)]
    return '\n'.join(out) + '\n' if out else ''

def mark_created(ctx, rel):
    created = ctx.state.setdefault('_created', [])
    if rel not in created: created.append(rel)

def drop_created(ctx, rel):
    """Delete a file that Opal created when nothing else is left in it."""
    path = ctx.home / rel
    created = ctx.state.get('_created', [])
    if rel in created and not (read(path) or '').strip():
        path.unlink(missing_ok=True); created.remove(rel)

def ini_apply(ctx, target, rel, changes):
    """Write keys into a user ini file. The first prior value of each key goes to the state."""
    path = ctx.home / rel
    text = read(path)
    if text is None: mark_created(ctx, rel)
    entry = ctx.target(target).setdefault('ini', {}).setdefault(rel, {'created': text is None, 'keys': {}})
    new = text or ''
    for section, keys in changes.items():
        for key, value in keys.items():
            current = ini_get(new, section, key)
            record = entry['keys'].get(section + '\t' + key)
            if current == value and not record: continue
            if not record or record['written'] != current:
                entry['keys'][section + '\t' + key] = {'prior': current, 'written': value}
            else: record['written'] = value
            new = ini_set(new, section, key, value)
    if not entry['keys']: ctx.target(target)['ini'].pop(rel)
    if new != (text or ''): atomic(path, new)

def ini_revert(ctx, target):
    for rel, entry in (ctx.state.get(target, {}).get('ini') or {}).items():
        path = ctx.home / rel
        text = read(path)
        if text is None: continue
        for name, record in entry['keys'].items():
            section, key = name.split('\t', 1)
            if ini_get(text, section, key) == record['written']: text = ini_set(text, section, key, record['prior'])
        text = drop_empty_sections(text)
        atomic(path, text); drop_created(ctx, rel)
    ctx.state.get(target, {}).pop('ini', None)

def drop_empty_sections(text):
    lines, out = text.splitlines(), []
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith('[') and s.endswith(']'):
            body = []
            for later in lines[i + 1:]:
                if later.strip().startswith('['): break
                body.append(later)
            if not any(b.strip() for b in body): continue
        out.append(line)
    return '\n'.join(out) + '\n' if out else ''

# ---------- gsettings with recorded prior values ----------

def quote(text): return "'" + str(text).replace('\\', '\\\\').replace("'", "\\'") + "'"

def gs_get(ctx, key, schema=IFACE):
    if not ctx.which('gsettings'): return None
    return ctx.out(['gsettings', 'get', schema, key]) or None

def gs_set(ctx, target, key, value, schema=IFACE):
    current = gs_get(ctx, key, schema)
    if current is None: return False
    name = schema + ' ' + key
    records = ctx.target(target).setdefault('gsettings', {})
    record = records.get(name)
    if current == value and not record: return False
    if not record or record['written'] != current: records[name] = {'prior': current, 'written': value}
    else: record['written'] = value
    if current != value: ctx.run(['gsettings', 'set', schema, key, value])
    return True

def gs_revert(ctx, target):
    for name, record in (ctx.state.get(target, {}).get('gsettings') or {}).items():
        schema, key = name.split(' ', 1)
        if gs_get(ctx, key, schema) == record['written']: ctx.run(['gsettings', 'set', schema, key, record['prior']])
    ctx.state.get(target, {}).pop('gsettings', None)

# ---------- File ownership helpers ----------

def own_file(ctx, target, rel, text):
    """Write a file that Opal owns. Returns true when the content changed."""
    path = ctx.home / rel
    old = read(path)
    files = ctx.target(target).setdefault('files', [])
    if rel not in files: files.append(rel)
    if old == text: return False
    atomic(path, text); return True

def remove_owned(ctx, target):
    for rel in ctx.state.get(target, {}).get('files') or []:
        path = ctx.home / rel
        if path.is_dir(): shutil.rmtree(path, ignore_errors=True)
        else: path.unlink(missing_ok=True)
        parent = path.parent
        while parent != ctx.home and parent.is_dir() and not any(parent.iterdir()) and parent.name not in ('.config', '.local', 'share'):
            parent.rmdir(); parent = parent.parent
    ctx.state.get(target, {}).pop('files', None)

# ---------- GTK ----------

def gtk_names(c, light):
    p = palette(c, light)
    n = {'accent_color': c['primary'], 'accent_bg_color': c['primary'], 'accent_fg_color': c['onPrimary'],
         'window_bg_color': c['base'], 'window_fg_color': c['text'], 'view_bg_color': p['lowest'], 'view_fg_color': c['text'],
         'headerbar_bg_color': c['surface'], 'headerbar_fg_color': c['text'], 'headerbar_border_color': p['outlineVariant'],
         'headerbar_backdrop_color': c['base'], 'headerbar_shade_color': p['outlineVariant'],
         'sidebar_bg_color': c['surface'], 'sidebar_fg_color': c['text'], 'sidebar_backdrop_color': c['base'], 'sidebar_shade_color': p['outlineVariant'],
         'secondary_sidebar_bg_color': c['base'], 'secondary_sidebar_fg_color': c['text'],
         'card_bg_color': c['surface'], 'card_fg_color': c['text'], 'card_shade_color': p['outlineVariant'],
         'popover_bg_color': c['surfaceHigh'], 'popover_fg_color': c['text'],
         'dialog_bg_color': c['surfaceHigh'], 'dialog_fg_color': c['text'],
         'thumbnail_bg_color': c['surface'], 'thumbnail_fg_color': c['text'],
         'shade_color': 'rgba(0,0,0,.%d)' % (7 if light else 36), 'scrollbar_outline_color': p['outlineVariant'],
         'destructive_bg_color': c['error'], 'destructive_fg_color': c['base'], 'destructive_color': c['error'],
         'success_bg_color': p['positive'], 'success_fg_color': c['base'], 'success_color': p['positive'],
         'warning_bg_color': p['neutral'], 'warning_fg_color': c['base'], 'warning_color': p['neutral'],
         'error_bg_color': c['error'], 'error_fg_color': c['base'], 'error_color': c['error'],
         # GTK3 theme names.
         'theme_bg_color': c['base'], 'theme_fg_color': c['text'], 'theme_base_color': p['lowest'], 'theme_text_color': c['text'],
         'theme_selected_bg_color': c['primary'], 'theme_selected_fg_color': c['onPrimary'],
         'theme_unfocused_bg_color': c['base'], 'theme_unfocused_fg_color': c['subtext'],
         'theme_unfocused_base_color': p['lowest'], 'theme_unfocused_text_color': c['subtext'],
         'theme_unfocused_selected_bg_color': c['primaryContainer'], 'theme_unfocused_selected_fg_color': c['onPrimaryContainer'],
         'insensitive_bg_color': c['surface'], 'insensitive_fg_color': p['disabled'],
         'insensitive_base_color': c['surface'], 'insensitive_text_color': p['disabled'],
         'borders': p['outlineVariant'], 'unfocused_borders': p['outlineVariant'], 'content_view_bg': p['lowest'],
         'tooltip_bg_color': c['surfaceHigh'], 'tooltip_fg_color': c['text'], 'link_color': c['primary'], 'visited_link_color': c['tertiary']}
    return n

def gtk_shapes(version):
    s = SHAPES
    common = '''
button, .button {{ border-radius: {pill}px; padding: 6px 18px; min-height: 24px; }}
button.circular, button.image-button.circular {{ border-radius: 9999px; padding: 6px; }}
button.pill {{ border-radius: 9999px; padding: 10px 32px; }}
entry, spinbutton, searchbar > revealer > box {{ border-radius: {sm}px; min-height: 24px; padding: 4px 12px; }}
.card, list.boxed-list, .boxed-list {{ border-radius: {md}px; }}
popover > contents, popover.menu > contents {{ border-radius: {md}px; }}
tooltip, tooltip.background {{ border-radius: {xs}px; }}
scale trough, progressbar trough, progressbar progress, levelbar trough {{ border-radius: 9999px; }}
scale slider {{ border-radius: 9999px; }}
switch {{ border-radius: 9999px; }}
switch slider {{ border-radius: 9999px; }}
check, radio {{ border-radius: 6px; }}
radio {{ border-radius: 9999px; }}
menu, .menu {{ border-radius: {sm}px; padding: 4px; }}
menuitem, .menuitem {{ border-radius: {xs}px; }}
notebook > header > tabs > tab {{ border-radius: {sm}px {sm}px 0 0; }}
'''.format(pill=s['md'] + 4, **s)
    if version == 'gtk-4.0':
        return common + '''
window.csd, window.csd decoration {{ border-radius: {lg}px; }}
dialog.messagedialog, window.dialog {{ border-radius: {lg}px; }}
row.activatable, listview > row, columnview > listview > row {{ border-radius: {xs}px; }}
.navigation-sidebar > row, .navigation-sidebar > list > row {{ border-radius: {sm}px; }}
'''.format(**s)
    return common + '''
window.csd, window.csd decoration, window.csd headerbar, .csd.popup decoration {{ border-radius: {md}px {md}px 0 0; }}
window.csd.solid-csd, window.csd.maximized, window.csd.tiled {{ border-radius: 0; }}
list row {{ border-radius: {xs}px; }}
'''.format(**s)

def gtk_css(c, light, version):
    names = ''.join('@define-color %s %s;\n' % item for item in gtk_names(c, light).items())
    return OPAL_MARK + '\n' + names + gtk_shapes(version)

def export_gtk(ctx, c, light, options):
    changed = False
    for version in ('gtk-3.0', 'gtk-4.0'):
        changed |= own_file(ctx, 'gtk', '.config/%s/opal.css' % version, gtk_css(c, light, version))
        line = '@import "opal.css";'
        if not line in (read(ctx.home / '.config' / version / 'gtk.css') or '').splitlines():
            if read(ctx.home / '.config' / version / 'gtk.css') is None: mark_created(ctx, '.config/%s/gtk.css' % version)
            ctx.target('gtk').setdefault('imports', []).append('.config/%s/gtk.css' % version)
            ensure_line(ctx.home / '.config' / version / 'gtk.css', line); changed = True
    gs_set(ctx, 'gtk', 'color-scheme', quote('default' if light else 'prefer-dark'))
    accent = gs_get(ctx, 'accent-color')
    if accent is not None: gs_set(ctx, 'gtk', 'accent-color', quote(accent_name(c['primary'])))
    if changed: nudge_gtk_theme(ctx)

def nudge_gtk_theme(ctx):
    """Switch the GTK theme name away and back. GTK3 apps then reload their CSS."""
    current = gs_get(ctx, 'gtk-theme')
    if not current: return
    other = quote('Adwaita-dark') if current != "'Adwaita-dark'" else quote('Adwaita')
    ctx.run(['gsettings', 'set', IFACE, 'gtk-theme', other])
    ctx.run(['gsettings', 'set', IFACE, 'gtk-theme', current])

def revert_gtk(ctx):
    for rel in ctx.state.get('gtk', {}).get('imports', []): remove_line(ctx.home / rel, '@import "opal.css";')
    for version in ('gtk-3.0', 'gtk-4.0'): remove_line(ctx.home / '.config' / version / 'gtk.css', '@import "opal.css";')
    for version in ('gtk-3.0', 'gtk-4.0'): drop_created(ctx, '.config/%s/gtk.css' % version)
    ctx.state.get('gtk', {}).pop('imports', None)
    remove_owned(ctx, 'gtk'); gs_revert(ctx, 'gtk')
    nudge_gtk_theme(ctx)

# ---------- Kitty ----------

def export_kitty(ctx, c, light, options):
    own_file(ctx, 'kitty', '.config/kitty/opal-theme.conf', base_tools.kitty_conf(c))
    conf = ctx.home / '.config/kitty/kitty.conf'
    line = 'include opal-theme.conf'
    if line not in (read(conf) or '').splitlines():
        if read(conf) is None: mark_created(ctx, '.config/kitty/kitty.conf')
        ctx.target('kitty')['included'] = True; ensure_line(conf, line)
    reload_kitty(ctx)

def reload_kitty(ctx):
    """Use remote control when it is on. Otherwise send SIGUSR1, which reloads the config."""
    theme = str(ctx.home / '.config/kitty/opal-theme.conf')
    if ctx.which('kitty'):
        result = ctx.run(['kitty', '@', 'set-colors', '--all', '--configured', theme])
        if result is not None and not result.returncode: return
    if ctx.which('pkill'): ctx.run(['pkill', '-USR1', '-x', 'kitty'])

def revert_kitty(ctx):
    remove_line(ctx.home / '.config/kitty/kitty.conf', 'include opal-theme.conf')
    drop_created(ctx, '.config/kitty/kitty.conf'); remove_owned(ctx, 'kitty'); ctx.state.pop('kitty', None)
    if ctx.which('pkill'): ctx.run(['pkill', '-USR1', '-x', 'kitty'])

# ---------- KDE colour scheme ----------

def kde_sections(c, light):
    p = palette(c, light)
    def block(bg, alt, fg=None, deco=None, sel=False):
        fg = fg or c['text']
        return {'BackgroundNormal': rgb_text(bg), 'BackgroundAlternate': rgb_text(alt), 'DecorationFocus': rgb_text(c['primary']),
                'DecorationHover': rgb_text(c['primary']), 'ForegroundActive': rgb_text(c['onPrimary'] if sel else c['primary']),
                'ForegroundInactive': rgb_text(c['onPrimary'] if sel else c['subtext']), 'ForegroundLink': rgb_text(c['onPrimary'] if sel else c['primary']),
                'ForegroundNegative': rgb_text(c['error']), 'ForegroundNeutral': rgb_text(p['neutral']), 'ForegroundNormal': rgb_text(fg),
                'ForegroundPositive': rgb_text(p['positive']), 'ForegroundVisited': rgb_text(c['tertiary'])}
    return {
        'Colors:Window': block(c['base'], c['surface']),
        'Colors:View': block(p['lowest'], c['surface']),
        'Colors:Button': block(c['surfaceHigh'], c['surface']),
        'Colors:Header': block(c['surface'], c['base']),
        'Colors:Tooltip': block(c['surfaceHigh'], c['surface']),
        'Colors:Complementary': block(c['surfaceHigh'], c['surface']),
        'Colors:Selection': block(c['primary'], c['primaryContainer'], fg=c['onPrimary'], sel=True),
    }

def kde_scheme_text(c, light):
    out = ['[ColorEffects:Disabled]', 'Color=%s' % rgb_text(c['base']), 'ColorAmount=0.3', 'ColorEffect=2', 'ContrastAmount=0.1', 'ContrastEffect=1', 'IntensityAmount=0', 'IntensityEffect=0', '',
           '[ColorEffects:Inactive]', 'ChangeSelectionColor=true', 'Color=%s' % rgb_text(c['base']), 'ColorAmount=0.025', 'ColorEffect=2', 'ContrastAmount=0.1', 'ContrastEffect=2', 'Enable=false', 'IntensityAmount=0', 'IntensityEffect=0', '']
    for name, keys in kde_sections(c, light).items():
        out += ['[%s]' % name] + ['%s=%s' % kv for kv in sorted(keys.items())] + ['']
    out += ['[General]', 'ColorScheme=Opal', 'Name=Opal', 'shadeSortColumn=true', '',
            '[KDE]', 'contrast=4', '',
            '[WM]', 'activeBackground=%s' % rgb_text(c['surface']), 'activeBlend=%s' % rgb_text(c['text']), 'activeForeground=%s' % rgb_text(c['text']),
            'inactiveBackground=%s' % rgb_text(c['base']), 'inactiveBlend=%s' % rgb_text(c['subtext']), 'inactiveForeground=%s' % rgb_text(c['subtext']), '']
    return '\n'.join(out)

def kde_notify(ctx, categories):
    """Tell running KDE and Qt apps to reload. Category numbers come from KGlobalSettings."""
    if ctx.which('plasma-apply-colorscheme') and 0 in categories:
        ctx.run(['plasma-apply-colorscheme', 'Opal'])
    if not ctx.which('dbus-send'): return
    for category in categories:
        ctx.run(['dbus-send', '--session', '--type=signal', '/KGlobalSettings', 'org.kde.KGlobalSettings.notifyChange', 'int32:%d' % category, 'int32:0'])

def platform_theme(options):
    """Pick the Qt platform theme every app uses: KDE's plasma-integration, else qt6ct."""
    if options.get('platformTheme') in ('kde', 'qt6ct', ''): return options['platformTheme']
    plugins = [d for root in ('/usr/lib', '/usr/lib64', '/usr/lib/x86_64-linux-gnu', '/usr/lib/aarch64-linux-gnu') for d in pathlib.Path(root).glob('qt6/plugins/platformthemes')]
    if any((d / 'KDEPlasmaPlatformTheme6.so').exists() for d in plugins): return 'kde'
    if any((d / 'libqt6ct.so').exists() for d in plugins): return 'qt6ct'
    return ''

def session_env(ctx, name, value):
    """Give a variable to apps started from now on: systemd and D-Bus activation, Hyprland and, for the real home only, this process."""
    pair = '%s=%s' % (name, value)
    if ctx.which('systemctl'): ctx.run(['systemctl', '--user', 'set-environment' if value else 'unset-environment', pair if value else name])
    if value and ctx.which('dbus-update-activation-environment'): ctx.run(['dbus-update-activation-environment', '--systemd', pair])
    if value and ctx.which('hyprctl'): ctx.run(['hyprctl', 'eval', 'hl.env(%s, %s)' % (json.dumps(name), json.dumps(value))])
    if ctx.home == pathlib.Path(base_tools.HOME):
        if value: os.environ[name] = value
        else: os.environ.pop(name, None)

def export_kde(ctx, c, light, options):
    own_file(ctx, 'kde', '.local/share/color-schemes/Opal.colors', kde_scheme_text(c, light))
    changes = {'General': {'ColorScheme': 'Opal'}}
    for name, keys in kde_sections(c, light).items(): changes[name] = keys
    # Kvantum draws every Qt app when KDE's platform theme reads the widget style from kdeglobals.
    if ctx.kvantum():
        changes.setdefault('KDE', {})['widgetStyle'] = 'kvantum'
        # Older KStyle code reads the legacy General key, so it gets the same value.
        changes['General']['widgetStyle'] = 'kvantum'
    ini_apply(ctx, 'kde', '.config/kdeglobals', changes)
    theme = platform_theme(options)
    if theme:
        # Qt 5 apps have no KDE platform plugin here, so the style is also forced; Qt 6 apps get the same value from kdeglobals.
        style = 'kvantum' if ctx.kvantum() else ''
        own_file(ctx, 'kde', '.config/environment.d/opal-qt.conf', '# Opal: Qt apps use the Opal colours and Kvantum.\nQT_QPA_PLATFORMTHEME=%s\n' % theme + ('QT_STYLE_OVERRIDE=%s\n' % style if style else ''))
        session_env(ctx, 'QT_QPA_PLATFORMTHEME', theme)
        if style: session_env(ctx, 'QT_STYLE_OVERRIDE', style)
        ctx.target('kde')['platformTheme'] = theme
        ctx.target('kde')['styleOverride'] = style
    kde_notify(ctx, (0, 2))

def revert_kde(ctx):
    had_theme = bool(ctx.state.get('kde', {}).get('platformTheme'))
    had_style = bool(ctx.state.get('kde', {}).get('styleOverride'))
    ini_revert(ctx, 'kde'); remove_owned(ctx, 'kde'); ctx.state.pop('kde', None)
    if had_theme: session_env(ctx, 'QT_QPA_PLATFORMTHEME', '')
    if had_style: session_env(ctx, 'QT_STYLE_OVERRIDE', '')
    kde_notify(ctx, (0, 2))

# ---------- Kvantum theme ----------

def kv_frame(name, x, y, r, fill, border):
    """Draw one nine-slice frame. Corners are quarter discs and edges are strips."""
    def at(ox, oy, inner): return '<g id="%s" transform="translate(%d,%d)">%s</g>' % (inner[0], x + ox, y + oy, inner[1])
    def shape(d1, d2): return '<path d="%s" fill="%s"/><path d="%s" fill="%s"/>' % (d1, border, d2, fill)
    q = r - 1
    pieces = {
        'topleft': (0, 0, shape('M0,%d A%d,%d 0 0 1 %d,0 L%d,%d Z' % (r, r, r, r, r, r), 'M1,%d A%d,%d 0 0 1 %d,1 L%d,%d Z' % (r, q, q, r, r, r))),
        'top': (r, 0, '<rect width="%d" height="%d" fill="%s"/><rect y="1" width="%d" height="%d" fill="%s"/>' % (r, r, border, r, r - 1, fill)),
        'topright': (2 * r, 0, shape('M0,0 A%d,%d 0 0 1 %d,%d L0,%d Z' % (r, r, r, r, r), 'M0,1 A%d,%d 0 0 1 %d,%d L0,%d Z' % (q, q, q, r, r))),
        'left': (0, r, '<rect width="%d" height="%d" fill="%s"/><rect x="1" width="%d" height="%d" fill="%s"/>' % (r, r, border, r - 1, r, fill)),
        'right': (2 * r, r, '<rect width="%d" height="%d" fill="%s"/><rect width="%d" height="%d" fill="%s"/>' % (r, r, border, r - 1, r, fill)),
        'bottomleft': (0, 2 * r, shape('M%d,%d A%d,%d 0 0 1 0,0 L%d,0 Z' % (r, r, r, r, r), 'M%d,%d A%d,%d 0 0 1 1,0 L%d,0 Z' % (r, q, q, q, r))),
        'bottom': (r, 2 * r, '<rect width="%d" height="%d" fill="%s"/><rect width="%d" height="%d" fill="%s"/>' % (r, r, border, r, r - 1, fill)),
        'bottomright': (2 * r, 2 * r, shape('M%d,0 A%d,%d 0 0 1 0,%d L0,0 Z' % (r, r, r, r), 'M%d,0 A%d,%d 0 0 1 0,%d L0,0 Z' % (q, q, q, q))),
    }
    out = ''.join(at(ox, oy, ('%s-%s' % (name, key), body)) for key, (ox, oy, body) in pieces.items())
    out += '<rect id="%s" x="%d" y="%d" width="%d" height="%d" fill="%s"/>' % (name, x + r, y + r, r, r, fill)
    return out

def kv_indicator(name, x, y, size, fill, border, mark, round_):
    rr = size / 2 if round_ else 6
    out = '<g id="%s" transform="translate(%d,%d)"><rect width="%d" height="%d" rx="%s" fill="%s"/><rect x="1" y="1" width="%d" height="%d" rx="%s" fill="%s"/>' % (name, x, y, size, size, rr, border, size - 2, size - 2, max(rr - 1, 0), fill)
    if mark == 'check': out += '<path d="M5,10.5 L8.5,14 L15,6.5" fill="none" stroke="%s" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>' % '#MARK#'
    elif mark == 'dot': out += '<circle cx="10" cy="10" r="4" fill="#MARK#"/>'
    elif mark == 'dash': out += '<path d="M5,10 L15,10" stroke="#MARK#" stroke-width="2.2" stroke-linecap="round"/>'
    return out + '</g>'

def kv_elements(c, light):
    """Return the frame table: base name, corner size and the fill of each state.

    Shapes are border-free tonal fills, like Material 3. Round shapes come from frame.expansion in the config, which
    scales the corners; a drawn border would scale with them, so only the text field keeps an outline.
    """
    p = palette(c, light)
    hover = mix(c['surfaceHigh'], c['primary'], .10)
    press = mix(c['surfaceHigh'], c['primary'], .22)
    clear = c['base']
    flat = lambda f: (f, f)
    tonal = {'normal': flat(c['surfaceHigh']), 'focused': flat(hover), 'pressed': flat(press), 'toggled': flat(c['primaryContainer']),
             'disabled': flat(mix(c['base'], c['surfaceHigh'], .5))}
    # Tool buttons rest on a faint tonal pill, so a toolbar reads as a group of controls, not loose icons.
    tool = {'normal': flat(mix(clear, c['text'], .055)), 'focused': flat(mix(clear, c['text'], .11)), 'pressed': flat(mix(clear, c['text'], .17)),
            'toggled': flat(c['primaryContainer']), 'disabled': flat(clear)}
    # A border would scale up with the rounded corners, so focus is a tint, not an outline.
    field = {'normal': flat(mix(p['lowest'], c['surfaceHigh'], .6)), 'focused': flat(mix(mix(p['lowest'], c['surfaceHigh'], .6), c['primary'], .14)),
             'disabled': flat(c['surface'])}
    item = {'normal': flat(p['lowest']), 'focused': flat(mix(p['lowest'], c['text'], .07)), 'pressed': flat(mix(p['lowest'], c['text'], .12)),
            'toggled': flat(c['secondaryContainer'] if 'secondaryContainer' in c else mix(c['base'], c['secondary'], .26)), 'disabled': flat(p['lowest'])}
    return [
        ('button', 4, dict(tonal, default=flat(c['primaryContainer']))), ('tbutton', 4, tool), ('combo', 4, tonal), ('lineedit', 4, field),
        ('tab', 4, {'normal': flat(clear), 'focused': flat(hover), 'pressed': flat(press), 'toggled': flat(c['primaryContainer']), 'disabled': flat(clear)}),
        ('menu', 4, {'normal': flat(c['surfaceHigh'])}),
        ('menuitem', 4, {'normal': flat(c['surfaceHigh']), 'focused': flat(mix(c['surfaceHigh'], c['text'], .08)), 'toggled': flat(c['primaryContainer'])}),
        ('itemview', 4, item),
        ('toolbar', 4, {'normal': flat(c['base'])}), ('dock', 4, {'normal': flat(c['surface'])}),
        ('group', 4, {'normal': flat(c['surface'])}), ('tooltip', 4, {'normal': flat(c['surfaceHigh'])}),
        ('header', 4, {'normal': flat(p['lowest']), 'focused': flat(mix(p['lowest'], c['text'], .06))}),
        ('progress', 4, {'normal': flat(c['surfaceHigh'])}), ('progress-pattern', 4, {'normal': flat(c['primary']), 'disabled': flat(p['disabled'])}),
        ('slider', 3, {'normal': flat(c['surfaceHigh']), 'toggled': flat(c['primary']), 'disabled': flat(c['surface'])}),
        ('scrollbar', 4, {'normal': flat(c['base'])}),
        ('scrollbar-slider', 4, {'normal': flat(mix(c['base'], c['text'], .28)), 'focused': flat(mix(c['base'], c['text'], .42)), 'pressed': flat(c['primary'])}),
    ]

def kv_cursor(name, fill, ring):
    """Slider handle: a short rounded bar, as in Material 3 expressive sliders."""
    return '<g id="%s"><rect width="20" height="20" fill="none"/><rect x="7" y="0" width="6" height="20" rx="3" fill="%s"/><rect x="7.5" y="0.5" width="5" height="19" rx="2.5" fill="none" stroke="%s" stroke-width="1"/></g>' % (name, fill, ring)

def kv_svg(c, light):
    out, y = [], 0
    # View items and attached widgets only round when an "expand-" copy of their frame exists.
    expandable = ('itemview', 'combo', 'lineedit', 'tbutton', 'tab')
    for base, r, states in kv_elements(c, light):
        for state, (fill, border) in states.items():
            out.append(kv_frame('%s-%s' % (base, state), 0, y, r, fill, border)); y += 3 * r + 4
            if base in expandable:
                out.append(kv_frame('expand-%s-%s' % (base, state), 0, y, r, fill, border)); y += 3 * r + 4
    p = palette(c, light)
    # Indicators. Kvantum names checked states as checked-normal, checked-focused and so on.
    on, off_ring = c['primary'], c['subtext']
    states = (('normal', 'none', off_ring, None), ('focused', mix(c['base'], c['text'], .08), c['text'], None), ('pressed', mix(c['base'], c['primary'], .2), c['primary'], None),
              ('disabled', 'none', p['disabled'], None),
              ('checked-normal', on, on, 'mark'), ('checked-focused', mix(on, c['text'], .12), mix(on, c['text'], .12), 'mark'),
              ('checked-pressed', mix(on, c['text'], .24), mix(on, c['text'], .24), 'mark'), ('checked-disabled', p['disabled'], p['disabled'], 'mark'))
    for kind in ('checkbox', 'radio'):
        rows = states + ((('tristate-normal', on, on, 'dash'), ('tristate-focused', mix(on, c['text'], .12), mix(on, c['text'], .12), 'dash')) if kind == 'checkbox' else ())
        for suffix, fill, ring, mark in rows:
            g = '<g id="%s-%s" transform="translate(0,%d)">' % (kind, suffix, y)
            if kind == 'radio':
                g += '<circle cx="10" cy="10" r="8.5" fill="none" stroke="%s" stroke-width="2"/>' % ring
                if mark: g += '<circle cx="10" cy="10" r="4.5" fill="%s"/>' % fill
            else:
                g += '<rect x="2" y="2" width="16" height="16" rx="4" fill="%s" stroke="%s" stroke-width="2"/>' % (fill if mark else 'none', ring)
                if mark == 'mark': g += '<path d="M5.5,10.5 L8.5,13.5 L14.5,7" fill="none" stroke="%s" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>' % c['onPrimary']
                elif mark == 'dash': g += '<path d="M6,10 L14,10" stroke="%s" stroke-width="2.2" stroke-linecap="round"/>' % c['onPrimary']
            out.append(g + '</g>'); y += 24
    # Chevron arrows for combo boxes, spin boxes, menus and scroll areas.
    paths = {'down': 'M4,7 L10,13 L16,7', 'up': 'M4,13 L10,7 L16,13', 'left': 'M13,4 L7,10 L13,16', 'right': 'M7,4 L13,10 L7,16'}
    for direction, d in paths.items():
        for suffix, ink in (('normal', c['subtext']), ('focused', c['text']), ('pressed', c['text']), ('toggled', c['onPrimaryContainer']), ('disabled', p['disabled'])):
            out.append('<g id="arrow-%s-%s" transform="translate(0,%d)"><rect width="20" height="20" fill="none"/><path d="%s" fill="none" stroke="%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></g>' % (direction, suffix, y, d, ink)); y += 24
    for prefix in ('slidercursor', 'slidercursor-tickless'):
        for suffix, fill in (('normal', c['primary']), ('focused', mix(c['primary'], c['text'], .15)), ('pressed', mix(c['primary'], c['text'], .3)), ('disabled', p['disabled'])):
            out.append('<g transform="translate(0,%d)">%s</g>' % (y, kv_cursor('%s-%s' % (prefix, suffix), fill, c['base']))); y += 24
    body = ''.join(out)
    return '<?xml version="1.0" encoding="UTF-8"?>\n<!-- Opal generated Kvantum theme -->\n<svg xmlns="http://www.w3.org/2000/svg" width="64" height="%d" viewBox="0 0 64 %d">%s</svg>\n' % (y, y, body)

def kv_config(c, light):
    p = palette(c, light)
    def section(name, element, frame=3, expansion=0, interior=True, extra=''):
        text = '[%s]\ninherits=PanelButtonCommand\nframe=true\nframe.element=%s\ninterior=%s\ninterior.element=%s\nframe.top=%d\nframe.bottom=%d\nframe.left=%d\nframe.right=%d\n' % (
            name, element, 'true' if interior else 'false', element, frame, frame, frame, frame)
        if expansion: text += 'frame.expansion=%d\n' % expansion
        return text + extra
    general = {'author': 'Opal', 'comment': 'Generated from the Opal palette', 'x11drag': 'menubar_and_primary_toolbar', 'alt_mnemonic': 'true', 'left_tabs': 'false', 'attach_active_tab': 'false',
               'mirror_doc_tabs': 'true', 'group_toolbar_buttons': 'false', 'toolbar_item_spacing': '2', 'toolbar_interior_spacing': '4', 'toolbar_separator_thickness': '0', 'spread_progressbar': 'true',
               'progressbar_thickness': '8', 'composite': 'true', 'menu_shadow_depth': '8', 'tooltip_shadow_depth': '6', 'splitter_width': '4', 'scroll_width': '8', 'scroll_arrows': 'false',
               'scroll_min_extent': '40', 'slider_width': '6', 'slider_handle_width': '20', 'slider_handle_length': '20', 'tickless_slider_handle_size': '20', 'check_size': '20',
               'transient_scrollbar': 'true', 'transient_groove': 'true', 'layout_spacing': '6', 'layout_margin': '9', 'submenu_overlap': '0', 'animate_states': 'true',
               'button_contents_shift': 'false', 'combo_as_lineedit': 'true', 'combo_menu': 'true', 'hide_combo_checkboxes': 'true', 'combo_focus_rect': 'false', 'spin_button_width': '22',
               'opaque': 'kaffeine,kmplayer,subtitlecomposer,kdenlive,vlc,smplayer,smplayer2,avidemux,avidemux2_qt4,avidemux3_qt4,avidemux3_qt5,kamoso,QtCreator,Qt-subapplication,Krita',
               'reduce_window_opacity': '0', 'reduce_menu_opacity': '0', 'translucent_windows': 'false', 'blurring': 'false', 'popup_blurring': 'false', 'vertical_spin_indicators': 'false',
               'inline_spin_indicators': 'true', 'joined_inactive_tabs': 'false', 'center_normal_tabs': 'false', 'small_icon_size': '16', 'large_icon_size': '32', 'button_icon_size': '16',
               'toolbar_icon_size': '22', 'fill_rubberband': 'true', 'dialog_button_layout': '0', 'scrollbar_in_view': 'true', 'respect_DE': 'true', 'no_inactiveness': 'false', 'no_focus_rect': 'true',
               'menu_separator_height': '9', 'tree_branch_line': 'false', 'click_behavior': '0'}
    colors = {'window.color': c['base'], 'inactive.window.color': c['base'], 'base.color': p['lowest'], 'inactive.base.color': p['lowest'], 'alt.base.color': c['surface'], 'inactive.alt.base.color': c['surface'],
              'button.color': c['surfaceHigh'], 'light.color': c['surfaceHigh'], 'mid.light.color': c['surface'], 'dark.color': mix(c['base'], '#000000', .2), 'mid.color': p['outlineVariant'],
              'highlight.color': c['primary'], 'inactive.highlight.color': c['primaryContainer'], 'text.color': c['text'], 'inactive.text.color': c['subtext'], 'window.text.color': c['text'],
              'inactive.window.text.color': c['subtext'], 'button.text.color': c['text'], 'disabled.text.color': p['disabled'], 'tooltip.text.color': c['text'], 'highlight.text.color': c['onPrimary'],
              'link.color': c['primary'], 'link.visited.color': c['tertiary'], 'progress.indicator.text.color': c['text']}
    ink = lambda normal, toggle=None: 'text.normal.color=%s\ntext.focus.color=%s\ntext.press.color=%s\ntext.toggle.color=%s\n' % (normal, normal, normal, toggle or c['onPrimaryContainer'])
    parts = ['[%General]\n' + ''.join('%s=%s\n' % kv for kv in general.items()), '[GeneralColors]\n' + ''.join('%s=%s\n' % kv for kv in colors.items())]
    # Buttons are tonal pills. The default button uses the primary container, so the normal text colour stays readable.
    parts.append('[PanelButtonCommand]\nframe=true\nframe.element=button\ninterior=true\ninterior.element=button\nframe.top=3\nframe.bottom=3\nframe.left=3\nframe.right=3\nframe.expansion=64\n'
                 'text.margin.top=5\ntext.margin.bottom=5\ntext.margin.left=12\ntext.margin.right=12\ntext.shadow=0\ntext.iconspacing=6\nindicator.size=10\nindicator.element=arrow\n'
                 'min_width=+1font\nmin_height=+0.5font\n' + ink(c['text']))
    parts.append(section('PanelButtonTool', 'tbutton', 3, 64, extra='text.margin.left=8\ntext.margin.right=8\ntext.margin.top=4\ntext.margin.bottom=4\n' + ink(c['text'])))
    parts.append(section('ToolbarButton', 'tbutton', 3, 64, extra='text.margin.left=8\ntext.margin.right=8\ntext.margin.top=4\ntext.margin.bottom=4\n' + ink(c['text'])))
    parts.append(section('ComboBox', 'combo', 3, 64, extra='text.margin.left=12\ntext.margin.right=8\ntext.margin.top=4\ntext.margin.bottom=4\n' + ink(c['text'])))
    parts.append('[IndicatorSpinBox]\ninherits=PanelButtonCommand\nframe=false\ninterior=false\nindicator.element=arrow\n' + ink(c['text']))
    parts.append(section('LineEdit', 'lineedit', 3, 64, interior=True, extra='text.margin.left=10\ntext.margin.right=10\ntext.margin.top=4\ntext.margin.bottom=4\n'))
    parts.append('[Toolbar]\ninherits=PanelButtonCommand\nframe=false\ninterior=true\ninterior.element=toolbar\nframe.expansion=0\n')
    parts.append(section('Menu', 'menu', 4, 24, extra='frame.expansion=24\n'))
    parts.append(section('MenuItem', 'menuitem', 3, 64, extra='text.margin.left=10\ntext.margin.right=10\ntext.margin.top=4\ntext.margin.bottom=4\n' + ink(c['text'])))
    parts.append(section('MenuBarItem', 'menuitem', 3, 64, extra=ink(c['text'])))
    parts.append(section('Tab', 'tab', 3, 64, extra='text.margin.left=14\ntext.margin.right=14\ntext.margin.top=5\ntext.margin.bottom=5\n' + ink(c['subtext'])))
    parts.append('[TabFrame]\ninherits=PanelButtonCommand\nframe=false\ninterior=false\n')
    # Selected rows are rounded tonal pills inside the view.
    parts.append(section('ItemView', 'itemview', 3, 64, extra='text.margin.left=6\ntext.margin.right=6\ntext.margin.top=2\ntext.margin.bottom=2\n' + ink(c['text'], c['text'])))
    # Views, docks and frames lose the bevel; separation comes from tone.
    parts.append('[GenericFrame]\ninherits=PanelButtonCommand\nframe=false\ninterior=false\n')
    parts.append(section('Dock', 'dock', 3, 0, extra='frame=false\n'))
    parts.append('[DockTitle]\ninherits=PanelButtonCommand\nframe=false\ninterior=false\ntext.bold=true\n' + ink(c['subtext']))
    parts.append(section('GroupBox', 'group', 4, 24, extra='frame=true\ntext.bold=true\n'))
    parts.append(section('ToolTip', 'tooltip', 4, 32, extra=ink(c['text'])))
    parts.append(section('HeaderSection', 'header', 3, 0, extra=ink(c['subtext']) + 'text.bold=true\n'))
    parts.append(section('Progressbar', 'progress', 3, 64, extra='text.margin=0\ntext.bold=true\n' + ink(c['text'])))
    parts.append(section('ProgressbarContents', 'progress-pattern', 3, 64))
    parts.append(section('Slider', 'slider', 3, 64))
    parts.append('[SliderCursor]\ninherits=PanelButtonCommand\nframe=false\ninterior=true\ninterior.element=slidercursor\n')
    parts.append(section('Scrollbar', 'scrollbar', 3, 0, extra='frame=false\n'))
    parts.append(section('ScrollbarSlider', 'scrollbar-slider', 3, 64))
    parts.append('[ScrollbarGroove]\ninherits=PanelButtonCommand\nframe=false\ninterior=false\n')
    parts.append('[CheckBox]\ninherits=PanelButtonCommand\nframe=false\ninterior=true\ninterior.element=checkbox\nframe.expansion=0\ntext.margin.left=4\n' + ink(c['text'], c['text']))
    parts.append('[RadioButton]\ninherits=PanelButtonCommand\nframe=false\ninterior=true\ninterior.element=radio\nframe.expansion=0\ntext.margin.left=4\n' + ink(c['text'], c['text']))
    parts.append('[Focus]\ninherits=PanelButtonCommand\nframe=false\ninterior=false\n')
    parts.append('[StatusBar]\ninherits=PanelButtonCommand\nframe=false\ninterior=false\n')
    return '\n'.join(parts)

def export_qt(ctx, c, light, options):
    own_file(ctx, 'qt', '.config/qt6ct/colors/Opal.conf', base_tools.qt_colors(c))
    own_file(ctx, 'qt', '.config/qt5ct/colors/Opal.conf', base_tools.qt_colors(c))
    kvantum = ctx.kvantum()
    if kvantum:
        own_file(ctx, 'qt', '.config/Kvantum/Opal/Opal.kvconfig', kv_config(c, light))
        own_file(ctx, 'qt', '.config/Kvantum/Opal/Opal.svg', kv_svg(c, light))
        ini_apply(ctx, 'qt', '.config/Kvantum/kvantum.kvconfig', {'General': {'theme': 'Opal'}})
    for folder in ('qt6ct', 'qt5ct'):
        keys = {'color_scheme_path': str(ctx.home / '.config' / folder / 'colors/Opal.conf'), 'custom_palette': 'true'}
        if kvantum: keys['style'] = 'kvantum'
        ini_apply(ctx, 'qt', '.config/%s/%s.conf' % (folder, folder), {'Appearance': keys})

def revert_qt(ctx):
    ini_revert(ctx, 'qt'); remove_owned(ctx, 'qt'); ctx.state.pop('qt', None)

# ---------- Fonts, icons, cursor and scale ----------

def qt_font(name, size): return '"%s,%d,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"' % (name, size)

def export_sync(ctx, c, light, options):
    font, icons, cursor = options.get('font'), options.get('iconTheme'), options.get('cursorTheme')
    size = options.get('cursorSize') if isinstance(options.get('cursorSize'), int) else None
    pt = options.get('fontSize') if isinstance(options.get('fontSize'), int) else 10
    scale = options.get('scale') if isinstance(options.get('scale'), (int, float)) and .5 <= options.get('scale') <= 3 else None
    safe = lambda v: isinstance(v, str) and 0 < len(v) <= 120 and not any(ch in v for ch in '\n\r\0')
    font, icons, cursor = (v if safe(v) else None for v in (font, icons, cursor))
    if font: gs_set(ctx, 'sync', 'font-name', quote('%s %d' % (font, pt)))
    if icons: gs_set(ctx, 'sync', 'icon-theme', quote(icons))
    if cursor: gs_set(ctx, 'sync', 'cursor-theme', quote(cursor))
    if size: gs_set(ctx, 'sync', 'cursor-size', str(size))
    if scale: gs_set(ctx, 'sync', 'text-scaling-factor', str(float(scale)))
    for version in ('gtk-3.0', 'gtk-4.0'):
        keys = {}
        if font: keys['gtk-font-name'] = '%s %d' % (font, pt)
        if icons: keys['gtk-icon-theme-name'] = icons
        if cursor: keys['gtk-cursor-theme-name'] = cursor
        if size: keys['gtk-cursor-theme-size'] = str(size)
        keys['gtk-application-prefer-dark-theme'] = '0' if light else '1'
        ini_apply(ctx, 'sync', '.config/%s/settings.ini' % version, {'Settings': keys})
    for folder in ('qt6ct', 'qt5ct'):
        changes = {}
        if icons: changes['Appearance'] = {'icon_theme': icons}
        if font: changes['Fonts'] = {'general': qt_font(font, pt)}
        if changes: ini_apply(ctx, 'sync', '.config/%s/%s.conf' % (folder, folder), changes)
    kde = {}
    if font: kde['General'] = {'font': '%s,%d,-1,5,400,0,0,0,0,0' % (font, pt)}
    if icons: kde['Icons'] = {'Theme': icons}
    if kde: ini_apply(ctx, 'sync', '.config/kdeglobals', kde)
    if cursor or size:
        mouse = {}
        if cursor: mouse['cursorTheme'] = cursor
        if size: mouse['cursorSize'] = str(size)
        ini_apply(ctx, 'sync', '.config/kcminputrc', {'Mouse': mouse})
    if cursor:
        default_rel = '.icons/default/index.theme'
        existing = read(ctx.home / default_rel)
        ours = existing is not None and existing.startswith('# Opal')
        if existing is None or ours:
            own_file(ctx, 'sync', default_rel, '# Opal cursor theme\n[Icon Theme]\nName=Default\nComment=Default cursor theme\nInherits=%s\n' % cursor)
        else:
            ini_apply(ctx, 'sync', default_rel, {'Icon Theme': {'Inherits': cursor}})
        env = 'XCURSOR_THEME=%s\n' % cursor + ('XCURSOR_SIZE=%d\n' % size if size else '')
        own_file(ctx, 'sync', '.config/environment.d/opal-cursor.conf', env)
        if ctx.which('hyprctl'):
            ctx.run(['hyprctl', 'setcursor', cursor, str(size or 24)])
    kde_notify(ctx, (1, 4, 5))

def revert_sync(ctx):
    ini_revert(ctx, 'sync'); gs_revert(ctx, 'sync'); remove_owned(ctx, 'sync'); ctx.state.pop('sync', None)
    kde_notify(ctx, (1, 4, 5))

# ---------- Hyprland borders ----------

def export_hyprland(ctx, c, light, options):
    if not ctx.which('hyprctl'): return False
    active, inactive = 'rgba(%sff)' % c['primary'][1:], 'rgba(%sff)' % c['surfaceHigh'][1:]
    result = ctx.run(['hyprctl', 'eval', 'hl.config({general={["col.active_border"]="%s",["col.inactive_border"]="%s"}})' % (active, inactive)])
    if result is None or result.returncode or 'error' in (result.stdout or '').lower():
        ctx.run(['hyprctl', 'keyword', 'general:col.active_border', active])
        ctx.run(['hyprctl', 'keyword', 'general:col.inactive_border', inactive])
    ctx.target('hyprland')['applied'] = True
    return True

def revert_hyprland(ctx):
    if ctx.state.get('hyprland', {}).get('applied') and ctx.which('hyprctl'): ctx.run(['hyprctl', 'reload'])
    ctx.state.pop('hyprland', None)

# ---------- Flatpak ----------

def flatpak_global(ctx):
    return read(ctx.home / '.local/share/flatpak/overrides/global') or ''

def export_flatpak(ctx, c, light, options):
    if not ctx.which('flatpak'): return False
    text = flatpak_global(ctx)
    have = ini_get(text, 'Context', 'filesystems') or ''
    existing = {p.strip() for p in have.split(';') if p.strip()}
    state = ctx.target('flatpak')
    added = state.setdefault('filesystems', [])
    for path in FLATPAK_PATHS:
        if path in existing or path in added or path.split(':')[0] in existing: continue
        ctx.run(['flatpak', 'override', '--user', '--filesystem=' + path]); added.append(path)
    env = state.setdefault('env', [])
    wanted = {}
    gtk_theme = options.get('gtkTheme')
    if isinstance(gtk_theme, str) and re.fullmatch(r'[A-Za-z0-9._ -]{1,80}', gtk_theme) and ((ctx.home / '.themes' / gtk_theme).is_dir() or (ctx.home / '.local/share/themes' / gtk_theme).is_dir()):
        wanted['GTK_THEME'] = gtk_theme
    if ctx.kvantum() and 'KStyle.Kvantum' in (ctx.out(['flatpak', 'list', '--runtime', '--columns=application']) or ''): wanted['QT_STYLE_OVERRIDE'] = 'kvantum'
    for key, value in wanted.items():
        if ini_get(text, 'Environment', key) is None and key not in env:
            ctx.run(['flatpak', 'override', '--user', '--env=%s=%s' % (key, value)]); env.append(key)
    return True

def revert_flatpak(ctx):
    state = ctx.state.get('flatpak', {})
    if ctx.which('flatpak'):
        for path in state.get('filesystems', []): ctx.run(['flatpak', 'override', '--user', '--nofilesystem=' + path.split(':')[0]])
        for key in state.get('env', []): ctx.run(['flatpak', 'override', '--user', '--unset-env=' + key])
    ctx.state.pop('flatpak', None)

# ---------- Entry points ----------

EXPORTERS = {'gtk': export_gtk, 'kitty': export_kitty, 'qt': export_qt, 'hyprland': export_hyprland, 'kde': export_kde, 'sync': export_sync, 'flatpak': export_flatpak}
REVERTERS = {'gtk': revert_gtk, 'kitty': revert_kitty, 'qt': revert_qt, 'hyprland': revert_hyprland, 'kde': revert_kde, 'sync': revert_sync, 'flatpak': revert_flatpak}
ORDER = ('sync', 'qt', 'kde', 'gtk', 'kitty', 'hyprland', 'flatpak')

def export(colors, targets, home=None, runner=None, which=None, kvantum=None, options=None):
    """Write the chosen targets. Returns the targets that were written."""
    if not base_tools.valid_colors(colors): raise ValueError('Invalid colours')
    options = options if isinstance(options, dict) else {}
    ctx = Ctx(home, runner, which, kvantum)
    light = is_light(colors, options)
    done = []
    for name in ORDER:
        if name not in targets: continue
        result = EXPORTERS[name](ctx, colors, light, options)
        if result is not False: done.append(name)
    ctx.save()
    return done

def revert(targets, home=None, runner=None, which=None, kvantum=None):
    ctx = Ctx(home, runner, which, kvantum)
    for name in ORDER:
        if name in targets: REVERTERS[name](ctx)
    ctx.save()

# ---------- Installed theme discovery ----------

def discover(home=None, runner=None, which=None, roots=None):
    """List installed icon themes, cursor themes and font families."""
    home = pathlib.Path(home or base_tools.HOME)
    roots = roots or [home / '.icons', home / '.local/share/icons', pathlib.Path('/usr/share/icons'), pathlib.Path('/usr/local/share/icons')]
    icons, cursors = set(), set()
    for root in roots:
        try: entries = sorted(root.iterdir())
        except OSError: continue
        for folder in entries:
            if not folder.is_dir(): continue
            index = read(folder / 'index.theme') or ''
            if (folder / 'cursors').is_dir(): cursors.add(folder.name)
            if re.search(r'^Directories\s*=', index, re.M) and not re.search(r'^Hidden\s*=\s*true', index, re.M | re.I): icons.add(folder.name)
    fonts = set()
    run, which = runner or base_tools.run, which or shutil.which
    if which('fc-list'):
        result = run(['fc-list', ':', 'family'])
        if result is not None and not result.returncode:
            for line in (result.stdout or '').splitlines():
                name = line.split(',')[0].strip()
                if name and len(name) <= 80: fonts.add(name)
    return {'icons': sorted(icons, key=str.lower), 'cursors': sorted(cursors, key=str.lower), 'fonts': sorted(fonts, key=str.lower)[:400]}

# ---------- Debounce ----------

class Debounce:
    """Run only the last submitted job after a quiet delay."""
    def __init__(self, delay=.6): self.delay, self.timer, self.lock = delay, None, threading.Lock()
    def submit(self, job):
        with self.lock:
            if self.timer: self.timer.cancel()
            self.timer = threading.Timer(self.delay, job); self.timer.daemon = True; self.timer.start()
    def flush(self):
        with self.lock:
            if self.timer: self.timer.cancel(); self.timer = None

DEBOUNCE = Debounce()
