package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func procStart(pid int) string {
	b := read(fmt.Sprintf("/proc/%d/stat", pid))
	i := strings.LastIndex(b, ") ")
	if i < 0 {
		return ""
	}
	f := strings.Fields(b[i+2:])
	if len(f) < 20 {
		return ""
	}
	return f[19]
}
func bootID() string { return read("/proc/sys/kernel/random/boot_id") }
func (a *app) pidWrite(role string, pid int, generation string) error {
	s := procStart(pid)
	if s == "" {
		return fmt.Errorf("%s process %d disappeared", role, pid)
	}
	return writeFields(a.p("run", role+".pid"), map[string]string{"pid": strconv.Itoa(pid), "start": s, "boot_id": bootID(), "role": role, "generation": generation})
}
func (a *app) pidMatch(role, generation string) int {
	m := fields(a.p("run", role+".pid"))
	pid := intValue(m["pid"])
	if pid <= 1 || m["role"] != role || m["boot_id"] != bootID() || m["start"] == "" || m["start"] != procStart(pid) || (generation != "" && m["generation"] != generation) {
		return 0
	}
	return pid
}
func (a *app) pidSignal(role string, sig syscall.Signal, generation string) {
	if pid := a.pidMatch(role, generation); pid != 0 {
		_ = syscall.Kill(pid, sig)
	}
	_ = os.Remove(a.p("run", role+".pid"))
}
func (a *app) lock() (func(), error) {
	if e := os.MkdirAll(a.p("run"), 0755); e != nil {
		return nil, e
	}
	f, e := os.OpenFile(a.p("run/transition.flock"), os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		return nil, e
	}
	e = a.wait(5*time.Second, func() bool { return syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB) == nil })
	if e != nil {
		f.Close()
		return nil, fmt.Errorf("transition lock busy: %w", e)
	}
	return func() { _ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN); _ = f.Close() }, nil
}
func (a *app) generation() string {
	return strconv.Itoa(intValue(fields(a.p("run/transition.state"))["generation"]) + 1)
}
func (a *app) state(state, generation, step, result string) error {
	return writeFields(a.p("run/transition.state"), map[string]string{"schema": "1", "boot_id": bootID(), "generation": generation, "state": state, "step": step, "result": result})
}
func (a *app) spawn(role, generation string, args ...string) error {
	if a.pidMatch(role, "") != 0 {
		return nil
	}
	exe, e := os.Executable()
	if e != nil {
		return e
	}
	if e = os.MkdirAll(a.p("log"), 0755); e != nil {
		return e
	}
	f, e := os.OpenFile(a.p("log", role+".log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	defer f.Close()
	c := exec.Command(exe, append([]string{"internal", role}, args...)...)
	c.Env = append(os.Environ(), "AURORA="+a.root)
	c.Stdout = f
	c.Stderr = f
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if e = c.Start(); e != nil {
		return e
	}
	if e = a.pidWrite(role, c.Process.Pid, generation); e != nil {
		_ = c.Process.Kill()
		_ = c.Wait()
		return e
	}
	return c.Process.Release()
}
func (a *app) pids(name string) []int {
	s, _ := a.output("pidof", name)
	var p []int
	for _, v := range strings.Fields(s) {
		if n := intValue(v); n > 1 {
			p = append(p, n)
		}
	}
	return p
}
func processFrozen(pid int) bool {
	s := fieldsColon(fmt.Sprintf("/proc/%d/status", pid))["State"]
	return strings.HasPrefix(s, "T") || strings.HasPrefix(s, "t")
}
func fieldsColon(p string) map[string]string {
	m := map[string]string{}
	for _, s := range strings.Split(read(p), "\n") {
		k, v, ok := strings.Cut(s, ":")
		if ok {
			m[k] = strings.TrimSpace(v)
		}
	}
	return m
}
func (a *app) internal(x []string) error {
	if len(x) == 0 {
		return usage("missing internal operation")
	}
	if a.side != "android" {
		return a.guestInternal(x)
	}
	role := x[0]
	switch role {
	case "install-guest":
		if len(x) != 2 {
			return usage("internal install-guest ROOT")
		}
		return a.deliverGuest(x[1])
	case "environment":
		return a.environmentRun(arg(x, 1, "install"), arg(x, 2, ""))
	case "evgrab":
		return a.grab()
	case "input-forwarder":
		return a.forwardInput(arg(x, 1, a.p("run/control/external-input.fifo")))
	case "daemon":
		return a.daemon(len(x) > 1 && x[1] == "--allow-transitions")
	case "ping-range":
		return os.WriteFile("/proc/sys/net/ipv4/ping_group_range", []byte("0 2147483647"), 0644)
	case "net-keeper":
		for a.ctx.Err() == nil {
			a.netAssert()
			if e := a.sleep(10 * time.Second); e != nil {
				return e
			}
		}
		return nil
	case "hostagent":
		return a.hostagent()
	case "color-compat":
		return a.colorCompat()
	case "compositor", "client":
		return a.supervise(role)
	case "suppressor", "ss-freezer":
		cfg, e := a.loadProfile()
		if e != nil {
			return e
		}
		for exists(a.p("run/desktop-mode")) {
			if role == "suppressor" {
				if a.property("init.svc.surfaceflinger") == "running" {
					_ = a.quiet("stop", "surfaceflinger")
				}
				if cfg["AURORA_BACKLIGHT_PATH"] != "" {
					_ = os.WriteFile(cfg["AURORA_BACKLIGHT_PATH"], []byte(cfg["AURORA_BACKLIGHT_LEVEL"]), 0644)
				}
			} else {
				for _, pid := range a.pids("system_server") {
					if !processFrozen(pid) {
						_ = syscall.Kill(pid, syscall.SIGSTOP)
					}
				}
			}
			if e := a.sleep(200 * time.Millisecond); e != nil {
				return e
			}
		}
		return nil
	case "health-keeper", "bootanim-keeper":
		end := time.Now().Add(120 * time.Second)
		for time.Now().Before(end) {
			if role == "health-keeper" {
				if a.property("init.svc.vendor.lineage_health") != "running" {
					_ = a.quiet("start", "vendor.lineage_health")
				}
			} else if a.property("init.svc.bootanim") == "running" {
				_ = a.quiet("setprop", "service.bootanim.exit", "1")
				_ = a.quiet("setprop", "service.bootanim.progress", "1")
				_ = a.sleep(3 * time.Second)
				if a.property("init.svc.bootanim") == "running" {
					_ = a.quiet("stop", "bootanim")
				}
			}
			if e := a.sleep(time.Second); e != nil {
				return e
			}
		}
		return nil
	case "transition":
		return a.transition(arg(x, 1, "desktop"))
	case "boot-failed":
		return a.bootFailed()
	case "boot-service":
		return a.bootService()
	case "legacy":
		return a.legacy(x[1:])
	}
	return usage("unknown internal operation: " + role)
}
func copyFile(src, dst string, mode os.FileMode) error {
	b, e := os.ReadFile(src)
	if e != nil {
		return e
	}
	return atomicWrite(dst, b, mode)
}
func (a *app) memory(x []string) error {
	op := arg(x, 0, "status")
	gen := arg(x, 1, "")
	if !oneOf(op, "status", "reclaim", "release") || (op != "status" && (!digits(gen) || len(x) != 2)) {
		return usage("aurora memory status|reclaim GENERATION|release GENERATION")
	}
	const prefix = "/system/bin/app_process /system/bin com.android.commands.content.Content call --uri content://g.tqyipmcoon.provider --user 0 --method log "
	proc := env("AURORA_PROC_ROOT", "/proc")
	anc := map[int]bool{}
	for p := os.Getpid(); p > 1 && !anc[p]; {
		anc[p] = true
		b := read(filepath.Join(proc, strconv.Itoa(p), "stat"))
		i := strings.LastIndex(b, ") ")
		if i < 0 {
			break
		}
		f := strings.Fields(b[i+2:])
		if len(f) < 2 {
			break
		}
		p = intValue(f[1])
	}
	matches := func() []int {
		var out []int
		ps := a.pids("app_process")
		if s := os.Getenv("AURORA_MEMORY_PIDS"); s != "" {
			ps = nil
			for _, v := range strings.Fields(s) {
				ps = append(ps, intValue(v))
			}
		}
		for _, p := range ps {
			if p <= 1 || anc[p] {
				continue
			}
			b, _ := os.ReadFile(filepath.Join(proc, strconv.Itoa(p), "cmdline"))
			if strings.HasPrefix(strings.ReplaceAll(string(b), "\x00", " "), prefix) {
				out = append(out, p)
			}
		}
		return out
	}
	before, after, term, killed := 0, 0, 0, 0
	if op != "release" {
		pids := matches()
		before = len(pids)
		if op == "status" {
			fmt.Fprintf(a.out, "matching_workers=%d\n", before)
			for _, p := range pids {
				fmt.Fprintf(a.out, "pid=%d\n", p)
			}
			return nil
		}
		if os.Getenv("AURORA_MEMORY_DRY_RUN") != "1" {
			identities := map[int]string{}
			for _, p := range pids {
				identities[p] = procStart(p)
				if identities[p] != "" && syscall.Kill(p, syscall.SIGTERM) == nil {
					term++
				}
			}
			if term > 0 {
				_ = a.sleep(time.Second)
				for _, p := range matches() {
					if identities[p] != "" && procStart(p) == identities[p] && syscall.Kill(p, syscall.SIGKILL) == nil {
						killed++
					}
				}
			}
		}
		after = len(matches())
	}
	return writeFields(a.p("run/desktop-memory.state"), map[string]string{"schema": "1", "mode": op, "generation": gen, "matching_before": strconv.Itoa(before), "matching_after": strconv.Itoa(after), "term_sent": strconv.Itoa(term), "kill_sent": strconv.Itoa(killed), "dry_run": env("AURORA_MEMORY_DRY_RUN", "0")})
}
