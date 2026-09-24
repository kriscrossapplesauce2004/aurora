package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

type packet struct {
	op             uint32
	status         int32
	id, generation uint64
	deadline       uint32
	response       bool
	payload        []byte
}

func (p packet) encode() ([]byte, error) {
	if len(p.payload) > 16384 {
		return nil, fmt.Errorf("RPC payload exceeds 16 KiB")
	}
	b := make([]byte, 48+len(p.payload))
	le := binary.LittleEndian
	le.PutUint32(b, 0x44544331)
	le.PutUint16(b[4:], 1)
	le.PutUint16(b[6:], 2)
	le.PutUint16(b[8:], 48)
	if p.response {
		le.PutUint16(b[10:], 1)
	}
	le.PutUint32(b[12:], p.op)
	le.PutUint32(b[16:], uint32(p.status))
	le.PutUint32(b[20:], uint32(len(p.payload)))
	le.PutUint64(b[24:], p.id)
	le.PutUint64(b[32:], p.generation)
	le.PutUint32(b[40:], p.deadline)
	copy(b[48:], p.payload)
	return b, nil
}
func decodePacket(b []byte) (packet, error) {
	p := packet{}
	le := binary.LittleEndian
	if len(b) < 48 || len(b) > 16432 || le.Uint32(b) != 0x44544331 || le.Uint16(b[4:]) != 1 || le.Uint16(b[8:]) != 48 || int(le.Uint32(b[20:])) != len(b)-48 || le.Uint32(b[44:]) != 0 || le.Uint16(b[10:]) > 1 {
		return p, fmt.Errorf("invalid RPC packet")
	}
	p.op = le.Uint32(b[12:])
	p.status = int32(le.Uint32(b[16:]))
	p.id = le.Uint64(b[24:])
	p.generation = le.Uint64(b[32:])
	p.deadline = le.Uint32(b[40:])
	p.response = le.Uint16(b[10:]) == 1
	p.payload = append([]byte{}, b[48:]...)
	return p, nil
}
func readPacket(c *net.UnixConn) (packet, error) {
	buf := make([]byte, 16433)
	n, _, flags, _, e := c.ReadMsgUnix(buf, nil)
	if e != nil {
		return packet{}, e
	}
	if flags&(syscall.MSG_TRUNC|syscall.MSG_CTRUNC) != 0 {
		return packet{}, fmt.Errorf("truncated RPC packet")
	}
	return decodePacket(buf[:n])
}
func rpc(path string, p packet) (packet, error) {
	c, e := net.DialUnix("unixpacket", nil, &net.UnixAddr{Name: path, Net: "unixpacket"})
	if e != nil {
		return packet{}, e
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(3 * time.Second))
	b, e := p.encode()
	if e != nil {
		return packet{}, e
	}
	if _, e = c.Write(b); e != nil {
		return packet{}, e
	}
	r, e := readPacket(c)
	if e == nil && (!r.response || r.id != p.id || r.op != p.op) {
		return r, fmt.Errorf("RPC response identity mismatch")
	}
	return r, e
}
func rpcExit(status int32) error {
	codes := map[int32]int{-1: 3, -2: 4, -3: 5, -4: 6, -7: 7, -8: 8, -5: 9, -6: 10, -9: 11}
	if status >= 0 {
		return nil
	}
	return exitError{codes[status], fmt.Sprintf("control request failed (status %d)", status)}
}
func (a *app) controlClient(x []string) error {
	socket := a.p("run/aurorad.sock")
	wait := false
	deadline := uint32(120000)
	var args []string
	for i := 0; i < len(x); i++ {
		switch x[i] {
		case "--root", "--socket", "--deadline":
			k := x[i]
			i++
			if i == len(x) {
				return usage("missing " + k + " value")
			}
			switch k {
			case "--root":
				socket = filepath.Join(x[i], "run/aurorad.sock")
			case "--socket":
				socket = x[i]
			case "--deadline":
				n := intValue(x[i])
				if n < 5 || n > 300 {
					return usage("deadline must be 5..300 seconds")
				}
				deadline = uint32(n * 1000)
			}
		case "--wait":
			wait = true
		case "--json":
		default:
			args = append(args, x[i])
		}
	}
	op := map[string]uint32{"hello": 1, "ping": 2, "status": 3, "doctor": 4, "capabilities": 5, "metrics": 6, "health": 7, "sessions": 9, "mode": 0x100, "recover": 0x102, "ops": 0x103, "cancel": 0x104, "boot-profile": 0x110, "boot-apply": 0x112}[arg(args, 0, "status")]
	if op == 0 {
		return usage("unknown control command")
	}
	payload := arg(args, 1, "")
	if payload != "" {
		switch op {
		case 0x100:
			if !oneOf(payload, "phone", "desktop") {
				return usage("mode phone|desktop")
			}
			op = 0x101
		case 0x110:
			if !oneOf(payload, "phone", "linux-first") {
				return usage("boot-profile phone|linux-first")
			}
			op = 0x111
		case 9:
			op = 0x105
		case 0x103, 0x104:
			if !digits(payload) {
				return usage("operation ID must be numeric")
			}
		default:
			return usage("unexpected control argument")
		}
	}
	p := packet{op: op, id: uint64(time.Now().UnixNano()), deadline: deadline, payload: []byte(payload)}
	r, e := rpc(socket, p)
	if e != nil {
		return exitError{4, e.Error()}
	}
	if !wait || r.status != 1 {
		fmt.Fprintln(a.out, string(r.payload))
		return rpcExit(r.status)
	}
	target := payload
	if op == 0x102 {
		target = "phone"
	}
	if op == 0x112 {
		target = "phone"
		if strings.Contains(string(r.payload), "linux-first") {
			target = "desktop"
		}
	}
	end := time.Now().Add(time.Duration(deadline) * time.Millisecond)
	for time.Now().Before(end) {
		if e = a.sleep(200 * time.Millisecond); e != nil {
			return e
		}
		p.op = 0x100
		p.payload = nil
		r, e = rpc(socket, p)
		if e != nil {
			return e
		}
		var body struct {
			State map[string]any `json:"state"`
		}
		if e = json.Unmarshal(r.payload, &body); e != nil {
			return e
		}
		if body.State["observed"] == target && body.State["step"] == "idle" {
			fmt.Fprintln(a.out, string(r.payload))
			return nil
		}
		if body.State["observed"] == "recovery" {
			return exitError{8, string(r.payload)}
		}
	}
	return exitError{5, "transition deadline exceeded"}
}

type controlServer struct {
	a                                  *app
	mu                                 sync.Mutex
	allow, busy                        bool
	desired, observed, step, lastError string
	id, generation                     uint64
	cancel                             context.CancelFunc
}

func (s *controlServer) state() map[string]any {
	return map[string]any{"schema": 1, "generation": s.generation, "boot_id": bootID(), "desired": s.desired, "observed": s.observed, "transition_id": s.id, "step": s.step, "last_error": s.lastError, "completed_steps": []string{}}
}
func (s *controlServer) save() error {
	b, e := json.Marshal(s.state())
	if e != nil {
		return e
	}
	return atomicWrite(s.a.p("state/go-control.json"), b, 0600)
}
func (s *controlServer) status() map[string]any {
	a := s.a
	live := "phone"
	if exists(a.p("run/desktop-mode")) {
		live = "desktop"
	}
	sf := a.property("init.svc.surfaceflinger")
	guest := "stopped"
	if a.running() {
		guest = "running"
	}
	var report any
	_ = json.Unmarshal([]byte(read(a.p("run/guest-health.json"))), &report)
	return map[string]any{"protocol": "1.2", "observe_only": !s.allow, "state": s.state(), "live_observed": live, "surfaceflinger": sf, "guest_report": report, "memory": fieldsColon("/proc/meminfo"), "direct_audio": map[string]any{"phase": fields(a.p("run/audio-owner.state"))["phase"], "profile": fields(a.p("etc/audio-owner.conf"))["profile"], "probe": true, "owner": true}, "compat": map[string]string{"uid": "0", "kernel": read("/proc/sys/kernel/osrelease"), "sf": sf, "mode": live, "guest": guest}, "presenter": map[string]bool{"socket_ready": exists("/data/user_de/0/com.aurora.companion/files/presenter.sock")}}
}
func (s *controlServer) start(target string, p packet) (int32, any) {
	if !s.allow {
		return -1, map[string]string{"error": "daemon is observe-only"}
	}
	if s.busy {
		if s.desired == target {
			return 1, s.status()
		}
		return -4, map[string]string{"error": "conflicting transition in progress"}
	}
	s.busy = true
	s.desired = target
	s.step = "starting"
	s.generation++
	s.id = p.id
	s.lastError = ""
	if e := s.save(); e != nil {
		s.busy = false
		return -9, map[string]string{"error": e.Error()}
	}
	deadline := p.deadline
	if deadline < 5000 || deadline > 300000 {
		deadline = 120000
	}
	ctx, cancel := context.WithTimeout(s.a.ctx, time.Duration(deadline)*time.Millisecond)
	s.cancel = cancel
	q := *s.a
	q.ctx = ctx
	go func() {
		var e error
		if target == "desktop" {
			e = q.desktopOn()
		} else {
			e = q.desktopOff(true)
		}
		cancel()
		s.mu.Lock()
		defer s.mu.Unlock()
		s.busy = false
		s.step = "idle"
		s.observed = target
		if e != nil {
			s.lastError = e.Error()
			s.observed = "recovery"
			s.step = "failed"
		}
		_ = s.save()
		entry := map[string]any{"schema": 2, "transition_id": s.id, "generation": s.generation, "target": target, "result": s.observed, "error": s.lastError, "timestamp_ms": time.Now().UnixMilli()}
		b, _ := json.Marshal(entry)
		f, err := os.OpenFile(s.a.p("state/operations.jsonl"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
		if err == nil {
			_, _ = f.Write(append(b, '\n'))
			_ = f.Sync()
			_ = f.Close()
		}
	}()
	return 1, s.status()
}
func peerAllowed(guest bool, uid uint32) bool { return uid == 0 || (guest && uid == 1000) }
func (s *controlServer) handle(p packet, guest bool, uid uint32) packet {
	s.mu.Lock()
	defer s.mu.Unlock()
	r := packet{op: p.op, id: p.id, generation: s.generation, response: true}
	var body any = map[string]bool{"ok": true}
	fail := func(code int32, msg string) { r.status = code; body = map[string]string{"error": msg} }
	if p.response || !peerAllowed(guest, uid) {
		fail(-7, "peer is not authorized")
	} else {
		switch p.op {
		case 1:
			body = map[string]any{"protocol": "1.2", "max_payload": 16384}
		case 2:
		case 3, 0x100:
			body = s.status()
		case 4:
			body = map[string]any{"ok": s.observed != "recovery", "state": s.state(), "checks": map[string]bool{"guest_tools": executable(s.a.p("guest-tools/aurora")), "emergency_phone_restore": executable(s.a.p("bin/aurora")), "binderfs": exists("/dev/binderfs"), "pid_namespace": exists("/proc/self/ns/pid")}}
		case 5:
			body = map[string]any{"operations": []string{"hello", "ping", "status", "doctor", "capabilities", "metrics", "health", "sessions", "mode-get", "mode-set", "mode-recover", "op-query", "op-cancel", "session-validate", "boot-profile-get", "boot-profile-set", "boot-profile-apply", "guest-report"}, "guest_endpoint": guest, "transitions": s.allow, "structured_state": true, "authenticated_peer_credentials": true, "presenter_protocol": 1}
		case 6:
			body = map[string]any{"schema": 1, "state": s.state(), "memory": fieldsColon("/proc/meminfo"), "pressure": map[string]string{"cpu": read("/proc/pressure/cpu"), "memory": read("/proc/pressure/memory"), "io": read("/proc/pressure/io")}}
		case 7:
			body = map[string]any{"schema": 1, "state": s.state(), "guest_report": read(s.a.p("run/guest-health.json"))}
		case 9, 0x105:
			items := []map[string]string{}
			paths, _ := filepath.Glob(s.a.p("etc/sessions/*.session"))
			for _, path := range paths {
				m := fields(path)
				if p.op == 0x105 && m["id"] != string(p.payload) {
					continue
				}
				items = append(items, m)
			}
			body = map[string]any{"schema": 1, "sessions": items}
		case 0x101, 0x102:
			target := string(p.payload)
			if p.op == 0x102 {
				target = "phone"
			}
			if !oneOf(target, "phone", "desktop") {
				fail(-6, "invalid mode")
			} else if guest && target != "phone" {
				fail(-7, "guest may only restore phone mode")
			} else {
				r.status, body = s.start(target, p)
			}
		case 0x103:
			lines := strings.Split(read(s.a.p("state/operations.jsonl")), "\n")
			if len(lines) > 128 {
				lines = lines[len(lines)-128:]
			}
			entries := []json.RawMessage{}
			for _, line := range lines {
				if json.Valid([]byte(line)) {
					entries = append(entries, json.RawMessage(line))
				}
			}
			body = map[string]any{"schema": 2, "active": s.state(), "operations": entries}
		case 0x104:
			if guest {
				fail(-7, "cancellation requires admin endpoint")
			} else if s.cancel != nil && s.busy {
				s.cancel()
				body = map[string]string{"message": "cancellation requested; recovery remains active"}
			}
		case 0x110:
			body = map[string]string{"profile": fields(s.a.p("state/boot-profile"))["desired"]}
		case 0x111:
			if guest {
				fail(-7, "boot profile requires admin endpoint")
			} else if e := s.a.boot([]string{string(p.payload)}); e != nil {
				fail(-6, e.Error())
			}
		case 0x112:
			if guest {
				fail(-7, "boot apply requires admin endpoint")
			} else {
				target := "phone"
				if fields(s.a.p("state/boot-profile"))["desired"] == "linux-first" {
					target = "desktop"
				}
				r.status, body = s.start(target, p)
			}
		case 0x200:
			if !guest {
				fail(-7, "reports require guest endpoint")
			} else if !json.Valid(p.payload) || len(p.payload) > 8192 || len(p.payload) == 0 || p.payload[0] != '{' {
				fail(-6, "invalid health report")
			} else if e := atomicWrite(s.a.p("run/guest-health.json"), p.payload, 0640); e != nil {
				fail(-9, e.Error())
			}
		case 0x201:
			if !guest || !oneOf(string(p.payload), "reboot", "poweroff") {
				fail(-7, "invalid power request")
			} else {
				action := string(p.payload)
				go func() {
					_ = s.a.sleep(100 * time.Millisecond)
					if action == "poweroff" {
						_ = s.a.run("svc", "power", "shutdown")
					} else {
						_ = s.a.run("svc", "power", "reboot")
					}
				}()
			}
		default:
			fail(-6, "unknown operation")
		}
	}
	r.payload, _ = json.Marshal(body)
	if len(r.payload) > 16384 {
		r.status = -9
		r.payload = []byte(`{"error":"response exceeds protocol limit"}`)
	}
	return r
}
func (a *app) daemon(allow bool) error {
	for _, p := range []string{"run/control", "state"} {
		if e := os.MkdirAll(a.p(p), 0750); e != nil {
			return e
		}
	}
	lock, e := os.OpenFile(a.p("run/aurorad.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		return e
	}
	defer lock.Close()
	if e = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); e != nil {
		return fmt.Errorf("control daemon already running")
	}
	s := &controlServer{a: a, allow: allow, desired: "phone", observed: "phone", step: "idle"}
	if exists(a.p("run/desktop-mode")) {
		s.desired = "desktop"
		s.observed = "desktop"
	}
	var previous map[string]any
	if json.Unmarshal([]byte(read(a.p("state/go-control.json"))), &previous) == nil {
		if g, ok := previous["generation"].(float64); ok {
			s.generation = uint64(g)
		}
		if previous["step"] != "idle" && previous["boot_id"] == bootID() {
			s.observed = "recovery"
			s.step = "interrupted"
		}
	}
	if e = s.save(); e != nil {
		return e
	}
	var listeners []*net.UnixListener
	defer func() {
		for _, l := range listeners {
			l.Close()
		}
	}()
	for _, guest := range []bool{false, true} {
		path := a.p("run/aurorad.sock")
		if guest {
			path = a.p("run/control/aurorad.sock")
			_ = os.Chown(filepath.Dir(path), 0, 1000)
			_ = os.Chmod(filepath.Dir(path), 0770)
		}
		_ = os.Remove(path)
		l, e := net.ListenUnix("unixpacket", &net.UnixAddr{Name: path, Net: "unixpacket"})
		if e != nil {
			return e
		}
		listeners = append(listeners, l)
		_ = os.Chown(path, 0, 1000)
		if e = os.Chmod(path, 0660); e != nil {
			return e
		}
		go func(l *net.UnixListener, guest bool) {
			limit := make(chan struct{}, 16)
			for {
				c, e := l.AcceptUnix()
				if e != nil {
					return
				}
				select {
				case limit <- struct{}{}:
					go func() {
						defer func() { <-limit; c.Close() }()
						_ = c.SetDeadline(time.Now().Add(3 * time.Second))
						raw, e := c.SyscallConn()
						if e != nil {
							return
						}
						var cred *syscall.Ucred
						var credErr error
						e = raw.Control(func(fd uintptr) {
							cred, credErr = syscall.GetsockoptUcred(int(fd), syscall.SOL_SOCKET, syscall.SO_PEERCRED)
						})
						if e != nil || credErr != nil || cred == nil {
							return
						}
						p, e := readPacket(c)
						if e != nil {
							return
						}
						r := s.handle(p, guest, cred.Uid)
						b, e := r.encode()
						if e == nil {
							_, _ = c.Write(b)
						}
					}()
				default:
					c.Close()
				}
			}
		}(l, guest)
	}
	<-a.ctx.Done()
	s.mu.Lock()
	if s.cancel != nil {
		s.cancel()
	}
	s.mu.Unlock()
	return nil
}
func (a *app) guestAgent(x []string) error {
	op := arg(x, 0, "status")
	socket := filepath.Join(env("AURORA_CONTROL", "/mnt/aurora-control"), "aurorad.sock")
	request := func(op uint32, payload []byte) error {
		r, e := rpc(socket, packet{op: op, id: uint64(time.Now().UnixNano()), deadline: 120000, payload: payload})
		if e != nil {
			return e
		}
		fmt.Fprintln(a.out, string(r.payload))
		return rpcExit(r.status)
	}
	report := func() error {
		b, _ := json.Marshal(map[string]any{"schema": 1, "boot_id": bootID(), "monotonic_ms": uptimeMillis(), "uid": os.Getuid(), "wayland": exists("/run/user/1000/wayland-0"), "session_bus": exists("/run/user/1000/bus"), "memory_pressure": read("/proc/pressure/memory")})
		return request(0x200, b)
	}
	switch op {
	case "serve":
		for a.ctx.Err() == nil {
			if e := report(); e != nil {
				fmt.Fprintln(a.err, "guest health report:", e)
			}
			_ = a.sleep(10 * time.Second)
		}
		return nil
	case "report":
		return report()
	case "ping":
		return request(2, nil)
	case "status":
		return request(3, nil)
	case "doctor":
		return request(4, nil)
	case "signal":
		action := arg(x, 1, "")
		if action == "exit" {
			e := request(0x101, []byte("phone"))
			var ee exitError
			if errors.As(e, &ee) && oneOf(strconv.Itoa(ee.code), "3", "4") {
				return atomicWrite(filepath.Join(env("AURORA_CONTROL", "/mnt/aurora-control"), "exit"), nil, 0600)
			}
			return e
		}
		if oneOf(action, "reboot", "poweroff") {
			return request(0x201, []byte(action))
		}
	case "recover":
		return request(0x102, []byte("phone"))
	}
	return usage("guest agent ping|status|doctor|report|serve|signal exit|reboot|poweroff|recover")
}
func uptimeMillis() int64 {
	s := strings.Fields(read("/proc/uptime"))
	if len(s) == 0 {
		return 0
	}
	n, _ := strconv.ParseFloat(s[0], 64)
	return int64(n * 1000)
}
