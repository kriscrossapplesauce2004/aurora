"""JSON-lines convergence service. It reads input state, decides layouts and moves windows.

Commands on stdin: {"cmd":"state","outputs":[...],"prefs":{...}} and {"cmd":"undo"}.
Events on stdout: {"event":"convergence", ...} and {"event":"windows", ...}. Diagnostics go to stderr.
"""
import json
import sys
import threading

import convergence_events
import convergence_policy
import convergence_windows


class Service:
    def __init__(self, emit, actions=None, memory=None):
        self.emit = emit
        self.engine = convergence_policy.Engine()
        self.input_state = {'keyboard': False, 'pointer': False, 'lid': None, 'tablet': None}
        self.outputs = []
        self.prefs = {}
        self.mover = convergence_windows.Mover(actions, memory) if actions else None
        self.lock = threading.Lock()
        self.undo_windows = False
        self.ready = False
        self.have_input = False

    def set_input(self, state):
        with self.lock:
            self.input_state = state
            self.have_input = True
            self._decide()

    def set_outputs(self, outputs, prefs):
        with self.lock:
            self.outputs = outputs
            self.prefs = prefs
            self.ready = True
            self._decide()

    def _decide(self):
        if not (self.ready and self.have_input):
            return
        state = dict(self.input_state, outputs=self.outputs)
        result = self.engine.update(state, self.prefs)
        if result is None:
            return
        windows = None
        if self.mover and result['initial']:
            self._adopt()
        moving = self.mover and not result['initial'] and self.prefs.get('convergeAuto', True) is not False \
            and self.prefs.get('convergeHotplug', True) is not False and self.prefs.get('convergeMoveApps', True) is not False
        if moving:
            windows = self._move(result)
        if windows is not None:
            result['windows'] = windows
            if windows.get('moved'):
                result['text'] += ' · ' + str(windows['moved']) + (' app moved' if windows['moved'] == 1 else ' apps moved')
        self.emit(dict(result, event='convergence'))

    def _move(self, result):
        phone = next((o['name'] for o in self.outputs if o.get('builtin')), '')
        # Windows move only to and from a panel that is in the phone layout; a laptop or desktop monitor keeps its tiling.
        if phone and result.get('layouts', {}).get(phone) != 'phone':
            return None
        try:
            if result['externalAdded'] and phone:
                return self.mover.dock(phone, result['externalAdded'][0])
            if phone and any(n in self.mover.docked for n in result['removed']):
                return self.mover.undock(phone, result['removed'])
        except (ValueError, OSError, KeyError, TypeError) as error:
            return {'moved': 0, 'error': str(error)}
        except Exception as error:
            return {'moved': 0, 'error': 'Window move failed: ' + str(error)}
        return None

    def _adopt(self):
        # A monitor present at start is docked already; remember it without moving anything.
        try:
            self.mover.adopt([o['name'] for o in self.outputs if not o.get('builtin')])
        except Exception:
            pass

    def snapshot(self):
        """Remember docked layouts so an undock can restore them later."""
        if self.mover and self.mover.docked:
            with self.lock:
                try:
                    self.mover.snapshot()
                except Exception:
                    pass

    def undo(self):
        if self.mover:
            try:
                self.emit({'event': 'windows', **self.mover.undo()})
            except Exception as error:
                self.emit({'event': 'windows', 'moved': 0, 'error': str(error)})
        else:
            self.emit({'event': 'windows', 'moved': 0, 'error': 'Window moves need Hyprland'})


def main():
    import os
    import shutil
    from hypr_actions import HyprActions

    def emit(data):
        sys.stdout.write(json.dumps(data, separators=(',', ':')) + '\n')
        sys.stdout.flush()

    hypr = bool(os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') and shutil.which('hyprctl'))
    service = Service(emit, HyprActions() if hypr else None, convergence_windows.Memory() if hypr else None)
    if not hypr:
        emit({'event': 'capabilities', 'windows': False})
    threading.Thread(target=convergence_events.watch, args=(service.set_input,), daemon=True).start()

    def snapshots():
        import time
        while True:
            time.sleep(3)
            service.snapshot()
    threading.Thread(target=snapshots, daemon=True).start()
    for line in sys.stdin:
        try:
            command = json.loads(line)
        except ValueError:
            continue
        if not isinstance(command, dict):
            continue
        if command.get('cmd') == 'state' and isinstance(command.get('outputs'), list) and isinstance(command.get('prefs'), dict):
            outputs = [{'name': str(o.get('name', '')), 'width': int(o.get('width', 0)), 'height': int(o.get('height', 0)),
                        'builtin': convergence_policy.is_builtin(str(o.get('name', '')), str(command['prefs'].get('phoneDisplay', '')), command['prefs'])}
                       for o in command['outputs'][:32] if isinstance(o, dict)]
            service.set_outputs(outputs, command['prefs'])
        elif command.get('cmd') == 'undo':
            service.undo()


if __name__ == '__main__':
    main()
