"""On-demand connectivity adapter. No shell input or persisted credentials."""
import re
import subprocess
import threading


FILTERED_DEVICE_LINE = re.compile(r'^Device ((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})(?: |$)')
DEVICE_LINE = re.compile(r'Device ([0-9A-Fa-f:]{17}) (.*)')


def fields(line):
    result, part, escaped = [], [], False
    for char in line:
        if escaped:
            part.append(char)
            escaped = False
        elif char == '\\':
            escaped = True
        elif char == ':':
            result.append(''.join(part))
            part = []
        else:
            part.append(char)
    if escaped:
        part.append('\\')
    result.append(''.join(part))
    return result


def filtered_addresses(rows, candidates):
    addresses = set()
    for line in rows.splitlines():
        match = FILTERED_DEVICE_LINE.match(line)
        if match:
            address = match.group(1).upper()
            if address in candidates:
                addresses.add(address)
    return addresses


class Connectivity:
    def __init__(self, emit):
        self.emit = emit
        self.lock = threading.Lock()

    def run(self, *args, timeout=35):
        try:
            p = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                               env={**__import__('os').environ, 'LC_ALL': 'C'})
        except FileNotFoundError:
            raise ValueError(args[0] + ' is not installed')
        except subprocess.TimeoutExpired:
            raise ValueError('Operation timed out. Refresh to check the device state.')
        if p.returncode:
            raise ValueError('Operation failed. Check the radio, credentials and system permissions.')
        return p.stdout.strip()

    def request(self, command):
        if not self.lock.acquire(False):
            return
        threading.Thread(target=self.work, args=(command,), daemon=True).start()

    def work(self, c):
        kind = c.get('kind')
        try:
            if kind not in ('wifi', 'bluetooth'):
                return
            self.emit({'event': 'connectivity', 'kind': kind, 'busy': True})
            verb = c.get('verb', 'refresh')
            if kind == 'wifi':
                if verb == 'power':
                    if type(c.get('enabled')) is not bool: raise ValueError('Invalid power state')
                    self.run('nmcli', 'radio', 'wifi', 'on' if c['enabled'] else 'off')
                elif verb == 'connect':
                    ssid = c.get('ssid')
                    password = c.get('password', '')
                    if not isinstance(ssid, str) or not 0 < len(ssid.encode()) <= 32 or '\x00' in ssid: raise ValueError('Invalid network name')
                    if not isinstance(password, str) or len(password) > 256 or '\x00' in password: raise ValueError('Invalid password')
                    args = ['nmcli', '--wait', '25', 'device', 'wifi', 'connect', ssid]
                    if password: args += ['password', password]
                    self.run(*args)
                elif verb == 'disconnect':
                    device = c.get('device', '')
                    if not isinstance(device, str) or not re.fullmatch(r'[\w.-]{1,64}', device): raise ValueError('Invalid device')
                    self.run('nmcli', 'device', 'disconnect', device)
                elif verb not in ('refresh', 'scan'): raise ValueError('Unsupported operation')
                powered = self.run('nmcli', 'radio', 'wifi') == 'enabled'
                rows = self.run('nmcli', '-t', '-f', 'IN-USE,SSID,SIGNAL,SECURITY,DEVICE', 'device', 'wifi', 'list', '--rescan', 'yes' if verb == 'scan' else 'no') if powered else ''
                items = []
                seen_ssids = set()
                # Saved profiles let the panel skip the password field and group known networks.
                profiles = self.run('nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show') if powered else ''
                saved = {f[0] for f in map(fields, profiles.splitlines()) if len(f) == 2 and 'wireless' in f[1]}
                for line in rows.splitlines():
                    row = fields(line)
                    if len(row) == 5 and row[1] and row[1] not in seen_ssids:
                        seen_ssids.add(row[1])
                        items.append(dict(active=row[0] == '*', ssid=row[1], signal=int(row[2]) if row[2].isdigit() else 0, security=row[3], device=row[4], saved=row[1] in saved))
                items.sort(key=lambda i: (not i['active'], -int(i['signal'] or 0)))
            else:
                if verb == 'power':
                    if type(c.get('enabled')) is not bool: raise ValueError('Invalid power state')
                    self.run('bluetoothctl', 'power', 'on' if c['enabled'] else 'off')
                elif verb in ('connect', 'disconnect', 'pair', 'remove'):
                    address = c.get('address', '')
                    if not isinstance(address, str) or not re.fullmatch(r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}', address): raise ValueError('Invalid Bluetooth address')
                    self.run('bluetoothctl', '--timeout', '25', verb, address)
                elif verb == 'scan':
                    self.run('bluetoothctl', '--timeout', '8', 'scan', 'on', timeout=12)
                elif verb != 'refresh': raise ValueError('Unsupported operation')
                powered = 'Powered: yes' in self.run('bluetoothctl', 'show')
                devices = []
                for line in self.run('bluetoothctl', 'devices').splitlines()[:40]:
                    match = DEVICE_LINE.match(line)
                    if not match: continue
                    address, name = match.groups()
                    devices.append((address, name))
                candidates = {address.upper() for address, _ in devices}
                connected = filtered_addresses(self.run('bluetoothctl', 'devices', 'Connected'), candidates)
                paired = filtered_addresses(self.run('bluetoothctl', 'devices', 'Paired'), candidates)
                items = []
                for address, name in devices:
                    address_key = address.upper()
                    items.append(dict(address=address, name=name, active=address_key in connected, paired=address_key in paired))
            self.emit({'event': 'connectivity', 'kind': kind, 'busy': False, 'powered': powered, 'items': items, 'error': ''})
        except (ValueError, OSError):
            import sys
            self.emit({'event': 'connectivity', 'kind': kind, 'busy': False, 'error': str(sys.exc_info()[1])})
        finally:
            self.lock.release()
