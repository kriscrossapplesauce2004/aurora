package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

func (a *app) guestStart() error {
	unlock, e := a.lock()
	if e != nil {
		return e
	}
	defer unlock()
	return a.guestStartLocked()
}
func (a *app) guestStartLocked() error {
	cfg, e := a.loadProfile()
	if e != nil {
		return e
	}
	if e = a.ensureDistro(); e != nil {
		return e
	}
	root := a.guestRoot()
	if !a.running() {
		for _, line := range strings.Split(read(filepath.Join(root, "etc/passwd")), "\n") {
			f := strings.Split(line, ":")
			if len(f) > 3 && f[2] == "1000" && f[0] != "aurora" {
				oldGroup, _ := a.output("chroot", root, "/usr/bin/id", "-gn", f[0])
				if e = a.run("chroot", root, "/usr/sbin/usermod", "-l", "aurora", "-d", "/home/aurora", "-m", f[0]); e != nil {
					return e
				}
				if oldGroup != "" && oldGroup != "aurora" {
					_ = a.quiet("chroot", root, "/usr/sbin/groupmod", "-n", "aurora", oldGroup)
				}
			}
		}
		if strings.Contains(read(filepath.Join(root, "etc/passwd")), "aurora:") {
			if e = atomicWrite(filepath.Join(root, "etc/sudoers.d/aurora"), []byte("aurora ALL=(ALL) ALL\n"), 0440); e != nil {
				return e
			}
		}
	}
	identity := a.p("etc/ssh-host-keys")
	if !exists(filepath.Join(identity, "ssh_host_ed25519_key")) {
		for _, src := range []string{a.p("guest/etc/ssh"), filepath.Join(root, "etc/ssh")} {
			if exists(filepath.Join(src, "ssh_host_ed25519_key")) {
				if e = os.MkdirAll(identity, 0700); e != nil {
					return e
				}
				if e = copyKeys(src, identity); e != nil {
					return e
				}
				break
			}
		}
	}
	if exists(identity) && exists(filepath.Join(root, "etc/ssh")) {
		if e = copyKeys(identity, filepath.Join(root, "etc/ssh")); e != nil {
			return e
		}
	}
	for _, p := range []string{"lxc/lib/lxc/rootfs", "run/control", "log", "guest"} {
		if e = os.MkdirAll(a.p(p), 0755); e != nil {
			return e
		}
	}
	if e = a.generateLXC(cfg, a.p("lxc/config.base"), a.p("lxc/config")); e != nil {
		return e
	}
	if e = a.generateGuest(cfg); e != nil {
		return e
	}
	if e = copyFile(a.p("lxc/config"), a.p("guest/config"), 0600); e != nil {
		return e
	}
	if e = a.deliverGuest(root); e != nil {
		return e
	}
	if !strings.Contains(read("/proc/mounts"), " "+root+" ") {
		if e = a.run("mount", "--bind", root, root); e != nil {
			return e
		}
		if e = a.run("mount", "-o", "remount,bind,dev,exec,suid", root, root); e != nil {
			return e
		}
	}
	a.netAssert()
	if e = a.spawn("net-keeper", ""); e != nil {
		return e
	}
	if !a.running() {
		if _, e = a.lxc("lxc-start", "-f", a.p("lxc/config"), "-l", "WARN", "-o", a.p("log/lxc.log")); e != nil {
			return e
		}
		if e = a.wait(10*time.Second, a.running); e != nil {
			return e
		}
	}
	if e = a.attach("/usr/local/bin/aurora", "internal", "guest-prepare", bootID()); e != nil {
		return e
	}
	pid, _ := a.lxc("lxc-info", "-pH")
	if digits(pid) {
		_ = a.run("nsenter", "-t", pid, "-n", "--", a.p("bin/aurora"), "internal", "ping-range")
	}
	return a.spawn("hostagent", "")
}
func copyKeys(src, dst string) error {
	paths, _ := filepath.Glob(filepath.Join(src, "ssh_host_*_key*"))
	for _, p := range paths {
		mode := os.FileMode(0600)
		if strings.HasSuffix(p, ".pub") {
			mode = 0644
		}
		if e := copyFile(p, filepath.Join(dst, filepath.Base(p)), mode); e != nil {
			return e
		}
	}
	return nil
}
func (a *app) deliverGuest(root string) error {
	if e := copyFile(a.p("guest-tools/aurora"), filepath.Join(root, "usr/local/bin/aurora"), 0755); e != nil {
		return e
	}
	files, e := os.ReadDir(a.p("guest-tools"))
	if e != nil {
		return e
	}
	for _, f := range files {
		n := f.Name()
		if f.IsDir() || n == "aurora" {
			continue
		}
		dst := filepath.Join(root, "usr/local/libexec/aurora", n)
		mode := os.FileMode(0755)
		switch {
		case strings.HasSuffix(n, ".service"):
			dst = filepath.Join(root, "etc/systemd/system", n)
			mode = 0644
		case strings.HasSuffix(n, ".desktop"):
			dst = filepath.Join(root, "usr/share/applications", n)
			mode = 0644
		case strings.HasSuffix(n, ".conf"):
			dst = filepath.Join(root, "etc/pipewire/pipewire.conf.d", n)
			mode = 0644
		}
		if e = copyFile(a.p("guest-tools", n), dst, mode); e != nil {
			return e
		}
	}
	for _, name := range []string{"opal", "omarchy"} {
		src := a.p("guest-assets", name)
		if exists(src) {
			dst := filepath.Join(root, "usr/local/share/aurora-"+name)
			if e = os.MkdirAll(dst, 0755); e != nil {
				return e
			}
			if e = a.run("cp", "-a", src+"/.", dst+"/"); e != nil {
				return e
			}
		}
	}
	paths, _ := filepath.Glob(a.p("guest-config/*.conf"))
	for _, p := range paths {
		if e = copyFile(p, filepath.Join(root, "etc/aurora", filepath.Base(p)), 0644); e != nil {
			return e
		}
	}
	return a.migrateGuest(root)
}
func (a *app) netAssert() {
	cfg, e := a.loadProfile()
	if e != nil {
		return
	}
	_ = a.quiet("ip", "link", "add", "aurora0", "type", "bridge")
	_ = a.quiet("ip", "addr", "add", "192.168.117.1/24", "dev", "aurora0")
	_ = a.quiet("ip", "link", "set", "aurora0", "up")
	_ = os.WriteFile("/proc/sys/net/ipv4/ip_forward", []byte("1"), 0644)
	for _, r := range [][]string{{"-t", "nat", "POSTROUTING", "-s", "192.168.117.0/24", "-j", "MASQUERADE"}, {"INPUT", "-i", "aurora0", "-j", "ACCEPT"}, {"OUTPUT", "-o", "aurora0", "-j", "ACCEPT"}, {"FORWARD", "-s", "192.168.117.0/24", "-j", "ACCEPT"}, {"FORWARD", "-d", "192.168.117.0/24", "-j", "ACCEPT"}} {
		prefix := []string{}
		rule := r
		if r[0] == "-t" {
			prefix = r[:2]
			rule = r[2:]
		}
		if a.quiet("iptables", append(append([]string{}, prefix...), append([]string{"-C"}, rule...)...)...) != nil {
			op := "-I"
			if len(prefix) > 0 {
				op = "-A"
			}
			_ = a.quiet("iptables", append(append([]string{}, prefix...), append([]string{op}, rule...)...)...)
		}
	}
	rules, _ := a.output("ip", "rule", "list")
	if !strings.Contains(rules, "to 192.168.117.0/24 lookup main") {
		_ = a.quiet("ip", "rule", "add", "pref", "9000", "to", "192.168.117.0/24", "lookup", "main")
	}
	wifi := cfg["AURORA_WIFI_IFACE"]
	if wifi != "" && !strings.Contains(rules, "21000:") {
		_ = a.quiet("ip", "rule", "add", "pref", "21000", "iif", "aurora0", "lookup", wifi)
	}
	route, _ := a.output("ip", "route", "get", "1.1.1.1")
	f := strings.Fields(route)
	for i := 0; i+3 < len(f); i++ {
		if f[i] == "via" && f[i+2] == "dev" && f[i+3] == wifi {
			_ = a.quiet("ip", "route", "replace", "default", "via", f[i+1], "dev", wifi, "table", "117")
		}
	}
	if !strings.Contains(rules, "21100:") {
		_ = a.quiet("ip", "rule", "add", "pref", "21100", "iif", "aurora0", "lookup", "117")
	}
}
func (a *app) guestInternal(x []string) error {
	switch x[0] {
	case "plasma-prepare":
		return a.plasmaPrepare(arg(x, 1, "foot"))
	case "guest-prepare":
		if os.Geteuid() != 0 {
			return fmt.Errorf("guest preparation requires root")
		}
		if e := a.run("mount", "-o", "remount,bind,suid,dev,exec", "/"); e != nil {
			return e
		}
		bid := arg(x, 1, "")
		if !word.MatchString(bid) {
			return fmt.Errorf("invalid boot ID")
		}
		ash := "/dev/ashmem" + bid
		if !exists(ash) {
			if e := syscall.Mknod(ash, syscall.S_IFCHR|0666, 10<<8|59); e != nil {
				return e
			}
			_ = os.Chmod(ash, 0666)
		}
		if e := a.run("mount", "-o", "remount,gid=5,mode=620,ptmxmode=666", "devpts", "/dev/pts"); e != nil {
			return e
		}
		if !exists("/dev/ptmx") {
			_ = os.Symlink("pts/ptmx", "/dev/ptmx")
		}
		for n := 0; n < 3; n++ {
			p := fmt.Sprintf("/dev/tty%d", n)
			if !exists(p) {
				if e := syscall.Mknod(p, syscall.S_IFCHR|0620, 4<<8|n); e != nil {
					return e
				}
			}
		}
		return nil
	case "session-prepare":
		if e := os.MkdirAll("/run/user/1000", 0700); e != nil {
			return e
		}
		if e := os.Chown("/run/user/1000", 1000, 1000); e != nil {
			return e
		}
		_ = os.Chmod("/etc/phoc.ini", 0644)
		if e := a.helper("aurora-input-udevdb"); e != nil {
			return e
		}
		return a.helper("aurora-platform", "service-start", "seatd")
	case "guest-agent":
		return a.guestAgent(x[1:])
	case "audio-probe":
		return a.audioProbe(x[1:])
	case "as-user":
		if len(x) < 2 {
			return usage("internal as-user COMMAND...")
		}
		return a.run("/usr/bin/setpriv", append([]string{"--reuid=1000", "--regid=1000", "--init-groups", "--"}, x[1:]...)...)
	case "legacy":
		return a.legacy(x[1:])
	}
	return usage("unknown guest internal operation: " + x[0])
}
