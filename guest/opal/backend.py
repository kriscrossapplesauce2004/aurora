#!/usr/bin/env python3
"""Opal's optional Linux adapters. JSON-lines only; no shell-evaluated user input."""
import sys, os, json, subprocess, threading, time, pathlib, shutil, glob, select, struct, math, ast, operator, re, urllib.parse
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
from wallpaper_service import DEFAULTS as WALLPAPER_DEFAULTS, local_image, generate, valid_preference, image_library, browse_images
HOME = pathlib.Path.home()
STORE = HOME / '.local/state/aurora-opal/preferences.json'
lock = threading.Lock()
prefs_lock = threading.Lock()
JSON_SEPARATORS = (',', ':')
system_osk = None
# Quick Settings tile identifiers. The shell can reorder or hide these, but not add unknown ones.
QUICK_TILE_IDS = ('wifi','bluetooth','dnd','awake','theme','saver','mic','keyboard','motion','capture','autohide','clipboard','focus','convergence')
QUICK_TILE_DEFAULT = ('wifi','bluetooth','dnd','awake','theme','saver','mic','keyboard')
def emit(data):
    with lock:
        print(json.dumps(data), flush=True)
@lru_cache(maxsize=64)
def command_available(name):
    return bool(shutil.which(name))

def run(*args, timeout=1.4):
    if not command_available(args[0]): return ''
    try: return subprocess.check_output(args, stderr=subprocess.DEVNULL, timeout=timeout).decode().strip()
    except (OSError, subprocess.SubprocessError): return ''
def spawn(args, env=None):
    try: subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True, env=env)
    except OSError: emit({'event':'message', 'text':f'{args[0]} is not installed'})
BAR_STYLES = ('islands','dock','split','edge')
SHEET_SECTION_IDS = ('sliders','tiles','media','notifications','calendar','monitor','clipboard','focus','battery','devices')
SHEET_SECTION_DEFAULT = ('sliders','tiles','media','notifications')
PHONE_WIDGETS = ('glance','stack','media','calendar','battery','focus')
def valid_phone_home(value):
    """Phone home layout: up to 8 pages of widgets and items; items are app ids or small folders."""
    def app_id(v): return isinstance(v,str) and 0<len(v)<300
    def item(v):
        if app_id(v): return True
        return isinstance(v,dict) and set(v)=={'folder','apps'} and isinstance(v['folder'],str) and len(v['folder'])<=40 and isinstance(v['apps'],list) and 0<len(v['apps'])<=24 and all(map(app_id,v['apps']))
    if not isinstance(value,dict) or set(value)!={'pages'} or not isinstance(value['pages'],list) or not 0<len(value['pages'])<=8: return False
    for page in value['pages']:
        if not isinstance(page,dict) or set(page)!={'widgets','items'}: return False
        widgets,items=page['widgets'],page['items']
        if not isinstance(widgets,list) or len(widgets)>4 or len(set(widgets))!=len(widgets) or not all(w in PHONE_WIDGETS for w in widgets): return False
        if not isinstance(items,list) or len(items)>48 or not all(map(item,items)): return False
    return True

import system_tools
import theme_export
TIME = re.compile(r'([01]\d|2[0-3]):[0-5]\d')
PROFILE_KEYS = ('barStyle','iconStyle','quickTiles','sheetSections','light','palette','dynamicColors','dynamicPalette','colorScheme','glass','wallpaperPath','wallpaperFit','wallpaperDim','mode','taskbarCenter','taskbarLabels','taskbarClockDate','taskbarAutoHide','reduceMotion','desktopWidgets')
def valid_schedules(value):
    """Night light, dark mode and Do not disturb schedules: sun times or custom times."""
    if not isinstance(value,dict) or not set(value)<={'nightLight','darkMode','dnd'}: return False
    for item in value.values():
        if not isinstance(item,dict) or not set(item)<={'enabled','mode','from','to','temperature'}: return False
        if type(item.get('enabled',False)) is not bool or item.get('mode','custom') not in ('sun','custom'): return False
        if any(k in item and not (isinstance(item[k],str) and TIME.fullmatch(item[k])) for k in ('from','to')): return False
        if 'temperature' in item and (type(item['temperature']) is not int or not 2500<=item['temperature']<=6500): return False
    return True
def valid_dock_choices(value):
    if not isinstance(value,dict) or len(value)>16: return False
    for name,c in value.items():
        if not isinstance(name,str) or not re.fullmatch(r'[A-Za-z0-9._-]{1,64}',name) or not isinstance(c,dict) or set(c)-{'mode','phoneMode','resolution','scale'}: return False
        if c.get('mode') not in ('desktop','console','phone','mirror') or c.get('phoneMode') not in ('trackpad','screen','panel'): return False
        if not isinstance(c.get('resolution',''),str) or len(c.get('resolution',''))>40 or type(c.get('scale',1)) not in (int,float) or not .5<=c.get('scale',1)<=4: return False
    return True
def valid_theme_sync(value):
    if not isinstance(value,dict) or set(value)-{'font','iconTheme','cursorTheme','cursorSize','fontSize'}: return False
    text=lambda v: isinstance(v,str) and len(v)<=120 and not any(ch in v for ch in '\n\r\0')
    return all(text(v) for k,v in value.items() if k in ('font','iconTheme','cursorTheme')) and all(type(value[k])==int and lo<=value[k]<=hi for k,lo,hi in (('cursorSize',16,128),('fontSize',6,32)) if k in value)
def valid_profiles(value):
    if not isinstance(value,dict) or len(value)>10: return False
    return all(isinstance(name,str) and 0<len(name)<=40 and isinstance(saved,dict) and set(saved)<=set(PROFILE_KEYS) for name,saved in value.items())

def load():
    base = {'mode':'auto', 'palette':0, 'light':False, 'dnd':False, 'glass':0.78, 'favorites':[], 'recent':[], 'wallpaper':0, 'pinsConfigured':False, 'taskbarAutoHide':False, 'taskbarLabels':True, 'phoneButtons':False, 'controllerLayout':'standard'}
    base['displayModes'] = {}
    base['phoneDisplay'] = ''
    base['taskbarOrder'] = []
    base['reduceMotion'] = False
    base['taskbarCenter'] = False
    base['taskbarClockDate'] = True
    base['barStyle'] = 'islands'
    base['iconStyle'] = 'raw'
    base['gamePins'] = []
    base['autoRotate'] = True
    base['themeExport'] = []
    base['themeSync'] = {}
    base['linkEnabled'] = False
    base['linkClipboard'] = True
    base['linkSession'] = True
    base['linkImportKde'] = True
    base['schedules'] = {}
    base['profiles'] = {}
    base['sheetSections'] = list(SHEET_SECTION_DEFAULT)
    base['quickTiles'] = list(QUICK_TILE_DEFAULT)
    base['phoneRows'] = 5
    base.update(WALLPAPER_DEFAULTS)
    try: base.update(json.loads(STORE.read_text()))
    except (OSError, ValueError): pass
    return base
prefs = load()
night_light = system_tools.NightLight()
GREETER_CACHE = pathlib.Path(os.environ.get('OPAL_GREETER_CACHE', '/var/cache/opal-greeter'))
GREETER_KEYS = ('light','palette','dynamicColors','dynamicPalette','colorScheme','wallpaperDim','reduceMotion')
def sync_greeter_theme(values=None, cache=None):
    """Copy theme roles and the wallpaper into the greeter cache when the installer made it writable for this user."""
    values = prefs if values is None else values
    cache = GREETER_CACHE if cache is None else cache
    if not cache.is_dir() or not os.access(cache, os.W_OK): return False
    theme = {key: values[key] for key in GREETER_KEYS if key in values}
    source = str(values.get('wallpaperPath') or '')
    if source.startswith('file://'):
        path = pathlib.Path(urllib.parse.unquote(source[7:]))
        if path.is_file() and path.suffix.lower() in ('.png','.jpg','.jpeg','.webp'):
            target = cache / ('wallpaper' + path.suffix.lower())
            try:
                if not target.exists() or target.stat().st_size != path.stat().st_size or target.stat().st_mtime < path.stat().st_mtime:
                    temp = target.with_suffix('.tmp'); shutil.copyfile(path, temp); temp.chmod(0o644); temp.replace(target)
                theme['wallpaperPath'] = target.as_uri()
            except OSError:
                pass
    temp = cache / 'theme.tmp'
    try:
        temp.write_text(json.dumps(theme, separators=JSON_SEPARATORS)); temp.chmod(0o644); temp.replace(cache / 'theme.json')
    except OSError:
        return False
    return True

def save():
    STORE.parent.mkdir(parents=True, exist_ok=True)
    temp = STORE.with_suffix('.tmp')
    temp.write_text(json.dumps(prefs, separators=JSON_SEPARATORS))
    temp.replace(STORE)
    emit({'event':'preferences', 'data':prefs.copy()})
    if system_osk: system_osk.refresh(prefs)
    threading.Thread(target=sync_greeter_theme,args=(prefs.copy(),),daemon=True).start()
    if (prefs.get('linkEnabled') is True)!=(LINK['service'] is not None): threading.Thread(target=link_apply,daemon=True).start()

def exit_with_parent():
    """Ask Linux to send SIGTERM to this child when the backend dies, so a reload never leaves an orphan keyboard."""
    try:
        import ctypes, signal as signals
        ctypes.CDLL('libc.so.6',use_errno=True).prctl(1,signals.SIGTERM,0,0,0)
    except (OSError,AttributeError):
        pass

VIRTUAL_KEYBOARD_WORDS=('virtual','uinput','ydotool','input-remapper','keyd','kanata','power button','sleep button','video bus','consumer control','system control','hotkeys','wmi')

def physical_keyboard_present(devices=None):
    """Report a real hardware keyboard: a kernel keyboard handler with LED support that is not a known virtual device."""
    try:
        text=devices if devices is not None else pathlib.Path('/proc/bus/input/devices').read_text(errors='replace')
    except OSError:
        return False
    for block in text.split('\n\n'):
        name=re.search(r'^N: Name="([^"]*)"',block,re.M)
        handlers=re.search(r'^H: Handlers=(.*)$',block,re.M)
        events=re.search(r'^B: EV=([0-9a-f]+)',block,re.M)
        if not (name and handlers and events):continue
        if 'kbd' not in handlers.group(1).split():continue
        # EV bit 17 is LED: full keyboards have lock lights, media buttons and remotes do not.
        if not int(events.group(1),16)&(1<<17):continue
        if any(word in name.group(1).lower() for word in VIRTUAL_KEYBOARD_WORDS):continue
        return True
    return False

def keyboard_command():
    """Return the system keyboard argument list and its name. Borealis is preferred; Squeekboard is the fallback."""
    override=os.environ.get('OPAL_KEYBOARD','')
    candidates=[override] if override else []
    candidates+=[shutil.which('opal-keyboard') or '',str(HOME/'.local'/'bin'/'opal-keyboard')]
    for path in candidates:
        if path and os.access(path,os.X_OK) and pathlib.Path(path).is_file():
            # Borealis reads the Opal preference file itself, so it needs no theme wrapper.
            return [path],'Borealis'
    squeekboard=shutil.which('squeekboard')
    launcher=pathlib.Path(__file__).with_name('osk_theme.py')
    if squeekboard and launcher.is_file():
        return [sys.executable,str(launcher),'--preferences',str(STORE),'--',squeekboard],'Squeekboard'
    return None,'No system keyboard is installed (Borealis or Squeekboard)'

class SystemOsk:
    def __init__(self):
        self.process = None
        self.generation = 0
        self.signature = ''
        self.name = 'System keyboard'
        self.hardware = False
        self.explicit = False
        self.lock = threading.Lock()

    def theme_signature(self, values):
        subset={key:values.get(key) for key in ('light','palette','dynamicColors','dynamicPalette','colorScheme')}
        return json.dumps(subset, sort_keys=True, separators=JSON_SEPARATORS)

    def publish(self, available, running, detail='', visible=False):
        emit({'event':'systemOsk','available':bool(available),'running':bool(running),'visible':bool(visible),'detail':detail})

    def visible(self):
        commands=[]
        if command_available('gdbus'):
            commands.append(['gdbus','call','--session','--dest','sm.puri.OSK0','--object-path','/sm/puri/OSK0','--method','org.freedesktop.DBus.Properties.Get','sm.puri.OSK0','Visible'])
        if command_available('busctl'):
            commands.append(['busctl','--user','get-property','sm.puri.OSK0','/sm/puri/OSK0','sm.puri.OSK0','Visible'])
        for command in commands:
            try:
                reply=subprocess.check_output(command,stderr=subprocess.DEVNULL,timeout=.8,text=True).strip().lower()
            except (OSError,subprocess.SubprocessError):
                continue
            if 'true' in reply:return True
            if 'false' in reply:return False
        return None

    def wait_ready(self, process, generation):
        for _ in range(40):
            with self.lock:
                if generation!=self.generation or process is not self.process:return
            if process.poll() is not None:return
            visible=self.visible()
            if visible is not None:
                self.publish(True,True,'Wayland input method',visible)
                return
            time.sleep(.1)
        self.publish(True,False,self.name+' did not register its session D-Bus service')

    def set_visible(self, visible):
        if not self.process or self.process.poll() is not None:
            if not visible:return True
            self.start(explicit=True)
        deadline=time.monotonic()+2.5
        while time.monotonic()<deadline:
            if self.visible() is not None:break
            time.sleep(.05)
        commands=[]
        value='true' if visible else 'false'
        if command_available('gdbus'):
            commands.append(['gdbus','call','--session','--dest','sm.puri.OSK0','--object-path','/sm/puri/OSK0','--method','sm.puri.OSK0.SetVisible',value])
        if command_available('busctl'):
            commands.append(['busctl','--user','call','sm.puri.OSK0','/sm/puri/OSK0','sm.puri.OSK0','SetVisible','b',value])
        for command in commands:
            try:
                subprocess.run(command,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=1,check=True)
                self.publish(True,True,'Wayland input method',visible)
                return True
            except (OSError,subprocess.SubprocessError):
                continue
        self.publish(bool(keyboard_command()[0]),False,'System keyboard control is unavailable')
        return False

    def toggle(self):
        visible=self.visible()
        return self.set_visible(not bool(visible))

    def auto(self):
        """Run the keyboard only without a hardware keyboard, and follow keyboard hotplug."""
        threading.Thread(target=self.follow_hardware,daemon=True).start()

    def follow_hardware(self):
        last=None
        while True:
            present=physical_keyboard_present()
            if present!=last:
                last=present
                self.hardware=present
                with self.lock: running=bool(self.process and self.process.poll() is None)
                if present and running and not self.explicit:
                    self.stop()
                    self.publish(True,False,'Hidden while a hardware keyboard is connected')
                elif not present and not running:
                    self.start()
                elif present and not running:
                    self.publish(bool(keyboard_command()[0]),False,'Hidden while a hardware keyboard is connected')
            time.sleep(3)

    def start(self, explicit=False):
        self.explicit=explicit
        if os.environ.get('OPAL_SYSTEM_OSK','1') in ('0','false','no'):
            self.publish(False,False,'System keyboard disabled by OPAL_SYSTEM_OSK')
            return
        command,name=keyboard_command()
        if not command:
            self.publish(False,False,name)
            return
        # With a hardware keyboard, Borealis only appears on request, never on text focus.
        if name=='Borealis' and physical_keyboard_present():
            command=command+['--manual']
        with self.lock:
            if self.process and self.process.poll() is None: return
            self.generation+=1
            generation=self.generation
            self.name=name
            try:
                self.process=subprocess.Popen(command,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True,preexec_fn=exit_with_parent)
            except OSError as error:
                self.process=None
                self.publish(True,False,str(error))
                return
            process=self.process
            self.signature=self.theme_signature(prefs)
        self.publish(True,False,'Starting Wayland input method')
        threading.Thread(target=self.wait_ready,args=(process,generation),daemon=True).start()
        threading.Thread(target=self.watch,args=(process,generation),daemon=True).start()

    def watch(self, process, generation):
        code=process.wait()
        with self.lock:
            if generation!=self.generation or process is not self.process: return
            self.process=None
        detail=self.name+' exited' if code==0 else f'{self.name} exited with status {code}'
        self.publish(True,False,detail)

    def stop(self):
        with self.lock:
            self.generation+=1
            process=self.process
            self.process=None
        if not process or process.poll() is not None: return
        process.terminate()
        try: process.wait(timeout=1.5)
        except subprocess.TimeoutExpired:
            process.kill()
            try: process.wait(timeout=.5)
            except subprocess.TimeoutExpired: pass

    def restart(self):
        self.stop()
        self.start()

    def refresh(self, values):
        signature=self.theme_signature(values)
        if signature==self.signature: return
        self.signature=signature
        with self.lock: running=bool(self.process and self.process.poll() is None)
        # Borealis follows theme changes itself; only the Squeekboard wrapper needs a restart.
        if running and self.name!='Borealis': threading.Thread(target=self.restart,daemon=True).start()

def settings(which):
    choices = {
        'network': [['nm-connection-editor'], ['systemsettings','kcm_networkmanagement'], ['kitty','-e','nmtui']],
        'bluetooth': [['blueman-manager'], ['systemsettings','kcm_bluetooth']],
        'audio': [['pavucontrol'], ['systemsettings','kcm_pulseaudio']],
        'display': [['systemsettings','kcm_kscreen']],
        'files': [['xdg-open',str(HOME)]],
        'terminal': [['kitty'], ['foot'], ['alacritty']],
        'browser': [['xdg-open','https://www.google.com']],
        'steam': [['steam','-gamepadui']],
        'lock': [['loginctl','lock-session'], ['hyprlock']],
    }
    for cmd in choices.get(which, []):
        if shutil.which(cmd[0]): spawn(cmd); return
    emit({'event':'message','text':'No compatible application installed'})

CALCULATOR_OPS = {ast.Add:operator.add, ast.Sub:operator.sub, ast.Mult:operator.mul, ast.Div:operator.truediv, ast.Mod:operator.mod, ast.Pow:operator.pow}
def calculate(expr):
    # Deliberately tiny calculator, never Python eval or shell execution.
    def visit(n):
        if isinstance(n,ast.Constant) and type(n.value) in (int,float): return n.value
        if isinstance(n,ast.UnaryOp) and isinstance(n.op,(ast.UAdd,ast.USub)): return visit(n.operand) * (-1 if isinstance(n.op,ast.USub) else 1)
        if isinstance(n,ast.BinOp) and type(n.op) in CALCULATOR_OPS:
            a,b=visit(n.left),visit(n.right)
            if abs(a)>1e15 or abs(b)>1e15 or isinstance(n.op,ast.Pow) and abs(b)>12: raise ValueError()
            return CALCULATOR_OPS[type(n.op)](a,b)
        raise ValueError()
    try:
        if len(expr)>100: raise ValueError()
        value=visit(ast.parse(expr,mode='eval').body)
        if isinstance(value,complex) or not math.isfinite(value) or abs(value)>1e18: raise ValueError()
        return format(value,'.12g')
    except Exception: return ''

from clipboard_service import ClipboardHistory
def clipboard_emit(data):
    emit(data)
    # Opal Link: share new local clipboard text with paired devices.
    if data.get('event')=='clipboard' and data.get('items'):
        link_clipboard(data['items'][0].get('text',''))
clipboard = ClipboardHistory(clipboard_emit)
from connectivity import Connectivity
connectivity = Connectivity(emit)
from hypr_actions import HyprActions
from convergence_policy import PREF_KEYS as CONVERGE_KEYS
from power_status import (connected_bluetooth_devices, cpu_governor,
                          merge_batteries, parse_bluetooth_battery,
                          parse_upower_batteries, primary_battery,
                          system_batteries)
hypr_actions = HyprActions()
import phone_commands, assistant
GAMES_LISTED = []


def publish_wallpapers(c):
    try:
        if c.get('browse'):
            data=browse_images(c.get('folder',''))
        else:
            data={'items':image_library(c.get('folder',''), prefs.get('wallpaperPath','')), 'folders':[], 'folder':'', 'parent':''}
        emit({'event':'wallpapers','request':c.get('request'), **data, 'error':''})
    except (ValueError, OSError) as error:
        emit({'event':'wallpapers','request':c.get('request'), 'items':[], 'error':str(error)})


def commands():
    for line in sys.stdin:
        try:
            c=json.loads(line); action=c.get('action')
            if action=='preference':
                key=c.get('key'); value=c.get('value')
                valid = key=='controllerLayout' and value in ('standard','nintendo') or key=='barStyle' and value in BAR_STYLES or key=='iconStyle' and value in ('raw','squircle','themed') or key=='mode' and value in ('auto','desktop','phone','console') or key in ('palette','wallpaper') and type(value)==int and 0<=value<=3 or key in ('light','dnd','taskbarAutoHide','taskbarLabels','phoneButtons','reduceMotion','taskbarCenter','taskbarClockDate','autoRotate','onboarded','linkEnabled','linkClipboard','linkSession','linkImportKde','quickAccessGuide') and type(value)==bool or key=='glass' and type(value) in (int,float) and .45<=value<=1
                valid = valid or key=='themeExport' and isinstance(value,list) and all(v in system_tools.TARGETS for v in value) and len(set(value))==len(value)
                valid = valid or key=='themeSync' and valid_theme_sync(value)
                valid = valid or key=='schedules' and valid_schedules(value)
                valid = valid or key=='profiles' and valid_profiles(value)
                valid = valid or key=='dockChoices' and valid_dock_choices(value)
                valid = valid or key=='phoneHome' and valid_phone_home(value)
                valid = valid or key=='gamePins' and isinstance(value,list) and len(value)<=256 and all(isinstance(v,str) and 0<len(v)<300 for v in value) and len(set(value))==len(value)
                valid = valid or key=='sheetSections' and isinstance(value,list) and len(value)<=len(SHEET_SECTION_IDS) and all(v in SHEET_SECTION_IDS for v in value) and len(set(value))==len(value)
                valid = valid or key=='quickTiles' and isinstance(value,list) and len(value)<=len(QUICK_TILE_IDS) and all(v in QUICK_TILE_IDS for v in value) and len(set(value))==len(value)
                valid = valid or key=='phoneRows' and type(value)==int and 4<=value<=7
                valid = valid or valid_preference(key, value)
                valid = valid or phone_commands.valid_preference(key, value)
                valid = valid or key=='taskbarOrder' and isinstance(value,list) and len(value)<=128 and all(isinstance(v,str) and 0<len(v)<300 for v in value) and len(set(value))==len(value)
                valid = valid or key=='phoneDisplay' and isinstance(value,str) and 0<len(value)<=128 and all(ch.isalnum() or ch in '_.:-' for ch in value)
                valid = valid or key=='assistantMode' and value in ('ask','auto')
                valid = valid or key=='displayModes' and isinstance(value,dict) and len(value)<=32 and all(isinstance(k,str) and 0<len(k)<=200 and v in ('desktop','phone') for k,v in value.items())
                valid = valid or key in CONVERGE_KEYS and type(value)==bool
                if valid:
                    with prefs_lock: prefs[key]=value; save()
            elif action=='display-layouts':
                from display_layouts import publish
                runtime=os.environ.get('XDG_RUNTIME_DIR')
                if runtime and publish(runtime,c.get('mode'),c.get('displays')) and os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') and shutil.which('hyprctl'):
                    subprocess.run(['hyprctl','reload','config-only'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
            elif action=='wallpaper-list':
                threading.Thread(target=publish_wallpapers,args=(c,),daemon=True).start()
            elif action=='wallpaper':
                try:
                    path = local_image(c.get('path')) if c.get('path') else None
                    extra={}
                    for key in ('wallpaperFit','wallpaperDim','wallpaper'):
                        if key not in c: continue
                        value=c[key]
                        if not (type(value) is int and 0<=value<=3 if key=='wallpaper' else valid_preference(key,value)):
                            raise ValueError('Invalid wallpaper preview settings.')
                        extra[key]=value
                    with prefs_lock:
                        prefs.update(extra)
                        prefs['wallpaperPath'] = path.as_uri() if path else ''
                        save()
                    emit({'event':'message','text':'Wallpaper updated' if path else 'Plain background restored'})
                except (ValueError, OSError) as error:
                    emit({'event':'message','text':str(error)})
            elif action=='matugen':
                emit({'event':'themeBusy','busy':True})
                try:
                    path = local_image(prefs.get('wallpaperPath'))
                    palette = generate(path, prefs.get('colorScheme','scheme-tonal-spot'))
                    with prefs_lock:
                        prefs['dynamicPalette'] = palette
                        prefs['dynamicColors'] = True
                        save()
                    emit({'event':'message','text':'Wallpaper colors applied · light and dark palettes ready'})
                except Exception as error:
                    emit({'event':'message','text':str(error) if isinstance(error, ValueError) else 'Matugen could not read this image or generate colors. Previous colors kept.'})
                finally:
                    emit({'event':'themeBusy','busy':False})
            elif action in ('pin','recent'):
                app=c.get('id','')
                if isinstance(app,str) and 0<len(app)<300:
                    with prefs_lock:
                        key='favorites' if action=='pin' else 'recent'
                        items=list(prefs[key])
                        if action=='pin' and not prefs.get('pinsConfigured'):
                            defaults=c.get('initial',[])
                            if isinstance(defaults,list): items=[i for i in defaults[:24] if isinstance(i,str) and len(i)<300]
                            prefs['pinsConfigured']=True
                        if app in items: items.remove(app)
                        elif action=='pin': items.append(app)
                        if action=='recent': items.insert(0,app)
                        prefs[key]=items[:24]; save()
            elif action=='rotate':
                try: hypr_actions.rotate(c.get('output'),c.get('transform'))
                except (ValueError,OSError,subprocess.SubprocessError) as error: emit({'event':'message','text':str(error)})
            elif action=='close-window':
                try: hypr_actions.close(c.get('address'))
                except (ValueError,OSError,subprocess.SubprocessError) as error: emit({'event':'message','text':str(error)[:160]})
            elif action=='workspace-empty':
                try: hypr_actions.workspace_empty()
                except (ValueError,OSError,subprocess.SubprocessError) as error: emit({'event':'message','text':str(error)[:160]})
            elif action in ('focus-window','workspace','move-window'):
                try:
                    if action=='focus-window':hypr_actions.focus(c.get('address'))
                    elif action=='move-window':hypr_actions.move(c.get('address'),c.get('number'),c.get('follow') is True)
                    else:hypr_actions.workspace(c.get('number'))
                except (ValueError,OSError,subprocess.SubprocessError) as error:
                    emit({'event':'message','text':str(error)})
            elif phone_commands.handle(c,emit,GAMES_LISTED): pass
            elif assistant.handle(c,emit): pass
            elif action=='connectivity': connectivity.request(c)
            elif action=='settings': settings(c.get('which'))
            elif action=='claude-ask' and isinstance(c.get('text'),str) and 0<len(c['text'])<8000:
                threading.Thread(target=ask_claude,args=(c['text'],int(c.get('id') or 0)),daemon=True).start()
            elif action=='claude-stop': stop_claude()
            elif action=='theme-export':
                def export(c=c):
                    options=dict(c.get('options') if isinstance(c.get('options'),dict) else {},**{k:v for k,v in (prefs.get('themeSync') or {}).items() if v not in ('',None)})
                    try: emit({'event':'themeExport','done':system_tools.export_theme(c.get('colors'),[t for t in (c.get('targets') or []) if t in system_tools.TARGETS],options=options)})
                    except (ValueError,OSError) as error: emit({'event':'message','text':'Theme export failed: '+str(error)})
                theme_export.DEBOUNCE.submit(lambda: threading.Thread(target=export,daemon=True).start())
            elif action=='theme-export-remove':
                try: system_tools.remove_export([t for t in (c.get('targets') or []) if t in system_tools.TARGETS])
                except OSError as error: emit({'event':'message','text':str(error)})
            elif action=='theme-discover': threading.Thread(target=lambda:emit({'event':'themeChoices','data':theme_export.discover()}),daemon=True).start()
            elif action=='updates': threading.Thread(target=lambda:emit(dict(system_tools.updates(),event='updates')),daemon=True).start()
            elif action=='health': emit(dict(system_tools.health(),event='health'))
            elif action=='system-update':
                command=system_tools.update_command()
                if command: spawn(command)
                else: emit({'event':'message','text':'No terminal found to run the update'})
            elif action=='monitors': threading.Thread(target=lambda:emit({'event':'monitors','data':system_tools.monitors()}),daemon=True).start()
            elif action=='monitors-apply':
                try: system_tools.apply_monitors(c.get('displays'),c.get('keep') is True); emit({'event':'monitorsApplied','keep':c.get('keep') is True})
                except (ValueError,OSError) as error: emit({'event':'message','text':str(error)})
                threading.Thread(target=lambda:(time.sleep(1),emit({'event':'monitors','data':system_tools.monitors()})),daemon=True).start()
            elif action=='night-light':
                if not night_light.set(c.get('enabled') is True,c.get('temperature') if type(c.get('temperature')) is int else 4000): emit({'event':'message','text':'Night light needs hyprsunset'})
            elif action=='sun-times':
                where=system_tools.zone_coordinates(); times=system_tools.sun_times(*where) if where else None
                emit({'event':'sun','sunrise':times[0] if times else '07:00','sunset':times[1] if times else '19:00','estimated':times is None})
            elif action in ('pointer','pointer-start','pointer-stop'): pointer_command(c)
            elif isinstance(action,str) and action.startswith('link-'):
                threading.Thread(target=link_command,args=(c,),daemon=True).start()
            elif action=='game-library': threading.Thread(target=publish_games,daemon=True).start()
            elif action=='game-launch': launch_game(c.get('id'))
            elif action in ('perf-get','perf-set','perf-copy','game-detail','game-uninstall'):
                import game_perf
                threading.Thread(target=game_perf.dispatch,args=(c,emit,spawn),daemon=True).start()
            elif action=='system-osk' and c.get('verb') in ('show','hide','toggle'):
                if not system_osk:
                    emit({'event':'systemOsk','available':False,'running':False,'visible':False,'detail':'System keyboard is not initialized'})
                elif c.get('verb')=='toggle': system_osk.toggle()
                else: system_osk.set_visible(c.get('verb')=='show')
            elif action=='volume': run('wpctl','set-volume','-l','1','@DEFAULT_AUDIO_SINK@',str(max(0,min(100,int(c['value']))))+'%')
            elif action=='mute': run('wpctl','set-mute','@DEFAULT_AUDIO_SINK@','toggle')
            elif action=='mic': run('wpctl','set-mute','@DEFAULT_AUDIO_SOURCE@','toggle')
            elif action=='brightness': run('brightnessctl','set',str(max(1,min(100,int(c['value']))))+'%')
            elif action=='wifi': run('nmcli','radio','wifi','off' if c.get('enabled') else 'on')
            elif action=='bluetooth': run('bluetoothctl','power','off' if c.get('enabled') else 'on')
            elif action=='media' and c.get('verb') in ('play-pause','next','previous'):
                if command_available('playerctl'): run('playerctl',c['verb'])
                else: run('aurora-media-action',c['verb'])
            elif action=='profile' and c.get('value') in ('power-saver','balanced','performance'): run('powerprofilesctl','set',c['value'])
            elif action=='screenshot':
                time.sleep(.5)
                folder=HOME/'Pictures/Screenshots'; folder.mkdir(parents=True,exist_ok=True)
                dest=str(folder/time.strftime('Opal-%Y%m%d-%H%M%S.png'))
                if shutil.which('grim'):
                    try:
                        subprocess.run(['grim',dest],check=True,timeout=5)
                        emit({'event':'message','text':'Screenshot saved to Pictures/Screenshots'})
                    except Exception: emit({'event':'message','text':'Screenshot failed'})
            elif action=='power' and c.get('verb')=='suspend':
                emit({'event':'message','text':'Suspend is unavailable while Android owns the power lifecycle'})
            elif action=='power' and c.get('verb') in ('reboot','poweroff'):
                spawn(['aurora-signal',c['verb']])
            elif action=='power' and c.get('verb')=='logout':
                # Aurora: the Android side owns the session; this file asks its control channel to end it.
                pathlib.Path('/mnt/aurora-control/exit').touch()
            elif action=='calculate': emit({'event':'calculation','query':c.get('text',''),'result':calculate(c.get('text',''))})
            elif action=='clipboard':
                if shutil.which('wl-copy'): subprocess.run(['wl-copy'],input=str(c.get('text','')).encode('utf-8'),timeout=2)
            elif action=='clipboard-list': clipboard.publish()
            elif action=='clipboard-copy': clipboard.copy(c.get('id',''))
            elif action=='clipboard-delete': clipboard.delete(c.get('id',''))
            elif action=='clipboard-clear': clipboard.clear()
            elif action=='clipboard-pause' and type(c.get('paused')) is bool: clipboard.set_paused(c['paused'])
            elif action=='web': spawn(['xdg-open','https://www.google.com/search?q='+__import__('urllib.parse',fromlist=['quote']).quote(str(c.get('text','')))])
        except Exception as e: emit({'event':'message','text':'That action could not be completed'})

last_cpu=None
status_workers=ThreadPoolExecutor(max_workers=8, thread_name_prefix='opal-status')
status_cache={}
status_cache_lock=threading.Lock()
connected_battery_cache={'signature':(), 'time':0, 'items':[]}
connected_battery_cache_lock=threading.Lock()

def status_probe(specs):
    futures={}
    values={}
    now=time.monotonic()
    with status_cache_lock:
        for key,args,ttl in specs:
            cached=status_cache.get(key)
            if ttl and cached and now-cached[0] < ttl:
                values[key]=cached[1]
            else:
                futures[key]=status_workers.submit(run,*args)
    for key,future in futures.items():
        try: value=future.result()
        except Exception: value=''
        values[key]=value
        for spec_key,_,ttl in specs:
            if spec_key==key and ttl:
                with status_cache_lock: status_cache[key]=(time.monotonic(),value)
                break
    return values


def connected_bluetooth_batteries(rows):
    """Read connected Bluetooth battery levels at a bounded refresh rate."""
    devices = connected_bluetooth_devices(rows)
    signature = tuple(address for address, _ in devices)
    now = time.monotonic()
    with connected_battery_cache_lock:
        cached = connected_battery_cache
        if cached['signature'] == signature and now-cached['time'] < 20:
            return cached['items']
    futures = [(address, name, status_workers.submit(run, 'bluetoothctl', 'info', address)) for address, name in devices[:8]]
    batteries = []
    for address, name, future in futures:
        try:
            battery = parse_bluetooth_battery(address, name, future.result())
        except Exception:
            battery = None
        if battery:
            batteries.append(battery)
    with connected_battery_cache_lock:
        connected_battery_cache.update(signature=signature, time=now, items=batteries)
    return batteries

def status():
    global last_cpu
    # Compositor fields arrive independently from hypr_events, never from this poll.
    s={'volume':0,'muted':False,'network':'Offline','wifi':False,'bluetooth':False,'track':'','artist':'','art':'','playing':False,'battery':-1,'batteries':[],'charging':False,'brightness':-1,'cpu':0,'memory':0,'profile':'','governor':'','uptime':''}
    values=status_probe([
        ('volume',('wpctl','get-volume','@DEFAULT_AUDIO_SINK@'),0),
        ('audioOutput',('wpctl','inspect','@DEFAULT_AUDIO_SINK@'),10),
        ('mic',('wpctl','get-volume','@DEFAULT_AUDIO_SOURCE@'),0),
        ('network',('nmcli','-t','-f','NAME,TYPE','connection','show','--active'),3),
        ('wifi',('nmcli','radio','wifi'),3),
        ('bluetooth',('bluetoothctl','show'),5),
        ('media',('playerctl','metadata','--format','{{title}}\n{{artist}}\n{{mpris:artUrl}}\n{{status}}'),0),
        ('profile',('powerprofilesctl','get'),10),
        ('upower',('upower','-d'),20),
        ('connectedBluetooth',('bluetoothctl','devices','Connected'),20),
    ])
    v=values['volume']
    try: s['volume']=round(float(v.split()[1])*100)
    except (ValueError,IndexError): pass
    s['muted']='MUTED' in v
    description=re.search(r'node\.description\s*=\s*"([^"]+)"',values['audioOutput'])
    s['audioOutput']=description.group(1) if description else ''
    s['micMuted']='MUTED' in values['mic']
    n=values['network']
    s['network']=next((l.rsplit(':',1)[0] for l in n.splitlines() if not l.endswith(':loopback')),'Offline')
    s['wifi']=values['wifi']=='enabled'
    s['bluetooth']='Powered: yes' in values['bluetooth']
    meta=values['media'].splitlines()
    if meta:
        for i,k in enumerate(('track','artist','art')):
            if len(meta)>i: s[k]=meta[i]
        s['playing']=len(meta)>3 and meta[3]=='Playing'
    batteries=merge_batteries(system_batteries(), parse_upower_batteries(values['upower']), connected_bluetooth_batteries(values['connectedBluetooth']))
    s['batteries']=batteries
    s['battery'],s['charging']=primary_battery(batteries)
    for b in glob.glob('/sys/class/backlight/*'):
        try: s['brightness']=round(int(pathlib.Path(b,'brightness').read_text())/int(pathlib.Path(b,'max_brightness').read_text())*100)
        except (OSError,ValueError,ZeroDivisionError): pass
    try:
        cpu=list(map(int,pathlib.Path('/proc/stat').read_text().splitlines()[0].split()[1:8])); total=sum(cpu); idle=cpu[3]+cpu[4]
        if last_cpu and total>last_cpu[0]: s['cpu']=round(100*(1-(idle-last_cpu[1])/(total-last_cpu[0])))
        last_cpu=(total,idle)
        mem={l.split(':')[0]:int(l.split()[1]) for l in pathlib.Path('/proc/meminfo').read_text().splitlines()}
        s['memory']=round(100*(1-mem['MemAvailable']/mem['MemTotal']))
        hrs=int(float(pathlib.Path('/proc/uptime').read_text().split()[0]))//3600
        s['uptime']=str(hrs)+'h'
    except (OSError,ValueError,KeyError): pass
    s['profile']=values['profile']
    s['governor']=cpu_governor()
    return s

def library_art():
    """Index existing local Steam artwork. Never download assets."""
    result={}
    bases=[HOME/'.local/share/Steam/appcache/librarycache', HOME/'.steam/steam/appcache/librarycache']
    seen=set()
    for base in bases:
        try:
            resolved=base.resolve()
            if resolved in seen or not base.is_dir(): continue
            seen.add(resolved)
            def add(path_entry, appid):
                if not appid.isdigit(): return
                name=path_entry.name.rsplit('.',1)[0].lower()
                kind='cover' if '600x900' in name or 'library_capsule' in name else 'hero' if 'library_hero' in name and 'blur' not in name else 'header' if 'library_header' in name else None
                if kind: result.setdefault(appid,{})[kind]=pathlib.Path(path_entry.path).resolve().as_uri()
            directories=[]
            with os.scandir(base) as entries:
                for entry in entries:
                    if entry.is_file():
                        add(entry, entry.name.split('_',1)[0])
                    elif entry.is_dir():
                        directories.append((entry, entry.name, 0))
            while directories:
                entry, appid, depth=directories.pop()
                try:
                    with os.scandir(entry.path) as entries:
                        for path_entry in entries:
                            if path_entry.is_file():
                                add(path_entry, appid)
                            elif depth < 1 and path_entry.is_dir():
                                directories.append((path_entry, appid, depth+1))
                except OSError:
                    continue
        except OSError: continue
    return result

GAMES = {}
GAME_STATE = HOME / '.local/state/opal/games.json'
def publish_games():
    """Index local games and art, remember launch commands by id, and send the list without them."""
    import game_library
    art = library_art()
    emit({'event':'libraryArt','data':art})
    try: played = json.loads(GAME_STATE.read_text())
    except (OSError, ValueError): played = {}
    games = game_library.library(art)
    GAMES.clear()
    listed = []
    for game in games:
        GAMES[game['id']] = game['launch']
        entry = {k: v for k, v in game.items() if k != 'launch'}
        entry['lastPlayed'] = max(int(entry.get('lastPlayed') or 0), int(played.get(game['id'], 0) if isinstance(played, dict) else 0))
        listed.append(entry)
    listed.sort(key=lambda g: (-g['lastPlayed'], g['title'].lower()))
    GAMES_LISTED[:]=listed
    emit({'event':'gameLibrary','data':listed})

def launch_game(game_id):
    """Launch only commands from the local index; the UI sends an id, never a command line."""
    command = GAMES.get(game_id) if isinstance(game_id, str) else None
    if not command: emit({'event':'message','text':'That game is no longer installed'}); return
    if not shutil.which(command[0]): emit({'event':'message','text':f'{command[0]} is not installed'}); return
    import game_perf
    spawn(command, game_perf.launch_env())
    try:
        try: played = json.loads(GAME_STATE.read_text())
        except (OSError, ValueError): played = {}
        if not isinstance(played, dict): played = {}
        played[game_id] = int(time.time())
        GAME_STATE.parent.mkdir(parents=True, exist_ok=True)
        temp = GAME_STATE.with_suffix('.tmp'); temp.write_text(json.dumps(played)); temp.replace(GAME_STATE)
    except OSError:
        pass

def controllers():
    from controller_mapping import device_maps, device_info, family, ranked_devices, NavigationState
    # Linux joystick API, read-only. Never grabs devices or injects global input.
    while True:
        f=None
        name=''
        profile='generic'
        for p in ranked_devices(glob.glob('/dev/input/js*')):
            candidate=None
            try:
                import fcntl
                candidate=open(p,'rb',buffering=0)
                buf=bytearray(128)
                fcntl.ioctl(candidate.fileno(), 0x80000000 | (128<<16) | (ord('j')<<8) | 0x13, buf)
                candidate_name=bytes(buf).split(b'\0',1)[0].decode(errors='replace')
                buttons=bytearray(1)
                fcntl.ioctl(candidate.fileno(), 0x80016a12, buttons)
                # Absolute pointer devices can expose js nodes too; they are not gamepads.
                if buttons[0]<6 or any(word in candidate_name.lower() for word in ('pointer','mouse','keyboard')):
                    candidate.close(); continue
                info=device_info(p)
                f=candidate; name=candidate_name; profile=family(info['name'] or candidate_name,info['vendor']); break
            except OSError:
                if candidate: candidate.close()
        emit({'event':'controller','connected':f is not None,'name':name})
        if f is None: time.sleep(5); continue
        try:
            button_codes,axis_codes=device_maps(f)
            # NavigationState owns hysteresis, repeat, trigger edges and the startup snapshot.
            navigation=NavigationState(button_codes,axis_codes,profile)
            while True:
                now=time.monotonic()
                if not select.select([f],[],[],navigation.wait(now))[0]:
                    for key in navigation.repeat(time.monotonic()): emit({'event':'navigation','key':key})
                    continue
                data=f.read(8)
                if len(data)!=8: break
                _,value,kind,number=struct.unpack('IhBB',data)
                for key in navigation.feed(kind,number,value,time.monotonic(),prefs.get('controllerLayout','standard')):
                    emit({'event':'navigation','key':key})
        except OSError: pass
        finally: f.close()
        time.sleep(2)

ORIENTATIONS = {'normal':0,'left-up':1,'bottom-up':2,'right-up':3}
def orientation_watch(process=None):
    """Follow iio-sensor-proxy through monitor-sensor and report accelerometer orientation. Quiet when there is no sensor."""
    if process is None:
        if not shutil.which('monitor-sensor'): return
        try: process=subprocess.Popen(['monitor-sensor','--accel'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
        except OSError: return
    for line in process.stdout:
        match=re.search(r'(?:orientation changed|orientation): ([a-z-]+)',line)
        if match and match.group(1) in ORIENTATIONS:
            emit({'event':'orientation','value':match.group(1),'transform':ORIENTATIONS[match.group(1)]})

CLAUDE = {'process': None, 'id': 0}
CLAUDE_PROMPT = ("You are answering inside Opal, the user's desktop shell launcher. Keep answers short and plain. "
                 "When the user asks to change the shell, use the opal tools.")
def ask_claude(text, request):
    """Stream an answer from the Claude Code CLI (the user's own subscription) with the Opal MCP server attached."""
    stop_claude()
    if not shutil.which('claude'): emit({'event':'claude','id':request,'text':'Claude Code is not installed.','done':True,'error':True}); return
    server = str(pathlib.Path(__file__).resolve().with_name('opal_mcp.py'))
    config = json.dumps({'mcpServers': {'opal': {'command': 'python3', 'args': [server]}}})
    command = ['claude', '-p', text, '--output-format', 'stream-json', '--verbose', '--include-partial-messages', '--no-session-persistence',
               '--strict-mcp-config', '--mcp-config', config, '--allowedTools', 'mcp__opal', '--append-system-prompt', CLAUDE_PROMPT]
    try: process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, text=True, cwd=str(HOME))
    except OSError as error: emit({'event':'claude','id':request,'text':str(error),'done':True,'error':True}); return
    CLAUDE['process'], CLAUDE['id'] = process, request
    answer, tools = '', []
    for line in process.stdout:
        try: event = json.loads(line)
        except ValueError: continue
        kind = event.get('type')
        if kind == 'stream_event':
            delta = event.get('event', {}).get('delta', {})
            if delta.get('type') == 'text_delta':
                answer += delta.get('text', '')
                emit({'event':'claude','id':request,'text':answer,'tools':tools,'done':False})
        elif kind == 'assistant':
            for block in event.get('message', {}).get('content', []):
                if block.get('type') == 'tool_use':
                    tools.append(block.get('name', '').replace('mcp__opal__', '').replace('_', ' '))
                    emit({'event':'claude','id':request,'text':answer,'tools':tools,'done':False})
        elif kind == 'result':
            final = event.get('result') if isinstance(event.get('result'), str) else answer
            emit({'event':'claude','id':request,'text':final or answer,'tools':tools,'done':True,'error':bool(event.get('is_error'))})
    process.wait()
    if CLAUDE['process'] is process: CLAUDE['process'] = None

def stop_claude():
    process = CLAUDE.get('process')
    if process and process.poll() is None:
        process.terminate()
    CLAUDE['process'] = None

def health_watch():
    """Check disks and temperatures every five minutes and updates every three hours; warn once per condition."""
    warned=set(); last_updates=0
    time.sleep(60)
    while True:
        report=system_tools.health(); emit(dict(report,event='health'))
        for disk in report['disks']:
            key='disk-'+disk['label']
            if disk['percent']>=92 and key not in warned: warned.add(key); emit({'event':'message','text':f"{disk['label']} disk is {disk['percent']}% full"})
            elif disk['percent']<88: warned.discard(key)
        if report['hottest']>=90 and 'hot' not in warned: warned.add('hot'); emit({'event':'message','text':f"Running hot: {report['hottest']}°C"})
        elif report['hottest']<80: warned.discard('hot')
        if time.time()-last_updates>3*3600:
            last_updates=time.time(); emit(dict(system_tools.updates(),event='updates'))
        time.sleep(300)

# ---------- Docked trackpad ----------
POINTER = {'process': None}
def pointer_command(c):
    """Forward validated trackpad commands to opal-pointer, which runs only while the phone is a trackpad."""
    action = c.get('action')
    process = POINTER['process']
    if action == 'pointer-stop':
        if process and process.poll() is None:
            try: process.stdin.close()
            except OSError: pass
            process.terminate()
        POINTER['process'] = None
        return
    if action == 'pointer-start':
        output = c.get('output')
        if not isinstance(output, str) or not re.fullmatch(r'[A-Za-z0-9._-]{1,64}', output): return
        if not process or process.poll() is not None:
            helper = shutil.which('opal-pointer') or str(HOME / '.local/bin/opal-pointer')
            if not os.path.exists(helper): emit({'event':'message','text':'The trackpad helper is not installed'}); return
            try: process = subprocess.Popen([helper], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, text=True, bufsize=1)
            except OSError as error: emit({'event':'message','text':str(error)}); return
            POINTER['process'] = process
        line = 'output ' + output
    elif action == 'pointer':
        op = c.get('op')
        if not process or process.poll() is not None: return
        if op in ('move', 'scroll'):
            dx, dy = c.get('dx'), c.get('dy')
            if type(dx) not in (int, float) or type(dy) not in (int, float) or abs(dx) > 4000 or abs(dy) > 4000: return
            line = '%s %.2f %.2f' % (op, dx, dy)
        elif op in ('down', 'up', 'click') and c.get('button') in ('left', 'right', 'middle'):
            line = op + ' ' + c['button']
        else:
            return
    else:
        return
    try: process.stdin.write(line + '\n'); process.stdin.flush()
    except (OSError, ValueError): POINTER['process'] = None

# ---------- Opal Link ----------
LINK = {'service': None}
def notify(title, body='', app='Opal Link', urgency='normal'):
    if shutil.which('notify-send'): spawn(['notify-send','-a',app,'-u',urgency,title[:200],body[:800]])

def link_clipboard(text):
    service=LINK['service']
    if not service or not prefs.get('linkClipboard',True) or not isinstance(text,str) or not text or len(text)>100000 or text==service.last_clipboard: return
    service.last_clipboard=text
    service.broadcast('kdeconnect.clipboard',{'content':text})

def link_copy(text):
    service=LINK['service']
    if service: service.last_clipboard=text
    try: subprocess.run(['wl-copy','--',text],timeout=5,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); return True
    except (OSError,subprocess.SubprocessError): return False

def link_open_url(url):
    if isinstance(url,str) and re.match(r'https?://',url) and len(url)<4000 and shutil.which('xdg-open'): spawn(['xdg-open',url]); return True
    return False

def link_handlers(service):
    seen=set()
    def ping(device, body): notify('Ping from '+device.name, str(body.get('message','')))
    def notification(device, body):
        if body.get('isCancel') or body.get('silent') or not body.get('title') and not body.get('text'): return
        key=(device.id,body.get('id'),body.get('title'),body.get('text'))
        if key in seen: return
        seen.add(key)
        if len(seen)>500: seen.clear()
        notify(str(body.get('title') or body.get('appName') or ''), str(body.get('text','')), app=str(body.get('appName') or device.name)+' · '+device.name)
    def clip(device, body):
        if prefs.get('linkClipboard',True) and isinstance(body.get('content'),str): link_copy(body['content'])
    def share(device, body):
        if link_open_url(body.get('url')): return
        if isinstance(body.get('text'),str):
            if link_copy(body['text']): notify('Text from '+device.name,'Copied to the clipboard')
            return
        if body.get('filename'):
            def fetch():
                target=service.download(device,body,HOME/'Downloads')
                notify(('Received '+target.name) if target else 'A file from '+device.name+' did not arrive', str(target.parent) if target else '')
            threading.Thread(target=fetch,daemon=True).start()
    def find(device, body): notify(device.name+' is looking for this device','',urgency='critical')
    def handoff(device, body):
        kind,value=body.get('kind'),body.get('value')
        if kind=='url': link_open_url(value)
        elif kind=='app' and isinstance(value,str) and re.fullmatch(r'[A-Za-z0-9._-]{1,200}',value) and shutil.which('gtk-launch'): spawn(['gtk-launch',value])
        elif kind=='text' and isinstance(value,str): link_copy(value)
    def paired(device):
        if device.link:
            s=LINK.get('status') or {}
            device.link.send('kdeconnect.battery',{'currentCharge':s.get('battery',-1),'isCharging':bool(s.get('charging')),'thresholdEvent':0})
            if device.opal: device.link.send('opal.session',LINK.get('session') or {})
    service.handlers.update({'kdeconnect.ping':ping,'kdeconnect.notification':notification,'kdeconnect.clipboard':clip,'kdeconnect.clipboard.connect':clip,
                             'kdeconnect.share.request':share,'kdeconnect.findmyphone.request':find,'opal.handoff':handoff,'paired':paired})

def link_apply():
    """Start or stop Opal Link to match preferences."""
    import opal_link
    wanted=prefs.get('linkEnabled') is True
    service=LINK['service']
    if wanted and not service:
        service=opal_link.LinkService(emit, HOME/'.local/state/opal/link', device_type=prefs.get('linkDeviceType','desktop') if prefs.get('linkDeviceType') in ('desktop','laptop','phone','tablet') else 'desktop')
        link_handlers(service)
        try:
            if service.start(import_kde=prefs.get('linkImportKde',True) is not False): LINK['service']=service
        except (OSError,ValueError) as error:
            emit({'event':'link','status':'error','detail':str(error),'devices':[]})
    elif not wanted and service:
        service.stop(); LINK['service']=None
    elif not wanted:
        emit({'event':'link','status':'off','devices':[]})

def link_status(current):
    """Share battery with paired devices and the active app and media with paired Opal devices."""
    service=LINK['service']
    previous=LINK.get('status') or {}
    LINK['status']=current
    if not service: return
    if current.get('battery')!=previous.get('battery') or current.get('charging')!=previous.get('charging'):
        service.broadcast('kdeconnect.battery',{'currentCharge':current.get('battery',-1),'isCharging':bool(current.get('charging')),'thresholdEvent':0})
    link_session()

def link_compositor(data):
    """Keep the latest window list and focus from compositor patches."""
    state=LINK.setdefault('compositor',{})
    state.update({k:v for k,v in data.items() if k in ('windows','activeAddress')})
    link_session()

def link_session():
    service=LINK['service']
    if not service: return
    current=LINK.get('status') or {}
    state=LINK.get('compositor') or {}
    active=next((w for w in state.get('windows') or [] if w.get('address')==state.get('activeAddress')),{})
    share=prefs.get('linkSession',True) is not False
    session={'app':active.get('className','') if share else '','title':'','track':current.get('track','') if share else '','artist':current.get('artist','') if share else '','playing':bool(current.get('playing'))}
    if session!=LINK.get('session'):
        LINK['session']=session
        service.broadcast('opal.session',session,opal_only=True)

def link_command(c):
    action=c.get('action'); service=LINK['service']; ident=c.get('id')
    if action=='link-stop-kde':
        if shutil.which('pkill'): subprocess.run(['pkill','-x','kdeconnectd'],timeout=5)
        time.sleep(1); LINK['service']=None; link_apply(); return
    if not service: return
    if action=='link-refresh': service.announce(); service.publish()
    elif action=='link-pair': service.pair(ident)
    elif action=='link-accept': service.accept(ident,True)
    elif action=='link-reject': service.accept(ident,False)
    elif action=='link-unpair': service.unpair(ident)
    elif action=='link-ping': service.send(ident,'kdeconnect.ping',{})
    elif action=='link-ring': service.send(ident,'kdeconnect.findmyphone.request',{})
    elif action=='link-clipboard':
        text=clipboard.items[0]['text'] if clipboard.items else ''
        if text: service.send(ident,'kdeconnect.clipboard',{'content':text})
    elif action=='link-handoff' and c.get('kind') in ('url','app','text') and isinstance(c.get('value'),str) and len(c['value'])<4000:
        service.send(ident,'opal.handoff',{'kind':c['kind'],'value':c['value']})

def session_object_path(session_id):
    """Encode a logind session ID as its D-Bus object path, like systemd's bus_path_encode."""
    if not session_id: return ''
    out=''.join(c if c.isalnum() and c.isascii() and not (i==0 and c.isdigit()) else '_%02x'%ord(c) for i,c in enumerate(session_id))
    return '/org/freedesktop/login1/session/'+out

def logind_locks(session_id=None, monitor=None):
    """Follow logind Lock requests for this session, so loginctl lock-session and suspend open the Opal lock screen."""
    path=session_object_path(session_id if session_id is not None else os.environ.get('XDG_SESSION_ID',''))
    if not path or not shutil.which('gdbus'): return
    try:
        process=monitor or subprocess.Popen(['gdbus','monitor','--system','--dest','org.freedesktop.login1','--object-path',path],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
    except OSError:
        return
    for line in process.stdout:
        if line.startswith(path+':') and 'org.freedesktop.login1.Session.Lock ()' in line:
            emit({'event':'lock'})
        elif line.startswith(path+':') and 'org.freedesktop.login1.Session.Unlock ()' in line:
            emit({'event':'unlock'})

def main():
    import atexit, signal
    global system_osk
    system_osk=SystemOsk()
    atexit.register(clipboard.stop)
    atexit.register(system_osk.stop)
    atexit.register(status_workers.shutdown, wait=False, cancel_futures=True)
    def shutdown(signum, frame):
        clipboard.stop()
        system_osk.stop()
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    threading.Thread(target=clipboard.watch,daemon=True).start()
    emit({'event':'preferences','data':prefs})
    system_osk.auto()
    threading.Thread(target=commands,daemon=True).start()
    threading.Thread(target=controllers,daemon=True).start()
    threading.Thread(target=logind_locks,daemon=True).start()
    threading.Thread(target=orientation_watch,daemon=True).start()
    threading.Thread(target=health_watch,daemon=True).start()
    threading.Thread(target=publish_games,daemon=True).start()
    threading.Thread(target=link_apply,daemon=True).start()
    from hypr_events import listen as listen_hyprland
    def compositor_emit(data):
        emit(data)
        if data.get('event')=='compositor': link_compositor(data.get('data') or {})
    threading.Thread(target=listen_hyprland, args=(compositor_emit,), daemon=True).start()
    last_published=None
    while True:
        try:
            current=status()
            if current != last_published:
                emit({'event':'status','data':current})
                last_published=current
                link_status(current)
        except Exception: pass
        time.sleep(2)

if __name__ == '__main__':
    main()
