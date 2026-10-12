# steam-frame-uvc

Builds and loads the `uvcvideo` driver on the Steam Frame, so a USB webcam shows up as `/dev/video*`.

SteamOS on the Frame is built without `CONFIG_MEDIA_USB_SUPPORT`, so plugging in a UVC camera does nothing. The installer downloads the matching Valve kernel headers and the upstream `uvcvideo` sources, builds the modules, and installs a boot service that loads them. After a kernel update, the service rebuilds them on the next boot if the network is up.

Unofficial. Not affiliated with or endorsed by Valve.

## Install

Desktop mode or SSH, as your normal user (it asks for sudo when it needs it):

```bash
chmod +x install.sh uninstall.sh src/build.sh src/load.sh
./install.sh
```

Then plug the camera in and check:

```bash
lsmod | grep uvc
ls /sys/class/video4linux/
journalctl -u frame-uvc     # what the boot service did
```

Everything installs under `/srv/frame-uvc/`, with the boot service `frame-uvc.service`.

## Remove

```bash
./uninstall.sh
```

## Changes from the upstream driver

`src/build.sh` builds the driver from the `torvalds/linux` tag matching the running kernel, with two adjustments:

- **Small bulk payloads.** Kernels before early 2026 fail to start a stream when one USB packet holds a whole UVC payload (`npackets == 1` in `uvc_alloc_urb_buffers()`), and report `Cannot allocate memory`. Full-speed bulk cameras with 64-byte payloads hit this, for example an ESP32-S3 running OpenIris firmware in UVC mode. The build applies the one-character fix from mainline ("media: uvcvideo: Fix allocation for small frame sizes") when the downloaded source still has the old loop. Isochronous webcams are not affected either way.
- **Stable point releases.** `torvalds/linux` has no stable tags, so for a kernel such as `6.18.3` the build falls back to the `v6.18` sources.

Details in [docs/NOTES.md](docs/NOTES.md).

## Requirements

`pacman`, `curl`, `bsdtar`, `make`, `gcc`, `python3`, `modinfo` and `sudo`, all present on SteamOS. The first build and any rebuild after a kernel update need network access.

## Licence and credits

The scripts are MIT licensed (see [LICENSE](LICENSE)). The driver logic is adapted from [SaberMage/shadowcast-on-frame](https://github.com/SaberMage/shadowcast-on-frame) (MIT), with its game-launcher and ShadowCast-specific parts removed.

This repository contains no kernel code. The Linux sources and Valve headers that `build.sh` downloads at build time, and the modules built from them, are under the GPL-2.0 like the rest of the kernel.
