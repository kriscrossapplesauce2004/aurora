"""Publish the shell's resolved per-output layouts for the Lua compositor config."""
import os
import re


MODES = frozenset(('auto', 'desktop', 'phone', 'console'))
DISPLAY_MODES = frozenset(('desktop', 'phone', 'console'))
DISPLAY_NAME = re.compile(r'[A-Za-z0-9_.:-]{1,128}')


def publish(runtime, mode, displays):
    if mode not in MODES or not isinstance(displays, list) or len(displays) > 32:
        raise ValueError('Invalid display layouts')
    phones = set()
    for display in displays:
        if not isinstance(display, dict):
            raise ValueError('Invalid display')
        name = display.get('name', '')
        layout = display.get('mode')
        if not isinstance(name, str) or not DISPLAY_NAME.fullmatch(name) or layout not in DISPLAY_MODES:
            raise ValueError('Invalid display')
        if layout == 'phone':
            phones.add(name)
    path = os.path.join(runtime, 'opal-phone-displays')
    data = 'mode=' + mode + '\n' + ''.join(name + '\n' for name in sorted(phones))
    try:
        with open(path, encoding='utf-8') as published:
            if published.read() == data:
                return False
    except FileNotFoundError:pass
    temp = path + '.tmp'
    with open(temp, 'w', encoding='utf-8') as pending:
        pending.write(data)
    os.replace(temp, path)
    return True
