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

### Android, before unlock (P1.2, P1.6; 2026-11-19, over adb, non-root)

| Property | Value |
|---|---|
| Model / device / SKU | Pixel 5 / redfin / GTT9Q (`pcbcfg R3-ROW`), revision MP1.0 |
| Build | `UP1A.231105.001.B2` (Android 14, patch 2023-11-05): already the final build |
| Bootloader | `r3-0.6-10489834` |
| Active slot | `_b` |
| dtbo_idx | **25** (matches the offline pick of `v2 Redfin PVT`) |
| RAM / UFS | 8 GB Micron LPDDR4X / 128 GB Micron |
| Kernel | `4.19.278-g7b0944645172-ab10812814`, Android clang 12.0.5 (r416183b) |
| OEM unlock | allowed; bootloader locked, verifiedbootstate green |

Partitions (`/dev/block/by-name`; LUN sda = data, sdb/sdc = xbl, sdd = cdt/ddr, **sde = bootloader chain, never write**, sdf = modem NV):

| Partition | Device | Partition | Device |
|---|---|---|---|
| ssd | sda1 | persist | sda2 |
| misc | sda3 | keystore | sda4 |
| frp | sda5 | boot_a / boot_b | sda6 / sda7 |
| vendor_boot_a / _b | sda8 / sda9 | dtbo_a / _b | sda10 / sda11 |
| modem_a / _b | sda12 / sda13 | klog | sda14 |
| metadata | sda15 | vbmeta_system_a / _b | sda16 / sda17 |
| super | sda18 | userdata | sda19 |
| vbmeta_a / _b | sde10 / sde26 | modemst1 / modemst2 | sdf2 / sdf3 |
| fsg / fsc | sdf4 / sdf5 | devinfo | sde33 |

Android mounts `modem_b` (vfat) at `/vendor/firmware_mnt` and vendor via dm (`dm-10`); `persist` (ext4) at `/mnt/vendor/persist`. Non-root can't list `/vendor/firmware_mnt`. Raw dumps: `firmware/inventory/` (gitignored).

### Debug shell on the stock kernel (P2.5, 2026-11-19)

Live DT (`/sys/firmware/fdt` → `firmware/live.dtb`, 669 KB, gitignored; `firmware/live.dts` decompiled, 29835 lines): model `Google Inc. MSM sm7250 v2 Redfin PVT`, `compatible = "google,redfin-sm7250", "qcom,sm7250"`, `qcom,msm-id = <0x190 0x20000 0x1b8 0x20000>`, `qcom,board-id = <0xb1e05 0>`. This is the base DTB after the bootloader applied dtbo entry 25, as predicted offline.

Kernel cmdline: the bootloader adds these to the vendor cmdline (values safe to record; the serial and `vbmeta.digest`/`cid` values are not recorded):

| Key | Value |
|---|---|
| `msm_drm.dsi_display0` | `qcom,mdss_dsi_s6e3hc2_dvt_dsc_1080p_cmd:` (panel: Samsung S6E3HC2, DSC, command mode) |
| `androidboot.hardware.platform` / `hardware` | `sm7250` / `redfin` |
| `androidboot.dtbo_idx` / `dtb_idx` | 25 / 0 |
| `androidboot.slot_suffix`, `slot_successful`, `slot_retry_count` | `_b`, yes, 0 |
| `androidboot.verifiedbootstate`, `vbmeta.device_state`, `veritymode` | orange, unlocked, enforcing |
| `androidboot.secure_boot`, `ramdump` | PRODUCTION, disabled |
| `androidboot.bootreason` | `reboot,bootloader` (after our probe reboots) |
| `androidboot.hardware.ddr`, `ufs` | `8GB,Micron,LPDDR4X`, `128GB,Micron` |
| `androidboot.hardware.devcfg`, `majorid`, `radio.subtype`, `dsds` | `G950-03453-01`, `0x0B`, 2, 0 |
| others | `init=/init`, `rootwait`, `ro`, `rcu_nocbs`, `rcupdate.rcu_expedited`, `usbcfg.suzyq=disabled`, `androidboot.force_normal_boot=1` |

UFS LUNs: `sda` 121920 MiB (19 partitions, data), `sdb`/`sdc` 8 MiB (2 each, xbl), `sdd` 8 MiB (3, cdt/ddr), `sde` 64 MiB (42, bootloader chain), `sdf` 16 MiB (5, modem NV). Partition numbers as in the table above. RAM visible to Linux: 7462 MiB.

Subsystems (`/sys/bus/msm_subsys`, after loading all 218 first-stage modules, no firmware): `modem`, `adsp`, `cdsp`, `npu`, `venus`, `a620_zap`, `ipa_fws`, all `OFFLINING` (registered, not booted).

Init facts (Tests 1–11, `docs/log.md`): our ramdisk must be **LZ4 legacy**; `watchdog_v2` must load within ~100 s; module loading must honour `modules.softdep` (`qmi_helpers pre: qrtr`); `reboot bootloader` only lands in fastboot once the full module set (restart reason via `msm-poweroff`) is up.
