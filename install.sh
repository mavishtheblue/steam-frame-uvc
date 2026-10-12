#!/bin/bash
# Build and load the missing uvcvideo driver on Steam Frame.
# SteamOS ships without CONFIG_MEDIA_USB_SUPPORT, so USB webcams never appear
# as /dev/video nodes. This builds uvcvideo against the running kernel and
# loads it at boot.
#
#   ./install.sh
#
# After a SteamOS update that changes the kernel, the boot service rebuilds
# the driver itself. That rebuild needs a network connection.
set -euo pipefail

INSTALL_DIR=/srv/frame-uvc
SERVICE=frame-uvc.service
REPO="$(cd "$(dirname "$0")" && pwd)"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -m)" = aarch64 ] || die "this is for Steam Frame (aarch64)"
grep -q '^ID=steamos' /etc/os-release || die "this is for SteamOS"
[ "$EUID" -ne 0 ] || die "run as your normal user (it asks for sudo when needed)"
for tool in pacman curl bsdtar make gcc python3 modinfo sudo; do
    command -v "$tool" >/dev/null || die "missing required tool: $tool"
done

KVER="$(uname -r)"
if modinfo -k "$KVER" uvcvideo >/dev/null 2>&1; then
    say "This kernel already ships UVC support; nothing to do."
    exit 0
fi

WORK="$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/frame-uvc.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

TMPDIR="$WORK" "$REPO/src/build.sh" "$WORK/out" || die "build failed"
mapfile -t MODULES < "$WORK/out/load-order"

say "Installing (sudo)"
sudo install -d -m 755 "$INSTALL_DIR/$KVER"
for m in "${MODULES[@]}"; do
    sudo install -m 644 "$WORK/out/$m.ko" "$INSTALL_DIR/$KVER/$m.ko"
done
sudo install -m 644 "$WORK/out/load-order" "$INSTALL_DIR/$KVER/load-order"
sudo install -m 755 "$REPO/src/build.sh" "$INSTALL_DIR/build.sh"
sudo install -m 755 "$REPO/src/load.sh" "$INSTALL_DIR/load.sh"
sudo install -m 644 "$REPO/src/$SERVICE" "/etc/systemd/system/$SERVICE"
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE" >/dev/null 2>&1
sudo systemctl restart "$SERVICE"

sleep 1
say "UVC driver loaded. It will load at boot and rebuild after a kernel update."
found=0
for d in /sys/class/video4linux/video*; do
    [ -e "$d/device/driver" ] || continue
    [ "$(basename "$(readlink "$d/device/driver")")" = uvcvideo ] || continue
    echo "    /dev/${d##*/}: $(cat "$d/name")"
    found=1
done
[ "$found" = 1 ] || echo "    No UVC device attached right now. Plug the camera in."
echo "    Check with: lsmod | grep uvc"
echo "    Logs: journalctl -u $SERVICE"
