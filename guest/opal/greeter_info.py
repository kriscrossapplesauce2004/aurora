#!/usr/bin/env python3
"""Greeter adapter: list login users and Wayland sessions, and remember the last choice. Standard library only."""
import json, os, pathlib, pwd, shlex, sys

STATE = pathlib.Path(os.environ.get('OPAL_GREETER_STATE', '/var/lib/opal-greeter/state.json'))
SESSION_DIRS = [pathlib.Path(p) for p in os.environ.get('OPAL_SESSION_DIRS', '/usr/share/wayland-sessions').split(':')]
NO_LOGIN = ('nologin', 'false')

def users():
    found = []
    for entry in pwd.getpwall():
        if 1000 <= entry.pw_uid < 60000 and not entry.pw_shell.endswith(NO_LOGIN):
            name = entry.pw_gecos.split(',')[0].strip() or entry.pw_name
            icon = pathlib.Path('/var/lib/AccountsService/icons') / entry.pw_name
            found.append({'login': entry.pw_name, 'name': name, 'avatar': icon.as_uri() if icon.is_file() else ''})
    return sorted(found, key=lambda u: u['login'])

def desktop_entry(path):
    """Read the command and desktop identity from a session file."""
    values, group = {}, ''
    for line in path.read_text(errors='replace').splitlines():
        line = line.strip()
        if line.startswith('['): group = line
        elif group == '[Desktop Entry]' and '=' in line:
            key, value = line.split('=', 1)
            values.setdefault(key.strip(), value.strip())
    if values.get('Hidden') == 'true' or values.get('NoDisplay') == 'true' or not values.get('Exec'): return None
    try: command = [part for part in shlex.split(values['Exec']) if not part.startswith('%')]
    except ValueError: return None
    desktop = ':'.join(part for part in values.get('DesktopNames', '').split(';') if part) or path.stem
    return {'id': path.stem, 'name': values.get('Name', path.stem), 'desktop': desktop, 'command': command} if command else None

def sessions():
    found = {}
    for folder in SESSION_DIRS:
        if folder.is_dir():
            for path in sorted(folder.glob('*.desktop')):
                entry = desktop_entry(path)
                if entry and entry['id'] not in found: found[entry['id']] = entry
    return sorted(found.values(), key=lambda s: s['name'].lower())

def keyboard_layout():
    for path in ('/etc/X11/xorg.conf.d/00-keyboard.conf',):
        try:
            for line in pathlib.Path(path).read_text().splitlines():
                if 'XkbLayout' in line: return line.split('"')[-2]
        except (OSError, IndexError): pass
    try:
        for line in pathlib.Path('/etc/vconsole.conf').read_text().splitlines():
            if line.startswith('KEYMAP='): return line.split('=', 1)[1].strip('"')
    except OSError: pass
    return ''

def remembered():
    try: data = json.loads(STATE.read_text())
    except (OSError, ValueError): return {}
    return {k: data[k] for k in ('user', 'session') if isinstance(data.get(k), str)}

def remember(user, session):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    temp = STATE.with_suffix('.tmp')
    temp.write_text(json.dumps({'user': user, 'session': session}))
    temp.replace(STATE)

def main(argv):
    if len(argv) == 4 and argv[1] == '--remember':
        try: remember(argv[2], argv[3])
        except OSError as error: print(error, file=sys.stderr)
        return
    print(json.dumps({'users': users(), 'sessions': sessions(), 'layout': keyboard_layout(), 'last': remembered()}))

if __name__ == '__main__':
    main(sys.argv)
