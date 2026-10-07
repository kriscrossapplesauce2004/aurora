"""Event-driven Hyprland adapter; independent of slow system-status polling."""
import json
import os
import pathlib
import select
import socket
import time


REFRESH_EVENTS = frozenset({
    'createworkspace', 'createworkspacev2', 'destroyworkspace',
    'destroyworkspacev2', 'moveworkspace', 'moveworkspacev2',
    'renameworkspace', 'openwindow', 'closewindow', 'movewindow',
    'movewindowv2', 'monitoradded',
    'monitorremoved', 'configreloaded', 'fullscreen', 'workspace', 'workspacev2',
    'focusedmon', 'focusedmonv2', 'activespecial', 'activespecialv2',
})


def fullscreen_monitors(monitors, clients):
    """Return outputs with a true fullscreen client on a visible workspace."""
    result = []
    for monitor in monitors:
        special = monitor.get('specialWorkspace', {}).get('id', 0)
        workspace = special or monitor.get('activeWorkspace', {}).get('id')
        if any(client.get('mapped') and not client.get('hidden', False)
               and client.get('monitor') == monitor.get('id')
               and client.get('workspace', {}).get('id') == workspace
               and client.get('fullscreen') == 2 for client in clients):
            result.append(monitor['name'])
    return result


def _address(text):
    return '0x' + text.removeprefix('0x') if text else ''


def _drop_urgent(state, address, patch):
    # A focused or closed window is no longer urgent.
    if address in state['urgent']:
        state['urgent'].remove(address)
        patch({'urgent': list(state['urgent'])})


def _handle_state_event(event, payload, patch, state):
    """Handle events that keep small state in the adapter; return True if handled."""
    if event == 'urgent':
        address = _address(payload)
        if address and address not in state['urgent']:
            state['urgent'].append(address)
            patch({'urgent': list(state['urgent'])})
    elif event == 'closewindow':
        address = _address(payload)
        _drop_urgent(state, address, patch)
        if address in state['minimized']:
            state['minimized'].remove(address)
            patch({'minimized': list(state['minimized'])})
        return False
    elif event == 'submap':
        patch({'submap': payload.strip()})
    elif event in ('activespecialv2', 'activespecial'):
        # The v2 payload is id,name,monitor; the old one is name,monitor.
        fields = payload.split(',')
        name, monitor = (fields[1], fields[-1]) if event == 'activespecialv2' and len(fields) >= 3 else (fields[0], fields[-1])
        if event == 'activespecial' and len(fields) < 2:
            return False
        state['special'][monitor] = name
        patch({'special': dict(state['special'])})
        return False
    elif event == 'windowtitlev2':
        address, _, title = payload.partition(',')
        patch({'windowTitle': {'address': _address(address), 'title': title}})
    elif event == 'minimized':
        address, _, flag = payload.partition(',')
        address = _address(address)
        known = address in state['minimized']
        if flag.strip() == '1' and not known:
            state['minimized'].append(address)
        elif flag.strip() != '1' and known:
            state['minimized'].remove(address)
        else:
            return True
        patch({'minimized': list(state['minimized'])})
    else:
        return False
    return True


def new_state():
    return {'urgent': [], 'special': {}, 'minimized': []}


def _handle_event(event, payload, patch, query, state=None):
    state = state if state is not None else new_state()
    if _handle_state_event(event, payload, patch, state) and event != 'closewindow':
        return False
    if event == 'workspacev2':
        patch({'workspace': int(payload.split(',', 1)[0])})
    elif event == 'focusedmonv2':
        monitor, _, workspace = payload.partition(',')
        patch({'workspace': int(workspace), 'activeMonitor': monitor})
    elif event == 'focusedmon':
        # This event has no workspace number on older Hyprland releases.
        patch({'workspace': query('activeworkspace')['id'], 'activeMonitor': payload.split(',', 1)[0]})
    elif event == 'activewindow':
        patch({'title': payload.partition(',')[2] or 'Your desktop'})
    elif event == 'activewindowv2':
        patch({'activeAddress': _address(payload)})
        _drop_urgent(state, _address(payload), patch)
    return event in REFRESH_EVENTS


def _drain_events(buffer, patch, query, state=None):
    """Handle complete lines and keep one incomplete line."""
    state = state if state is not None else new_state()
    start = 0
    needs_refresh = False
    while (newline := buffer.find(b'\n', start)) >= 0:
        event, _, payload = buffer[start:newline].decode(errors='replace').partition('>>')
        needs_refresh = _handle_event(event, payload, patch, query, state) or needs_refresh
        start = newline + 1
    if start:
        del buffer[:start]
    return needs_refresh


def listen(emit):
    signature = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE')
    if not signature:
        return
    base = pathlib.Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'hypr' / signature
    if not (base / '.socket2.sock').exists():
        base = pathlib.Path('/tmp/hypr') / signature

    def query(name):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(0.5)
            client.connect(str(base / '.socket.sock'))
            client.sendall(('j/' + name).encode())
            chunks = []
            while True:
                chunk = client.recv(65536)
                if not chunk:
                    break
                chunks.append(chunk)
            return json.loads(b''.join(chunks))

    def patch(data):
        emit({'event': 'compositor', 'data': data})

    state = new_state()

    def refresh(initial=False):
        # Do not overwrite event-driven focus with a background snapshot.
        clients = query('clients')
        monitors = query('monitors')
        names = {m.get('id'): m.get('name', '') for m in monitors}
        data = {
            'workspaces': [w['id'] for w in query('workspaces') if w['id'] > 0],
            'fullscreenMonitors': fullscreen_monitors(monitors, clients),
            # Monitor names and active workspaces let the phone home show and move windows between screens.
            # Geometry lets Rooms draw each workspace with its real tiling.
            'monitors': [{'name': m.get('name', ''), 'workspace': m.get('activeWorkspace', {}).get('id', 0),
                          'x': m.get('x', 0), 'y': m.get('y', 0), 'width': m.get('width', 0), 'height': m.get('height', 0),
                          'scale': m.get('scale', 1) or 1, 'transform': m.get('transform', 0)} for m in monitors],
            'windows': [
                {'title': w['title'], 'className': w['class'],
                 'address': w['address'], 'workspace': w['workspace']['id'],
                 'monitor': names.get(w.get('monitor'), ''),
                 'at': w.get('at', [0, 0]), 'size': w.get('size', [0, 0]),
                 'floating': bool(w.get('floating')), 'fullscreen': w.get('fullscreen', 0)}
                for w in clients if w.get('mapped')
            ],
        }
        live = {w['address'] for w in clients if w.get('mapped')}
        for key in ('urgent', 'minimized'):
            state[key] = [a for a in state[key] if a in live]
        data.update(urgent=list(state['urgent']), minimized=list(state['minimized']))
        if initial:
            focused = query('activewindow')
            workspace = query('activeworkspace')
            data.update(hypr=True, workspace=workspace['id'], activeMonitor=workspace.get('monitor', ''),
                        title=focused.get('title', 'Your desktop'), activeAddress=focused.get('address', ''))
        patch(data)

    while True:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as events:
                events.connect(str(base / '.socket2.sock'))
                # Subscribe first so transitions during initialization aren't lost.
                refresh(initial=True)
                buffer = bytearray()
                deadline = None
                while True:
                    timeout = None if deadline is None else max(0, deadline - time.monotonic())
                    if select.select([events], [], [], timeout)[0]:
                        chunk = events.recv(65536)
                        if not chunk:
                            break
                        buffer.extend(chunk)
                        if _drain_events(buffer, patch, query, state) and deadline is None:
                            deadline = time.monotonic() + 0.025
                    if deadline is not None and time.monotonic() >= deadline:
                        refresh()
                        deadline = None
        except (OSError, ValueError, KeyError, TypeError):
            pass
        state.update(new_state())
        patch({'hypr': False, 'fullscreenMonitors': [], 'urgent': [], 'submap': '', 'special': {}, 'minimized': []})
        # Reconnect without busy-looping if the compositor socket goes away.
        time.sleep(1)
