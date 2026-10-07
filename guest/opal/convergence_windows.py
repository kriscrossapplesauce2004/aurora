"""Move windows between the phone output and a docked monitor, and remember each layout."""
import json
import os
import pathlib

STORE = pathlib.Path.home() / '.local/state/opal/convergence-windows.json'
MAX_REMEMBERED = 16
MAX_WINDOWS = 64


def monitor_key(monitor):
    """Key a monitor by make, model and serial (EDID data) and fall back to its connector name."""
    parts = [str(monitor.get(k) or '').strip() for k in ('make', 'model', 'serial')]
    return '-'.join(p.replace(' ', '_') for p in parts if p) or monitor.get('name', '')


def logical_size(monitor):
    width, height = monitor.get('width', 0), monitor.get('height', 0)
    if monitor.get('transform', 0) % 2:
        width, height = height, width
    scale = monitor.get('scale') or 1
    return max(1, round(width / scale)), max(1, round(height / scale))


def placement(client, monitor):
    """Describe where a window sits, in fractions of its monitor so it survives a size change."""
    width, height = logical_size(monitor)
    at, size = client.get('at', [0, 0]), client.get('size', [width, height])
    return {
        'class': client.get('class', ''), 'title': client.get('title', '')[:120],
        'workspace': client.get('workspace', {}).get('id', 0), 'floating': bool(client.get('floating')),
        'fullscreen': int(client.get('fullscreen') or 0),
        'rel': [round((at[0] - monitor.get('x', 0)) / width, 4), round((at[1] - monitor.get('y', 0)) / height, 4),
                round(size[0] / width, 4), round(size[1] / height, 4)],
    }


def pixels(rel, monitor):
    """Turn a fractional placement into pixels on a monitor, clamped inside it."""
    width, height = logical_size(monitor)
    w = max(100, min(width, round(rel[2] * width)))
    h = max(100, min(height, round(rel[3] * height)))
    x = max(0, min(width - w, round(rel[0] * width))) + monitor.get('x', 0)
    y = max(0, min(height - h, round(rel[1] * height))) + monitor.get('y', 0)
    return int(x), int(y), int(w), int(h)


def windows_on(clients, monitor_id):
    return [c for c in clients if c.get('monitor') == monitor_id and not c.get('hidden') and c.get('workspace', {}).get('id', 0) > 0][:MAX_WINDOWS]


def match(saved, clients):
    """Pair saved placements with live windows by class, then by title. Each window is used once."""
    pairs, used = [], set()
    for entry in saved:
        candidates = [c for c in clients if c['address'] not in used and c.get('class') == entry['class']]
        best = next((c for c in candidates if c.get('title', '')[:120] == entry['title']), candidates[0] if candidates else None)
        if best:
            used.add(best['address'])
            pairs.append((entry, best))
    return pairs


def plan(entries_for, clients, target, active_workspace):
    """Return ops that place windows on a target monitor.

    entries_for maps a window address to a placement dict or None. Windows without a placement go to the
    target's visible workspace. A remembered workspace is used only when it is visible on the target.
    """
    ops = []
    for address, entry in entries_for.items():
        number = active_workspace
        if entry and entry['workspace'] == active_workspace:
            number = entry['workspace']
        ops.append({'op': 'workspace', 'address': address, 'number': number})
        if entry and entry['floating']:
            ops.append({'op': 'floating', 'address': address, 'value': True})
            ops.append({'op': 'geometry', 'address': address, 'rect': pixels(entry['rel'], target)})
        elif entry:
            ops.append({'op': 'floating', 'address': address, 'value': False})
        if entry and entry['fullscreen']:
            ops.append({'op': 'fullscreen', 'address': address, 'mode': entry['fullscreen']})
    return ops


def run_ops(ops, actions, focused=''):
    """Apply ops through HyprActions. Return how many succeeded and the first error text."""
    done, error = 0, ''
    for op in ops:
        try:
            kind = op['op']
            if kind == 'workspace':
                actions.move(op['address'], op['number'])
            elif kind == 'floating':
                actions.set_floating(op['address'], op['value'])
            elif kind == 'geometry':
                actions.geometry(op['address'], *op['rect'])
            elif kind == 'fullscreen':
                actions.fullscreen(op['address'], op['mode'], focused)
            done += 1
        except (ValueError, OSError, KeyError, TypeError) as exc:
            error = error or str(exc)
    return done, error


class Memory:
    """Remembered layouts: phone-side placements while docked and per-monitor placements."""

    def __init__(self, path=STORE):
        self.path = pathlib.Path(path)
        self.data = {'monitors': {}, 'phone': {}}
        try:
            loaded = json.loads(self.path.read_text())
            if isinstance(loaded, dict):
                self.data.update({k: v for k, v in loaded.items() if k in self.data and isinstance(v, dict)})
        except (OSError, ValueError):
            pass

    def save(self):
        self.data['monitors'] = dict(list(self.data['monitors'].items())[-MAX_REMEMBERED:])
        temp = str(self.path) + '.tmp'
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with open(temp, 'w', encoding='utf-8') as handle:
                json.dump(self.data, handle, separators=(',', ':'))
            os.replace(temp, self.path)
        except OSError:
            pass


class Mover:
    """Dock and undock choreography. Every call returns a result dict for the UI."""

    def __init__(self, actions, memory):
        self.actions = actions
        self.memory = memory
        self.docked = {}   # external monitor name -> its key
        self.journal = []  # inverse ops for undo, newest last

    def _state(self):
        monitors = self.actions.monitors()
        clients = self.actions.clients()
        return monitors, clients

    def adopt(self, names):
        """Treat monitors that were present at start as docked, without moving windows."""
        for monitor in self.actions.monitors():
            if monitor['name'] in names:
                self.docked[monitor['name']] = monitor_key(monitor)

    def snapshot(self):
        """Remember the placements on every docked monitor. Call while the monitor is still present."""
        monitors, clients = self._state()
        by_name = {m['name']: m for m in monitors}
        for name, key in self.docked.items():
            monitor = by_name.get(name)
            if monitor:
                self.memory.data['monitors'][key] = [placement(c, monitor) for c in windows_on(clients, monitor['id'])]
        self.memory.save()

    def dock(self, phone, external):
        """Move phone windows to the new monitor and restore that monitor's remembered layout."""
        monitors, clients = self._state()
        by_name = {m['name']: m for m in monitors}
        if phone not in by_name or external not in by_name:
            return {'moved': 0, 'error': 'Output not found'}
        phone_monitor, target = by_name[phone], by_name[external]
        key = monitor_key(target)
        self.docked[external] = key
        moving = windows_on(clients, phone_monitor['id'])
        self.memory.data['phone'][phone] = [placement(c, phone_monitor) | {'address': c['address']} for c in moving]
        saved = self.memory.data['monitors'].get(key, [])
        pairs = {c['address']: e for e, c in match(saved, clients)}
        # Remembered windows may sit on another monitor; only phone windows and matches move.
        entries = {c['address']: pairs.get(c['address']) for c in moving}
        for address, entry in pairs.items():
            entries.setdefault(address, entry)
        active = target.get('activeWorkspace', {}).get('id', 0)
        if active <= 0:
            return {'moved': 0, 'error': 'The new monitor has no workspace yet'}
        ops = plan(entries, clients, target, active)
        self.journal = [{'op': 'workspace', 'address': c['address'], 'number': c['workspace']['id']} for c in clients if c['address'] in entries]
        self.journal += [{'op': 'floating', 'address': c['address'], 'value': bool(c.get('floating'))} for c in clients if c['address'] in entries]
        self.memory.save()
        done, error = run_ops(ops, self.actions, '')
        return {'moved': len(entries), 'applied': done, 'error': error, 'restored': len(pairs)}

    def undock(self, phone, gone_names):
        """Gather every window back on the phone output and restore its earlier placement."""
        for name in gone_names:
            self.docked.pop(name, None)
        monitors, clients = self._state()
        by_name = {m['name']: m for m in monitors}
        if phone not in by_name:
            return {'moved': 0, 'error': 'Phone output not found'}
        target = by_name[phone]
        active = target.get('activeWorkspace', {}).get('id', 0)
        if active <= 0:
            return {'moved': 0, 'error': 'The phone output has no workspace'}
        saved = self.memory.data['phone'].pop(phone, [])
        pairs = {c['address']: e for e, c in match(saved, clients)}
        stray = [c for c in clients if c.get('monitor') != target['id'] and not c.get('hidden') and c['workspace']['id'] > 0]
        entries = {c['address']: pairs.get(c['address']) for c in stray}
        for address, entry in pairs.items():
            entries[address] = entry
        # Floating windows from a large monitor must fit the small panel.
        for c in clients:
            if c['address'] not in entries and c.get('floating') and c.get('monitor') == target['id']:
                entries[c['address']] = placement(c, target) | {'workspace': active}
        ops = plan(entries, clients, target, active)
        self.journal = [{'op': 'workspace', 'address': c['address'], 'number': c['workspace']['id']} for c in clients if c['address'] in entries]
        self.memory.save()
        done, error = run_ops(ops, self.actions, '')
        return {'moved': len(entries), 'applied': done, 'error': error}

    def undo(self):
        """Replay the inverse of the last move."""
        ops, self.journal = self.journal, []
        done, error = run_ops(ops, self.actions, '')
        return {'moved': done, 'error': error}
