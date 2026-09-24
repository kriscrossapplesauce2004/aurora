package main

import (
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func (a *app) guestSignal(action string) error {
	return a.helper("aurora-guest-agent", "signal", action)
}
func (a *app) power(x []string) error {
	if len(x) != 1 {
		return usage("aurora power reboot|off")
	}
	switch x[0] {
	case "reboot":
		return a.guestSignal("reboot")
	case "off":
		return a.guestSignal("poweroff")
	}
	return usage("aurora power reboot|off")
}
func (a *app) wifi(x []string) error {
	op := arg(x, 0, "status")
	rest := []string{}
	if len(x) > 0 {
		rest = x[1:]
	}
	switch op {
	case "status", "scan":
		if len(rest) != 0 {
			return usage("aurora wifi " + op)
		}
		return a.connectivity("wifi-"+op, nil)
	case "saved":
		if len(rest) != 0 {
			return usage("aurora wifi saved")
		}
		return a.connectivity("wifi-list", nil)
	case "on", "off":
		if len(rest) != 0 {
			return usage("aurora wifi on|off")
		}
		return a.connectivity("wifi-enable", []string{op})
	case "connect":
		if len(rest) < 2 || len(rest) > 3 {
			return usage("aurora wifi connect SSID open|owe|wpa2|wpa3|wep [PASSPHRASE]")
		}
		if !oneOf(rest[1], "open", "owe", "wpa2", "wpa3", "wep") {
			return usage("unsupported Wi-Fi security")
		}
		return a.connectivity("wifi-connect", rest)
	case "forget":
		if len(rest) != 1 || !digits(rest[0]) {
			return usage("aurora wifi forget NETWORK_ID")
		}
		return a.connectivity("wifi-forget", rest)
	}
	return usage("aurora wifi status|scan|saved|on|off|connect|forget")
}
func (a *app) bluetooth(x []string) error {
	if len(x) > 1 {
		return usage("aurora bluetooth status|on|off")
	}
	op := map[string]string{"status": "bt-status", "on": "bt-enable", "off": "bt-disable"}[arg(x, 0, "status")]
	if op == "" {
		return usage("aurora bluetooth status|on|off")
	}
	return a.connectivity(op, nil)
}
func (a *app) connectivity(op string, args []string) error {
	dir := env("AURORA_CONTROL", "/mnt/aurora-control")
	if !exists(filepath.Join(dir, "connectivity")) {
		return fmt.Errorf("Android connectivity channel is unavailable")
	}
	id := fmt.Sprintf("%d.%d", os.Getpid(), time.Now().UnixNano())
	req := filepath.Join(dir, "connectivity", "req."+id)
	res := filepath.Join(dir, "connectivity", "res."+id)
	defer os.Remove(req)
	defer os.Remove(res)
	var b strings.Builder
	b.WriteString(op + "\n")
	for _, s := range args {
		b.WriteString(base64.StdEncoding.EncodeToString([]byte(s)) + "\n")
	}
	if e := atomicWrite(req, []byte(b.String()), 0600); e != nil {
		return e
	}
	if e := atomicWrite(filepath.Join(dir, "connectivity-wake"), nil, 0600); e != nil {
		return e
	}
	if e := a.wait(40*time.Second, func() bool { return exists(res) }); e != nil {
		return fmt.Errorf("Android connectivity request timed out: %w", e)
	}
	data, e := os.ReadFile(res)
	if e != nil {
		return e
	}
	code, body, ok := strings.Cut(string(data), "\n")
	n, e := strconv.Atoi(code)
	if !ok || e != nil || n < 0 || n > 255 {
		return fmt.Errorf("invalid connectivity response")
	}
	fmt.Fprint(a.out, body)
	if n != 0 {
		return exitError{n, "Android could not complete the connectivity request"}
	}
	return nil
}
func (a *app) keyboard(x []string) error {
	if len(x) > 1 {
		return usage("aurora keyboard show|hide|toggle")
	}
	op := arg(x, 0, "toggle")
	if !oneOf(op, "show", "hide", "toggle") {
		return usage("aurora keyboard show|hide|toggle")
	}
	visible := op == "show"
	if op == "toggle" {
		s, e := a.output("busctl", "--user", "get-property", "sm.puri.OSK0", "/sm/puri/OSK0", "sm.puri.OSK0", "Visible")
		if e != nil {
			return fmt.Errorf("cannot query the on-screen keyboard: %w", e)
		}
		switch strings.TrimSpace(s) {
		case "b true":
			visible = false
		case "b false":
			visible = true
		default:
			return fmt.Errorf("unexpected keyboard state: %s", s)
		}
	}
	return a.run("busctl", "--user", "call", "sm.puri.OSK0", "/sm/puri/OSK0", "sm.puri.OSK0", "SetVisible", "b", strconv.FormatBool(visible))
}
func (a *app) volume(x []string) error {
	if e := a.volumeCommand(x); e != nil {
		return e
	}
	if arg(x, 0, "get") != "get" {
		s, e := a.output("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@")
		if e == nil {
			f := strings.Fields(s)
			if len(f) > 1 {
				v, e := strconv.ParseFloat(f[1], 64)
				if e == nil {
					icon := "volume-high"
					if v < 0.34 {
						icon = "volume-low"
					} else if v < 0.67 {
						icon = "volume-medium"
					}
					if strings.Contains(s, "MUTED") {
						icon = "volume-muted"
					}
					_ = a.privateHelper("aurora-omarchy", "ipc", "shell", "summon", "omarchy.osd", fmt.Sprintf(`{"icon":%q,"value":%d}`, icon, int(v*100)))
				}
			}
		}
	}
	return nil
}
func (a *app) volumeCommand(x []string) error {
	op := arg(x, 0, "get")
	switch op {
	case "get":
		if len(x) > 1 {
			return usage("aurora volume get")
		}
		return a.run("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@")
	case "up", "down":
		if len(x) > 1 {
			return usage("aurora volume up|down")
		}
		delta := "5%+"
		if op == "up" {
			_ = a.quiet("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0")
		}
		if op == "down" {
			delta = "5%-"
		}
		return a.run("wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", delta)
	case "mute", "unmute", "toggle":
		if len(x) > 1 {
			return usage("aurora volume mute|unmute")
		}
		v := "1"
		if op == "toggle" {
			v = "toggle"
		}
		if op == "unmute" {
			v = "0"
		}
		return a.run("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", v)
	case "set":
		if len(x) != 2 || !strings.HasSuffix(x[1], "%") || !digits(strings.TrimSuffix(x[1], "%")) {
			return usage("aurora volume set 0%..100%")
		}
		if intValue(strings.TrimSuffix(x[1], "%")) > 100 {
			return usage("volume must be between 0% and 100%")
		}
		return a.run("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", x[1])
	}
	return usage("aurora volume get|up|down|mute|unmute|set N%")
}
func (a *app) media(x []string) error {
	if len(x) != 1 {
		return usage("aurora media play-pause|next|previous")
	}
	method := map[string]string{"play-pause": "PlayPause", "next": "Next", "previous": "Previous"}[x[0]]
	if method == "" {
		return usage("aurora media play-pause|next|previous")
	}
	s, e := a.output("busctl", "--user", "--no-pager", "--list")
	if e != nil {
		return e
	}
	found := false
	for _, line := range strings.Split(s, "\n") {
		f := strings.Fields(line)
		if len(f) > 0 && strings.HasPrefix(f[0], "org.mpris.MediaPlayer2.") {
			found = true
			if e := a.quiet("busctl", "--user", "call", f[0], "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", method); e != nil {
				return e
			}
		}
	}
	if !found {
		return fmt.Errorf("no media player is running in this session")
	}
	return nil
}
func (a *app) shell(x []string) error {
	if len(x) == 0 || !oneOf(x[0], "opal", "omarchy") {
		return usage("aurora shell opal|omarchy [ARGS...]")
	}
	return a.helper("aurora-"+x[0], x[1:]...)
}
func oneOf(s string, v ...string) bool {
	for _, x := range v {
		if s == x {
			return true
		}
	}
	return false
}
func digits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}
