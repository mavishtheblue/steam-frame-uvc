# How the build works

## Files

| Path | Role |
| --- | --- |
| `install.sh` | Checks it is on SteamOS/aarch64, builds into a temp dir, installs the modules to `/srv/frame-uvc/<kernel>/`, installs and starts `frame-uvc.service`. Exits early if the kernel already ships `uvcvideo`. |
| `src/build.sh <outdir>` | Downloads headers and sources, patches, builds, writes the `.ko` files and a `load-order` list. Used by `install.sh` and by the boot service. |
| `src/load.sh` | Run at boot as root. Builds for a new kernel if needed (waits for the network), then `insmod`s each module in `load-order`, skipping any already loaded. |
| `src/frame-uvc.service` | Oneshot unit that runs `load.sh`. |
| `uninstall.sh` | Disables the service, unloads the modules if idle, removes `/srv/frame-uvc`. |

## build.sh, step by step

1. Reads the kernel package from `/usr/lib/modules/$(uname -r)/pkgbase` and requires the repository's `<pkg>-headers` to be the same version. If they differ, a SteamOS update is pending: install it and reboot first.
2. Downloads and unpacks the headers package (no install; nothing touches `/usr`).
3. Picks the source tag: `6.18.0-gXXXX` gives `v6.18`, `6.18.3-...` tries `v6.18.3` and falls back to `v6.18`.
4. Downloads every `.c`/`.h` in `drivers/media/usb/uvc` at that tag through the GitHub API.
5. Applies the small-payload fix below if the old line is present.
6. Adds `uvc.c` (`drivers/media/common`) and `videobuf2-vmalloc` only if the running kernel does not already export `uvc_format_by_guid` / `vb2_vmalloc_memops`.
7. Builds with `make -C <headers> M=<src>` and checks each module's vermagic matches the running kernel.

The sources are deleted after the build; nothing from the kernel is kept in this repository or under `/srv`.

## The small-payload fix

`uvc_init_video_bulk()` calls `uvc_alloc_urb_buffers(stream, size, psize)` with `size = dwMaxPayloadTransferSize` and `psize` the endpoint's packet size. When both are 64, `npackets = DIV_ROUND_UP(64, 64) = 1`, and the old retry loop

```c
for (; npackets > 1; npackets /= 2) {
```

never runs, so the function returns 0 and stream start fails with `-ENOMEM`. Mainline changed the condition to `npackets > 0` in January 2026 ("media: uvcvideo: Fix allocation for small frame sizes"). The upstream patch also resets `stream->urb_size` on failure; in v6.18 every failure path already does that through `uvc_free_urb_buffers()`, so only the loop condition is changed.

Confirmed on a Steam Frame with v6.18: an OpenIris (ESP32-S3, full-speed bulk) camera failed with `[Errno 12] Cannot allocate memory` before the fix and streamed after it.

## Reloading after a change

`load.sh` skips modules that are already loaded, so after reinstalling:

```bash
sudo rmmod uvcvideo          # fails while something holds /dev/video* open; stop it first, or reboot
sudo systemctl restart frame-uvc
```
