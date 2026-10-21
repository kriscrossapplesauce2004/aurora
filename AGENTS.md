# Aurora - project context

Android convergence layer for the reference OnePlus 7 (`guacamoleb`, SM8150 /
Adreno 640). Android stays PID1; a Debian LXC guest on the same downstream
kernel takes the display via libhybris→hwcomposer. Ships as custom boot.img +
Magisk module + Zygisk - never a ROM, never touches /system.

**Deprecated 2026-10-21.** The project is archived and no longer developed;
the remote is read-only. Treat everything below as historical reference. See
`docs/history/retrospective-2026-10-21.md`.

**Continuing an existing session?** Read `docs/CONTINUE.md` first. It is the
session protocol: orientation, house rules, tracking, device access, and
private-branch handling. Then run `tools/agent-status.sh`.

**Read first:** `docs/design-spec.md` (authoritative design), `docs/recon-findings.md`
(device ground truth), `README.md` (repo map + milestones).

## Device (recon-verified, don't re-derive)

- crDroid 12.11 / Android 16 (SDK 36), slot `_a`. Magisk 30.7 + ReZygisk.
- Kernel `4.14.357-openela` (crDroid sm8150 fork, branch `16.0`).
- Composer: HIDL `graphics.composer@2.1–2.4` (no AIDL). Gralloc: QTI mapper@4.0.
- binderfs in kernel; guest gets private binderfs in its IPC ns.
- DP-alt over USB-C works; Android native desktop mode runs on it.

## Talking to the phone

- USB cable connected (fastboot recovery possible). Wireless adb as fallback
  (official platform-tools only, port rotates per reboot).
- **Never `adb root`**. Root = `adb shell "su -c '<cmds>'"`. If su returns
  permission denied, Shell toggle in Magisk Superuser tab is off.
- Flash path: `usb-install/host-flash.sh check|flash|restore|verify` or Magisk
  action zips. Dry-run: `touch /sdcard/Download/aurora-dryrun`.

## Build system

- `kernel/build.sh`: merges `aurora.config` onto running kernel config,
  verifies all options, compiles. Toolchain in `toolchain/` (gitignored).
- `boot/repack.sh`: swaps kernel into boot.img via magiskboot (from `toolchain/usr/bin`).
- Zygisk: `cd zygisk && ndk-build NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=jni/Android.mk NDK_APPLICATION_MK=jni/Application.mk`
- Companion: `~/android-sdk/gradle-8.7/bin/gradle --no-daemon assembleDebug` in `companion/`.
- NDK at `~/android-sdk/ndk/27.2.12479018`. Platform-tools at `~/platform-tools`.

## Conventions

- The compositor is named **Hyprland**, with runtime prefix `/opt/hyprland`.
- Current bring-up: `docs/arch-opal-bringup.md`. User requires no mode switches;
  use host builds and display-safe probes until explicitly authorized otherwise.
- Next work handoff: `docs/handoffs/alarm-apps-opal-osk.md`. Fresh ALARM needs
  installed applications; ship fixes through the installer. OSK source work is
  in `~/.local/state/opal/staging/`, not the installed host shell.
- Probe/script outputs → `artifacts/`. Structured recon → `recon/report-*/`.
- Commit as work lands; use the contributor's repository-configured identity.
- `~/op7-port/` + pmOS = mainline kernel track. Don't mix with Aurora.

### Comment discipline

- Comment why only when the code cannot make it obvious. Do not narrate the code.
- Keep routine comments to one line. Put incident history, dates, evidence, and
  extended rationale in docs or commit messages.
- Longer comments are reserved for dangerous invariants, hardware quirks, and
  constraints whose removal could cause data loss, boot failure, or a device wedge.
- During reviews, delete stale or redundant comments instead of preserving them
  as archaeology.

## Graphics invariant — explicit user requirement

Hyprland and Sxmo must use vendor EGL/GLES through **libhybris**,
Android gralloc allocations with complete native handles and sync fences, and
libhybris/hwcomposer for internal presentation. Do not substitute Mesa/Zink,
Turnip, raw KMS, or a nested KWin session to claim delivery. Native graphics
results below are historical experiments, not the product implementation path.
Modern Hyprland uses Aquamarine, not the Droidian wlroots ABI; implement and
validate the needed backend/renderer integration rather than enabling an
incompatible session manifest. `docs/graphics-architecture.md` governs this.

## Key technical facts

**Guest compositor stack:** phoc 0.47 (droidian `group/102/keypad-slide-lights`)
on droidian wlroots fork (`feature/next/backport-0.18`), built in-guest against
upstream libhybris. Build script: `guest/build-wlroots-phoc.sh`.

**libhybris:** built from upstream master (has PR #609, A15/16 support).
`guest/build-libhybris.sh`. Includes: GSK struct-varying rewrite hook (Adreno
flat-struct bug), eglSwapBuffersWithDamageKHR override, epoxy EGL_EXT_device_query
filter, HWCNativeWindowSetBufferCount, setDisplayBrightness(1.0) after power-on.

**hwc2-compat:** standalone NDK cross-build, `hwc2-compat/build.sh`. Installs to
guest `/usr/lib/android/`.

**GPU app buffers:** hybris wayland EGL platform (zero-copy). Clients need
`EGL_PLATFORM=wayland HYBRIS_EGLPLATFORM=wayland`. `GSK_RENDERER=ngl`.
`/etc/profile.d/hybris.sh` sets defaults. Gate: `guest/gpu-smoke.sh`.

**Input:** wlroots EVIOCGRAB handoff, libinput udev properties
(`aurora-input-udevdb`), quirks for touchpanel, seatd needs /dev/tty0-2.

**Non-root session (2026-07-12):** the guest desktop runs as unprivileged
`aurora` (uid 1000), NOT root. `desktop-on` does root-only prep (udev DB, seatd,
create `/run/user/1000`, `chmod a+r /etc/phoc.ini`) then `runuser -u aurora`
launches phoc + phosh; runtime dir is `/run/user/1000`. Device access works
because GPU/dri/binder/ashmem are world-rw and kgsl/ion are 1000-owned (uid
1000 == Android AID_SYSTEM); the ONE gate is `/dev/input/*` (0660 root:1004) -
handled by group `android_input` (gid 1004, matches AID_INPUT) that aurora
joins. seatd socket is group `video`(44). Perms recon: `artifacts/node-perms-probe.txt`.
`/etc/phoc.ini` MUST be world-readable or phoc segfaults on parse. Sudo is
password-gated (`aurora ALL=(ALL) ALL`) - run `aurora passwd` once before sudo
works. **nosuid gotcha:** Android's /data is `nosuid,nodev`, and the container
rootfs is a bind of a /data subtree, so the container `/` inherits nosuid and
sudo's setuid bit is ignored ("effective uid is not 0 … nosuid"). `guest-start`
fixes it by `mount -o remount,bind,suid,dev,exec /` inside the container
post-start (the host-side bind-remount of `$AURORA/guest` does NOT reach the
pivoted container root on 4.14). `aurora guest` = aurora shell; `aurora guest-root`
= root escape hatch. Known
gap: phosh runs bare (no logind), so polkit-gated actions log "No session" -
Logout/Reboot/Poweroff are fine (aurora-session-manager intercepts them).

**pidfd shim:** `aurora-pidfd-shim.so` (LD_PRELOAD) - pidfd_open→ENOSYS forces
SIGCHLD fallback. Required because waitid(P_PIDFD) is EINVAL on 4.14.

**Session manager:** `aurora-session-manager` owns org.gnome.SessionManager on the
session bus. Routes Logout→exit (phone mode), Shutdown→poweroff, Reboot→reboot.
Also plays gsd-power for wake: ActiveChanged(true)→AddUserActiveWatch→SetActive(false).

**Control channel:** `toggle/aurora-hostagent` (inotifyd-driven) watches
`/data/aurora/run/control`. Guest writes commands via `/mnt/aurora-control`.

**Battery:** `bms` node is accurate (not `battery`). `aurora-battery` bind-mounts
the corrected capacity over `battery/capacity`. The bind is re-asserted every
poll pass, not once: the qpnp-smb5 charger re-enumerates its power_supply node
on USB plug/unplug and silently drops the bind (else phosh falls back to the
stuck raw value). The bind reaches UPower even though upowerd runs in its own
private mount namespace, because `/sys` is a shared mount so the pid1-ns bind
propagates in. (Separate, likely pre-existing: UPower reports `discharging`
while charging - `ac` line_power is online=0, only `pc_port`/`usb` are online=1.)

**Container PTYs:** guest-start remounts devpts + symlinks /dev/ptmx (ptmxmode=000 fix).
Same post-start block remounts `/` suid (nosuid /data would break sudo - see non-root session).

**sway is dead:** incompatible with the droidian wlroots hybrid 0.17/0.18 API.

**Never `phoc -E`:** glib child-watch broken on 4.14 (pidfd half-backport).

**ReZygisk:** native Zygisk MUST stay disabled (`zygisk=0`) or ReZygisk skips
module loading. Both ABI .so files required (arm64-v8a + armeabi-v7a).

## Current state (2026-07-19)

**Kernel #4 running** (`4.14.357-perf-g96adfa8256dc #2`, distro clang 22).
pstore/ramoops enabled. Device module v0.4.1 (versionCode=8); Aqua
v0.5.0-alpha.2 (versionCode=13) is the current source release; it adds the
in-app desktop environment installer (`bin/env-install` + the companion Apps-tab
environments section), so the module payload must be refreshed for it to exist
on-device. Guest RUNNING.

**Milestones complete:** 1 (kernel flash), 3 (guest renders on panel), 4 (input +
phosh verified, cable-free round trip, §4 signed off), 6 (SF-death Zygisk hook +
system_server freezer - full desktop-mode stability).

**Milestone 5 native experiment proven:** Turnip-on-KGSL + minigbm pass the
native smoke gate, raw KMS scans out on DSI, and Plasma Mobile runs under KWin
with zink/Turnip GPU compositing and touch. Product graphics policy is now
compatibility-first: vendor EGL/GLES always goes through libhybris; Android
gralloc owns buffers; minigbm supplies the compositor-facing GBM layer. The
first shared-allocation gate passes on-device: the complete QTI gralloc handle
round-trips through libhybris, vendor EGL renders through the reconstructed
object, and minigbm imports/re-exports its pixel dma-buf. The handle contained 2
fds plus 22 private ints, so the direct compositor bridge must keep the complete
Android native handle and sync fences rather than reducing it to one generic
dma-buf. The remaining M5 headline is concurrent external convergence through
an Android presenter on DP-alt. See `docs/graphics-architecture.md`.

**Compatibility graphics benchmark (2026-07-19):** display-safe vendor EGL at
1080x2340 completes four fullscreen textured/blended layers in 4.263 ms mean,
4.625 ms p99 (240 measured frames); full native-handle round trip averages 8 us
and minigbm import/export 92 us. This excludes KWin, presentation/vsync and
explicit-fence transport. Evidence: `artifacts/hybris-minigbm-benchmark-20260719.txt`.

**Wake path VERIFIED** (power button blank/unblank works). KEY_POWER quirk removed.

**Desktop-mode crash loop FIXED (2026-07-12):** The `ss-freezer` loop in
`toggle/desktop-on` (step 3b) SIGSTOPs system_server the moment we hand off, so
its `android.display` thread can never accumulate 60s of block time and the
framework Watchdog never fires. Verified 150s soak: ss stays state=T, wlan0 stays
UP with IP, guest ping works. `desktop-off` SIGKILLs the frozen ss so init/zygote
respawns it fresh (SIGCONT would just unblock the Watchdog and it'd self-kill
from the accumulated block time). **Guest networking now works in desktop mode.**

Failed alternative: PLT-hooking `kill`/`tgkill`/`abort`/`exit`/`_exit` in
libandroid_runtime/libc/libutils/libbase/libprocessgroup from Zygisk. Hooks
registered fine but never fired - the actual Watchdog kill path doesn't go
through any of those GOT entries in system_server. Don't retry this angle.

**Exit wedge: lazy health HAL → bootanim last frame stuck (FIXED 2026-08-03):**
`vendor.lineage_health` is a lazy AIDL HAL. While ss is SIGSTOP-frozen through the
desktop session it idles out and unregisters; crDroid's servicemanager can't
lazy-restart it, so the SIGKILL-respawned system_server blocks FOREVER in
`ChargingControlController` (waiting for `IChargingControl`) → Watchdog kill-loop
→ nothing ever draws over bootanim's final frame (screen looks stuck on the last
frame of the boot animation). `desktop-off` step 1c now runs a 120s
setsid-detached keeper that re-asserts `start vendor.lineage_health` across the
ss boot window, and step 3b gained the 60s bootanim keeper from native-restore.
Diagnosis: `service.bootanim.exit 1` is a *symptom*, not the cause — check
Watchdog for "Blocked in handler on main thread" + `ChargingControlController`
before touching bootanim props.

**Guest distro profiles (2026-08-09, buildable but not device-qualified):**
Debian remains the only proven guest. The active rootfs is selected through
`/data/aurora/active-guest`; Debian keeps its compatible location at
`/data/aurora/guest`, while optional Arch Linux ARM and Alpine slots live
under `/data/aurora/guests/<id>/rootfs`. `toggle/guest-distro` owns
install/select/provision/rollback, and refuses switching while desktop mode is
active. `guest/aurora-platform` abstracts package, service, user-session and libc
differences; `aurora distro ...` and the companion Software screen expose it.
Portable rootfs builders live in `guest/build-portable-rootfs.sh`; Alpine is a
native musl build (no `gcompat` shortcut), so glibc-specific libhybris hooks are
skipped there. Guest helper binaries are static. Do not call Arch or Alpine
graphically supported until they pass hwcomposer, Phoc/input, repeated Android
restore, audio and external-display qualification on the phone.

**Multi-compositor internal sessions (2026-08-25):** `desktop-on` no longer
hardcodes phoc+phosh. It resolves `$AURORA/etc/compositor` against
`$AURORA/etc/sessions/<id>.session` via `toggle/session-select`
(planned/incompatible refuse; fallback = phosh), commits the record to
`$AURORA/run/session.active`, and branches on the manifest `backend=`:
`libhybris-hwcomposer` → wlroots path via `guest/aurora-session-launch`;
`gralloc-minigbm` → KWin through `aurora-plasma.service` (PAM/logind session,
composer HAL stopped pre-launch, evgrab released + touchpanel notifier after
the socket appears). `desktop-off` tears down from `session.active` including
HAL restart + livedisplay/color-HAL bounce. Plasma Mobile/KWin 6.3.6 verified
interactive on-panel through this path (2026-08-25); qualification stays
experimental — nightlight.so segfaults under the Aug-9 patched libkwin (ABI
skew with system libKF6ConfigCore) and is disabled via guest
`/root/.config/kwinrc`. Session manifests deploy via magisk module payload to
`$AURORA/etc/sessions`. The companion Software screen now renders those manifests
(the old hardcoded COMPOSITORS list is gone); APK rebuild needs the Android
SDK restored on the host (`~/android-sdk` currently missing).

**Other known issues:**
- phoc teardown segfaults (rc 139, cosmetic).
- matrix flat varyings (mat3/mat4) unverified in GSK shader fix.
- /sdcard (FUSE) unavailable in desktop mode (framework thrash). Drop files
  elsewhere (e.g., /data/local/tmp for adb staging).

## Next steps (see `docs/north-star.md`)

1. Audio stack (pipewire) → volume keys
2. Phosh polish (feedbackd, backgrounds)
3. §5 external convergence (DP-alt)

## adb/su/lxc quoting rule

`adb shell "su -c '<entire chain>'"` - one quoted arg or only the first command
runs as root. File drop into guest: adb push → su cp over existing guest file →
lxc-attach `/bin/cp` to final path.

## On-device paths

- Active guest rootfs pointer: `/data/aurora/active-guest`
- Proven Debian rootfs: `/data/aurora/guest` (no `rootfs/` subdir)
- Optional distro slots: `/data/aurora/guests/<id>/rootfs`
- Toggle scripts deploy to: `/data/aurora/bin/`
- Control channel: `/data/aurora/run/control`
- LXC tools: `/data/aurora/lxc/bin`
- Backups: `/sdcard/Download/boot_a-before-aurora-*.img` + `artifacts/backups/`
