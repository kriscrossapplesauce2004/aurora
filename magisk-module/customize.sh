# Aurora Magisk module installer (runs inside Magisk app's install flow).
# Lays down the on-device toolkit under /data/aurora; the module dir
# itself only carries the boot hooks + sepolicy.

ui_print "- $(grep_prop name "$MODPATH/module.prop") $(grep_prop version "$MODPATH/module.prop")"

AURORA=/data/aurora
VERSION=$(grep_prop versionCode "$MODPATH/module.prop")
SETS="$AURORA/versions"
STAGE="$SETS/.stage-$VERSION-$$"
TARGET="$SETS/$VERSION"
mkdir -p "$STAGE/bin" "$STAGE/libexec" "$STAGE/guest-tools" "$STAGE/guest-assets" "$STAGE/guest-config" "$STAGE/sessions" "$AURORA/etc" "$AURORA/log" "$AURORA/run" "$AURORA/lxc" "$SETS"
trap 'rm -rf "$STAGE"' EXIT
[ ! -e "$TARGET" ] || abort "! payload version $VERSION is already staged"

# Existing installs keep the proven Debian rootfs exactly where it is. The
# active pointer is the only path new multi-distro code writes through.
if [ -d "$AURORA/guest" ] && [ ! -e "$AURORA/active-guest" ]; then
    ln -s guest "$AURORA/active-guest.new" && mv -f "$AURORA/active-guest.new" "$AURORA/active-guest" \
        || abort "! cannot create active guest pointer"
fi
GUEST_ROOT=
if [ -L "$AURORA/active-guest" ]; then
    GUEST_ROOT=$(readlink -f "$AURORA/active-guest" 2>/dev/null)
fi
[ -n "$GUEST_ROOT" ] || GUEST_ROOT="$AURORA/guest"

# Retire the replaced GTK shell from both the staged payload and active guest.
rm -f "$STAGE/guest-tools/aurora-hypr-shell" \
    "$GUEST_ROOT/usr/local/bin/aurora-hypr-shell"

# Do not leave withdrawn experimental sessions selectable after a module update.
for f in cage gamescope-headless labwc mutter sway weston; do
    rm -f "$STAGE/sessions/$f.session" "$AURORA/etc/sessions/$f.session"
done

[ -f "$MODPATH/tools/aurora" ] || abort "! missing Android Aurora executable"
cp -f "$MODPATH/tools/aurora" "$STAGE/bin/aurora"
chmod 0755 "$STAGE/bin/aurora"
while IFS= read -r f; do
    case "$f" in ''|*[!a-zA-Z0-9._-]*) abort "! invalid private command name" ;; esac
    ln -s ../bin/aurora "$STAGE/libexec/$f" || abort "! cannot stage private command $f"
done < "$MODPATH/tools/android-commands"
cp -f "$MODPATH/guest-tools/aurora" "$STAGE/guest-tools/aurora"
chmod 0755 "$STAGE/guest-tools/aurora"
cp -f "$MODPATH/tools/lxc-config-base" "$STAGE/lxc-config-base"
for f in aurora-guest-agent aurora-audio-probe aurora-audio-session aurora-audio-volume aurora-pipewire-smoke aurora-input-actions aurora-media-action aurora-connectivity aurora-connectivity-menu aurora-platform aurora-apps aurora-phosh-session aurora-compat-check aurora-osk aurora-firefox-content-defaults aurora-session-launch aurora-plasma-session aurora-plasma-client aurora-hyprland aurora-hyprland-opal aurora-hyprland-omarchy aurora-omarchy aurora-opal aurora-opal-bridge opal; do
  if [ -f "$MODPATH/guest-tools/$f" ]; then
    cp -f "$MODPATH/guest-tools/$f" "$STAGE/guest-tools/$f"
    chmod 0755 "$STAGE/guest-tools/$f"
    if [ -d "$GUEST_ROOT/usr/local/bin" ]; then
        cp -f "$MODPATH/guest-tools/$f" "$GUEST_ROOT/usr/local/bin/$f"
        chmod 0755 "$GUEST_ROOT/usr/local/bin/$f"
    fi
  fi
done
if [ -d "$MODPATH/guest-assets/opal" ]; then
    cp -a "$MODPATH/guest-assets/opal" "$STAGE/guest-assets/opal"
    if [ -d "$GUEST_ROOT/usr/local/share" ]; then
        mkdir -p "$GUEST_ROOT/usr/local/share/aurora-opal"
        cp -a "$MODPATH/guest-assets/opal/." "$GUEST_ROOT/usr/local/share/aurora-opal/"
    fi
fi
# The vendored Omarchy commands are shebang scripts whose executable bit must
# survive packaging. Restore it after every copy, regardless of zip metadata.
restore_script_modes() {
    [ -d "$1" ] || return 0
    find "$1" -type f 2>/dev/null | while IFS= read -r f; do
        [ "$(dd if="$f" bs=2 count=1 2>/dev/null)" = '#!' ] || continue
        chmod 0755 "$f"
    done
}
if [ -d "$MODPATH/guest-assets/omarchy" ]; then
    mkdir -p "$STAGE/guest-assets/omarchy"
    cp -a "$MODPATH/guest-assets/omarchy/." "$STAGE/guest-assets/omarchy/"
    if [ -d "$GUEST_ROOT/usr/local/share" ]; then
        mkdir -p "$GUEST_ROOT/usr/local/share/aurora-omarchy"
        cp -a "$MODPATH/guest-assets/omarchy/." "$GUEST_ROOT/usr/local/share/aurora-omarchy/"
    fi
    restore_script_modes "$STAGE/guest-assets/omarchy"
    restore_script_modes "$GUEST_ROOT/usr/local/share/aurora-omarchy"
fi
for aurora_guest_config in "$MODPATH"/guest-config/*.conf; do
    [ -f "$aurora_guest_config" ] || continue
    config_name=$(basename "$aurora_guest_config")
    cp -f "$aurora_guest_config" "$STAGE/guest-config/$config_name"
    chmod 0644 "$STAGE/guest-config/$config_name"
    if [ -d "$GUEST_ROOT/etc" ]; then
        mkdir -p "$GUEST_ROOT/etc/aurora"
        cp -f "$aurora_guest_config" "$GUEST_ROOT/etc/aurora/$config_name"
        chmod 0644 "$GUEST_ROOT/etc/aurora/$config_name"
    fi
done
if [ -f "$MODPATH/guest-tools/setup-compatibility.sh" ]; then
    cp -f "$MODPATH/guest-tools/setup-compatibility.sh" \
        "$STAGE/guest-tools/setup-compatibility.sh"
    chmod 0755 "$STAGE/guest-tools/setup-compatibility.sh"
    if [ -d "$GUEST_ROOT/usr/local/sbin" ]; then
        cp -f "$MODPATH/guest-tools/setup-compatibility.sh" \
            "$GUEST_ROOT/usr/local/sbin/setup-compatibility.sh"
        chmod 0755 "$GUEST_ROOT/usr/local/sbin/setup-compatibility.sh"
    fi
fi
if [ -f "$MODPATH/guest-tools/aurora-phosh.service" ]; then
    cp -f "$MODPATH/guest-tools/aurora-phosh.service" "$STAGE/guest-tools/aurora-phosh.service"
    chmod 0644 "$STAGE/guest-tools/aurora-phosh.service"
    if [ -d "$GUEST_ROOT/usr/local/lib" ]; then
        mkdir -p "$GUEST_ROOT/usr/local/lib/aurora"
        cp -f "$MODPATH/guest-tools/aurora-phosh.service" \
            "$GUEST_ROOT/usr/local/lib/aurora/aurora-phosh.service"
        chmod 0644 "$GUEST_ROOT/usr/local/lib/aurora/aurora-phosh.service"
    fi
    if [ -d "$GUEST_ROOT/etc/systemd/system" ]; then
        cp -f "$MODPATH/guest-tools/aurora-phosh.service" \
            "$GUEST_ROOT/etc/systemd/system/aurora-phosh.service"
        chmod 0644 "$GUEST_ROOT/etc/systemd/system/aurora-phosh.service"
    fi
fi
if [ -f "$MODPATH/guest-tools/aurora-plasma.service" ]; then
    cp -f "$MODPATH/guest-tools/aurora-plasma.service" "$STAGE/guest-tools/aurora-plasma.service"
    chmod 0644 "$STAGE/guest-tools/aurora-plasma.service"
    if [ -d "$GUEST_ROOT/etc/systemd/system" ]; then
        cp -f "$MODPATH/guest-tools/aurora-plasma.service" \
            "$GUEST_ROOT/etc/systemd/system/aurora-plasma.service"
        chmod 0644 "$GUEST_ROOT/etc/systemd/system/aurora-plasma.service"
    fi
fi
if [ -f "$MODPATH/guest-tools/aurora-input-proxy" ]; then
    cp -f "$MODPATH/guest-tools/aurora-input-proxy" "$STAGE/guest-tools/aurora-input-proxy"
    chmod 0755 "$STAGE/guest-tools/aurora-input-proxy"
    if [ -d "$GUEST_ROOT/usr/local/bin" ]; then
        cp -f "$MODPATH/guest-tools/aurora-input-proxy" "$GUEST_ROOT/usr/local/bin/aurora-input-proxy"
        chmod 0755 "$GUEST_ROOT/usr/local/bin/aurora-input-proxy"
    fi
fi
if [ -f "$MODPATH/guest-tools/aurora-input-proxy-session" ]; then
    cp -f "$MODPATH/guest-tools/aurora-input-proxy-session" "$STAGE/guest-tools/aurora-input-proxy-session"
    chmod 0755 "$STAGE/guest-tools/aurora-input-proxy-session"
    if [ -d "$GUEST_ROOT/usr/local/bin" ]; then
        cp -f "$MODPATH/guest-tools/aurora-input-proxy-session" "$GUEST_ROOT/usr/local/bin/aurora-input-proxy-session"
        chmod 0755 "$GUEST_ROOT/usr/local/bin/aurora-input-proxy-session"
    fi
fi
if [ -f "$MODPATH/guest-tools/aurora-input-proxy.service" ] && [ -d "$GUEST_ROOT/etc/systemd/system" ]; then
    cp -f "$MODPATH/guest-tools/aurora-input-proxy.service" "$STAGE/guest-tools/aurora-input-proxy.service"
    chmod 0644 "$STAGE/guest-tools/aurora-input-proxy.service"
    cp -f "$MODPATH/guest-tools/aurora-input-proxy.service" "$GUEST_ROOT/etc/systemd/system/aurora-input-proxy.service"
    chmod 0644 "$GUEST_ROOT/etc/systemd/system/aurora-input-proxy.service"
    mkdir -p "$GUEST_ROOT/etc/systemd/system/multi-user.target.wants"
    ln -sf ../aurora-input-proxy.service         "$GUEST_ROOT/etc/systemd/system/multi-user.target.wants/aurora-input-proxy.service"
fi
if [ -f "$MODPATH/guest-tools/aurora-input-udevdb" ]; then
    cp -f "$MODPATH/guest-tools/aurora-input-udevdb" "$STAGE/guest-tools/aurora-input-udevdb"
    chmod 0755 "$STAGE/guest-tools/aurora-input-udevdb"
    if [ -d "$GUEST_ROOT/usr/local/sbin" ]; then
        cp -f "$MODPATH/guest-tools/aurora-input-udevdb" "$GUEST_ROOT/usr/local/sbin/aurora-input-udevdb"
        chmod 0755 "$GUEST_ROOT/usr/local/sbin/aurora-input-udevdb"
    fi
fi
if [ -f "$MODPATH/guest-tools/aurora-connectivity.desktop" ]; then
    cp -f "$MODPATH/guest-tools/aurora-connectivity.desktop" \
        "$STAGE/guest-tools/aurora-connectivity.desktop"
    chmod 0644 "$STAGE/guest-tools/aurora-connectivity.desktop"
    if [ -d "$GUEST_ROOT/usr/share/applications" ]; then
        cp -f "$MODPATH/guest-tools/aurora-connectivity.desktop" \
            "$GUEST_ROOT/usr/share/applications/aurora-connectivity.desktop"
        chmod 0644 "$GUEST_ROOT/usr/share/applications/aurora-connectivity.desktop"
    fi
fi
if [ -f "$MODPATH/guest-tools/aurora-input-proxy.desktop" ]; then
    cp -f "$MODPATH/guest-tools/aurora-input-proxy.desktop" \
        "$STAGE/guest-tools/aurora-input-proxy.desktop"
    chmod 0644 "$STAGE/guest-tools/aurora-input-proxy.desktop"
    if [ -d "$GUEST_ROOT/usr/share/applications" ]; then
        cp -f "$MODPATH/guest-tools/aurora-input-proxy.desktop" \
            "$GUEST_ROOT/usr/share/applications/aurora-input-proxy.desktop"
        chmod 0644 "$GUEST_ROOT/usr/share/applications/aurora-input-proxy.desktop"
    fi
fi
if [ -f "$MODPATH/guest-tools/90-aurora-direct.conf" ]; then
    cp -f "$MODPATH/guest-tools/90-aurora-direct.conf" \
        "$STAGE/guest-tools/90-aurora-direct.conf"
    chmod 0644 "$STAGE/guest-tools/90-aurora-direct.conf"
fi

# Session manifests are repo-owned declarations (the selection itself lives in
# $AURORA/etc/compositor), so every install refreshes them wholesale.
for f in "$MODPATH"/sessions/*.session; do
    [ -f "$f" ] || continue
    mkdir -p "$STAGE/sessions" "$AURORA/etc/sessions"
    cp -f "$f" "$STAGE/sessions/${f##*/}"
    cp -f "$f" "$AURORA/etc/sessions/${f##*/}"
    chmod 0644 "$STAGE/sessions/${f##*/}" "$AURORA/etc/sessions/${f##*/}"
done

if [ -d "$GUEST_ROOT/etc" ]; then
    AURORA="$STAGE" "$STAGE/bin/aurora" internal install-guest "$GUEST_ROOT" || abort "! guest CLI migration failed"
fi

# Verify the complete staged set before one atomic pointer change. Keep the
# prior target intact for recovery; runtime paths resolve through current/.
(cd "$STAGE" && find . -type f -print | LC_ALL=C sort | xargs sha256sum) > "$STAGE/SHA256SUMS" || abort "! payload hash generation failed"
printf '%s\n' "$VERSION" > "$STAGE/manifest-id"
mv "$STAGE" "$TARGET" || abort "! payload activation staging failed"
ln -s "versions/$VERSION" "$AURORA/current.new" || abort "! cannot prepare current payload pointer"
mv -f "$AURORA/current.new" "$AURORA/current" || abort "! cannot activate payload pointer"
if [ -d "$AURORA/bin" ] && [ ! -L "$AURORA/bin" ]; then
    mv "$AURORA/bin" "$SETS/legacy-bin" || abort "! cannot preserve prior toolkit"
fi
ln -s current/bin "$AURORA/bin.new" && mv -f "$AURORA/bin.new" "$AURORA/bin" || abort "! cannot activate toolkit"
ln -s current/libexec "$AURORA/libexec.new" && mv -f "$AURORA/libexec.new" "$AURORA/libexec" || abort "! cannot activate private commands"
if [ -d "$AURORA/guest-tools" ] && [ ! -L "$AURORA/guest-tools" ]; then
    mv "$AURORA/guest-tools" "$SETS/legacy-guest-tools" || abort "! cannot preserve guest tools"
fi
ln -s current/guest-tools "$AURORA/guest-tools.new" && mv -f "$AURORA/guest-tools.new" "$AURORA/guest-tools" || abort "! cannot activate guest tools"
if [ -d "$AURORA/guest-assets" ] && [ ! -L "$AURORA/guest-assets" ]; then
    mv "$AURORA/guest-assets" "$SETS/legacy-guest-assets" || abort "! cannot preserve guest assets"
fi
ln -s current/guest-assets "$AURORA/guest-assets.new" && mv -f "$AURORA/guest-assets.new" "$AURORA/guest-assets" || abort "! cannot activate guest assets"
if [ -d "$AURORA/guest-config" ] && [ ! -L "$AURORA/guest-config" ]; then
    mv "$AURORA/guest-config" "$SETS/legacy-guest-config" || abort "! cannot preserve guest config"
fi
ln -s current/guest-config "$AURORA/guest-config.new" && mv -f "$AURORA/guest-config.new" "$AURORA/guest-config" || abort "! cannot activate guest config"
if [ -e "$AURORA/lxc/config.base" ] && [ ! -L "$AURORA/lxc/config.base" ]; then
    cp -f "$AURORA/lxc/config.base" "$SETS/legacy-lxc-config-base" || abort "! cannot preserve LXC base"
    rm -f "$AURORA/lxc/config.base"
fi
ln -s ../current/lxc-config-base "$AURORA/lxc/config.base.new" && mv -f "$AURORA/lxc/config.base.new" "$AURORA/lxc/config.base" || abort "! cannot activate LXC base"

# Install a known profile only on a matching device. Unknown devices use the
# runtime discovery defaults and receive no silently-wrong vendor assumptions.
DEVICE=$(getprop ro.product.device)
[ ! -f "$AURORA/etc/device.conf" ] && [ -f "$MODPATH/device-profiles/$DEVICE.conf" ] && {
    cp -f "$MODPATH/device-profiles/$DEVICE.conf" "$AURORA/etc/device.conf"
    chmod 0644 "$AURORA/etc/device.conf"
    ui_print "- Device profile: $DEVICE"
}
# Merge newly introduced typed capabilities into an existing exact-match
# profile without replacing locally qualified values.
if [ -f "$AURORA/etc/device.conf" ] && [ -f "$MODPATH/device-profiles/$DEVICE.conf" ]; then
    for key in AURORA_LINUX_FIRST_SUPPORTED AURORA_LINUX_FIRST_KEEP_NETWORK AURORA_LINUX_FIRST_FREEZE_SYSTEM_SERVER; do
        grep -q "^$key=" "$AURORA/etc/device.conf" && continue
        value=$(sed -n "s/^$key=//p" "$MODPATH/device-profiles/$DEVICE.conf" | head -n 1)
        [ -z "$value" ] || printf '%s=%s\n' "$key" "$value" >> "$AURORA/etc/device.conf"
    done
fi
[ -f "$AURORA/etc/device.conf" ] && ui_print "- Config: $AURORA/etc/device.conf"

# Audio ownership profiles are stricter than general device discovery: never
# guess service names or codec topology. Install only the exact hardware profile
# selected by the exact-match device config, and preserve local qualification.
AUDIO_PROFILE_ID=$(sed -n 's/^AURORA_PROFILE_ID=//p' "$AURORA/etc/device.conf" 2>/dev/null | head -n 1)
AUDIO_PROFILE=
if [ -n "$AUDIO_PROFILE_ID" ] && [ -f "$MODPATH/audio-profiles/$AUDIO_PROFILE_ID.conf" ]; then
    AUDIO_PROFILE="$MODPATH/audio-profiles/$AUDIO_PROFILE_ID.conf"
else
    # Profile ids are renamed as device profiles evolve; match the ALSA card
    # instead of guessing a service topology for an unmatched id.
    for audio_candidate in "$MODPATH"/audio-profiles/*.conf; do
        [ -f "$audio_candidate" ] || continue
        audio_card=$(sed -n 's/^card_contains=//p' "$audio_candidate" | head -n 1)
        [ -n "$audio_card" ] || continue
        if grep -q "$audio_card" /proc/asound/cards 2>/dev/null; then
            AUDIO_PROFILE="$audio_candidate"
            break
        fi
    done
fi
AUDIO_PROFILE_NAME=
[ -z "$AUDIO_PROFILE" ] || AUDIO_PROFILE_NAME=$(basename "$AUDIO_PROFILE" .conf)
if [ -n "$AUDIO_PROFILE_NAME" ] && [ ! -f "$AURORA/etc/audio-owner.conf" ]; then
    cp -f "$AUDIO_PROFILE" "$AURORA/etc/audio-owner.conf"
    chmod 0640 "$AURORA/etc/audio-owner.conf"
    ui_print "- Direct audio ownership profile: $AUDIO_PROFILE_NAME (manual gate only)"
fi
if [ "$AUDIO_PROFILE_NAME" = guacamoleb ] && \
   [ -f "$AURORA/guest-tools/90-aurora-direct.conf" ] && \
   [ -d "$GUEST_ROOT/etc/pipewire/pipewire.conf.d" ]; then
    cp -f "$AURORA/guest-tools/90-aurora-direct.conf" \
        "$GUEST_ROOT/etc/pipewire/pipewire.conf.d/90-aurora-direct.conf"
    chmod 0644 "$GUEST_ROOT/etc/pipewire/pipewire.conf.d/90-aurora-direct.conf"
fi

# Keep the payload out of the mounted module dir.
rm -rf "$MODPATH/tools" "$MODPATH/guest-tools" "$MODPATH/guest-assets" "$MODPATH/device-profiles" \
    "$MODPATH/audio-profiles" "$MODPATH/guest-config"

# Running the Aurora kernel? Warn, don't block --- module install before
# kernel flash is a legitimate order of operations.
if [ ! -e /proc/self/ns/pid ] || ! zcat /proc/config.gz 2>/dev/null | grep -q ANDROID_BINDERFS=y; then
    ui_print "! Note: Aurora kernel not detected (yet) --- guest won't start until it's flashed"
elif ! zcat /proc/config.gz 2>/dev/null | grep -q '^CONFIG_VT=y'; then
    # Kernel #3 marker: VT is off in stock and in kernels #1/#2.
    ui_print "! Note: pre-#3 Aurora kernel --- VT / nftables / IPv6-NAT need a kernel update"
fi

ui_print "- Toolkit installed to $AURORA/bin"
ui_print "- Next: install a guest rootfs + static lxc, then $AURORA/bin/desktop-on"
