package main

import (
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"time"
	"unsafe"
)

const evGrab = 0x40044590

func ioctl(fd int, request, arg uintptr) error {
	_, _, e := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), request, arg)
	if e != 0 {
		return e
	}
	return nil
}
func ioctlBytes(fd int, request uintptr, b []byte) error {
	return ioctl(fd, request, uintptr(unsafe.Pointer(&b[0])))
}
func evRead(nr, size int) uintptr { return uintptr(0x80000000 | size<<16 | int('E')<<8 | nr) }
func (a *app) grab() error {
	paths, e := filepath.Glob(filepath.Join(env("AURORA_INPUT_DIR", "/dev/input"), "event*"))
	if e != nil {
		return e
	}
	if len(paths) == 0 || len(paths) > 64 {
		return fmt.Errorf("expected 1..64 input nodes, found %d", len(paths))
	}
	var fds []int
	defer func() {
		for _, fd := range fds {
			_ = ioctl(fd, evGrab, 0)
			_ = syscall.Close(fd)
		}
		_ = os.Remove(a.p("run/evgrab.ready"))
	}()
	for _, p := range paths {
		fd, e := syscall.Open(p, syscall.O_RDONLY|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
		if e != nil {
			return e
		}
		fds = append(fds, fd)
		if e = ioctl(fd, evGrab, 1); e != nil {
			return fmt.Errorf("grab %s: %w", p, e)
		}
	}
	if e = atomicWrite(a.p("run/evgrab.ready"), []byte(fmt.Sprint(os.Getpid())), 0600); e != nil {
		return e
	}
	<-a.ctx.Done()
	return nil
}

type inputSource struct {
	fd        int
	id, flags uint32
	path      string
}

func bit(b []byte, n int) bool { return n/8 < len(b) && b[n/8]&(1<<uint(n%8)) != 0 }
func inputFlags(fd int) uint32 {
	abs, prop := make([]byte, 8), make([]byte, 8)
	var flags uint32
	if ioctlBytes(fd, evRead(0x23, len(abs)), abs) == nil {
		if (bit(abs, 0) && bit(abs, 1)) || (bit(abs, 0x35) && bit(abs, 0x36)) {
			flags |= 1
		}
		if bit(abs, 0x35) && bit(abs, 0x36) && bit(abs, 0x39) {
			flags |= 4
		}
	}
	if ioctlBytes(fd, evRead(9, len(prop)), prop) == nil && bit(prop, 1) {
		flags |= 2
	}
	return flags
}
func inputPacket(src inputSource, event []byte) []byte {
	b := make([]byte, 48)
	le := binary.LittleEndian
	le.PutUint32(b, 0x44494631)
	le.PutUint16(b[4:], 1)
	le.PutUint16(b[6:], 48)
	le.PutUint32(b[8:], src.id)
	copy(b[12:20], event[16:24])
	le.PutUint32(b[28:], src.flags)
	if le.Uint16(b[12:]) == 3 {
		info := make([]byte, 24)
		if ioctlBytes(src.fd, evRead(0x40+int(le.Uint16(b[14:])), 24), info) == nil {
			copy(b[20:28], info[4:12])
		}
	}
	return b
}
func (a *app) forwardInput(path string) error {
	fd := -1
	var e error
	if e = a.wait(10*time.Second, func() bool {
		fd, e = syscall.Open(path, syscall.O_WRONLY|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
		return e == nil
	}); e != nil {
		return e
	}
	defer syscall.Close(fd)
	sources := map[string]inputSource{}
	defer func() {
		for _, s := range sources {
			_ = ioctl(s.fd, evGrab, 0)
			_ = syscall.Close(s.fd)
		}
	}()
	scan := func() {
		paths, _ := filepath.Glob(filepath.Join(env("AURORA_INPUT_DIR", "/dev/input"), "event*"))
		for _, p := range paths {
			if _, ok := sources[p]; ok {
				continue
			}
			if len(sources) >= 63 {
				break
			}
			f, e := syscall.Open(p, syscall.O_RDONLY|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
			if e != nil {
				continue
			}
			id := make([]byte, 8)
			if ioctlBytes(f, evRead(2, 8), id) != nil || !(binary.LittleEndian.Uint16(id) == 3 || binary.LittleEndian.Uint16(id) == 5) {
				syscall.Close(f)
				continue
			}
			if e = ioctl(f, evGrab, 1); e != nil {
				syscall.Close(f)
				continue
			}
			used := map[uint32]bool{}
			for _, s := range sources {
				used[s.id] = true
			}
			n := uint32(1)
			for used[n] {
				n++
			}
			sources[p] = inputSource{f, n, inputFlags(f), p}
		}
	}
	scan()
	next := time.Now().Add(time.Second)
	for a.ctx.Err() == nil {
		if time.Now().After(next) {
			scan()
			next = time.Now().Add(time.Second)
		}
		for p, s := range sources {
			buf := make([]byte, 24*32)
			n, e := syscall.Read(s.fd, buf)
			if e == syscall.EAGAIN || e == syscall.EINTR {
				continue
			}
			if e == syscall.ENODEV || n == 0 {
				_ = ioctl(s.fd, evGrab, 0)
				syscall.Close(s.fd)
				delete(sources, p)
				continue
			}
			if e != nil {
				return e
			}
			if n%24 != 0 {
				return fmt.Errorf("partial evdev event")
			}
			for i := 0; i < n; i += 24 {
				packet := inputPacket(s, buf[i:i+24])
				sent, e := syscall.Write(fd, packet)
				if e != nil || sent != len(packet) {
					return fmt.Errorf("input proxy disconnected or stopped consuming: %v", e)
				}
			}
		}
		if e = a.sleep(5 * time.Millisecond); e != nil {
			return nil
		}
	}
	return nil
}
func (a *app) input(x []string) error {
	op := arg(x, 0, "status")
	fifo := a.p("run/control/external-input.fifo")
	switch op {
	case "status":
		s := "inactive"
		if a.pidMatch("input-forwarder", "") != 0 {
			s = "active"
		}
		fmt.Fprintln(a.out, s)
		return nil
	case "stop":
		a.pidSignal("input-forwarder", syscall.SIGTERM, "")
		_ = a.attach("/bin/systemctl", "stop", "aurora-input-proxy.service")
		_ = os.Remove(fifo)
		return nil
	case "start":
		if !exists(a.p("run/desktop-mode")) {
			if e := a.guestStart(); e != nil {
				return e
			}
			if e := a.attach("/bin/systemctl", "is-active", "--quiet", "aurora-plasma-presenter.service"); e != nil {
				return fmt.Errorf("no internal or external desktop is active")
			}
		}
		_ = a.input([]string{"stop"})
		if e := os.MkdirAll(filepath.Dir(fifo), 0755); e != nil {
			return e
		}
		if e := syscall.Mkfifo(fifo, 0660); e != nil {
			return e
		}
		if e := os.Chown(fifo, 0, 1000); e != nil {
			return e
		}
		if e := os.Chmod(fifo, 0660); e != nil {
			return e
		}
		if e := a.attach("/bin/systemctl", "start", "aurora-input-proxy.service"); e != nil {
			return e
		}
		if e := a.spawn("input-forwarder", "", fifo); e != nil {
			return e
		}
		_ = a.sleep(300 * time.Millisecond)
		if a.pidMatch("input-forwarder", "") == 0 {
			_ = a.input([]string{"stop"})
			return fmt.Errorf("input forwarder did not stay alive")
		}
		return nil
	}
	return usage("aurora input start|stop|status")
}
