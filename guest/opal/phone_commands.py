"""Backend commands for phone and tablet mode. One entry point keeps backend.py changes small."""
import threading

import battery_stats
import recent_activity
import torch
from phone_windows import PhoneWindows, MODES

ACTIONS = ('torch', 'torch-status', 'battery-stats', 'recent-activity', 'phone-fit', 'phone-split', 'phone-slideover', 'phone-home', 'phone-unsplit', 'phone-lift', 'phone-release')
_windows = PhoneWindows()


def _ratio(value, default):
    return float(value) if type(value) in (int, float) and 0 <= value <= 1 else default


def _inset(value):
    return int(value) if type(value) is int and 0 <= value <= 2000 else 0


def handle(c, emit, games=None):
    """Run one phone command. Returns True when the action belongs to this module."""
    action = c.get('action')
    if action not in ACTIONS:
        return False
    if action in ('torch', 'torch-status'):
        state = torch.set_state(c['on']) if action == 'torch' and type(c.get('on')) is bool else torch.status()
        emit(dict(state, event='torch'))
    elif action == 'battery-stats':
        emit(dict(battery_stats.read(), event='batteryStats'))
    elif action == 'recent-activity':
        threading.Thread(target=lambda: emit(dict(recent_activity.snapshot(games), event='recentActivity')), daemon=True).start()
    elif action == 'phone-fit':
        modes = c.get('modes') if isinstance(c.get('modes'), dict) else {}
        modes = {str(k).lower(): v for k, v in modes.items() if v in MODES}
        outputs = c.get('outputs') if isinstance(c.get('outputs'), list) else []
        threading.Thread(target=lambda: _windows.fit(outputs, modes), daemon=True).start()
    elif action == 'phone-split':
        threading.Thread(target=lambda: _windows.split(c.get('output'), c.get('left'), c.get('right'), _ratio(c.get('ratio'), .5),
                                                       _inset(c.get('top')) or 48, _inset(c.get('bottom')), _inset(c.get('keyboard')),
                                                       c.get('workspace') if type(c.get('workspace')) is int else 0), daemon=True).start()
    elif action == 'phone-home':
        threading.Thread(target=_windows.go_home, daemon=True).start()
    elif action == 'phone-unsplit':
        outputs = c.get('outputs') if isinstance(c.get('outputs'), list) else []
        threading.Thread(target=lambda: _windows.unsplit(c.get('addresses') if isinstance(c.get('addresses'), list) else [], outputs), daemon=True).start()
    elif action == 'phone-release':
        outputs = c.get('outputs') if isinstance(c.get('outputs'), list) else []
        threading.Thread(target=lambda: _windows.release(outputs), daemon=True).start()
    elif action == 'phone-lift':
        threading.Thread(target=lambda: _windows.lift(c.get('output'), _inset(c.get('keyboard'))), daemon=True).start()
    else:
        threading.Thread(target=lambda: _windows.slide_over(c.get('output'), c.get('address'), _ratio(c.get('fraction'), .38),
                                                            _inset(c.get('top')) or 48, _inset(c.get('bottom'))), daemon=True).start()
    return True


LOCK_NOTIFICATIONS = ('off', 'count', 'title')


def valid_preference(key, value):
    """Check phone preferences. Unknown keys are not valid here."""
    if key in ('phoneFitApps', 'phoneEdgeBack', 'ambientClock'):
        return type(value) is bool
    if key == 'lockNotifications':
        return value in LOCK_NOTIFICATIONS
    if key == 'phoneSplitRatio':
        return type(value) in (int, float) and .25 <= value <= .75
    if key == 'phoneAppModes':
        return isinstance(value, dict) and len(value) <= 128 and all(isinstance(k, str) and 0 < len(k) <= 200 and v in MODES for k, v in value.items())
    return False
