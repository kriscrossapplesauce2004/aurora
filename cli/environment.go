package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"
)

func commaList(s string) []string {
	var out []string
	for _, v := range strings.Split(s, ",") {
		v = strings.TrimSpace(v)
		if v != "" {
			out = append(out, v)
		}
	}
	return out
}
func (a *app) environmentManifest(id string) (map[string]string, error) {
	if !sessionID.MatchString(id) {
		return nil, usage("invalid environment ID")
	}
	p := filepath.Join(env("AURORA_ENV_SESSIONS", a.p("etc/sessions")), id+".session")
	m := fields(p)
	if m["id"] != id {
		return nil, fmt.Errorf("unknown environment: %s", id)
	}
	return m, nil
}
func (a *app) environmentPackages(m map[string]string) ([]string, error) {
	set := map[string]bool{}
	for _, group := range commaList(m["packages"]) {
		s, e := a.lxc("lxc-attach", "--", "/usr/local/libexec/aurora/aurora-platform", "deps-packages", group)
		if e != nil {
			return nil, e
		}
		for _, p := range strings.Fields(s) {
			set[p] = true
		}
	}
	out := []string{}
	for p := range set {
		out = append(out, p)
	}
	sort.Strings(out)
	return out, nil
}
func (a *app) environmentRecord(m map[string]string) error {
	fmt.Fprintln(a.out, "==environment")
	for _, k := range []string{"id", "title", "description", "backend", "renderer", "qualification", "reason", "limitations", "packages", "build_deps", "build", "glue", "required_binaries"} {
		fmt.Fprintf(a.out, "%s=%s\n", k, m[k])
	}
	ready, reason := "yes", ""
	if e := a.sessionReady(m); e != nil {
		ready = "no"
		reason = e.Error()
	}
	fmt.Fprintf(a.out, "runtime_ready=%s\nruntime_reason=%s\ninstalled=%s\n", ready, reason, ready)
	recipe, installable, pkgState := "none", "no", "unknown"
	why := "No package recipe; build the environment on the PC."
	if m["packages"] != "" {
		recipe = "packages"
		installable = "yes"
		why = ""
	} else if m["build"] != "" {
		recipe = "build"
	}
	pkgs, e := a.environmentPackages(m)
	if a.running() {
		pkgState = "unsupported"
		if e == nil && len(pkgs) > 0 {
			pkgState = "available"
		} else if m["packages"] != "" {
			installable = "no"
			why = "No package set for this guest distro."
		}
	}
	fmt.Fprintf(a.out, "recipe=%s\npackage_set=%s\ninstallable=%s\ninstallable_reason=%s\nbuild_entrypoint=%s\nbuild_present=no\n", recipe, pkgState, installable, why, m["build"])
	return nil
}
func (a *app) environmentChecks() error {
	checks := []struct {
		id, title, detail string
		ok                bool
	}{{"root", "Root access", "Run through Magisk su", os.Geteuid() == 0}, {"mode", "Display ownership", "Exit to phone mode before changing packages", !exists(a.p("run/desktop-mode"))}, {"runtime", "Aurora runtime", "Install the current module", executable(a.p("bin/aurora"))}, {"guest", "Guest rootfs", "Install a Linux rootfs", exists(a.guestRoot())}}
	var disk syscall.Statfs_t
	if syscall.Statfs(a.guestRoot(), &disk) == nil {
		checks = append(checks, struct {
			id, title, detail string
			ok                bool
		}{"storage", "Guest storage", "At least 1 GiB free is required", disk.Bavail*uint64(disk.Bsize) >= 1024*1024*1024})
	}
	failed := false
	for _, c := range checks {
		state := "ok"
		if !c.ok {
			state = "fail"
			failed = true
		}
		fmt.Fprintf(a.out, "==check\nid=%s\nstate=%s\ntitle=%s\ndetail=%s\n", c.id, state, c.title, c.detail)
	}
	if failed {
		return fmt.Errorf("environment prerequisites failed")
	}
	return nil
}
func (a *app) environment(x []string) error {
	op := arg(x, 0, "catalog")
	id := arg(x, 1, "")
	switch op {
	case "catalog", "readiness", "plan":
		mode := "phone"
		if exists(a.p("run/desktop-mode")) {
			mode = "desktop"
		}
		running := "no"
		if a.running() {
			running = "yes"
		}
		fmt.Fprintf(a.out, "==meta\nmode=%s\nguest_running=%s\ndistro=%s\nguest_root=%s\n", mode, running, a.currentDistro(), a.guestRoot())
		if op == "plan" {
			m, e := a.environmentManifest(id)
			if e != nil {
				return e
			}
			_ = a.environmentRecord(m)
			_ = a.environmentChecks()
			pkgs, _ := a.environmentPackages(m)
			for _, p := range pkgs {
				fmt.Fprintf(a.out, "==package\nname=%s\nstate=unknown\n", p)
			}
			return nil
		}
		paths, _ := filepath.Glob(filepath.Join(env("AURORA_ENV_SESSIONS", a.p("etc/sessions")), "*.session"))
		for _, p := range paths {
			if e := a.environmentRecord(fields(p)); e != nil {
				return e
			}
		}
		return nil
	case "status":
		fmt.Fprintln(a.out, "==state")
		if exists(a.p("run/env.state")) {
			fmt.Fprintln(a.out, read(a.p("run/env.state")))
		} else {
			fmt.Fprintln(a.out, "running=no\nstate=none\nstep_index=0\nstep_total=6")
		}
		for _, line := range strings.Split(read(a.p("run/env.steps")), "\n") {
			id, title, ok := strings.Cut(line, "|")
			if ok {
				fmt.Fprintf(a.out, "==step\nid=%s\ntitle=%s\n%s\n", id, title, read(a.p("run/env", id+".state")))
			}
		}
		return nil
	case "log":
		n := intValue(arg(x, 1, "60"))
		if n < 1 || n > 10000 {
			return usage("aurora environment log [1..10000]")
		}
		lines := strings.Split(read(a.p("log/env-install.log")), "\n")
		if len(lines) > n {
			lines = lines[len(lines)-n:]
		}
		fmt.Fprintln(a.out, strings.Join(lines, "\n"))
		return nil
	case "cancel":
		if arg(x, 1, "") == "--now" {
			a.pidSignal("environment", syscall.SIGTERM, "")
		}
		return atomicWrite(a.p("run/env.cancel"), nil, 0600)
	case "reset":
		if a.pidMatch("environment", "") != 0 {
			return fmt.Errorf("environment operation still running")
		}
		for _, p := range []string{"run/env.state", "run/env.checks", "run/env.cancel", "run/env.steps"} {
			_ = os.Remove(a.p(p))
		}
		return os.RemoveAll(a.p("run/env"))
	case "install", "remove":
		if _, e := a.environmentManifest(id); e != nil {
			return e
		}
		if a.pidMatch("environment", "") != 0 {
			return fmt.Errorf("environment operation already running")
		}
		_ = os.Remove(a.p("run/env.cancel"))
		for _, flag := range x[2:] {
			if flag != "--foreground" && flag != "--with-build" {
				return usage("unknown environment flag: " + flag)
			}
		}
		if oneOf("--foreground", x...) {
			return a.environmentRun(op, id)
		}
		return a.spawn("environment", "", op, id)
	}
	return usage("aurora environment catalog|plan ID|install ID|remove ID|status|readiness|cancel|reset|log")
}
func (a *app) environmentRun(action, id string) (err error) {
	unlock, e := a.lock()
	if e != nil {
		return e
	}
	defer unlock()
	m, e := a.environmentManifest(id)
	if e != nil {
		return e
	}
	if e = a.environmentChecks(); e != nil {
		return e
	}
	_ = os.WriteFile(env("AURORA_SETUP_WAKE_LOCK", "/sys/power/wake_lock"), []byte("aurora-env"), 0600)
	defer os.WriteFile(env("AURORA_SETUP_WAKE_UNLOCK", "/sys/power/wake_unlock"), []byte("aurora-env"), 0600)
	state := map[string]string{"running": "yes", "state": "running", "action": action, "env": id, "env_title": m["title"], "started": fmt.Sprint(time.Now().Unix()), "step_total": "6", "distro": a.currentDistro(), "with_build": "no", "runtime_ready": "unknown", "log": a.p("log/env-install.log")}
	steps := "preflight|Check prerequisites\npackages|Update environment packages\nglue|Deliver Aurora integration\nbuild|Check PC-built components\nservices|Enable session services\nverify|Verify environment\n"
	if e = atomicWrite(a.p("run/env.steps"), []byte(steps), 0600); e != nil {
		return e
	}
	finish := func() {
		state["running"] = "no"
		state["finished"] = fmt.Sprint(time.Now().Unix())
		state["state"] = "ok"
		if err != nil {
			state["state"] = "fail"
			state["error"] = err.Error()
		}
		_ = writeFields(a.p("run/env.state"), state)
	}
	defer finish()
	step := func(id string, n int, detail string) error {
		if exists(a.p("run/env.cancel")) {
			return fmt.Errorf("cancelled between package steps")
		}
		state["step"] = id
		state["step_index"] = fmt.Sprint(n)
		state["updated"] = fmt.Sprint(time.Now().Unix())
		if e := writeFields(a.p("run/env.state"), state); e != nil {
			return e
		}
		return writeFields(a.p("run/env", id+".state"), map[string]string{"state": "running", "detail": detail})
	}
	done := func(id, state, detail string) {
		_ = writeFields(a.p("run/env", id+".state"), map[string]string{"state": state, "detail": detail})
	}
	if e = step("preflight", 1, "Preparing guest"); e != nil {
		return e
	}
	if e = a.guestStartLocked(); e != nil {
		return e
	}
	done("preflight", "ok", "Guest running")
	if e = step("packages", 2, "Updating packages"); e != nil {
		return e
	}
	pkgs, e := a.environmentPackages(m)
	if e != nil {
		return e
	}
	state["package_count"] = fmt.Sprint(len(pkgs))
	platform := func(args ...string) error {
		return a.attach(append([]string{"/usr/local/libexec/aurora/aurora-platform"}, args...)...)
	}
	if action == "remove" {
		if len(pkgs) > 0 {
			if e = platform(append([]string{"package-remove"}, pkgs...)...); e != nil {
				return e
			}
		}
	} else if len(pkgs) > 0 {
		if e = platform("package-refresh"); e != nil {
			return e
		}
		for _, group := range commaList(m["packages"]) {
			if exists(a.p("run/env.cancel")) {
				return fmt.Errorf("cancelled between package steps")
			}
			if e = platform("deps", group); e != nil {
				return e
			}
		}
	}
	done("packages", "ok", "Package operation completed")
	if e = step("glue", 3, "Refreshing integration"); e != nil {
		return e
	}
	if e = a.deliverGuest(a.guestRoot()); e != nil {
		return e
	}
	done("glue", "ok", "Integration delivered")
	if e = step("build", 4, "Checking compiled components"); e != nil {
		return e
	}
	done("build", "skip", "Compositor and system artifacts are cross-built on the PC")
	if e = step("services", 5, "Enabling services"); e != nil {
		return e
	}
	if action != "remove" {
		for _, service := range commaList(m["services"]) {
			if !word.MatchString(service) {
				return fmt.Errorf("invalid service name")
			}
			_ = platform("service-enable", service)
		}
	}
	done("services", "ok", "Services checked")
	if e = step("verify", 6, "Checking runtime executables"); e != nil {
		return e
	}
	if e = a.sessionReady(m); e != nil {
		state["runtime_ready"] = "no"
		state["runtime_reason"] = e.Error()
		done("verify", "warn", e.Error())
		state["summary"] = "Packages updated; missing runtime components must be built on the PC"
	} else {
		state["runtime_ready"] = "yes"
		done("verify", "ok", "Runtime executables present")
		state["summary"] = "Environment installed; device qualification is separate"
	}
	return nil
}
