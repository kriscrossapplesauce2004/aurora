"""Read local power state without changing device power settings."""
from pathlib import Path
import re


SYSTEM_POWER_PATH = Path('/sys/class/power_supply')
CPU_PATH = Path('/sys/devices/system/cpu')
CONNECTED_DEVICE = re.compile(r'^Device ((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})\s+(.+)$')
BATTERY_PERCENTAGE = re.compile(r'Battery Percentage:\s*(?:0x[0-9A-Fa-f]+\s*)?\((\d{1,3})\)|Battery Percentage:\s*(\d{1,3})%?')


def _text(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ''


def _percent(value):
    try:
        number = int(str(value).strip().rstrip('%'))
    except ValueError:
        return None
    return number if 0 <= number <= 100 else None


def system_batteries(root=SYSTEM_POWER_PATH):
    """Return batteries exposed by the Linux power-supply class."""
    try:
        devices = sorted(Path(root).iterdir())
    except OSError:
        return []
    batteries = []
    for device in devices:
        if _text(device / 'type').lower() != 'battery':
            continue
        percent = _percent(_text(device / 'capacity'))
        if percent is None:
            continue
        state = _text(device / 'status').lower()
        name = _text(device / 'model_name') or ('System battery' if device.name.upper().startswith('BAT') else device.name)
        batteries.append({
            'id': device.name,
            'name': name,
            'percent': percent,
            'state': state,
            'charging': state in ('charging', 'pending-charge'),
            'internal': True,
            'source': 'system',
        })
    return batteries


def parse_upower_batteries(text):
    """Parse the battery records from `upower -d` output."""
    batteries = []
    for section in re.split(r'(?m)^Device:\s+', text)[1:]:
        lines = section.splitlines()
        if not lines:
            continue
        device_path = lines[0].strip()
        if device_path.endswith('/DisplayDevice'):
            continue
        values = {}
        for line in lines[1:]:
            match = re.match(r'^\s+([A-Za-z][A-Za-z -]+):\s*(.+)$', line)
            if match:
                key = match.group(1).strip().lower().replace(' ', '_')
                values[key] = match.group(2).strip()
        if values.get('present', 'yes').lower() == 'no':
            continue
        percent = _percent(values.get('percentage', ''))
        if percent is None:
            continue
        native_path = values.get('native-path', '')
        power_supply = values.get('power_supply', '').lower() == 'yes'
        internal = power_supply or native_path.upper().startswith('BAT')
        name = values.get('model') or native_path or device_path.rsplit('/', 1)[-1]
        state = values.get('state', '').lower()
        batteries.append({
            'id': native_path or device_path,
            'name': name,
            'percent': percent,
            'state': state,
            'charging': state in ('charging', 'pending-charge'),
            'internal': internal,
            'source': 'upower',
        })
    return batteries


def connected_bluetooth_devices(text):
    """Return connected-device addresses and names from bluetoothctl output."""
    devices = []
    for line in text.splitlines():
        match = CONNECTED_DEVICE.match(line.strip())
        if match:
            devices.append(match.groups())
    return devices


def parse_bluetooth_battery(address, name, text):
    """Return one connected Bluetooth battery, or None when unavailable."""
    match = BATTERY_PERCENTAGE.search(text)
    if not match:
        return None
    percent = _percent(match.group(1) or match.group(2))
    if percent is None:
        return None
    return {
        'id': 'bluetooth:' + address.upper(),
        'name': name or address.upper(),
        'percent': percent,
        'state': '',
        'charging': False,
        'internal': False,
        'source': 'bluetooth',
    }


def merge_batteries(*groups):
    """Merge battery sources while keeping the system record authoritative."""
    merged = {}
    for group in groups:
        for battery in group:
            key = str(battery.get('id', '')).lower()
            if not key:
                continue
            current = merged.get(key)
            if current is None or battery.get('source') == 'system':
                merged[key] = battery
    return list(merged.values())


def primary_battery(batteries):
    """Prefer system batteries, then use a connected Bluetooth battery."""
    internal = [battery for battery in batteries if battery.get('internal')]
    if internal:
        percent = round(sum(battery['percent'] for battery in internal) / len(internal))
        return percent, any(battery.get('charging') for battery in internal)
    connected = [battery for battery in batteries if battery.get('source') == 'bluetooth']
    if not connected:
        return -1, False
    percent = round(sum(battery['percent'] for battery in connected) / len(connected))
    return percent, any(battery.get('charging') for battery in connected)


def cpu_governor(root=CPU_PATH):
    """Return the active CPU governor, or mixed when CPUs disagree."""
    governors = set()
    try:
        paths = Path(root).glob('cpu[0-9]*/cpufreq/scaling_governor')
        for path in paths:
            value = _text(path)
            if value:
                governors.add(value)
    except OSError:
        return ''
    if not governors:
        return ''
    return next(iter(governors)) if len(governors) == 1 else 'mixed'
