#!/system/bin/sh
# The PC validates every artifact and retains a verified boot backup before this script runs.
set -eu
stage=$1 distro=$2 hostname=$3 version=$4 display_name=$5
AURORA=/data/aurora
case "$distro" in debian|arch|alpine) ;; *) exit 2 ;; esac
case "$hostname" in ''|*[!a-z0-9-]*) exit 2 ;; esac
case "$version" in ''|*[!0-9]*) exit 2 ;; esac
[ -n "$display_name" ] && [ "${#display_name}" -le 64 ] || exit 2
if printf '%s' "$display_name" | grep -q '[[:cntrl:]:,]'; then
    exit 2
fi
if [ -x "$AURORA/lxc/bin/lxc-info" ]; then
    if [ -f "$AURORA/guest/config" ]; then
        [ "$("$AURORA/lxc/bin/lxc-info" -P "$AURORA" -n guest -sH)" = STOPPED ]
    else
        running=$("$AURORA/lxc/bin/lxc-ls" -P "$AURORA" --running -1) || exit 1
        if printf '%s\n' "$running" | grep -qx guest; then
            echo 'Guest is running without a config; stop it before installing.'
            exit 1
        fi
    fi
fi
if [ -d "$AURORA/versions/$version" ]; then
    [ -x "$AURORA/libexec/guest-distro" ] || { echo 'Existing module version is incomplete.'; exit 1; }
    [ "$(readlink -f "$AURORA/current")" = "$AURORA/versions/$version" ] || {
        echo 'This module version exists but is not active. Resolve the existing installation before retrying.'
        exit 1
    }
    echo "Reusing active module version $version."
else
    magisk --install-module "$stage/module"
fi
mkdir -p "$AURORA/lxc"
runtime="$AURORA/lxc/bin.new.$$"
mkdir -m 700 "$runtime"
tar -xzf "$stage/runtime" -C "$runtime"
for tool in lxc-start lxc-stop lxc-attach lxc-info lxc-ls lxc-console lxc-execute; do
    [ -f "$runtime/$tool" ] && [ ! -L "$runtime/$tool" ]
    chmod 0755 "$runtime/$tool"
done
"$runtime/lxc-start" --version
previous="$AURORA/lxc/bin.previous.$$"
[ ! -d "$AURORA/lxc/bin" ] || mv "$AURORA/lxc/bin" "$previous"
if ! mv "$runtime" "$AURORA/lxc/bin"; then
    [ ! -d "$previous" ] || mv "$previous" "$AURORA/lxc/bin"
    exit 1
fi
inventory=$("$AURORA/libexec/guest-distro" list)
if ! printf '%s\n' "$inventory" | grep -q "^$distro|installed|"; then
    "$AURORA/libexec/guest-distro" install "$distro" "$stage/rootfs"
fi
# Older module installers created an asset directory where the pointer belongs.
if [ ! -L "$AURORA/active-guest" ] && [ -d "$AURORA/active-guest" ]; then
    for init in sbin/init bin/init; do
        if [ -e "$AURORA/active-guest/$init" ] || [ -L "$AURORA/active-guest/$init" ]; then
            echo 'Active guest is a real rootfs directory; refusing automatic relocation.'
            exit 1
        fi
    done
    pointer_backup="$AURORA/active-guest.saved.$(date +%s).$$"
    [ ! -e "$pointer_backup" ] && [ ! -L "$pointer_backup" ]
    mv "$AURORA/active-guest" "$pointer_backup"
    echo "Preserved misplaced guest assets at $pointer_backup."
fi
"$AURORA/libexec/guest-distro" activate "$distro"
root=$("$AURORA/libexec/guest-distro" root)
[ -d "$root/etc" ]
[ -f "$root/etc/passwd" ] || { echo 'Active guest has no passwd database.'; exit 1; }
passwd_new="$root/etc/passwd.new.$$"
export AURORA_DISPLAY_NAME="$display_name"
if ! awk -F: -v OFS=: '
    $3 == 1000 { $5 = ENVIRON["AURORA_DISPLAY_NAME"]; found = 1 }
    { print }
    END { if (!found) exit 1 }
' "$root/etc/passwd" > "$passwd_new"; then
    rm -f "$passwd_new"
    echo 'Active guest has no uid-1000 account.'
    exit 1
fi
chmod 0644 "$passwd_new"
mv -f "$passwd_new" "$root/etc/passwd"
printf '%s\n' "$hostname" > "$root/etc/hostname"
printf 'hostname=%s\n' "$hostname" > "$AURORA/etc/installer.conf.new"
chmod 0600 "$AURORA/etc/installer.conf.new"
mv "$AURORA/etc/installer.conf.new" "$AURORA/etc/installer.conf"
echo "Userspace installed. Previous runtime retained at $previous."
