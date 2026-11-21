# Pixel 2 (walleye) → Pixel 5 (redfin): transfer inventory

Source: `../ubuntu-touch-pixel2` (sibling clone) (read-only; 208 commits, 122 tracked files outside `external/` and `LICENSES/`, about 8,300 lines).
Target: this repository.
Scope: local analysis of the Pixel 2 repo only. Items marked **[verify P5]** are assumptions about the Pixel 5 that the hardware, kernel and boot-chain research agents need to confirm. I did no web research for them.

Legend: **R** = reuse as-is (at most a `pixel2`→`pixel5` rename), **A** = adapt (the logic carries over; walleye values are baked in), **D** = drop (MSM8998, walleye or 4.4-only).

---

## 0. Executive summary

- **The Pixel 2 repo is two ports in one.** The first is a downstream 4.4 kernel port that runs Android vendor daemons (`android-env`, `cnss-daemon`, bionic property area, `libperipheral_client` stub). The second is a mainline 7.2.2 port on Porthole's msm8998 patches: `rmtfs`, `tqftpserv`, `diag-router` and squashed firmware. A Pixel 5 port should copy **only the mainline path**. The whole 4.4 and Android-daemon stack is DROP, about 1,000 lines.
- **Generic infrastructure is ready to copy.** The parts that really are generic and battle-tested:
  - Docker build environment: `dev.sh`, x86 cross-compiling and qemu binfmt.
  - `build-all.sh` hash-stamp skeleton.
  - `check-prereqs.sh`.
  - Busybox initramfs with an NCM+ACM USB gadget, telnet/serial debug shell, a 10-minute auto-return to fastboot, and probe/flight-recorder variants.
  - `try-boot.sh` (tethered `fastboot boot` with 3x retry).
  - `ssh.sh`, `initrd-sh.py`, `serial-sh.py`, `push-overlay.sh`.
  - Rootfs from `ubuntu:24.04`, exported and packed with `mkfs.ext4 -d` and `img2simg`.
  - About 20 systemd/NM/udev overlay files.
  - qbootctl slot marking.
  - REUSE/SPDX licensing setup.
- **Boot-image layer assumptions are the most dangerous to copy blindly.**
  - `make-bootimg.sh` hardcodes header v0 and its offsets, the walleye stock cmdline with `dtbo_idx=3`, `os_version 11.0.0` and a 32 MiB limit.
  - The mainline boot image is `Image.gz` with an appended DTB.
  - Walleye mounts `vendor_a`/`modem_a` as plain partitions.
  - **[verify P5]**: redfin launched on Android 11. It very likely has boot header v3 with a `vendor_boot` partition (DTB and vendor ramdisk live there), dynamic partitions (`vendor` is a logical partition inside `super`), and different dtbo handling. The DTB packaging, `mount-vendor.sh`, `pixel2-modem-fw`, `get-firmware.sh` and `flash.sh` all need rework for that.
- **Rough split of the non-doc code:** 37 files / ~970 lines reusable as-is; 34 files / ~2,370 lines to adapt; 40 files / ~3,200 lines to drop (see §6).

---

## 1. Transfer inventory, file by file

### 1.1 Top level, process and licensing

| File | Class | Notes |
|---|---|---|
| `CLAUDE.md` (114) | A | Process rules carry over (see §2). Walleye-specific parts:<br>• lines 3-5: mainline on `boot_b`, 4.4 on `boot_a`.<br>• line 17: kernel-msm as the hardware reference.<br>• lines 48-49: pixel2-modem-fw, TAS2557.<br>• line 51: `/var/lib/pixel2/wlan0.mac`.<br>• lines 60-61: way back via `fastboot flash boot_b build/boot.img` (4.4).<br>• line 72: `PIXEL2_HOST`.<br>• line 75: PMIC regmap path `0-00`.<br>• line 87: container name `pixel2-build`.<br>• lines 100-104: the hardware-questions recipe uses HTC muskie DTs, `lge/*taimen*` and Porthole taimen.<br>• line 109: power measurements via `pmi8998-charger/current_now`. |
| `PLAN.md` (257) | A | Keep the format (see §2.2). Phases 0-7 and 9 are a good template. Phase 8 content is walleye-only. Phase 10 (licensing table) is reusable almost verbatim. Stale reference: `scripts/stage-mainline-wifi.sh` (now `stage-mainline.sh`). |
| `README.md` (63) | A | Install flow: case-sensitive APFS volume, clone, `check-prereqs`, `build-all`, `flash.sh`, `ssh.sh`. Change the URL, the device, the "not Verizon" note and the dual-kernel text. |
| `LICENSE` (21) | R | MIT, "The ubuntu-touch-pixel2 contributors" → rename. |
| `LICENSES/*` | R | MIT, GPL-2.0-only, BSD-2-Clause and CC0-1.0 texts. BSD-2 and CC0 are only needed if camera material is copied. |
| `LICENSING.md` (51) | A | Structure reusable. Exceptions table names pixel2-screen font, imx179.yaml, chromatix cct(). |
| `REUSE.toml` (43) | R | Rename copyright holder; drop the `walleye-audio.dtsi` Giuseppe Maggio block. |
| `docs/licensing-inventory.md` (99) | A | Use as the template for P10.1. |
| `.gitignore` (22) | R | `build/ out/ firmware/ *.img *.simg *.zip .env /sed??????`. |
| `.gitmodules` (39) | A | See §1.10. |

### 1.2 docs/

| File | Class | Notes |
|---|---|---|
| `docs/research.md` | D (template A) | Content is walleye-specific. The structure works as a template: device table, options surveyed, chosen route, known risks, handy facts, sources. |
| `docs/mainline.md` | D | msm8998 subsystem table; the format is reusable. |
| `docs/device-info.md` | A (template) | Shows exactly what to record: getvar all (without the serial), partition sizes, stock kernel version and toolchain, `unpack_bootimg` output, full stock cmdline, mkbootimg arguments. The redfin version must also cover `vendor_boot` and the header v3/v4 fields. |
| `docs/log.md` | D (content) | Lessons extracted in §3. Start a fresh log in the same style. |
| `docs/camera-walleye.md` (793) | D | Taimen→walleye camera DT port. The method is reusable (sources, per-camera map, risks, "UNCONFIRMED" list); the content is not. |

### 1.3 docker/

| File | Class | Walleye/4.4 assumptions |
|---|---|---|
| `docker/Dockerfile` (36) | A, or merge into mainline | Ubuntu **20.04** + **clang-11**, chosen to match the 4.4 stock toolchain; also `python2` and `gcc-arm-linux-gnueabi` (CROSS_COMPILE_ARM32 for 4.4). The rootfs packing step (`mkfs.ext4 -d`, `img2simg`, `simg2img`, `debugfs`, `busybox-static` for the initramfs) also runs in this image (`pixel2-build`). For a mainline-only port: one 24.04 image with clang-18+, `android-sdk-libsparse-utils`, `e2fsprogs`, `busybox-static`, `device-tree-compiler`, `cpio`, `lz4`, `ccache`. |
| `docker/mainline/Dockerfile` (21) | R | 24.04 + clang/lld/llvm-18 + ccache + `libqrtr-dev libudev-dev` (for diag-router). Bump the LLVM version if the sm7250 tree needs it. |
| `docker/libcamera/Dockerfile` (12) | R (later) | Generic libcamera build deps on 24.04. |

### 1.4 scripts/

| File | Class | Walleye-specific assumptions (file:line) |
|---|---|---|
| `dev.sh` (43) | **R** | Image name `pixel2-build` (:16). `DEV_CROSS=1` gives an amd64 image on x86 hosts; `DEV_IMAGE`/`DEV_DOCKERDIR` switch images. Comment :15 mentions `/Volumes/Pixel2Dev`. |
| `ssh.sh` (9) | **R** | `PIXEL2_HOST`, `build/ssh/pixel2_ed25519`, 172.16.42.1. |
| `initrd-sh.py` (73) | **R** | Telnet client for busybox telnetd (macOS has no telnet). Marker `__PIXEL2_DONE__`. |
| `serial-sh.py` (64) | **R** | Glob `/dev/cu.usbmodempixel2*` (:20) depends on the gadget serialnumber `pixel2-ubuntu`. That deliberately keeps the phone's real serial out of the device name. Rename both together. |
| `push-overlay.sh` (14) | **R/A** | Also builds and pushes `pixel2-screen` (:9-13). Sets the phone clock from the Mac; `chmod 600` on nmconnections (lesson: NM rejects 0644). |
| `check-prereqs.sh` (147) | **R** | Host checks; network list :121-123 includes android.googlesource.com and gitlab.freedesktop.org. Disk numbers (~45 GB + ~40 GB) assume two kernels. Case-sensitivity check :106-113. |
| `build-initramfs.sh` (25) | **R** | Static busybox + `reboot-bootloader.c` + `/dev/console` node. Generic. |
| `build-qbootctl.sh` (17) | **R** | Static qbootctl (linux-msm). Generic for Qualcomm A/B UFS. **[verify P5]**: redfin's slot attributes match the Qualcomm GPT bits qbootctl expects. |
| `build-modem-tools.sh` (22) | **R** | pil-squasher + diag-router; generic Qualcomm. Image name `pixel2-mainline-build`. |
| `build-all.sh` (191) | **A** | Skeleton generic (see §4). Walleye-specific:<br>• `KREL=4.4.223-walleye-ubuntu` (:21).<br>• SUBS list (:53-55).<br>• the 4.4 kernel, android-stubs, screen (uses `K_HEAD` of kernel-msm), bootimg (factory boot.img) and libcamera steps.<br>• `MAINLINE=0` switch.<br>• `build/ssh/pixel2_ed25519.pub`. |
| `build-mainline.sh` (118) | **A** | Generic logic:<br>• copies the tree with APFS `cp -c` (macOS) or `--reflink=auto` (Linux);<br>• applies the Porthole series in APKBUILD `source=` order;<br>• applies our patches incrementally, tracked in `.ours`;<br>• copies the `.dts`/`.dtsi` in every build;<br>• merges the fragment, then warns for each option that did not apply.<br>Specific values:<br>• `PKG=…/linux-postmarketos-qcom-msm8998-7.2` (:19), `DTS=msm8998-google-walleye-ubuntu` (:20);<br>• Porthole config file name (:97);<br>• `LLVM=-18` (:88), `KBUILD_BUILD_USER=pixel2` (:89);<br>• outputs `Image.gz` + `dts/qcom/$DTS.dtb`. |
| `build-mainline-bootimg.sh` (19) | **A** | Appended DTB: `cat Image.gz $DTB` (:17). This is header v0 behaviour; header v3 needs the DTB in `vendor_boot` **[verify P5]**. Cmdline `clk_ignore_unused pd_ignore_unused panic=10 reboot=w selinux=0 fbcon=font:TER16x32 quiet` (:19): the first five are good defaults, the font matches the 1080x1920 panel. |
| `make-bootimg.sh` (30) | **A (high risk)** | Hardcoded:<br>• `STOCK_CMDLINE` with `androidboot.hardware=walleye`, `ttyMSM0`, `msm_rtb.filter`, `firmware_class.path=/vendor/firmware`, `androidboot.dtbo_idx=3`, `buildvariant=user` (:15);<br>• `--header_version 0 --pagesize 4096 --base 0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 --tags_offset 0x100 --os_version 11.0.0 --os_patch_level 2020-10` (:20-22);<br>• the 32 MiB `boot_a/boot_b` limit (:28).<br>All must come from redfin's `unpack_bootimg` output (header v3: kernel + generic ramdisk in boot, cmdline/DTB/vendor ramdisk in vendor_boot; os_version/patch level must match or AVB/rollback may complain). |
| `build-bootimg.sh` (29) | **D** | 4.4-only: factory DTB spliced onto `Image.lz4`, cgroup-v1 flags, `DEBUG=1` adds `initdebug softlockup_panic=1 hung_task_panic=1 nmi_watchdog=panic`. **Keep the DEBUG idea** (initdebug + hang→panic) in the mainline bootimg script. |
| `extract-dtb.py` (27) | **A** | Generic "find the first sane FDT in a blob". Useful for pulling the factory DTB from redfin's `vendor_boot.img`/`dtb.img` as a hardware reference (e.g. `qcom,msm-id`, `qcom,board-id`). The walleye rationale in its docstring is specific. |
| `build-kernel.sh` (88) | **D** | 4.4 wahoo build (clang 11, `wahoo_defconfig`, `CC_WERROR` off, `Image.lz4-dtb`). If a downstream fallback kernel is ever wanted (**[verify P5]**: redbull 4.19), the idempotent patch apply/revert (:26-39) and the "fragment option not applied" check (:66-76) are the parts worth copying. |
| `build-android-stubs.sh` (15) | **D** | `libperipheral_client.so` stub for 4.4 cnss-daemon. |
| `build-screen.sh` (19) | **A/D** | Takes the font from `external/kernel-msm/lib/fonts/font_8x16.c` (:16). On mainline pixel2-screen uses fbcon and draws nothing itself (see tools). |
| `build-mainline-fw.sh` (46) | **A** | ath10k WCN3990: `firmware-5.bin` from linux-firmware (URL + SHA-256 :11-12, path `WCN3990/hw1.0`); `board-2.bin` encoded from walleye's `vendor.img:/firmware/bdwlan.{bin,b09,b80}` with board ids ff/9/80 (:33-43). **[verify P5]** wifi chip / driver (ath10k snoc WCN399x vs other), board-data file names and QMI board_id. It reads `vendor.img` with `simg2img` + `debugfs`; with dynamic partitions this needs `lpunpack` on `super.img` first **[verify P5]**. |
| `build-rootfs.sh` (125) | **A** | Hardcoded or walleye:<br>• `KREL=4.4.223-walleye-ubuntu` and the hard requirement on 4.4 modules (:23-29);<br>• stubs/qbootctl/screen installs (:63-70);<br>• hostname `pixel2` (:55-56); project key `pixel2_ed25519` (:34);<br>• ath10k `WCN3990/hw1.0` paths (:79-81);<br>• `/boot/boot-mainline.img`;<br>• camera tuning imx179/imx362 (:89-93);<br>• `/etc/pixel2-build` stamp (:118);<br>• `mkfs.ext4 -O ^metadata_csum_seed` "limited to what kernel 4.4 supports" (:122). Mainline-only can drop that flag. **Keep** `-E lazy_itable_init=0,lazy_journal_init=0` (growfs lesson).<br>Generic parts: `docker build` → `docker export` → unpack as root in the container → `mkfs.ext4 -d` → `img2simg` (no loop devices, no `--privileged`); SSH keys (all `~/.ssh/*.pub` + project key); NM wifi profile from `build/wifi.{ssid,pass}` written with umask 077 and never echoed. |
| `build-libcamera.sh` (44) | **A (later)** | libcamera 0.7.2 + Porthole msm8998 patches (`temp/libcamera/APKBUILD`). Defer until a camera phase. |
| `get-firmware.sh` (48) | **A** | `BUILD=walleye-rp1a.201005.004.a1`, the URL, SHA-256 `0c23f6cf…` (:19-22); extracts `boot.img vbmeta.img vendor.img` from the inner `image-*.zip` (:47). Redfin needs its final factory build and hash, and probably `boot.img vendor_boot.img vbmeta.img dtbo.img super.img` (or `vendor.img` from it) **[verify P5]**. Pattern kept: download with resume (`curl -C -`), check SHA-256 (Google embeds the first 8 hex digits in the file name), unpack, keep `flash-all.sh` for restore. |
| `flash.sh` (183) | **A** | Walleye-specific:<br>• `BUILD`, `WANT_BOOTLOADER=mw8998-003.0085.00`, `WANT_BASEBAND=g8998-…` (:18-20);<br>• `product = walleye` check (:60);<br>• dual-kernel scheme: mainline on the active slot, 4.4 on the other, `KERNEL=4.4` (:97-150);<br>• `vbmeta_a/b` flashed with `--disable-verity --disable-verification` (:147-148). Redfin may also need `vbmeta_system` **[verify P5]**;<br>• no `vendor_boot`/`dtbo` handling;<br>• "bootloader goes quiet after the userdata write, pick START" (:155-159);<br>• SSH wait on 172.16.42.1 / `pixel2.local` with macOS `nc -G` (:167);<br>• asks about the LED pulse and the screen (:179-180).<br>Generic: `wait_fastboot`, the `getvar` parser, the unlock walkthrough, typing "yes", the `set_active` reset of the retry counter, the `restore` path via `flash-all.sh`. |
| `try-boot.sh` (71) | **R** | Reaches fastboot from Android (adb), Ubuntu (ssh), the initramfs (telnet) or serial, then runs `fastboot boot` and waits for 172.16.42.1. Exit 0 up, 1 Android came back, 2 timeout. 3x retry for flaky reboot-bootloader. macOS flags `ping -t1`, `nc -G` (:21,27). The serial glob depends on the gadget name. |
| `stage-mainline.sh` (48) | **A** | Dev helper for staging mainline on a phone running 4.4 Ubuntu. The pattern (tar over ssh, install modules + depmod, firmware, enable units) is useful; it removes leftover drop-ins by name (:29). |

### 1.5 initramfs/

| File | Class | Notes |
|---|---|---|
| `init` (124) | **A (small)** | Mostly generic:<br>• mounts proc/sys/devtmpfs/devpts/configfs;<br>• builds an NCM+ACM gadget (VID 0x18d1, PID 0xd001);<br>• runs a getty loop on ttyGS0;<br>• `initdebug` debug shell: 172.16.42.1, udhcpd, telnetd, pstore mount, auto `reboot-bootloader` after 600 s unless `/tmp/keep` (`initdebug_timeout=`);<br>• finds root by **`PARTNAME=userdata`** in uevent (no `/dev/sda45` hardcode, which is good);<br>• kills the getty loop before `switch_root` (fork-storm lesson).<br>Walleye-specific: product string "Pixel 2 (Ubuntu)", serial "pixel2-ubuntu" (:38-39), and the "do NOT write ncm dev_addr" warning (:32-34), which is a **4.4 f_ncm bug**. On mainline, fixed `dev_addr/host_addr` *may* be safe and could fix the macOS "NCM no carrier" issue (untested). |
| `probe-init` (65) | **R** | Writes dmesg/udc/net/block/deferred snapshots to `userdata:/mainline-probe/` before and after the USB gadget comes up, then goes back to fastboot. For bring-up when USB never appears. It needs something on the phone that can read userdata afterwards (on walleye the 4.4 Ubuntu). |
| `probe-loop-init` (36) | **R** | Flight recorder: rewrites a synced dmesg every 0.5 s for 60 s. |
| `reboot-bootloader.c` (12) | **R** | `reboot(2)` RESTART2 "bootloader" (busybox can't pass an argument). |

### 1.6 kernel/

| File | Class | Notes |
|---|---|---|
| `patches/0001-initramfs-ignore-skip_initramfs.patch` | **D** | 4.4 only; mainline has no `skip_initramfs`. Check redfin's stock cmdline anyway (Android 10+ launch devices always use the ramdisk). |
| `walleye-ubuntu.config`, `walleye-ubuntu-vt.config`, `debug-minimal.config` | **D** | 4.4 fragments. Their **systemd checklist** (DEVTMPFS(_MOUNT), FHANDLE, AUTOFS, TMPFS_POSIX_ACL/XATTR, cgroups, namespaces, `# ANDROID_PARANOID_NETWORK is not set`, SELINUX_BOOTPARAM, USB_CONFIGFS_NCM/ECM/ACM, `# MODVERSIONS is not set`) is the reference list if a downstream kernel is ever tried. |
| `debug/irqdbg.patch` | **D** | mdss_dsi debug for 4.4. |
| `mainline/ubuntu.config` (33) | **A** | Generic and keepable:<br>• `LOCALVERSION` (rename), `# LOCALVERSION_AUTO is not set`;<br>• AUTOFS, CGROUP_BPF, DEVTMPFS, FHANDLE;<br>• PSTORE/PSTORE_RAM/PSTORE_CONSOLE;<br>• DEBUG_INFO_NONE (faster build, no pahole);<br>• FONTS + FONT_TER16x32;<br>• Docker: NFT_COMPAT, NFT_FIB_INET/IPV4/IPV6.<br>Drop: `DRM_PANEL_SAMSUNG_S6E3FA5`, `RMI4_F11`, `REGULATOR_BCM15602_EASEL`, `EASEL_MIPI`.<br>Also make sure USB_CONFIGFS_NCM/ACM are on in whatever base config is used. |
| `mainline/msm8998-google-walleye-ubuntu.dts` (756) | **D** (method R) | Method worth copying:<br>• an "-ubuntu" DTS that `#include`s the upstream/Porthole device DTS;<br>• everything disabled except what a headless boot needs, then **re-enabled one block at a time**;<br>• extra `reserved-memory` copied from the stock DTB + dtbo (easel, splash, HTC regions);<br>• ramoops moved to the stock region so either kernel can read the other's crash;<br>• `qcom,msm-id` forced to the factory DTB's value. |
| `mainline/wahoo-dtbo-sink.dtsi` (300) | **D** (technique **A**) | Walleye's bootloader always applies dtbo idx 3 to the kernel DTB and hangs, then later fails with "Load Error", when the overlay's `__fixups__` labels don't resolve. Fix: a hand-written `__symbols__` pointing all 137 labels at empty dummy nodes under `/wahoo-dtbo-sink`, each with a phandle via a `sink-refs` property. **Very likely relevant to redfin** if its bootloader also applies a dtbo overlay to whatever DTB we supply **[verify P5]**. Generate the sink with a script from `fdtdump`/`fdtoverlay` of the stock dtbo entry instead of by hand, and check offline with `fdtoverlay` before any boot. |
| `mainline/walleye-audio.dtsi` (250) | **D** | WCD9340 + TAS2557. |
| `mainline/patches/0001-qcom_smbx-charge-behaviour.patch` | **D** (idea A) | Adds `charge_behaviour` (inhibit-charge) to the PMI8998 SMB2 driver. Redfin's charger (**[verify P5]**: PM7250B, which mainline driver?) may need the same feature for the charge limit. |
| `mainline/patches/0002-drm-panel-samsung-s6e3fa5.patch` | **D** | Walleye panel driver, written from the vendor DT. Same method applies to redfin's panel. |
| `mainline/patches/0003-iommu-arm-smmu-qcom-identity-…msm8998-mdss.patch` | **D** (lesson R) | Continuous-splash + SMMU reset (see §3). Check whether `qcom,sm7250-mdss` is already in the `arm-smmu-qcom.c` identity list. |
| `mainline/patches/0004-imx362-ois-switched-rails.patch` | **D** | Camera. |

### 1.7 rootfs/

`rootfs/Dockerfile` (54), **A**:
- **Packages** (generic, keep): systemd, udev, dbus, ssh, sudo, NetworkManager, wpasupplicant, iw, wireless-regdb, avahi + libnss-mdns, unattended-upgrades, `rmtfs tqftpserv qrtr-tools`, alsa-utils, Mesa. libcamera runtime deps only if a camera phase happens.
- **Enable list** (:31-47): the android-*, cnss-daemon, modem and wifi-mac-record units are 4.4 and get dropped; the pixel2-* units need renaming.
- **Generic setup**: `systemctl mask getty@tty1` (only because there is no keyboard and pixel2-screen owns tty1); `rm ssh_host_*`; empty machine-id; `passwd -l ubuntu`.

Overlay, `/etc`:

| File | Class | Notes |
|---|---|---|
| `NetworkManager/conf.d/10-pixel2.conf` | R | Leaves rmnet/dummy/bond/sit/ip6/vti unmanaged. |
| `NetworkManager/conf.d/pixel2-wifi.conf` | R | No random MAC while scanning. |
| `NetworkManager/dispatcher.d/50-timesync` | R | Kicks timesyncd on wlan0/usb0 up and connectivity-change; `reset-failed` first (test 53, start-limit). |
| `NetworkManager/system-connections/usb0.nmconnection` | R | `method=shared`, 172.16.42.1/24; the Mac gets DHCP. Mode 600. |
| `android/props.conf` | D | |
| `fstab` | R | `/dev/disk/by-partlabel/userdata / ext4 defaults,noatime,x-systemd.growfs`. Generic **if** redfin's userdata partlabel is `userdata` (standard). |
| `modprobe.d/pixel2-ath.conf` | A | `ath regd_override=0x67`. Needed because walleye's board data has no country (strict-reg path re-enabled ch 169/173 and crashed the WLAN firmware). This may well apply to redfin's ath10k too; it depends on a **Porthole patch** in `regd.c`, so check that the sm7250 kernel tree has it **[verify P5]**. |
| `modules-load.d/pixel2.conf` | D | 4.4 module names. |
| `ssh/sshd_config.d/10-pixel2.conf` | R | Keys only; no root login. |
| `sudoers.d/ubuntu` | R | NOPASSWD + `verifypw=any` (Homebrew `sudo -v` lesson). |
| `systemd/logind.conf.d/10-pixel2-powerkey.conf` | R | `HandlePowerKey=ignore`, `HandlePowerKeyLongPress=poweroff` (test 54). |
| `systemd/system/android-daemon@.service`, `android-env.service`, `android-logd.service`, `cnss-daemon.service`, `modem.service` + their `kernel-4.4-only.conf` drop-ins | D | Vendor-daemon route for 4.4 only. |
| `systemd/system/diag-router.service` | R | `Before=rmtfs`. Remove `ConditionKernelVersion=>=5` if single-kernel. |
| `systemd/system/pixel2-audio.service` | D | |
| `systemd/system/pixel2-boot-successful.service` | R | `qbootctl -m` after ssh + NM. |
| `systemd/system/pixel2-camera-tuning.service` | D | |
| `systemd/system/pixel2-charge-limit.service` | R | HIGH=80 LOW=70, `ExecStopPost=… resume`, `Restart=always`. |
| `systemd/system/pixel2-modem-fw.service` | A | `Requires=vendor.service`, `After=android-env` (drop that), `Before=rmtfs tqftpserv`. |
| `systemd/system/pixel2-screen.service` | A | |
| `systemd/system/pixel2-status-led.service` | A/D | **[verify P5]**: the Pixel 5 likely has **no notification LED**. Pick another "alive" signal (e.g. a brief vibration at boot) or drop it. |
| `systemd/system/pixel2-wifi-mac-record.service` | D | 4.4 only. |
| `systemd/system/pixel2-wifi-mac.service` | A | `hold` (keeps NM off wlan0) + set MAC; `Before=NetworkManager`. |
| `systemd/system/qrtr-ns.service.d/never.conf` | R | Mainline has the in-kernel QRTR nameserver (≥5.7). Disables Ubuntu's userspace one through an impossible ConditionPathExists, so `rmtfs` (`Requires=qrtr-ns`) still starts. |
| `systemd/system/rmtfs.service.d/mainline-only.conf` | A | Keep `Wants/After=tqftpserv diag-router`; drop the kernel condition. |
| `systemd/system/serial-getty@ttyGS0.service.d/autologin.conf` | R | |
| `systemd/system/ssh.service.d/hostkeys.conf` | R | Resets ExecStartPre so `ssh-keygen -A` runs before `sshd -t`. |
| `systemd/system/systemd-backlight@.service.d/pixel2.conf` | A | No-op because the panel is off at boot (EINVAL left the system degraded). Probably needed again for any OLED that is kept off. |
| `systemd/system/tqftpserv.service.d/mainline-only.conf` | A | Creates an empty `/tmp/tqftpserv/ota_firewall/ruleset`; drop the kernel condition. |
| `systemd/system/usb-gadget.service` | R | `DefaultDependencies=no`, `Before=network-pre`, `WantedBy=sysinit`. |
| `systemd/system/vendor.service` | A | See `mount-vendor.sh`. |
| `udev/rules.d/70-pixel2-camera.rules` | R (later) | dma_heap/udmabuf → group video. |
| `udev/rules.d/86-pixel2-usb-gadget-nm.rules` | R | Overrides NM's `85-nm-unmanaged.rules` for DEVTYPE=gadget. |

Overlay, `/usr/local`:

| File | Class | Walleye assumptions |
|---|---|---|
| `sbin/usb-gadget.sh` (27) | A | Strings "Pixel 2 (Ubuntu)" / "pixel2-ubuntu"; 4.4 dev_addr warning. Otherwise idempotent and generic. |
| `sbin/mount-vendor.sh` (12) | **A (high risk)** | Mounts `/dev/disk/by-partlabel/vendor$suffix` (:8), slot suffix from `androidboot.slot_suffix`. On redfin `vendor` is most likely a **logical partition inside `super`** **[verify P5]**: needs a dm-linear mapping from the LP metadata (e.g. `parse-android-dynparts` / `dmsetup`, or `lpunpack` offsets) before mounting. |
| `sbin/pixel2-modem-fw` (55) | **A** | The logic is the key reusable idea (see §3): build firmware at boot from the phone's own partitions, idempotent via a sha256 stamp of the sources, pil-squasher for `.mdt`→`.mbn`. Hardcoded:<br>• target dir `/lib/firmware/qcom/msm8998/wahoo` (must match the DTS `firmware-name`);<br>• modem partition `modem$suffix` as vfat with `/image/modem.mdt`, `mba.mbn` (**sm7250 has no MBA** **[verify P5]**), `modemr.jsn`;<br>• vendor files `modemuw.jsn`, `wlanmdsp.mbn`, `ipa_fws.mdt`;<br>• GPU `a540_zap.mdt`, `a530_pm4/pfp`, `a540_gpmu.fw2` (redfin: Adreno 620 → a615/a620 zap + `a630_sqe`/`a650_gmu`-family **[verify P5]**);<br>• `adsp.mdt`, TAS2557 bins;<br>• the stamp check list (:39-40). |
| `sbin/pixel2-wifi-mac` (63) | A | Drop the `record` mode (it needs 4.4). Keep the "generate one locally administered MAC, persist it in `/var/lib/…/wlan0.mac`, set it before NM" path. Better if a real MAC is found: **[verify P5]** wlan MAC in `persist` / `bdaddr`-like files / DT `local-mac-address` from the bootloader. |
| `sbin/pixel2-charge-limit` (42) | R (mainline branch) | Finds a `type=Battery` supply and a `charge_behaviour` attribute generically (:21-29). Works on any mainline charger that exposes `charge_behaviour`; the 4.4 `charge_disable` branch goes. |
| `sbin/pixel2-status-led` (86) | A/D | The mainline branch drives `rgb:status` with a `hw_pattern` pulse (generic LPG). Redfin likely has no LED. |
| `sbin/pixel2-audio` (23) | D | |
| `sbin/pixel2-camera-tuning` (119) | D | |
| `sbin/android-env`, `android-props`, `android-logd`, `lib/pixel2/apex-payload-offset.pl` | D | 4.4 vendor-daemon route. Clever, but not needed with mainline QRTR. |
| `bin/pixel2-console` (33) | A (small) | Status header + journal for the screen console. Battery path `/sys/class/power_supply/battery` (:13) is the 4.4 name; on mainline find the `type=Battery` supply. Filters walleye's `[BATT]` kernel lines. |
| `bin/pixel2-camera` (88) | D | DT paths `/base/soc@0/cci@ca0c000/...` (:19-20), imx sensors. |

### 1.8 tools/, android/, camera/

| File | Class | Notes |
|---|---|---|
| `tools/pixel2-screen.c` (754) | A | Two modes. The 4.4 mdss_fb mode (its own VT100 emulator drawing into an mmapped fb0) gets dropped. The mainline mode (`fb0_is_drm()` → fbcon on tty1, panel on/off via `/sys/class/graphics/fb0/blank` 0/4, wake on input) is about 150 lines and is what to keep. Hardcoded input names: `synaptics_dsxv26`, `gpio-keys`, `Synaptics S3708AR`, `pm8941_pwrkey`, `qpnp_pon` (:67-68). Grid 67x60. A rewrite of just the mainline mode is probably simpler. |
| `tools/fbtest.c` (67) | R | Colour bars via mmap + FBIOPAN. |
| `tools/mod-bisect.sh` (27) | R | Loads modules one by one from the initramfs, logging and syncing before each; the last line names the module that hung. |
| `tools/chromatix-awb-points.py` (39) | D (later) | Qualcomm chromatix AWB extraction. |
| `android/stubs/peripheral_client.c` | D | |
| `camera/tuning/imx179.yaml` | D | |

### 1.9 Untracked clutter in the Pixel 2 tree

`README.md~` and 24 `sed??????` files in the repo root are temp files left by `merge_config.sh` running in `/work` (build-kernel.sh). build-mainline.sh avoids them with `cd "$OUT"` (:99). In the new repo, always run `merge_config.sh` from the output directory.

### 1.10 Submodules (`.gitmodules`)

| Submodule | Class | Notes |
|---|---|---|
| `external/mkbootimg` (AOSP) | R | `mkbootimg.py` / `unpack_bootimg.py`; it handles header v3/v4 and `vendor_boot` (`--vendor_boot`, `--vendor_ramdisk`, `--dtb`). |
| `external/qbootctl` | R | |
| `external/pil-squasher` | R | |
| `external/qcom-diag` | R | diag-router. |
| `external/qca-swiss-army-knife` | R if ath10k | `ath10k-bdencoder`. |
| `external/linux-mainline` | A | Shallow, `ignore = dirty`. The pin depends on the sm7250 base tree **[verify P5]**. |
| `external/libcamera` | R (later) | |
| `external/kernel-msm` (android-msm-wahoo-4.4) | D | Replace with redfin's downstream kernel + DT repo as the **hardware reference** (status ok/disabled, regulators, GPIOs). Shallow, `ignore=dirty`. **[verify P5]**: branch/repo names. |
| `external/porthole-pmaports` (taimen-bringup) | D | Replace with whatever sm7250/redfin mainline effort exists **[verify P5]**. |

---

## 2. Process and conventions to carry over

### 2.1 CLAUDE.md rules (copy nearly verbatim)

- **Where things are:**
  - `PLAN.md` is the checklist, starting at **▶ RESUME HERE**; tick the box, then move the pointer.
  - `docs/log.md` holds dated notes. Every phone test gets a running number (`Test 50: …`) recording what was run, what was measured and what it means.
  - Subsystem docs live in `docs/`.
- **Commits:**
  - Commit after every change: each file, each ticked box, each log entry.
  - Subject `P8.6: what changed`, or `plan: …`, `log: test N, …`, `plan/log: …`, `rootfs: …`, `build: …`, `build-all: …` (by count: plan 35, P8.5 16, log 14, rootfs 12, P8.3.6 12). The body says **why**, often with measurements.
  - Footer: `Co-Authored-By: Claude …` only; never session references or URLs.
  - Don't push unless asked.
- **Licensing:**
  - New files get an `SPDX-License-Identifier` header: MIT for original work, GPL-2.0-only for kernel patches and DTs, upstream terms for borrowed code (credit it).
  - Check with `reuse lint` (pip `reuse[charset-normalizer]` in a python container).
- **Third-party code:** pinned submodules under `external/` only. Never an ad-hoc clone, never `git clone` in a Dockerfile.
- **Never commit or print:**
  - **The phone serial.** It appears in `fastboot devices`, `/dev/cu.usbmodem*` names and `androidboot.serialno` in `/proc/cmdline`. Grep single keys from cmdline; probe logs that contain the cmdline stay in `build/`.
  - Firmware or images: `firmware/` and `build/` are gitignored, and vendor blobs never leave the phone.
  - Wifi credentials (`build/wifi.ssid/.pass`, mode 600) and the wifi MAC.
- **Phone safety:**
  - **Never boot stock Android.** It formats userdata because it finds a foreign ext4 there (fstab `formattable`). This happened 3 times.
  - Confirm with the owner before any `fastboot flash`.
  - Test kernels tethered first with `scripts/try-boot.sh <img> 150` (`fastboot boot`, nothing flashed); flash only after a clean tethered boot. Document the way back.
  - `reboot bootloader` from Ubuntu is occasionally flaky; tooling retries 3x.
  - OLED burn-in: never leave a static image lit; blank after every screen test.
  - Don't scan an I2C/CCI bus whose devices are unpowered.
- **Talking to the phone:**
  - `ssh.sh` over USB 172.16.42.1 or wifi.
  - Pipe files in with `cat f | ssh.sh 'sudo install -m755 /dev/stdin /path'`.
  - Pre-journald kernel lines exist only in that boot's `dmesg`. Never `dmesg -C`.
  - Python that reads anything copied off the phone runs as `python3 -I`.
- **Building:**
  - `build-all.sh` rebuilds only steps whose input hash changed. **When a step gains a new input directory, add it to that step's `hash_of` list.**
  - Check a built rootfs without flashing: `debugfs` on `build/rootfs.img` in the build container.
  - The clone must be on a case-sensitive volume.
  - The Mac uses zsh/BSD tools: `sed -i ''`, `-E` instead of `\|`, quoted globs, no ffmpeg.
- **How to work:**
  - Carry on until the owner is really needed; owner actions should be small and concrete.
  - Hardware questions: read the downstream vendor DT first. `status = "ok"` vs `"disabled"` decides which part is fitted. Then check the closest mainline sibling's work.
  - DT changes need a reboot; firmware and packages can be staged on the running phone first.
  - **Measure before claiming; compare within one boot** (A/B power on USB input current; single readings swing ±30 mA). Unproven causes are logged as unproven.
  - When something can't be reproduced on demand, **make tooling tolerate it (retry) and log the pattern** instead of guessing a fix.
  - **One change per test image** (`boot-gpu.img`, then `boot-audio.img`).

### 2.2 PLAN.md format

- A one-line **Goal**, then `## ▶ RESUME HERE: <next step / what we're waiting on>`.
- "How to use this file":
  1. Do the RESUME step.
  2. Tick it and move the pointer.
  3. Commit right away (`plan: tick P1.4`).
  4. Log decisions and failures with a date in `docs/log.md`.
  5. A **Gate** must pass before moving on; if it fails, stop and log it.
- A "get back to stock Android anytime" line at the top.
- Phases with time estimates and ⚠️ markers for wiping steps. Steps `- [ ] **Pn.m** …` with sub-bullets and `- Gate: …`.
- When a step is done, prepend an italic result: `_Done 2026-11-17: …_`.
- Milestones marked 🎉 in the gates.
- Phase sequence worth copying:
  - P0 repo setup;
  - P1 phone prep (record getvar, unlock, factory image, extract images, **prove `fastboot boot` of the stock boot.img works**);
  - P2 build environment;
  - P3 kernel;
  - P4 initramfs + rootfs + bootimg;
  - P5 first tethered boot (with a bisect step);
  - P6 wifi;
  - P7 make it permanent (vbmeta off, flash boot, slot marking, cold power-on gate, 5-reboot gate);
  - P8 optional subsystems, each with its own gate;
  - P9 one-command build + guided flash (gate: **someone else** flashes using only README + flash.sh);
  - P10 licensing.
- For Pixel 5, **flash boot as early as practical** (P7). On walleye, any failed tethered boot fell back to Android, which wiped userdata.

### 2.3 Test discipline seen in log.md

- Debug images turn hangs into panics: `softlockup_panic=1 hung_task_panic=1 nmi_watchdog=panic`, `PANIC_TIMEOUT=1` / `panic=10`. The initramfs returns to fastboot after 10 min, so unattended runs never wedge the phone.
- Images are named per experiment (`boot-min-debug.img`, `boot-B-debug.img`, …) and pre-built before the owner is needed.
- The panel is watched with a USB webcam on the Mac (`imagesnap`). Input is faked by writing evdev events to `/dev/input/eventN`.
- Before touching modem/EFS, back up `modemst1/2`, `fsg`, `fsc`, `persist`, `ssd` and the GPT head/tail of every LUN to `firmware/backup/` (gitignored).

---

## 3. Hard-won lessons from log.md likely to generalize to another Qualcomm Pixel

Boot chain and bootloader:
1. **Prove `fastboot boot` first** (P1.8). It is how every kernel gets tested without flashing.
2. **Android wipes userdata** if it ever boots with our ext4 there; this happened 3 times. Until our boot image is flashed, every failed tethered boot can fall back to Android. The P6.R recovery recipe:
   - check the ext4 label at offset 0x478 from the initramfs (`ubuntu` = intact);
   - reflash `rootfs.simg`.

   After the flash, a crash reboots into our kernel and pstore survives.
3. **The bootloader goes quiet on USB after `fastboot flash userdata`** (`usb_read failed`); the write finishes asynchronously, then pick START on the phone. A `fastboot boot` also sometimes took ~5 min to start the kernel. Timeouts must allow for both.
4. **A/B slot marking:** without marking the slot successful, the retry counter runs down (`slot-retry-count` 0, then "slot unbootable: load error"). Fix: static `qbootctl -m` from a unit after ssh/NM; `fastboot set_active <slot>` resets the counter when flashing.
5. **vbmeta** is flashed to both slots with `--disable-verity --disable-verification` (orange state). Redfin may need `vbmeta_system` too **[verify P5]**.
6. **dtbo overlay:** the bootloader always applies the stock dtbo entry to the kernel DTB. With a mainline DTB (no `__symbols__`) it hung for 6.5 min and then refused even known-good images ("Load Error") until `fastboot reboot-bootloader`. Fixes:
   - a sink DTSI with dummy label targets that have phandles, checked offline with `fdtoverlay`;
   - the factory `qcom,msm-id`;
   - `/chosen` without `bootargs`.

   Read `androidboot.dtbo_idx` from `/proc/cmdline` and parse `dtbo.img` entries first (P8.3.1).
7. **`earlycon=` (copied from the sibling device's cmdline) reset the phone.** Don't copy earlycon blindly.
8. **Reset-before-USB debugging ladder:**
   - `rdinit=/bin/reboot-bootloader` (does the kernel reach userspace?);
   - `probe-init` (dmesg to userdata, then fastboot);
   - `probe-loop-init` (0.5 s flight recorder);
   - initdebug shell;
   - `mod-bisect.sh`;
   - DT bisect by enabling one node at a time.

   The **bootloader wipes RAM logs** (ramoops was empty even after clean reboots), so file-based probes beat pstore.
9. **Continuous splash vs SMMU:** enabling MDSS reset the SoC ~0.6 s into boot, because `mmss_smmu` put MDSS into a translated domain while the bootloader's MDP was still fetching the splash. Fix: add the MDSS compatible to the arm-smmu-qcom identity (bypass) list. Expect this on any Qualcomm phone with continuous splash. Also `clk_ignore_unused pd_ignore_unused` on the cmdline.
10. **Reserved memory:** compare the stock DTB+dtbo reserved regions with the mainline map and mark stock-only regions `no-map` (not the root cause on walleye, but cheap insurance).
11. **`reboot bootloader` flakiness:** on mainline every reset was cold (PS_HOLD, IMEM/PON lost); 3 failures in about 16 tries, then 0 of 10 in controlled trials. The answer was tolerance (3x retry), not a fix. `systemctl reboot --reboot-argument=bootloader` plus `reboot=w`.
12. **Power-off with USB attached** starts charger mode (`androidboot.mode=charger`), which boots our image again: a "spontaneous reboot" that is really an orderly power-off. Combined with logind's default `HandlePowerKey=poweroff`, a short power press looked like a crash (test 54). Fix: `HandlePowerKey=ignore`, long press = poweroff.

Kernel and console:

13. **VT/fbcon broke the downstream kernel** (VT alone reset it). On 4.4, fbcon drew through NULL because mdss_fb allocates fb memory only on mmap. On mainline DRM, fbcon works (TER16x32 font). For a headless port, keep the screen off by default and wake it only on touch or a button.
14. **Regulator voltage matters:** the touch rail at 3.3 V hard-hung walleye with no watchdog. The fix was the upstream dtsi default (3.008 V). Take regulator values from the vendor DT, and bisect hangs with the probe initramfs.
15. **MODVERSIONS/KASLR** (4.4 only) and **lazy itable init**: `mkfs.ext4 -E lazy_itable_init=0,lazy_journal_init=0`, otherwise `x-systemd.growfs` fails ("Inode table for bg 0 marked as needing zeroing").
16. **Initramfs getty loop** must be killed before `switch_root`, or it fork-storms (PIDs at 1.9 M).

Modem, wifi and firmware (mainline):

17. **Wifi on a Qualcomm SoC needs the modem (MSS) up.** Userspace chain:
    - `rmtfs -r -P -s` (`-s` starts MSS once it serves);
    - `tqftpserv` (modem pulls config files; serve an empty `ota_firewall/ruleset`);
    - `diag-router` (without it the modem's diag task starves and its watchdog kills the WLAN PD every ~19 s; found by Porthole on taimen);
    - in-kernel QRTR ns (disable Ubuntu's `qrtr-ns`; keep rmtfs's `Requires=` satisfied);
    - `pd-mapper` is in-kernel on mainline. Ordering: tqftpserv and diag-router **before** rmtfs.
18. **Firmware squashing:** mainline remoteproc wants single `.mbn` files. `pil-squasher out.mbn in.mdt` merges `.mdt`+`.bNN` split images (modem, ipa_fws, GPU zap, adsp).
19. **Build firmware at boot from the phone's own partitions** (`pixel2-modem-fw`):
    - mount the modem partition (vfat, `shortname=lower`) and vendor read-only;
    - squash and copy into `/lib/firmware/qcom/<soc>/<device>/` to match the DTS `firmware-name`;
    - stamp with a hash of the sources and skip if unchanged.

    Blobs never enter git or `build/` (except board data from the factory image). Licensing-clean and per-phone correct.
20. **ath10k board data:** encode `bdwlan.*` from vendor into `board-2.bin` with `ath10k-bdencoder`, keyed by `bus=snoc,qmi-board-id=XX`; `firmware-5.bin` comes from linux-firmware with a pinned SHA-256.
21. **ath regulatory:** board data without a country gives the US strict-reg path, which re-enables DT-disabled channels (169/173) and crashes the WLAN firmware (`halphy_caldb` assert). Fix: `options ath regd_override=0x67` (needs Porthole's regd.c patch).
22. **ath10k_snoc can't be reloaded** without restarting the modem ("msa map permissions -22"); reboot instead.
23. **Stable wifi MAC:** mainline ath10k gets no MAC from the WCN399x firmware (QMI DMS says NotProvisioned), so wlan0 is random each boot. Generate one locally administered MAC once, persist it on the phone, apply it before NetworkManager (NM held off wlan0 via a runtime `unmanaged-devices` conf, then `nmcli general reload conf` + rescan), and disable scan MAC randomisation.
24. **Wrong wifi password vs driver bug:** verify the PSK offline against the AP's PMKID (HMAC-SHA1 of PBKDF2) before blaming the driver. The first "failure" was a missing newline in `.env`.
25. **Occasional boot-time modem crash** (dog_hb, recovered) is a known pattern. Log it, don't chase it per test.

Userspace and Ubuntu integration:

26. NM ignores gadget interfaces (`85-nm-unmanaged.rules`): override with an `NM_UNMANAGED=0` rule.
27. NM rejects nmconnection files that are not 0600.
28. Ubuntu's `ssh.service` runs `sshd -t` before keys exist; reset ExecStartPre.
29. The clock starts a month behind (systemd build-time floor, no RTC sync). Kick timesyncd from an NM dispatcher hook, but only for real uplinks, and `reset-failed` first (Docker interfaces caused a start-limit hit).
30. `systemd-backlight` fails on a panel that is off at boot; no-op it.
31. **Docker needs `NFT_COMPAT` + `NFT_FIB_*`** (Ubuntu's iptables-nft).
32. A charge limit via `charge_behaviour=inhibit-charge` (USB keeps powering the phone) needed a kernel patch on PMI8998.
33. **OLED burn-in:** kill the bootloader splash at boot. On 4.4 that meant open fb0, one black frame, close; plain blank ioctls broke later power-ups. On mainline, `fb0/blank` 4. Wake on touch, power key or volume; off after 300 s.

Host and build:

34. **Case-sensitive volume** is required (the kernel tree has case-colliding files). Docker must be able to see it: Colima only shares `$HOME` by default, and `-v` quietly mounts an empty dir; check-prereqs tests for this.
35. **`git submodule update --init --depth 1 -b` fetched only master**: clone the branch with `--single-branch`, then `git submodule add`. Interrupted shallow clones leave `.git`-only submodules; `--force` fixes them.
36. `grep -q` under `pipefail` + SIGPIPE makes "is a submodule missing?" false exactly when one is missing; let grep read everything. An unmatched `~/.ssh/*.pub` glob under pipefail silently killed a build.
37. BSD vs GNU: `cp -c` (APFS clone) vs `--reflink=auto`; `nc -G`, `ping -t`.
38. **ccache** per kernel (5 GB each): mainline went from 73 min cold to 10 min warm on 4 x86 cores. A full on-phone build took 2 h 20 min, with kernels at 93 %.
39. On x86 hosts, kernels cross-compile in an amd64 image (`DEV_CROSS=1`, run as the host user). Everything else runs in arm64 images through qemu binfmt (`tonistiigi/binfmt` pinned by digest), re-registered every run.
40. A **macOS "NCM no carrier"** issue (Mac sees the gadget, no traffic) came and went and stayed unexplained (possibly boot delay). ACM serial and wifi always worked as fallbacks, so keep both gadget functions.

---

## 4. Build pipeline skeleton (`scripts/build-all.sh`)

Five phases, printed as `== N/5 …`:

1. **Prerequisites:**
   - `scripts/check-prereqs.sh --build` reports every gap at once (FAIL vs warn), with the fix command for each (brew/apt; Colima, Docker Desktop and OrbStack hints).
   - On a non-arm64 Docker host, register qemu binfmt (pinned image digest) if arm64 containers don't run.
   - `mkdir -p build/.stamps`.
2. **Sources and firmware:**
   - `SUBS=(…)`, only what this build uses;
   - `git submodule update --init` when any shows `-`;
   - warn for `+` (not at the committed version);
   - `scripts/get-firmware.sh` (idempotent).
3. **Wifi:** ask once in a TTY; store `build/wifi.ssid` / `wifi.pass` with umask 077. An empty ssid file means "no wifi, don't ask again".
4. **Build container:** `docker build -q --platform linux/arm64 -t <img> docker/`.
5. **Steps**, each a `step <name> <output> <hash> <cmd…>`:
   - Skip if `FORCE != 1`, the output exists and `build/.stamps/<name>` equals the hash.
   - Otherwise remove the stamp, run with the log in `build/<name>.log`, and on failure show `tail -30` and die.
   - Check that the output exists, write the stamp, print the duration.

`hash_of <paths|@text>…` takes one SHA-256 over every file under the paths (missing paths skipped, `*~` and `.DS_Store` ignored, `LC_ALL=C` sorted, `find -print0 | xargs -0 shasum -a 256`) plus literal `@text` values. Conventions:

- `H_DOCKER = hash_of docker scripts/dev.sh` goes into every step.
- Big trees are represented by their **submodule commit** (`@$(git -C external/X rev-parse HEAD)`); they are too big to scan, and fresh clones change mtimes.
- **Upstream step hashes are chained as `@$H_…`** into downstream steps:

| Step | Hash inputs |
|---|---|
| kernel | fragment + patches + script + K_HEAD + H_DOCKER |
| bootimg | firmware/boot.img + scripts + mkbootimg HEAD + H_KERNEL + H_INITRAMFS |
| rootfs | rootfs/ + script + camera/tuning + wifi files + project pubkey + `@$(cat ~/.ssh/*.pub)` + every upstream hash |

- Optional branches fold into one `@…` (`H_ML="@$H_MTOOLS $H_MFW …"` or `@no-mainline`).

Walleye's step graph:

```
docker ─┬─ kernel(4.4) ─┬─ bootimg (factory DTB) ─────────────┐
        ├─ initramfs ───┤                                     │
        ├─ android-stubs                                      │
        ├─ qbootctl                                           ├─ rootfs → rootfs.img + rootfs.simg
        ├─ screen (font from kernel-msm)                      │
        └─ [MAINLINE] modem-tools, mainline-fw(vendor.img),   │
             mainline (kernel/mainline + linux + porthole),   │
             mainline-bootimg (+initramfs), libcamera ────────┘
```

Suggested Pixel 5 skeleton (mainline only):

```
docker ─┬─ mainline-kernel (kernel/mainline + linux HEAD + base-tree HEAD)
        ├─ initramfs
        ├─ qbootctl, modem-tools (pil-squasher, diag-router)
        ├─ fw (board data from factory image, linux-firmware pins)
        ├─ bootimg (+ vendor_boot? header v3/v4 [verify P5]) ← kernel + initramfs + firmware/*.img + mkbootimg HEAD
        ├─ screen (optional)
        └─ rootfs ← everything above + rootfs/ + wifi + ssh keys
```

Per-script patterns to keep:
- Each build script re-execs itself in the container: `[ -f /.dockerenv ] || exec scripts/dev.sh /work/scripts/<self> "$@"`, with host-side prep (submodule init, downloads, SHA checks) done before the exec.
- Fragment-applied check after `olddefconfig`.
- `INSTALL_MOD_STRIP=1 modules_install` into `build/…/modules-install`.
- The kernel tree is cloned into `build/` so the submodule stays pristine.
- The incremental own-patch list (`.ours`) avoids full recopies when a patch is appended.

---

## 5. Walleye-specific values index (grep list for the port)

- **Names:**
  - `walleye`, `wahoo`, `msm8998`, `muskie`, `taimen`, `pixel2`, `Pixel 2`;
  - `PIXEL2_HOST`, `pixel2_ed25519`, `pixel2-build`, `pixel2-mainline-build`, `pixel2-libcamera-build`, `pixel2-rootfs`;
  - hostname `pixel2` / `pixel2.local`, `/etc/pixel2-build`, `/var/lib/pixel2/`, `/usr/local/lib/pixel2/`, `__PIXEL2_DONE__`, `/dev/cu.usbmodempixel2*`.
- **Kernel release strings:** `4.4.223-walleye-ubuntu`, `-walleye-mainline`.
- **Boot image:**
  - header v0, page 4096, base 0, kernel 0x8000, ramdisk 0x1000000, tags 0x100, os 11.0.0 / 2020-10, 32 MiB;
  - `androidboot.dtbo_idx=3`, `qcom,msm-id = <0x124 0x20001>`, dtbo id 444 rev 3.
- **Partitions:**
  - by partlabel (good): `userdata`, `vendor$slot`, `modem$slot` (vfat), `system$slot`, `persist`;
  - by device number (only in docs/PLAN): `/dev/sda45` userdata, sda9/sda30 boot, sda20/sda41 vendor.
- **Firmware paths:** `qcom/msm8998/wahoo/`, `ath10k/WCN3990/hw1.0/`, `a530_*`, `a540_*`, `tas2557s_*`, `bdwlan.b80` (QMI board id 0x80).
- **Factory image:** `walleye-rp1a.201005.004.a1`, SHA `0c23f6cf…`, bootloader `mw8998-003.0085.00`, baseband `g8998-00034-2006052136`.
- **sysfs and devices:**
  - `pmi8998-charger`, `bms`, `rgb:status`;
  - PMIC regmap `0-00` / `spmi0-03`;
  - input names `synaptics_dsxv26`, `Synaptics S3708AR`, `pm8941_pwrkey`;
  - sound card `GooglePixel2`; CCI DT paths.

---

## 6. Generic vs device-specific: rough count

Classification of the 122 tracked files outside `external/` and `LICENSES/` (lines from `wc -l`):

| Class | All files | Lines | Non-doc files | Non-doc lines |
|---|---|---|---|---|
| R: reuse as-is or rename only | 37 | ~970 | 37 | ~970 |
| A: adapt | 40 | ~3,020 | 34 | ~2,370 |
| D: drop | 44 | ~4,350 | 40 | ~3,210 |

- About 13 % of non-doc lines (31 % of non-doc files) are reusable unchanged. They are small files: the overlay configs, helpers, initramfs and dev scripts.
- About 36 % of non-doc lines need adapting. That figure is inflated by `tools/pixel2-screen.c` (754 lines, of which only the ~150-line mainline mode survives) and by `build-all.sh`, `build-rootfs.sh`, `flash.sh` and `build-mainline.sh`, whose skeletons are generic.
- About 50 % of non-doc lines drop. They are dominated by device-tree and kernel material: walleye DTS 756, the 4 mainline patches 796, dtbo sink 300, audio dtsi 250; plus camera (~380) and the 4.4 Android-daemon stack (~330 in overlay plus stubs).
- **By function:**
  - build/host/dev tooling (scripts/, docker/, initramfs/): about 75 % R or A;
  - rootfs overlay: about 55 % R/A;
  - kernel/DT: about 95 % D (only `ubuntu.config` and the methods survive);
  - camera/audio: 100 % D.
- **Rule of thumb:** the "how" carries over (pipeline, debugging ladder, safety process, modem/wifi userspace recipe). The "what" (DT, patches, firmware lists, boot-image layout, partition scheme) has to be rebuilt for redfin.

---

## 7. Open questions handed to the Pixel 5 research agents

1. Boot image header version on redfin (v3?), the `vendor_boot` layout, where the DTB lives, and whether the bootloader still applies a `dtbo` overlay to a custom DTB. If it does, the dtbo-sink technique is needed. Also: `vbmeta_system`/`vbmeta_vendor` handling.
2. Dynamic partitions: is `vendor` (and the firmware files) inside `super`? This decides how `mount-vendor.sh`, `pixel2-modem-fw` and `build-mainline-fw.sh` find blobs (lpunpack / dm-linear).
3. Modem partition format (vfat `modem_a` with `image/*.mdt`?) and the MSS firmware set on SM7250 (no `mba.mbn`?).
4. Wifi chip and driver (ath10k snoc WCN3990-family?), board data names and board id, and whether `regd_override` is needed.
5. Mainline status for sm7250/redfin: an existing DTS (pmOS/sm7250-mainline?), panel driver, touch controller, charger (PM7250B) with or without `charge_behaviour`, MDSS in the SMMU identity list, GPU (Adreno 620) firmware names.
6. Whether redfin has a notification LED (likely not) and what replaces the "alive" indicator.
7. The downstream kernel/DT repository (redbull 4.19?) to pin as the hardware reference, the way kernel-msm was used for walleye.
8. Final factory image build ID, URL and SHA-256 for `get-firmware.sh`, plus the final bootloader/baseband strings for `flash.sh`.
