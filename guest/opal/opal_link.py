"""Opal Link: a KDE Connect protocol (version 8) device, with Opal-only extensions for handoff and session continuity.

Talks to the KDE Connect Android app and to other Opal devices on the local network. Standard library plus openssl
for the first certificate. A KDE Connect identity and its trusted devices can be imported read-only, so existing
pairings keep working. Trust is pinned per device certificate.
"""
import base64, hashlib, json, os, pathlib, re, shutil, socket, ssl, subprocess, threading, time, uuid

PORT = 1716
PORT_RANGE = range(1716, 1765)
PROTOCOL = 8
DEVICE_ID = re.compile(r'[A-Za-z0-9_]{32,38}')
APP_ID = re.compile(r'[A-Za-z0-9._-]{1,200}')
MAX_LINE = 1 << 20
MAX_DOWNLOAD = 4 << 30
CAPABILITIES = ['kdeconnect.ping', 'kdeconnect.battery', 'kdeconnect.clipboard', 'kdeconnect.clipboard.connect',
                'kdeconnect.notification', 'kdeconnect.share.request', 'kdeconnect.findmyphone.request', 'opal.handoff', 'opal.session']


def packet(kind, body):
    return (json.dumps({'id': int(time.time() * 1000), 'type': kind, 'body': body}) + '\n').encode()


def certificate_cn(der):
    """Common name from a DER certificate. The subject follows the issuer; for self-signed certificates both match."""
    names = []
    index = 0
    marker = b'\x06\x03\x55\x04\x03'
    while True:
        index = der.find(marker, index)
        if index < 0: break
        tag_at = index + len(marker)
        if tag_at + 2 > len(der): break
        length = der[tag_at + 1]
        names.append(der[tag_at + 2:tag_at + 2 + length].decode('utf-8', 'replace'))
        index = tag_at
    return names[-1] if names else ''


def pem_to_der(text):
    body = ''.join(line for line in text.replace('\\n', '\n').splitlines() if line and 'CERTIFICATE' not in line)
    return base64.b64decode(body)


class Device:
    def __init__(self, ident):
        self.id = ident
        self.name, self.type, self.address = '', 'unknown', ''
        self.link, self.paired, self.pair_requested, self.pair_pending = None, False, False, False
        self.battery, self.charging, self.opal, self.session = -1, False, False, {}
        self.last_seen = 0

    def view(self):
        return {'id': self.id, 'name': self.name or self.id[:8], 'type': self.type, 'reachable': self.link is not None, 'paired': self.paired,
                'pairRequested': self.pair_requested, 'pairPending': self.pair_pending, 'battery': self.battery, 'charging': self.charging,
                'opal': self.opal, 'session': self.session}


class Link:
    """One TLS connection to a device. Lines are JSON packets."""
    def __init__(self, service, device, tls):
        self.service, self.device, self.tls = service, device, tls
        self.lock = threading.Lock()
        self.alive = True

    def send(self, kind, body):
        try:
            with self.lock: self.tls.sendall(packet(kind, body))
            return True
        except OSError:
            self.close(); return False

    def close(self):
        if not self.alive: return
        self.alive = False
        try: self.tls.close()
        except OSError: pass
        self.service.dropped(self)

    def run(self):
        buffer = b''
        try:
            while self.alive:
                chunk = self.tls.recv(65536)
                if not chunk: break
                buffer += chunk
                if len(buffer) > MAX_LINE: break
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    if line.strip():
                        try: self.service.received(self, json.loads(line))
                        except (ValueError, KeyError, TypeError): pass
        except OSError:
            pass
        self.close()


class LinkService:
    def __init__(self, emit, state_dir, name=None, device_type='desktop', runner=subprocess.run, discovery_port=PORT, kde_dir=None):
        self.emit, self.state = emit, pathlib.Path(state_dir)
        self.name = name or socket.gethostname()
        self.device_type, self.runner = device_type, runner
        self.discovery_port = discovery_port
        # Port that unicast replies and broadcasts go to; tests use separate ports on one host.
        self.reply_port = discovery_port
        self.kde_dir = pathlib.Path(kde_dir) if kde_dir else pathlib.Path.home() / '.config/kdeconnect'
        self.devices, self.lock = {}, threading.RLock()
        self.running, self.tcp_port, self.status = False, None, 'off'
        self.last_clipboard = ''
        self.handlers = {}
        self.udp = self.server = None

    # ---------- Identity and trust ----------
    @property
    def cert_path(self): return self.state / 'certificate.pem'
    @property
    def key_path(self): return self.state / 'privateKey.pem'
    @property
    def trust_path(self): return self.state / 'trusted.json'

    def ensure_identity(self, import_kde=True):
        self.state.mkdir(parents=True, exist_ok=True)
        os.chmod(self.state, 0o700)
        if not self.cert_path.exists() or not self.key_path.exists():
            if not (import_kde and self.import_kde_connect()):
                self.generate_identity()
        self.der = ssl.PEM_cert_to_DER_cert(self.cert_path.read_text())
        self.device_id = certificate_cn(self.der)
        if not DEVICE_ID.fullmatch(self.device_id): raise ValueError('Opal Link certificate has an invalid device id')
        self.trusted = self.load_trust()

    def generate_identity(self):
        ident = uuid.uuid4().hex
        result = self.runner(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1', '-nodes', '-days', '3650',
                              '-subj', '/O=KDE/OU=Kde connect/CN=' + ident, '-keyout', str(self.key_path), '-out', str(self.cert_path)],
                             capture_output=True, text=True, timeout=30)
        if result.returncode: raise OSError('Could not create the Opal Link certificate: ' + (result.stderr or '').strip()[:200])
        os.chmod(self.key_path, 0o600)

    def import_kde_connect(self):
        """Reuse a KDE Connect identity and its trusted devices. KDE Connect's files are only read."""
        cert, key = self.kde_dir / 'certificate.pem', self.kde_dir / 'privateKey.pem'
        if not cert.is_file() or not key.is_file(): return False
        try:
            shutil.copyfile(cert, self.cert_path); shutil.copyfile(key, self.key_path); os.chmod(self.key_path, 0o600)
            trusted, current = {}, None
            for line in (self.kde_dir / 'trusted_devices').read_text().splitlines():
                line = line.strip()
                if line.startswith('[') and line.endswith(']'): current = line[1:-1]; trusted[current] = {}
                elif current and '=' in line:
                    key_name, value = line.split('=', 1); trusted[current][key_name] = value
            store = {}
            for ident, values in trusted.items():
                if DEVICE_ID.fullmatch(ident) and values.get('certificate'):
                    try: der = pem_to_der(values['certificate']) if 'BEGIN' in values['certificate'] else base64.b64decode(values['certificate'])
                    except (ValueError, base64.binascii.Error): continue
                    store[ident] = {'name': values.get('name', ''), 'type': values.get('type', 'phone'), 'cert': base64.b64encode(der).decode()}
            self.write_trust(store)
            return True
        except OSError:
            return False

    def load_trust(self):
        try: data = json.loads(self.trust_path.read_text())
        except (OSError, ValueError): return {}
        return {k: v for k, v in data.items() if DEVICE_ID.fullmatch(k) and isinstance(v, dict) and v.get('cert')}

    def write_trust(self, store=None):
        store = self.trusted if store is None else store
        temp = self.trust_path.with_suffix('.tmp')
        temp.write_text(json.dumps(store)); os.chmod(temp, 0o600); temp.replace(self.trust_path)

    def identity(self):
        return {'deviceId': self.device_id, 'deviceName': self.name, 'deviceType': self.device_type, 'protocolVersion': PROTOCOL,
                'incomingCapabilities': CAPABILITIES, 'outgoingCapabilities': CAPABILITIES, 'tcpPort': self.tcp_port,
                # Opal extension: the certificate itself, so another Opal device can pin it before TLS.
                'opalCertificate': base64.b64encode(self.der).decode()}

    def context(self, server, peer_der=None):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER if server else ssl.PROTOCOL_TLS_CLIENT)
        context.load_cert_chain(str(self.cert_path), str(self.key_path))
        context.check_hostname = False
        if peer_der:
            # A known device: pin its exact certificate.
            context.verify_mode = ssl.CERT_REQUIRED
            context.verify_flags |= getattr(ssl, 'VERIFY_X509_PARTIAL_CHAIN', 0)
            context.load_verify_locations(cadata=peer_der)
        else:
            context.verify_mode = ssl.CERT_NONE
        return context

    # ---------- Lifecycle ----------
    def start(self, import_kde=True):
        self.ensure_identity(import_kde)
        try:
            self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.udp.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            self.udp.bind(('', self.discovery_port))
        except OSError:
            self.status = 'busy'; self.publish(); return False
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        for port in PORT_RANGE:
            try: self.server.bind(('', port)); self.tcp_port = port; break
            except OSError: continue
        if self.tcp_port is None:
            self.status = 'busy'; self.udp.close(); self.publish(); return False
        self.server.listen(8)
        self.running, self.status = True, 'running'
        for ident, info in self.trusted.items():
            device = self.device(ident); device.paired = True; device.name = info.get('name', ''); device.type = info.get('type', 'phone')
        for target in (self.discovery_loop, self.accept_loop, self.announce_loop): threading.Thread(target=target, daemon=True).start()
        self.publish()
        return True

    def stop(self):
        self.running = False
        for sock in (self.udp, self.server):
            try: sock and sock.close()
            except OSError: pass
        with self.lock:
            links = [d.link for d in self.devices.values() if d.link]
        for link in links: link.close()
        self.status = 'off'; self.publish()

    def device(self, ident):
        with self.lock:
            if ident not in self.devices: self.devices[ident] = Device(ident)
            return self.devices[ident]

    def publish(self):
        with self.lock: devices = [d.view() for d in sorted(self.devices.values(), key=lambda d: (not d.paired, d.name.lower()))]
        self.emit({'event': 'link', 'status': self.status, 'id': getattr(self, 'device_id', ''), 'name': self.name, 'devices': devices})

    # ---------- Discovery ----------
    def announce(self, address='<broadcast>', port=None):
        try: self.udp.sendto(packet('kdeconnect.identity', self.identity()), (address, port or self.reply_port))
        except OSError: pass

    def announce_loop(self):
        while self.running:
            self.announce(); time.sleep(60)

    def discovery_loop(self):
        while self.running:
            try: data, (address, _) = self.udp.recvfrom(65536)
            except OSError: break
            try: identity = json.loads(data)['body']
            except (ValueError, KeyError, TypeError): continue
            ident = identity.get('deviceId', '')
            if ident == self.device_id or not DEVICE_ID.fullmatch(str(ident)): continue
            device = self.device(ident)
            device.address, device.last_seen = address, time.time()
            self.remember(device, identity)
            if device.link: continue
            pinned = self.peer_certificate(ident, identity)
            # Paired devices, or unknown Opal devices with a higher id than ours, get a connection from us.
            if pinned and isinstance(identity.get('tcpPort'), int) and (device.paired or self.device_id > ident):
                threading.Thread(target=self.connect, args=(device, address, identity['tcpPort'], pinned), daemon=True).start()
            elif not device.paired:
                # Unknown device: answer directly, so it connects to us and we can read its certificate as the TLS client.
                self.announce(address)
            self.publish()

    def peer_certificate(self, ident, identity):
        """The certificate to pin: the trusted one, else an Opal identity's own certificate when its name matches."""
        if ident in self.trusted: return base64.b64decode(self.trusted[ident]['cert'])
        try: der = base64.b64decode(identity.get('opalCertificate') or '', validate=True)
        except (ValueError, TypeError): return None
        return der if der and certificate_cn(der) == ident else None

    def remember(self, device, identity):
        device.name = str(identity.get('deviceName', device.name))[:64]
        device.type = str(identity.get('deviceType', device.type))[:16]
        device.opal = 'opal.session' in (identity.get('incomingCapabilities') or [])

    def connect(self, device, address, port, pinned):
        """We open TCP, send our identity, then act as the TLS server with the peer certificate pinned."""
        try:
            raw = socket.create_connection((address, port), timeout=8)
            raw.sendall(packet('kdeconnect.identity', self.identity()))
            tls = self.context(True, ssl.DER_cert_to_PEM_cert(pinned)).wrap_socket(raw, server_side=True)
            self.established(tls, device.id, address)
        except (OSError, ssl.SSLError, KeyError, ValueError):
            pass

    def accept_loop(self):
        while self.running:
            try: raw, (address, _) = self.server.accept()
            except OSError: break
            threading.Thread(target=self.accepted, args=(raw, address), daemon=True).start()

    def accepted(self, raw, address):
        """Incoming TCP: read the plain identity, then act as the TLS client."""
        try:
            raw.settimeout(8)
            line = b''
            while not line.endswith(b'\n') and len(line) < 65536:
                chunk = raw.recv(1)
                if not chunk: raise OSError('closed')
                line += chunk
            identity = json.loads(line)['body']
            ident = identity['deviceId']
            if not DEVICE_ID.fullmatch(str(ident)) or ident == self.device_id: raise ValueError('bad id')
            pinned = self.peer_certificate(ident, identity)
            tls = self.context(False, ssl.DER_cert_to_PEM_cert(pinned) if pinned else None).wrap_socket(raw, server_side=False)
            self.established(tls, ident, address)
        except (OSError, ssl.SSLError, ValueError, KeyError, TypeError):
            try: raw.close()
            except OSError: pass

    def established(self, tls, ident, address):
        der = tls.getpeercert(binary_form=True) or b''
        if certificate_cn(der) != ident: tls.close(); return
        known = self.trusted.get(ident)
        if known and base64.b64decode(known['cert']) != der: tls.close(); return
        tls.settimeout(None)
        # Protocol 8: identities are exchanged again inside TLS.
        tls.sendall(packet('kdeconnect.identity', self.identity()))
        buffer = b''
        tls.settimeout(8)
        while b'\n' not in buffer and len(buffer) < 65536:
            chunk = tls.recv(4096)
            if not chunk: tls.close(); return
            buffer += chunk
        tls.settimeout(None)
        first, rest = buffer.split(b'\n', 1)
        identity = json.loads(first).get('body', {})
        if identity.get('deviceId') != ident: tls.close(); return
        device = self.device(ident)
        with self.lock:
            if device.link and device.link.alive: tls.close(); return
            device.address, device.peer_der = address, der
            self.remember(device, identity)
            link = Link(self, device, tls)
            device.link = link
        self.publish()
        if rest.strip():
            for line in rest.split(b'\n'):
                if line.strip():
                    try: self.received(link, json.loads(line))
                    except ValueError: pass
        if device.paired: self.on_paired_link(device)
        link.run()

    def dropped(self, link):
        with self.lock:
            if link.device.link is link: link.device.link = None
        self.publish()

    # ---------- Pairing ----------
    def pair(self, ident):
        device = self.devices.get(ident)
        if not device or not device.link: return False
        device.pair_pending = True; self.publish()
        return device.link.send('kdeconnect.pair', {'pair': True, 'timestamp': int(time.time())})

    def accept(self, ident, yes=True):
        device = self.devices.get(ident)
        if not device or not device.link or not device.pair_requested: return False
        device.pair_requested = False
        device.link.send('kdeconnect.pair', {'pair': bool(yes)})
        if yes: self.trust(device)
        self.publish(); return True

    def unpair(self, ident):
        device = self.devices.get(ident)
        if device and device.link: device.link.send('kdeconnect.pair', {'pair': False})
        self.trusted.pop(ident, None); self.write_trust()
        if device: device.paired = device.pair_pending = device.pair_requested = False
        self.publish()

    def trust(self, device):
        der = getattr(device, 'peer_der', None)
        if not der: return
        self.trusted[device.id] = {'name': device.name, 'type': device.type, 'cert': base64.b64encode(der).decode()}
        self.write_trust()
        device.paired, device.pair_pending = True, False
        self.on_paired_link(device)

    def verification_key(self, ident):
        """Short code both screens can show while pairing: a hash of both certificates."""
        device = self.devices.get(ident)
        der = getattr(device, 'peer_der', b'') if device else b''
        return hashlib.sha256(b''.join(sorted([self.der, der]))).hexdigest()[:8].upper()

    def on_paired_link(self, device):
        handler = self.handlers.get('paired')
        if handler: handler(device)

    # ---------- Packets ----------
    def received(self, link, message):
        device, kind, body = link.device, message.get('type'), message.get('body') or {}
        if kind == 'kdeconnect.pair':
            if body.get('pair') is True:
                if device.pair_pending: self.trust(device)
                elif not device.paired:
                    stamp = body.get('timestamp')
                    if isinstance(stamp, int) and abs(stamp - time.time()) > 1800: link.send('kdeconnect.pair', {'pair': False}); return
                    device.pair_requested = True
                    self.emit({'event': 'linkPairRequest', 'id': device.id, 'name': device.name, 'code': self.verification_key(device.id)})
            else:
                device.pair_pending = device.pair_requested = False
                if device.paired: self.trusted.pop(device.id, None); self.write_trust(); device.paired = False
            self.publish(); return
        if not device.paired: return
        handler = self.handlers.get(kind)
        if kind == 'kdeconnect.battery':
            device.battery = int(body.get('currentCharge', -1)) if isinstance(body.get('currentCharge'), int) else -1
            device.charging = bool(body.get('isCharging')); self.publish()
        elif kind == 'opal.session' and isinstance(body, dict):
            device.session = {k: str(body.get(k, ''))[:200] for k in ('app', 'appName', 'title', 'track', 'artist')}
            device.session['playing'] = bool(body.get('playing')); self.publish()
        if handler: handler(device, body)

    def send(self, ident, kind, body):
        device = self.devices.get(ident)
        return bool(device and device.paired and device.link and device.link.send(kind, body))

    def broadcast(self, kind, body, opal_only=False):
        with self.lock: targets = [d for d in self.devices.values() if d.paired and d.link and (d.opal or not opal_only)]
        for device in targets: device.link.send(kind, body)

    # ---------- Payload download (file share) ----------
    def download(self, device, body, folder):
        info, size, name = body.get('payloadTransferInfo') or {}, body.get('payloadSize'), os.path.basename(str(body.get('filename') or 'file'))
        port = info.get('port')
        if not isinstance(port, int) or not isinstance(size, int) or not 0 <= size <= MAX_DOWNLOAD or not name or name.startswith('.'): return None
        folder = pathlib.Path(folder); folder.mkdir(parents=True, exist_ok=True)
        target = folder / name
        stem, suffix, counter = target.stem, target.suffix, 1
        while target.exists(): target = folder / ('%s (%d)%s' % (stem, counter, suffix)); counter += 1
        try:
            raw = socket.create_connection((device.address, port), timeout=10)
            tls = self.context(False, ssl.DER_cert_to_PEM_cert(base64.b64decode(self.trusted[device.id]['cert']))).wrap_socket(raw, server_side=False)
            received = 0
            with open(target, 'wb') as out:
                while received < size:
                    chunk = tls.recv(min(1 << 16, size - received))
                    if not chunk: break
                    out.write(chunk); received += len(chunk)
            tls.close()
            if received != size: target.unlink(missing_ok=True); return None
            return target
        except (OSError, ssl.SSLError, KeyError):
            target.unlink(missing_ok=True); return None
