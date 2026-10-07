"""Torch control through a sysfs flash LED or brightnessctl. Missing hardware reports unavailable."""
import pathlib
import shutil
import subprocess

LED_ROOT = pathlib.Path('/sys/class/leds')
# Android and Linux phones name the flash LED in several ways.
NAMES = ('flashlight', 'torch', 'flash', 'white:flash', 'white:torch', 'led:torch', 'led:flash')


def find(root=LED_ROOT):
    """Return the first flash LED directory, or None."""
    try:
        entries = sorted(pathlib.Path(root).iterdir())
    except OSError:
        return None
    for entry in entries:
        if any(name in entry.name.lower() for name in NAMES) and (entry / 'brightness').exists():
            return entry
    return None


def _number(path):
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return 0


def status(root=LED_ROOT):
    """Return availability and state. The torch is hidden when available is false."""
    led = find(root)
    if led is None:
        return {'available': False, 'on': False, 'name': ''}
    return {'available': True, 'on': _number(led / 'brightness') > 0, 'name': led.name}


def set_state(on, root=LED_ROOT, runner=subprocess.run, which=shutil.which):
    """Switch the torch. Direct sysfs writes come first, then brightnessctl for the same device."""
    led = find(root)
    if led is None:
        return status(root)
    level = max(1, _number(led / 'max_brightness')) if on else 0
    try:
        (led / 'brightness').write_text(str(level))
    except OSError:
        if which('brightnessctl'):
            runner(['brightnessctl', '-d', led.name, 'set', str(level)], capture_output=True, timeout=3)
    return status(root)
