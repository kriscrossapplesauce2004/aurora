"""Pure convergence policy. Map device signals and outputs to a layout for each output."""
import re

TRIGGERS = ('Keyboard', 'Pointer', 'Lid', 'Tablet', 'Rotate', 'Hotplug')
PREF_KEYS = ('convergeAuto', 'convergeMoveApps') + tuple('converge' + name for name in TRIGGERS)
BUILTIN = re.compile(r'^(eDP|LVDS|DSI)')
# A phone-class panel stays touch-first because its short side is small.
PHONE_SHORT_SIDE = 600
# A panel with a long side below this value is too small for a desktop layout.
DESKTOP_LONG_SIDE = 1000


def enabled(prefs, trigger):
    """Return True when the master switch and the trigger switch are both on."""
    return prefs.get('convergeAuto', True) is not False and prefs.get('converge' + trigger, True) is not False


def is_builtin(name, phone_display='', prefs=None):
    """A built-in panel, or the chosen phone display while it is really used as a phone."""
    if BUILTIN.match(name):
        return True
    if not phone_display or name != phone_display:
        return False
    # An external monitor that was once the phone display must not stay a phone after it is set back to desktop.
    prefs = prefs or {}
    chosen = (prefs.get('displayModes') or {}).get(name)
    if chosen:
        return chosen == 'phone'
    return prefs.get('mode') == 'phone'


def effective_signals(state, prefs):
    """Drop the signals of triggers the user turned off."""
    return {
        'keyboard': bool(state.get('keyboard')) and enabled(prefs, 'Keyboard'),
        'pointer': bool(state.get('pointer')) and enabled(prefs, 'Pointer'),
        'lid': state.get('lid') if enabled(prefs, 'Lid') else None,
        'tablet': state.get('tablet') if enabled(prefs, 'Tablet') else None,
    }


def decide(state, prefs):
    """Return {'layouts': {output: mode}, 'off': [outputs], 'external': [outputs]}."""
    signals = effective_signals(state, prefs)
    outputs = [dict(o, builtin=o.get('builtin', is_builtin(o.get('name', ''), prefs.get('phoneDisplay', ''), prefs))) for o in state.get('outputs', [])]
    external = [o['name'] for o in outputs if not o['builtin']]
    layouts, off = {}, []
    for out in outputs:
        name = out['name']
        if not out['builtin']:
            layouts[name] = 'desktop'
            continue
        short, long = sorted((out.get('width', 0), out.get('height', 0)))
        small = short < PHONE_SHORT_SIDE or long < DESKTOP_LONG_SIDE
        if signals['lid'] == 'closed' and external:
            off.append(name)
            layouts[name] = 'desktop'
        elif signals['tablet'] is not None:
            # A convertible follows its tablet-mode switch.
            layouts[name] = 'phone' if signals['tablet'] else 'desktop'
        elif signals['lid'] is not None:
            # A laptop without a tablet switch stays a desktop.
            layouts[name] = 'desktop'
        elif small:
            layouts[name] = 'phone'
        else:
            # A tablet turns into a desktop while a keyboard or mouse is attached.
            layouts[name] = 'desktop' if signals['keyboard'] or signals['pointer'] else 'phone'
    return {'layouts': layouts, 'off': off, 'external': external}


def _names(state):
    return {o['name'] for o in state.get('outputs', [])}


def triggers_between(old, new, prefs):
    """List the enabled triggers whose signal changed. Order is by priority."""
    found = []
    if _names(old) != _names(new) and enabled(prefs, 'Hotplug'):
        found.append('Hotplug')
    for trigger, key in (('Lid', 'lid'), ('Tablet', 'tablet'), ('Keyboard', 'keyboard'), ('Pointer', 'pointer')):
        if old.get(key) != new.get(key) and enabled(prefs, trigger):
            found.append(trigger)
    return found


def describe(trigger, state, added=(), removed=(), layout=''):
    """Return one short sentence for the undo toast."""
    suffix = {'desktop': 'Desktop layout', 'phone': 'Touch layout'}.get(layout, '')
    if trigger == 'Hotplug':
        text = (', '.join(added) + ' connected') if added else (', '.join(removed) + ' disconnected')
    elif trigger == 'Keyboard':
        text = 'Keyboard connected' if state.get('keyboard') else 'Keyboard disconnected'
    elif trigger == 'Pointer':
        text = 'Mouse connected' if state.get('pointer') else 'Mouse disconnected'
    elif trigger == 'Lid':
        text = 'Lid closed' if state.get('lid') == 'closed' else 'Lid opened'
    elif trigger == 'Tablet':
        text = 'Tablet mode on' if state.get('tablet') else 'Tablet mode off'
    else:
        text = 'Display changed'
    return text + (' · ' + suffix if suffix else '')


class Engine:
    """Keep the previous state and report layout changes with their cause."""

    def __init__(self):
        self.state = None
        self.layouts = {}

    def update(self, state, prefs):
        """Return None for no change or a dict with layouts, changes, trigger, text, added, removed and initial."""
        decision = decide(state, prefs)
        old = self.state
        self.state = state
        previous, self.layouts = self.layouts, decision['layouts']
        if old is None:
            return {'initial': True, 'layouts': decision['layouts'], 'off': decision['off'], 'changes': [], 'trigger': '', 'text': '', 'added': [], 'removed': [], 'externalAdded': []}
        added = sorted(_names(state) - _names(old))
        removed = sorted(_names(old) - _names(state))
        changes = [{'output': n, 'from': previous.get(n, ''), 'to': m} for n, m in decision['layouts'].items() if previous.get(n) != m]
        triggers = triggers_between(old, state, prefs)
        # Hotplug of a built-in-only change still reports the dock or undock.
        if not triggers and not changes:
            return None
        trigger = triggers[0] if triggers else ''
        layout = changes[0]['to'] if changes else ''
        text = describe(trigger, state, added if trigger == 'Hotplug' else (), removed if trigger == 'Hotplug' else (), layout) if trigger else ''
        return {'initial': False, 'layouts': decision['layouts'], 'off': decision['off'], 'changes': changes, 'trigger': trigger,
                'text': text, 'added': added, 'removed': removed, 'externalAdded': [n for n in added if n in decision['external']]}
