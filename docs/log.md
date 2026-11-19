# Log

Dated notes. Every phone test gets a number (`Test 1: ...`): what was run, what was measured, what it means.

## 2026-11-18

- Repo created. Four research passes (Pixel 2 transfer, mainline status, boot chain, existing ports); reports in `docs/research/`, summary in `docs/research.md`.
- Findings that shape the plan: no mainline kernel has booted on redfin; DTB lives in `vendor_boot` (header v3), so `fastboot boot` alone can't test a mainline DTB; vendor firmware is inside `super`; Ubuntu Touch 24.04 already exists for redfin (fallback/reference).
- Plan: downstream 4.19 first (stock kernel debug shell → backups → Ubuntu → wifi → flash), then mainline. Route awaits owner confirmation (PLAN.md D1).

## 2026-11-19

- D1: owner picked route A (plain Ubuntu 24.04, own kernels).
- P0.2: generic tooling copied from the Pixel 2 repo and renamed (`pixel5-build` image, `PIXEL5_HOST`, gadget serial `pixel5-ubuntu`, `build/ssh/pixel5_ed25519`). One container instead of two: Ubuntu 24.04 + LLVM 18 + busybox-static, sparse and e2fs tools. `dev.sh uname -m` = aarch64 (image build 24 s); `build-initramfs.sh` → 1.2 MB cpio.
- Found: this clone sits on the case-insensitive system volume. The Pixel 2 clone lives on `/Volumes/Pixel2Dev` (case-sensitive) for the kernel trees. Must move before P0.4.
- Clone moved by the owner to `/Volumes/Pixel2Dev/pixel5-ubuntu` (case-sensitive, checked). P0.4 unblocked.
- P0.3: licensing set up; `scripts/reuse-lint.sh` compliant.
- P0.4: submodules (license checked before adding):

  | Path | Upstream | Revision | License |
  |---|---|---|---|
  | external/kernel-redbull | LineageOS android_kernel_google_redbull, `lineage-24.0`, shallow | 929e7e2f (2026-11-07, 4.19.325) | GPL-2.0 |
  | external/mkbootimg | AOSP platform/system/tools/mkbootimg | d2bb0af5 | Apache-2.0 |
  | external/avb | AOSP platform/external/avb (avbtool) | 20bfb02a | MIT / Apache-2.0 |
  | external/qbootctl | linux-msm/qbootctl | 39a6e6da (0.2.2) | GPL-3.0 |
  | external/pil-squasher | linux-msm/pil-squasher | 3c9f8b87 | BSD-3-Clause |
  | external/parse-android-dynparts | tchebb/parse-android-dynparts | c8837c1c | Apache-2.0 |
  | external/lpunpack | unix3dgforce/lpunpack | c59b8f3b | LGPL-3.0 |

  GitHub reports the kernel's license as NOASSERTION; its `COPYING` is GPL-2.0. The shallow kernel checkout is 1.1 GB.
- P1.5/P1.8/P1.9 offline from the factory zip (owner downloaded it; SHA-256 matches the page): facts in `docs/device-info.md`.
  - Both boot images are header v3. The vendor_boot DTB is a generic Lito base; the retail board comes from dtbo entry 25 (`v2 Redfin PVT`, board-id `0xb1e05`).
  - Vendor ramdisk = recovery + 218 first-stage modules (UFS, USB). NCM is built into the stock kernel; ACM is not.
  - P3.1 answered: the stock kernel can't run systemd (no DEVTMPFS, FHANDLE, AUTOFS). Initramfs now falls back to a tmpfs /dev filled by `mdev -s`, and ACM is optional, so the Phase 2 stock-kernel debug shell can still work (telnet over NCM only).
- P1.4: bootloader unlocked (owner confirmed on the phone). `getvar all` saved to `firmware/getvar-all.txt` without the serial. Notable: `slot-unbootable:a:yes` (slot a is marked unbootable; slot b active and successful); baseband `g7250-00264-230619-B-10346159`.
- P3.2: 4.19 kernel builds without LTO/CFI (20 min, all fragment options applied): `4.19.325-cip136-st20-redfin-ubuntu+`, 329 modules.
- **Test 1: stock kernel + our debug initramfs, `fastboot boot` (`initdebug`).** `fastboot boot` accepted (no AVB footer needed). Then: screen **solid bright white** (webcam), nothing on USB (no NCM, no fastboot, no adb), and no return to fastboot after 16 min. Stock `PANIC_TIMEOUT=5`, so this is a hang, not a panic. Unknown whether our init ran: its fastboot-return timer only started inside the debug shell, after module loading and USB setup. Fix: the timer now starts at the top of init, and `initstage=N` reboots to fastboot right after stage N (0 init runs, 2 modules loaded, 3 USB bound) so each probe answers "did we get this far". Images `build/boot-stock-stage{0,2,3}.img`, timeout 180 s.
- **Test 2: stage 0 probe (`initstage=0`, gzip ramdisk).** No return to fastboot within 246 s; webcam shows the white Google splash. So our `/init` never ran. Cause (read in the kernel source, not yet measured on the phone): the bootloader concatenates the vendor ramdisk (**LZ4 legacy**) and our boot ramdisk (**gzip**). `lib/decompress_unlz4.c` only accepts another LZ4 legacy magic between archives; it reads the gzip header `1f 8b 08 00` as a chunk length, fails with "Decoding failed", and `populate_rootfs` only logs "Initramfs unpacking failed". Our cpio is dropped and the vendor's recovery `/init` runs. Same cause for Test 1. Also seen: fastboot prints `boot.img missing cmdline or OS version` (header has os_version 14.0.0; our cmdline is non-empty) but boots anyway. Fix: `build-initramfs.sh` now writes LZ4 legacy (`lz4 -l -9`), magic `02 21 4c 18` like stock. Stage images rebuilt.
- **Test 2b: stage 0 probe, LZ4 ramdisk.** Back in fastboot after **106 s** (expected ~15–20 s for a clean `reboot-bootloader`).
- **Test 3: stage 0 with `initstage_delay=60`.** Back after **124 s**: an 18 s shift, not 60. So the return is not (only) our `reboot-bootloader`. Likely reading (unproven): `watchdog_v2.ko` and `msm-poweroff.ko` are vendor modules (`modules.load` lines 60, 142), not loaded at stage 0. The restart probably stalls without the Qualcomm restart driver, and the unpetted hardware watchdog resets the phone at ~100–120 s; the bootloader then stays in fastboot. Reboot timing before module load proves nothing; Test 2 → 2b (hang → return, only change gzip → LZ4) does suggest our ramdisk now unpacks.
- **Test 4: stage 2 probe (`initstage=2`).** Started 10:08. At 10:12 the webcam showed **Android setup** ("Welcome to your Pixel!"; the unlock wipe ran). So the probe ended in a reset without the bootloader reason (panic during module load, watchdog, or a failed restart), and the bootloader booted slot b normally. Can't tell which from timing. Next: read Android's boot reason (`sys.boot.reason`) and last kernel log (`dumpsys dropbox SYSTEM_LAST_KMSG`) over adb; needs USB debugging enabled by the owner.
- After Test 4 the owner enabled USB debugging. Android's `persist.sys.boot.reason.history`: every probe reset was `watchdog`. The current boot's dmesg shows Android loads `watchdog_v2.ko` at 0.49 s, and the PMIC reports a **cold** boot, so pstore held nothing from the probe (no LAST KMSG in the bugreport; saved under `firmware/inventory/bugreport/`, gitignored). Recovery from Android needs no owner action now: `adb reboot bootloader`.
- Init change: load `watchdog_v2`, `spmi-pmic-arb`, `qcom-spmi-pmic`, `qpnp-power-on`, `msm-poweroff` (with `modules.dep` deps) before stage 0, as Android does.
- **Test 5: stage 0 + early modules.** Phone reset and came up in **Android after 33 s** (reason recorded as `watchdog`). Compared with Test 2b's 106 s, only the init changed, so our init runs.
- **Test 6: same + `initstage_delay=60`.** Android after **94 s** (= 33 + 60 + 1). Proven: our `/init` runs, the early modules load without a crash, and our `reboot-bootloader` is what resets the phone. But the bootloader reason is lost (normal boot into Android, logged as `watchdog`). Unproven why: `msm-poweroff` or `qpnp-power-on` may not have probed (SPMI not up), or the IMEM restart-reason write fails.
