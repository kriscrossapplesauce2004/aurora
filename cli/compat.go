package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Private multicall links preserve fixed-argv consumers during payload migration.
func (a *app) legacy(x []string) error {
	if len(x) == 0 {
		return usage("missing compatibility command")
	}
	name, args := x[0], x[1:]
	switch name {
	case "auroractl":
		return a.controlClient(args)
	case "aurorad":
		allow := false
		for i := 0; i < len(args); i++ {
			switch args[i] {
			case "--root":
				i++
				if i == len(args) {
					return usage("missing root")
				}
				a.root = args[i]
			case "--allow-transitions":
				allow = true
			case "--observe-only":
				allow = false
			case "--foreground":
			default:
				return usage("unknown daemon option")
			}
		}
		return a.daemon(allow)
	case "aurora-guest-agent":
		return a.guestAgent(args)
	case "aurora-audio-probe":
		return a.audioProbe(args)
	case "aurora-audio-owner":
		return a.audioOwner(arg(args, 0, "status"), len(args) > 1 && args[1] == "--apply")
	case "aurora-audio-route":
		return a.audioRoute(arg(args, 0, ""))
	case "aurora-audio-smoke":
		return a.audioSmoke(args)
	case "aurora-input-forwarder":
		if len(args) != 1 {
			return usage("input forwarder FIFO")
		}
		return a.forwardInput(args[0])
	case "evgrab":
		return a.grab()
	case "device-config":
		return a.config([]string{"show"})
	case "generate-lxc-config":
		return a.config(append([]string{"lxc"}, args...))
	case "generate-guest-config":
		return a.config([]string{"guest"})
	case "boot-profile":
		if arg(args, 0, "") == "failed" {
			return a.bootFailed()
		}
		return a.boot(args)
	case "guest-distro":
		return a.distro(args)
	case "env-install":
		return a.environment(args)
	case "guest-start":
		return a.guestStart()
	case "desktop-on":
		return a.desktopOn()
	case "desktop-off", "native-restore":
		return a.desktopOff(name == "native-restore" || arg(args, 0, "") == "--emergency")
	case "desktop-memory":
		return a.memory(args)
	case "session-catalog":
		return a.session([]string{"list"})
	case "session-select":
		return a.session([]string{"show"})
	case "session-set":
		return a.session(append([]string{"select"}, args...))
	case "run-transition":
		return a.transition(arg(args, 0, ""))
	case "external-input":
		return a.input(args)
	case "external-presenter":
		return a.external(args)
	case "aurora-hostagent":
		return a.hostagent()
	case "aurora-color-compat":
		return a.colorCompat()
	case "cycle-stress.sh":
		return a.cycles(args)
	case "aurora-connectivity":
		if len(args) == 0 {
			return usage("missing connectivity operation")
		}
		return a.connectivity(args[0], args[1:])
	case "aurora-osk":
		return a.keyboard(args)
	case "aurora-media-action":
		return a.media(args)
	case "aurora-audio-volume":
		if len(args) == 1 && args[0] == "mute" {
			args = []string{"toggle"}
		}
		return a.volume(args)
	case "aurora-signal":
		return a.guestSignal(arg(args, 0, ""))
	}
	return fmt.Errorf("unknown private command: %s", name)
}
func (a *app) plasmaPrepare(shell string) error {
	if e := a.privateHelper("aurora-input-udevdb"); e != nil {
		return e
	}
	paths, _ := filepath.Glob("/sys/class/drm/card[0-9]/dev")
	for _, p := range paths {
		dev := read(p)
		if strings.Contains(dev, "/") {
			return fmt.Errorf("invalid DRM device identity")
		}
		if e := atomicWrite("/run/udev/data/c"+dev, []byte("E:ID_SEAT=seat0\nG:seat\nG:master-of-seat\nQ:seat\nQ:master-of-seat\nI:1\n"), 0644); e != nil {
			return e
		}
	}
	if e := a.run("systemctl", "start", "systemd-logind"); e != nil {
		return e
	}
	p := "/home/aurora/.config/kwinrc"
	if !strings.Contains(read(p), "nightlightEnabled") {
		if e := atomicWrite(p, []byte("[Plugins]\nnightlightEnabled=false\n"), 0600); e != nil {
			return e
		}
		_ = os.Chown(p, 1000, 1000)
	}
	client := "foot"
	if oneOf(filepath.Base(shell), "plasmashell", "aurora-plasma-client") {
		client = "plasmashell"
	}
	return atomicWrite("/run/aurora-plasma.env", []byte("AURORA_GRAPHICS_RENDERER=mesa\nAURORA_PLASMA_CLIENT="+client+"\n"), 0644)
}
