# Pixel 5 → Ubuntu 24.04 (headless first): Plan

**Goal:** the Pixel 5 (redfin, SM7250) powers on straight into plain Ubuntu 24.04 arm64, reachable over SSH (USB and wifi). No Android at runtime. Same approach as the Pixel 2 project (`../ubuntu-touch-pixel2`): everything built from source, pinned submodules, rootfs on userdata.

## ▶ RESUME HERE: P6.4 suspend: s2idle 47 mA (QG FIFO, Tests 204/206), AOSS 0; display CX hold fixed (patch 0013, Test 205, module only, not in a flashed image). Next: stop the DSPs/modem before suspend to test firmware-side holders. Release `ga7e4b32f250b` on boot_b (Test 197). Open owner items: P7.2 gate, nairo licence.

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
- [x] **P1.1** _Owner 2026-11-19._ Back up anything you want from the phone. Unlocking erases it.
- [x] **P1.2** _Done 2026-11-19 via getprop: GTT9Q, MP1.0, final build, slot _b; `docs/device-info.md`._ Settings → About phone: Android version, build number, storage, model → `docs/device-info.md`.
- [x] **P1.3** _Done 2026-11-19: not greyed out (`sys.oem_unlock_allowed=1`)._ Tap *Build number* 7×, turn on **OEM unlocking** + **USB debugging**.
  - Gate: OEM unlocking is not greyed out (Verizon units can't be unlocked).
- [x] **P1.4** _Done 2026-11-19: unlocked by the owner._ `adb reboot bootloader`, `fastboot flashing unlock` (confirm on phone), `fastboot getvar unlocked`.
  - Gate: `unlocked: yes`.
- [x] **P1.5** _Zip downloaded by the owner 2026-11-19; SHA-256 `4e5a2679…` pinned in get-firmware.sh and matches. Phone build still to check in P1.2._ Download the final factory image (`UP1A.231105.001.B2`, Android 14) from developers.google.com/android/images#redfin into `firmware/`; record its SHA-256 from the page. If the phone is on an older build, run its `flash-all.sh`.
  - Gate: phone boots Android 14 with the matching build number.
- [x] **P1.6** _Done 2026-11-19: partition map, dtbo_idx 25, kernel, config → `docs/device-info.md`, raw in `firmware/inventory/`. `/vendor/firmware_mnt` (modem) not readable without root: listed in P2.6 instead._ **Last chance with Android running**, inventory over `adb shell` (non-root; record what is readable): `ls -lR /vendor/firmware /vendor/firmware_mnt/image /vendor/etc/sensors`, `ls -l /dev/block/by-name`, `getprop | grep -E 'ro.boot|ro.product|ro.hardware'` (drop `serialno`), `zcat /proc/config.gz` if readable → `docs/device-info.md` / `firmware/` (gitignored).
  - Why: the mainline report could not confirm firmware file names; this answers it in 5 minutes.
- [x] **P1.7** _Done 2026-11-19: `firmware/getvar-all.txt` (serial removed); partition map in `docs/device-info.md`._ `fastboot getvar all 2>&1 | tee firmware/getvar-all.txt`. Note slot, sizes of boot, vendor_boot, dtbo, super, userdata, modem. Strip the serial before committing anything.
- [x] **P1.8** _Done 2026-11-19 by `get-firmware.sh`; vendor.img is its own file in the zip (no lpunpack needed)._ From the factory zip extract `boot.img`, `vendor_boot.img`, `dtbo.img`, `vbmeta.img`, `super` (via `lpunpack` → `vendor.img`) into `firmware/`.
- [x] **P1.9** _Done 2026-11-19: `docs/device-info.md` (v3 both; base DTB generic, board picked from dtbo entry 25 `0xb1e05`; vendor ramdisk = recovery + 218 first-stage modules; stock kernel lacks DEVTMPFS/FHANDLE/AUTOFS/ACM)._ `unpack_bootimg` both boot images → `docs/device-info.md`: header versions, cmdline (boot + vendor_boot), kernel/ramdisk offsets, page size, vendor ramdisk contents (is there an `/init`? which `.ko` + `modules.load`?), DTB `msm-id` / `board-id`.
- [ ] **P1.10** `fastboot boot firmware/boot.img`.
  - Gate: Android boots. Proves tethered boots work. If refused, retry with an AVB hash footer (`avbtool add_hash_footer --partition_size 100663296`) and log which one worked.

## Phase 2: Debug shell on the stock kernel (2–4 h, nothing flashed)
Why first: the stock kernel matches the stock vendor_boot modules, so UFS and USB load with zero kernel work. We get a Linux shell before building anything, and use it for backups.
- [x] **P2.1** _Done 2026-11-19 (Tests 1-9): LZ4-legacy ramdisk (gzip is dropped after the vendor ramdisk), watchdog + msm-poweroff loaded first, modprobe-like loader honouring modules.softdep/dep, firmware fallback off, `initstage=N`/`initmods=N` probes._ `scripts/build-initramfs.sh` (adapted): busybox `/init` that `insmod`s from the vendor ramdisk's `/lib/modules` in `modules.load` order, starts a configfs NCM/ECM gadget at `172.16.42.1`, runs `telnetd`, never mounts userdata read-write, and returns to fastboot after 10 min.
- [x] **P2.2** _Done 2026-11-19: all fields from the factory boot.img via `unpack_bootimg --format=mkbootimg`; no AVB footer needed for `fastboot boot`._ `scripts/make-bootimg.sh` for header v3: stock kernel from `firmware/boot.img` + our ramdisk (+ AVB footer if P1.10 needed it).
- [x] **P2.3** _Done 2026-11-19 (Test 11): ping after 22 s, telnet root shell; 218 modules, 0 failed; gadget on a600000.dwc3. Our `/init` wins over the vendor's._ `scripts/try-boot.sh build/boot-stock-debug.img`.
  - Gate: telnet or USB-serial shell. If the vendor ramdisk's `/init` wins over ours (reported by AginxOS, unverified): log it, try `rdinit=`, then a renamed init.
- [x] **P2.4** _Done 2026-11-19: `scripts/backup-nv.sh`; persist, modemst1/2, fsg, fsc in `firmware/backup/` (mode 600), SHA-256 equal on phone and Mac._ ⚠️ **Backups before anything else touches the phone:** `dd` `persist`, `modemst1`, `modemst2`, `fsg`, `fsc` (IMEI + calibration) to `firmware/backup/` on the Mac.
  - Gate: SHA-256 equal on phone and Mac. Never committed, never leaves the Mac.
- [x] **P2.5** _Done 2026-11-19: `firmware/live.dtb` (v2 Redfin PVT, board-id 0xb1e05), cmdline keys (panel `s6e3hc2` DSC cmd), LUN sizes, subsystems → `docs/device-info.md`. `scripts/initrd-pull.sh`._ Inventory: `/proc/cmdline` single keys only (never `serialno`), `/sys/firmware/fdt` → `firmware/live.dtb` (the DT **after** dtbo overlay; the board DTS reference for P6.3), `/dev/block/by-name`, LUN layout → `docs/device-info.md`.
- [x] **P2.6** _Done 2026-11-19: active slot is `_b`. `vendor_b` = 2 extents in super; hashed in place it equals the factory vendor.img (no dmsetup in busybox; dm-linear moves to P4.1). `modem_b` vfat mounted ro: modem.mdt/b00-b34, modem_pr, modemr.jsn._ Map `vendor_a` out of `super` with dm-linear (`parse-android-dynparts` + `dmsetup`) and mount it read-only; mount `modem_a` (vfat) read-only.
  - Gate: firmware lists match P1.6.

## Phase 3: Ubuntu on the downstream kernel (1–3 days)
- [x] **P3.1** _Answered offline 2026-11-19: **no** (stock config has no DEVTMPFS, FHANDLE, AUTOFS; static usermode helper on). P3.2 is required._ Can Ubuntu run on the **stock** kernel? Check its config (P1.6/P2) for systemd needs: `DEVTMPFS`, `FHANDLE`, `CGROUPS`, `AUTOFS_FS`, namespaces, `SECCOMP`, `TMPFS_XATTR`. All present → skip P3.2 for milestone 1 and log it.
- [x] **P3.2** _Done 2026-11-19 (Test 12): `4.19.325-cip136-st20-redfin-ubuntu+` + our 218 first-stage modules (`KMODS=1 build-initramfs.sh`, vendor load order, deps/softdeps from modinfo) → ping after 22 s, 0 modules failed, devtmpfs, USB serial works._ `scripts/build-kernel.sh`: LineageOS 4.19 `redbull_defconfig` + `kernel/redfin-ubuntu.config` (systemd options above; static usermode helper off; firmware user-helper fallback off; USB `CONFIGFS_NCM`). Build first-stage drivers in (`=y`) where possible; ship the rest in our initramfs, since vendor ramdisk modules won't match our vermagic.
  - Gate: compiles; `fastboot boot` reaches the P2 debug shell with our modules.
- [x] **P3.3** _Done 2026-11-19 (Test 15): booted from RAM via `scripts/ramroot.sh`: Ubuntu 24.04.5, systemd running, 0 failed units, SSH over USB. Fixed NCM MACs needed (Test 13)._ _Prepared 2026-11-19: builds (65 s), 4 GiB → 242 MB sparse; label `ubuntu`, no `orphan_file`/`metadata_csum_seed` (4.19 can't mount them rw), units enabled, keys + qbootctl in. Kernel modules get added once build-kernel.sh has run._ `scripts/build-rootfs.sh` (adapted): ext4 label **`ubuntu`** (the initramfs refuses anything else), ubuntu-base 24.04, hostname `pixel5`, user `ubuntu` + SSH keys, NetworkManager, avahi, USB gadget unit, kernel modules → ext4 `build/rootfs.img` → `img2simg`.
- [x] **P3.4** _Done 2026-11-19 (Tests 16-18): label read from the ext4 superblock (no blkid in busybox); growfs by systemd (`x-systemd.growfs`), 4 GiB → 107.3 GiB on first boot._ initramfs: find userdata by partlabel, `resize2fs` once, `switch_root`; debug shell on failure.
- [x] **P3.5** _Done 2026-11-19 (Test 18): owner OK; userdata flashed; SSH 22 s after `fastboot boot` once the kernel accepted NM's route (`kernel/patches/0001`)._ ⚠️ (owner OK) `fastboot flash userdata build/rootfs.simg`, then `scripts/try-boot.sh build/boot.img`.
  - Gate: `ssh ubuntu@172.16.42.1` works. 🎉 **Milestone 1: Ubuntu 24.04 runs on the Pixel 5.**
- [x] **P3.6** _Done 2026-11-19: in `docs/log.md` (0 failed units; 438 dmesg errors, mostly remote-processor services not up yet; charging works)._ Save `uname -a`, `systemctl --failed`, notable `dmesg` errors in `docs/log.md`.

## Phase 4: Wifi on the downstream kernel (2 h – 3 days)
- [x] **P4.1** _Done 2026-11-19: `pixel5-dynparts` (LP metadata for the active slot → dm-linear, read-only) + `pixel5-firmware.service`: `/vendor` and `/vendor/firmware_mnt` (modem_b) mounted read-only at boot._ systemd units: vendor (dm-linear from super, P2.6) and `modem_a` mounted read-only where the kernel looks for firmware.
- [x] **P4.2** _Done 2026-11-19 (Tests 19–22): qrtr-ns, pd-mapper + tqftpserv (ours), rmtfs (UIO), `/dev/ipa`, `wlan.ko`, modem held open, then our `pixel5-wlfw-bdf` (BDF + cal report) → FW ready → wlan0. All at boot via `pixel5-wifi.service` with a crash guard._ Gate: `wlan0` exists. WCN3990 needs the modem up first.
- [x] **P4.3** _Done 2026-11-19: open-source daemons only, plus a 150-line Python WLFW client instead of cnss-daemon. No vendor daemons._ No `wlan0`? Try the open-source daemons first (`rmtfs`, `tqftpserv`, `pd-mapper`, `qrtr`; start order from the Pixel 2 mainline lesson: tqftpserv + diag before `rmtfs -s`). Then fall back to running vendor daemons (`cnss-daemon` etc.) directly, as the Pixel 2 did on 4.4 (its dropped `android-env` helpers).
- [x] **P4.4** _Done 2026-11-19: MAC = factory (google_wlan_mac); NM profile baked in; cable unplugged → `ssh ubuntu@pixel5.local` over wifi._ Stable MAC (generate once, persist), `nmcli dev wifi connect`, baked-in NM profile.
  - Gate: `ssh ubuntu@pixel5.local` with the cable unplugged.

## Phase 5: Make it permanent (1–2 h, ⚠️ flashes)
- [x] **P5.1** _Not needed (2026-11-19): with an AVB hash footer on boot, the unlocked bootloader boots our image without touching vbmeta (sde)._ (owner OK) `fastboot --disable-verity --disable-verification flash vbmeta_a firmware/vbmeta.img`, same for `vbmeta_b`.
- [x] **P5.2** _Done 2026-11-19 (owner OK), boot_b only (slot a is unbootable from the factory): `AVB_FOOTER=1` image; without the footer even `fastboot boot` failed (Load Error)._ (owner OK) `fastboot flash boot_a build/boot.img` and `boot_b`. vendor_boot stays stock on the downstream route.
- [x] **P5.3** _Done 2026-11-19: qbootctl reports `_b` active + successful after boots from boot_b._ Mark the slot successful at boot (`qbootctl`; untested on redfin).
  - Gate: after 3 boots `fastboot getvar slot-successful:<slot>` is `yes`.
- [x] **P5.4** _Done 2026-11-19: 5 warm reboots → SSH over wifi in 45–48 s (Test 23); cold boot → 31.5 s (Test 26). Milestone 2._ Power off, press power. Then 5 reboots.
  - Gate: SSH over wifi within 60 s every time. 🎉 **Milestone 2: the phone boots into Linux.**
- [x] **P5.5** _Done 2026-11-19: panel undriven after the bootloader splash; SOC from our QGauge client (`pixel5-qgauge`, was frozen at 53 %); charge limit 70–80 % works (input cut above 80, Test 24); unattended-upgrades on. Alive: 2 short buzzes when wifi is up, 1 long if not (`pixel5-alive`)._ Headless tuning: panel off from boot (OLED burn-in), charge limit 70–80 %, `unattended-upgrades`. No notification LED on the Pixel 5: pick an alive signal (short vibration at boot, or a tiny dim pixel moving on the AMOLED). Owner decides.

## Phase 6: Mainline kernel (weeks; research-heavy, mirrors Pixel 2 P8.3)
Source: `docs/research/mainline.md`. No mainline kernel has ever been shown booting on redfin.
- [x] **P6.1** _Done 2026-11-19: `scripts/build-mainline.sh` builds next-20261021 + 23 nairo patches (Image 42.7 MB, 0 warnings). Recipe: `docs/research/mainline-tree.md` (built in our container: linux-next next-20261021 + 23 nairo patches → Image + DTB, 0 warnings). Owner 2026-11-19: single patch files may be committed with their origin recorded (v15 path OK); the owner asks the nairo author to confirm GPL-2.0. Until then nairo-based builds stay local (never published)._ Assemble a tree, every source a pinned submodule: linux-next (or 7.4) + Sreeshankar K's SM7250 base series (v15) + Ishu Brar's interconnect / gpucc / dispcc / DPU series + cherry-picks from `effeffe/nairoArchLinuxArmTools` (TLMM, UFS, USB, A620, IPA, MPSS, SMB5, QGauge) + `lazybrar/avicii-mainline` (DSC command-mode panel path). Check each tree's license first; `sohalartz/redfin-postmarketos` is reference only (no license, commits blobs and an SSH host key).
  - Gate: it builds a generic SM7250 kernel.
- [x] **P6.2** **Boot path: the first gate.** _Test plan: `docs/research/mainline-boot.md`. **T0b passed (Test 27): ABL uses the DTB of a header-v2 boot image (`scripts/make-bootimg-v2.sh`) and still applies dtbo; mainline tests need no flashing. T0a (Test 28): pstore survives neither a warm reboot nor a panic; debug via fastboot-return, UFS and USB.** **T1 passed (Test 82): mainline reaches userspace and reboots into fastboot (18 s); the hang was TZ-owned GPIOs 0–3 (`gpio-reserved-ranges`).** **T3 = gate passed (Test 83): USB NCM + serial shell on mainline after 19 s; UFS, 8 CPUs, cpufreq up.** Slot b is the live Ubuntu slot, so experiments use slot a; `boot_a` still holds Android: flash it with a non-Android image (owner OK) before any `--set-active=a`._ How does redfin's bootloader take a mainline DTB? Try, in order, flashing **only the inactive slot** (stock/downstream slot stays the way back via `fastboot --set-active`):
  1. mainline DTB in `vendor_boot_a` with redfin's `msm-id <400 0x20000>, <440 0x20000>` and `board-id <0x0b1e05 0>`, plus a dtbo "sink" (Pixel 2 technique, generated by script);
  2. erase `dtbo_a` (what avicii needed);
  3. chainload upstream U-Boot (then every kernel test is a plain `fastboot boot`).
  - No UART: debug through pstore/ramoops and USB serial from our initramfs. Kernel loads at offset 0x80000 if ABL insists.
  - Gate: mainline reaches our initramfs and USB serial works.
- [x] **P6.3** _First gate done 2026-11-19: `kernel/mainline/dts/sm7250-google-redfin.dts` + generated dtbo sink (177 labels); all 36 overlays apply offline with 0 diff outside the sink (T0c). Grows per P6.4 item._ `kernel/mainline/dts/sm7250-google-redfin.dts` from the downstream DT (`lito-redfin*.dtsi`) and `firmware/live.dtb` (P2.5).
- [ ] **P6.4** Bring-up, one change per test image, each `fastboot boot` or inactive slot only:
  - [x] UFS + USB2 gadget + rootfs (nairo patches; 32-bit DMA mask) _Done 2026-11-19 (Tests 83–86): reads/writes verified, our Ubuntu boots on mainline, SSH over USB in 22 s. Mainline modules installed (Test 87): Ubuntu on mainline `running`, 0 failed units._
  - [x] Charger (SMB5) + fuel gauge (QGauge), cpufreq + thermal _Done 2026-11-19 (Tests 88–91): qcom_smbx + qcom_qg (OCV tables generated from the phone's DT at build time), 80/70 hold via USB input suspend (`pixel5-charge-hold`), one full cycle verified; cpufreq (schedutil, 3 policies); 27 TSENS zones with 110 °C shutdown._
  - [x] Modem (MPSS PAS + Pixel SMEM socinfo quirk, tqftpserv `modem_pr/`, pd-mapper table) → wifi (ath10k_snoc, `board-2.bin` from vendor `bdwlan*`) _Done 2026-11-19 (Tests 92–95): modem boots via qcom_q6v5_pas without the SMEM item; wifi at boot in 15–17 s with a stable MAC, SSH over wifi; board.bin = the phone's bdwlan-redfin.bin, firmware-5.bin pinned from linux-firmware. Not done: IPA/mobile data, calls._
  - [x] GPU A620 (simpledrm first, then msm + Mesa) _Done 2026-11-20 (Test 98): msm render-only (no display yet), freedreno FD620 GL 4.6 / Turnip Vulkan 1.3, 275/400 MHz. Needs linux-firmware a650_sqe.fw (vendor v93 too old). simpledrm skipped: it would keep the panel lit._
  - [x] Panel S6E3HC2 DSC command mode: **new driver** from downstream DCS sequences _Done 2026-11-20 (Tests 137–141): driver generated by lmdpdg from the GPL source dtsi (local 0004) + nairo MDSS/DPU patches, no interconnect votes. Owner saw a clean modetest pattern. Text console on the panel, `consoleblank=60` switches the rails off; Power wakes it, re-blanks 60 s later. One reboot hang after a manual DPU unbind/rebind (unproven)._
  - [x] Touch S6SY79x: **SPI transport** for `s6sy761`; GPIO 35 to the AP _Done 2026-11-21 (Tests 143–144): local patch 0005 (sec_ts SPI framing behind read/write callbacks), QUP0 SE0 SPI, L17A 3.304 V, reset GPIO 8, IRQ GPIO 9. Device id 0x3791, 1080x2340, 16 slots; owner taps/drag/two fingers decoded with correct axes. Firmware = the IC's own flash (s6sy79x.bin not loaded)._
  - [x] Audio, speakers: 2x CS35L41 on quinary TDM _Done 2026-11-21 (Tests 146–162): APR q6afe/asm/adm on the ADSP, local 0006–0008 (sm8250 TDM back ends, q6afe TDM data delay, q6routing S32). Both amps play; verified through their own speaker-current sense (IMON) at the played frequency, ~58 dB stereo separation. Owner heard the test tone (Test 165). No ADSP restarts in 20 min. Amps run with their protection DSP bypassed (PCM Source ASP): keep volumes low until the protection firmware is loaded._
  - [x] Audio, mics: RT5514 _Done 2026-11-21 (Tests 169–173): mainline GPI SPI returns zeros for receive-only transfers, so rt5514-spi reads full-duplex (patch 0009); patch 0010 loads the RT5514P DSP firmware, leaves the interface clocks to it and keeps DAPM off its registers; reset + retry covers a boot-time load failure (about 1 in 2 first attempts, cause unknown). Release `g7926d9799a68` tested tethered (3 boots, speaker-to-mic loop 41–67 dB), flashed to boot_b (Test 174). Gain as Android's voice recorder (ADC1 52, Test 176); owner: voice "sounds clear" (Test 177). Mono. `arecord -D hw:G5,1 -f S16_LE -r 48000 -c 2`._
  - [x] Bluetooth (hci_qca) _Done 2026-11-20 (Test 99): WCN3991 on QUP0 SE5, vendor firmware, NVM deep-sleep byte patched at boot (else wedges after idle and crashes WLAN), machine-id BD address._
  - [x] Haptics (DRV2624: new driver) _Done 2026-11-20 (Test 100): local patch 0002 (FF_RUMBLE, RTP), pixel5-alive buzzes on mainline. Owner confirmed (2 buzzes)._
  - [x] Sensors (ADSP SEE) _Done 2026-11-20 (Tests 114–134): ADSP via PAS + FastRPC node + smp2p `sleepstate` entries (without them Google's CHRE fatals every 10 s); hexagonrpcd + our write/large-buffer patches serves a writable copy of persist's registry; `pixel5-see` reads accel, gyro, mag, pressure, light from Linux. CDSP: TZ refuses it (-22), parked._
  - [ ] Suspend (s2idle) _Partly (Tests 101–131, 178–192): suspends and resumes cleanly. Every DSP now sleeps: the CDSP starts with the compute NoC vote (patch 0011, Test 184), the ADSP sleeps once q6afe keeps its LPASS core vote handle (patch 0012, Test 192). The SoC still never reached AOSS sleep (`aosd` 0) in every test so far, also with BT and USB off (Test 185, before 0012) and under the downstream kernel (Test 182). Cable-out s2idle with 0012: still 0 (Test 194), also without `pd_ignore_unused` (Test 196); without `clk_ignore_unused` the kernel hangs at boot (Test 195). Tests 198-201: the boot clocks, the display's CX hold (it leaks a prepared-clock hold at boot and on every resume), the TBU GDSCs, BT, USB and wifi all released at once: still 0; no interconnect vote left. UFS ruled out (Tests 202-203, also `spm_lvl=5`). Left: votes outside Linux, and whether the counter moves on this phone at all; measured with the QG FIFO (Test 204): 46 mA in s2idle vs 117 mA awake, so the counter is right and the SoC really stays out of deep sleep. Open fix regardless: the msm display clock hold (CX in sleep)._
- [x] **P6.5** (owner OK) Flash mainline as default on the active slot; downstream stays on the other. _Done 2026-11-20: mainline on boot_b (slot a is factory-unbootable, so downstream is a backup image instead: build/backup/boot_b-downstream-2026-11-20.img). SSH 28 s after power-on._

## Phase 7: One-command build + guided flashing (half a day; copy Pixel 2 P9)
- [x] **P7.1** _Done 2026-11-20: fresh clone → images with only the factory zip added (≈1 h 40 min cold); two gaps found and fixed (battery data from the kernel source, vendor module order from vendor_boot.img). Mainline kernel modules now in the rootfs._ `scripts/build-all.sh` (hash-gated steps, as in the Pixel 2): submodules, container, kernel(s), initramfs, boot images, rootfs, firmware staging scripts.
  - Gate: fresh clone → images, no manual steps.
- [ ] **P7.2** _Script path done 2026-11-20 (Test 136): full install on this phone, Ubuntu up on wifi, all services and sensors working. Gate left: someone else flashes a phone from the README._ `scripts/flash.sh`: checks the phone is redfin + unlocked + on the final build, asks for `yes`, flashes vbmeta/boot/(vendor_boot)/userdata on explicit `_a`/`_b`, waits for SSH. Plus `restore`.
  - Gate: someone else flashes a phone using only README + `flash.sh`.
- [x] **P7.3** README: install flow. _Done 2026-11-20; repo public at github.com/jasiek/pixel5-ubuntu._

## Parked (research problems; pick up only on request)
Cameras (no SM7250 CAMSS, no IMX363/IMX481 drivers), rear fingerprint (TrustZone), CDSP + Venus video (TZ refuses on other SM7250 phones), wireless charging (P9382), 5G NR and VoLTE (unproven anywhere), NFC (ST21NFC fit unverified), modem data/SMS on downstream (needs a SIM).

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
