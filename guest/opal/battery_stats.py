"""Battery statistics from sysfs for the phone battery page. Values that sysfs does not give are left out."""
import pathlib

POWER = pathlib.Path('/sys/class/power_supply')


def _read(path):
    try:
        return pathlib.Path(path).read_text().strip()
    except OSError:
        return ''


def _int(path):
    try:
        return int(_read(path))
    except ValueError:
        return None


def estimate_hours(status, energy_now, energy_full, power_now):
    """Return hours to empty or to full from micro watt hours and micro watts, or None."""
    if not power_now or power_now <= 0 or energy_now is None:
        return None
    if status == 'Discharging':
        return round(energy_now / power_now, 2)
    if status == 'Charging' and energy_full:
        return round(max(0, energy_full - energy_now) / power_now, 2)
    return None


def read(root=POWER):
    """Return details for the first battery, or a result with available false."""
    try:
        entries = sorted(pathlib.Path(root).iterdir())
    except OSError:
        return {'available': False}
    for entry in entries:
        if _read(entry / 'type') != 'Battery' or _read(entry / 'scope') == 'Device':
            continue
        status = _read(entry / 'status') or 'Unknown'
        # Some drivers use charge and microamps. Convert with voltage so one path handles both.
        volts = _int(entry / 'voltage_now')
        energy_now, energy_full = _int(entry / 'energy_now'), _int(entry / 'energy_full')
        design = _int(entry / 'energy_full_design')
        power = _int(entry / 'power_now')
        if energy_now is None and volts:
            charge_now, charge_full = _int(entry / 'charge_now'), _int(entry / 'charge_full')
            charge_design, current = _int(entry / 'charge_full_design'), _int(entry / 'current_now')
            scale = volts / 1_000_000
            energy_now = None if charge_now is None else int(charge_now * scale)
            energy_full = None if charge_full is None else int(charge_full * scale)
            design = None if charge_design is None else int(charge_design * scale)
            power = None if current is None else int(abs(current) * scale)
        elif power is not None:
            power = abs(power)
        health = round(100 * energy_full / design) if energy_full and design else None
        temperature = _int(entry / 'temp')
        return {'available': True, 'name': entry.name, 'status': status, 'percent': _int(entry / 'capacity'),
                'watts': None if power is None else round(power / 1_000_000, 2),
                'volts': None if not volts else round(volts / 1_000_000, 2),
                'hours': estimate_hours(status, energy_now, energy_full, power),
                'health': health if health is None or 0 < health <= 130 else None,
                'cycles': _int(entry / 'cycle_count'),
                'celsius': None if temperature is None else round(temperature / 10, 1)}
    return {'available': False}
