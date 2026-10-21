# Aurora retrospective

Status: historical material
Authority: none for current operation
Date: 2026-10-21

Aurora (developed as Determination, briefly DecemberOS) was deprecated on
2026-10-21 and the repository archived. No further development is planned.
This page records what the project proved, what it learned the hard way, and
what was left open, so the work stays useful to anyone attempting the same
thing on another device.

## Span

- First commit 2026-07-01, last engineering commit 2026-10-07: 224 commits.
- One reference device throughout: OnePlus 7 `guacamoleb` (SM8150 / Adreno
  640), crDroid 12.x / Android 16, downstream `4.14.357` kernel.
- The `0.5.0 "Aqua"` release train reached `0.5.0-alpha.2`. No release was
  tagged.

## What was verified on hardware

| Date | Result |
|---|---|
| 2026-07-02 | Custom kernel with container options flashed and booting; PID/USER/IPC namespaces confirmed; full hardware smoke test green (milestone 1). |
| 2026-07-04 | Debian LXC guest on the shared kernel; upstream libhybris `test_hwcomposer` draws GLES 3.2 on the panel. |
| 2026-07-06/07 | phoc + phosh + squeekboard on the panel through libhybris/hwcomposer, touch working (milestone 3). |
| 2026-07-10 | Zero-copy GPU app buffers over the hybris Wayland EGL platform. |
| 2026-07-11 | Cable-free phone ⇄ desktop round trip from the companion app, QS tile and guest power menu (milestone 4). |
| 2026-07-12 | Desktop-mode stability: `system_server` freezer stops the Watchdog kill loop; guest networking survives (milestone 6). |
| 2026-07-13/14 | Native experiment: Turnip on KGSL, minigbm, raw DSI KMS scanout, Plasma Mobile under KWin with GPU compositing. Kept as an experiment, not the product path. |
| 2026-07-19 | Full QTI gralloc native handle (2 fds + 22 ints) round-trips through libhybris into minigbm; vendor EGL draws four fullscreen layers in 4.263 ms mean. |
| 2026-08-02 | Direct audio: internal speaker through ALSA and PipeWire with journalled Android ownership. |
| 2026-08-03 | Exit wedge fixed: lazy health HAL keeper lets the respawned `system_server` boot past `ChargingControlController`. |
| 2026-08-25 | Plasma Mobile / KWin interactive on the panel through the manifest-driven session selector. |
| 2026-09-16 | Arch Linux ARM guest running the Omarchy/Hyprland session; external DP-alt monitor hotplugged through HWC as an extended desktop; volume keys drive the guest sink; external input proxy live. |

Landed in source but not recorded as hardware-qualified: the single Go `aurora`
CLI that replaced the shell toggles and C++ control plane (2026-09-24), the
October Opal shell sync, the Linux-first boot profile, and the Alpine profile.

## Dead ends worth not repeating

- **sway**: incompatible with the Droidian wlroots 0.17/0.18 hybrid API.
- **PLT-hooking the Watchdog kill path** (`kill`, `tgkill`, `abort`, `exit` in
  libandroid_runtime/libc/libutils/libbase/libprocessgroup): the hooks
  registered and never fired. Freezing `system_server` worked instead.
- **`phoc -E`**: glib child-watch breaks on 4.14's half-backported pidfd; the
  same root cause required the `pidfd_open` → `ENOSYS` shim.
- **`SIGCONT` on desktop exit**: unblocks the accumulated Watchdog time and the
  framework kills itself. `SIGKILL` and a clean respawn is the exit path.
- **Treating `service.bootanim.exit` as the cause** of the stuck exit frame: it
  is a symptom. Check the Watchdog for a blocked main-thread handler first.
- **Mesa/Zink/Turnip or raw KMS as the product renderer**: it works on this
  device and does not port. Vendor EGL through libhybris with complete Android
  native handles and sync fences was the deliberate product policy
  ([graphics architecture](../graphics-architecture.md)).
- **nightlight under the patched libkwin**: segfaults from ABI skew with the
  system KF6ConfigCore.

## Left open

- Concurrent external convergence: Android keeps the panel while the guest
  presents on DP-alt. The guest-owns-both extended desktop works; the
  Android-live variant does not exist yet.
- DP audio: blocked at the kernel (no `msm-dp-audio` driver, ELD or device-tree
  audio node). A kernel/DT project, not a mixer setting.
- Monitor unplug path untested.
- Android capability bridge: designed in
  [android-capability-bridge.md](../android-capability-bridge.md); P0
  inventory not started, P1 selective `system_server` freeze needs a hardware
  session.
- Arch Linux ARM application profile, installer parity and a usable OSK; see
  the [ALARM handoff](../handoffs/alarm-apps-opal-osk.md).
- Arch and Alpine guests never passed the full qualification set (hwcomposer,
  input, repeated Android restore, audio, external display).
- Portability beyond `guacamoleb`: the PC porting installer exists, but no
  second device was brought up.

## Where the knowledge lives

- [Design spec](../design-spec.md) and [recon findings](../recon-findings.md):
  the architecture and the device ground truth.
- [AGENTS.md](../../AGENTS.md) "Key technical facts": the dense list of
  kernel-4.14 and Android-16 quirks that cost the most time.
- [Handoffs](../handoffs/) and [history](README.md): dated session records.
- `artifacts/` with [ARTIFACTS.md](../../ARTIFACTS.md): the evidence behind each
  claim above.
- To return a device to stock, follow the
  [install and recovery guide](../guides/install-and-recovery.md) with the
  boot image backed up before installation.
