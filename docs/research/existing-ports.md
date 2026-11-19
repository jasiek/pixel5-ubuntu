# Linux distribution ports for the Google Pixel 5 (redfin, SM7250 "lito")

Survey date: 2026-11-18. Sources were checked live (web pages, GitLab/GitHub APIs, UBports system-image server, MediaWiki API) unless a claim is marked **[unverified]**.

---

## TL;DR

| Port | Base | Kernel | State (2026-11-18) |
|---|---|---|---|
| **Ubuntu Touch (UBports), community port** | **Ubuntu 24.04 noble** (UT `24.04-2.x`), Lomiri | Downstream **4.19.269** (`redbull`), Halium 13 | **Active.** Nearly full phone feature set. **Daily OTA images built today** on the `24.04-2.x` channel. Device-page MR still open, and the port is not in the UBports Installer yet. |
| postmarketOS (renamed **Nura** on 2026-09-27) | Alpine | none | **Stub wiki page only.** `booting = no`, `packaged = no`, no pmaports packages. The SoC (SM7250) is not upstream. |
| Droidian | Debian 13 trixie + Halium | n/a | **No redfin port.** The only Pixel in its device list is the 3a (sargo). |
| Mobian | Debian, mainline only | n/a | **No SM7250 support** (qcom configs cover sdm670, sdm845, sm6350, sm7150, sc7280). |
| Sailfish OS | Mer/hybris | n/a | **No port found.** Forum threads only ask for one. |
| Out-of-tree **mainline SM7250** bring-ups | Arch ARM / custom / Ubuntu 24.04 | Linux **v7.3-rc6/rc7** + patch stacks | Three hobby projects from Oct–Nov 2026, one of them for **redfin itself** (`sohalartz/redfin-postmarketos`). Self-reported to work: CPU, UFS, display, GPU, Wi-Fi, USB NCM, Ubuntu 24.04 boot. |
| LineageOS 24.0 (Android) | AOSP | Downstream 4.19 | Officially maintained. This is the source of the device tree, kernel and blob lists. |

**Ubuntu 24.04 with a phone UI exists for redfin today**, as Ubuntu Touch 24.04-2.x daily builds. Plain headless Ubuntu 24.04 on a mainline kernel is at "early hobby bring-up" stage, but someone is already doing it.

---

## 1. Ubuntu Touch (UBports): Halium 13, Ubuntu 24.04 noble

### Identity
- **Maintainer:** "DadrickPistachio" ([forum profile](https://forums.ubports.com/user/dadrickpistachio)).
- **Announcement:** [UBports forum topic 12584 "Google Pixel 5 (redfin)"](https://forums.ubports.com/topic/12584/google-pixel-5-redfin), posted 2026-09-07. Testers reported successful installs on 2026-09-10. A French relay is on [forum.ubuntu-fr.org](https://forum.ubuntu-fr.org/viewtopic.php?pid=22907066); that link returned 502 when I tried it.
- **Official community-port repos** (created 2026-09-18 under the UBports GitLab group):
  - Device adaptation: <https://gitlab.com/ubports/porting/community-ports/android13/google-pixel-5/google-redfin>. Last commit 2026-10-19 ("Move to ofono-binder-plugin-ext-qti@556d6cd7"). Licence **Apache-2.0**, added by Marius Gripsgard (UBports lead) on 2026-10-19. CI pipelines succeeded on 2026-10-20.
  - Kernel: <https://gitlab.com/ubports/porting/community-ports/android13/google-pixel-5/kernel-google-redbull>, branch `halium-13.0`. GPL-2.0 (Linux).
  - Original personal repos: [gitlab.com/dadrickpistachio/google-redfin](https://gitlab.com/dadrickpistachio/google-redfin) (no licence file) and the kernel [github.com/dadrickpistachio/android_kernel_google_redbull](https://github.com/dadrickpistachio/android_kernel_google_redbull). The kernel is a fork of `LineageOS/android_kernel_google_redbull` with branches `halium-11.0`, `halium-13.0` and `halium-14.0`.
- **devices.ubuntu-touch.io:** `/device/redfin/` currently returns **404**. [MR !686 "Add Google Pixel 5"](https://gitlab.com/ubports/infrastructure/devices.ubuntu-touch.io/-/merge_requests/686), described as "with support for noble", has been **open since 2026-10-03**. It declares `portType: Halium 13.0`, `kernelVersion: 4.19.269`, maintainer DadrickPistachio, and release file `releases/noble.md`.
- **UBports Installer:** there is no `redfin.yml` in `ubports/installer-configs` (404), so installation is manual with fastboot.

### Base and release (verified)
- `deviceinfo_halium_version="13"` and no `deviceinfo_ubuntu_touch_release`, so the generic build tools fall back to their default. That default is **`24.04-2.x`** since commit `878ed891` (2026-07-03).
- The CI log of the 2026-09-05 `devel-flashable` job confirms it downloaded `ubuntu-touch-rootfs/job/ubports%2F24.04-2.x/.../ubuntu-touch-android9plus-rootfs-arm64.tar.gz`.
- On [system-image.ubports.com/channels.json](https://system-image.ubports.com/channels.json), `redfin` appears in **`24.04-2.x/arm64/android9plus/daily`**, `24.04-2.x/.../android9plus_qt6/daily`, `26.04-1.x/.../daily` and `utnext/devel`.
  - It is **not** in any `stable` or `rc` channel, and not in 20.04 focal.
  - The redfin index has 59 images. The newest is tagged `24.04-2.x (2026-11-18/2)`, with device tarball `20261118`.
- **There is no focal (20.04) build.** The port is noble-only.
- Required Android firmware base: stock **Android 13 `redfin-tq3a.230901.001`**, flashed with Google's `flash-all` before installing UT.

### Install method (from the forum post)
1. Unlock the bootloader and flash the factory image TQ3A.230901.001 to slot a.
2. `fastboot reboot fastboot` (fastbootd).
3. `delete-logical-partition product_a system_ext_a`, so the 3.7 GB Ubuntu system image fits in `super`.
4. `fastboot flash system ubuntu.img`, then `fastboot erase userdata`.
5. Flash `boot.img`, `vendor_boot.img` and `dtbo.img`.

Images come from the CI artifact `devel-flashable`, or from OTA once the device is installed. The official repo also adds `make-super-empty.sh`/`super_empty.img` and raises the dynamic-partition group cap to let `system_a` reach 4500 MiB. Recovery: re-flash the Google factory image.

### Feature matrix (porter's README and the MR; `+` works, `+-` partial, `-` broken, `?` untested, `x` no hardware)

| Area | Status |
|---|---|
| Display / touch / brightness / auto-rotate / auto-brightness | + |
| GPU-accelerated UI | + (Android GLES blobs via libhybris) |
| HW video decode | + |
| Wi-Fi / hotspot | + |
| Bluetooth | + |
| NFC | + |
| Calls / call audio / routing / VoLTE / SMS / mobile data | + |
| MMS | +- (incoming SMS needed a patched `ofono-binder-plugin-ext-qti`, see below) |
| Dual SIM / eSIM | - |
| Audio (speaker, mic) | + (ships its own `pulseaudio-modules-droid` 14.2.110 to fix a crash on jackless phones) |
| Camera photo/video/flash/switch | + |
| GPS | + |
| Sensors (accel/rotation, light) | + |
| Proximity | ? (porter's unit is broken; a tester was asked to check) |
| **Fingerprint** | **-** |
| Double-tap-to-wake | - |
| Battery %, charging on/off | + |
| Qi wireless charging | ? |
| Vibration, torch, RTC, shutdown, recovery, factory reset | + |
| Waydroid, AppArmor | + |
| MTP / ADB | + |
| USB-C video out | ? |
| **Suspend / battery life** | **?** "Battery lifetime test" and "no spontaneous reboots" are untested. **[unverified]** whether deep sleep actually reaches low-power states. The kernel cmdline carries the stock `lpm_levels.sleep_disabled=1`, which Android's vendor init normally clears at runtime. |

### Reusable artefacts
- **Halium 13 kernel config** (`redbull_defconfig` + `halium.config`). Adds AppArmor, Waydroid/binder fixes, an RNDIS gadget, and a DSI TE2 timing fix. GPL-2.0.
- **deviceinfo**: full stock cmdline, boot image header v3, `Image.lz4`, the DTB `google/qcom-base/lito.dtb` plus 8 redfin dtbo overlays, `vendor_boot` layout.
- **Overlays**: ofono `qti.conf` IMS indication interface (`vendor.qti.googleext.imsext@4.0::IRadioExtIndication`), audio config, persist mount, USB HAL disable.
- **Build tooling**: `halium-generic-adaptation-build-tools`, Apache-2.0 since 2026-10-19, which builds the kernel plus boot/vendor_boot/dtbo images reproducibly in CI (`ubuntu:22.04` container).

---

## 2. postmarketOS → **Nura**

- postmarketOS was **renamed "Nura" on 2026-09-27**, and `postmarketos.org`, `wiki.postmarketos.org` and `pkgs.postmarketos.org` now 301-redirect to `nura.eco`. Coverage: [linuxiac](https://linuxiac.com/postmarketos-is-now-nura-after-major-project-rebrand/), [It's FOSS](https://itsfoss.com/news/postmarketos-nura-rebranding/), [pmcr 0003](https://docs.postmarketos.org/pmcr/main/0003-name-change-plan.html).
- The wiki is behind Anubis bot protection. I read it through the MediaWiki API.
- **[Google Pixel 5 (google-redfin)](https://wiki.postmarketos.org/wiki/Google_Pixel_5_(google-redfin))**:
  - `category = testing`, **`booting = no`, `packaged = no`**, `pmoskernel` empty, and **every feature field is blank**.
  - Created as a stub by Daviewales on 2023-12-13. Later edits only add the flash-mode description and links to downstream kernels (Google `redbull`, LineageOS); the last edit was 2025-09-12.
  - There are **no pmaports packages** (`device-google-redfin` and `linux-postmarketos-qcom-sm7250` do not exist).
- **[SM7250 SoC page](https://wiki.postmarketos.org/wiki/Qualcomm_Snapdragon_765/765G/768G_(SM7250))**: "mainline = In LKML, not merged yet", and every component status is blank. Edited Aug–Sep 2026, cosmetically only.
- **Sibling SM7250 devices on the wiki:**
  - Pixel 4a 5G (bramble) and Pixel 5a (barbet): not booting, stubs.
  - OnePlus Nord (avicii): downstream kernel, initfs debug shell only.
  - Xiaomi Mi 10 Lite 5G (monet): downstream 4.19.325, boots, USB net, touch and display partly working.
  - Redmi K30 5G (picasso): downstream 4.19.314, "porting".
- **Mainline status, checked against `torvalds/linux` master on 2026-11-18:** there is **no `sm7250*.dts(i)`** in `arch/arm64/boot/dts/qcom`. The nearby SoCs sm7125, sm7225 (FP4) and sm6350 are present.
- **Conclusion for option (d):** postmarketOS has **no kernel work for redfin to reuse**. Its only contributions would be the general pmbootstrap/pmaports infrastructure, the qcom firmware packaging pattern, and `msm-firmware-loader`/`droid-juicer`-style firmware handling.

---

## 3. Droidian

- Debian **trixie** base plus Halium. The project is active: the `droidian/droidian-release` repo was pushed on 2026-11-16.
- The device list at [devices.droidian.org](https://devices.droidian.org/) is a React bundle with 33 devices. **No redfin, bramble or barbet**; the only Pixel is the **3a (sargo)**.
- No GitHub repos `droidian-devices/*redfin*` or `*redbull*` exist.
- **Feasibility [partly unverified]:** Droidian ports Halium ≥ 9 GSI-style devices with a `linux-android-<vendor>-<device>` kernel package plus an `adaptation-*` package. The UT Halium 13 kernel (`halium-13.0` branch) and its vendor-side knowledge would carry over almost directly. Droidian's kernel packaging (`linux-packaging-snippets`) also produces a proper Debian kernel `.deb`, which is closer to the Pixel 2 project's "built from source" ethos. I did not verify Droidian's Halium 13 support policy as of 2026.

---

## 4. Mobian

- Mainline-only Debian derivative. The `Mobian-team/mobian-recipes` `devices/qcom/configs` directory contains `sc7280`, `sdm670`, `sdm845`, `sm6350`, `sm7150` and `wip` only. There is **no SM7250**.
- A reusable idea is **`droid-juicer`**, Mobian's tool for extracting device firmware from the phone's Android vendor/modem partitions at first boot, which avoids redistributing blobs. **[unverified]**: its licence. I believe it is GPL-3.0 but did not check.

---

## 5. Sailfish OS

- No community port found ([SFOS forum "SailfishOS on Google Pixel Devices"](https://forum.sailfishos.org/t/sailfishos-on-google-pixel-devices/6052) is only requests). Jolla's [supported devices](https://docs.sailfishos.org/Support/Supported_Devices/) are Xperia and Jolla hardware.
- The mer-hybris side could reuse the same Halium/hybris adaptation knowledge, but nobody has started one.

---

## 6. Out-of-tree mainline / "plain Linux" projects (most relevant to option a)

| Repo | What | Kernel | Status | Licence | Notes |
|---|---|---|---|---|---|
| [lazybrar/avicii-mainline](https://github.com/lazybrar/avicii-mainline) | OnePlus Nord (SM7250) mainline; **goal "a headless server"** | v7.3-rc7 + 14 subsystem patches (~75 commits) | Works: CPUs/cpufreq, UFS, USB gadget net, display (DSC cmd mode), **Adreno 620 with Mesa (Vulkan 1.3)**, touch, Wi-Fi (WCN3990 via modem, qrtr HACK), battery gauge, PM7250B charger, speaker (ADSP restarts every ~40 s). Not done: BT (partial later), modem calls/data, sensors, mic, camera, fingerprint. Suspend untested. | **GPL-2.0** | Brings up the whole **SM7250 SoC**: GCC/RPMh/dispcc/gpucc clocks, TLMM, UFS PHY, DPU 6.1 catalog, a620, MPSS/ADSP/CDSP PAS, `sm7250.dtsi`. Nothing upstreamed. Last push 2026-10-25. |
| [sm7250-mainline/linux_kernel](https://github.com/sm7250-mainline/linux_kernel) | Redmi K30 5G (picasso) | 7.3-rc6 | Early: GCC, RPMh, UFS, SoC dtsi split from the board | NOASSERTION (Linux tree) | Separate SM7250 SoC effort, 2026-10-20. Tries to match upstream naming, so it may be the better-upstreamable base. |
| [**sohalartz/redfin-postmarketos**](https://github.com/sohalartz/redfin-postmarketos) | **Pixel 5 (redfin) itself**: mainline + Ubuntu 24.04 rootfs boot image | v7.3-rc7 + avicii patches + `sm7250-google-redfin.dts` + new `panel-samsung-s6e3hc2.c` driver | Self-reported "VERIFIED WORKING": 8 CPUs + cpufreq, S6E3HC2 DSC panel (1080x2340@60), UFS, Adreno 620, WCN3990 Wi-Fi (scan), USB NCM `172.16.42.1`, SSH (dropbear), systemd as PID 1, Ubuntu 24.04 rootfs (`build_ubuntu_bootimg.py`). 20 commits, 2026-11-07 → 2026-11-09. | **None** (all rights reserved by default) | ⚠️ It **commits proprietary firmware** (`a620_zap.*`, `wlanmdsp.mbn`, `ipa_fws.*`, `bdwlan-*.bin`) **and a dropbear private host key plus `authorized_keys`** into the repo. It looks AI-agent driven (there is a "Handoff Guide for Antigravity"). Its claims are not independently verified. Treat it as a reference for the DTS and panel driver, not as a dependency. |
| [yinnho/aginxos](https://github.com/yinnho/aginxos) → `aginxos-next` | Rust-userspace "agent OS" on redfin | Downstream first, then bare-metal experiments | Archived 2026-09-05. The successor mirror ([gectcanada-sys/aginxos-next…](https://github.com/gectcanada-sys/aginxos-next-A-Rust-OS-for-AI-agents-on-a-real-phone-Linux-kernel-for-drivers-Rust-for-the-system)) has bare-metal register notes (USB dwc3/QUSB2, GDSC, PMIC ICL). | MIT | Mostly Chinese docs. A useful source of register-level notes, not a distro. |
| [radito/kernel-msm](https://github.com/radito/kernel-msm) | redbull 4.19 kernel + KernelSU | 4.19 | Android-oriented | NOASSERTION | Not relevant beyond being another 4.19 tree. |

---

## 7. LineageOS (vendor blobs and downstream reference)

- `redfin` is **officially maintained**, with `current_branch: 24.0` and versions 18.1 → 24.0. The device repo was pushed 2026-11-14 and the kernel 2026-11-07. Maintainer: `mikeioannina`. Sources: [lineage_wiki data](https://github.com/LineageOS/lineage_wiki/blob/main/_data/devices/redfin.yml) and [wiki](https://wiki.lineageos.org/devices/redfin/) (the wiki returned 403 to WebFetch; I read the data file instead).
- Kernel: [LineageOS/android_kernel_google_redbull](https://github.com/LineageOS/android_kernel_google_redbull), 4.19, shared with bramble and barbet. Device tree: [android_device_google_redfin](https://github.com/LineageOS/android_device_google_redfin) plus the `redbull` common tree.
- **Firmware prerequisite:** LineageOS requires stock **Android 14** firmware (`needs_specific_android_fw`, `version: '14'`, `ships_fw: true`). UT requires **Android 13 TQ3A.230901.001** instead. Make sure the modem/DSP firmware versions in your chosen base match what your kernel expects.
- **Vendor blobs:** `proprietary-files.txt` plus `extract-files.py` in the device tree enumerate every blob, including firmware paths such as `/vendor/firmware/*`, modem `image/*.mbn`, `a620_zap`, `wlanmdsp.mbn` and `bdwlan.bin`. Mirrors exist ([pixelos-redfin/proprietary_vendor_google_redfin](https://github.com/pixelos-redfin/proprietary_vendor_google_redfin)), but they are proprietary and not redistributable. The clean approach is to extract from Google's factory image or from the phone's own `modem_a`/`vendor_a` at build or first boot.

---

## 8. Recommendation matrix

Reference: the Pixel 2 project is plain Ubuntu 24.04 noble, headless-first, SSH over USB ECM/NCM and Wi-Fi, mainline kernel, everything built from source with pinned git submodules.

| | **(a1) Custom: mainline kernel + plain Ubuntu 24.04** | **(a2) Custom: downstream 4.19 kernel + plain Ubuntu 24.04 (no Android container)** | **(b) Ubuntu Touch 24.04-2.x (Halium 13)** | **(c) Droidian-style (Debian trixie + Halium)** | **(d) Base on postmarketOS/Nura kernel work** |
|---|---|---|---|---|---|
| **Effort to first SSH** | **Medium–high.** No upstream SM7250. You must carry avicii-mainline's SoC patch stack (~75 commits on 7.3-rc7) plus a redfin DTS and the S6E3HC2 panel driver; `sohalartz` shows it is doable in days for the basics. A rebase is needed every kernel cycle. | **Low–medium.** The LineageOS/UBports 4.19 tree builds today, and UT's deviceinfo gives the exact cmdline and boot header v3 / vendor_boot / dtbo recipe. USB gadget (RNDIS/NCM) works with configfs. | **Very low.** Flash the CI images or OTA; the device boots today. | **Medium.** You write `linux-android-google-redfin` + `adaptation-google-redfin` packages, reusing the UT kernel. There is no existing port. | Same as (a1): **there is nothing in pmOS to reuse** (stub page, not packaged, no kernel). |
| **Works on day 1** | CPU, UFS, USB NCM, display (DRM/KMS), GPU (freedreno/turnip), Wi-Fi with board-file and qrtr workarounds, battery gauge. *Self-reported by hobby projects.* **Missing:** modem calls/SMS/data, audio (ADSP unstable), BT (in progress), sensors, camera, fingerprint, suspend (untested). | Kernel-level drivers: display (fbdev/sde), touch, UFS, USB gadget, likely Wi-Fi (icnss/qca_cld in-kernel module + firmware). **[unverified]** Without Android userspace you lose GPU 3D (kgsl only; Mesa turnip has a KGSL backend, untested here), audio (needs Android audio HAL), modem (needs Qualcomm RIL/qmi daemons), camera and sensors. Suspend via the downstream LPM is plausible. | **Nearly everything:** calls/VoLTE/SMS/data, Wi-Fi, BT, NFC, GPS, camera, audio, GPU, sensors, Waydroid. **Missing:** fingerprint, dual SIM. Endurance, suspend and proximity are untested. | Roughly what UT gives, since it uses the same Halium layer, once the adaptation is done. Debian rather than Ubuntu. | — |
| **Long-term maintainability** | **Best trajectory, highest ongoing cost.** Mainline is the future, but SM7250 is out of tree and maintained by 2–3 hobbyists with nothing upstreamed. You would effectively become an SM7250 co-maintainer. | **Poor.** 4.19 is EOL upstream (LineageOS still patches it). It is frozen with Android 13/14 firmware, has an old userspace ABI (cgroups v1, no modern DRM for compositors), and diverges from Ubuntu kernels. | **Good while the porter stays active.** It is in the UBports org with Apache-2.0 adaptation, daily OTA on 24.04-2.x and 26.04-1.x channels, and Lomiri/Halium shared across many devices. Risks: a single maintainer, the not-yet-merged device page, the Android 13 firmware pin, and the Halium container being opaque. | Medium. Droidian is active but small, and Debian cadence is not Ubuntu's. | — |
| **Closeness to the Pixel 2 project** | **Closest.** Plain noble rootfs, mainline kernel, headless, USB NCM + Wi-Fi SSH, all from source with pinned submodules (pin `torvalds/linux` + `avicii-mainline` + your DTS). | Plain noble rootfs and headless, but a vendor kernel, and the downstream USB/Wi-Fi stacks differ from the Pixel 2 approach. | **Far.** Ubuntu Touch is an image-based, read-only rootfs with system-image OTA, an Android LXC container plus libhybris, and Lomiri. It is "Ubuntu 24.04" only in the package base. Headless use is possible over ADB/SSH, but the system is not built from source in your tree; you would consume UBports CI. | Far: same Halium architecture as UT, and Debian instead of Ubuntu. | n/a |

### Suggested strategy
1. **Primary path: (a1) mainline + plain Ubuntu 24.04.** It matches the Pixel 2 project, and the SoC groundwork exists as of October–November 2026.
   - Pin submodules: `linux` v7.3 (or the matching rc), the `lazybrar/avicii-mainline` patches (GPL-2.0), and your own redfin DTS. Use `sohalartz/redfin-postmarketos`'s `sm7250-google-redfin.dts` and `panel-samsung-s6e3hc2.c` **only as references**: the repo has no licence, so re-derive or ask the author to license it.
   - Extract firmware from the phone or the factory image at build time; never commit it.
   - Target headless first: USB NCM, Wi-Fi, UFS, battery/charger, display console.
   - Watch upstream LKML for SM7250 series.
2. **Use (b) Ubuntu Touch as a reference and a fallback.**
   - Its `deviceinfo` gives the exact boot image layout and cmdline.
   - Its Halium-13 kernel config tells you what the vendor stack needs.
   - Its working modem/IMS/audio configuration shows what hardware works and which firmware versions are needed.
   - If "a usable phone running Ubuntu 24.04" ever matters more than "plain Ubuntu built from source", UT 24.04-2.x on redfin is available **today**.
3. **Skip (c) and (d).** Droidian would mean writing a Halium port that UT already has. pmOS/Nura has no redfin or SM7250 kernel work at all.

---

## 9. Could not verify / caveats
- **devices.ubuntu-touch.io/device/redfin:** 404. All UT feature data comes from the porter's README, the forum post and MR !686. I could not run the device, and "+" entries are the porter's own claims; one tester confirmed install only.
- **UT suspend/deep-sleep behaviour and battery life:** not reported.
- **sohalartz/redfin-postmarketos "VERIFIED WORKING" claims:** self-reported, three days of commits, apparently AI-agent driven. I did not check that its CI produces a booting image.
- **avicii-mainline status:** self-reported for a different phone (OnePlus Nord). Pixel 5 board peripherals differ: panel S6E3HC2 vs AMS644VK04, touch, Cirrus CS35L41 amps vs TFA9874, charger/fuel-gauge wiring.
- **The "In LKML, not merged yet" status of SM7250:** taken from the pmOS wiki. lore.kernel.org was blocked by Anubis, so I could not check which series are posted. I only confirmed that `torvalds/linux` master has no `sm7250` DTS.
- **Droidian's Halium 13 support policy, and the `droid-juicer` licence:** not checked.
- **Option (a2) capabilities without an Android userspace:** reasoned from how Qualcomm downstream stacks work, not tested or documented for redfin.
- **LineageOS wiki page:** returned 403. I used the wiki's data YAML on GitHub instead.
