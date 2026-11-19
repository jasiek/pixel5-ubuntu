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
