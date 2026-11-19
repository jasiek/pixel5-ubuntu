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
