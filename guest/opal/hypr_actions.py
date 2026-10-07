"""Checked Hyprland actions for native Lua and legacy dispatcher builds."""
import json
import re
import subprocess
from functools import lru_cache


_COMPOSITOR_ERROR = re.compile(
    r'(^|\n)\s*(error:|unknown request|unknown dispatcher|invalid dispatcher)',
    re.I,
)


class HyprActions:
    _ADDRESS = re.compile(r'0x[0-9a-fA-F]+')
    _LUA_FOCUS_PREFIX = 'local w=hl.get_window("address:'
    _LUA_FOCUS_SUFFIX = (
        '"); assert(w and w.mapped,"Window is no longer available"); '
        'if w.monitor then hl.dispatch(hl.dsp.focus({monitor=w.monitor})) end; '
        'if w.workspace then hl.dispatch(hl.dsp.focus({workspace=w.workspace})) end; '
        'hl.dispatch(hl.dsp.focus({window=w}))'
    )

    def __init__(self, runner=None):
        self.runner=runner or self._run
        self.lua=None

    @staticmethod
    def _run(args):
        result=subprocess.run(args,capture_output=True,text=True,timeout=3)
        text=(result.stdout+'\n'+result.stderr).strip()
        # Check text because some builds return zero on errors.
        if result.returncode or _COMPOSITOR_ERROR.search(text):
            raise ValueError('Hyprland rejected the action: '+text[:240])
        return result.stdout.strip()

    def is_lua(self):
        if self.lua is None:
            try:
                self.lua=self.runner(['hyprctl','eval','return true']).strip()=='ok'
            except (ValueError,OSError,subprocess.SubprocessError):self.lua=False
        return self.lua

    @classmethod
    def _validate_address(cls,address):
        if not isinstance(address,str) or cls._ADDRESS.fullmatch(address) is None:
            raise ValueError('Invalid window address')

    @staticmethod
    def _validate_workspace(number):
        if type(number) is not int or not 1<=number<=2147483647:
            raise ValueError('Invalid workspace')

    @classmethod
    @lru_cache(maxsize=256)
    def _lua_focus_code(cls,address):
        return cls._LUA_FOCUS_PREFIX+address+cls._LUA_FOCUS_SUFFIX

    @staticmethod
    @lru_cache(maxsize=256)
    def _lua_workspace_code(number):
        return 'hl.dispatch(hl.dsp.focus({workspace="'+str(number)+'"}))'

    def focus(self,address):
        self._validate_address(address)
        if self.is_lua():
            # Resolve the live window inside the compositor.
            code=self._lua_focus_code(address)
            runner=self.runner
            runner(['hyprctl','eval',code])
        else:
            runner=self.runner
            clients=json.loads(runner(['hyprctl','-j','clients']))
            window=None
            for candidate in clients:
                if candidate.get('address')==address and candidate.get('mapped'):
                    window=candidate
                    break
            if not window:raise ValueError('Window is no longer available')
            workspace=window['workspace']
            target=str(workspace['id']) if workspace['id']>0 else workspace['name']
            runner(['hyprctl','dispatch','workspace',target])
            runner(['hyprctl','dispatch','focuswindow','address:'+address])

    def workspace(self,number):
        self._validate_workspace(number)
        runner=self.runner
        if self.is_lua():
            runner(['hyprctl','eval',self._lua_workspace_code(number)])
        else:runner(['hyprctl','dispatch','workspace',str(number)])

    def move(self,address,number,follow=False):
        """Move a window to a workspace. With follow, focus goes with it."""
        self._validate_address(address)
        self._validate_workspace(number)
        if self.is_lua():
            code=(self._LUA_FOCUS_PREFIX+address+'"); assert(w and w.mapped,"Window is no longer available"); '
                  'hl.dispatch(hl.dsp.window.move({workspace="'+str(number)+'",window=w}))')
            if follow:code+='; hl.dispatch(hl.dsp.focus({workspace="'+str(number)+'"})); hl.dispatch(hl.dsp.focus({window=w}))'
            self.runner(['hyprctl','eval',code])
        else:
            verb='movetoworkspace' if follow else 'movetoworkspacesilent'
            self.runner(['hyprctl','dispatch',verb,str(number)+',address:'+address])

    _OUTPUT=re.compile(r'[A-Za-z0-9._-]{1,64}')
    def rotate(self,output,transform):
        """Rotate one output and its touch input. Transform is Hyprland's 0-3 (0, 90, 180, 270 degrees)."""
        if not isinstance(output,str) or self._OUTPUT.fullmatch(output) is None:raise ValueError('Invalid output')
        if type(transform) is not int or not 0<=transform<=3:raise ValueError('Invalid rotation')
        if self.is_lua():
            self.runner(['hyprctl','eval','hl.monitor({output="'+output+'",mode="preferred",position="auto",scale="auto",transform='+str(transform)+'}); '
                         'hl.config({input={touchdevice={transform='+str(transform)+',output="'+output+'"}}})'])
        else:
            self.runner(['hyprctl','keyword','monitor',output+',preferred,auto,auto,transform,'+str(transform)])
            self.runner(['hyprctl','keyword','input:touchdevice:transform',str(transform)])


    def close(self,address):
        """Ask a window to close, like its close button."""
        self._validate_address(address)
        if self.is_lua():self.runner(['hyprctl','eval',self._LUA_FOCUS_PREFIX+address+'"); assert(w and w.mapped,"Window is no longer available"); hl.dispatch(hl.dsp.window.close({window=w}))'])
        else:self.runner(['hyprctl','dispatch','closewindow','address:'+address])

    def center(self,address):
        """Center a floating window on its monitor."""
        self._validate_address(address)
        if self.is_lua():self._lua_window(address,'hl.dispatch(hl.dsp.window.center({window=w}))')
        else:
            self.runner(['hyprctl','dispatch','focuswindow','address:'+address])
            self.runner(['hyprctl','dispatch','centerwindow'])

    def raise_window(self,address):
        """Put a floating window above the others."""
        self._validate_address(address)
        if self.is_lua():self._lua_window(address,'hl.dispatch(hl.dsp.window.alter_zorder({mode="top",window=w}))')
        else:self.runner(['hyprctl','dispatch','alterzorder','top,address:'+address])

    def workspace_empty(self):
        """Go to the first empty workspace."""
        if self.is_lua():self.runner(['hyprctl','eval','hl.dispatch(hl.dsp.focus({workspace="empty"}))'])
        else:self.runner(['hyprctl','dispatch','workspace','empty'])

    def exit(self):
        """End the compositor session."""
        if self.is_lua():self.runner(['hyprctl','eval','hl.dispatch(hl.dsp.exit())'])
        else:self.runner(['hyprctl','dispatch','exit'])

    _OPTION=re.compile(r'[a-z_]+(:[a-z_]+)*:[a-z_.]+')
    def config(self,option,value):
        """Set one runtime option such as general:col.active_border. Lua builds get a nested hl.config table."""
        if not isinstance(option,str) or self._OPTION.fullmatch(option) is None:raise ValueError('Invalid option')
        if isinstance(value,bool):lua,legacy='true' if value else 'false','true' if value else 'false'
        elif isinstance(value,(int,float)):lua=legacy=str(value)
        elif isinstance(value,str) and re.fullmatch(r'[A-Za-z0-9 #(),._-]{0,200}',value):lua,legacy=json.dumps(value),value
        else:raise ValueError('Invalid value')
        if self.is_lua():
            *sections,leaf=option.split(':')
            table='['+json.dumps(leaf)+']='+lua
            for section in reversed(sections):table=section+'={'+table+'}'
            self.runner(['hyprctl','eval','hl.config({'+table+'})'])
        else:self.runner(['hyprctl','keyword',option,legacy])

    def clients(self):
        """Return mapped, visible-capable windows from the compositor."""
        return [c for c in json.loads(self.runner(['hyprctl','-j','clients'])) if c.get('mapped')]

    def monitors(self):
        return json.loads(self.runner(['hyprctl','-j','monitors']))

    def _lua_window(self,address,body):
        # Run a best-effort call inside the compositor; an unsupported call must not stop the batch.
        code=(self._LUA_FOCUS_PREFIX+address+'"); if w and w.mapped then pcall(function() '+body+' end) end')
        self.runner(['hyprctl','eval',code])

    def set_floating(self,address,floating):
        """Make a window floating or tiled without focusing it."""
        self._validate_address(address)
        if self.is_lua():self._lua_window(address,'hl.dispatch(hl.dsp.window.float({action="'+('enable' if floating else 'disable')+'",window=w}))')
        else:self.runner(['hyprctl','dispatch','setfloating' if floating else 'settiled','address:'+address])

    def geometry(self,address,x,y,width,height):
        """Place a floating window at exact pixel coordinates."""
        self._validate_address(address)
        for value in (x,y,width,height):
            if type(value) is not int or not -100000<=value<=100000:raise ValueError('Invalid geometry')
        if width<1 or height<1:raise ValueError('Invalid geometry')
        if self.is_lua():
            self._lua_window(address,'hl.dispatch(hl.dsp.window.resize({x='+str(width)+',y='+str(height)+',exact=true,window=w})); '
                             'hl.dispatch(hl.dsp.window.move({x='+str(x)+',y='+str(y)+',exact=true,window=w}))')
        else:
            self.runner(['hyprctl','dispatch','resizewindowpixel','exact '+str(width)+' '+str(height)+',address:'+address])
            self.runner(['hyprctl','dispatch','movewindowpixel','exact '+str(x)+' '+str(y)+',address:'+address])

    def fullscreen(self,address,mode,restore_focus=''):
        """Set fullscreen mode 0 (off), 1 (maximize) or 2 (fullscreen). Hyprland acts on the focused window, so focus returns afterwards."""
        self._validate_address(address)
        if mode not in (0,1,2):raise ValueError('Invalid fullscreen mode')
        if self.is_lua():
            # The Lua dispatcher accepts a window target, so focus does not change.
            if mode:self._lua_window(address,'hl.dispatch(hl.dsp.window.fullscreen({mode="'+('fullscreen' if mode==2 else 'maximized')+'",action="set",window=w}))')
            else:self._lua_window(address,'hl.dispatch(hl.dsp.window.fullscreen_state({internal=0,client=0,action="set",window=w}))')
            return
        self.focus(address)
        if mode:self.runner(['hyprctl','dispatch','fullscreen','0' if mode==2 else '1'])
        else:self.runner(['hyprctl','dispatch','fullscreenstate','0 0'])
        if restore_focus and restore_focus!=address:self.focus(restore_focus)
