# Wifi on the downstream 4.19 kernel (redfin, SM7250 "lito"): what Android does, and what Ubuntu needs

Research date: 2026-11-19. Scope: Phase 4 (`wlan0` up and connected) on our LineageOS 4.19.325 kernel (`external/kernel-redbull`, `build/kernel/.config`) with plain Ubuntu 24.04 userspace. I worked offline only: kernel source, our `.config`, `firmware/vendor.img` (read with `debugfs`), `firmware/live.dts`, the Android bugreport saved before unlock (`firmware/inventory/bugreport/`), the Pixel 2 project, and the upstream linux-msm sources and Ubuntu archive on the web. I did not touch the phone.

Confidence markers (same as `bootchain.md`): **[V]** means verified from a primary source (kernel tree, vendor image, or the saved Android dmesg). **[S]** means a single secondary source, or an inference from the Pixel 2 that is very likely to carry over. **[U]** means unverified, so test it on the device.

Vendor rc and binary copies used below were extracted to `build/vendor-rc/` and `build/vendor-bin/` (gitignored). Vendor line numbers refer to those files, which are byte copies of the vendor.img paths named.

> Privacy note: `firmware/live.dts` (`/chosen/cdt/cdb2`, around line 625) holds the phone's IMEI/MEID, PSN/DSN, BT and wifi MACs. Never grep it whole into logs or commits. This report quotes property names only.

---

## TL;DR

- **Chip/driver:** integrated WCN399x-family WLAN behind **ICNSS (v1, not icnss2)**. `msm_icnss.ko` (`CONFIG_ICNSS=m`, `CONFIG_ICNSS_QMI=y`, `CONFIG_ICNSS2` off) plus qcacld-3.0 **`wlan.ko`** (`CONFIG_QCA_CLD_WLAN=m`, profile `default`, `pld_snoc` bus). The WLAN firmware runs as a **protection domain on the modem DSP** (`msm/modem/wlan_pd`, instance 180), so **the modem has to boot first** [V].
- **Android order** (measured in the saved dmesg): `wlan.ko` loads at 3.5 s → `qrtr-ns` 4.42 s → `pd_mapper` 4.47 s → `rmt_storage` 4.49 s → `tftp_server` 4.50 s → servloc connects 4.55 s → `cnss-daemon` 6.76 s → modem PIL 6.85 s (triggered by `pm-service`, which keeps `/dev/subsys_modem` open) → modem out of reset 7.74 s → wlan_pd up and **WLFW QMI server connected 9.06 s** → **"WLAN FW is ready" 14.98 s** (after cnss-daemon sent the board file) → `wlan.ko` probes, takes the MAC "from platform driver", then idles the firmware until wlan0 is brought up [V].
- **Open-source equivalents on THIS kernel:**
  - `qrtr-ns`: needed, because 4.19 has no in-kernel QRTR name service. Ubuntu `qrtr-tools` 1.0 ships it [V].
  - `rmtfs`: works through **UIO** (`msm_sharedmem` exposes a uio device named `rmtfs`; rmtfs ≥ 1.0 falls back to `/dev/qcom_rmtfs_uio1`, which needs a udev symlink). Run without `-s`. `rmtfs` 1.0-3 is in noble [V].
  - `tqftpserv` and `pd-mapper`: upstream **only find files through `/sys/class/remoteproc/*/firmware`**, and this kernel has `CONFIG_REMOTEPROC` off. They need either a small patch or a systemd mount-namespace trick that fakes that directory. pd-mapper is **not in the noble archive**, and noble's `tqftpserv` 1.0 lacks the `/readonly/vendor/firmware/` prefix the modem uses on redfin. Build both from pinned submodules [V].
  - **cnss-daemon has no open-source equivalent:** icnss v1 does *not* download the board data file (BDF); on Android, cnss-daemon does it (`bdwlan-*.bin` → WLFW `BDF_DOWNLOAD`). Without it there is no FW_READY and no wlan0. The choice: a small WLFW BDF client of our own (libqrtr, ~300 lines), or the vendor cnss-daemon in a bionic shim as on the Pixel 2 [V for the need, S for the options].
- **MAC:** `google_wlan_mac.ko` (already loaded, first stage) reads `wlan_mac1` from `/chosen/cdt/cdb2` and hands it to `cnss_utils`. qcacld uses it ("using MAC address from platform driver"). So **the stable factory MAC comes for free**, and PLAN P4.4's "generate once, persist" is not needed [V].
- **Firmware loading:** user-helper fallback is off. PIL asks for relative names (`modem.mdt`, `modem.bNN`), qcacld for `wlan/qca_cld/WCNSS_qcom_cfg.ini` (mandatory). The kernel has no hard-coded `/vendor` or `/firmware` paths. One symlink farm set via `/sys/module/firmware_class/parameters/path` serves everything [V].
- **Biggest risk:** a kernel panic now reboots after 5 s (`CONFIG_PANIC_TIMEOUT=5`) **into stock Android on the active slot**, which formats userdata (`formattable`). That would wipe the Ubuntu rootfs, as happened three times on the Pixel 2. Several things panic on purpose: modem crash at the default restart level, SSR failures, SSR notifier timeouts, and `QDF_BUG` in our `wlan.ko` (built with `PANIC_ON_BUG`). **Before any modem test: add `panic=0`** (watchdog_v2 then disables the watchdog and the phone hangs instead of rebooting), set the modem's `restart_level` to `RELATED`, and ask the owner whether to put our boot image on the active slot early [V for the mechanisms; the final behaviour is U].

---

## 1. Chip and driver path

### Kernel config (our `build/kernel/.config`) [V]

| Line | Option | Meaning |
|---|---|---|
| 4747–4750 | `# CONFIG_ICNSS2 is not set`, `CONFIG_ICNSS=m`, `CONFIG_ICNSS_QMI=y` | ICNSS **v1** (`drivers/soc/qcom/icnss.c`, `icnss_qmi.c`), module `msm_icnss.ko` (`drivers/soc/qcom/Makefile:100,102`; icnss2 would be `:107`) |
| 4449 | `CONFIG_QCA_CLD_WLAN=m` | qcacld-3.0 → `wlan.ko` (`drivers/staging/Makefile:55`) |
| 4448 | `CONFIG_GOOGLE_WLAN_MAC=m` | `drivers/staging/wlan_mac/google_wlan_mac.c` |
| 2127–2135 | `WCNSS_MEM_PRE_ALLOC=m`, `CNSS_UTILS=m`, `CNSS_GENL=m`; all `CNSS_QCA6x90` off | helpers; **no** cnss2/PCIe path |
| 1314–1316 | `CONFIG_QRTR=m`, `CONFIG_QRTR_SMD=m` | QRTR over GLINK/rpmsg |
| 4675 | `# CONFIG_QCOM_RMTFS_MEM is not set` | no `/dev/qcom_rmtfs_mem1` |
| 4331, 4341 | `CONFIG_UIO=y`, `CONFIG_UIO_MSM_SHAREDMEM=m` | rmtfs memory through UIO |
| 4617 | `# CONFIG_REMOTEPROC is not set` | no `/sys/class/remoteproc` (matters for tqftpserv/pd-mapper) |
| 4694–4699 | `MSM_SERVICE_LOCATOR=m`, `MSM_SERVICE_NOTIFIER=m`, `MSM_SUBSYSTEM_RESTART=m`, `MSM_PIL=m`, `MSM_SYSMON_QMI_COMM=m`, `MSM_PIL_SSR_GENERIC=m` | downstream PIL/SSR/PDR stack |
| 4739 | `MEM_SHARE_QMI_SERVICE=m` | in-kernel memshare QMI service for the modem |
| 2461 | `CONFIG_DIAG_CHAR=m` | in-kernel diag (the modem's diag channel has a consumer without userspace) |
| 1370, 1377 | `CFG80211=y`, `CFG80211_INTERNAL_REGDB=y`; `MAC80211` off | qcacld is a cfg80211 full-MAC driver |

qcacld build details [V]:
- `drivers/staging/qcacld-3.0/Kbuild:14,19`: `MODNAME := wlan`, `WLAN_PROFILE := default` (`configs/default_defconfig`).
- `Kbuild:1819–1820` and `:2167–2172`: with `CONFIG_ICNSS` (y or m) it builds `pld_snoc.o` with `-DCONFIG_PLD_SNOC_ICNSS`. So the bus is SNOC via the icnss API, not a platform driver. **`wlan.ko` has no modalias, so udev never autoloads it; it must be `modprobe`d explicitly.** `modules.alias` only has `of:...qcom,icnss → msm_icnss`.
- `modules.dep`: `wlan.ko` depends on `msm_icnss`, `cnss_utils`, `cnss_nl`, `cnss_prealloc`, **`ipa3`**, `msm_gsi`, `service-locator`, `service-notifier`, `subsystem-restart`, `qmi_helpers`, … (all already loaded in the first stage).
- In stock, `wlan.ko` is a **second-stage** module (vendor `/lib/modules/modules.load:111`, loaded by `insmod_sh`). It is not in the 218 first-stage modules. `msm_icnss.ko` is first-stage #74; `google_wlan_mac.ko` is #177; `qrtr.ko`/`qrtr-smd.ko` are #217/#218; `msm_sharedmem.ko` is #114.

### Device tree [V]

`external/kernel-redbull/arch/arm64/boot/dts/vendor/qcom/lito.dtsi:3662–3698` (identical in `firmware/live.dts:8206`):

```
icnss: qcom,icnss@18800000 {
    compatible = "qcom,icnss";
    reg = <0x18800000 0x800000>, <0xb0000000 0x10000>;   /* membase, smmu_iova_ipa */
    iommus = <&apps_smmu 0xC0 0x1>;
    interrupts = 12 copy-engine IRQs (CE0..CE11);
    qcom,wlan-msa-fixed-region = <&pil_wlan_fw_mem>;      /* 0x8ba00000, 2 MiB */
    vdd-cx-mx (L1A), vdd-1.8-xo (L14A), vdd-1.3-rfa (L2C), vdd-3.3-ch0 (L10C), vdd-3.3-ch1 (L11C);
    qcom,smp2p_map_wlan_1_in { force-fatal-error, early-crash-ind };
};
```

- The redfin dtsi files add nothing for wlan except power monitors (`lito-redfin-pac193x.dtsi:31–39`) and a wifi thermistor (`lito-redfin-thermal.dtsi:105ff`). Memory: `google/lito-redbull-memory.dtsi:39,44` (`pil_wlan_fw_mem` 0x8ba00000/2 MiB; `modem_wlan_mem` 0x8c000000/0x11800000 is the MPSS carveout, which holds the WLAN PD too).
- Modem: `live.dts:7343` `qcom,mss@4080000`, `compatible = "qcom,pil-tz-generic"`, `qcom,firmware-name = "modem"`, `qcom,pas-id = <4>`, `qcom,sysmon-id = <0>`, `qcom,ssctl-instance-id = <0x12>`. It is loaded through TZ PAS, so no MBA.
- rmtfs memory: `live.dts:6712–6717` `qcom,rmtfs_sharedmem@0 { compatible = "qcom,sharedmem-uio"; reg = <0 0x280000>; reg-names = "rmtfs"; qcom,client-id = <1>; }`. Address 0 means it is allocated dynamically by `msm_sharedmem` (see §3).
- Factory identity: `/chosen/cdt/cdb2` has `wlan_mac1`, `wlan_mac2`, `bt_addr` (values not reproduced here).
- GLINK: `live.dts:7129ff`, edge `mpss` with an `IPCRTR` channel (`qcom,modem_qrtr`). This is QRTR transport to the modem.

---

## 2. Android bring-up sequence

### rc files (vendor.img) [V]

| File | What matters |
|---|---|
| `/etc/init/hw/init.redfin.rc:17` | imports `init.sm7250.rc`; `:33–36` `service vendor.mdm_helper` (external-modem helper, irrelevant: no MDM on redfin) |
| `/etc/init/hw/init.sm7250.rc:159–201` | `on fs`: `mount_all fstab.sm7250 --early` (modem partition → `/vendor/firmware_mnt`); persist `rfs/` dirs |
| `init.sm7250.rc:203–211` | `on post-fs`: wait for qseecomd listeners, then **`write /dev/ipa 1`** (loads the IPA firmware) |
| `init.sm7250.rc:443–463` | `on boot`: `setprop wifi.interface wlan0`, `start init-modem-sh` (publishes the IMEI to props), `ro.boot.wificountrycode 00`, `chown /d/icnss/stats` |
| `init.sm7250.rc:568–591` | `service vendor.per_mgr /vendor/bin/pm-service` (peripheral manager, **the modem voter**), started on `persist.vendor.modem.esim.reset=done/noneed` or `sys.boot_completed=1`; `per_proxy` follows |
| `init.sm7250.rc:629–633` | `service vendor.qrtr-ns /vendor/bin/qrtr-ns -f` (class core) |
| `init.sm7250.rc:635–644` | `irsc_util /vendor/etc/sec_config` (IPC-router security rules; **no-op on QRTR**: `net/qrtr/qrtr.c` has no security-rule hook), `modem_svc -q` (Google modem service, not needed for wifi) |
| `init.sm7250.rc:652–668` | `vendor.ssr_setup` writes `/sys/bus/msm_subsys/devices/*/restart_level` from `persist.vendor.sys.ssr.restart_level`; `enable_ramdumps` 0/1 |
| `init.sm7250.rc:717–722` | `service insmod_sh /vendor/bin/init.insmod.sh /vendor/etc/init.insmod.${ro.hardware}.cfg` |
| `/etc/init.insmod.redfin.cfg:8–19` | `modprobe -b *` (second-stage modules incl. **wlan.ko**), `setprop vendor.all.modules.ready`, `enable /sys/kernel/boot_adsp/boot`, `enable /sys/kernel/boot_cdsp/boot` (ADSP/CDSP only; **nothing writes a boot_wlan or modem trigger**) |
| `init.sm7250.rc:738–747` | `service pd_mapper /vendor/bin/pd-mapper` (class core); `service cnss-daemon /vendor/bin/cnss-daemon -n -l` (class late_start, user system, groups inet wifi) |
| `/etc/init/vendor.qti.rmt_storage.rc:7–12` | `service vendor.rmt_storage /vendor/bin/rmt_storage` (class core, root) |
| `/etc/init/vendor.qti.tftp.rc:11–13` | `service vendor.tftp_server /vendor/bin/tftp_server` (class core, root) |
| `/etc/init/hw/init.sm7250.mpssrfs.rc` | `mkdir /data/vendor/rfs/mpss` (tftp readwrite root) |
| `/etc/init/cnss-daemon.rc` | only `mkdir /data/vendor/wifi/cnss_daemon` |
| `/etc/init/android.hardware.wifi.supplicant-service.rc` | wpa_supplicant on `wlan0` (replaced by Ubuntu's NM + wpa_supplicant) |
| `/ueventd.rc:17–18` | `firmware_directories /vendor/firmware_mnt/image/` (plus AOSP's defaults `/etc/firmware/ /odm/firmware/ /vendor/firmware/ /firmware/image/`) |
| `/etc/fstab.sm7250` | `/dev/block/bootdevice/by-name/modem  /vendor/firmware_mnt  vfat  ro,shortname=lower,…  wait,slotselect` |

No Android property or sysfs write boots the modem directly. **The modem boots when a process opens `/dev/subsys_modem`** (`subsys_device_open` → `subsystem_get_with_fwname`, `drivers/soc/qcom/subsystem_restart.c:1457–1477`, node created at `:1544` as `subsys_%s`), and it stays up while the file is open (`subsys_device_close` → `subsystem_put`, `:1479–1495`). On Android, `pm-service` does that when a client votes. Here the client is cnss-daemon (`pm_vote`, via `libperipheral_client.so`), which is why the PIL load follows cnss-daemon's start by 90 ms. **qcacld writes no `/sys/kernel/boot_wlan` trigger when it is a module:** `hdd_module_init` calls `hdd_driver_load()` directly (`core/hdd/src/wlan_hdd_main.c:15535–15540`); the `boot_wlan` sysfs node (`:216–237`, `:15414`) exists only for a built-in driver. `/dev/wlan` ("ON"/"OFF", `:14375–14428`) is the framework's on/off hint: it waits for driver load and stops the idle-shutdown timer. Not needed with NM, which simply brings the netdev up.

### The tftp/rfs tree the modem sees (vendor `/rfs/msm/mpss`) [V]

| Modem path (TFTP over QRTR) | Android target |
|---|---|
| `/readonly/firmware` | `/vendor/firmware_mnt` (modem partition) |
| `/readonly/vendor/firmware` | `/vendor/firmware` (holds `wlanmdsp.mbn`, `bdwlan-*.bin`, `modemuw.jsn`) |
| `/readonly/vendor/mbn/{mcfg_hw,mcfg_sw,mcfg.version}` | modem_pr MCFG (cellular config) |
| `/readwrite` | `/data/vendor/rfs/mpss` |
| `/shared`, `/hlos` | `/mnt/vendor/persist/rfs/shared`, `.../hlos_rfs/shared` |
| `/ramdumps` | `/data/vendor/tombstones/rfs/modem` |

### Measured timeline (Android 14 on the stock kernel, `firmware/inventory/bugreport/dmesg-after-test4.txt`) [V]

| t (s) | dmesg line | Event |
|---|---|---|
| 0.58 / 0.61 | 692, 728 | `qrtr.ko`; `service-locator.ko enable=1` (vendor cmdline `service_locator.enable=1`) |
| 0.65 / 0.75 | 834, 1069 | `msm_icnss.ko`; "icnss: Platform driver probed successfully" (this queues the PDR `get_service_location`) |
| 0.99 | 1462 | "msm_sharedmem: Device created for client 'rmtfs'" |
| 2.49 | 2778 | `insmod_sh` starts |
| 2.66–2.81 | 2881–2985 | IPA firmware `ipa_fws.mdt` via PIL ("Brought out of reset"), from `write /dev/ipa 1` |
| 3.51 | 3518, 3521 | "wlan: Loading driver v5.2.05.22K +PANIC_ON_BUG"; `wlan_hdd_state` (/dev/wlan) |
| 4.42 | 4592 | `vendor.qrtr-ns` |
| 4.44 / 4.45 | 4599, 4604 | `irsc_util`, `modem_svc` |
| 4.47 | 4625 | `pd_mapper` |
| 4.49 / 4.50 | 4652, 4654 | `vendor.rmt_storage`, `vendor.tftp_server` |
| 4.56 | 4699–4700 | "servloc: Connection established with the Service locator" / "Service locator initialized" |
| 4.82 | 4859 | `vendor.per_mgr` |
| 6.76 | 5142 | `cnss-daemon` |
| 6.85 | 5226–5251 | memshare before-powerup; "subsys-pil-tz 4080000.qcom,mss: … modem.mdt"; "modem: loading from 0x8c000000" |
| 7.74 / 7.80 | 5516, 5524 | "modem: Brought out of reset", "Power/Clock ready interrupt received" |
| 9.06 | 5755–5757 | service-notifier: indication from **`msm/modem/wlan_pd`** (instance 180) → **"icnss_qmi: QMI Server Connected"** (WLFW service 0x45) |
| 14.98 | 6080 | **"icnss: WLAN FW is ready: 0xd87"** (≈ 6 s later: cnss-daemon's BDF download) |
| 15.10–15.12 | 6122–6141 | `wma_wait_for_ready_event: FW ready event received`; `hdd_platform_wlan_mac: provisioned MAC`; "using MAC address from platform driver" |
| 18.19 | 6363 | "Psoc idle timeout elapsed; starting psoc shutdown" (FW powered down until an interface goes up) |
| 244.8 | 7169–7229 | "Wifi Turning On from UI" (/dev/wlan ON) → FW ready again → `wlan0: link is not ready` (wpa_supplicant takes over) |

---

## 3. Each daemon vs. an open-source equivalent on this kernel

### QRTR name service: needed (userspace) [V]

`net/qrtr/` in this tree has `qrtr.c smd.c tun.c usb.c fifo.c mhi.c` and **no `ns.c`**. The in-kernel name service arrived in mainline 5.7. So `qrtr-ns` is required. The kernel's default node id is 1 (`net/qrtr/qrtr.c:125`). When a name service binds the control port, the kernel resets all QRTR sockets (`qrtr_reset_ports`, `:1470–1513`), and kernel QMI handles re-send their lookups (`drivers/soc/qcom/qmi_interface.c:422–438`, `qmi_handle_net_reset`). So kernel clients registered before qrtr-ns started (icnss, servloc) recover when it comes up. Android runs it the same way (`qrtr-ns -f`).

Ubuntu noble: **`qrtr-tools` 1.0-2ubuntu3** (universe, arm64) ships `/usr/bin/qrtr-ns`, `qrtr-lookup`, `qrtr-cfg` and `qrtr-ns.service`; also `libqrtr1`/`libqrtr-dev` 1.0 [V, packages.ubuntu.com]. Its unit starts it with node id 1 [S], the same as the kernel default.

### rmtfs: works via UIO [V for the mechanism, U on the phone]

- Kernel side: `drivers/uio/msm_sharedmem/msm_sharedmem.c`. Address 0 in DT → `dma_alloc_coherent` of 0x280000 (`:148–175`); `setup_shared_ram_perms` hyp-assigns it to HLOS+MSS for client id 1 (`:71–105`, `:189`); the uio device is named after `reg-names`, i.e. **`rmtfs`** (`info->name = clnt_res->name`, `:193`), with `maps/map0/addr|size` = the physical buffer (`:195–196`). Android's `rmt_storage` finds it by scanning `/sys/class/uio/uio*/name` (strings in `/vendor/bin/rmt_storage`).
- linux-msm/rmtfs `sharedmem.c` (v1.0 and master): tries `/dev/qcom_rmtfs_mem1` (absent: `QCOM_RMTFS_MEM` off) → **falls back to `/dev/qcom_rmtfs_uio1`**, reading `maps/map0/addr` and `maps/map0/size` through udev, then mmaps it → last resort `/dev/mem` + `/proc/device-tree/reserved-memory/rmtfs*` (no such node here). It does **not** match uio names, so we need a udev rule:
  `SUBSYSTEM=="uio", ATTR{name}=="rmtfs", SYMLINK+="qcom_rmtfs_uio1"`.
- Options (`getopt "o:Prsv"`): `-P` raw partitions by partlabel (`modemst1`, `modemst2`, `fsg`, `fsc` on LUN sdf), `-r` **read-only** (EFS writes stay in RAM; use this first, since modemst1/2 hold calibration; backups are in `firmware/backup/`), `-v` verbose, `-s` start/stop the modem via **remoteproc** sysfs. **Drop `-s`** (no remoteproc here); we boot the modem by opening `/dev/subsys_modem`.
- Ubuntu noble: **`rmtfs` 1.0-3** (universe, arm64) with `rmtfs.service` [V]. Its packaged ExecStart is `rmtfs -r -P -s` [S, matches the Pixel 2's mainline use]; we override it with a drop-in.

### tqftpserv: needs a fix for "no remoteproc" and a newer version [V]

- Upstream master `translate.c`: prefixes `/readonly/firmware/image/`, `/readonly/firmware/modem_pr…` (keeps `modem_pr/`), `/readwrite/` (→ `/var/lib/tqftpserv`), `/readonly/vendor/firmware_mnt/image/`, **`/readonly/vendor/firmware/`**. All read-only lookups go through `translate_readonly()`, which **opens `/sys/class/remoteproc` and, for each entry, takes `dirname(<entry>/firmware)`**. It then tries `<firmware_class.path>/<dir>/<file>`, `/lib/firmware/updates/<dir>/<file>`, `/lib/firmware/<dir>/<file>`. If the class is missing or empty, every read-only request fails.
- **v1.0 (noble's `tqftpserv` 1.0-5)** handles only `/readonly/firmware/image/` and `/readwrite/` (→ `/tmp/tqftpserv`), and also requires remoteproc. On redfin, `wlanmdsp.mbn` lives in `/vendor/firmware`, which the vendor rfs tree exposes as `/readonly/vendor/firmware/`, so the modem most likely asks for that path [U: confirm from tqftpserv's log]. **Build upstream master from a pinned submodule** rather than using noble's package.

### pd-mapper: not in noble; same remoteproc problem [V]

- Not published in the Ubuntu archive at all (Launchpad: no current release; only a third-party PPA for jammy). Build it from a pinned submodule (linux-msm/pd-mapper, BSD-3-Clause [S]).
- It walks `/sys/class/remoteproc/*/firmware`, then scans `<firmware_class.path or /lib/firmware>/<dirname>` for `*.jsn`. **With no remoteproc entries it loads no maps, prints "no pd maps available" and exits 1.**
- It must serve **`modemr.jsn`** (modem partition `image/`) and **`modemuw.jsn`** (vendor `/firmware`). `modemuw.jsn` maps service `wlan/fw` → domain `msm/modem/wlan_pd`, `qmi_instance_id` 180. The vendor pd-mapper reads `/vendor/firmware` and `/vendor/firmware_mnt/image` (strings in `/vendor/bin/pd-mapper`).
- Kernel side: `drivers/soc/qcom/service-locator.c` is a **client** of QMI service **0x40 v1, instance 1** (SERVREG_LOC; `service-locator-private.h:11–12`, `service-locator.c:23,268–271`). That is exactly what pd-mapper publishes. icnss asks it for `"wlan/fw"` as client `"ICNSS-WLAN"` (`icnss.c:55–56`, `:2006–2008`) to get PD-restart notifications. The modem also needs a locator for its wlan_pd. The Pixel 2 found "without it a kworker hangs in pd_locator_work" [S].
- **Timing trap:** `init_service_locator` waits **300 s** (`LOCATOR_SERVICE_TIMEOUT`, `:28`, `:273–286`) from the first `get_service_location`, which icnss queues at probe (initramfs, a few seconds after boot). After a timeout it sets the static `service_timedout` and **returns -ETIME forever in that boot**. That is the "servloc … Unable to connect to service locator" family already in our P3.6 dmesg (`:348`). **pd-mapper must run within ~5 min of boot**, so enable it at boot and don't start it by hand later. A missing locator only disables icnss PD-restart; it does not stop WLFW from appearing. But the modem's own wlan_pd start needs pd-mapper.

**Two ways to satisfy the remoteproc lookup (both [U]):**

1. *No patch, systemd namespace:* in tqftpserv.service and pd-mapper.service use `TemporaryFileSystem=/sys/class` plus `BindReadOnlyPaths=/etc/pixel5/remoteproc:/sys/class/remoteproc`, where `/etc/pixel5/remoteproc/modem/firmware` is a regular file containing `modem.mdt`. Then `dirname` gives `.`, and both daemons look in `<firmware_class.path>/./` = our firmware farm (§4). Neither daemon needs anything else under `/sys/class`.
2. *Small patch* (carried in `external/` patches): when `/sys/class/remoteproc` is missing, use `firmware_class.path` (or a `-d <dir>` option) as the one firmware dir. This is cleaner long-term and maybe upstreamable.

### cnss-daemon: required for BDF; no open-source replacement exists [V for the need]

- **icnss v1 never downloads the board file.** `icnss_driver_event_server_arrive` (`icnss.c:1061ff`) does: connect to WLFW → `wlfw_ind_register` → `wlfw_msa_mem_info` → hyp-assign MSA → `wlfw_msa_ready` → `wlfw_cap` → `icnss_hw_power_on` → dynamic feature mask, then waits for `FW_READY_IND` (`icnss_qmi.c:1046,1197`). `WLFW_BDF_DOWNLOAD` appears only as a max message length (`icnss_qmi.c:1343`).
- The vendor `/vendor/bin/cnss-daemon` strings: "WLFW service connected", "Wait for MSA ready Indication from FW", "Wait for FW memory ready indication", "Looking for BDF file: %s", `bdwlan-%s.b%02x`, `bdwlan-%s.%03x`, `bdwlan-u`, "Using BDF file: %s", `regdb.bin` / "Failed to Download the REGDB File", "Sending MAC address to FW" (QMI DMS from the modem NV), `/vendor/firmware/`, `/vendor/firmware_mnt/image/`, `/data/vendor/wifi/wlfw_cal_%02d.bin`. It also votes the modem up through `libperipheral_client.so` (binder to pm-service). The Pixel 2 (same icnss design on 4.4) proved it: "cnss-daemon downloads the BDF … Only then does icnss get FW_READY and wlan.ko probe" (`../ubuntu-touch-pixel2/docs/log.md:77`).
- BDFs in vendor `/firmware`: `bdwlan-redfin.bin` and `bdwlan-u-redfin.bin` (26328 B each, **different** content). Which one cnss-daemon picks for this phone (SKU GTT9Q, `pcbcfg R3-ROW`, `radio.subtype` 2) is **[U]**. The phone is ROW, so `bdwlan-redfin.bin` is my first guess. There is no `regdb.bin` in vendor `/firmware`, so the REGDB download probably fails harmlessly on Android too [U].
- The MAC that cnss-daemon sends to the FW is optional for us: qcacld gets the MAC from the platform (`hdd_initialize_mac_address`, `wlan_hdd_main.c:11670`) and pushes it via WMI. The vendor ini sets `enable_mac_provision=1`, which **requires** the platform MAC. `google_wlan_mac.c:28–29,82–91` provides it from `/chosen/cdt/cdb2/wlan_mac1` via `cnss_utils_set_wlan_mac_address` at module load [V].

**Options for the BDF step:**

- **A. Own WLFW BDF client (recommended first).** About 300 lines of C on `libqrtr` (noble `libqrtr-dev` has a QMI encoder). It looks up service 0x45 v1 inst 0 (`wlan_firmware_service_v01.h:9–10`), registers for MSA-ready / FW-ready indications (`QMI_WLFW_IND_REGISTER_REQ 0x20`), waits until icnss has finished `msa_ready`/`cap`, then sends `QMI_WLFW_BDF_DOWNLOAD_REQ_V01` (0x25) in segments of `QMI_WLFW_MAX_DATA_SIZE_V01` = 6144 bytes (`:56`, `:102`; message layout `:482–497`: `valid, file_id, total_size, seg_id, data, end, bdf_type`). The element tables to port are in `drivers/soc/qcom/wlan_firmware_service_v01.c`. Mainline ath10k's `qmi.c`/`qmi_wlfw_v01.c` does the same exchange in-kernel for the same WCN3990 firmware family, so it is a good reference for the field values (bdf_type BIN = 0) [S]. This is original work (MIT), with no Android pieces.
- **B. Vendor cnss-daemon in a bionic shim (Pixel 2 route).** It needs `/system` (logical partition in super, dm-linear like vendor), the `com.android.runtime` APEX (bionic, linker64), VNDK v34 libs, a legacy property area (`ro.baseband`, `ro.hardware`, `ro.boot.hardware.radio.subtype`, …), and stubs for `libperipheral_client.so`. Its NEEDED list: `libcutils liblog libqmi_cci libqmi_common_so libnl libcld80211 google_wifi_firmware_config_version_c_wrapper libperipheral_client libmdmdetect libqmiservices libc++` (`readelf -d`). It is proven on the Pixel 2 (`../ubuntu-touch-pixel2/rootfs/overlay/usr/local/sbin/android-env`, `etc/systemd/system/cnss-daemon.service`), but Android 14 is heavier than the Pixel 2's Android 11. It also runs `vndbinder` threads, so expect binder errors. Keep it as the fallback, or as a one-off probe to learn which BDF file it picks ("Using BDF file: %s").

### Not needed for wifi

`pm-service`/`pm-proxy` (replaced by a unit that holds `/dev/subsys_modem` open), `mdm_helper` (no external modem), `irsc_util` (no QRTR security hook in this tree), `modem_svc`, `qseecomd` (only for the IPA firmware path, see below), `ipacm`/`netmgrd`/`qcrild` (cellular), `wificond`/`wifi_ext`/Android `wpa_supplicant` (NM + Ubuntu `wpasupplicant` speak nl80211 to cfg80211), `subsystem_ramdump` (ramdumps are off by default, `enable_ramdumps`=0), diag daemons (in-kernel `diagchar`, loaded first-stage #87, consumes the modem's diag channel; the Pixel 2 mainline needed `diag-router` only because mainline has no in-kernel diag [S]).

**IPA:** `wlan.ko` links against `ipa3.ko`, and the vendor ini has `gIPAConfig=0x7d` (IPA offload incl. uC). qcacld registers a "uC ready" callback if the IPA firmware isn't loaded (`components/ipa/core/src/wlan_ipa_core.c:478–503,738–748`), so it should cope [U]. If probe fails on IPA, either `echo 1 > /dev/ipa` (Android's post-fs step; may need qseecomd [U]) or override the ini with `gIPAConfig=0`.

---

## 4. Firmware loading in this kernel [V]

- `build/kernel/.config:1424–1426`: `CONFIG_FW_LOADER=y`, `EXTRA_FIRMWARE=""`, `# CONFIG_FW_LOADER_USER_HELPER is not set` (so no `_FALLBACK` either; from our fragment `kernel/redfin-ubuntu.config`). A missing file fails at once (stock waited 60 s: "Falling back to syfs fallback for: modem.mdt" in the Android dmesg).
- Search order (`drivers/base/firmware_loader/main.c:284–298`): `fw_path_para` (= `firmware_class.path`, **writable at runtime** at `/sys/module/firmware_class/parameters/path`, mode 0644, one directory), then `/lib/firmware/updates/<uname>`, `/lib/firmware/updates`, `/lib/firmware/<uname>`, `/lib/firmware`. Symlinks are followed.
- PIL: `peripheral-loader.c:1245–1246` `snprintf(fw_name, "%s.mdt", desc->fw_name); request_firmware(...)`; segments `:1021–1030` `"%s.b%02d"` via `request_firmware_into_buf`. `fw_name` comes from DT `qcom,firmware-name` (`"modem"`), so the names are relative: `modem.mdt`, `modem.b00`…`modem.b34`. The name can be changed at runtime via `/sys/bus/msm_subsys/devices/subsysN/firmware_name` (`subsystem_restart.c:340–359`, buffer < 30 chars). Not needed.
- qcacld: ini via `cfg_parse(WLAN_INI_FILE)` → `qdf_file_read` → `request_firmware("wlan/qca_cld/WCNSS_qcom_cfg.ini")` (`wlan_hdd_misc.h:44–46` with `MSM_PLATFORM` from `Kbuild:2197`; `wlan_hdd_main.c:10881–10886`). **If it is missing, hdd context creation fails.** Optional `wlan/qca_cld/wlan_mac.bin` (`wlan_hdd_cfg.c:242`) is unused when the platform MAC is provisioned.
- `grep` over `drivers/soc/qcom`, `drivers/net/wireless/cnss*`, `drivers/staging/qcacld-3.0/core`, `drivers/staging/wlan_mac`, `drivers/base/firmware_loader`: **no hard-coded `/vendor/…`, `/firmware/…` or `/firmware_mnt` paths**. All lookups are relative.
- The modem pulls `wlanmdsp.mbn` (and MCFG etc.) **itself over TFTP/QRTR**, not through the kernel loader. That is tqftpserv's job (§3).

Firmware the kernel and daemons must find (one farm, e.g. `/run/pixel5-fw`, set as `firmware_class.path`):

| Needed by | Files | Source |
|---|---|---|
| PIL (kernel) | `modem.mdt`, `modem.b00`–`modem.b34` | modem partition `image/` |
| PIL, optional | `ipa_fws.mdt/.bNN` | vendor `/firmware` |
| qcacld (kernel) | `wlan/qca_cld/WCNSS_qcom_cfg.ini` | vendor `/firmware/wlan/qca_cld/` |
| tqftpserv → modem | `wlanmdsp.mbn`, `modem_pr/…` (MCFG), whatever else the modem asks for | vendor `/firmware`, modem `image/modem_pr/` |
| pd-mapper | `modemr.jsn`, `modemuw.jsn` (+ `adsp*.jsn`, `cdspr.jsn`, harmless) | modem `image/`, vendor `/firmware` |
| BDF client | `bdwlan-redfin.bin` (or `bdwlan-u-redfin.bin`, [U]) | vendor `/firmware` |

Like the Pixel 2 (`android-env`), mount vendor and `modem${slot}` read-only on the phone and symlink both trees into the farm. To override the ini, put a real file at `wlan/qca_cld/WCNSS_qcom_cfg.ini` *in the farm*: `fw_path_para` is searched before `/lib/firmware`.

---

## 5. Bring-up plan for Ubuntu (ordered; one change per test image)

Each step is tethered: `fastboot boot build/boot.img`, nothing flashed. Each step has a gate read from `dmesg`/`journalctl`/`qrtr-lookup`. Units are written so that a later step can be disabled by masking one unit.

**Step 0 — safety net first (before any modem work).**
- Add **`panic=0`** to our boot cmdline (`make-bootimg.sh` extra args). With `panic_timeout == 0`, `watchdog_v2` disables the watchdog on panic (`drivers/soc/qcom/watchdog_v2.c:224–225`). The phone then **hangs** instead of rebooting after 5 s (`CONFIG_PANIC_TIMEOUT=5`, `.config:5908`) into stock Android, where `fstab` `formattable` would format userdata. Recovery from a hang: owner holds Power + Vol-down → fastboot. Gate: `cat /proc/sys/kernel/panic` = 0. Do **not** trigger a test panic.
- **Ask the owner** whether to flash our `boot.img` to `boot_b` now (P5.2 early). That is the only full protection against resets that bypass the kernel panic path (TZ/XPU resets, PMIC watchdog), which would still land in Android.
- ramdumps stay off (`/sys/module/subsystem_restart/parameters/enable_ramdumps` = 0, the default).

**Step 1 (P4.1) — mounts and firmware farm** (`pixel5-firmware.service`, oneshot, After=local-fs):
- vendor: dm-linear from super with the P2.6 extents → `/vendor` (ro). `modem${slot}` (slot from `androidboot.slot_suffix`, grepped as a single key) → `/vendor/firmware_mnt` (`vfat ro,shortname=lower`).
- `/run/pixel5-fw`: symlinks to `/vendor/firmware/*` and `/vendor/firmware_mnt/image/*`; `printf /run/pixel5-fw > /sys/module/firmware_class/parameters/path`.
- `echo RELATED > /sys/bus/msm_subsys/devices/<the one whose name = modem>/restart_level`. The default level 0 is `SYSTEM` (`subsystem_restart.c:122–125`), and a modem crash at that level is `panic("subsys-restart: Resetting the SoC - %s crashed.")` (`:1283–1296`). Android does this in `ssr_setup`.
- Gate: files visible through the path; `restart_level` = RELATED; nothing booted yet.

**Step 2 — qrtr-ns** (apt `qrtr-tools`; keep its `qrtr-ns.service`). Gate: `qrtr-lookup` runs; kernel lookups visible after the socket reset.

**Step 3 — pd-mapper** (pinned `external/pd-mapper`, built in arm64 Docker; `pd-mapper.service` with the remoteproc namespace trick or patch; After=qrtr-ns; **enabled at boot**, so it runs well inside the 300 s servloc window). Gate: dmesg `servloc: … Connection established with the Service locator` and `Service locator initialized` (the same as Android lines 4699–4700); `qrtr-lookup` shows service 64.

**Step 4 — tqftpserv** (pinned `external/tqftpserv`, same trick; `StateDirectory=tqftpserv` for `/var/lib/tqftpserv`; pre-create `ota_firewall/ruleset` as on the Pixel 2 [S]). Gate: running, service 4096 in `qrtr-lookup`.

**Step 5 — rmtfs** (apt `rmtfs`; drop-in `ExecStart=/usr/bin/rmtfs -r -P -v`; udev rule for `/dev/qcom_rmtfs_uio1`). Gate: rmtfs logs the mapped address/size (0x280000), service 14 in `qrtr-lookup`. Note: `-r`, so nothing is written to modemst1/2 until we decide otherwise.

**Step 6 — `wlan.ko`** (`/etc/modules-load.d/wlan.conf` or `ExecStartPre=modprobe wlan`). Android loads it before the modem; probe is deferred until FW_READY (`icnss_driver_event_register_driver`, `icnss.c:1322ff`). Gate: "wlan: Loading driver", `/dev/wlan` exists, no wlan0 yet, no panic.

**Step 7 — boot the modem** (`modem.service`: `ExecStart=/bin/sh -c 'exec 3</dev/subsys_modem; exec sleep infinity'`, Requires/After the units above, as on the Pixel 2). On first boot (`subsys_start`) a failure only returns an error, with no panic. Gates, in order:
1. `subsys-pil-tz 4080000.qcom,mss: modem: loading from 0x8c000000`, "Brought out of reset", "Power/Clock ready", subsys `state` ONLINE.
2. tqftpserv/rmtfs logs show modem requests (note every path the modem asks for, including any ENOENT).
3. `service-notifier: Indication received from msm/modem/wlan_pd` and **`icnss_qmi: QMI Server Connected`** (WLFW is up).
4. Watch for 5 min: no `Restart sequence requested for modem`.

If 1 fails, check the farm. If 1 passes but 3 doesn't, check pd-mapper and tqftpserv logs (wlanmdsp.mbn path).

**Step 8 — BDF → FW_READY** (Option A tool as `wlfw-bdf.service`, After=modem.service; or Option B vendor cnss-daemon). Gate: **`icnss: WLAN FW is ready`**, `wma_wait_for_ready_event: FW ready event received`, "using MAC address from platform driver", `ip link` shows **wlan0** (PLAN P4.2 gate). If the first BDF guess gives FW errors, try the other file (one change per test).

**Step 9 (P4.4) — NetworkManager.** `nmcli dev wifi list`, then a profile with **`autoconnect no`** first (Pixel 2 lesson: a crash plus autoconnect becomes a boot loop). Check the PSK before sending it. Then autoconnect, and SSH over wifi with the cable unplugged. The MAC is already stable (factory MAC from DT). Optionally set NM `wifi.scan-rand-mac-address=no` if scans misbehave [U].

Packages (noble arm64, universe): `qrtr-tools` 1.0-2ubuntu3, `libqrtr1`/`libqrtr-dev` 1.0-2ubuntu3, `rmtfs` 1.0-3, `tqftpserv` 1.0-5 (too old, see §3). **No `pd-mapper` package.** New submodules: linux-msm `pd-mapper` and `tqftpserv` (BSD-3-Clause [S]; check `LICENSE` before adding). Optionally `qrtr`/`rmtfs` sources too, if we want to patch rather than use the packages.

---

## 6. Risks and how to contain them

| Risk | Mechanism (source) | Containment |
|---|---|---|
| **Reset lands in stock Android → userdata formatted** | `CONFIG_PANIC_TIMEOUT=5`; bootloader boots active slot (stock); fstab `formattable` (Pixel 2 lost userdata 3× this way) | `panic=0` (Step 0); owner watches the screen during modem tests; consider flashing our boot to the active slot first (owner OK) |
| Modem crash → SoC reset | default `restart_level` SYSTEM → `panic` (`subsystem_restart.c:1283–1296`) | `RELATED` before opening `/dev/subsys_modem` |
| SSR itself panics | RELATED path → `subsystem_powerup`: `panic` on powerup error or err_ready timeout (`:838–870`); shutdown failure panic (`:793`); `CONFIG_PANIC_ON_SSR_NOTIF_TIMEOUT=y` + 20 s notifier timeouts (`.config:4690–4692`, `subsystem_restart.c:75–76`); crash storm `max_restarts` (`:493–549`, off by default) | Keep the firmware mounts up for the whole session (SSR reloads `modem.mdt`); don't stop `modem.service` casually; prefer reboot over SSR experiments |
| `wlan.ko` asserts panic the kernel | qcacld `PANIC_ON_BUG := y` because `CONFIG_SLUB_DEBUG=y` (`configs/default_defconfig:418–426`, `.config:233`); `QDF_DEBUG_PANIC` on psoc failure (`wlan_hdd_main.c:10891`). Stock has the same ("+PANIC_ON_BUG") | `panic=0`; load wlan.ko only from Step 6 on |
| servloc dead for the rest of the boot | 300 s timeout, then `service_timedout` (`service-locator.c:28,273–286`) | pd-mapper enabled at boot; if missed, reboot (don't reload modules) |
| Modem crash loop from missing files | modem asks via TFTP for files we don't serve (`/shared`, `/hlos`, `/readonly/vendor/mbn/…`) | log every tqftpserv ENOENT; add mappings one at a time; the Pixel 2 mainline modem tolerated missing ones [S] |
| EFS writes to modemst1/2 | rmtfs without `-r` | run `-r` until wifi is stable; backups exist in `firmware/backup/` |
| BDF mismatch | two BDF variants, choice unknown | try `bdwlan-redfin.bin`, then `-u-`; or learn the pick from the vendor cnss-daemon once (Option B) |
| IPA not loaded | `gIPAConfig=0x7d` in the vendor ini | ini override `gIPAConfig=0` if probe complains |
| Reloading wlan/icnss without a modem restart | Pixel 2 mainline: "msa map permissions -22" after a reload | reboot between attempts |

Testing discipline: one new unit or change per test image, numbered tests in `docs/log.md`, gates read from the same boot. Never `fastboot flash` without the owner's OK. Never boot stock Android.

---

## Sources

- Kernel: `external/kernel-redbull` (LineageOS 4.19.325): `drivers/soc/qcom/{icnss.c,icnss_qmi.c,wlan_firmware_service_v01.h,service-locator.c,service-locator-private.h,subsystem_restart.c,peripheral-loader.c,watchdog_v2.c,Makefile,Kconfig}`, `drivers/uio/msm_sharedmem/msm_sharedmem.c`, `drivers/staging/qcacld-3.0/{Kbuild,configs/default_defconfig,core/hdd/...}`, `drivers/staging/wlan_mac/google_wlan_mac.c`, `drivers/base/firmware_loader/main.c`, `net/qrtr/qrtr.c`, `arch/arm64/boot/dts/vendor/qcom/lito.dtsi`, `arch/arm64/boot/dts/google/lito-redbull-memory.dtsi`.
- Our build: `build/kernel/.config`, `build/kernel/modules-install/lib/modules/*/modules.{dep,alias}`, `build/stock/vbx/lib/modules/modules.{load,softdep}`.
- Vendor (`firmware/vendor.img`, UP1A.231105.001.B2): `/etc/init/hw/init.{redfin,sm7250,sm7250.mpssrfs}.rc`, `/etc/init/{cnss-daemon,vendor.qti.rmt_storage,vendor.qti.tftp,android.hardware.wifi.supplicant-service}.rc`, `/etc/init.insmod.redfin.cfg`, `/etc/fstab.sm7250`, `/ueventd.rc`, `/rfs/msm/mpss/*`, `/firmware/{modemuw.jsn,bdwlan-*.bin,wlanmdsp.mbn,wlan/qca_cld/WCNSS_qcom_cfg.ini}`, `/lib/modules/modules.load`, binaries `/bin/{cnss-daemon,pd-mapper,tftp_server,rmt_storage,pm-service,ssr_setup}` (strings, `readelf -d`).
- Android run: `firmware/inventory/bugreport/dmesg-after-test4.txt`, `firmware/inventory/getprop.txt`. Live DT: `firmware/live.dts`.
- Pixel 2: `../ubuntu-touch-pixel2/docs/log.md:65–77,163–171`, `rootfs/overlay/usr/local/sbin/android-env`, `rootfs/overlay/etc/systemd/system/{modem,cnss-daemon,android-env}.service`, `{rmtfs,tqftpserv,qrtr-ns}.service.d/`.
- Upstream: [linux-msm/rmtfs `sharedmem.c`](https://github.com/linux-msm/rmtfs/blob/master/sharedmem.c), [`rmtfs.c` v1.0](https://github.com/linux-msm/rmtfs/blob/v1.0/rmtfs.c), [linux-msm/tqftpserv `translate.c`](https://github.com/linux-msm/tqftpserv/blob/master/translate.c) (and [v1.0](https://github.com/linux-msm/tqftpserv/blob/v1.0/translate.c)), [linux-msm/pd-mapper `pd-mapper.c`](https://github.com/linux-msm/pd-mapper/blob/master/pd-mapper.c) (and [v1.0](https://github.com/linux-msm/pd-mapper/blob/v1.0/pd-mapper.c)).
- Ubuntu archive (noble): [tqftpserv](https://packages.ubuntu.com/search?keywords=tqftpserv&searchon=names&suite=noble&section=all), [rmtfs](https://packages.ubuntu.com/noble/arm64/rmtfs/filelist), [qrtr-tools](https://packages.ubuntu.com/noble/arm64/qrtr-tools/filelist), [pd-mapper (no release in Ubuntu)](https://launchpad.net/ubuntu/+source/pd-mapper).
