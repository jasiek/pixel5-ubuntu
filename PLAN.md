# Pixel 5 → Ubuntu 24.04 (headless first): Plan

**Goal:** the Pixel 5 (redfin, SM7250) powers on straight into plain Ubuntu 24.04 arm64, reachable over SSH (USB and wifi). No Android at runtime. Same approach as the Pixel 2 project (`../ubuntu-touch-pixel2`): everything built from source, pinned submodules, rootfs on userdata.

## ▶ RESUME HERE: phone needed for P1.1. Offline prep meanwhile: factory-image script, v3 boot image script, 4.19 test build.

---

## How to use this file
1. Find **RESUME HERE** above and do that step.
2. Tick its box (`- [ ]` → `- [x]`), add a one-line italic result, move the RESUME HERE pointer.
3. Commit right away: `git commit -am "plan: tick P1.4"`.
4. Something went wrong or you made a decision? Add a dated, numbered test entry to `docs/log.md` and commit.
5. A **Gate** is a check that must pass before moving on. If it fails, stop and log it.

Background: `docs/research.md` (summary) and `docs/research/*.md` (full agent reports, 2026-11-18). Phone details: `docs/device-info.md` (created in P1.2).

**Back to stock Android anytime:** bootloader (power off, hold **Vol-Down + Power**) → `flash-all.sh` from the factory image. This erases the phone.

---

## Decision D1: which route (owner)

- [x] **D1** _Done 2026-11-19: owner picked **A**._ Pick one:
  - **A. Plain Ubuntu 24.04, own kernel (recommended).** Downstream 4.19 kernel first for a quick SSH shell (as the Pixel 2 used 4.4), then mainline. Matches the Pixel 2 methods. Days to SSH, weeks to months for mainline.
  - **B. Ubuntu Touch 24.04 community port** (Halium 13, 4.19, Android 13 base; UBports GitLab `community-ports/android13/google-pixel-5`). About 1 h to a full phone UI with calls, wifi and camera. Images are built by UBports, not by us; there is an Android container at runtime. Kept as a reference and fallback either way.
  - Why A: the goal is "no Android at runtime, built from source". B contradicts both. B's kernel tree and firmware lists are still useful references for A.

## What is different from the Pixel 2

| | Pixel 2 (walleye) | Pixel 5 (redfin) | Plan impact |
|---|---|---|---|
| Boot image | header v0, DTB appended | header v3; DTB + vendor ramdisk in `vendor_boot`; `dtbo` overlays | new `make-bootimg.sh`; `fastboot boot` always uses the **flashed** vendor_boot |
| Vendor firmware | `vendor_a` partition | inside `super` (dynamic partitions) | dm-linear map (`parse-android-dynparts`) to read it |
| Modem firmware | `modem_a` | `modem_a`, vfat | small change |
| Fallback kernel | 4.4, mostly built in | 4.19 (LineageOS, 4.19.325); UFS/USB/display are **modules** | initramfs must load modules in order |
| Mainline | Porthole msm8998 patches existed | **nothing upstream boots**; 3 out-of-tree SM7250 phones (nairo, avicii, picasso) | assemble our own tree; boot path is unknown |
| Status LED | RGB notification LED | **none** | different "phone is alive" signal (P5.5) |
| Final firmware | Android 11 | Android 14, `UP1A.231105.001.B2` | |

---

## Phase 0: Repo setup (1–2 h)
- [x] **P0.1** _Done 2026-11-18: `PLAN.md`, `CLAUDE.md`, `README.md`, `docs/research.md` + `docs/research/`, `docs/log.md`, `.gitignore`._
- [x] **P0.2** _Done 2026-11-19: scripts (dev, check-prereqs, ssh, try-boot, initrd-sh, serial-sh, push-overlay, build-initramfs), initramfs/, one docker/Dockerfile (24.04 + LLVM 18 + rootfs tools; the 20.04/clang-11 image was 4.4-only). `dev.sh uname -m` → aarch64; initramfs builds; no walleye in scripts/._ Copy the generic tooling from the Pixel 2 repo (list: `docs/research/pixel2-transfer.md`, "REUSE AS-IS"): `scripts/dev.sh`, `check-prereqs.sh`, `ssh.sh`, `try-boot.sh`, `initrd-sh.py`, `serial-sh.py`, `push-overlay.sh`, `docker/Dockerfile`, the busybox initramfs skeleton. Rename `pixel2`→`pixel5`, `PIXEL2_HOST`→`PIXEL5_HOST`.
  - Gate: `scripts/dev.sh uname -m` prints `aarch64`; `grep -rn walleye scripts/` is empty.
- [x] **P0.3** _Done 2026-11-19: `LICENSE` (MIT), `LICENSING.md`, `LICENSES/MIT.txt`, `REUSE.toml` (MIT default, GPL-2.0-only for kernel patches/DTs), `scripts/reuse-lint.sh`. Compliant, 25/25 files. GPL-2.0 text gets added with the first kernel file (REUSE rejects unused license texts)._ Licensing from day one (Pixel 2 P10 done up front): `LICENSE` (MIT), `LICENSING.md`, `LICENSES/`, `REUSE.toml`, SPDX headers.
  - Gate: `reuse lint` passes.
- [x] **P0.4** _Done 2026-11-19 (revisions in docs/log.md); added `external/lpunpack` for vendor.img out of super.img. Clone moved to `/Volumes/Pixel2Dev/pixel5-ubuntu` (case-sensitive) on 2026-11-19._ Submodules (shallow, pinned): `external/mkbootimg`, `external/avb` (avbtool), `external/kernel-redbull` (LineageOS `android_kernel_google_redbull`, branch `lineage-24.0`), `external/qbootctl`, `external/pil-squasher`, `external/parse-android-dynparts`. Mainline trees come in P6.1.
  - Record each branch + commit in `docs/log.md`.

## Phase 1: Phone prep (1–2 h, needs the phone, ⚠️ wipes it)
- [ ] **P1.1** Back up anything you want from the phone. Unlocking erases it.
- [ ] **P1.2** Settings → About phone: Android version, build number, storage, model → `docs/device-info.md`.
- [ ] **P1.3** Tap *Build number* 7×, turn on **OEM unlocking** + **USB debugging**.
  - Gate: OEM unlocking is not greyed out (Verizon units can't be unlocked).
- [ ] **P1.4** `adb reboot bootloader`, `fastboot flashing unlock` (confirm on phone), `fastboot getvar unlocked`.
  - Gate: `unlocked: yes`.
- [ ] **P1.5** Download the final factory image (`UP1A.231105.001.B2`, Android 14) from developers.google.com/android/images#redfin into `firmware/`; record its SHA-256 from the page. If the phone is on an older build, run its `flash-all.sh`.
  - Gate: phone boots Android 14 with the matching build number.
- [ ] **P1.6** **Last chance with Android running**, inventory over `adb shell` (non-root; record what is readable): `ls -lR /vendor/firmware /vendor/firmware_mnt/image /vendor/etc/sensors`, `ls -l /dev/block/by-name`, `getprop | grep -E 'ro.boot|ro.product|ro.hardware'` (drop `serialno`), `zcat /proc/config.gz` if readable → `docs/device-info.md` / `firmware/` (gitignored).
  - Why: the mainline report could not confirm firmware file names; this answers it in 5 minutes.
- [ ] **P1.7** `fastboot getvar all 2>&1 | tee firmware/getvar-all.txt`. Note slot, sizes of boot, vendor_boot, dtbo, super, userdata, modem. Strip the serial before committing anything.
- [ ] **P1.8** From the factory zip extract `boot.img`, `vendor_boot.img`, `dtbo.img`, `vbmeta.img`, `super` (via `lpunpack` → `vendor.img`) into `firmware/`.
- [ ] **P1.9** `unpack_bootimg` both boot images → `docs/device-info.md`: header versions, cmdline (boot + vendor_boot), kernel/ramdisk offsets, page size, vendor ramdisk contents (is there an `/init`? which `.ko` + `modules.load`?), DTB `msm-id` / `board-id`.
- [ ] **P1.10** `fastboot boot firmware/boot.img`.
  - Gate: Android boots. Proves tethered boots work. If refused, retry with an AVB hash footer (`avbtool add_hash_footer --partition_size 100663296`) and log which one worked.

## Phase 2: Debug shell on the stock kernel (2–4 h, nothing flashed)
Why first: the stock kernel matches the stock vendor_boot modules, so UFS and USB load with zero kernel work. We get a Linux shell before building anything, and use it for backups.
- [ ] **P2.1** _Prepared 2026-11-19 (untested on the phone): modules.load in two passes, 15 s UDC wait, userdata mounted only with ext4 label `ubuntu`._ `scripts/build-initramfs.sh` (adapted): busybox `/init` that `insmod`s from the vendor ramdisk's `/lib/modules` in `modules.load` order, starts a configfs NCM/ECM gadget at `172.16.42.1`, runs `telnetd`, never mounts userdata read-write, and returns to fastboot after 10 min.
- [ ] **P2.2** _Prepared 2026-11-19: all fields from the factory boot.img via `unpack_bootimg --format=mkbootimg`; tested on a synthetic v3 image._ `scripts/make-bootimg.sh` for header v3: stock kernel from `firmware/boot.img` + our ramdisk (+ AVB footer if P1.10 needed it).
- [ ] **P2.3** `scripts/try-boot.sh build/boot-stock-debug.img`.
  - Gate: telnet or USB-serial shell. If the vendor ramdisk's `/init` wins over ours (reported by AginxOS, unverified): log it, try `rdinit=`, then a renamed init.
- [ ] **P2.4** ⚠️ **Backups before anything else touches the phone:** `dd` `persist`, `modemst1`, `modemst2`, `fsg`, `fsc` (IMEI + calibration) to `firmware/backup/` on the Mac.
  - Gate: SHA-256 equal on phone and Mac. Never committed, never leaves the Mac.
- [ ] **P2.5** Inventory: `/proc/cmdline` single keys only (never `serialno`), `/sys/firmware/fdt` → `firmware/live.dtb` (the DT **after** dtbo overlay; the board DTS reference for P6.3), `/dev/block/by-name`, LUN layout → `docs/device-info.md`.
- [ ] **P2.6** Map `vendor_a` out of `super` with dm-linear (`parse-android-dynparts` + `dmsetup`) and mount it read-only; mount `modem_a` (vfat) read-only.
  - Gate: firmware lists match P1.6.

## Phase 3: Ubuntu on the downstream kernel (1–3 days)
- [ ] **P3.1** Can Ubuntu run on the **stock** kernel? Check its config (P1.6/P2) for systemd needs: `DEVTMPFS`, `FHANDLE`, `CGROUPS`, `AUTOFS_FS`, namespaces, `SECCOMP`, `TMPFS_XATTR`. All present → skip P3.2 for milestone 1 and log it.
- [ ] **P3.2** `scripts/build-kernel.sh`: LineageOS 4.19 `redbull_defconfig` + `kernel/redfin-ubuntu.config` (systemd options above; static usermode helper off; firmware user-helper fallback off; USB `CONFIGFS_NCM`). Build first-stage drivers in (`=y`) where possible; ship the rest in our initramfs, since vendor ramdisk modules won't match our vermagic.
  - Gate: compiles; `fastboot boot` reaches the P2 debug shell with our modules.
- [ ] **P3.3** `scripts/build-rootfs.sh` (adapted): ext4 label **`ubuntu`** (the initramfs refuses anything else), ubuntu-base 24.04, hostname `pixel5`, user `ubuntu` + SSH keys, NetworkManager, avahi, USB gadget unit, kernel modules → ext4 `build/rootfs.img` → `img2simg`.
- [ ] **P3.4** initramfs: find userdata by partlabel, `resize2fs` once, `switch_root`; debug shell on failure.
- [ ] **P3.5** ⚠️ (owner OK) `fastboot flash userdata build/rootfs.simg`, then `scripts/try-boot.sh build/boot.img`.
  - Gate: `ssh ubuntu@172.16.42.1` works. 🎉 **Milestone 1: Ubuntu 24.04 runs on the Pixel 5.**
- [ ] **P3.6** Save `uname -a`, `systemctl --failed`, notable `dmesg` errors in `docs/log.md`.

## Phase 4: Wifi on the downstream kernel (2 h – 3 days)
- [ ] **P4.1** systemd units: vendor (dm-linear from super, P2.6) and `modem_a` mounted read-only where the kernel looks for firmware.
- [ ] **P4.2** Gate: `wlan0` exists. WCN3990 needs the modem up first.
- [ ] **P4.3** No `wlan0`? Try the open-source daemons first (`rmtfs`, `tqftpserv`, `pd-mapper`, `qrtr`; start order from the Pixel 2 mainline lesson: tqftpserv + diag before `rmtfs -s`). Then fall back to running vendor daemons (`cnss-daemon` etc.) directly, as the Pixel 2 did on 4.4 (its dropped `android-env` helpers).
- [ ] **P4.4** Stable MAC (generate once, persist), `nmcli dev wifi connect`, baked-in NM profile.
  - Gate: `ssh ubuntu@pixel5.local` with the cable unplugged.

## Phase 5: Make it permanent (1–2 h, ⚠️ flashes)
- [ ] **P5.1** (owner OK) `fastboot --disable-verity --disable-verification flash vbmeta_a firmware/vbmeta.img`, same for `vbmeta_b`.
- [ ] **P5.2** (owner OK) `fastboot flash boot_a build/boot.img` and `boot_b`. vendor_boot stays stock on the downstream route.
- [ ] **P5.3** Mark the slot successful at boot (`qbootctl`; untested on redfin).
  - Gate: after 3 boots `fastboot getvar slot-successful:<slot>` is `yes`.
- [ ] **P5.4** Power off, press power. Then 5 reboots.
  - Gate: SSH over wifi within 60 s every time. 🎉 **Milestone 2: the phone boots into Linux.**
- [ ] **P5.5** Headless tuning: panel off from boot (OLED burn-in), charge limit 70–80 %, `unattended-upgrades`. No notification LED on the Pixel 5: pick an alive signal (short vibration at boot, or a tiny dim pixel moving on the AMOLED). Owner decides.

## Phase 6: Mainline kernel (weeks; research-heavy, mirrors Pixel 2 P8.3)
Source: `docs/research/mainline.md`. No mainline kernel has ever been shown booting on redfin.
- [ ] **P6.1** Assemble a tree, every source a pinned submodule: linux-next (or 7.4) + Sreeshankar K's SM7250 base series (v15) + Ishu Brar's interconnect / gpucc / dispcc / DPU series + cherry-picks from `effeffe/nairoArchLinuxArmTools` (TLMM, UFS, USB, A620, IPA, MPSS, SMB5, QGauge) + `lazybrar/avicii-mainline` (DSC command-mode panel path). Check each tree's license first; `sohalartz/redfin-postmarketos` is reference only (no license, commits blobs and an SSH host key).
  - Gate: it builds a generic SM7250 kernel.
- [ ] **P6.2** **Boot path: the first gate.** How does redfin's bootloader take a mainline DTB? Try, in order, flashing **only the inactive slot** (stock/downstream slot stays the way back via `fastboot --set-active`):
  1. mainline DTB in `vendor_boot_b` with redfin's `msm-id <400 0x20000>, <440 0x20000>` and `board-id <0x0b1e05 0>`, plus a dtbo "sink" (Pixel 2 technique, generated by script);
  2. erase `dtbo_b` (what avicii needed);
  3. chainload upstream U-Boot (then every kernel test is a plain `fastboot boot`).
  - No UART: debug through pstore/ramoops and USB serial from our initramfs. Kernel loads at offset 0x80000 if ABL insists.
  - Gate: mainline reaches our initramfs and USB serial works.
- [ ] **P6.3** `kernel/mainline/sm7250-google-redfin.dts` from the downstream DT (`lito-redfin*.dtsi`) and `firmware/live.dtb` (P2.5).
- [ ] **P6.4** Bring-up, one change per test image, each `fastboot boot` or inactive slot only:
  - [ ] UFS + USB2 gadget + rootfs (nairo patches; 32-bit DMA mask)
  - [ ] Charger (SMB5) + fuel gauge (QGauge), cpufreq + thermal
  - [ ] Modem (MPSS PAS + Pixel SMEM socinfo quirk, tqftpserv `modem_pr/`, pd-mapper table) → wifi (ath10k_snoc, `board-2.bin` from vendor `bdwlan*`)
  - [ ] GPU A620 (simpledrm first, then msm + Mesa)
  - [ ] Panel S6E3HC2 DSC command mode: **new driver** from downstream DCS sequences
  - [ ] Touch S6SY79x: **SPI transport** for `s6sy761`; GPIO 35 to the AP
  - [ ] Audio: 2x CS35L41 (TDM) + RT5514 mics; watch for ADSP restarts every ~40 s
  - [ ] Bluetooth (hci_qca), haptics (DRV2624: new driver), suspend (s2idle)
- [ ] **P6.5** (owner OK) Flash mainline as default on the active slot; downstream stays on the other.

## Phase 7: One-command build + guided flashing (half a day; copy Pixel 2 P9)
- [ ] **P7.1** `scripts/build-all.sh` (hash-gated steps, as in the Pixel 2): submodules, container, kernel(s), initramfs, boot images, rootfs, firmware staging scripts.
  - Gate: fresh clone → images, no manual steps.
- [ ] **P7.2** `scripts/flash.sh`: checks the phone is redfin + unlocked + on the final build, asks for `yes`, flashes vbmeta/boot/(vendor_boot)/userdata on explicit `_a`/`_b`, waits for SSH. Plus `restore`.
  - Gate: someone else flashes a phone using only README + `flash.sh`.
- [ ] **P7.3** README: install flow.

## Parked (research problems; pick up only on request)
Cameras (no SM7250 CAMSS, no IMX363/IMX481 drivers), rear fingerprint (TrustZone), CDSP + Venus video (TZ refuses on other SM7250 phones), wireless charging (P9382), 5G NR and VoLTE (unproven anywhere), NFC (ST21NFC fit unverified), SSC sensors (needs hexagonrpcd + libssc), modem data/SMS on downstream (needs a SIM).

## Open questions (verify on the phone, cheapest first)
1. Firmware file names in `/vendor/firmware` and `modem_a:image/` (P1.6).
2. Does `fastboot boot` need an AVB footer (P1.10)?
3. Whose `/init` wins: ours or the vendor ramdisk's (P2.3)?
4. Does the stock 4.19 kernel already run systemd (P3.1)?
5. Does a failed dtbo overlay on a custom DTB stop the boot (P6.2)?
6. Does the Pixel modem SMEM socinfo quirk apply under the PAS loader (P6.4)?

## Rough time
| Phases | Estimate |
|---|---|
| 0–2: setup, unlock, stock-kernel debug shell, backups | 1 day |
| 3–5: Ubuntu + wifi on 4.19, flashed (Milestone 2) | 3–7 days |
| 6: mainline to SSH + wifi | 2–4 weeks if P6.2 resolves quickly; open-ended if not |
| 6: display + touch + audio on mainline | another 2–6 weeks |
