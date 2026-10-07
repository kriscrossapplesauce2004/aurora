#!/usr/bin/env python3
"""Opal MCP server: lets Claude read and change the running Opal shell over Quickshell IPC. stdio, JSON-RPC 2.0."""
import base64
import json, os, pathlib, socket, subprocess, sys
import assistant_tools

CONFIG = os.environ.get('OPAL_CONFIG_DIR') or str(pathlib.Path(__file__).resolve().parent)
PANELS = ('launcher', 'controls', 'notifications', 'clipboard', 'appearance', 'settings', 'convergence', 'audio', 'quickaccess', 'close')
LAYOUTS = {'phone': 'phone', 'desktop': 'desktop', 'console': 'gaming', 'auto': 'adaptive'}

def ipc(function, *args):
    result = subprocess.run(['quickshell', 'ipc', '-p', CONFIG, 'call', 'opal', function, *map(str, args)], capture_output=True, text=True, timeout=10)
    if result.returncode: raise RuntimeError((result.stderr or result.stdout).strip() or 'Opal is not running')
    return result.stdout.strip()

def schema(properties=None, required=()):
    return {'type': 'object', 'properties': properties or {}, 'required': list(required)}

def list_windows(arguments):
    # Hyprland gives addresses; other compositors fall back to the shell's own list.
    try: return json.dumps(assistant_tools.windows())
    except RuntimeError: return ipc('windows')

def approve(arguments):
    """Permission prompt tool for Claude Code. It asks the user in the Opal assistant panel and denies on any failure."""
    tool_input = arguments.get('input') if isinstance(arguments.get('input'), dict) else {}
    allow = False
    path = os.environ.get('OPAL_APPROVAL_SOCKET')
    if path:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                connection.settimeout(135)
                connection.connect(path)
                connection.sendall((json.dumps({'tool_name': str(arguments.get('tool_name', '')), 'input': tool_input}) + '\n').encode())
                data = b''
                while not data.endswith(b'\n'):
                    chunk = connection.recv(4096)
                    if not chunk: break
                    data += chunk
            allow = json.loads(data.decode()).get('allow') is True
        except (OSError, ValueError): allow = False
    if allow: return json.dumps({'behavior': 'allow', 'updatedInput': tool_input})
    return json.dumps({'behavior': 'deny', 'message': 'The user declined this action in the Opal panel.'})

def workspace_number(value):
    if type(value) is not int or not 1 <= value <= 99: raise ValueError('Workspace must be 1 to 99')
    return value

TOOLS = {
    'get_status': ('Read Opal status: page, layout mode, unread count, volume, battery, network, media.', schema(), lambda a: ipc('inspect')),
    'get_preferences': ('Read Opal preferences (theme, bar style, layout, tiles, sections and more).', schema(), lambda a: ipc('preferences')),
    'set_preference': ('Change one Opal preference. Value is JSON. Examples: light=true, barStyle="dock", iconStyle="themed", dnd=true, sheetSections=["sliders","tiles"]. Invalid values are ignored.',
                       schema({'key': {'type': 'string'}, 'value': {'description': 'JSON value'}}, ('key', 'value')),
                       lambda a: ipc('setPreferenceEncoded', a['key'], base64.b64encode(json.dumps(a['value']).encode()).decode())),
    'open_panel': ('Open or close an Opal panel.', schema({'panel': {'type': 'string', 'enum': list(PANELS)}}, ('panel',)), lambda a: ipc(a['panel'])),
    'set_layout': ('Switch the shell layout.', schema({'layout': {'type': 'string', 'enum': list(LAYOUTS)}}, ('layout',)), lambda a: ipc(LAYOUTS[a['layout']])),
    'list_notifications': ('List notifications in the Opal inbox.', schema(), lambda a: ipc('listNotifications')),
    'list_windows': ('List open windows with address, app, title and workspace.', schema(), list_windows),
    'launch_app': ('Launch an installed app by name, like "Firefox".', schema({'name': {'type': 'string'}}, ('name',)), lambda a: assistant_tools.launch_app(a['name'])),
    'focus_window': ('Bring a window to the front. Match by address, app name or title.', schema({'window': {'type': 'string'}}, ('window',)), lambda a: assistant_tools.focus_window(a['window'])),
    'close_window': ('Close a window. Match by address, app name or title. The user must confirm.', schema({'window': {'type': 'string'}}, ('window',)), lambda a: assistant_tools.close_window(a['window'])),
    'move_window': ('Move a window to a workspace.', schema({'window': {'type': 'string'}, 'workspace': {'type': 'integer', 'minimum': 1, 'maximum': 99}, 'follow': {'type': 'boolean'}}, ('window', 'workspace')),
                    lambda a: assistant_tools.move_window(a['window'], workspace_number(a['workspace']), a.get('follow') is True)),
    'switch_workspace': ('Switch to a workspace by number.', schema({'workspace': {'type': 'integer', 'minimum': 1, 'maximum': 99}}, ('workspace',)), lambda a: assistant_tools.switch_workspace(workspace_number(a['workspace']))),
    'open_target': ('Open a web link, mail link or existing file with the default app. The user must confirm.', schema({'target': {'type': 'string'}}, ('target',)), lambda a: assistant_tools.open_target(a['target'])),
    'approve': ('Internal permission prompt for the Opal assistant. Do not call it.', schema({'tool_name': {'type': 'string'}, 'input': {'type': 'object'}, 'tool_use_id': {'type': 'string'}}, ('tool_name',)), approve),
    'media': ('Control the active media player.', schema({'action': {'type': 'string', 'enum': ['play-pause', 'next', 'previous']}}, ('action',)), lambda a: ipc('media', a['action'])),
    'set_volume': ('Set output volume, 0 to 100.', schema({'value': {'type': 'integer', 'minimum': 0, 'maximum': 100}}, ('value',)), lambda a: ipc('volume', int(a['value']))),
    'search': ('Open Start with a search query.', schema({'text': {'type': 'string'}}, ('text',)), lambda a: ipc('search', a['text'])),
    'show_message': ('Show a short message in the shell.', schema({'text': {'type': 'string'}}, ('text',)), lambda a: ipc('toast', a['text']) or 'Shown'),
    'lock_screen': ('Lock the session.', schema(), lambda a: ipc('lock') or 'Locked'),
}

def handle(message):
    method, ident = message.get('method'), message.get('id')
    if method == 'initialize':
        result = {'protocolVersion': message.get('params', {}).get('protocolVersion', '2025-06-18'), 'capabilities': {'tools': {}},
                  'serverInfo': {'name': 'opal', 'version': '1.0'}, 'instructions': 'Tools for the Opal desktop shell. Read status or preferences before changing things.'}
    elif method == 'tools/list':
        result = {'tools': [{'name': n, 'description': d, 'inputSchema': s} for n, (d, s, _) in TOOLS.items()]}
    elif method == 'tools/call':
        params = message.get('params', {})
        tool = TOOLS.get(params.get('name'))
        if not tool: return {'jsonrpc': '2.0', 'id': ident, 'error': {'code': -32602, 'message': 'Unknown tool'}}
        try: text, error = tool[2](params.get('arguments') or {}) or 'Done', False
        except (RuntimeError, KeyError, ValueError, OSError, subprocess.SubprocessError) as problem: text, error = str(problem), True
        result = {'content': [{'type': 'text', 'text': text}], 'isError': error}
    elif method == 'ping':
        result = {}
    elif ident is None:
        return None
    else:
        return {'jsonrpc': '2.0', 'id': ident, 'error': {'code': -32601, 'message': 'Method not found'}}
    return {'jsonrpc': '2.0', 'id': ident, 'result': result}

def main():
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        try: reply = handle(json.loads(line))
        except ValueError: reply = {'jsonrpc': '2.0', 'id': None, 'error': {'code': -32700, 'message': 'Parse error'}}
        if reply is not None:
            sys.stdout.write(json.dumps(reply) + '\n'); sys.stdout.flush()

if __name__ == '__main__':
    main()
