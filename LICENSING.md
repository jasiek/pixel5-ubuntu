# Licensing

**Default:** original material in this repository is under the MIT License
(`LICENSE`). That covers the scripts, build recipes, initramfs and runtime
helpers, service and configuration files, and the documentation, except
where a file or the table below says otherwise.

The MIT license does **not** cover:
- third-party code in `external/`;
- vendor firmware;
- the images this repo builds.

A file's own `SPDX-License-Identifier` line, where present, wins over this
default. `REUSE.toml` is the machine-readable version; check with
`reuse lint`.

## Exceptions

| What | License | Why |
|---|---|---|
| Kernel patches (`kernel/**/*.patch`) and device trees (`kernel/**/*.dts`, `*.dtsi`) | GPL-2.0-only (`LICENSES/GPL-2.0-only.txt`, added with the first such file: `reuse download GPL-2.0-only`) | They modify or extend the Linux kernel and vendor device trees, which are GPL-2.0. |
| Material adapted from the Pixel 2 project (`../ubuntu-touch-pixel2`) | MIT | Same owner, same license. Anything there under other terms is not copied without its notice. |
| `external/*` (git submodules) | Their own licenses | Each submodule's license is checked before it is added and recorded in `docs/log.md` with its revision. Sources without a license (for example `sohalartz/redfin-postmarketos`) are read for reference only and never added. |

## Firmware and vendor files

Nothing proprietary is in this repository:
- `firmware/` and `build/` are git-ignored.
- Google's factory image is downloaded from Google, under Google's terms.
- Firmware the phone needs is taken from its own partitions.
- IMEI and calibration backups (`firmware/backup/`) never leave the Mac.

Converting a blob (for example squashing it with pil-squasher) doesn't
change its license or grant any right to redistribute it.

## Built images

Boot images and the rootfs combine many licenses (Linux and BusyBox
GPL-2.0, Ubuntu packages under their own terms, and others). They are not
MIT. Before any image is published, its contents, notices, GPL/LGPL
source obligations and firmware terms must be accounted for. Images
aren't published today.
