"""Task-aware home data: recent files and recent games, from local sources only."""
import os
import pathlib
import time
import urllib.parse
import xml.etree.ElementTree as ET

XBEL = pathlib.Path.home() / '.local/share/recently-used.xbel'
MAX_BYTES = 2_000_000
# Names that look like private or throwaway files stay out of the home screen.
HIDDEN_PARTS = ('/.', '/tmp/', '/.cache/', '/.local/share/Trash/')
KIND_BY_PREFIX = (('image/', 'image'), ('video/', 'movie'), ('audio/', 'music_note'), ('text/', 'description'),
                  ('application/pdf', 'picture_as_pdf'), ('application/', 'draft'))


def _timestamp(text):
    """Return epoch seconds for an ISO 8601 UTC time, or 0 when it is not valid."""
    try:
        return int(time.mktime(time.strptime(text[:19], '%Y-%m-%dT%H:%M:%S')) - time.timezone)
    except (TypeError, ValueError):
        return 0


def icon_for(mime):
    """Choose a Material symbol name for a MIME type."""
    for prefix, name in KIND_BY_PREFIX:
        if mime.startswith(prefix):
            return name
    return 'draft'


def parse_xbel(text, limit=12, exists=os.path.exists):
    """Return the newest existing local files from XBEL text. The newest file is first."""
    if not isinstance(text, str) or len(text) > MAX_BYTES or '<!ENTITY' in text:
        return []
    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        return []
    files, seen = [], set()
    for mark in root.iter('bookmark'):
        parsed = urllib.parse.urlparse(mark.get('href', ''))
        if parsed.scheme != 'file':
            continue
        path = urllib.parse.unquote(parsed.path)
        if not path.startswith('/') or path in seen or any(part in path for part in HIDDEN_PARTS):
            continue
        seen.add(path)
        mime = ''
        for node in mark.iter():
            if node.tag.endswith('mime-type'):
                mime = node.get('type', '')
        # The visited time is the best sign of what the user did last.
        when = max(_timestamp(mark.get('visited')), _timestamp(mark.get('modified')))
        if exists(path):
            files.append({'kind': 'file', 'title': os.path.basename(path), 'path': path, 'mime': mime,
                          'icon': icon_for(mime), 'when': when, 'folder': os.path.dirname(path)})
    files.sort(key=lambda item: -item['when'])
    return files[:limit]


def recent_files(limit=12, path=XBEL):
    """Read the recently-used file list. A missing or large file gives an empty list."""
    try:
        if path.stat().st_size > MAX_BYTES:
            return []
        return parse_xbel(path.read_text(errors='replace'), limit)
    except OSError:
        return []


def recent_games(games, limit=4, now=None, horizon=60 * 86400):
    """Return games played in the last horizon seconds, newest first. Launch commands are never included."""
    now = now or time.time()
    result = []
    for game in games if isinstance(games, list) else []:
        when = int(game.get('lastPlayed') or 0)
        if when and now - when <= horizon and game.get('id') and game.get('title'):
            result.append({'kind': 'game', 'id': game['id'], 'title': game['title'], 'source': game.get('source', ''),
                           'cover': game.get('cover', ''), 'when': when})
    result.sort(key=lambda item: -item['when'])
    return result[:limit]


def relative(when, now=None):
    """Return a short phrase such as 5 min ago."""
    now = now or time.time()
    delta = max(0, int(now - when))
    if not when:
        return ''
    if delta < 90:
        return 'Just now'
    if delta < 3600:
        return f'{delta // 60} min ago'
    if delta < 86400:
        return f'{delta // 3600} h ago'
    return f'{delta // 86400} d ago'


def snapshot(games=None, files=None, limit=8):
    """Build the payload for the home section. Link devices and media are added by the shell."""
    files = recent_files(limit) if files is None else files
    now = time.time()
    items = files[:limit]
    for item in items:
        item['ago'] = relative(item['when'], now)
    played = recent_games(games or [], 3, now)
    for item in played:
        item['ago'] = relative(item['when'], now)
    return {'files': items, 'games': played}
