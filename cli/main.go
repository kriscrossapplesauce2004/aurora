package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type app struct {
	root, side string
	out, err   io.Writer
	ctx        context.Context
}
type command struct {
	path, usage, description string
	side                     string
	run                      func(*app, []string) error
}
type exitError struct {
	code    int
	message string
}

func (e exitError) Error() string { return e.message }
func usage(s string) error        { return exitError{2, s} }
func env(k, v string) string {
	if x := os.Getenv(k); x != "" {
		return x
	}
	return v
}
func read(p string) string { b, _ := os.ReadFile(p); return strings.TrimSpace(string(b)) }
func exists(p string) bool { _, e := os.Stat(p); return e == nil }
func executable(p string) bool {
	s, e := os.Stat(p)
	return e == nil && !s.IsDir() && s.Mode()&0111 != 0
}
func (a *app) p(parts ...string) string { return filepath.Join(append([]string{a.root}, parts...)...) }
func fields(p string) map[string]string {
	m := map[string]string{}
	for _, s := range strings.Split(read(p), "\n") {
		k, v, ok := strings.Cut(s, "=")
		if ok && !strings.HasPrefix(k, "#") {
			m[k] = v
		}
	}
	return m
}
func atomicWrite(p string, b []byte, mode os.FileMode) error {
	if e := os.MkdirAll(filepath.Dir(p), 0755); e != nil {
		return e
	}
	f, e := os.CreateTemp(filepath.Dir(p), ".aurora-*")
	if e != nil {
		return e
	}
	defer os.Remove(f.Name())
	if e = f.Chmod(mode); e == nil {
		_, e = f.Write(b)
	}
	if e == nil {
		e = f.Sync()
	}
	ce := f.Close()
	if e == nil {
		e = ce
	}
	if e != nil {
		return e
	}
	return os.Rename(f.Name(), p)
}
func writeFields(p string, m map[string]string) error {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		fmt.Fprintf(&b, "%s=%s\n", k, m[k])
	}
	return atomicWrite(p, []byte(b.String()), 0600)
}
func (a *app) output(name string, args ...string) (string, error) {
	c := exec.CommandContext(a.ctx, name, args...)
	b, e := c.CombinedOutput()
	return strings.TrimSpace(string(b)), e
}
func (a *app) run(name string, args ...string) error {
	c := exec.CommandContext(a.ctx, name, args...)
	c.Stdin = os.Stdin
	c.Stdout = a.out
	c.Stderr = a.err
	return c.Run()
}
func (a *app) quiet(name string, args ...string) error { _, e := a.output(name, args...); return e }
func (a *app) helper(name string, args ...string) error {
	switch name {
	case "auroractl":
		return a.controlClient(args)
	case "aurora-guest-agent":
		return a.guestAgent(args)
	case "aurora-audio-probe":
		return a.audioProbe(args)
	}
	return a.privateHelper(name, args...)
}

func commandContext(ctx context.Context, name string, args ...string) *exec.Cmd {
	return exec.CommandContext(ctx, name, args...)
}
func (a *app) privateHelper(name string, args ...string) error {
	dir := env("AURORA_LIBEXEC", "/usr/local/libexec/aurora")
	c := exec.CommandContext(a.ctx, filepath.Join(dir, name), args...)
	c.Env = append(os.Environ(), "PATH="+dir+":"+env("PATH", "/usr/local/bin:/usr/bin:/bin"))
	c.Stdin = os.Stdin
	c.Stdout = a.out
	c.Stderr = a.err
	return c.Run()
}
func (a *app) lxc(tool string, args ...string) (string, error) {
	return a.output(filepath.Join(env("AURORA_LXC_BIN", a.p("lxc/bin")), tool), append([]string{"-P", a.root, "-n", "guest"}, args...)...)
}
func (a *app) attach(args ...string) error {
	return a.run(a.p("lxc/bin/lxc-attach"), append([]string{"-P", a.root, "-n", "guest", "--"}, args...)...)
}
func (a *app) guestRoot() string {
	if p, e := filepath.EvalSymlinks(a.p("active-guest")); e == nil {
		return p
	}
	return a.p("guest")
}
func (a *app) property(k string) string { s, _ := a.output("getprop", k); return s }
func (a *app) wait(d time.Duration, f func() bool) error {
	end := time.Now().Add(d)
	for {
		if f() {
			return nil
		}
		if time.Now().After(end) {
			return fmt.Errorf("deadline exceeded after %s", d)
		}
		select {
		case <-a.ctx.Done():
			return a.ctx.Err()
		case <-time.After(100 * time.Millisecond):
		}
	}
}
func (a *app) sleep(d time.Duration) error {
	select {
	case <-a.ctx.Done():
		return a.ctx.Err()
	case <-time.After(d):
		return nil
	}
}
func arg(args []string, i int, def string) string {
	if len(args) > i {
		return args[i]
	}
	return def
}
func exact(args []string, n int, s string) error {
	if len(args) != n {
		return usage(s)
	}
	return nil
}
func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	defer cancel()
	side := "linux"
	if runtime.GOOS == "android" || exists("/system/bin/getprop") {
		side = "android"
	}
	a := &app{env("AURORA", "/data/aurora"), side, os.Stdout, os.Stderr, ctx}
	args := os.Args[1:]
	if name := filepath.Base(os.Args[0]); name != "aurora" && !strings.HasPrefix(name, "aurora.test") {
		args = append([]string{"internal", "legacy", name}, args...)
	}
	if e := a.dispatch(args); e != nil {
		fmt.Fprintln(a.err, "aurora:", e)
		code := 1
		var ee exitError
		var xe *exec.ExitError
		if errors.As(e, &ee) {
			code = ee.code
		} else if errors.As(e, &xe) {
			code = xe.ExitCode()
			if code < 1 {
				code = 1
			}
		}
		os.Exit(code)
	}
}
func (a *app) dispatch(args []string) error {
	if len(args) == 0 || args[0] == "help" || args[0] == "--help" || args[0] == "-h" {
		if len(args) > 0 {
			args = args[1:]
		}
		return a.help(strings.Join(args, " "))
	}
	if args[0] == "internal" {
		return a.internal(args[1:])
	}
	for _, c := range commands() {
		if c.side != "" && c.side != a.side {
			continue
		}
		p := strings.Fields(c.path)
		if len(args) < len(p) || strings.Join(args[:len(p)], " ") != c.path {
			continue
		}
		rest := args[len(p):]
		for _, s := range rest {
			if s == "--help" || s == "-h" {
				return a.help(c.path)
			}
		}
		return c.run(a, rest)
	}
	if len(args) == 1 {
		return a.help(args[0])
	}
	return usage("unknown command; run 'aurora help'")
}
func (a *app) help(prefix string) error {
	found := false
	fmt.Fprintf(a.out, "Aurora — %s controls\n\n", a.side)
	for _, c := range commands() {
		if c.side != "" && c.side != a.side {
			continue
		}
		if prefix != "" && c.path != prefix && !strings.HasPrefix(c.path, prefix+" ") {
			continue
		}
		found = true
		fmt.Fprintf(a.out, "  aurora %-38s %s\n", c.usage, c.description)
	}
	if !found {
		return usage("unknown command: " + prefix)
	}
	fmt.Fprintln(a.out, "\nUse aurora <command> --help for command help.")
	return nil
}
func commands() []command {
	return []command{
		{"status", "status", "Show desktop, guest and control-plane state.", "", (*app).status},
		{"doctor", "doctor [--json]", "Check runtime health and report missing capabilities.", "", func(a *app, x []string) error {
			if a.side == "android" {
				return a.helper("auroractl", append([]string{"doctor"}, x...)...)
			}
			return a.helper("aurora-compat-check", x...)
		}},
		{"desktop", "desktop on|off", "Give the phone display to Linux, or restore Android.", "android", (*app).desktop},
		{"recover", "recover", "Restore Android after an interrupted display handoff.", "android", func(a *app, x []string) error {
			if e := exact(x, 0, "aurora recover"); e != nil {
				return e
			}
			return a.desktopOff(true)
		}},
		{"guest", "guest start|status", "Start the Linux container without changing display ownership.", "android", (*app).guest},
		{"distro", "distro list|status|install|activate|select|provision", "Manage Linux rootfs slots; failed boots roll back.", "android", (*app).distro},
		{"session", "session list|show|select ID", "Inspect desktops or select the next desktop session.", "android", (*app).session},
		{"boot", "boot status|phone|linux-first|apply|recover", "Choose the boot profile; Linux-first is device-profile gated.", "android", (*app).boot},
		{"external", "external status|plasma|smoke|stop", "Manage the external display producer; start the presenter in the Android app.", "android", (*app).external},
		{"input", "input start|stop|status", "Manage USB/Bluetooth input forwarding to Linux.", "android", (*app).input},
		{"audio", "audio status|claim|restore|smoke", "Inspect or transfer audio ownership, or run a playback check.", "android", (*app).audio},
		{"memory", "memory status|reclaim GENERATION|release GENERATION", "Inspect or reclaim stale command-provider workers.", "android", (*app).memory},
		{"config", "config show|lxc|guest", "Inspect the typed device profile or regenerate container configuration.", "android", (*app).config},
		{"test cycles", "test cycles [COUNT]", "Cycle display ownership and write recovery evidence; changes the display.", "android", (*app).cycles},
		{"environment", "environment catalog|plan|install|remove|status|cancel", "Install desktop packages and inspect progress; system builds run on the PC.", "android", (*app).environment},
		{"phone", "phone", "Leave Linux and restore the Android phone interface.", "linux", func(a *app, x []string) error {
			if e := exact(x, 0, "aurora phone"); e != nil {
				return e
			}
			return a.guestSignal("exit")
		}},
		{"power", "power reboot|off", "Request a device reboot or shutdown through authenticated control RPC.", "linux", (*app).power},
		{"wifi", "wifi status|scan|saved|on|off|connect|forget", "Manage Android-owned Wi-Fi; cached reads remain available in internal desktop mode.", "linux", (*app).wifi},
		{"bluetooth", "bluetooth status|on|off", "Inspect or toggle Android-owned Bluetooth.", "linux", (*app).bluetooth},
		{"keyboard", "keyboard show|hide|toggle", "Control the on-screen keyboard in this desktop session.", "linux", (*app).keyboard},
		{"volume", "volume get|up|down|mute|unmute|set N%", "Adjust this Linux session's audio volume.", "linux", (*app).volume},
		{"media", "media play-pause|next|previous", "Control media players in this session.", "linux", (*app).media},
		{"apps", "apps [status|list|apply|--help]", "Inspect or install the Aurora application profile.", "linux", func(a *app, x []string) error { return a.helper("aurora-apps", x...) }},
		{"shell", "shell opal|omarchy [ARGS...]", "Inspect or control the installed desktop shell.", "linux", (*app).shell},
	}
}
func (a *app) status(x []string) error {
	if len(x) != 0 {
		return usage("aurora status")
	}
	if a.side == "linux" {
		fmt.Fprintf(a.out, "session=%s\nruntime=%s\ncontrol=%t\n", os.Getenv("XDG_CURRENT_DESKTOP"), os.Getenv("XDG_RUNTIME_DIR"), exists("/mnt/aurora-control"))
		return nil
	}
	s, _ := a.lxc("lxc-info", "-sH")
	fmt.Fprintf(a.out, "guest=%s\ndesktop=%t\n", s, exists(a.p("run/desktop-mode")))
	fmt.Fprintln(a.out, read(a.p("run/transition.state")))
	return nil
}
func (a *app) guest(x []string) error {
	switch arg(x, 0, "status") {
	case "status":
		return a.status(nil)
	case "start":
		return a.guestStart()
	}
	return usage("aurora guest start|status")
}
func intValue(s string) int { n, _ := strconv.Atoi(s); return n }
