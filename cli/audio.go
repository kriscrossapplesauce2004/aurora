package main

import (
	"context"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type audioHolder struct {
	PID     int    `json:"pid"`
	FD      int    `json:"fd"`
	Comm    string `json:"comm"`
	Cmdline string `json:"cmdline"`
	Target  string `json:"target"`
}

func audioHolders(root string) ([]audioHolder, error) {
	out := []audioHolder{}
	ps, e := os.ReadDir(filepath.Join(root, "proc"))
	if e != nil {
		return nil, e
	}
	for _, p := range ps {
		if !digits(p.Name()) {
			continue
		}
		base := filepath.Join(root, "proc", p.Name())
		fds, e := os.ReadDir(filepath.Join(base, "fd"))
		if e != nil {
			if os.IsNotExist(e) {
				continue
			}
			return nil, fmt.Errorf("cannot inspect audio holders for pid %s: %w", p.Name(), e)
		}
		for _, f := range fds {
			target, e := os.Readlink(filepath.Join(base, "fd", f.Name()))
			if e == nil && strings.HasPrefix(target, "/dev/snd/") {
				b, _ := os.ReadFile(filepath.Join(base, "cmdline"))
				out = append(out, audioHolder{intValue(p.Name()), intValue(f.Name()), read(filepath.Join(base, "comm")), strings.ReplaceAll(string(b), "\x00", " "), target})
			}
		}
	}
	return out, nil
}
func (a *app) audioProbe(x []string) error {
	root := "/"
	unowned := false
	for i := 0; i < len(x); i++ {
		switch x[i] {
		case "--root":
			i++
			if i >= len(x) {
				return usage("missing probe root")
			}
			root = x[i]
		case "--require-unowned":
			unowned = true
		case "--json":
		default:
			return usage("audio probe [--root PATH] [--require-unowned]")
		}
	}
	holders, e := audioHolders(root)
	if e != nil {
		return e
	}
	nodes := []map[string]any{}
	paths, _ := filepath.Glob(filepath.Join(root, "dev/snd/*"))
	for _, p := range paths {
		s, e := os.Lstat(p)
		if e != nil {
			continue
		}
		st, ok := s.Sys().(*syscall.Stat_t)
		if !ok {
			continue
		}
		kind := "other"
		name := filepath.Base(p)
		for prefix, t := range map[string]string{"controlC": "control", "pcmC": "pcm", "comprC": "compress", "hwC": "hardware-dependent", "seq": "sequencer", "timer": "timer"} {
			if strings.HasPrefix(name, prefix) {
				kind = t
				break
			}
		}
		nodes = append(nodes, map[string]any{"path": "/dev/snd/" + name, "type": kind, "mode": st.Mode & 07777, "uid": st.Uid, "gid": st.Gid, "major": (st.Rdev>>8)&0xfff | (st.Rdev>>32)&0xfffff000, "minor": st.Rdev&0xff | (st.Rdev>>12)&0xffffff00})
	}
	proc := map[string]string{}
	for _, name := range []string{"version", "cards", "devices", "pcm", "modules", "timers"} {
		if b, e := os.ReadFile(filepath.Join(root, "proc/asound", name)); e == nil {
			proc[name] = string(b)
		}
	}
	if e = json.NewEncoder(a.out).Encode(map[string]any{"schema": 1, "root": root, "nodes": nodes, "holders": holders, "holder_count": len(holders), "proc": proc}); e != nil {
		return e
	}
	if unowned && len(holders) > 0 {
		return exitError{3, "ALSA hardware still has open holders"}
	}
	return nil
}

type audioProfile struct {
	id, hash, card  string
	services, nodes []string
	timeout         time.Duration
}

func (a *app) audioProfile() (audioProfile, error) {
	p := audioProfile{timeout: 5 * time.Second}
	b, e := os.ReadFile(a.p("etc/audio-owner.conf"))
	if e != nil {
		return p, e
	}
	h := fnv.New64a()
	_, _ = h.Write(b)
	p.hash = strconv.FormatUint(h.Sum64(), 10)
	schema := ""
	for _, s := range strings.Split(string(b), "\n") {
		s = strings.TrimSpace(s)
		if s == "" || strings.HasPrefix(s, "#") {
			continue
		}
		k, v, ok := strings.Cut(s, "=")
		k = strings.TrimSpace(k)
		v = strings.TrimSpace(v)
		if !ok {
			return p, fmt.Errorf("malformed audio profile")
		}
		switch k {
		case "schema":
			schema = v
		case "profile":
			p.id = v
		case "card_contains":
			p.card = v
		case "service":
			if !word.MatchString(v) {
				return p, fmt.Errorf("invalid audio service")
			}
			p.services = append(p.services, v)
		case "required_node":
			if !strings.HasPrefix(v, "/dev/snd/") || filepath.Clean(v) != v {
				return p, fmt.Errorf("invalid ALSA node")
			}
			p.nodes = append(p.nodes, v)
		case "timeout_ms":
			n := intValue(v)
			if n < 250 || n > 120000 {
				return p, fmt.Errorf("invalid audio deadline")
			}
			p.timeout = time.Duration(n) * time.Millisecond
		default:
			return p, fmt.Errorf("unknown audio profile key %s", k)
		}
	}
	if schema != "1" || !word.MatchString(p.id) || p.card == "" || len(p.services) == 0 {
		return p, fmt.Errorf("incomplete audio profile")
	}
	return p, nil
}
func repeated(p, key string) []string {
	var out []string
	for _, s := range strings.Split(read(p), "\n") {
		k, v, ok := strings.Cut(s, "=")
		if ok && k == key {
			out = append(out, v)
		}
	}
	return out
}
func (a *app) audioOwner(op string, apply bool) error {
	p, e := a.audioProfile()
	if e != nil {
		return e
	}
	journal := a.p("run/audio-owner.state")
	m := fields(journal)
	services := repeated(journal, "service")
	marker := a.p("run/control/audio-claimed")
	if op == "status" {
		return json.NewEncoder(a.out).Encode(m)
	}
	if !oneOf(op, "claim", "restore", "recover") {
		return usage("audio owner claim|restore|recover|status [--apply]")
	}
	if !apply {
		return json.NewEncoder(a.out).Encode(map[string]any{"action": op, "apply": false, "phase": m["phase"]})
	}
	if e = os.MkdirAll(a.p("run"), 0755); e != nil {
		return e
	}
	f, e := os.OpenFile(a.p("run/audio-owner.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		return e
	}
	defer f.Close()
	if e = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); e != nil {
		return fmt.Errorf("audio ownership transaction busy: %w", e)
	}
	root := env("AURORA_AUDIO_PROBE_ROOT", "/")
	bid := read(filepath.Join(root, "proc/sys/kernel/random/boot_id"))
	getprop := env("AURORA_GETPROP", "getprop")
	setprop := env("AURORA_SETPROP", "setprop")
	property := func(s string) string {
		ctx, cancel := context.WithTimeout(a.ctx, p.timeout)
		defer cancel()
		q := *a
		q.ctx = ctx
		v, _ := q.output(getprop, "init.svc."+s)
		return v
	}
	set := func(verb, s string) error {
		ctx, cancel := context.WithTimeout(a.ctx, p.timeout)
		defer cancel()
		q := *a
		q.ctx = ctx
		if e := q.quiet(setprop, "ctl."+verb, s); e != nil {
			return e
		}
		wanted := "stopped"
		if verb == "start" {
			wanted = "running"
		}
		return q.wait(p.timeout, func() bool { return property(s) == wanted })
	}
	save := func(phase string, err error) error {
		m["phase"] = phase
		m["error"] = ""
		if err != nil {
			m["error"] = strings.ReplaceAll(err.Error(), "\n", " ")
		}
		var b strings.Builder
		for _, k := range []string{"schema", "generation", "owner_pid", "owner_started_ms", "phase", "boot_id", "profile", "profile_hash", "error"} {
			fmt.Fprintf(&b, "%s=%s\n", k, m[k])
		}
		for _, s := range services {
			fmt.Fprintf(&b, "service=%s\n", s)
		}
		return atomicWrite(journal, []byte(b.String()), 0640)
	}
	unowned := func() bool { h, e := audioHolders(root); return e == nil && len(h) == 0 }
	restore := func(requireRelease bool) error {
		if e := save("restoring", nil); e != nil {
			return e
		}
		if e := os.Remove(marker); e != nil && !os.IsNotExist(e) {
			return e
		}
		if requireRelease {
			if e := a.wait(p.timeout, unowned); e != nil {
				_ = save("restore-failed", e)
				return e
			}
		}
		for i := len(services) - 1; i >= 0; i-- {
			s, state, ok := strings.Cut(services[i], ":")
			if !ok || !oneOf(s, p.services...) {
				return fmt.Errorf("invalid journal service")
			}
			if oneOf(state, "running", "restarting") {
				if e := set("start", s); e != nil {
					_ = save("restore-failed", e)
					return e
				}
			}
		}
		return save("restored", nil)
	}
	if op != "claim" {
		if m["profile"] != p.id || m["profile_hash"] != p.hash || m["schema"] != "1" {
			return fmt.Errorf("journal/profile mismatch; refusing restore")
		}
		if m["boot_id"] != bid {
			return fmt.Errorf("audio journal belongs to a previous boot")
		}
		if m["phase"] == "restored" {
			return nil
		}
		return restore(oneOf(m["phase"], "claimed", "restoring", "restore-failed") || exists(marker))
	}
	if !strings.Contains(read(filepath.Join(root, "proc/asound/cards")), p.card) {
		return fmt.Errorf("ALSA topology does not match %s", p.id)
	}
	for _, node := range p.nodes {
		s, e := os.Stat(filepath.Join(root, node))
		if e != nil || s.Mode()&os.ModeCharDevice == 0 {
			return fmt.Errorf("required ALSA node missing: %s", node)
		}
	}
	if m["phase"] != "" && !oneOf(m["phase"], "restored", "rolled-back", "stale-after-reboot") {
		if m["phase"] == "claimed" && m["profile_hash"] == p.hash && m["boot_id"] == bid {
			return atomicWrite(marker, []byte("schema=1\nprofile="+p.id+"\nboot_id="+bid+"\n"), 0640)
		}
		return fmt.Errorf("unfinished audio transaction; recover first")
	}
	generation := intValue(m["generation"]) + 1
	m = map[string]string{"schema": "1", "generation": strconv.Itoa(generation), "owner_pid": fmt.Sprint(os.Getpid()), "owner_started_ms": fmt.Sprint(time.Now().UnixMilli()), "boot_id": bid, "profile": p.id, "profile_hash": p.hash}
	services = nil
	for _, s := range p.services {
		state := property(s)
		if !oneOf(state, "running", "restarting", "stopped") {
			return fmt.Errorf("cannot snapshot audio service %s: %s", s, state)
		}
		services = append(services, s+":"+state)
	}
	if e = save("quiescing", nil); e != nil {
		return e
	}
	claimed := false
	defer func() {
		if !claimed {
			q := *a
			q.ctx = context.Background()
			old := a.ctx
			a.ctx = q.ctx
			_ = restore(false)
			a.ctx = old
		}
	}()
	var settled time.Time
	e = a.wait(p.timeout, func() bool {
		all := true
		for _, s := range p.services {
			if property(s) != "stopped" {
				all = false
				_ = set("stop", s)
			}
		}
		if !all {
			settled = time.Time{}
			return false
		}
		if settled.IsZero() {
			settled = time.Now()
		}
		return time.Since(settled) >= 500*time.Millisecond
	})
	if e != nil {
		return e
	}
	if !unowned() {
		return fmt.Errorf("ALSA hardware still has open holders")
	}
	if e = save("claimed", nil); e != nil {
		return e
	}
	if e = atomicWrite(marker, []byte("schema=1\nprofile="+p.id+"\nboot_id="+bid+"\n"), 0640); e != nil {
		return e
	}
	claimed = true
	return nil
}

const speakerRoute = "QUAT_MI2S_RX Audio Mixer MultiMedia1"

func (a *app) mixerState() (map[string]string, error) {
	route, e := a.output("tinymix", speakerRoute)
	if e != nil {
		return nil, e
	}
	f := strings.Fields(route)
	if len(f) < 2 || !oneOf(f[len(f)-1], "On", "Off") || !oneOf(f[len(f)-2], "On", "Off") {
		return nil, fmt.Errorf("cannot parse speaker route")
	}
	m := map[string]string{"schema": "1", "route_left": "0", "route_right": "0"}
	if f[len(f)-2] == "On" {
		m["route_left"] = "1"
	}
	if f[len(f)-1] == "On" {
		m["route_right"] = "1"
	}
	s, e := a.output("tinymix", "TFA_CHIP_SELECTOR")
	f = strings.Fields(s)
	if e != nil || len(f) < 2 || !oneOf(f[1], "0", "1", "2", "3") {
		return nil, fmt.Errorf("cannot parse speaker selector")
	}
	m["selector"] = f[1]
	return m, nil
}
func (a *app) audioRoute(op string) error {
	p := a.p("run/audio-route.state")
	if op == "claim" {
		if exists(p) && exists(a.p("run/control/audio-claimed")) {
			return nil
		}
		m, e := a.mixerState()
		if e != nil {
			return e
		}
		if e = writeFields(p, m); e != nil {
			return e
		}
		if e = a.audioOwner("claim", true); e != nil {
			return e
		}
		if e = a.quiet("tinymix", speakerRoute, "1"); e == nil {
			e = a.quiet("tinymix", "TFA_CHIP_SELECTOR", "2")
		}
		if e == nil {
			m, e = a.mixerState()
			if e == nil && (m["route_left"] != "1" || m["selector"] != "2") {
				e = fmt.Errorf("speaker route did not apply")
			}
		}
		if e != nil {
			_ = a.audioOwner("restore", true)
			return e
		}
		return nil
	}
	if op != "restore" {
		return usage("audio route claim|restore")
	}
	m := fields(p)
	if !oneOf(m["route_left"], "0", "1") || !oneOf(m["route_right"], "0", "1") || !oneOf(m["selector"], "0", "1", "2", "3") {
		return fmt.Errorf("invalid audio route journal")
	}
	if e := a.audioOwner("restore", true); e != nil {
		return e
	}
	if e := a.wait(5*time.Second, func() bool {
		n, e := a.mixerState()
		return e == nil && n["selector"] == m["selector"] && n["route_left"] == m["route_left"] && n["route_right"] == m["route_right"]
	}); e != nil {
		return e
	}
	return os.Remove(p)
}
func (a *app) audio(x []string) error {
	switch arg(x, 0, "status") {
	case "status":
		if len(x) == 0 {
			return a.audioProbe(nil)
		}
		return a.audioProbe(x[1:])
	case "claim", "restore":
		return a.audioRoute(x[0])
	case "smoke":
		return a.audioSmoke(x[1:])
	}
	return usage("aurora audio status|claim|restore|smoke")
}
func (a *app) audioSmoke(x []string) (err error) {
	tone := arg(x, 0, "/home/aurora/aurora-audio-tone.wav")
	if !filepath.IsAbs(tone) {
		return usage("tone must be an absolute guest path")
	}
	if !exists(filepath.Join(a.guestRoot(), tone)) {
		return fmt.Errorf("test tone missing")
	}
	if err = a.audioRoute("claim"); err != nil {
		return err
	}
	defer func() {
		q := *a
		q.ctx = context.Background()
		e := q.audioRoute("restore")
		if err == nil {
			err = e
		}
	}()
	return a.attach("/usr/bin/aplay", "-q", "-D", "hw:0,0", tone)
}
