#!/usr/bin/env python3
"""Text-only, in-memory clipboard history. Never reads/writes a cliphist database."""
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import uuid

MAX_BYTES = 32768
MAX_ITEMS = 20
LINK_PATTERN = re.compile(r'https?://\S+\Z')


def capture():
    """Invoked by wl-paste; copied data is stdin, never a shell argument."""
    if os.environ.get('CLIPBOARD_STATE', 'data') != 'data':
        return
    try:
        types = subprocess.check_output(['wl-paste', '--list-types'],
                                        stderr=subprocess.DEVNULL, timeout=1).decode().lower()
        if any(hint in types for hint in ('passwordmanagerhint', 'keepass', 'sensitive', 'secret')):
            return
        raw = sys.stdin.buffer.read(MAX_BYTES + 1)
        if not raw or len(raw) > MAX_BYTES or b'\0' in raw:
            return
        text = raw.decode('utf-8')
        if text.strip():
            print(json.dumps({'text': text}), flush=True)
    except (OSError, UnicodeError, subprocess.SubprocessError):
        return


class ClipboardHistory:
    def __init__(self, emit):
        self.emit = emit
        self.items = []
        self._by_text = {}
        self._by_id = {}
        self.paused = False
        self.available = False
        self.detail = 'Waiting for clipboard service'
        self.lock = threading.RLock()
        self.wake = threading.Event()
        self.stopped = threading.Event()
        self.process = None

    def publish(self):
        with self.lock:
            self.emit({'event': 'clipboard', 'items': [i.copy() for i in self.items],
                       'paused': self.paused, 'available': self.available,
                       'detail': self.detail, 'limit': MAX_ITEMS})

    def add(self, text, sensitive=False):
        if not isinstance(text, str) or sensitive or '\0' in text:
            return False
        stripped = text.strip()
        if not stripped:
            return False
        encoded = text.encode('utf-8')
        if len(encoded) > MAX_BYTES:
            return False
        with self.lock:
            if self.paused:
                return False
            existing = self._by_text.get(text)
            if existing is not None:
                self.items.remove(existing)
                del self._by_id[existing['id']]
            entry = {'id': existing['id'] if existing else uuid.uuid4().hex,
                     'text': text, 'chars': len(text), 'lines': text.count('\n') + 1,
                     'kind': 'Link' if LINK_PATTERN.fullmatch(stripped) else
                             'Snippet' if '\n' in text else 'Text',
                     'captured': int(time.time() * 1000)}
            self.items.insert(0, entry)
            self._by_text[text] = entry
            self._by_id[entry['id']] = entry
            while len(self.items) > MAX_ITEMS:
                removed = self.items.pop()
                del self._by_text[removed['text']]
                del self._by_id[removed['id']]
            self.publish()
        return True

    def delete(self, identity):
        with self.lock:
            entry = self._by_id.pop(identity, None)
            if entry is not None:
                self.items.remove(entry)
                del self._by_text[entry['text']]
            self.publish()

    def clear(self):
        # Only this process's history. Never clear the system clipboard or other managers.
        with self.lock:
            self.items.clear()
            self._by_text.clear()
            self._by_id.clear()
            self.publish()

    def copy(self, identity):
        with self.lock:
            entry = self._by_id.get(identity)
            text = entry['text'] if entry else None
        success = False
        if text is not None and shutil.which('wl-copy'):
            try:
                subprocess.run(['wl-copy', '--type', 'text/plain;charset=utf-8'],
                               input=text.encode('utf-8'), check=True,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
                success = True
            except (OSError, subprocess.SubprocessError):
                pass
        self.emit({'event': 'clipboardCopied', 'id': identity, 'success': success})
        return success

    def terminate_watcher(self):
        with self.lock:
            process = self.process
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

    def set_paused(self, value):
        with self.lock:
            self.paused = bool(value)
            self.publish()
        if value:
            self.terminate_watcher()
        self.wake.set()

    def stop(self):
        self.stopped.set()
        self.terminate_watcher()
        self.wake.set()

    def watch(self):
        if not os.environ.get('WAYLAND_DISPLAY') or not shutil.which('wl-paste'):
            self.detail = 'Requires Wayland data-control and wl-clipboard'
            self.publish()
            return
        while not self.stopped.is_set():
            self.wake.clear()
            if self.paused:
                self.wake.wait()
                continue
            process = None
            try:
                with self.lock:
                    # Serialize spawn with pause, so a paused watcher cannot restart.
                    if self.paused or self.stopped.is_set():
                        continue
                    process = subprocess.Popen(
                        ['wl-paste', '--no-newline', '--type', 'text', '--watch', sys.executable,
                         os.path.abspath(__file__), '--capture'],
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                        text=True, start_new_session=True)
                    self.process = process
                    self.available = True
                    self.detail = 'Text only · session memory · 20 entries'
                    self.publish()
                for line in process.stdout:
                    if self.stopped.is_set():
                        break
                    try:
                        self.add(json.loads(line).get('text'))
                    except (ValueError, TypeError):
                        continue
                process.wait(timeout=2)
            except (OSError, subprocess.SubprocessError):
                if process is not None:
                    try:
                        os.killpg(process.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
            finally:
                if process is not None:
                    if process.stdout:
                        process.stdout.close()
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                with self.lock:
                    self.process = None
                    if not self.paused and not self.stopped.is_set():
                        self.available = False
                        self.detail = 'Clipboard watching unavailable on this compositor'
                    self.publish()
            self.wake.wait(5)


if __name__ == '__main__' and '--capture' in sys.argv:
    capture()
