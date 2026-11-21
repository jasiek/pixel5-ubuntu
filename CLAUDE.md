# Working on this repo

Pixel 5 (redfin, SM7250) → plain headless Ubuntu 24.04. Sibling of the Pixel 2
project at `../ubuntu-touch-pixel2`; same methods, rules and lessons.

## Where things are

- `PLAN.md`: the checklist. Start at **▶ RESUME HERE**. After a step, tick its
  box and move the pointer.
- `docs/log.md`: dated notes. Every phone test gets a number (`Test 1: ...`):
  what was run, what was measured, what it means.
- `docs/research.md`: summary; `docs/research/*.md`: full research reports.
- `docs/device-info.md`: phone facts (created in P1.2).
- `external/`: third-party code as pinned git submodules.

## Commits

- Commit after every change: each file, each ticked box, each log entry.
- Message style: `P3.2: what changed` or `plan/log: ...`. The body says why.
- End with `Co-Authored-By: Claude ...` only. **Never** include Claude session
  references (no `Claude-Session:` line, no session URLs or IDs).
- Don't push unless asked.
- New files get an `SPDX-License-Identifier` header (MIT for original work,
  GPL-2.0-only for kernel patches/DTs, upstream terms for borrowed code).
- Third-party software goes in a pinned submodule under `external/`. Never an
  ad-hoc clone or a `git clone` in a Dockerfile. Check its license first.
- Exception (owner, 2026-11-19): single third-party patch files (e.g. a lore
  series via `b4 am`) may be committed unmodified, each with its origin
  recorded: list URL / Message-ID or source repo + commit, and its license.

## Never commit or print

- **The phone's serial number**: `fastboot devices`, `/dev/cu.usbmodem*`
  names, `androidboot.serialno` in `/proc/cmdline`. Grep single keys out of
  `/proc/cmdline`, never the whole line.
- **IMEI / calibration backups** (`persist`, `modemst1/2`, `fsg`, `fsc`): they
  live in `firmware/backup/` on the Mac only.
- Firmware, images, vendor blobs: `firmware/` and `build/` are gitignored.
  Vendor blobs never leave the phone except into `firmware/`.
- Wifi credentials and the wifi MAC.

## Phone safety

- **Never boot stock Android** once Ubuntu is on userdata: it offers a factory
  reset that wipes the rootfs.
- Confirm with the owner before any `fastboot flash`. Flashing `userdata`
  wipes the phone.
- **Never write to `sdb`, `sdc`, `sde`** (xbl, ABL, TZ, vbmeta chain) or any
  bootloader partition. Use partlabels, never `/dev/sdX` numbers.
- Always flash an explicit slot (`boot_a`, `vendor_boot_b`). Experiments with
  `vendor_boot` / `dtbo` go to the **inactive** slot only; the other slot is the
  way back (`fastboot --set-active=<slot>`).
- `boot_b` holds our kernel, flashed with an AVB hash footer; without the
  footer the bootloader refuses it, and then even `fastboot boot` fails.
  Since 2026-11-20 (P6.5) that is **mainline**
  (`scripts/build-mainline-test.sh default`, header v2 with its own DTB;
  since Test 174 release `g7926d9799a68` with display, touch, speakers
  and microphone). Back to the previous mainline (speakers, no mics):
  `fastboot flash boot_b build/backup/boot_b-mainline-g62ce6353bb75-2026-11-21.img`.
  Back to downstream: `fastboot flash boot_b build/backup/boot_b-downstream-2026-11-20.img`
  (header v3, uses `vendor_boot_b`; `AVB_FOOTER=1 scripts/make-bootimg.sh`
  rebuilds it). A plain mainline reboot shows `bootreason=watchdog`: expected
  (Test 32), not a hang. Restore Android with
  `fastboot flash boot_b firmware/boot.img` (and never boot it with Ubuntu on
  userdata).
- Test tethered first with `fastboot boot`. Note: on redfin this still uses the
  **flashed** vendor_boot (DTB, vendor ramdisk, cmdline).
- **OLED burn-in**: never leave a static image lit.
- Don't scan an I2C/SPI bus whose devices are unpowered.

## How to work

- Carry on until the owner is really needed. Owner actions should be small and
  concrete.
- Hardware questions: read the downstream DT first
  (`external/kernel-redbull/arch/arm64/boot/dts/google/lito-redfin*.dtsi`,
  board `lito-v2-redfin-pvt`), then the live DT (`firmware/live.dtb`), then the
  other SM7250 mainline ports (nairo, avicii, picasso; see
  `docs/research/mainline.md`).
- Measure before claiming, and compare within one boot. When a cause is
  unproven, say so in the log.
- When something can't be reproduced on demand, make the tooling tolerate it
  (retry) and log the failure pattern, rather than guessing a fix.
- Keep one change per test image, so a failure points at one thing.
- The Mac shell is zsh with BSD tools (`sed -i ''`, `-E`). The clone must be
  on a case-sensitive volume. Builds run in arm64 Docker.
