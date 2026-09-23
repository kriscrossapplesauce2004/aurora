#!/usr/bin/env python3
import glob
import json
import os
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor


_COMMAND_WORKERS = 6
_STATUS_POOL = ThreadPoolExecutor(max_workers=_COMMAND_WORKERS, thread_name_prefix='opal-status')

def run(*args):
    try: return subprocess.check_output(args, stderr=subprocess.DEVNULL, timeout=1).decode().strip()
    except Exception: return ''


def _run_status_commands(commands):
    """Run independent probes together and keep one result per probe."""
    def probe(item):
        name, args = item
        try:
            return name, run(*args)
        except Exception:
            return name, ''

    return dict(_STATUS_POOL.map(probe, commands.items()))

def collect_status():
    s = {'workspace': 1, 'workspaces': [], 'title': 'Your space, beautifully quiet', 'volume': 0, 'muted': False, 'network': 'Offline', 'track': '', 'artist': '', 'battery': -1}
    commands = {
        'volume': ('wpctl', 'get-volume', '@DEFAULT_AUDIO_SINK@'),
        'network': ('nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show', '--active'),
        'media': ('playerctl', 'metadata', '--format', '{{title}}\x1f{{artist}}'),
    }
    hyprland = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE')
    if hyprland:
        commands.update({
            'workspace': ('hyprctl', 'activeworkspace', '-j'),
            'workspaces': ('hyprctl', 'workspaces', '-j'),
            'window': ('hyprctl', 'activewindow', '-j'),
        })
    values = _run_status_commands(commands)
    if hyprland:
        try:
            s['workspace'] = json.loads(values['workspace'])['id']
            s['workspaces'] = [w['id'] for w in json.loads(values['workspaces'])]
            s['title'] = json.loads(values['window']).get('title', s['title'])
        except Exception: pass
    v = values['volume']
    try: s['volume'] = round(float(v.split()[1])*100)
    except Exception: pass
    s['muted'] = 'MUTED' in v
    n = values['network']
    s['network'] = next((l.rsplit(':',1)[0] for l in n.splitlines() if not l.endswith(':loopback')), 'Offline')
    media = values['media']
    if media:
        s['track'], _, s['artist'] = media.partition('\x1f')
    for b in glob.iglob('/sys/class/power_supply/BAT*/capacity'):
        try:
            with open(b) as capacity:
                s['battery'] = int(capacity.read())
        except Exception: pass
    return s


if __name__ == '__main__':
    while True:
        print(json.dumps(collect_status()), flush=True)
        time.sleep(2)
