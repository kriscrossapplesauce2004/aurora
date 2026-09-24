package main

import (
	"bytes"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var guestNative = []string{"aurora-guest-agent", "aurora-audio-probe", "aurora-connectivity", "aurora-media-action", "aurora-osk", "aurora-audio-volume", "aurora-signal"}
var guestPublicPath = regexp.MustCompile(`/usr/local/s?bin/(aurora-[A-Za-z0-9_.-]+)`)
var guestDesktopExec = regexp.MustCompile(`(?m)^(Exec=)(aurora-[A-Za-z0-9_.-]+)`)
var guestHyprExec = regexp.MustCompile(`(exec, )(aurora-[A-Za-z0-9_.-]+)`)

func rewriteGuest(b []byte) []byte {
	if bytes.IndexByte(b, 0) >= 0 {
		return b
	}
	s := guestPublicPath.ReplaceAllString(string(b), "/usr/local/libexec/aurora/$1")
	s = strings.ReplaceAll(s, "PATH=/usr/local/sbin:/usr/local/bin:", "PATH=/usr/local/libexec/aurora:/usr/local/sbin:/usr/local/bin:")
	s = strings.ReplaceAll(s, "PATH=/usr/local/bin:", "PATH=/usr/local/libexec/aurora:/usr/local/bin:")
	s = guestDesktopExec.ReplaceAllString(s, "${1}/usr/local/libexec/aurora/$2")
	s = guestHyprExec.ReplaceAllString(s, "${1}/usr/local/libexec/aurora/$2")
	return []byte(s)
}
func (a *app) migrateGuest(root string) error {
	private := filepath.Join(root, "usr/local/libexec/aurora")
	if e := os.MkdirAll(private, 0755); e != nil {
		return e
	}
	for _, dir := range []string{"usr/local/bin", "usr/local/sbin"} {
		paths, _ := filepath.Glob(filepath.Join(root, dir, "aurora-*"))
		for _, p := range paths {
			s, e := os.Lstat(p)
			if e != nil {
				return e
			}
			if !s.Mode().IsRegular() && s.Mode()&os.ModeSymlink == 0 {
				continue
			}
			dst := filepath.Join(private, filepath.Base(p))
			if !exists(dst) {
				if e = os.Rename(p, dst); e != nil {
					return e
				}
			} else if e = os.Remove(p); e != nil {
				return e
			}
		}
	}
	for _, name := range guestNative {
		p := filepath.Join(private, name)
		if e := os.Remove(p); e != nil && !os.IsNotExist(e) {
			return e
		}
		if e := os.Symlink("../../bin/aurora", p); e != nil {
			return e
		}
	}
	for _, dir := range []string{"usr/local/libexec/aurora", "etc/systemd", "usr/lib/systemd", "usr/share/applications", "etc/aurora", "root"} {
		base := filepath.Join(root, dir)
		if !exists(base) {
			continue
		}
		e := filepath.WalkDir(base, func(p string, d fs.DirEntry, e error) error {
			if e != nil {
				return e
			}
			if !d.Type().IsRegular() {
				return nil
			}
			s, e := d.Info()
			if e != nil {
				return e
			}
			if s.Size() > 2*1024*1024 {
				return nil
			}
			b, e := os.ReadFile(p)
			if e != nil {
				return e
			}
			next := rewriteGuest(b)
			if bytes.Equal(b, next) {
				return nil
			}
			return atomicWrite(p, next, s.Mode().Perm())
		})
		if e != nil {
			return e
		}
	}
	return nil
}
