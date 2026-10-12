#!/bin/bash
# Run at boot by frame-uvc.service, as root. Load the UVC modules for the
# running kernel, building them first if this kernel has none yet.
set -u
ROOT="${FRAME_UVC_ROOT:-/srv/frame-uvc}"
KVER="$(uname -r)"
DIR="$ROOT/$KVER"

if [ ! -f "$DIR/load-order" ]; then
    echo "No UVC modules for kernel $KVER yet; building them."
    for i in $(seq 60); do
        curl -fsS --connect-timeout 5 -o /dev/null https://api.github.com && break
        [ "$i" = 1 ] && echo "Waiting for the network..."
        sleep 5
    done
    TMP="$(mktemp -d "$ROOT/.build-$KVER.XXXXXX")"
    if TMPDIR=/var/tmp "$ROOT/build.sh" "$TMP"; then
        rm -rf "$DIR" && mv "$TMP" "$DIR" && chmod 755 "$DIR"
        for old in "$ROOT"/*/; do
            [ "${old%/}" = "$DIR" ] || rm -rf "$old"
        done
    else
        rm -rf "$TMP"
        echo "Build failed; run install.sh again to retry."
        exit 1
    fi
fi

rc=0
while read -r m; do
    [ -n "$m" ] || continue
    if grep -q "^${m//-/_} " /proc/modules; then
        echo "$m already loaded"
    elif insmod "$DIR/$m.ko"; then
        echo "loaded $m"
    else
        echo "failed to load $m"
        rc=1
    fi
done < "$DIR/load-order"
exit $rc
