-- Loaded only while the runtime Opal marker exists. No DMS files are edited.
-- Compositor styling follows the shell layout mode, tuned per mode instead of
-- one generic desktop profile. Re-read on every Hyprland config reload; the
-- shell triggers one whenever the mode changes (see Hub.mode).
local function opal_mode()
    local f = io.open(os.getenv("HOME") .. "/.local/state/opal/preferences.json", "r")
    if not f then return "desktop" end
    local body = f:read("*a"); f:close()
    return body:match('"mode"%s*:%s*"([a-z]+)"') or "desktop"
end
local profiles = {
    desktop = { gaps_in = 5, gaps_out = 8, border = 1, rounding = 16 },
    console = { gaps_in = 2, gaps_out = 4, border = 1, rounding = 6 },
    -- Phone geometry is output-scoped below. Never square every monitor.
    phone = { gaps_in = 5, gaps_out = 8, border = 1, rounding = 16 },
}
local p = profiles[opal_mode()] or profiles.desktop
hl.config({
    general = { gaps_in = p.gaps_in, gaps_out = p.gaps_out, border_size = p.border,
        col = { active_border = "rgba(cbb5edee)", inactive_border = "rgba(55536655)" } },
    decoration = { rounding = p.rounding, blur = { enabled = true, size = 8, passes = 3 },
        shadow = { enabled = true, range = 35, render_power = 3, color = "rgba(080b1880)" } }
})
-- Written atomically by Opal after resolving each output's actual layout.
-- Workspace monitor selectors follow workspaces moved between outputs.
local runtime = os.getenv("XDG_RUNTIME_DIR")
local phone_displays = runtime and io.open(runtime .. "/opal-phone-displays", "r")
if phone_displays then
    for name in phone_displays:lines() do
        if not name:match("^mode=") and name:match("^[%w_.:%-]+$") then
            hl.workspace_rule({ workspace = "m[" .. name .. "]", no_rounding = true })
        end
    end
    phone_displays:close()
end
hl.layer_rule({ match = { namespace = "^opal-(bar|shelf|overlay|toast|volume-osd)$" }, blur = true, ignore_alpha = 0.1, no_anim = true })
-- New shade/audio cards blur only their own small surfaces; click-away layers
-- are transparent input surfaces, never fullscreen blur regions.
hl.layer_rule({ match = { namespace = "^opal-(audio|shade)$" }, blur = true, ignore_alpha = 0.1, no_anim = true })
-- The taskbar menu is a full-screen input host with one painted card.
-- ignore_alpha keeps blur confined to that translucent card.
hl.layer_rule({ match = { namespace = "^opal-taskbar-menu$" }, blur = true, ignore_alpha = 0.1, no_anim = true })
hl.layer_rule({ match = { namespace = "^opal-power-profile$" }, blur = true, ignore_alpha = 0.1, no_anim = true })
hl.layer_rule({ match = { namespace = "^opal-(audio|shade)-dismiss$" }, blur = false, no_anim = true })
local function bind(key, command)
    hl.unbind(key)
    hl.bind(key, hl.dsp.exec_cmd(command))
end
local qs = "quickshell ipc -p " .. os.getenv("HOME") .. "/.config/quickshell/opal call opal "
bind("SUPER + space", qs .. "launcher")
bind("ALT + space", qs .. "launcher")
bind("SUPER + comma", qs .. "controls")
bind("SUPER + N", qs .. "notifications")
bind("SUPER + CTRL + P", qs .. "phone")
bind("SUPER + CTRL + G", qs .. "gaming")
bind("SUPER + CTRL + D", qs .. "desktop")
bind("SUPER + X", qs .. "controls")
bind("SUPER + V", qs .. "clipboard")
bind("SUPER + M", "kitty -e btop")
bind("SUPER + ALT + L", "hyprlock")
bind("XF86AudioRaiseVolume", "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 3%+")
bind("XF86AudioLowerVolume", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%-")
bind("XF86AudioMute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
bind("XF86AudioMicMute", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")
bind("XF86AudioPlay", "playerctl play-pause")
bind("XF86AudioPause", "playerctl play-pause")
bind("XF86AudioNext", "playerctl next")
bind("XF86AudioPrev", "playerctl previous")
bind("XF86MonBrightnessUp", "brightnessctl set +5%")
bind("XF86MonBrightnessDown", "brightnessctl set 5%-")
