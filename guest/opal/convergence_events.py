"""Read-only input and switch detection for convergence. It never grabs or injects input."""
import fcntl
import os
import re
import struct
import time

DEVICES = '/proc/bus/input/devices'
# Bus ids: 3 is USB and 5 is Bluetooth. Built-in and virtual devices use other buses.
EXTERNAL_BUSES = frozenset((0x0003, 0x0005))
EV_REP = 1 << 20
KEY_A = 30
BTN_MOUSE = 0x110
SW_LID = 0
SW_TABLET_MODE = 1


def _bits(text):
    """Convert a kernel bitmap line (most significant word first) to an int."""
    value = 0
    for word in text.split():
        value = (value << 64) | int(word, 16)
    return value


def parse_devices(text):
    """Parse /proc/bus/input/devices into a list of dicts."""
    devices = []
    for block in re.split(r'\n\s*\n', text.strip()):
        device = {'name': '', 'bus': 0, 'handlers': [], 'ev': 0, 'key': 0, 'rel': 0, 'sw': 0}
        for line in block.splitlines():
            head, _, rest = line.partition(': ')
            rest = rest.strip()
            try:
                if head == 'I':
                    match = re.search(r'Bus=([0-9a-fA-F]+)', rest)
                    device['bus'] = int(match.group(1), 16) if match else 0
                elif head == 'N':
                    device['name'] = rest.partition('=')[2].strip('"')
                elif head == 'H':
                    device['handlers'] = rest.partition('=')[2].split()
                elif head == 'B':
                    key, _, value = rest.partition('=')
                    if key in ('EV', 'KEY', 'REL', 'SW'):
                        device[key.lower()] = _bits(value)
            except ValueError:
                continue
        if device['name']:
            devices.append(device)
    return devices


def is_keyboard(device):
    """True for an external device that types letters and repeats keys."""
    return (device['bus'] in EXTERNAL_BUSES and 'kbd' in device['handlers']
            and bool(device['ev'] & EV_REP) and bool(device['key'] >> KEY_A & 1))


def is_pointer(device):
    """True for an external mouse or trackball. A touchpad or touchscreen is not a mouse."""
    return (device['bus'] in EXTERNAL_BUSES and any(h.startswith('mouse') for h in device['handlers'])
            and bool(device['rel']) and bool(device['key'] >> BTN_MOUSE & 1))


def summarize(devices):
    """Return attached-input flags and the event paths that report switches."""
    switches = []
    for device in devices:
        if device['sw'] & ((1 << SW_LID) | (1 << SW_TABLET_MODE)):
            switches += ['/dev/input/' + h for h in device['handlers'] if h.startswith('event')]
    return {'keyboard': any(map(is_keyboard, devices)), 'pointer': any(map(is_pointer, devices)), 'switches': switches}


def read_switch_state(path, reader=None):
    """Read SW_LID and SW_TABLET_MODE with EVIOCGSW. Return a dict, or an empty dict without access."""
    if reader is None:
        def reader(file_path):
            fd = os.open(file_path, os.O_RDONLY | os.O_NONBLOCK)
            try:
                buffer = bytearray(8)
                # EVIOCGSW(8): _IOC(read, 'E', 0x1b, 8)
                fcntl.ioctl(fd, (2 << 30) | (8 << 16) | (ord('E') << 8) | 0x1b, buffer)
                return int.from_bytes(buffer, 'little')
            finally:
                os.close(fd)
    try:
        bits = reader(path)
    except OSError:
        return {}
    return {'lid': 'closed' if bits >> SW_LID & 1 else 'open', 'tablet': bool(bits >> SW_TABLET_MODE & 1)}


def read_lid_acpi(root='/proc/acpi/button/lid'):
    """Fall back to the ACPI lid file when no switch device is readable."""
    try:
        for name in sorted(os.listdir(root)):
            with open(os.path.join(root, name, 'state'), encoding='utf-8') as handle:
                return 'closed' if 'closed' in handle.read() else 'open'
    except OSError:
        pass
    return None


def snapshot(devices_text=None, switch_reader=None, lid_root='/proc/acpi/button/lid', has_sw=None):
    """Return one state dict: keyboard, pointer, lid, tablet. Unknown values are None."""
    if devices_text is None:
        try:
            with open(DEVICES, encoding='utf-8', errors='replace') as handle:
                devices_text = handle.read()
        except OSError:
            devices_text = ''
    info = summarize(parse_devices(devices_text))
    lid, tablet = None, None
    for path in info['switches']:
        state = read_switch_state(path, switch_reader)
        if state:
            lid = state['lid'] if lid is None or state['lid'] == 'closed' else lid
            tablet = state['tablet'] if tablet is None or state['tablet'] else tablet
    if lid is None:
        lid = read_lid_acpi(lid_root)
    # A switch device without a tablet bit would report false for ever; only trust a tablet switch that exists.
    if tablet is not None and not any(d['sw'] >> SW_TABLET_MODE & 1 for d in parse_devices(devices_text)):
        tablet = None
    return {'keyboard': info['keyboard'], 'pointer': info['pointer'], 'lid': lid, 'tablet': tablet}


def watch(emit, interval=2.0, sleep=time.sleep, snap=snapshot, should_stop=lambda: False):
    """Poll the snapshot and emit it when it changes. The first emit is the baseline."""
    last = None
    while not should_stop():
        current = snap()
        if current != last:
            emit(current)
            last = current
        sleep(interval)
