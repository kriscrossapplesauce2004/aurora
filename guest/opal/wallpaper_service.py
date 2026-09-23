"""Local wallpaper validation and shell-only Matugen colors (no template hooks)."""
import json
import os
import pathlib
import re
import shutil
import stat
import subprocess
import tempfile
from collections import deque
from urllib.parse import unquote, urlparse

ROLES = ('primary', 'on_primary', 'primary_container', 'on_primary_container',
         'secondary', 'tertiary', 'background', 'on_surface', 'on_surface_variant',
         'surface_container', 'surface_container_high', 'outline_variant')
SCHEMES = ('scheme-tonal-spot', 'scheme-expressive', 'scheme-vibrant', 'scheme-neutral')
IMAGE_SUFFIXES = ('.png', '.jpg', '.jpeg', '.webp', '.bmp')
DEFAULTS = dict(wallpaperPath='', wallpaperFit='crop', wallpaperDim=0.15,
                desktopWidgets=True, dynamicColors=False, dynamicPalette={},
                colorScheme='scheme-tonal-spot')

def local_image(value):
    if not isinstance(value, str) or not value or len(value) > 4096:
        raise ValueError('Choose a local image path.')
    if value.startswith('file:'):
        url = urlparse(value)
        if url.netloc not in ('', 'localhost'):
            raise ValueError('Only local wallpapers are supported.')
        value = unquote(url.path)
    path = pathlib.Path(value).expanduser()
    if not path.is_absolute():
        raise ValueError('Wallpaper must be an existing absolute path (or ~/path).')
    try:
        metadata = path.stat()
    except OSError:
        raise ValueError('Wallpaper must be an existing absolute path (or ~/path).') from None
    if not stat.S_ISREG(metadata.st_mode):
        raise ValueError('Wallpaper must be an existing absolute path (or ~/path).')
    if path.suffix.lower() not in IMAGE_SUFFIXES:
        raise ValueError('Choose a PNG, JPEG, WebP or BMP image.')
    if metadata.st_size > 64 * 1024 * 1024:
        raise ValueError('Choose an image smaller than 64 MiB.')
    return path.resolve()

def image_library(folder='', current='', home=None):
    """Bounded, local-only discovery; no recursive symlink traversal or downloads."""
    home = pathlib.Path(home) if home else pathlib.Path.home()
    if folder:
        if not isinstance(folder, str) or len(folder) > 4096:
            raise ValueError('Choose a local folder.')
        url = urlparse(folder)
        if url.scheme and url.scheme != 'file' or url.netloc not in ('', 'localhost'):
            raise ValueError('Choose a local folder.')
        root = pathlib.Path(unquote(url.path) if url.scheme else folder).expanduser()
        if not root.is_absolute() or not root.is_dir():
            raise ValueError('Folder is unavailable.')
        roots = [root]
    else:
        roots = [home/'Pictures/Wallpapers', home/'Pictures', home/'wallpapers', pathlib.Path('/usr/share/backgrounds'), pathlib.Path('/usr/share/wallpapers')]
    result, seen, scanned = [], set(), 0
    if current:
        try:
            p = local_image(current)
            result.append({'path':p.as_uri(), 'name':p.stem}); seen.add(p)
        except (ValueError, OSError): pass
    queue = deque((p, 0) for p in roots)
    while queue and len(result) < 120 and scanned < 3000:
        directory, depth = queue.popleft()
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    scanned += 1
                    if scanned > 3000 or len(result) >= 120: break
                    if entry.name.startswith('.') or entry.is_symlink(): continue
                    if entry.is_dir(follow_symlinks=False):
                        if depth < 3: queue.append((pathlib.Path(entry.path), depth+1))
                        continue
                    if not entry.name.lower().endswith(IMAGE_SUFFIXES): continue
                    try: p = local_image(entry.path)
                    except (ValueError, OSError): continue
                    if p not in seen:
                        seen.add(p)
                        name=p.stem
                        if p.parent.name in ('images','images_dark') and p.parent.parent.name=='contents':
                            name=p.parents[2].name+(' · dark' if p.parent.name=='images_dark' else '')+' · '+p.stem
                        result.append({'path':p.as_uri(), 'name':name})
        except OSError: continue
    return sorted(result, key=lambda item:item['name'].casefold())


def browse_images(value='', home=None):
    """One directory for the in-shell browser; no external file chooser."""
    home = pathlib.Path(home) if home else pathlib.Path.home()
    if not value:
        root = home/'Pictures' if (home/'Pictures').is_dir() else home
    else:
        if not isinstance(value,str) or len(value)>4096:
            raise ValueError('Choose a local folder.')
        url=urlparse(value)
        if url.scheme not in ('','file') or url.netloc not in ('','localhost'):
            raise ValueError('Only local folders are supported.')
        root=pathlib.Path(unquote(url.path) if url.scheme else value).expanduser()
        if not root.is_absolute(): raise ValueError('Enter an absolute folder path.')
    if not root.is_dir(): raise ValueError('Folder is unavailable.')
    root=root.resolve()
    folders,images=[],[]
    try:
        with os.scandir(root) as entries:
            for count,entry in enumerate(entries):
                if count>=3000:break
                if entry.name.startswith('.') or entry.is_symlink():continue
                try:
                    if entry.is_dir(follow_symlinks=False):
                        p=pathlib.Path(entry.path)
                        if len(folders)<200:folders.append({'path':p.as_uri(),'name':p.name,'directory':True})
                    elif len(images)<120 and entry.name.lower().endswith(IMAGE_SUFFIXES):
                        image=local_image(entry.path)
                        images.append({'path':image.as_uri(),'name':image.stem,'directory':False})
                except (ValueError,OSError):continue
    except OSError as error:
        raise ValueError('Cannot read this folder.') from error
    return {'folder':root.as_uri(),'parent':root.parent.as_uri() if root.parent!=root else '',
            'folders':sorted(folders,key=lambda p:p['name'].casefold()),
            'items':sorted(images,key=lambda p:p['name'].casefold())}


def normalize_colors(data):
    colors = data['colors']
    result = {}
    for mode in ('light', 'dark'):
        result[mode] = {}
        for role in ROLES:
            # Matugen 4 and older JSON formats.
            value = colors[role][mode] if role in colors else colors[mode][role]
            if isinstance(value, dict):
                value = value.get('color')
            if not isinstance(value, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', value):
                raise ValueError('Matugen returned an invalid palette.')
            result[mode][role] = value
    return result

def generate(path, scheme):
    if scheme not in SCHEMES:
        raise ValueError('Unsupported color scheme.')
    if not shutil.which('matugen'):
        raise ValueError('Install Matugen to generate wallpaper colors. Your wallpaper still works without it.')
    # Isolated config plus dry-run: never run user hooks, reload apps or set wallpaper.
    # Matugen v4 rejects an empty config, so write the smallest valid one (no templates).
    with tempfile.NamedTemporaryFile(suffix='.toml', mode='w') as config:
        config.write('[config]\nversion_check = false\n\n[templates]\n')
        config.flush()
        proc = subprocess.run(['matugen', 'image', '--config', config.name, '--dry-run',
                               '--json', 'hex', '--type', scheme, '--source-color-index', '0',
                               str(path)], capture_output=True, text=True, timeout=30, check=True)
    return normalize_colors(json.loads(proc.stdout))

def valid_preference(key, value):
    return (key in ('desktopWidgets', 'dynamicColors') and type(value) is bool
            or key == 'wallpaperFit' and value in ('crop', 'fit')
            or key == 'wallpaperDim' and type(value) in (int, float) and 0 <= value <= .8
            or key == 'colorScheme' and value in SCHEMES)
