#!/bin/sh
# Package the Aurora Magisk module zip (install via Magisk app -> Modules
# -> Install from storage; no META-INF needed for app installs).
# Ships one Go executable per operating system; hardware control is built in.

set -eu
cd "$(dirname "$0")"
REPO=$(cd .. && pwd)
. "$REPO/release/version.sh"
aurora_load_version "$REPO/version.properties"

sh "$REPO/cli/build.sh" android
sh "$REPO/cli/build.sh" guest
INPUT_PROXY="../build/aurora-input-proxy/aurora-input-proxy"
[ -f "$INPUT_PROXY" ] || { echo "build the guest input proxy first (./guest/build-aurora-input-proxy-cross.sh)" >&2; exit 1; }
file "$INPUT_PROXY" | grep -q 'ARM aarch64' || { echo "aurora-input-proxy is not an aarch64 build" >&2; exit 1; }

ZYGISK_64="../zygisk/libs/arm64-v8a/libaurora.so"
ZYGISK_32="../zygisk/libs/armeabi-v7a/libaurora.so"
[ -f "$ZYGISK_64" ] || { echo "build the zygisk module first (cd zygisk && ndk-build)" >&2; exit 1; }
[ -f "$ZYGISK_32" ] || { echo "build the zygisk module first (cd zygisk && ndk-build)" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cp customize.sh post-fs-data.sh service.sh sepolicy.rule "$WORK/"
aurora_render_version_template module.prop.in "$WORK/module.prop"
mkdir -p "$WORK/tools" "$WORK/guest-tools" "$WORK/guest-assets" "$WORK/zygisk" \
    "$WORK/device-profiles" "$WORK/audio-profiles"
cp ../device-profiles/*.conf "$WORK/device-profiles/"
cp ../audio/profiles/*.conf "$WORK/audio-profiles/"
mkdir -p "$WORK/sessions" "$WORK/guest-config"
cp ../guest/sessions/*.session "$WORK/sessions/"
cp ../guest/hyprland.conf "$WORK/guest-config/hyprland.conf"
cp ../guest/hyprland-opal.conf "$WORK/guest-config/hyprland-opal.conf"
cp ../guest/hyprland-omarchy.conf "$WORK/guest-config/hyprland-omarchy.conf"
cp ../guest/aurora-audio-session "$WORK/guest-tools/aurora-audio-session"
cp ../guest/aurora-audio-volume "$WORK/guest-tools/aurora-audio-volume"
cp ../guest/aurora-pipewire-smoke "$WORK/guest-tools/aurora-pipewire-smoke"
cp ../guest/aurora-input-actions "$WORK/guest-tools/aurora-input-actions"
cp ../guest/aurora-media-action "$WORK/guest-tools/aurora-media-action"
cp ../guest/aurora-connectivity "$WORK/guest-tools/aurora-connectivity"
cp ../guest/aurora-connectivity-menu "$WORK/guest-tools/aurora-connectivity-menu"
cp ../guest/aurora-platform "$WORK/guest-tools/aurora-platform"
cp ../guest/aurora-apps "$WORK/guest-tools/aurora-apps"
cp ../guest/aurora-phosh-session "$WORK/guest-tools/aurora-phosh-session"
cp ../guest/aurora-compat-check "$WORK/guest-tools/aurora-compat-check"
cp ../guest/aurora-osk "$WORK/guest-tools/aurora-osk"
cp ../guest/aurora-firefox-content-defaults "$WORK/guest-tools/aurora-firefox-content-defaults"
cp ../guest/aurora-session-launch "$WORK/guest-tools/aurora-session-launch"
cp ../guest/aurora-plasma-session "$WORK/guest-tools/aurora-plasma-session"
cp ../guest/aurora-plasma-client "$WORK/guest-tools/aurora-plasma-client"
cp ../guest/aurora-hyprland "$WORK/guest-tools/aurora-hyprland"
cp ../guest/aurora-hyprland-opal "$WORK/guest-tools/aurora-hyprland-opal"
cp ../guest/aurora-opal "$WORK/guest-tools/aurora-opal"
cp ../guest/aurora-omarchy "$WORK/guest-tools/aurora-omarchy"
cp ../guest/aurora-hyprland-omarchy "$WORK/guest-tools/aurora-hyprland-omarchy"
cp -a ../guest/omarchy "$WORK/guest-assets/omarchy"
cp ../guest/aurora-opal-bridge "$WORK/guest-tools/aurora-opal-bridge"
cp ../guest/opal-command "$WORK/guest-tools/opal"
cp -a ../guest/opal "$WORK/guest-assets/opal"
cp ../guest/setup-compatibility.sh "$WORK/guest-tools/setup-compatibility.sh"
cp ../guest/aurora-phosh.service "$WORK/guest-tools/aurora-phosh.service"
cp ../guest/aurora-plasma.service "$WORK/guest-tools/aurora-plasma.service"
cp ../guest/aurora-connectivity.desktop "$WORK/guest-tools/aurora-connectivity.desktop"
cp ../guest/aurora-input-proxy.desktop "$WORK/guest-tools/aurora-input-proxy.desktop"
cp "$INPUT_PROXY" "$WORK/guest-tools/aurora-input-proxy"
cp ../guest/aurora-input-proxy-session "$WORK/guest-tools/aurora-input-proxy-session"
cp ../guest/aurora-input-proxy.service "$WORK/guest-tools/aurora-input-proxy.service"
cp ../guest/aurora-input-udevdb "$WORK/guest-tools/aurora-input-udevdb"
cp ../guest/90-aurora-direct.conf "$WORK/guest-tools/90-aurora-direct.conf"
cp ../guest/lxc/config "$WORK/tools/lxc-config-base"
cp "$ZYGISK_64" "$WORK/zygisk/arm64-v8a.so"
cp "$ZYGISK_32" "$WORK/zygisk/armeabi-v7a.so"

python3 "$REPO/cli/stage.py" --payload "$WORK"

OUT="$PWD/aurora-magisk-v$AURORA_VERSION.zip"
rm -f "$OUT"
# Python zipfile keeps this independent of zip(1). Fixed timestamps plus a
# sorted file list make repeated release builds byte-for-byte reproducible;
# the Unix mode is preserved so guest-assets keep their executable bit.
(cd "$WORK" && SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-315532800}" python3 - "$OUT" <<'PY'
import os, sys, time, zipfile
out = sys.argv[1]
epoch = max(315532800, int(os.environ['SOURCE_DATE_EPOCH']))
stamp = time.gmtime(epoch)[:6]
paths = sorted(os.path.relpath(os.path.join(root, name), '.')
               for root, dirs, files in os.walk('.') for name in files)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for path in paths:
        info = zipfile.ZipInfo(path, stamp)
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = os.stat(path).st_mode << 16
        with open(path, 'rb') as src:
            z.writestr(info, src.read(), compress_type=zipfile.ZIP_DEFLATED,
                       compresslevel=9)
PY
)
echo "Wrote ${OUT##*/}"
python3 -c "import zipfile; print('\n'.join(zipfile.ZipFile('$OUT').namelist()))"
