#!/usr/bin/env python3
"""Assemble the single-binary runtime and migrate guest command locations."""
import argparse
from pathlib import Path
import re
import shutil

REPO = Path(__file__).resolve().parent.parent
ANDROID_COMMANDS = '''aurorad auroractl evgrab aurora-input-forwarder
aurora-audio-probe aurora-audio-owner aurora-audio-route aurora-audio-smoke
device-config generate-lxc-config generate-guest-config boot-profile guest-distro
env-install guest-start desktop-on desktop-off desktop-memory session-catalog
session-select session-set run-transition external-presenter external-input
native-restore aurora-hostagent aurora-color-compat
cycle-stress.sh'''.split()
GUEST_NATIVE = '''aurora-guest-agent aurora-audio-probe aurora-connectivity
aurora-media-action aurora-osk aurora-audio-volume aurora-signal'''.split()
PRIVATE = '/usr/local/libexec/aurora'


def rewrite(text):
    text = re.sub(r'/usr/local/(?:s?bin)/(aurora-[A-Za-z0-9_.-]+)',
                  lambda m: PRIVATE + '/' + m[1], text)
    # Internal shell launchers must still resolve their private sibling helpers.
    text = text.replace('PATH=/usr/local/sbin:/usr/local/bin:',
                        f'PATH={PRIVATE}:/usr/local/sbin:/usr/local/bin:')
    text = text.replace('PATH=/usr/local/bin:', f'PATH={PRIVATE}:/usr/local/bin:')
    # Desktop actions do not inherit the private implementation PATH.
    text = re.sub(r'(?m)^(Exec=)(aurora-[A-Za-z0-9_.-]+)',
                  lambda m: m[1] + PRIVATE + '/' + m[2], text)
    text = re.sub(r'(?<=exec, )(aurora-[A-Za-z0-9_.-]+)',
                  lambda m: PRIVATE + '/' + m[1], text)
    return text


def rewrite_tree(root):
    for path in root.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        raw = path.read_bytes()
        if b'\0' in raw:
            continue
        try:
            text = raw.decode('utf-8')
        except UnicodeDecodeError:
            continue
        updated = rewrite(text)
        if updated != text:
            path.write_text(updated)


def payload(work):
    tools = work / 'tools'
    tools.mkdir(parents=True, exist_ok=True)
    shutil.copy2(REPO / 'dist/cli/android-arm64/aurora', tools / 'aurora')
    (tools / 'android-commands').write_text('\n'.join(ANDROID_COMMANDS) + '\n')
    guest = work / 'guest-tools'
    shutil.copy2(REPO / 'dist/cli/linux-arm64/aurora', guest / 'aurora')
    for name in GUEST_NATIVE:
        (guest / name).unlink(missing_ok=True)
    for name in ('guest-tools', 'guest-assets', 'guest-config', 'sessions'):
        rewrite_tree(work / name)


def guest(root, binary):
    private = root / PRIVATE.lstrip('/')
    private.mkdir(parents=True, exist_ok=True)
    public = root / 'usr/local/bin'
    public.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, public / 'aurora')
    for folder in (public, root / 'usr/local/sbin'):
        for path in folder.glob('aurora-*'):
            if path.is_file() or path.is_symlink():
                shutil.move(str(path), str(private / path.name))
    for name in GUEST_NATIVE:
        path = private / name
        path.unlink(missing_ok=True)
        path.symlink_to('../../bin/aurora')
    for folder in ('usr/local/libexec/aurora', 'etc/systemd', 'usr/lib/systemd',
                   'usr/share/applications', 'etc/aurora', 'root'):
        rewrite_tree(root / folder)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--payload', type=Path)
    parser.add_argument('--guest-root', type=Path)
    parser.add_argument('--binary', type=Path, default=REPO / 'dist/cli/linux-arm64/aurora')
    args = parser.parse_args()
    if args.payload:
        payload(args.payload)
    elif args.guest_root:
        guest(args.guest_root, args.binary)
    else:
        parser.error('choose --payload or --guest-root')
