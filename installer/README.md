# Aurora PC installer

Aurora Installer is a linear terminal workbench for Linux PCs. It owns
system installation and porting; the Android companion owns desktop control.
Start `./aurora-installer` from the repository or run `make installer`.
No Python packages are required beyond the standard library. The interaction is
an interview: one question, one validated answer, then the next operation.
Device probes and commands stay in the operation log while the terminal shows
short progress steps. Set `AURORA_VERBOSE=1` when the raw diagnostic
stream is needed.

The interaction follows the prompt/default/validation model documented by
[pmbootstrap's CLI helpers](https://docs.postmarketos.org/pmbootstrap/main/api/pmb.helpers.html#pmb.helpers.cli.ask).
This implementation does not import or copy pmbootstrap code.

## Host setup

Use Python 3.10 or later, official Android platform-tools, and a Linux build of
magiskboot. Connect a rooted arm64 Android phone with USB debugging enabled
and grant Magisk root access to Shell. The installer never uses `adb root`.

The command accepts `--adb`, `--magiskboot`, and `--workspace`. Only use a
Magisk APK you trust when extracting the host executable: this is executable
host software, and an archive checksum does not establish its publisher.
Linux x86_64 and aarch64 are supported by this extraction path. Windows users
need Linux under WSL2 with USB forwarded to its ADB server; native
Windows and macOS toolchains are not qualified.

Kernel builds need git, make, the installed ROM's compiler and build dependencies,
and its downstream source. Keep at least the source tree's normal build space
available on the PC. Runtime download and extraction sizes are checked separately
against phone free space before userspace installation.

## Use the interview

`aurora-installer init` lists authorized devices, selects a lone authorized phone,
and inspects the exact Android fingerprint, active slot, boot size, battery,
kernel config, display size, ABI, and graphics services. It also records device-tree
identity, CPU and memory details, kernel command line, boot configuration, loaded
modules and module manifests, VINTF HAL declarations, graphics nodes, display
modes, input capabilities, power supplies, backlights, thermal sensors, network
interfaces, routes, and audio devices. Optional probe failures are recorded and
do not discard other findings. Each inspection saves a separate evidence report.
Boot partitions are resolved from the device's actual by-name links. Multiple phones are
never resolved by choosing the first device. The next question asks whether to
install, build a port, or recover.

The Magisk module payload is where the on-device toolkit lives: the module zip
carries `tools/` (including the environment installer, session catalog, and
session selection), `sessions/*.session` manifests, and `guest-tools/`. The
workbench builds that module from `toggle/`, `guest/`, and `magisk-module/`, so a
regular install delivers toolkit and manifest changes along with the kernel-side
work; the module freshness inputs cover those directories. Verify installation
checks that the toolkit, the catalogs, and the manifest set are present, because
a device without them boots but cannot be provisioned from the companion.

`aurora-installer install` accepts a schema 2 HTTPS manifest or a local manifest with its
artifacts beside it. It selects a compatible Debian, Arch, or Alpine guest from
the bundle, then asks for the Linux display name and hostname. The display name
is stored in the uid-1000 account's GECOS
field while the stable service and login identity remains `aurora`. Each
artifact must have a matching SHA-256 and length. Device and exact-build filters
apply before boot preparation, and ambiguous matches fail. Experimental releases
are available by default, including newly generated ports. Qualification remains
artifact metadata, without a separate permission question.

Distributors can set `AURORA_UPDATE_MANIFEST_URL` in the environment to
provide a default HTTPS release manifest without baking a repository owner into
the installer. If it is unset, the interview asks for a manifest explicitly.

When asked, **prepare and verify** downloads, validates, backs up, and repacks without
installing userspace or writing a partition. **Install Aurora** repeats
those checks, installs the module and static runtime, installs a missing guest
slot, sets the display name and hostname, installs the companion APK, then writes boot last.
Existing guest slots are retained. This is not an in-place distro upgrade.
A reboot is never automatic.

`aurora-installer port` does the reusable porting work. Maintained profiles
match the device aliases, Android SDK, ROM identity property, and kernel family
before selecting a known source checkout or repository, branch, image target,
and build settings. A spoofed public fingerprint alone never selects a source.
Unknown or ambiguous devices fall back to explicit source questions. Environment
overrides (`AURORA_KERNEL_SOURCE`, `AURORA_KERNEL_REF`,
`AURORA_KERNEL_TARGET`, `AURORA_BUILD_JOBS`, and
`AURORA_KERNEL_MAKE_ARGS`) remain available for port developers. If the
running configuration cannot be read, a maintained profile may supply its checked
recon artifact; otherwise the interview asks for a local file. The build uses
the running config, merges Aurora's common fragment, disables framebuffer
console ownership, resolves Kconfig defaults, checks mandatory container options,
and compiles the profile's actual boot kernel target. Incremental
build output is retained for retries.

The resulting kernel image is repacked with the original boot metadata and
ramdisk. The shared module gains a profile generated from actual
display dimensions and unambiguous wireless, backlight, and DRM observations;
unknown values are omitted. The complete inspection accompanies the bundle.
For source-checkout ports, Arch is the default. The installer builds missing
userspace artifacts and writes the base manifest automatically; it does not ask
for a bundle path. Local module and companion outputs are refreshed when their
inputs change. `AURORA_DISTRO` selects another distro, `AURORA_ROOTFS` supplies
an existing rootfs, and `AURORA_BASE_MANIFEST` explicitly overrides the automatic
base build. Arch currently uses the experimental base-rootfs recipe; creation
of its archive does not establish desktop or boot qualification.
The resulting local installation bundle has fresh checksums, the connected
fingerprint, device IDs, and build provenance. The next question offers to continue
with that bundle in the installation interview.
A built port is experimental until tested on hardware. This pipeline does not
implement a new composer HAL, synthesize downstream driver patches, rebuild
vendor kernel modules, or establish module ABI compatibility. Use matching ROM
source, config, and compiler; devices requiring new HAL integration or module
replacement still need that work before installation.

`aurora-installer recovery` saves and restores boot backups, checks installation after reboot,
and reboots the selected device. The operation log is saved in the workspace. ADB restore requires
Android to boot and provide root. For bootloops, use the device's supported
bootloader recovery procedure with the PC-held image and recorded slot.
Restore changes boot only; it retains the Magisk module and guest data.

## Boot and interruption behavior

The current backend requires a conventional Android boot image containing a
Magisk-patched ramdisk. Separate init_boot, vendor_boot-only root, unsupported
boot containers, and missing ramdisks stop during repack, before installation.
It does not unlock bootloaders, erase userdata, change slots, modify vbmeta, or
write system/vendor partitions.

A complete boot partition is copied directly to the PC and compared against
the device partition checksum. The repacked image is unpacked again to verify
the kernel and original ramdisk. Immediately before flashing, the installer
rechecks serial selection, fingerprint, slot, image fit, backup identity, and
the current partition hash. The staged image is hash-checked too. Both a failed
write and a failed readback trigger an immediate restore attempt. A disconnect
or power loss can prevent recovery; the PC backup remains available.

Ctrl-C is available during downloads and builds. It terminates the local build
process group and preserves completed cache entries and backups. Cancellation
is disabled during userspace mutation and boot write/readback. Failed installations retain their
staging directory and a transaction status rather than claiming success.
A userspace failure does not roll back every previously installed component.
Do not reboot an incomplete installation until its failure is understood.

One process can mutate a workspace at a time. After a crash, verify that its
process has exited before removing `operation.lock`. A verified cached download
is reusable; an interrupted partial download restarts. Saved settings do not
restore a stale device identity. Experimental artifacts are enabled independently
of saved settings.

## Workspace and tests

The default workspace is `~/.local/share/aurora`; override it with
`./aurora-installer --workspace /path/to/workspace`. It stores settings,
content-addressed downloads, source checkouts, incremental kernel output, local
port bundles, operation logs, transaction metadata, and versioned boot backups.
Logs and backup metadata include the device serial and Android fingerprint.

Run `make installer-test` for host-only tests. `tools/check-host.sh` includes the
same suite alongside existing repository checks. Physical flash, boot, graphics,
input, audio, networking, and Android restore qualification require a device;
fixture tests are not evidence that a new device is hardware-qualified.
