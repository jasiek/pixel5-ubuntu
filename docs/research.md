# Research summary (2026-11-18)

Four research passes; full reports with sources in `docs/research/`:

| Report | Question |
|---|---|
| [`pixel2-transfer.md`](research/pixel2-transfer.md) | What in the Pixel 2 repo is reusable, adaptable, or walleye-only |
| [`mainline.md`](research/mainline.md) | Mainline Linux status for SM7250 / redfin, per subsystem |
| [`bootchain.md`](research/bootchain.md) | Bootloader, partitions, boot image format, AVB, downstream kernel |
| [`existing-ports.md`](research/existing-ports.md) | Ubuntu Touch, Droidian, postmarketOS/Nura, others |

## Key findings

**Existing ports.**
- Ubuntu Touch 24.04 (noble) runs on redfin today: community port, Halium 13, downstream 4.19, Android 13 base, `24.04-2.x` daily channel. Feature claims (calls, data, wifi, camera, audio, GPU) are the porter's own.
- postmarketOS (now "Nura") has only a wiki stub. Droidian, Mobian, Sailfish: nothing.
- `sohalartz/redfin-postmarketos`: a Pixel 5 mainline attempt with an Ubuntu 24.04 boot image. No license, commits proprietary firmware and an SSH host key. Reference only.

**Boot chain.**
- A/B, boot header v3. The DTB lives in `vendor_boot`, board overlays in `dtbo`. `vendor` sits inside `super`; `modem_a` is vfat.
- `fastboot boot` works but uses the flashed vendor_boot. A mainline DTB therefore means flashing vendor_boot (inactive slot) or chainloading U-Boot.
- DTB match: `qcom,msm-id = <400 0x20000>, <440 0x20000>`, `qcom,board-id = <0x0b1e05 0>`.
- AVB: flash vbmeta with `--disable-verity --disable-verification`.
- Final firmware: Android 14 `UP1A.231105.001.B2`.
- Downstream fallback: LineageOS `android_kernel_google_redbull` `lineage-24.0` (4.19.325, active).

**Mainline.**
- Upstream 7.4-rc3 has only SM7250 basics (socinfo, RPMh clocks and power domains). The base `sm7250.dtsi` + GCC series is at v15, pending. No TLMM driver posted.
- Three out-of-tree SM7250 phones run mainline: Moto G 5G Plus "nairo" (most complete, incl. modem calls/SMS/data), OnePlus Nord "avicii" (DSC command-mode Samsung OLED, closest to our panel), Redmi K30 5G "picasso".
- No redfin DTS exists anywhere.

**Redfin hardware** (downstream DT):

| Part | Chip | Mainline |
|---|---|---|
| Panel | Samsung S6E3HC2, DSC command mode, 60/90 Hz | no driver |
| Touch | Samsung S6SY79x on SPI | `s6sy761` is I2C-only |
| GPU | Adreno 620 | proven on 3 SM7250 phones; Mesa 24.0 knows it |
| Wifi / BT | WCN3990 (ath10k_snoc / hci_qca) | works once the modem is up |
| Audio | 2x Cirrus CS35L41 + Realtek RT5514, no WCD codec | drivers exist; board wiring is new |
| Haptics | TI DRV2624 | no driver |
| Fingerprint | FPC1020 behind TrustZone | effectively infeasible |

**From the Pixel 2.**
- About 75 % of build/dev tooling carries over; the kernel/DT work almost entirely does not.
- Techniques likely needed again: dtbo sink, IOMMU identity mapping for the splash display, modem firmware assembled at boot from the phone's own partitions (pil-squasher), daemon start order (tqftpserv + diag before `rmtfs -s`), stable generated wifi MAC.

## Route decision

See PLAN.md D1. Recommended: plain Ubuntu 24.04 with our own kernels (downstream 4.19 first for a quick SSH, then mainline), as on the Pixel 2. Ubuntu Touch 24.04 is the fallback and a reference.

## Unverified (from the reports)

Exact ABL cmdline; whether a failed dtbo overlay stops boot; whether `fastboot boot` needs an AVB footer; whose `/init` wins with two ramdisks; firmware file names; camera sensor models; whether the Pixel modem SMEM quirk applies under PAS; 5G NR on any SM7250 mainline port; Ubuntu Touch feature claims. PLAN.md "Open questions" orders the cheap checks.
