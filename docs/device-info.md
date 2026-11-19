# Pixel 5 (redfin): device facts

Never record the phone's serial number here.

## From the factory image (offline, 2026-11-19)

Factory image `redfin-up1a.231105.001.b2` (Android 14, security patch 2023-11), zip SHA-256 `4e5a26793d8400f13b72cbd17aeb284e040b3236436f0c6f3119ccc77d4495ad` (`scripts/get-firmware.sh`).

### boot.img

| Field | Value |
|---|---|
| Header version | 3 |
| Kernel | LZ4 `Image`, 11.7 MB; stock `4.19.278-g7b0944645172-ab10812814` |
| Ramdisk | LZ4 legacy cpio, 2.0 MB; `/init` (regular file) + first-stage dirs |
| os_version / patch level | 14.0.0 / 2023-11 |
| Cmdline | empty (all from vendor_boot) |
| Partition size | 96 MiB (100663296) |

### vendor_boot.img

| Field | Value |
|---|---|
| Header version | 3, page size 4096 |
| Load addresses | kernel 0x8000, ramdisk 0x1000000, tags 0x100, DTB 0x1f00000 |
| Vendor ramdisk | LZ4 legacy cpio, 30 MB. Holds **recovery** (`/init` → `/system/bin/init` symlink, `init.recovery.redfin.rc`, `res/images`), `first_stage_ramdisk/fstab.sm7250`, and `lib/modules/` (218 in `modules.load`) |
| DTB | one generic base DTB: model `Qualcomm Technologies, Inc. Lito SoC`, `qcom,msm-id = <0x190 0x10000>, <0x1b8 0x10000>`, `qcom,board-id = <0 0>` |

Vendor cmdline:
```
console=ttyMSM0,115200n8 androidboot.console=ttyMSM0 printk.devkmsg=on msm_rtb.filter=0x237 ehci-hcd.park=3 service_locator.enable=1 androidboot.memcg=1 cgroup.memory=nokmem lpm_levels.sleep_disabled=1 usbcore.autosuspend=7 androidboot.usbcontroller=a600000.dwc3 swiotlb=2048 androidboot.boot_devices=soc/1d84000.ufshc loop.max_part=7 loop.hw_queue_depth=31 snd_soc_cs35l41_i2c.async_probe=1 i2c_qcom_geni.async_probe=1 st21nfc.async_probe=1 spmi_pmic_arb.async_probe=1 ufs_qcom.async_probe=1 spi-geni-qcom.async_probe=1 cnss_utils.async_probe=1 cgroup_disable=pressure
```

First-stage modules include UFS (`ufs_qcom`, `ufshcd-*`, `phy-qcom-ufs-qmp-v4-lito`) and USB (`dwc3*`, `usb-dwc3-msm`, `phy-msm-ssusb-qmp`, `phy-msm-snps-hs`). NCM is built in.

Ramdisk order (header v3): vendor ramdisk first, then the boot ramdisk, so the boot ramdisk's regular-file `/init` replaces the vendor's `/init` symlink (kernel `clean_path` on a type change). To be confirmed on the phone (P2.3).

### dtbo.img

36 overlays (redfin, bramble, barbet; all boards of the redbull family). Retail Pixel 5 = entry **25**, `Google Inc. MSM sm7250 v2 Redfin PVT`, `qcom,msm-id = <0x190 0x20000>, <0x1b8 0x20000>`, `qcom,board-id = <0xb1e05 0>`. The bootloader picks the overlay by these IDs and applies it to the generic base DTB.

### Stock kernel config (`extract-ikconfig`)

| Needed by systemd / us | Stock |
|---|---|
| `DEVTMPFS` | **off** (initramfs falls back to mdev) |
| `FHANDLE`, `AUTOFS4_FS` | **off** |
| `USER_NS`, `PID_NS`, `SYSVIPC` | off |
| `STATIC_USERMODEHELPER` | on (no hotplug/modprobe helper) |
| `FW_LOADER_USER_HELPER` | on |
| `SECURITY_SELINUX_BOOTPARAM` | off (`selinux=0` has no effect) |
| `USB_CONFIGFS_NCM` | on; `ACM`, `ECM`, `RNDIS` off |
| `RD_GZIP`, `RD_LZ4` | on |
| `MODVERSIONS` | on |

So Ubuntu needs our own kernel (P3.2); the stock kernel is only good for the Phase 2 debug shell (network over NCM, no USB serial).

### vendor.img `/firmware` (ext4, 756 MB)

GPU `a620_zap.{mdt,bNN,elf}`, `a650_sqe.fw`, `a650_gmu.bin`; DSPs `adsp.{mdt,bNN}`, `cdsp.{mdt,bNN}`, `ipa_fws.*`, `venus.*`; wifi `wlanmdsp.mbn`, `bdwlan-redfin.bin`, `bdwlan-u-redfin.bin`, `wlan/`; BT `crbtfw32.tlv`, `crnv32.bin`, `crnv32u.bin`; audio `cs35l41-*` (`.wmfw`, `.bin`, revB0/B2), `rt5514_dsp_fw*`, `rt5514p_dsp_fw*`; haptics `drv2624.bin`; touch `s6sy79x.bin`; NFC/eSE `st54j_*`; plus TrustZone apps (fingerprint, widevine, confirmationui, featenabler, hdcpsrm). 329 kernel modules in `/lib/modules`. The modem image itself lives on the `modem` partition, not here.

## From the phone

(P1.2, P1.6, P1.7, P2.5: to fill in.)
