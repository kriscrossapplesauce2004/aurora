package main

import (
	"context"
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

func (a *app) cacheConnectivity() {
	for op, args := range map[string][]string{"wifi-status": {"cmd", "wifi", "status"}, "wifi-list": {"cmd", "wifi", "list-networks"}, "bt-status": {"settings", "get", "global", "bluetooth_on"}} {
		ctx, cancel := context.WithTimeout(a.ctx, 8*time.Second)
		q := *a
		q.ctx = ctx
		s, e := q.output(args[0], args[1:]...)
		cancel()
		if e == nil {
			if op == "bt-status" {
				s = map[string]string{"1": "on", "0": "off"}[s]
			}
			_ = atomicWrite(a.p("run/connectivity-cache", op), []byte(s+"\n"), 0600)
		}
	}
}
func (a *app) androidConnectivity(op string, args []string) (string, error) {
	for _, pid := range a.pids("system_server") {
		if processFrozen(pid) {
			if !oneOf(op, "wifi-status", "wifi-scan", "wifi-list", "bt-status") {
				return "", exitError{69, "Android services are paused; change connectivity before handoff or use external-display mode"}
			}
			p := a.p("run/connectivity-cache", op)
			if !exists(p) {
				return "", exitError{69, "Android services are paused; no cached result is available"}
			}
			return read(p) + "\n[cached: Android services are paused in internal desktop mode]", nil
		}
	}
	var cmd []string
	switch op {
	case "wifi-status":
		cmd = []string{"cmd", "wifi", "status"}
	case "wifi-list":
		cmd = []string{"cmd", "wifi", "list-networks"}
	case "wifi-scan":
		if e := a.quiet("cmd", "wifi", "start-scan"); e != nil {
			return "", e
		}
		if e := a.sleep(3 * time.Second); e != nil {
			return "", e
		}
		cmd = []string{"cmd", "wifi", "list-scan-results"}
	case "wifi-enable":
		if len(args) != 1 || !oneOf(args[0], "on", "off") {
			return "", usage("invalid Wi-Fi state")
		}
		state := "disabled"
		if args[0] == "on" {
			state = "enabled"
		}
		cmd = []string{"cmd", "wifi", "set-wifi-enabled", state}
	case "wifi-connect":
		if len(args) < 2 || len(args) > 3 || !oneOf(args[1], "open", "owe", "wpa2", "wpa3", "wep") {
			return "", usage("invalid Wi-Fi connection")
		}
		cmd = append([]string{"cmd", "wifi", "connect-network"}, args...)
		cmd = append(cmd, "-p")
	case "wifi-forget":
		if len(args) != 1 || !digits(args[0]) {
			return "", usage("invalid network ID")
		}
		cmd = []string{"cmd", "wifi", "forget-network", args[0]}
	case "bt-status":
		s, e := a.output("settings", "get", "global", "bluetooth_on")
		v := map[string]string{"1": "on", "0": "off"}[s]
		if v == "" {
			v = "unknown"
		}
		return v, e
	case "bt-enable", "bt-disable":
		cmd = []string{"cmd", "bluetooth_manager", strings.TrimPrefix(op, "bt-")}
	default:
		return "", usage("unknown connectivity operation")
	}
	if oneOf(op, "wifi-status", "wifi-list", "wifi-scan", "bt-enable", "bt-disable") && len(args) != 0 {
		return "", usage("unexpected connectivity arguments")
	}
	// Android Binder shell services cannot write to Magisk-labelled descriptors.
	spool, e := os.CreateTemp("/data/local/tmp", ".aurora-connectivity-")
	if e != nil {
		return "", e
	}
	defer os.Remove(spool.Name())
	defer spool.Close()
	c := commandContext(a.ctx, cmd[0], cmd[1:]...)
	c.Stdout = spool
	c.Stderr = spool
	e = c.Run()
	b, _ := os.ReadFile(spool.Name())
	return strings.TrimSpace(string(b)), e
}
func (a *app) hostagent() error {
	dir := a.p("run/control/connectivity")
	if e := os.MkdirAll(dir, 0770); e != nil {
		return e
	}
	if e := os.Chown(dir, 1000, 1000); e != nil {
		return e
	}
	if e := os.Chmod(dir, 0770); e != nil {
		return e
	}
	fd, e := syscall.InotifyInit1(syscall.IN_CLOEXEC | syscall.IN_NONBLOCK)
	if e != nil {
		return e
	}
	defer syscall.Close(fd)
	for _, p := range []string{a.p("run/control"), dir} {
		if _, e = syscall.InotifyAddWatch(fd, p, syscall.IN_CREATE|syscall.IN_MOVED_TO); e != nil {
			return e
		}
	}
	for a.ctx.Err() == nil {
		paths, _ := filepath.Glob(filepath.Join(dir, "req.*"))
		for _, p := range paths {
			name := strings.TrimPrefix(filepath.Base(p), "req.")
			if !digits(strings.ReplaceAll(name, ".", "")) {
				continue
			}
			s, e := os.Lstat(p)
			if e != nil || !s.Mode().IsRegular() || s.Size() > 8192 {
				continue
			}
			raw, e := os.ReadFile(p)
			if e != nil {
				continue
			}
			lines := strings.Split(strings.TrimSuffix(string(raw), "\n"), "\n")
			if len(lines) == 0 {
				continue
			}
			op := lines[0]
			var args []string
			valid := true
			for _, line := range lines[1:] {
				b, e := base64.StdEncoding.DecodeString(line)
				if e != nil || strings.ContainsRune(string(b), 0) {
					valid = false
					break
				}
				args = append(args, string(b))
			}
			body := "invalid request"
			rc := 2
			if valid {
				ctx, cancel := context.WithTimeout(a.ctx, 30*time.Second)
				q := *a
				q.ctx = ctx
				body, e = q.androidConnectivity(op, args)
				cancel()
				rc = 0
				if e != nil {
					rc = 1
					if ee, ok := e.(exitError); ok {
						rc = ee.code
					}
					body += "\n" + e.Error()
				}
				if rc == 0 && oneOf(op, "wifi-status", "wifi-scan", "wifi-list", "bt-status") {
					_ = atomicWrite(a.p("run/connectivity-cache", op), []byte(body), 0600)
				}
			}
			res := filepath.Join(dir, "res."+name)
			if e = atomicWrite(res, []byte(fmt.Sprintf("%d\n%s\n", rc, body)), 0640); e != nil {
				return e
			}
			_ = os.Chown(res, 1000, 1000)
			_ = os.Remove(p)
		}
		if exists(a.p("run/control/exit")) {
			_ = os.Remove(a.p("run/control/exit"))
			if e = a.desktopOff(false); e != nil {
				fmt.Fprintln(a.err, e)
			}
		}
		_ = os.Remove(a.p("run/control/connectivity-wake"))
		buf := make([]byte, 4096)
		end := time.Now().Add(15 * time.Second)
		for time.Now().Before(end) {
			n, _ := syscall.Read(fd, buf)
			if n > 0 {
				break
			}
			if e = a.sleep(100 * time.Millisecond); e != nil {
				return nil
			}
		}
	}
	return nil
}
func (a *app) colorCompat() error {
	last := ""
	defer func() {
		q := *a
		q.ctx = context.Background()
		_ = q.quiet("service", "call", "SurfaceFlinger", "1008", "i32", "0")
		_ = atomicWrite(a.p("run/color-compat.state"), []byte("off\n"), 0600)
	}()
	for a.ctx.Err() == nil {
		s, _ := a.output("settings", "--user", "current", "get", "secure", "night_display_activated")
		v, label := "0", "off"
		if s == "1" || s == "true" {
			v = "1"
			label = "night-light"
		}
		if v != last && a.quiet("service", "call", "SurfaceFlinger", "1008", "i32", v) == nil {
			last = v
			_ = atomicWrite(a.p("run/color-compat.state"), []byte(label+"\n"), 0600)
		}
		if e := a.sleep(time.Second); e != nil {
			return nil
		}
	}
	return nil
}
func (a *app) external(x []string) error {
	op := arg(x, 0, "status")
	host := "/data/user_de/0/com.aurora.companion/files/presenter.sock"
	ready := func() bool {
		s, e := os.Stat(host)
		return e == nil && s.Mode()&os.ModeSocket != 0 && strings.Contains(read("/proc/net/unix"), host)
	}
	switch op {
	case "status":
		fmt.Fprintf(a.out, "socket_ready=%t\nguest_running=%t\n", ready(), a.running())
		for _, unit := range []string{"aurora-gralloc-pool.service", "aurora-plasma-presenter.service"} {
			s, _ := a.lxc("lxc-attach", "--", "/bin/systemctl", "is-active", unit)
			fmt.Fprintf(a.out, "%s=%s\n", unit, s)
		}
		return nil
	case "start":
		return fmt.Errorf("start the external display presenter in the Aurora Android app")
	case "stop":
		_ = a.input([]string{"stop"})
		a.pidSignal("external-presenter", syscall.SIGTERM, "")
		return a.attach("/bin/systemctl", "stop", "aurora-plasma-presenter.service", "aurora-gralloc-pool.service")
	case "plasma", "smoke":
		if e := a.guestStart(); e != nil {
			return e
		}
		if e := a.wait(10*time.Second, ready); e != nil {
			return fmt.Errorf("start the DP presenter in the Android app and connect a display")
		}
		if e := a.attach("/usr/bin/test", "-S", "/mnt/aurora-presenter/presenter.sock"); e != nil {
			return fmt.Errorf("presenter mount missing; restart the guest")
		}
		if op == "smoke" {
			return a.attach("/usr/bin/env", "LD_LIBRARY_PATH=/usr/local/lib:/opt/minigbm/lib", "HYBRIS_LD_LIBRARY_PATH=/usr/lib/android:/vendor/lib64:/system/lib64:/odm/lib64:/apex/com.android.runtime/lib64/bionic", "ANDROID_ROOT=/system", "EGL_PLATFORM=null", "HYBRIS_EGLPLATFORM=null", "/usr/local/bin/hybris-minigbm-probe", "/dev/dri/renderD128", "--present", "/mnt/aurora-presenter/presenter.sock", "1920", "1080", "20")
		}
		active := a.pidMatch("input-forwarder", "") != 0
		if active {
			_ = a.input([]string{"stop"})
		}
		_ = a.attach("/bin/systemctl", "stop", "aurora-plasma-presenter.service", "aurora-gralloc-pool.service")
		_ = a.attach("/bin/systemctl", "reset-failed", "aurora-plasma-presenter.service", "aurora-gralloc-pool.service")
		if e := a.attach("/bin/systemctl", "start", "aurora-gralloc-pool.service"); e != nil {
			return e
		}
		if e := a.wait(5*time.Second, func() bool {
			_, e := a.lxc("lxc-attach", "--", "/usr/bin/test", "-S", "/run/aurora/gralloc-pool.sock")
			return e == nil
		}); e != nil {
			return e
		}
		if e := a.attach("/bin/systemctl", "start", "aurora-plasma-presenter.service"); e != nil {
			return e
		}
		if active {
			return a.input([]string{"start"})
		}
		return nil
	}
	return usage("aurora external status|plasma|smoke|stop")
}
