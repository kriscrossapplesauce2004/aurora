"""Optional Hyprland adapter for phone and tablet window fit, split view and slide-over. Without Hyprland every call does nothing."""
import json
import re
import subprocess

from hypr_actions import HyprActions

_OUTPUT = re.compile(r'[A-Za-z0-9._-]{1,64}')
_ADDRESS = re.compile(r'0x[0-9a-fA-F]+')
# Dialogs and tool windows keep their own size and are only kept inside the screen.
SMALL_DIALOG = 0.8
MODES = ('maximize', 'fullscreen', 'float', 'none')


def is_tablet(width, height):
    """A wide output is a tablet when its shorter side is at least 600 logical pixels."""
    return min(width, height) >= 600


def usable_rect(monitor, top=48, bottom=0, keyboard=0):
    """Return x, y, w, h of the area below the status bar and above navigation and keyboard, in global pixels."""
    scale = monitor.get('scale') or 1
    width, height = int(monitor['width'] / scale), int(monitor['height'] / scale)
    if monitor.get('transform', 0) % 2:
        width, height = height, width
    return (monitor['x'] + 0, monitor['y'] + top, width, max(1, height - top - bottom - keyboard))


def split_rects(rect, ratio=0.5, gap=8, minimum=0.25):
    """Return left and right rectangles for a split view. The divider ratio stays within bounds."""
    x, y, width, height = rect
    ratio = max(minimum, min(1 - minimum, float(ratio)))
    left = int((width - gap) * ratio)
    return (x, y, left, height), (x + left + gap, y, width - gap - left, height)


def slide_over_rect(rect, fraction=0.38, margin=12, side='right'):
    """Return the floating slide-over rectangle at one edge of the usable area."""
    x, y, width, height = rect
    w = int(width * fraction)
    h = height - margin * 2
    return ((x + width - w - margin) if side == 'right' else (x + margin), y + margin, w, h)


def plan_fit(clients, monitors, phone_outputs, modes=None):
    """Return window actions for clients on phone outputs. Desktop outputs are never touched."""
    modes = modes or {}
    by_id = {m['id']: m for m in monitors if m.get('name') in phone_outputs}
    # Hyprland keeps one maximized window per workspace. Fitting every window makes them take the place in turn
    # and never stop, so only the front window (the latest in focus history) of each visible phone workspace is fitted.
    front = {}
    for client in clients:
        monitor = by_id.get(client.get('monitor'))
        if not monitor or not client.get('mapped') or client.get('hidden') or client.get('floating'):
            continue
        workspace = (client.get('workspace') or {}).get('id')
        if workspace != (monitor.get('activeWorkspace') or {}).get('id', workspace):
            continue
        rank = client.get('focusHistoryID', 1 << 30)
        if workspace not in front or rank < front[workspace].get('focusHistoryID', 1 << 30):
            front[workspace] = client
    chosen = {c.get('address') for c in front.values()}
    plan = []
    for client in clients:
        monitor = by_id.get(client.get('monitor'))
        if not monitor or not client.get('mapped') or client.get('hidden') or not _ADDRESS.fullmatch(client.get('address', '')):
            continue
        if not client.get('floating') and client.get('address') not in chosen:
            continue
        cls = (client.get('class') or client.get('initialClass') or '').lower()
        mode = modes.get(cls, 'maximize')
        if mode not in MODES or mode == 'none':
            continue
        width, height = client.get('size', [0, 0])
        small = client.get('floating') and width < monitor['width'] * SMALL_DIALOG and height < monitor['height'] * SMALL_DIALOG
        state = client.get('fullscreen', 0)
        if mode == 'float':
            continue
        if small:
            plan.append({'address': client['address'], 'do': 'clamp'})
        elif state != (2 if mode == 'fullscreen' else 1) and not client.get('floating'):
            plan.append({'address': client['address'], 'do': mode})
    return plan


def plan_lift(clients, monitor, keyboard, top=48):
    """Return moves that lift focused floating windows above the keyboard. Tiled and maximized windows are resized by the compositor."""
    if keyboard <= 0:
        return []
    scale = monitor.get('scale') or 1
    height = int(monitor['height'] / scale)
    if monitor.get('transform', 0) % 2:
        height = int(monitor['width'] / scale)
    limit = monitor['y'] + height - keyboard
    moves = []
    for client in clients:
        if client.get('monitor') != monitor.get('id') or not client.get('floating') or not client.get('mapped') or client.get('focusHistoryID', 1) != 0:
            continue
        x, y = client['at']
        bottom = y + client['size'][1]
        if bottom > limit and _ADDRESS.fullmatch(client.get('address', '')):
            moves.append({'address': client['address'], 'x': x, 'y': max(monitor['y'] + top, y - (bottom - limit))})
    return moves


class PhoneWindows:
    """Applies plans with hyprctl. The runner is replaceable for tests."""

    def __init__(self, runner=None):
        self.runner = runner or HyprActions._run
        self.available = None
        # Lua-config Hyprland refuses legacy dispatch and keyword commands, so every action goes through HyprActions.
        self.hypr = HyprActions(self.runner)
        # The first state of every window that phone mode changed, so leaving phone mode can give it back.
        self.originals = {}

    @staticmethod
    def _run(args):
        result = subprocess.run(args, capture_output=True, text=True, timeout=3)
        if result.returncode:
            raise ValueError(result.stderr.strip()[:200] or 'hyprctl failed')
        return result.stdout

    def _json(self, what):
        return json.loads(self.runner(['hyprctl', '-j', what]))

    def _act(self, action, *args):
        try:
            action(*args)
            return True
        except (ValueError, OSError, subprocess.SubprocessError):
            return False

    def _try(self, args):
        try:
            self.runner(args)
            return True
        except (ValueError, OSError, subprocess.SubprocessError):
            return False

    def probe(self):
        if self.available is None:
            self.available = self._try(['hyprctl', 'version'])
        return self.available

    def fit(self, phone_outputs, modes=None):
        """Maximize or fullscreen windows on phone outputs. Returns how many windows changed."""
        names = [n for n in phone_outputs if isinstance(n, str) and _OUTPUT.fullmatch(n)]
        if not names or not self.probe():
            return 0
        clients = self._json('clients')
        plan = plan_fit(clients, self._json('monitors'), set(names), modes)
        self._remember(clients, [step['address'] for step in plan])
        changed = 0
        for step in plan:
            if step['do'] == 'clamp':
                ok = self._act(self.hypr.center, step['address'])
            else:
                ok = self._act(self.hypr.fullscreen, step['address'], 2 if step['do'] == 'fullscreen' else 1)
            changed += bool(ok)
        return changed

    def place(self, address, rect, floating=True):
        """Float a window and set its exact rectangle. Used by split view and slide-over."""
        if not self.probe() or not _ADDRESS.fullmatch(address or ''):
            return False
        x, y, w, h = (int(v) for v in rect)
        self._remember(self._json('clients'), [address])
        if floating:
            self._act(self.hypr.set_floating, address, True)
        return self._act(self.hypr.geometry, address, x, y, w, h)

    def _remember(self, clients, addresses):
        by_address = {c.get('address'): c for c in clients}
        for address in addresses:
            client = by_address.get(address)
            if client and address not in self.originals:
                self.originals[address] = {'floating': bool(client.get('floating')), 'fullscreen': int(client.get('fullscreen') or 0)}

    def release(self, outputs=None):
        """Give windows back the floating and fullscreen state they had before phone mode changed them.

        With outputs, only windows now on those outputs are released. Returns how many windows were restored.
        """
        if not self.originals or not self.probe():
            return 0
        names = {n for n in (outputs or []) if isinstance(n, str) and _OUTPUT.fullmatch(n)}
        try:
            clients = self._json('clients')
            monitors = {m.get('id'): m.get('name') for m in self._json('monitors')}
        except (ValueError, OSError, subprocess.SubprocessError):
            return 0
        restored = 0
        for client in clients:
            address = client.get('address')
            first = self.originals.get(address)
            if first is None or (names and monitors.get(client.get('monitor')) not in names):
                continue
            if int(client.get('fullscreen') or 0) != first['fullscreen']:
                self._act(self.hypr.fullscreen, address, first['fullscreen'])
            if bool(client.get('floating')) != first['floating']:
                self._act(self.hypr.set_floating, address, first['floating'])
            del self.originals[address]
            restored += 1
        # Windows that closed are forgotten.
        live = {c.get('address') for c in clients}
        self.originals = {a: v for a, v in self.originals.items() if a in live}
        return restored

    def split(self, output, left, right, ratio=0.5, top=48, bottom=0, keyboard=0, workspace=0):
        """Put two windows side by side on one output. Both first move to the shown workspace, so a split never spans two."""
        if workspace and type(workspace) is int and workspace > 0:
            for address in (left, right):
                if _ADDRESS.fullmatch(address or ''): self._act(self.hypr.move, address, workspace, False)
        if not isinstance(output, str) or not _OUTPUT.fullmatch(output) or not self.probe():
            return False
        monitor = next((m for m in self._json('monitors') if m.get('name') == output), None)
        if not monitor:
            return False
        a, b = split_rects(usable_rect(monitor, top, bottom, keyboard), ratio)
        return self.place(left, a) and self.place(right, b)

    def slide_over(self, output, address, fraction=0.38, top=48, bottom=0, side='right'):
        """Float one window over the others at an edge."""
        monitor = next((m for m in self._json('monitors') if m.get('name') == output), None) if self.probe() and _OUTPUT.fullmatch(output or '') else None
        if not monitor:
            return False
        ok = self.place(address, slide_over_rect(usable_rect(monitor, top, bottom), fraction, side=side))
        return ok and self._act(self.hypr.raise_window, address)

    def lift(self, output, keyboard):
        """Move the focused floating window above the on-screen keyboard."""
        if not self.probe() or not _OUTPUT.fullmatch(output or ''):
            return 0
        monitor = next((m for m in self._json('monitors') if m.get('name') == output), None)
        if not monitor:
            return 0
        done = 0
        for move in plan_lift(self._json('clients'), monitor, keyboard):
            window = next((c for c in self._json('clients') if c.get('address') == move['address']), None)
            if window:
                done += self._act(self.hypr.geometry, move['address'], int(move['x']), int(move['y']), *(int(v) for v in window.get('size', [1, 1])))
        return done

    def unsplit(self, addresses, phone_outputs):
        """Return split windows to the tiled layout and fit them again."""
        if not self.probe():
            return 0
        for address in addresses:
            if _ADDRESS.fullmatch(address or ''):
                self._act(self.hypr.set_floating, address, False)
        return self.fit(phone_outputs)

    def go_home(self):
        """Show the home screen by switching to an empty workspace. Returns false without Hyprland."""
        if not self.probe():
            return False
        return self._act(self.hypr.workspace_empty)
