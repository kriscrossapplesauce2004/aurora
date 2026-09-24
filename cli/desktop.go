package main

import (
	"context"
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

func (a *app) desktop(x []string) error {
	if len(x) != 1 {
		return usage("aurora desktop on|off")
	}
	switch x[0] {
	case "on":
		return a.desktopOn()
	case "off":
		return a.desktopOff(false)
	}
	return usage("aurora desktop on|off")
}
func (a *app) desktopOn() (err error) {
	unlock, e := a.lock()
	if e != nil {
		return e
	}
	defer unlock()
	if exists(a.p("run/desktop-mode")) && fields(a.p("run/transition.state"))["state"] == "DESKTOP" {
		return nil
	}
	cfg, e := a.loadProfile()
	if e != nil {
		return e
	}
	gen := a.generation()
	if e = a.state("ENTERING", gen, "guest", "running"); e != nil {
		return e
	}
	// Rollback must outlive cancellation; a frozen system_server must never be resumed.
	defer func() {
		if err != nil {
			ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
			defer cancel()
			q := *a
			q.ctx = ctx
			if recovery := q.desktopOffLocked(true); recovery != nil {
				err = fmt.Errorf("entry failed (%v); recovery failed: %w", err, recovery)
			}
		}
	}()
	if e = a.guestStartLocked(); e != nil {
		return e
	}
	if !a.running() {
		return fmt.Errorf("guest failed to reach RUNNING")
	}
	session := a.selected()
	if e = a.sessionReady(session); e != nil {
		return e
	}
	if e = writeFields(a.p("run/session.active"), session); e != nil {
		return e
	}
	if e = atomicWrite(a.p("run/desktop-mode"), nil, 0600); e != nil {
		return e
	}
	a.cacheConnectivity()
	_ = os.Remove(a.p("run/evgrab.ready"))
	if e = a.spawn("evgrab", gen); e != nil {
		return e
	}
	if e = a.wait(3*time.Second, func() bool { return read(a.p("run/evgrab.ready")) == fmt.Sprint(a.pidMatch("evgrab", gen)) }); e != nil {
		return fmt.Errorf("input grab did not become ready: %w", e)
	}
	if e = a.state("ENTERING", gen, "display-owner", "running"); e != nil {
		return e
	}
	_ = a.quiet("stop", "bootanim")
	if e = a.quiet("stop", "surfaceflinger"); e != nil {
		return e
	}
	if e = a.spawn("suppressor", gen); e != nil {
		return e
	}
	if e = a.spawn("ss-freezer", gen); e != nil {
		return e
	}
	if e = a.wait(10*time.Second, func() bool { return a.property("init.svc.surfaceflinger") == "stopped" }); e != nil {
		return e
	}
	if e = a.sleep(time.Second); e != nil {
		return e
	}
	if p := cfg["AURORA_BACKLIGHT_PATH"]; p != "" {
		_ = os.WriteFile(p, []byte(cfg["AURORA_BACKLIGHT_LEVEL"]), 0644)
	}
	if e = a.transition("desktop"); e != nil {
		fmt.Fprintln(a.err, "transition animation skipped:", e)
	}
	if exists(a.p("etc/audio-owner.conf")) {
		if oneOf(fields(a.p("run/audio-owner.state"))["phase"], "restoring", "restore-failed") {
			_ = a.audioOwner("recover", true)
		}
		if e = a.audioRoute("claim"); e != nil {
			fmt.Fprintln(a.err, "audio claim failed; desktop continues muted:", e)
		}
	}
	raw := session["backend"] == "gralloc-minigbm"
	if raw {
		if e = a.quiet("stop", "vendor.hwcomposer-2-4"); e != nil {
			return e
		}
		if e = a.wait(5*time.Second, func() bool { return a.property("init.svc.vendor.hwcomposer-2-4") == "stopped" }); e != nil {
			return e
		}
		_ = os.WriteFile("/sys/class/backlight/panel0-backlight/brightness", []byte("500"), 0644)
		_ = os.WriteFile("/sys/class/drm/card0-Virtual-1/status", []byte("off"), 0644)
	}
	if e = a.wait(3*time.Second, func() bool {
		pids := a.pids("system_server")
		if len(pids) == 0 {
			return false
		}
		for _, p := range pids {
			if !processFrozen(p) {
				return false
			}
		}
		return true
	}); e != nil {
		return fmt.Errorf("system_server is not frozen at input handoff: %w", e)
	}
	if !raw {
		a.pidSignal("evgrab", syscall.SIGTERM, gen)
	}
	_ = a.memory([]string{"reclaim", gen})
	if e = a.state("ENTERING", gen, "compositor", "running"); e != nil {
		return e
	}
	if e = a.spawn("compositor", gen); e != nil {
		return e
	}
	if !raw && session["shell"] != "hyprland-config" {
		if e = a.spawn("client", gen); e != nil {
			return e
		}
	}
	if e = a.wait(30*time.Second, func() bool {
		_, err := a.lxc("lxc-attach", "--", "/usr/bin/test", "-S", "/run/user/1000/wayland-0")
		return err == nil
	}); e != nil {
		return fmt.Errorf("compositor did not publish Wayland socket: %w", e)
	}
	if raw {
		a.pidSignal("evgrab", syscall.SIGTERM, gen)
		_ = a.sleep(3 * time.Second)
		_ = os.WriteFile("/sys/kernel/oplus_display/notify_panel_blank", []byte("1"), 0644)
	}
	if e = a.state("DESKTOP", gen, "session", "committed"); e != nil {
		return e
	}
	if e = a.input([]string{"start"}); e != nil {
		fmt.Fprintln(a.err, "input forwarding unavailable:", e)
	}
	fmt.Fprintln(a.out, "Desktop ready:", session["id"])
	return nil
}
func (a *app) desktopOff(emergency bool) error {
	unlock, e := a.lock()
	if e != nil {
		return e
	}
	defer unlock()
	return a.desktopOffLocked(emergency)
}
func (a *app) desktopOffLocked(emergency bool) error {
	gen := fields(a.p("run/transition.state"))["generation"]
	if gen == "" {
		gen = "0"
	}
	signalGen := gen
	if emergency {
		signalGen = ""
	}
	if e := a.state("EXITING", gen, "preflight", "running"); e != nil {
		return e
	}
	_ = os.Remove(a.p("run/desktop-mode"))
	_ = os.Remove(a.p("run/native-gate"))
	a.pidSignal("suppressor", syscall.SIGTERM, signalGen)
	_ = a.input([]string{"stop"})
	a.pidSignal("ss-freezer", syscall.SIGTERM, signalGen)
	// SIGCONT would release the accumulated Android Watchdog timeout.
	for _, p := range a.pids("system_server") {
		_ = syscall.Kill(p, syscall.SIGKILL)
	}
	if a.property("sys.boot_completed") == "1" {
		_ = a.spawn("health-keeper", gen)
	}
	m := fields(a.p("run/session.active"))
	if m["compositor"] == "" {
		m = a.selected()
	}
	raw := m["backend"] == "gralloc-minigbm"
	for _, unit := range []string{"aurora-phosh.service", "aurora-plasma.service"} {
		_, _ = a.lxc("lxc-attach", "--", "/bin/systemctl", "stop", unit)
	}
	for _, name := range []string{filepath.Base(m["shell"]), "squeekboard", "foot", "plasmashell"} {
		if name != "" && name != "." && name != "hyprland-config" {
			_, _ = a.lxc("lxc-attach", "--", "/usr/bin/pkill", "-TERM", "-x", name)
		}
	}
	a.pidSignal("client", syscall.SIGTERM, signalGen)
	a.pidSignal("compositor", syscall.SIGTERM, signalGen)
	comp := filepath.Base(m["compositor"])
	if comp != "" && comp != "." {
		_, _ = a.lxc("lxc-attach", "--", "/usr/bin/pkill", "-TERM", "-x", comp)
		if e := a.wait(3*time.Second, func() bool { return len(a.pids(comp)) == 0 }); e != nil {
			_, _ = a.lxc("lxc-attach", "--", "/usr/bin/pkill", "-KILL", "-x", comp)
			if e = a.wait(time.Second, func() bool { return len(a.pids(comp)) == 0 }); e != nil {
				_ = a.state("RECOVERY", gen, "compositor", "ambiguous")
				return fmt.Errorf("compositor still owns display; refusing SurfaceFlinger restart")
			}
		}
	}
	_ = os.Remove(a.p("run/session.active"))
	if raw || emergency {
		_ = os.WriteFile("/sys/class/drm/card0-Virtual-1/status", []byte("detect"), 0644)
		if a.property("init.svc.vendor.hwcomposer-2-4") != "running" {
			_ = a.quiet("start", "vendor.hwcomposer-2-4")
			_ = a.sleep(2 * time.Second)
		}
		_ = a.quiet("stop", "vendor.livedisplay-hal")
		_ = a.quiet("stop", "display-color-hal-1-0")
		_ = a.sleep(time.Second)
		_ = a.quiet("start", "display-color-hal-1-0")
		_ = a.sleep(time.Second)
		_ = a.quiet("start", "vendor.livedisplay-hal")
	}
	for _, sig := range []string{"-TERM", "-KILL"} {
		for _, name := range []string{"wireplumber", "pipewire-pulse", "pipewire"} {
			_, _ = a.lxc("lxc-attach", "--", "/usr/bin/pkill", sig, "-x", name)
		}
		_ = a.sleep(300 * time.Millisecond)
	}
	if exists(a.p("run/audio-route.state")) {
		if e := a.audioRoute("restore"); e != nil {
			fmt.Fprintln(a.err, "audio restore needs recovery:", e)
		}
	} else if oneOf(fields(a.p("run/audio-owner.state"))["phase"], "claimed", "restoring", "restore-failed") {
		if e := a.audioOwner("restore", true); e != nil {
			fmt.Fprintln(a.err, "audio restore needs recovery:", e)
		}
	}
	if e := a.quiet("start", "surfaceflinger"); e != nil {
		return e
	}
	if e := a.wait(10*time.Second, func() bool { return a.property("init.svc.surfaceflinger") == "running" }); e != nil {
		_ = a.state("RECOVERY", gen, "surfaceflinger", "failed")
		return e
	}
	if a.property("sys.boot_completed") == "1" {
		_ = a.spawn("bootanim-keeper", gen)
	}
	a.pidSignal("evgrab", syscall.SIGTERM, signalGen)
	_ = a.memory([]string{"release", gen})
	if e := a.state("PHONE", gen, "complete", "committed"); e != nil {
		return e
	}
	if exists(a.p("etc/stop-guest-on-exit")) {
		_, _ = a.lxc("lxc-stop", "-t", "10")
	}
	return nil
}
func (a *app) transition(direction string) error {
	if !oneOf(direction, "desktop", "phone") {
		return usage("transition desktop|phone")
	}
	if a.property("init.svc.surfaceflinger") != "stopped" {
		return fmt.Errorf("SurfaceFlinger still owns HWC")
	}
	ctx, cancel := context.WithTimeout(a.ctx, 5*time.Second)
	defer cancel()
	q := *a
	q.ctx = ctx
	return q.attach("/usr/bin/env", "LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib/aarch64-linux-gnu", "HYBRIS_LD_LIBRARY_PATH=/usr/lib/android:/vendor/lib64:/system/lib64:/odm/lib64:/apex/com.android.runtime/lib64/bionic", "EGL_PLATFORM=hwcomposer", "HYBRIS_EGLPLATFORM=hwcomposer", "ANDROID_ROOT=/system", "TMPDIR=/tmp", "/usr/local/libexec/aurora/aurora-transition", direction)
}
func (a *app) supervise(role string) error {
	m := fields(a.p("run/session.active"))
	fails := 0
	for exists(a.p("run/desktop-mode")) && a.ctx.Err() == nil {
		started := time.Now()
		if role == "compositor" {
			if m["backend"] == "gralloc-minigbm" {
				if e := a.attach("/usr/local/bin/aurora", "internal", "plasma-prepare", m["shell"]); e != nil {
					return e
				}
				_ = a.attach("/bin/systemctl", "restart", "aurora-plasma.service")
				for exists(a.p("run/desktop-mode")) {
					_, e := a.lxc("lxc-attach", "--", "/bin/systemctl", "is-active", "--quiet", "aurora-plasma.service")
					if e != nil {
						break
					}
					if e = a.sleep(time.Second); e != nil {
						return e
					}
				}
			} else {
				if e := a.attach("/usr/local/bin/aurora", "internal", "session-prepare"); e != nil {
					return e
				}
				args := []string{"/usr/local/bin/aurora", "internal", "as-user", "/usr/local/libexec/aurora/aurora-session-launch", "compositor", m["compositor"]}
				args = append(args, strings.Fields(m["compositor_args"])...)
				_ = a.attach(args...)
			}
		} else if filepath.Base(m["shell"]) == "phosh" {
			_ = a.attach("/usr/local/bin/aurora", "internal", "as-user", "/usr/local/libexec/aurora/aurora-phosh-session")
		} else {
			shell := m["shell"]
			if shell == "" {
				shell = "/usr/bin/foot"
			}
			_ = a.attach("/usr/local/bin/aurora", "internal", "as-user", "/usr/local/libexec/aurora/aurora-session-launch", "client", shell)
		}
		if time.Since(started) < 5*time.Second {
			fails++
			if fails > 10 {
				fails = 10
			}
		} else {
			fails = 1
		}
		if e := a.sleep(time.Duration(fails) * time.Second); e != nil {
			return e
		}
	}
	return nil
}
func (a *app) boot(x []string) error {
	op := arg(x, 0, "status")
	path := a.p("state/boot-profile")
	m := fields(path)
	switch op {
	case "status":
		if len(m) == 0 {
			fmt.Fprintln(a.out, "desired=phone")
		} else {
			fmt.Fprintln(a.out, read(path))
		}
		return nil
	case "phone", "linux-first":
		cfg, e := a.loadProfile()
		if e != nil {
			return e
		}
		if op == "linux-first" && cfg["AURORA_LINUX_FIRST_SUPPORTED"] != "1" {
			return fmt.Errorf("Linux-first is not supported by this device profile")
		}
		unlock, e := a.lock()
		if e != nil {
			return e
		}
		defer unlock()
		previous := m["desired"]
		if previous != "linux-first" {
			previous = "phone"
		}
		b, _ := os.ReadFile(a.p("etc/device.conf"))
		digest := sha256.Sum256(b)
		return writeFields(path, map[string]string{"schema": "1", "desired": op, "previous_known_good": previous, "generation": a.generation(), "attempt_count": "0", "deadline_seconds": "45", "result": "accepted", "profile_digest": fmt.Sprintf("%x", digest)})
	case "apply":
		if m["desired"] == "linux-first" {
			cfg, e := a.loadProfile()
			if e != nil {
				return e
			}
			if cfg["AURORA_LINUX_FIRST_SUPPORTED"] != "1" {
				return fmt.Errorf("Linux-first profile unsupported")
			}
			ctx, cancel := context.WithTimeout(a.ctx, 45*time.Second)
			defer cancel()
			q := *a
			q.ctx = ctx
			if e = q.desktopOn(); e != nil {
				_ = a.bootFailed()
				return e
			}
		} else if m["desired"] == "phone" {
			if e := a.desktopOff(true); e != nil {
				return e
			}
		} else {
			return fmt.Errorf("invalid persisted boot profile")
		}
		m["result"] = "committed"
		return writeFields(path, m)
	case "recover":
		if e := a.desktopOff(true); e != nil {
			return e
		}
		return a.boot([]string{"phone"})
	}
	return usage("aurora boot status|phone|linux-first|apply|recover")
}
func (a *app) bootFailed() error {
	p := a.p("state/boot-profile")
	m := fields(p)
	m["desired"] = "phone"
	m["attempt_count"] = fmt.Sprint(intValue(m["attempt_count"]) + 1)
	m["result"] = "recovery-required"
	return writeFields(p, m)
}
func (a *app) bootService() error {
	if e := a.wait(180*time.Second, func() bool { return a.property("sys.boot_completed") == "1" }); e != nil {
		return e
	}
	for _, role := range []string{"daemon", "color-compat"} {
		if e := a.spawn(role, ""); e != nil {
			return e
		}
	}
	if e := a.guestStart(); e != nil {
		return e
	}
	if fields(a.p("state/boot-profile"))["desired"] == "linux-first" {
		return a.boot([]string{"apply"})
	}
	return nil
}
func (a *app) cycles(x []string) (err error) {
	n := intValue(arg(x, 0, "50"))
	if n < 1 || n > 10000 {
		return usage("aurora test cycles COUNT (1..10000)")
	}
	p := a.p("metrics", "cycle-"+time.Now().Format("20060102-150405")+".log")
	if e := os.MkdirAll(filepath.Dir(p), 0755); e != nil {
		return e
	}
	f, e := os.OpenFile(p, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	defer f.Close()
	defer func() {
		if err != nil {
			q := *a
			q.ctx = context.Background()
			_ = q.desktopOff(true)
		}
	}()
	for i := 1; i <= n; i++ {
		start := time.Now()
		if err = a.desktopOn(); err != nil {
			return err
		}
		if err = a.desktopOff(false); err != nil {
			return err
		}
		fmt.Fprintf(f, "cycle=%d elapsed_ms=%d surfaceflinger=%s\n", i, time.Since(start).Milliseconds(), a.property("init.svc.surfaceflinger"))
		_ = f.Sync()
	}
	fmt.Fprintln(a.out, "Cycle evidence:", p)
	return nil
}
