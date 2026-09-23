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
