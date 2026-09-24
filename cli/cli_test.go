package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"encoding/binary"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func testApp(t *testing.T, side string) (*app, *bytes.Buffer) {
	t.Helper()
	b := new(bytes.Buffer)
	return &app{root: t.TempDir(), side: side, out: b, err: b, ctx: context.Background()}, b
}
func put(t *testing.T, p, s string, mode os.FileMode) {
	t.Helper()
	if e := atomicWrite(p, []byte(s), mode); e != nil {
		t.Fatal(e)
	}
}
func TestHelpHasNoSideEffects(t *testing.T) {
	for _, side := range []string{"linux", "android"} {
		a, b := testApp(t, side)
		before, _ := os.ReadDir(a.root)
		for _, c := range commands() {
			if c.side != "" && c.side != side {
				continue
			}
			if e := a.dispatch(append(strings.Fields(c.path), "--help")); e != nil {
				t.Fatal(e)
			}
			if !strings.Contains(b.String(), c.description) {
				t.Fatalf("missing description for %s", c.path)
			}
			b.Reset()
		}
		after, _ := os.ReadDir(a.root)
		if len(before) != len(after) {
			t.Fatal("help wrote runtime state")
		}
	}
}
func TestUnknownCommandFails(t *testing.T) {
	a, _ := testApp(t, "linux")
	if a.dispatch([]string{"wibble", "on"}) == nil {
		t.Fatal("unknown command accepted")
	}
}
func TestPacketWireCompatibility(t *testing.T) {
	p := packet{op: 0x101, id: 0x0102030405060708, generation: 9, deadline: 45000, payload: []byte("phone")}
	b, e := p.encode()
	if e != nil {
		t.Fatal(e)
	}
	if len(b) != 53 || binary.LittleEndian.Uint32(b) != 0x44544331 || binary.LittleEndian.Uint64(b[24:]) != p.id || string(b[48:]) != "phone" {
		t.Fatal("wire layout changed")
	}
	q, e := decodePacket(b)
	if e != nil || q.op != p.op || q.id != p.id {
		t.Fatal(q, e)
	}
	for _, offset := range []int{0, 4, 8, 10, 20, 44} {
		bad := append([]byte{}, b...)
		bad[offset] = 255
		if _, e = decodePacket(bad); e == nil {
			t.Fatalf("accepted corrupt header byte %d", offset)
		}
	}
	if _, e = decodePacket(append(b, 0)); e == nil {
		t.Fatal("accepted trailing data")
	}
	p.payload = make([]byte, 16385)
	if _, e = p.encode(); e == nil {
		t.Fatal("accepted oversized payload")
	}
}
func TestGuestCapabilityBoundary(t *testing.T) {
	a, _ := testApp(t, "android")
	s := &controlServer{a: a, observed: "phone", desired: "phone", step: "idle"}
	for _, tc := range []struct {
		guest bool
		uid   uint32
		op    uint32
		body  string
		code  int32
	}{{true, 1000, 0x101, "desktop", -7}, {true, 1000, 0x111, "linux-first", -7}, {true, 1000, 0x104, "", -7}, {false, 1000, 2, "", -7}, {true, 1001, 2, "", -7}, {true, 1000, 2, "", 0}, {true, 1000, 0x101, "phone", -1}, {false, 0, 0x200, "{}", -7}, {true, 1000, 0x200, "[]", -6}, {true, 1000, 0x200, "{}", 0}} {
		r := s.handle(packet{op: tc.op, payload: []byte(tc.body)}, tc.guest, tc.uid)
		if r.status != tc.code {
			t.Fatalf("%+v: got %d %s", tc, r.status, r.payload)
		}
	}
}
func TestProfileRejectsCodeAndTraversal(t *testing.T) {
	a, _ := testApp(t, "android")
	for _, line := range []string{"AURORA_WIFI_IFACE=$(touch /tmp/pwn)", "AURORA_BACKLIGHT_PATH=/sys/../../etc/passwd", "AURORA_PANEL_WIDTH=-1", "AURORA_PANEL_REFRESH_MHZ=1", "UNKNOWN=x"} {
		put(t, a.p("etc/device.conf"), line+"\n", 0600)
		if _, e := a.loadProfile(); e == nil {
			t.Fatal("accepted", line)
		}
	}
}
func TestSessionAlternativeAndPreferenceOnly(t *testing.T) {
	a, _ := testApp(t, "android")
	put(t, a.p("guest/usr/bin/phosh"), "fixture", 0755)
	put(t, a.p("guest/usr/local/bin/phoc"), "fixture", 0755)
	put(t, a.p("etc/sessions/phosh.session"), "id=phosh\nqualification=qualified\ncompositor=/usr/local/bin/phoc\nshell=/usr/libexec/phosh|/usr/bin/phosh\nrequired_binaries=/usr/libexec/phosh|/usr/bin/phosh\n", 0644)
	if e := a.session([]string{"select", "phosh"}); e != nil {
		t.Fatal(e)
	}
	if got := a.selected()["shell"]; got != "/usr/bin/phosh" {
		t.Fatal(got)
	}
	if exists(a.p("run/desktop-mode")) {
		t.Fatal("selection switched display ownership")
	}
	if e := a.session([]string{"select", "../../bad"}); e == nil {
		t.Fatal("accepted traversal")
	}
}
func TestLXCConfigurationHasOneHostBinderPerTarget(t *testing.T) {
	a, _ := testApp(t, "android")
	host := t.TempDir()
	t.Setenv("AURORA_HOST_ROOT", host)
	for _, p := range []string{"/dev/binder", "/dev/binderfs/binder", "/dev/hwbinder", "/dev/binderfs/binder-control", "/dev/kgsl-3d0"} {
		put(t, filepath.Join(host, p), "", 0600)
	}
	base := a.p("lxc/config.base")
	put(t, base, "lxc.rootfs.path = dir:/old\nlxc.mount.entry = /dev/binder dev/binder none bind 0 0\nlxc.mount.entry = /dev/kgsl-3d0 dev/kgsl-3d0 none bind 0 0\n", 0600)
	if e := a.generateLXC(map[string]string{}, base, a.p("lxc/config")); e != nil {
		t.Fatal(e)
	}
	s := read(a.p("lxc/config"))
	if strings.Count(s, " dev/binder none ") != 1 || strings.Count(s, " dev/kgsl-3d0 ") != 1 || strings.Contains(s, "dir:/old") {
		t.Fatal(s)
	}
	stat, _ := os.Stat(a.p("lxc/config"))
	if stat.Mode().Perm() != 0600 {
		t.Fatal(stat.Mode())
	}
}
func TestPIDIdentityChecksGenerationAndBoot(t *testing.T) {
	a, _ := testApp(t, "android")
	if e := a.pidWrite("test", os.Getpid(), "42"); e != nil {
		t.Fatal(e)
	}
	if a.pidMatch("test", "42") != os.Getpid() || a.pidMatch("test", "43") != 0 {
		t.Fatal("generation mismatch")
	}
	m := fields(a.p("run/test.pid"))
	m["boot_id"] = "different"
	if e := writeFields(a.p("run/test.pid"), m); e != nil {
		t.Fatal(e)
	}
	if a.pidMatch("test", "") != 0 {
		t.Fatal("stale boot accepted")
	}
}
func TestInputPacketMatchesGuestABI(t *testing.T) {
	event := make([]byte, 24)
	binary.LittleEndian.PutUint16(event[16:], 1)
	binary.LittleEndian.PutUint16(event[18:], 30)
	binary.LittleEndian.PutUint32(event[20:], 1)
	b := inputPacket(inputSource{id: 7, flags: 2}, event)
	if len(b) != 48 || binary.LittleEndian.Uint32(b) != 0x44494631 || binary.LittleEndian.Uint32(b[8:]) != 7 || binary.LittleEndian.Uint16(b[14:]) != 30 || binary.LittleEndian.Uint32(b[28:]) != 2 {
		t.Fatal(b)
	}
}
func TestAudioInventoryDoesNotConfuseOtherFDs(t *testing.T) {
	root := t.TempDir()
	put(t, filepath.Join(root, "proc/123/comm"), "pipewire\n", 0600)
	put(t, filepath.Join(root, "proc/123/cmdline"), "pipewire\x00", 0600)
	if e := os.MkdirAll(filepath.Join(root, "proc/123/fd"), 0700); e != nil {
		t.Fatal(e)
	}
	for fd, target := range map[string]string{"4": "/dev/snd/pcmC0D0p", "5": "/dev/null"} {
		if e := os.Symlink(target, filepath.Join(root, "proc/123/fd", fd)); e != nil {
			t.Fatal(e)
		}
	}
	holders, e := audioHolders(root)
	if e != nil || len(holders) != 1 || holders[0].PID != 123 || holders[0].FD != 4 {
		t.Fatal(holders, e)
	}
}
func TestConnectivityKeepsArgumentsLiteral(t *testing.T) {
	a, b := testApp(t, "linux")
	root := t.TempDir()
	t.Setenv("AURORA_CONTROL", root)
	if e := os.Mkdir(filepath.Join(root, "connectivity"), 0700); e != nil {
		t.Fatal(e)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	a.ctx = ctx
	done := make(chan error, 1)
	go func() {
		done <- a.connectivity("wifi-connect", []string{"space ; $(literal)", "wpa2", "password with spaces"})
	}()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		paths, _ := filepath.Glob(filepath.Join(root, "connectivity/req.*"))
		if len(paths) > 0 {
			raw := read(paths[0])
			if strings.Contains(raw, "$(literal)") {
				t.Fatal("unencoded arguments")
			}
			id := strings.TrimPrefix(filepath.Base(paths[0]), "req.")
			put(t, filepath.Join(root, "connectivity/res."+id), "0\nconnected\n", 0600)
			if e := <-done; e != nil {
				t.Fatal(e)
			}
			if !strings.Contains(b.String(), "connected") {
				t.Fatal(b.String())
			}
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("request not published")
}
func TestRootfsRejectsTraversalBeforeWriting(t *testing.T) {
	for _, name := range []string{"../../escape", "/etc/escape"} {
		t.Run(name, func(t *testing.T) {
			archive := filepath.Join(t.TempDir(), "rootfs.tar.gz")
			f, e := os.Create(archive)
			if e != nil {
				t.Fatal(e)
			}
			z := gzip.NewWriter(f)
			w := tar.NewWriter(z)
			_ = w.WriteHeader(&tar.Header{Name: name, Mode: 0600, Size: 1})
			_, _ = w.Write([]byte("x"))
			_ = w.Close()
			_ = z.Close()
			_ = f.Close()
			if e = extractRootfs(archive, t.TempDir()); e == nil {
				t.Fatal("unsafe archive accepted")
			}
		})
	}
}
func TestAudioJournalHashUsesExistingFormat(t *testing.T) {
	a, _ := testApp(t, "android")
	put(t, a.p("etc/audio-owner.conf"), "schema=1\nprofile=test\ncard_contains=card\nservice=audio\n", 0600)
	p, e := a.audioProfile()
	if e != nil || p.id != "test" || p.hash == "" {
		t.Fatal(p, e)
	}
	if e = a.audioOwner("claim", false); e != nil {
		t.Fatal(e)
	}
	if exists(a.p("run/audio-owner.state")) {
		t.Fatal("dry-run claimed audio")
	}
}
func TestMalformedHealthReportCannotReplaceState(t *testing.T) {
	a, _ := testApp(t, "android")
	s := &controlServer{a: a}
	r := s.handle(packet{op: 0x200, payload: []byte(`{"broken":`)}, true, 1000)
	if r.status != -6 || exists(a.p("run/guest-health.json")) {
		t.Fatal("malformed report accepted")
	}
	if !json.Valid(r.payload) {
		t.Fatal("invalid error JSON")
	}
}
