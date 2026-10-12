#!/bin/bash
# Remove the boot service, the built modules, and unload the driver if idle.
set -uo pipefail
SERVICE=frame-uvc.service

sudo systemctl disable --now "$SERVICE" 2>/dev/null
sudo rm -f "/etc/systemd/system/$SERVICE"
sudo systemctl daemon-reload
for m in uvcvideo videobuf2_vmalloc uvc; do
    grep -q "^$m " /proc/modules && { sudo rmmod "$m" || echo "couldn't unload $m (in use?); it goes away at reboot"; }
done
sudo rm -rf /srv/frame-uvc
echo "frame-uvc removed."
