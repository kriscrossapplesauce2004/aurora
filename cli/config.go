package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var word = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)
var sessionID = regexp.MustCompile(`^[a-z0-9-]+$`)
var devicePath = regexp.MustCompile(`^/(sys|dev)/[A-Za-z0-9._/-]+$`)

func (a *app) loadProfile() (map[string]string, error) {
	m := map[string]string{"AURORA_DRM_CARD": "/dev/dri/card0", "AURORA_DRM_RENDER_NODE": "/dev/dri/renderD128", "AURORA_INPUT_QUIRK": "none", "AURORA_HWC_OUTPUT": "HWCOMPOSER-1", "AURORA_GRAPHICS_RENDERER": "libhybris", "AURORA_GBM_PROVIDER": "minigbm", "AURORA_EXTERNAL_RENDERER": "auto", "AURORA_LINUX_FIRST_SUPPORTED": "0", "AURORA_LINUX_FIRST_KEEP_NETWORK": "1", "AURORA_LINUX_FIRST_FREEZE_SYSTEM_SERVER": "1"}
	for _, p := range []string{"/sys/class/backlight/backlight/brightness", "/sys/class/backlight/panel0-backlight/brightness", "/sys/class/leds/lcd-backlight/brightness"} {
		if exists(p) {
			m["AURORA_BACKLIGHT_PATH"] = p
			break
		}
	}
	nets, _ := filepath.Glob("/sys/class/net/w*")
	for _, p := range nets {
		if strings.HasPrefix(filepath.Base(p), "wlan") || strings.HasPrefix(filepath.Base(p), "wifi") {
			m["AURORA_WIFI_IFACE"] = filepath.Base(p)
			break
		}
	}
	keys := strings.Fields("AURORA_PROFILE_ID AURORA_WIFI_IFACE AURORA_BATTERY_GAUGE AURORA_INPUT_QUIRK AURORA_GRAPHICS_RENDERER AURORA_GBM_PROVIDER AURORA_EXTERNAL_RENDERER AURORA_BACKLIGHT_LEVEL AURORA_PANEL_WIDTH AURORA_PANEL_HEIGHT AURORA_PANEL_REFRESH_MHZ AURORA_OUTPUT_SCALE AURORA_BACKLIGHT_PATH AURORA_DRM_CARD AURORA_DRM_RENDER_NODE AURORA_HWC_OUTPUT AURORA_LINUX_FIRST_SUPPORTED AURORA_LINUX_FIRST_KEEP_NETWORK AURORA_LINUX_FIRST_FREEZE_SYSTEM_SERVER AURORA_EXTRA_DEVICES")
	for _, k := range keys {
		if v := os.Getenv(k); v != "" {
			m[k] = v
		}
	}
	b, e := os.ReadFile(a.p("etc/device.conf"))
	if e != nil && !os.IsNotExist(e) {
		return nil, e
	}
	for _, line := range strings.Split(string(b), "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			return nil, fmt.Errorf("malformed device profile line")
		}
		if !oneOf(k, keys...) {
			return nil, fmt.Errorf("unknown profile key: %s", k)
		}
		m[k] = v
	}
	for k, v := range m {
		if v == "" {
			continue
		}
		valid := word.MatchString(v)
		switch {
		case oneOf(k, "AURORA_BACKLIGHT_LEVEL", "AURORA_PANEL_WIDTH", "AURORA_PANEL_HEIGHT", "AURORA_PANEL_REFRESH_MHZ", "AURORA_OUTPUT_SCALE"):
			valid = digits(v) && len(v) < 10
		case oneOf(k, "AURORA_BACKLIGHT_PATH", "AURORA_DRM_CARD", "AURORA_DRM_RENDER_NODE"):
			valid = devicePath.MatchString(v) && filepath.Clean(v) == v
		case k == "AURORA_EXTRA_DEVICES":
			valid = true
			for _, p := range strings.Fields(v) {
				valid = valid && devicePath.MatchString(p) && filepath.Clean(p) == p
			}
		case k == "AURORA_HWC_OUTPUT":
			valid = regexp.MustCompile(`^HWCOMPOSER-[0-9]$`).MatchString(v)
		case strings.HasPrefix(k, "AURORA_LINUX_FIRST_"):
			valid = v == "0" || v == "1"
		}
		if !valid {
			return nil, fmt.Errorf("invalid device profile value for %s", k)
		}
	}
	if m["AURORA_PANEL_WIDTH"] == "" || m["AURORA_PANEL_HEIGHT"] == "" {
		s, _ := a.output("wm", "size")
		f := regexp.MustCompile(`Physical size: ([0-9]+)x([0-9]+)`).FindStringSubmatch(s)
		if len(f) == 3 {
			m["AURORA_PANEL_WIDTH"] = f[1]
			m["AURORA_PANEL_HEIGHT"] = f[2]
		}
	}
	if m["AURORA_OUTPUT_SCALE"] == "" {
		n := (intValue(m["AURORA_PANEL_WIDTH"]) + 180) / 360
		if n < 1 {
			n = 1
		}
		if n > 4 {
			n = 4
		}
		m["AURORA_OUTPUT_SCALE"] = strconv.Itoa(n)
	}
	if s := m["AURORA_PANEL_REFRESH_MHZ"]; s != "" && (intValue(s) < 24000 || intValue(s) > 240000) {
		return nil, fmt.Errorf("panel refresh must be 24000..240000 mHz")
	}
	if m["AURORA_BACKLIGHT_LEVEL"] == "" && m["AURORA_BACKLIGHT_PATH"] != "" {
		n := intValue(read(filepath.Join(filepath.Dir(m["AURORA_BACKLIGHT_PATH"]), "max_brightness")))
		if n == 0 {
			n = 4095
		}
		n /= 3
		if n < 1 {
			n = 1
		}
		m["AURORA_BACKLIGHT_LEVEL"] = strconv.Itoa(n)
	}
	return m, nil
}
func (a *app) config(x []string) error {
	m, e := a.loadProfile()
	if e != nil {
		return e
	}
	switch arg(x, 0, "show") {
	case "show":
		keys := make([]string, 0, len(m))
		for k := range m {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			fmt.Fprintf(a.out, "%s=%s\n", k, m[k])
		}
		return nil
	case "lxc", "guest":
		unlock, e := a.lock()
		if e != nil {
			return e
		}
		defer unlock()
		if x[0] == "lxc" {
			return a.generateLXC(m, arg(x, 1, a.p("lxc/config.base")), arg(x, 2, a.p("lxc/config")))
		}
		return a.generateGuest(m)
	}
	return usage("aurora config show|lxc [BASE OUTPUT]|guest")
}
func (a *app) generateGuest(m map[string]string) error {
	root := env("AURORA_GUEST_ROOT", a.guestRoot())
	if !exists(root) {
		return fmt.Errorf("guest rootfs missing: %s", root)
	}
	if !oneOf(m["AURORA_INPUT_QUIRK"], "none", "", "oneplus-touchpanel-zero-axes") {
		return fmt.Errorf("unknown input quirk: %s", m["AURORA_INPUT_QUIRK"])
	}
	if e := atomicWrite(filepath.Join(root, "etc/phoc.ini"), []byte(fmt.Sprintf("# Generated by Aurora; edit /data/aurora/etc/device.conf.\n[output:%s]\nscale = %s\n", m["AURORA_HWC_OUTPUT"], m["AURORA_OUTPUT_SCALE"])), 0644); e != nil {
		return e
	}
	var b strings.Builder
	for _, k := range strings.Fields("AURORA_BATTERY_GAUGE AURORA_INPUT_QUIRK AURORA_GRAPHICS_RENDERER AURORA_GBM_PROVIDER AURORA_EXTERNAL_RENDERER AURORA_DRM_RENDER_NODE AURORA_PANEL_WIDTH AURORA_PANEL_HEIGHT AURORA_PANEL_REFRESH_MHZ") {
		fmt.Fprintf(&b, "%s=%s\n", k, m[k])
	}
	if e := atomicWrite(filepath.Join(root, "etc/aurora-device.conf"), []byte(b.String()), 0644); e != nil {
		return e
	}
	p := filepath.Join(root, "usr/share/libinput/99-aurora.quirks")
	if m["AURORA_INPUT_QUIRK"] == "oneplus-touchpanel-zero-axes" {
		return atomicWrite(p, []byte("[OnePlus touchpanel]\nMatchName=touchpanel\nAttrEventCode=-ABS_MT_WIDTH_MAJOR;-ABS_MT_PRESSURE\nAttrInputProp=+INPUT_PROP_DIRECT;-INPUT_PROP_POINTER\n"), 0644)
	}
	if e := os.Remove(p); e != nil && !os.IsNotExist(e) {
		return e
	}
	return nil
}
func (a *app) generateLXC(m map[string]string, base, out string) error {
	b, e := os.ReadFile(base)
	if e != nil {
		return e
	}
	host := os.Getenv("AURORA_HOST_ROOT")
	var config, manifest strings.Builder
	devices := strings.Fields("/dev/kgsl-3d0 /dev/mali0 /dev/pvr_sync /dev/galcore /dev/ashmem /dev/ion /dev/dma_heap /dev/dri /dev/input /dev/snd /dev/graphics " + m["AURORA_EXTRA_DEVICES"])
	for _, line := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(line, "lxc.rootfs.path = ") {
			continue
		}
		drop := false
		if strings.HasPrefix(line, "lxc.mount.entry = ") {
			f := strings.Fields(strings.TrimPrefix(line, "lxc.mount.entry = "))
			if len(f) > 0 {
				drop = oneOf(f[0], append(devices, "binder", "/dev/binder", "/dev/hwbinder", "/dev/vndbinder", "/data/user_de/0/com.aurora.companion/files")...) || strings.HasPrefix(f[0], "/dev/binderfs/")
			}
		}
		if !drop {
			config.WriteString(line + "\n")
		}
	}
	fmt.Fprintf(&config, "lxc.rootfs.path = dir:%s\n", env("AURORA_GUEST_ROOT_LINK", a.p("active-guest")))
	if strings.Contains(read(host+"/proc/filesystems"), "binder") || exists(host+"/dev/binderfs/binder-control") {
		config.WriteString("lxc.mount.entry = binder dev/binderfs binder nosuid,noexec,nodev,optional 0 0\n")
	}
	for _, name := range []string{"binder", "hwbinder", "vndbinder"} {
		for _, src := range []string{"/dev/binderfs/" + name, "/dev/" + name} {
			if exists(host + src) {
				fmt.Fprintf(&config, "lxc.mount.entry = %s dev/%s none bind,create=file,optional 0 0\n", src, name)
				fmt.Fprintf(&manifest, "%s -> /dev/%s\n", src, name)
				break
			}
		}
	}
	seen := map[string]bool{}
	for _, src := range devices {
		if seen[src] {
			continue
		}
		seen[src] = true
		s, e := os.Stat(host + src)
		if e != nil {
			continue
		}
		opts := "bind,create=file,optional"
		if s.IsDir() {
			opts = "rbind,create=dir,optional"
		}
		fmt.Fprintf(&config, "lxc.mount.entry = %s %s none %s 0 0\n", src, strings.TrimPrefix(src, "/"), opts)
		manifest.WriteString(src + "\n")
	}
	src := "/data/user_de/0/com.aurora.companion/files"
	if exists(host + src) {
		fmt.Fprintf(&config, "lxc.mount.entry = %s mnt/aurora-presenter none bind,create=dir,optional 0 0\n", src)
		manifest.WriteString(src + " -> /mnt/aurora-presenter\n")
	}
	if e := atomicWrite(out, []byte(config.String()), 0600); e != nil {
		return e
	}
	return atomicWrite(a.p("lxc/device-manifest"), []byte(manifest.String()), 0600)
}
func (a *app) sessionReady(m map[string]string) error {
	for _, p := range append([]string{m["compositor"], m["shell"]}, strings.Split(m["required_binaries"], ",")...) {
		if p == "" || p == "hyprland-config" {
			continue
		}
		if a.resolveGuestBinary(p) == "" {
			return fmt.Errorf("missing guest executable: %s", p)
		}
	}
	return nil
}

func (a *app) resolveGuestBinary(item string) string {
	for _, p := range strings.Split(item, "|") {
		p = strings.TrimSpace(p)
		if !filepath.IsAbs(p) || filepath.Clean(p) != p {
			continue
		}
		if executable(filepath.Join(a.guestRoot(), p)) {
			return p
		}
	}
	return ""
}
func (a *app) selected() map[string]string {
	fallback := map[string]string{"id": "phosh", "qualification": "qualified", "backend": "libhybris-hwcomposer", "renderer": "vendor-hybris", "compositor": "/usr/local/bin/phoc", "compositor_args": "-C /etc/phoc.ini", "shell": "/usr/libexec/phosh", "required_binaries": "/usr/libexec/phosh,/usr/bin/squeekboard"}
	id := read(a.p("etc/compositor"))
	if !sessionID.MatchString(id) {
		return fallback
	}
	m := fields(a.p("etc/sessions", id+".session"))
	if !oneOf(m["qualification"], "qualified", "proven", "experimental", "diagnostic") || m["compositor"] == "" || a.sessionReady(m) != nil {
		return fallback
	}
	m["id"] = id
	for _, k := range []string{"compositor", "shell"} {
		if m[k] != "" && m[k] != "hyprland-config" {
			m[k] = a.resolveGuestBinary(m[k])
		}
	}
	return m
}
func (a *app) session(x []string) error {
	switch arg(x, 0, "list") {
	case "list":
		paths, _ := filepath.Glob(a.p("etc/sessions/*.session"))
		for _, p := range paths {
			id := strings.TrimSuffix(filepath.Base(p), ".session")
			fmt.Fprintln(a.out, "==="+id)
			fmt.Fprintln(a.out, read(p))
			ready, reason := "yes", ""
			if e := a.sessionReady(fields(p)); e != nil {
				ready = "no"
				reason = e.Error()
			}
			fmt.Fprintf(a.out, "runtime_ready=%s\nruntime_reason=%s\n", ready, reason)
		}
		return nil
	case "show":
		m := a.selected()
		for _, k := range []string{"id", "qualification", "backend", "renderer", "compositor", "compositor_args", "shell", "required_binaries"} {
			fmt.Fprintf(a.out, "%s=%s\n", k, m[k])
		}
		return nil
	case "select":
		if len(x) != 2 || !sessionID.MatchString(x[1]) {
			return usage("aurora session select ID")
		}
		m := fields(a.p("etc/sessions", x[1]+".session"))
		if m["id"] != x[1] || !oneOf(m["qualification"], "qualified", "proven", "experimental", "diagnostic") {
			return fmt.Errorf("session unavailable: %s", m["reason"])
		}
		if e := a.sessionReady(m); e != nil {
			return e
		}
		return atomicWrite(a.p("etc/compositor"), []byte(x[1]+"\n"), 0644)
	}
	return usage("aurora session list|show|select ID")
}
