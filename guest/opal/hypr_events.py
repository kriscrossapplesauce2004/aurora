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
    'movewindowv2', 'windowtitle', 'windowtitlev2', 'monitoradded',
    'monitorremoved', 'configreloaded', 'fullscreen', 'workspace', 'workspacev2',
    'focusedmon', 'focusedmonv2', 'activespecial',
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


def _handle_event(event, payload, patch, query):
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
        patch({'activeAddress': ('0x' + payload.removeprefix('0x')) if payload else ''})
    return event in REFRESH_EVENTS


def _drain_events(buffer, patch, query):
    """Handle complete lines and keep one incomplete line."""
    start = 0
    needs_refresh = False
    while (newline := buffer.find(b'\n', start)) >= 0:
        event, _, payload = buffer[start:newline].decode(errors='replace').partition('>>')
        needs_refresh = _handle_event(event, payload, patch, query) or needs_refresh
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

    def refresh(initial=False):
        # Do not overwrite event-driven focus with a background snapshot.
        clients = query('clients')
        monitors = query('monitors')
        names = {m.get('id'): m.get('name', '') for m in monitors}
        data = {
            'workspaces': [w['id'] for w in query('workspaces') if w['id'] > 0],
            'fullscreenMonitors': fullscreen_monitors(monitors, clients),
            # Monitor names and active workspaces let the phone home show and move windows between screens.
            'monitors': [{'name': m.get('name', ''), 'workspace': m.get('activeWorkspace', {}).get('id', 0)} for m in monitors],
            'windows': [
                {'title': w['title'], 'className': w['class'],
                 'address': w['address'], 'workspace': w['workspace']['id'],
                 'monitor': names.get(w.get('monitor'), '')}
                for w in clients if w.get('mapped')
            ],
        }
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
                        if _drain_events(buffer, patch, query) and deadline is None:
                            deadline = time.monotonic() + 0.025
                    if deadline is not None and time.monotonic() >= deadline:
                        refresh()
                        deadline = None
        except (OSError, ValueError, KeyError, TypeError):
            pass
        patch({'hypr': False, 'fullscreenMonitors': []})
        # Reconnect without busy-looping if the compositor socket goes away.
        time.sleep(1)
