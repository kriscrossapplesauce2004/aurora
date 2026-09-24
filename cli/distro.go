package main

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func (a *app) slot(id string) string {
	if id == "debian" {
		return a.p("guest")
	}
	return a.p("guests", id, "rootfs")
}
func (a *app) installed(id string) bool {
	r := a.slot(id)
	init := false
	for _, p := range []string{"sbin/init", "bin/init"} {
		s, e := os.Lstat(filepath.Join(r, p))
		if e == nil && (s.Mode()&os.ModeSymlink != 0 || s.Mode()&0111 != 0) {
			init = true
		}
	}
	return init && (fields(filepath.Join(r, "etc/aurora-profile"))["ID"] == id || (id == "debian" && exists(filepath.Join(r, "etc/debian_version"))))
}
func (a *app) currentDistro() string {
	id := fields(a.p("etc/guest-distro"))["active"]
	if oneOf(id, "debian", "arch", "alpine") && a.installed(id) {
		return id
	}
	id = fields(filepath.Join(a.guestRoot(), "etc/aurora-profile"))["ID"]
	if oneOf(id, "debian", "arch", "alpine") {
		return id
	}
	return "debian"
}
func (a *app) running() bool { s, e := a.lxc("lxc-info", "-sH"); return e == nil && s == "RUNNING" }
func (a *app) point(id string) error {
	if !oneOf(id, "debian", "arch", "alpine") {
		return usage("unsupported distro")
	}
	p := a.p("active-guest")
	if s, e := os.Lstat(p); e == nil && s.Mode()&os.ModeSymlink == 0 {
		return fmt.Errorf("active guest pointer is not a symlink")
	}
	rel, e := filepath.Rel(a.root, a.slot(id))
	if e != nil {
		return e
	}
	tmp := fmt.Sprintf("%s.new.%d", p, os.Getpid())
	defer os.Remove(tmp)
	if e = os.Symlink(rel, tmp); e != nil {
		return e
	}
	if e = os.Rename(tmp, p); e != nil {
		return e
	}
	return writeFields(a.p("etc/guest-distro"), map[string]string{"active": id, "root": a.slot(id), "changed": fmt.Sprint(time.Now().Unix())})
}
func (a *app) ensureDistro() error {
	id := a.currentDistro()
	if !a.installed(id) {
		return fmt.Errorf("selected guest is missing: %s", id)
	}
	p, e := filepath.EvalSymlinks(a.p("active-guest"))
	if e != nil || p != a.slot(id) {
		if a.running() {
			return fmt.Errorf("cannot repair guest pointer while container is running")
		}
		return a.point(id)
	}
	return nil
}
func (a *app) distro(x []string) error {
	op := arg(x, 0, "status")
	switch op {
	case "active":
		fmt.Fprintln(a.out, a.currentDistro())
		return nil
	case "list":
		for _, id := range []string{"debian", "arch", "alpine"} {
			installed, active, ready, name := "absent", "inactive", "not-ready", map[string]string{"debian": "Debian", "arch": "Arch Linux ARM", "alpine": "Alpine Linux"}[id]
			if a.installed(id) {
				installed = "installed"
				ready = "needs-provision"
				if id == "debian" || exists(filepath.Join(a.slot(id), "etc/aurora-ready")) {
					ready = "ready"
				}
				if a.currentDistro() == id {
					active = "active"
				}
				if n := fields(filepath.Join(a.slot(id), "etc/aurora-profile"))["NAME"]; n != "" {
					name = n
				}
			}
			fmt.Fprintf(a.out, "%s|%s|%s|%s|%s\n", id, installed, active, ready, name)
		}
		return nil
	case "status", "root", "ensure":
		if e := a.ensureDistro(); e != nil {
			return e
		}
		if op == "root" {
			fmt.Fprintln(a.out, a.guestRoot())
		} else if op == "status" {
			fmt.Fprintf(a.out, "active=%s\nroot=%s\nrunning=%t\n", a.currentDistro(), a.guestRoot(), a.running())
		}
		return nil
	case "install":
		if len(x) != 3 || !oneOf(x[1], "debian", "arch", "alpine") {
			return usage("aurora distro install debian|arch|alpine ARCHIVE")
		}
		unlock, e := a.lock()
		if e != nil {
			return e
		}
		defer unlock()
		return a.installSlot(x[1], x[2])
	case "activate", "select", "switch":
		if len(x) != 2 || !oneOf(x[1], "debian", "arch", "alpine") {
			return usage("aurora distro " + op + " debian|arch|alpine")
		}
		unlock, e := a.lock()
		if e != nil {
			return e
		}
		defer unlock()
		if exists(a.p("run/desktop-mode")) {
			return fmt.Errorf("cannot switch rootfs while Linux owns the display")
		}
		if !a.installed(x[1]) {
			return fmt.Errorf("guest is not installed: %s", x[1])
		}
		previous := a.currentDistro()
		if a.running() {
			if _, e = a.lxc("lxc-stop", "-t", "20"); e != nil {
				return e
			}
		}
		if e = a.point(x[1]); e != nil {
			return e
		}
		if op == "activate" {
			return nil
		}
		if e = a.guestStartLocked(); e == nil {
			e = a.attach("/usr/bin/test", "-r", "/etc/os-release")
		}
		if e == nil {
			return nil
		}
		_, _ = a.lxc("lxc-stop", "-t", "20")
		if rollback := a.point(previous); rollback != nil {
			return fmt.Errorf("new guest failed (%v); pointer rollback failed: %w", e, rollback)
		}
		if rollback := a.guestStartLocked(); rollback != nil {
			return fmt.Errorf("new guest failed (%v); previous guest failed: %w", e, rollback)
		}
		return fmt.Errorf("new guest failed; rolled back to %s: %w", previous, e)
	case "provision":
		if e := a.guestStart(); e != nil {
			return e
		}
		if a.currentDistro() == "debian" {
			fmt.Fprintln(a.out, "Debian uses the existing setup flow.")
			return nil
		}
		if e := a.attach("/bin/sh", "/root/aurora-firstboot"); e != nil {
			return e
		}
		if a.currentDistro() == "arch" {
			return a.attach("/usr/local/bin/aurora", "apps", "apply")
		}
		return nil
	}
	return usage("aurora distro list|status|install|activate|select|provision")
}
func (a *app) installSlot(id, archive string) error {
	root := a.slot(id)
	if entries, e := os.ReadDir(root); e == nil {
		if id != "debian" || len(entries) > 1 || (len(entries) == 1 && entries[0].Name() != "config") {
			return fmt.Errorf("slot already exists: %s", id)
		}
	}
	if e := os.MkdirAll(a.p("guests"), 0755); e != nil {
		return e
	}
	stage, e := os.MkdirTemp(a.p("guests"), ".install-"+id+"-")
	if e != nil {
		return e
	}
	defer os.RemoveAll(stage)
	dst := filepath.Join(stage, "rootfs")
	if e = os.Mkdir(dst, 0755); e != nil {
		return e
	}
	if e = extractRootfs(archive, dst); e != nil {
		return e
	}
	identity := fields(filepath.Join(dst, "etc/aurora-profile"))["ID"]
	if id == "debian" {
		identity = strings.Trim(fields(filepath.Join(dst, "etc/os-release"))["ID"], "\"")
		if !exists(filepath.Join(dst, "etc/debian_version")) {
			return fmt.Errorf("Debian rootfs has no debian_version")
		}
	}
	if identity != id {
		return fmt.Errorf("rootfs identity %q does not match %s", identity, id)
	}
	init := false
	for _, p := range []string{"sbin/init", "bin/init"} {
		s, e := os.Lstat(filepath.Join(dst, p))
		if e == nil && (s.Mode()&0111 != 0 || s.Mode()&os.ModeSymlink != 0) {
			init = true
		}
	}
	if !init {
		return fmt.Errorf("rootfs has no init")
	}
	if exists(filepath.Join(root, "config")) {
		if e = copyFile(filepath.Join(root, "config"), filepath.Join(dst, "config"), 0600); e != nil {
			return e
		}
		if e = os.Remove(filepath.Join(root, "config")); e != nil {
			return e
		}
	}
	if exists(root) {
		if e = os.Remove(root); e != nil {
			return e
		}
	}
	if e = os.MkdirAll(filepath.Dir(root), 0755); e != nil {
		return e
	}
	return os.Rename(dst, root)
}
func cleanMember(name string) (string, error) {
	if filepath.IsAbs(name) {
		return "", fmt.Errorf("absolute archive member: %s", name)
	}
	p := filepath.Clean(name)
	if p == ".." || strings.HasPrefix(p, "../") {
		return "", fmt.Errorf("archive path escapes root: %s", name)
	}
	return p, nil
}
func extractRootfs(archive, dst string) error {
	f, e := os.Open(archive)
	if e != nil {
		return e
	}
	defer f.Close()
	z, e := gzip.NewReader(f)
	if e != nil {
		return e
	}
	defer z.Close()
	r := tar.NewReader(z)
	var links, dirs []*tar.Header
	for {
		h, e := r.Next()
		if e == io.EOF {
			break
		}
		if e != nil {
			return e
		}
		name, e := cleanMember(h.Name)
		if e != nil {
			return e
		}
		if name == "." {
			continue
		}
		p := filepath.Join(dst, name)
		if e = os.MkdirAll(filepath.Dir(p), 0755); e != nil {
			return e
		}
		switch h.Typeflag {
		case tar.TypeDir:
			if e = os.MkdirAll(p, 0755); e != nil {
				return e
			}
			v := *h
			dirs = append(dirs, &v)
		case tar.TypeReg, tar.TypeRegA:
			w, e := os.OpenFile(p, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
			if e != nil {
				return e
			}
			_, e = io.Copy(w, r)
			ce := w.Close()
			if e == nil {
				e = ce
			}
			if e != nil {
				return e
			}
			if e = os.Chown(p, h.Uid, h.Gid); e != nil {
				return e
			}
			if e = os.Chmod(p, os.FileMode(h.Mode&0777)|specialMode(h.Mode)); e != nil {
				return e
			}
		case tar.TypeSymlink, tar.TypeLink:
			v := *h
			v.Name = name
			links = append(links, &v)
		case tar.TypeXGlobalHeader, tar.TypeXHeader:
			continue
		default:
			return fmt.Errorf("unsupported special archive member: %s", h.Name)
		}
	}
	// Install links last so an archive cannot redirect writes outside its staging root.
	for _, h := range links {
		p := filepath.Join(dst, h.Name)
		if h.Typeflag == tar.TypeSymlink {
			if e = os.Symlink(h.Linkname, p); e != nil {
				return e
			}
		} else {
			target, e := cleanMember(h.Linkname)
			if e != nil {
				return e
			}
			s, e := os.Lstat(filepath.Join(dst, target))
			if e != nil || !s.Mode().IsRegular() {
				return fmt.Errorf("invalid hardlink target: %s", h.Linkname)
			}
			if e = os.Link(filepath.Join(dst, target), p); e != nil {
				return e
			}
		}
		if e = os.Lchown(p, h.Uid, h.Gid); e != nil {
			return e
		}
	}
	for i := len(dirs) - 1; i >= 0; i-- {
		h := dirs[i]
		p := filepath.Join(dst, h.Name)
		if e = os.Chown(p, h.Uid, h.Gid); e != nil {
			return e
		}
		if e = os.Chmod(p, os.FileMode(h.Mode&0777)|specialMode(h.Mode)); e != nil {
			return e
		}
	}
	return nil
}
func specialMode(m int64) os.FileMode {
	var mode os.FileMode
	if m&04000 != 0 {
		mode |= os.ModeSetuid
	}
	if m&02000 != 0 {
		mode |= os.ModeSetgid
	}
	if m&01000 != 0 {
		mode |= os.ModeSticky
	}
	return mode
}
