"""Read-only Linux joystick mapping; no grabs, injection or permission changes."""
import array
from pathlib import Path


_BUTTON_ACTIONS = {
    304: 'accept', 305: 'back', 307: 'search', 308: 'pin',
    310: 'previousTab', 311: 'nextTab', 312: 'pageUp', 313: 'pageDown',
    314: 'menu', 315: 'home', 316: 'guide', 317: 'search', 318: 'menu',
    544: 'up', 545: 'down', 546: 'left', 547: 'right',
}
_FALLBACK_BUTTON_ACTIONS = {
    0: 'accept', 1: 'back', 2: 'pin', 3: 'search',
    4: 'previousTab', 5: 'nextTab', 6: 'menu', 7: 'home',
    8: 'guide', 9: 'search', 10: 'menu',
}
_NINTENDO_ACTIONS = {
    'accept': 'back', 'back': 'accept', 'pin': 'search', 'search': 'pin',
}
# Guide timing: a tap ends below the tap limit, a hold starts at the hold time.
GUIDE_TAP_MAX, GUIDE_HOLD_MIN = .45, .6
_FALLBACK_AXIS_CODES = {0: 0, 1: 1, 6: 16, 7: 17}
_TRIGGER_CODES = {
    'stadia': (10, 9),
    'xbox': (2, 5),
    'playstation': (2, 5),
}


def device_maps(device):
    import fcntl
    def read_map(request, kind, length):
        values = array.array(kind, [0]) * length
        try:
            fcntl.ioctl(device.fileno(), request, values)
            return values
        except OSError:
            return None
    # Query independently: one unsupported ioctl must not discard the other map.
    return read_map(0x84006a34, 'H', 512), read_map(0x80406a32, 'B', 64)


def device_info(path, root=Path('/sys/class/input')):
    device = Path(root) / Path(path).name / 'device'
    def read(key):
        try:
            return (device / key).read_text().strip()
        except OSError:
            return ''
    name, vendor, product = read('name'), read('id/vendor'), read('id/product')
    return {'name': name, 'vendor': vendor, 'product': product,
            'virtual': vendor == '28de' and product == '11ff' or
                       '/devices/virtual/' in str(device.resolve())}


def ranked_devices(paths):
    # Steam Input may create jsN before the real controller. Never consume both.
    return sorted(paths, key=lambda p: (device_info(p)['virtual'], str(p)))


def family(name='', vendor=''):
    name = name.lower()
    if 'stadia' in name or vendor == '18d1':
        return 'stadia'
    if vendor == '054c' or any(s in name for s in ('dualsense', 'dualshock', 'playstation', 'sony interactive')):
        return 'playstation'
    if vendor == '057e' or any(s in name for s in ('nintendo', 'joy-con', 'switch pro')):
        return 'nintendo'
    if vendor == '045e' or any(s in name for s in ('xbox', 'x-box', 'xinput')):
        return 'xbox'
    return 'generic'


def effective_layout(layout, profile):
    return ('nintendo' if profile == 'nintendo' else 'standard') if layout == 'auto' else layout


def button_action(number, layout='standard', codes=None, profile='generic'):
    if number < 0:
        return None
    code = codes[number] if codes is not None and number < len(codes) else None
    # Unknown kernel codes must not become guessed face buttons.
    action = (_BUTTON_ACTIONS.get(code) if codes is not None else
              _FALLBACK_BUTTON_ACTIONS.get(number))
    if profile == 'stadia' and code is not None and 704 <= code < 708:
        action = 'menu'
    if effective_layout(layout, profile) == 'nintendo':
        swap = number < 4 if codes is None else code in (304, 305, 307, 308)
        if swap:
            action = _NINTENDO_ACTIONS.get(action, action)
    return action


def axis_code(number, codes=None):
    if number < 0:
        return None
    return (codes[number] if number < len(codes) else None) if codes is not None else _FALLBACK_AXIS_CODES.get(number)


def axis_orientation(number, codes=None):
    code = axis_code(number, codes)
    return 'horizontal' if code in (0, 16) else 'vertical' if code in (1, 17) else None


class NavigationState:
    """Hysteresis, repeat and trigger edges, including safe startup snapshots."""
    def __init__(self, buttons=None, axes=None, profile='generic'):
        self.buttons, self.axes, self.profile = buttons, axes, profile
        self.states, self.held, self.blocked = {}, {}, set()
        self.trigger_rest = {}
        # Guide press time, chord flag and hold flag for the current press.
        self.guide_down, self.guide_chord, self.guide_held = None, False, False
        self._button_actions = {}
        self._axis_actions = {}
        self._trigger_codes = _TRIGGER_CODES.get(profile, ())

    def _button_action(self, number, layout):
        key = (layout, number)
        try:
            return self._button_actions[key]
        except KeyError:
            action = button_action(number, layout, self.buttons, self.profile)
            self._button_actions[key] = action
            return action

    def _axis_action(self, number):
        try:
            return self._axis_actions[number]
        except KeyError:
            code = axis_code(number, self.axes)
            if code in (0, 16):
                action = (code, 1)
            elif code in (1, 17):
                action = (code, -1)
            else:
                action = (code, 0)
            self._axis_actions[number] = action
            return action

    def feed(self, kind, number, value, now, layout='auto'):
        initial, kind = bool(kind & 0x80), kind & 0x7f
        token = (kind, number)
        if kind == 1:
            key = self._button_action(number, layout)
            state = bool(value)
            old = self.states.get(token, 0)
        elif kind == 2:
            code, direction = self._axis_action(number)
            if direction:
                old = self.states.get(token, 0)
                threshold = 10000 if old else 18000
                state = 0 if abs(value) < threshold else (1 if value > 0 else -1)
                if direction > 0:
                    key = 'right' if state > 0 else 'left'
                else:
                    key = 'down' if state > 0 else 'up'
            else:
                if code not in self._trigger_codes:
                    return []
                old = self.states.get(token, 0)
                # JS drivers normalize both signed/unsigned hardware to signed
                # values; some virtual drivers instead rest at zero.
                if initial:
                    self.trigger_rest[number] = -32767 if value < -16000 else 0
                rest = self.trigger_rest.get(number, -32767)
                progress = (value - rest) / (32767 - rest)
                state = progress > (.35 if old else .65)
                key = 'pageUp' if code == self._trigger_codes[0] else 'pageDown'
        else:
            return []
        self.states[token] = state
        if kind == 1 and key == 'guide' and not initial:
            return self._guide_edge(token, state, old, now)
        if kind == 1 and key == 'accept' and state and not old and not initial \
                and self.guide_down is not None and token not in self.blocked:
            self.guide_chord = True
            return ['guide+accept']
        if initial:
            if state:
                self.blocked.add(token)
            return []
        if not state:
            self.blocked.discard(token)
            self.held.pop(token, None)
            return []
        if token in self.blocked or state == old or not key:
            return []
        if key in ('up', 'down', 'left', 'right'):
            self.held[token] = (key, now + .38)
        return [key]

    def _guide_edge(self, token, state, old, now):
        if token in self.blocked:
            # A Guide held at startup is ignored until its release.
            if not state:
                self.blocked.discard(token)
            return []
        if state and not old:
            self.guide_down, self.guide_chord, self.guide_held = now, False, False
            return []
        if state or self.guide_down is None:
            return []
        short = now - self.guide_down < GUIDE_TAP_MAX
        quiet = not self.guide_chord and not self.guide_held
        self.guide_down = None
        return ['guide'] if short and quiet else []

    def repeat(self, now):
        result = []
        if (self.guide_down is not None and not self.guide_held and not self.guide_chord
                and now - self.guide_down >= GUIDE_HOLD_MIN):
            self.guide_held = True
            result.append('guideHold')
        for token, (key, due) in self.held.items():
            if now >= due:
                if key not in result:
                    result.append(key)
                self.held[token] = (key, now + .13)
        return result

    def wait(self, now):
        delay = .5
        if self.guide_down is not None and not self.guide_held and not self.guide_chord:
            delay = min(delay, self.guide_down + GUIDE_HOLD_MIN - now)
        if not self.held:
            return max(0, delay)
        for _, due in self.held.values():
            remaining = due - now
            if remaining < delay:
                delay = remaining
        return max(0, delay)
