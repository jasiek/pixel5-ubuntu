# Mainline Linux on the Google Pixel 5 (redfin, SM7250 "lito"): status as of 2026-11-18

## TL;DR

- **Mainline has no SM7250 board support yet, and no redfin or bramble DTS exists anywhere.** That includes mainline, linux-next, pmaports and every GitHub tree I could find.
  - Mainline **v7.4-rc3** (torvalds HEAD, 2026-11-18) has only the SM7250 socinfo ID, RPMh clocks and RPMh power domains, plus the PDC and Kryo 475 bindings.
  - **linux-next (next-20261118)** adds the SM7250 UBWC entry, and nothing else.
  - The base series (`sm7250.dtsi` plus the GCC driver) is at **v15 (2026-11-16) and still pending**. There is no `arch/arm64/boot/dts/qcom/sm7250*` file in either tree.
- **The SoC is still well understood, because three independent SM7250 phones run mainline out of tree (Sep–Nov 2026).** All are "Claude/LLM-assisted" hobby ports:
  1. **Motorola Moto G 5G Plus "nairo"**: about 159 patches on next-20261021. It runs Arch with UFS, USB networking, Wi-Fi, a display through DPU, an Adreno 620 with GL and Vulkan, touch, audio, **modem calls, SMS and data**, suspend, and charger plus gauge. This is the most complete port.
  2. **OnePlus Nord "avicii"**: patches on v7.3-rc7. It has a DSC command-mode Samsung AMOLED, the GPU, Wi-Fi, SSC sensors and a speaker. The author (Ishu Brar) is upstreaming the interconnect, gpucc, dispcc, DPU/MDSS and UBWC pieces.
  3. **Xiaomi Redmi K30 5G "picasso"**: 7.3-rc6. It has display, GPU, touch, UFS and audio (WCD9385).
- **Pixel 5 itself:** no mainline port is visible.
  - postmarketOS (whose GitLab and wiki now redirect to `*.nura.eco`, branded "Nura") has only an empty `google-redfin` wiki stub, and no packages.
  - A downstream 4.19 `google-bramble` pmaports MR was opened and **closed** in Oct 2026.
  - "AginxOS" runs a custom userspace on redfin, but on the **stock downstream kernel**.
- **Verdict:** a mainline Ubuntu 24.04 on redfin is **feasible but not off the shelf.** Expect a port in the same spirit as the Pixel 2 "Porthole" effort, except no pmOS kernel package exists to start from. You would:
  - take the SoC-level work from the nairo and avicii series;
  - write a new `sm7250-google-redfin.dts`;
  - write or port four or five redfin-specific drivers: the S6E3HC2 DSC command-mode panel, Samsung S6SY79x SPI touch, the TI DRV2624 haptics, and the CS35L41 plus RT5514 audio wiring;
  - solve a few Pixel-specific problems: how the ABL loads the DTB and dtbo, and the requirement that the Pixel modem have its SMEM socinfo item filled in.
- Ubuntu 24.04's Mesa 24.0 already knows the A620 (`GPUId(620)` is in `freedreno_devices.py` since at least mesa-24.0.9). GPU userspace should therefore not need a PPA. This is unverified on a device.

---

## 1. Device trees: upstream and out of tree

### 1.1 Upstream (mainline v7.4-rc3 / linux-next next-20261118)

I checked out linux-next `e8017d29067f` ("next-20261118", Makefile 7.4.0-rc3) and grepped it. I also queried the torvalds/linux GitHub mirror.

| Item | Mainline 7.4-rc3 | linux-next 20261118 |
|---|---|---|
| `QCOM_ID_SM7250 = 400`, socinfo | yes | yes |
| `clk-rpmh` `qcom,sm7250-rpmh-clk` | yes | yes |
| `rpmhpd` `qcom,sm7250-rpmhpd` (CX, EBI, GFX, LCX, LMX, MSS, MX) | yes | yes |
| PDC binding, Kryo 475 CPU binding | yes | yes |
| `ubwc_config.c` `qcom,sm7250` | **no** | yes (Ishu Brar patch, "in-next") |
| `sm7250.dtsi`, GCC, TLMM pinctrl, interconnect, dispcc, gpucc, DPU 6.1, A620 catalog, UFS/USB PHY tables, PAS for ADSP/CDSP/MPSS, IPA | **no** | **no** |
| Any `*google-redfin*` or `*google-bramble*` DTS | no | no |

Notes:

- SM7250 does **not** reuse sm7225 or sm6350. `sm7225.dtsi` is the Fairphone 4, which is SM6350-based ("lagoon"). SM7250 "lito" is a cut-down SM8250 "kona" relative.
  - Its clocks, dispcc, gpucc and DSI are variants of the SM8250 drivers.
  - Its IPA (v4.7) and its LPASS LPI pinctrl match SM6350.
  - Its DPU is 6.1, which sits between SM8250's 6.0 and SC7180's 6.2.
  - These family relationships come from the nairo and avicii write-ups.
- Mainline's A6xx catalog has the A621 (`0x06020100`, SAR2130P) and the A623, but **not the A620**. The `a620_hwcg` table already exists and is reused by the A621.

### 1.2 Upstream patch series in flight (from the patchwork API, linux-arm-msm, query "SM7250")

| Series | Author | Latest | State |
|---|---|---|---|
| "Add initial support for Qualcomm SM7250 SoC": GCC, LMh, SCM, cpufreq-hw bindings, `sm7250.dtsi` | Sreeshankar K | **v15, 2026-11-16** (rebased for 7.4-rc3) | Pending; Reviewed-by from Krzysztof Kozlowski on the GCC binding. v1–v10 parts were merged in 7.4: socinfo, rpmhcc, rpmhpd, PDC, Kryo 475. The DTSI is CPUs, PSCI, interrupts, clocks, power domains and reserved memory only. [ratatoskr v15](https://ratatoskr.run/linux-arm-msm/2026/11/17942053/t), [patchwork list](https://patchwork.kernel.org/project/linux-arm-msm/list/?q=SM7250) |
| interconnect: SM7250 RPMh NoC provider | Ishu Brar | v6, 2026-11-18 | new |
| clk: SM7250 graphics clock controller | Ishu Brar | RESEND v3, 2026-11-16 | new |
| clk: SM7250 display clock controller | Ishu Brar | v1, 2026-10-23 | new |
| drm/msm/dpu + mdss: SM7250 (DPU 6.1) | Ishu Brar | v3, 2026-11-13 ("Tested on a OnePlus Nord (a 7.3 based tree)") | new |
| soc: qcom: ubwc: SM7250 | Ishu Brar | v1 | **in linux-next** |
| iommu/arm-smmu-qcom: skip PRR on SM7250 GPU SMMU; remoteproc PAS SM7250 ADSP; qfprom | Ishu Brar | Oct 2026 | "handled-elsewhere" (other lists) |
| remoteproc: qcom_q6v5_mss: publish socinfo for **Pixel** modems | David Heidelberg | v3, 2026-11-16 | Pixel-specific; see §2.4 ([patch](https://patchwork.kernel.org/project/linux-arm-msm/patch/20261116-modemsmem-v3-2-24ebc7ed6eb9@ixit.cz/)) |

A realistic forecast, and only a guess: the base dtsi and GCC could land for **7.5 or 7.6**, with DPU, interconnect and gpucc at the same time or one cycle later. No TLMM pinctrl driver has been posted upstream yet, and booting needs one.

### 1.3 Out-of-tree SM7250 trees (the useful material)

| Tree | Device | Base | Last activity | What works (per author) |
|---|---|---|---|---|
| [effeffe/nairoArchLinuxArmTools](https://github.com/effeffe/nairoArchLinuxArmTools) + [blog post source](https://github.com/effeffe/effeffe.github.io/blob/HEAD/_posts/2026-10-04-mainline-linux-moto-g-5g-plus.md) | Moto G 5G Plus (nairo) | linux-next **next-20261021** (7.3-rc5), 159-patch series in `kernel/patches/` | 2026-10-21 | UFS (HS-G3, reliable after `qphy.lvl` fix), SD, USB2 NCM gadget, Wi-Fi (ath10k_snoc), modem (LTE, calls, SMS, data via IPA + ModemManager), DPU/DSI/panel, A620 GL 4.6 / Vulkan 1.3, interconnect, TSENS/thermal, charger (SMB5) + QGauge, s2idle with modem wake, audio (WCD9380, speaker amp, call audio via q6voice), haptics. Missing: BT, cameras, sensors, VoLTE, CDSP (TZ `-EINVAL`). |
| [lazybrar/avicii-mainline](https://github.com/lazybrar/avicii-mainline) | OnePlus Nord (avicii) | **v7.3-rc7** | 2026-10-25 | CPUs/cpufreq, UFS, USB2 gadget, **Samsung AMS644VK04 DSI command mode + DSC** (closest analogue to the Pixel 5 panel), A620 (Turnip), Goodix touch, Wi-Fi (qrtr HACK), PM7250B charging, speaker (ADSP restarts every ~40 s, see below), **SSC sensors (accel/light/prox/mag)**. CDSP and Venus rejected by TZ (`-22`). "The bootloader needs `dtbo_a` erased to accept the mainline device tree." |
| [sm7250-mainline/linux_kernel](https://github.com/sm7250-mainline/linux_kernel) + [docs](https://github.com/sm7250-mainline/docs) | Redmi K30 5G (picasso) | 7.3-rc6 | 2026-10-21 | Display (Novatek DSC video), A620, NT36672C touch, UFS, WCD9385 sound card. ADSP `sensor_process` watchdog bite was unresolved. Needed a "copydown shim" for Xiaomi's ABL. Docs are in Chinese. |
| [yinnho/aginxos](https://github.com/yinnho/aginxos) | **Pixel 5 (redfin)** | stock/Lineage **downstream** kernel; patches `vendor_boot` | archived 2026-09-05 (successor `aginxos-next` not public) | Useful only for redfin boot facts: two ramdisks (boot + vendor_boot), USB gadget, `vendor_boot` patching. |
| pmaports MR [!9754](https://gitlab.nura.eco/nura/pmaports/-/merge_requests/9754) "downstream: add Google Pixel 4a (5G) (google-bramble)" | bramble | downstream 4.19 | opened 2026-10-12, **closed** 2026-10-14 | Display (msm_drm, pixman), touch, Wi-Fi, battery, NCM. Not mainline. |
| pmaports | — | — | — | **No** `device-google-redfin`, `device-google-bramble` or `linux-*-sm7250` packages in `device/{main,community,testing,downstream}`. The only SM7250 device is `device/downstream/device-xiaomi-monet` (4.19). Wiki pages for [redfin](https://wiki.postmarketos.org/wiki/Google_Pixel_5_(google-redfin)) and bramble are empty templates ("booting = no"). |
| Downstream references | redfin/bramble/barbet | 4.19 | — | [LineageOS/android_kernel_google_redbull](https://github.com/LineageOS/android_kernel_google_redbull) (branch lineage-24.0, 2026-11-07), DTs in `arch/arm64/boot/dts/google/lito-redfin*.dtsi`, `qcom-base/lito*.dtsi`; also [radito/kernel-msm](https://github.com/radito/kernel-msm). |

**Note on the "Porthole" analogy:** there is no ready-made SM7250 counterpart to `linux-postmarketos-qcom-msm8998`. The practical base is:

1. mainline or linux-next;
2. the Sreeshankar v15 base series;
3. Ishu Brar's interconnect, gpucc, dispcc and DPU series;
4. a cherry-pick of the nairo series: TLMM, SMMU, UFS, USB, IPA, MPSS/ADSP PAS, A620, TSENS, SMB5, QGauge, q6voice, suspend fixes;
5. the avicii pieces for the command-mode DSC panel and SSC sensors.

None of these trees has been rebased onto a common base. The nairo and avicii trees carry partly overlapping, independently written versions of the same drivers: TLMM, interconnect, gpucc and DPU.

---

## 2. Per-subsystem status for redfin

The hardware facts below come from the downstream redbull DT (`lito-redfin*.dtsi`, `lito-redbull*.dtsi`, `qcom-base/lito*.dtsi`). The production board is `lito-v2-redfin-pvt`: `compatible = "google,redfin-sm7250", "qcom,sm7250"`, `qcom,msm-id = <400 0x20000>, <440 0x20000>`, `qcom,board-id = <0x0b1e05 0>`.

### 2.1 Status table

Effort legend:

- **W**: works with upstream or near-upstream code, needs only DT.
- **S**: small patch, or applying an existing out-of-tree patch.
- **P**: port from downstream or another SM7250 tree, moderate effort.
- **R**: research problem, or unlikely to work.

| Subsystem | Pixel 5 hardware (source) | Mainline status | Best existing SM7250 work | Effort for redfin |
|---|---|---|---|---|
| SoC base: GCC, TLMM, SMMU, RPMh, PDC, cpufreq-hw | SM7250 v2 (msm-id 400/440, rev 0x20000) | Partial (RPMh clocks and power domains only) | Sreeshankar v15 (GCC, dtsi, cpufreq binding, LMh); TLMM from nairo, avicii or picasso (not upstream) | **S/P** |
| Board DTS `sm7250-google-redfin.dts` | — | none | none anywhere | **P**: write from downstream DT plus live `/sys/firmware/fdt` |
| Boot path (ABL, vendor_boot, dtbo) | Header v3: kernel in `boot`, DTB plus vendor ramdisk in `vendor_boot`, `dtbo` overlays applied by ABL (AginxOS notes) | n/a | nairo: ABL needs no EFI stub, overlay "sink" DT, model string `Qualcomm Technologies, Inc. Lito`. avicii: erase `dtbo_a`. picasso: copydown shim. | **R (small but unknown)**: Pixel ABL behaviour with a mainline DTB is **not documented anywhere I found** |
| Debug console | No easy UART | — | pstore/ramoops (nairo, avicii) | S |
| UFS | UFS 2.1 (Samsung/Micron/SK Hynix, LUN layout per factory GPT) | no SM7250 QMP-UFS tables | nairo: QMP-UFS SM7250 tables, downstream reset sequence, `qphy.lvl` permanent vote, HS-G3 at 150 MHz UniPro, **32-bit DMA mask** (UFS SMMU SID unknown); picasso and avicii similar | **S** (apply nairo patches) |
| USB peripheral (NCM/ECM gadget) | dwc3 `a600000`, PM7250B Type-C/PD (`pm7250b_pdphy`), external 5 V boost via a TPS regulator | dwc3-qcom, `qcom,pm8150b-typec`/pdphy and `pm7250b.dtsi` exist upstream | nairo and avicii: USB2 HS gadget with `qcom,select-utmi-as-pipe-clk` + apps SMMU SID + resume fix | **S** for USB2 gadget. **P** for USB3 SuperSpeed: needs SM7250 QMP USB3/DP PHY tables (`lito-qmp-usb3`). Nobody has done this, because both proxy phones are USB 2.0 only. |
| Display | **Samsung S6E3HC2** DDIC, 1080x2340 AMOLED, "s6e3hc2 amoled 5.96 cmd mode panel", **DSI command mode with DSC** (slice 540x65, 8 bpc), 60 and 90 Hz modes; reset on PM7250B GPIO5, TE on TLMM 10; DVT panels have a gamma fixup | DPU 6.1, MDSS and dispcc not upstream (posted). DSI 7 nm PHY OK. **No s6e3hc2 panel driver** (mainline has s6e3ha2/ha8/fa7/fc2x01, not hc2). | Ishu Brar DPU/MDSS/dispcc (avicii: Samsung AMS644VK04 **cmd mode + DSC works**); nairo dispcc variant | **P**: new panel driver from downstream DCS sequences (e.g. via linux-mdss-dsi-panel-driver-generator) plus the DPU series |
| Touchscreen | **Samsung S6SY79x** (`sec,sec_ts`) on **SPI** QUP SE0, IRQ TLMM 9, reset TLMM 8, **TLMM 35 selects AP vs sensor hub ("SLPI")**, firmware `s6sy79x.bin` | `s6sy761` driver exists but is **I2C only** | none for this chip | **P/S**: add SPI transport to s6sy761 (or port sec_ts); drive GPIO 35 low; panel-follower |
| GPU | Adreno 620 (speed-bin fuse decides 540, 625 or 750 MHz) | **A620 not in catalog**; A621 entry close | nairo: catalog, gpucc-sm8250 variant, GMU PDC programming, PRR skip, zap region alignment, speed bins, GMU bandwidth vote; picasso: same chip id variant `0x06020002`; Ishu gpucc v3 + PRR posted | **S** (proven on 3 phones). Userspace: Ubuntu 24.04 Mesa 24.0 has `GPUId(620)`. |
| Interconnect | — | not upstream | Ishu Brar v6 (posted); nairo generated driver (12 providers, 138 nodes) | **S** |
| Wi-Fi | **WCN3990** (`qca,wcn3990`, ath10k_snoc; WLAN firmware runs on MPSS) | ath10k_snoc yes; needs SM7250 modem, PD-mapper, DT | nairo and avicii: works. Needs pd-mapper SM7250 table (plus `qcom,lito` compatible if dtbo rewrites root), board-2.bin built from vendor `bdwlan*`, `qcom,calibration-variant`, hwmon skip patch | **S** once the modem is up |
| Bluetooth | WCN3990 BT over UART (`bt_wcn3990`) | hci_qca supports WCN3990 | not done on any SM7250 port (avicii has it on an unpublished branch, WCN3991) | **S** |
| Modem (MPSS, QRTR, rmtfs, IPA, ModemManager) | Integrated X52 (sub-6 GHz 5G; mmWave on the Verizon GD1YQ SKU) | PAS lacks SM7250 MPSS; IPA v4.7 code exists (SM6350) | nairo: MPSS PAS, IPA SM7250 entry + IMEM, `modem_pr/` served by tqftpserv, IPA loaded before modem, QRTR-ns fix; LTE calls, SMS and data work; boot race workaround; no VoLTE | **P + Pixel-specific R**: Google modem firmware (Pixel 3–5a) refuses to boot unless SMEM item 134 holds socinfo ([Heidelberg patch](https://patchwork.kernel.org/project/linux-arm-msm/patch/20261116-modemsmem-v3-2-24ebc7ed6eb9@ixit.cz/)). That patch targets `qcom_q6v5_mss`; whether redfin's modem needs it under the PAS loader is **unverified**. 5G NR registration on mainline is **unverified** (nobody has reported it); VoLTE needs an IMS stack (R). |
| Audio | **2x Cirrus CS35L41** amps on QUP SE9 I2C @0x40/0x41 over **quinary TDM** (bottom speaker plus the under-display "panel speaker" that replaces the earpiece; downstream "sm7250-noextcodec-snd-card"). Mics through **Realtek RT5514** DSP codec (I2C 0x57 on SE7 + SPI on SE4, DMIC mux). **No WCD codec**, no headphone jack. | q6afe/q6asm/q6adm (APR, not AudioReach) + sm8250 machine driver exist; cs35l41 and rt5514 codec drivers exist | nairo: ADSP PAS (`adsp2` variant fuse!), LPASS macros, q6voice call audio (out of tree); avicii: ADSP + MI2S amp | **P**: new board wiring (TDM to two CS35L41, RT5514), Cirrus DSP firmware/tuning from vendor (no speaker protection), UCM. Risk of **ADSP `sensor_process` watchdog restarts every ~40 s** without hexagonrpcd plus the sensor registry (seen on avicii and picasso, not on nairo). |
| Call audio | — | q6voice not upstream | nairo port of sdm845-mainline q6voice (CVD 2.3, codec DMA ports) | **P** |
| Charger | PM7250B SMB5 | `qcom_smbx` has PMI8998/PM660 only | posted upstream "SMB5 support for qcom_smbx" series (applied by nairo) | **S** |
| Fuel gauge | PM7250B QGauge (`qcom,qg-iterm-ma = 600`, redfin battery profile); Google gbms layered on top downstream | none | nairo: new read-only `qcom_qg` driver using OCV table | **S/P** |
| Wireless charging | IDT **P9382** (`lito-redfin-wcharger.dtsi`) | no driver | none | **P or R** (may charge autonomously; **unverified**) |
| PMIC regulators | PM8150 (A), PM8150L (C) RPMh regulators; PM7250B; PM8008 for cameras | all supported (`qcom,pm8150*-rpmh-regulators`, pm8008) | — | **W** |
| Power monitors | Microchip PAC1934 | `iio/adc/pac1934` exists | — | **W** |
| Cameras | Not named in the DT (camx userspace). Per public spec sheets, **not verified from source**: Sony IMX363 main, IMX481 ultrawide, IMX355 front. CCI0/1, EEPROM, actuator, OIS. | imx355 driver exists; imx363 and imx481 do not; **no SM7250 CAMSS** (Titan 175-class; mainline has 170 and 480) | avicii: camcc/CCI/CAMSS probe, no frames | **R** |
| Sensors (accel, gyro, prox, light, mag, baro) | On the ADSP-hosted SSC (lito has no separate SLPI) | needs FastRPC + userspace (hexagonrpcd, libssc) | avicii: **accel, light, prox, mag working**; picasso fought the `sensor_process` watchdog | **P/R** |
| Fingerprint (rear) | **FPC1020** behind TrustZone | none | none | **R** (TEE trustlet; effectively infeasible) |
| Haptics | **TI DRV2624** (I2C) | `drv260x` covers 2604/2605 only; no 2624 | nairo wrote an AW8695 driver (different chip) | **P** (small new driver) |
| NFC / eSE | **ST21NFC** (`st,st21nfc`) + ST54J secure element | `st-nci` covers st21nfcb/c over I2C; fit for the redfin chip **unverified** | none | **S-P / unverified** |
| Flash LED | PM8150L flash (likely; via `camera-pmic` DT) | `qcom,pm8150l-flash-led` supported | — | **W/S** |
| Notification LED / backlight | OLED, so DCS brightness; no WLED needed | — | — | via panel driver |
| CPU freq / thermal | cpufreq-hw 3 domains, LMh, TSENS | cpufreq-hw driver generic; SM7250 binding and LMh in v15 | nairo: TSENS + 27 zones; avicii: cpufreq, idle, capacities | **S** |
| Suspend | s2idle only | — | nairo: s2idle works (`fw_devlink.sync_state=timeout`, dwc3 resume fix, glink-smem wake for modem) | **S** |
| CDSP / Venus video | — | — | Both nairo and avicii: TZ rejects CDSP/Venus PAS (`-EINVAL`/`-22`) | **R** |
| "Rainbow" flicker sensor, laser AF, Titan M | ST VD6281, laser, Citadel | none | none | not needed |

### 2.2 Pixel 5 vs bramble differences (if using the Pixel 4a 5G as a proxy)

Both share the redbull kernel and the lito SoC. bramble's display is the `sofef01` family. linux-next now has a `samsung,sofef01-m` **binding** (Sony panels) but I found no driver. bramble's touch is described as "FocalTech FT5446" in MR !9754 (not cross-checked). bramble has a headphone jack and thus a codec. So display, touch and audio do **not** transfer between redfin and bramble. Modem, Wi-Fi, GPU, UFS and charging should.

### 2.3 Boot-path risks specific to Pixel 5 (unverified)

- **Two ramdisks, DTB from vendor_boot.** Per AginxOS, redfin's ABL loads `boot` and `vendor_boot` ramdisks, and the vendor ramdisk's `init` wins. A mainline boot will probably require flashing a custom `vendor_boot` with the mainline DTB, plus an empty or neutral vendor ramdisk.
  - `fastboot boot` of a header-v3 boot image keeps the **stock** vendor_boot, and so the stock DTB. This is my inference from the header-v3 layout and was not tested.
- **dtbo overlay.** All three SM7250 ports had to defeat ABL's dtbo overlay: erase it (avicii), create a symbol "sink" (nairo), or use a shim (picasso). On nairo, the overlay also rewrote the root compatible to `qcom,lito`, which broke the UBWC and pd-mapper compatible matches. Expect the same class of problem on redfin.
- **The DTB must probably carry the matching IDs**: `qcom,msm-id = <400 0x20000>` and `qcom,board-id = <0x0b1e05 0>`.
- **A/B and AVB.** The bootloader must be unlocked. AVB/vbmeta probably needs disabling with `--disable-verity --disable-verification` (standard Pixel practice, not verified for this flow).

### 2.4 Modem specifics

- Pixel modem firmware expects socinfo in SMEM item 134. The patch is upstream-bound, for `qcom_q6v5_mss` with a `google,require-socinfo` DT property.
- If redfin's MPSS is started via `qcom_q6v5_pas` (as on nairo), the same hook may be needed there. **Unverified.**
- Userspace needs:
  - `rmtfs` against the `modemst1`/`modemst2`/`fsg`/`fsc` partitions (read-only copies recommended, as nairo does);
  - `tqftpserv` serving the modem partition's `image/modem_pr/` tree;
  - `pd-mapper` (in kernel since 6.x, needs an SM7250 table);
  - `qrtr`;
  - ModemManager's QRTR backend.
- ModemManager's `--test-quick-suspend-resume` helps keep the modem across suspend.

---

## 3. Firmware needs

General rules:

- All Qualcomm DSP, modem and zap images are **signed for the OEM**. Use the phone's own files, or at least files from the same redbull (Google) signing chain. Never use another vendor's SM7250 blobs.
- Mainline's `qcom_mdt_loader` can load split `.mdt` + `.bNN` files directly. linux-firmware convention, and most pmOS packages, squash them into a single `.mbn` with [`pil-squasher`](https://github.com/linux-msm/pil-squasher). Either works if the DT `firmware-name` matches.
- No re-signing is needed (or possible).

| Blob | Purpose | Likely source on redfin | Notes |
|---|---|---|---|
| `modem.mdt`/`.bNN` (→ `modem.mbn`) and `modem_pr/` tree (MCFG, `so/*.mbn`) | MPSS | `modem_a` partition (vfat), `image/` | nairo: the modem watchdog fired until `modem_pr/so/819_0_0.mbn` was served via tqftpserv |
| `adsp.mdt` (and possibly `adsp2.*`) | ADSP (audio, SSC sensors) | `modem_a:image/` | nairo needed `adsp2`, selected by an `adsp_variant` fuse; check which one redfin uses (look at the downstream `firmware-name` or the dmesg of stock) |
| `cdsp.mdt` | CDSP | `modem_a:image/` | TZ refused CDSP on nairo and avicii; optional |
| `wlanmdsp.mbn` | WCN3990 WLAN firmware (runs on modem) | `modem_a:image/` | loaded by the modem via tqftpserv |
| `bdwlan*.bin` | WCN3990 board data | `modem_a:image/` or vendor | wrap into `ath10k/WCN3990/hw1.0/board-2.bin` with a `variant=` (nairo script) |
| `ath10k/WCN3990/hw1.0/firmware-5.bin` | ath10k host firmware descriptor | linux-firmware | — |
| `qca/crbtfw21.tlv`, `qca/crnv21.bin` | WCN3990 BT | linux-firmware (or vendor) | — |
| `a620_zap.mdt`/`.bNN` (→ `.mbn`) | Adreno zap shader (secure) | vendor partition (`/vendor/firmware`) or `modem_a:image/` | Signed. The zap region in the downstream DT (`0x8bc15400`) is not page-aligned, so use an aligned page (nairo). |
| `a650_sqe.fw`, `a650_gmu.bin` | A620 CP microcode and GMU | **linux-firmware** (`qcom/`) or vendor | Same files the downstream kernel uses |
| `ipa_fws.*` | IPA GSI firmware | `modem_a:image/` or vendor | With `modem-init`, the modem loads it. Check what nairo stages. |
| `s6sy79x.bin` | Touch firmware | vendor `/vendor/firmware` | Usually already flashed in the controller; may be optional |
| CS35L41 `.wmfw` / `.bin` tunings | Speaker/panel-exciter amps | vendor `/vendor/firmware` | Without them the amps run in bypass mode (no speaker protection) |
| RT5514 firmware (`rt5514_dsp_fw*.bin`) | Hotword DSP (mics) | vendor | Only for the DSP path; plain DMIC passthrough may not need it (**unverified**) |
| Sensor registry / `sns_reg` config | SSC sensors | vendor `/vendor/etc/sensors/` and the `persist` partition | For hexagonrpcd + libssc |
| `venus.*`, `cvpss`, `npu` | Video, CV, NPU | vendor | Not needed initially; Venus was TZ-refused on avicii |

I could not list the exact file names on a redfin vendor or modem image. Confirm them with `adb shell ls /vendor/firmware /vendor/firmware_mnt/image` on stock Android before planning packaging.

---

## 4. Top 5 blockers and difficulty

1. **No SM7250 SoC and board support in any tree we can just build** (difficulty S/P, but large in volume).
   - Base dtsi and GCC are at v15; TLMM is not posted; DPU, interconnect and gpucc are only now being posted.
   - You must assemble a tree from nairo, avicii, Sreeshankar and Ishu Brar, then write `sm7250-google-redfin.dts` from the downstream DT.
   - Expect 1–3 weeks of focused work to reach a UFS + USB-NCM shell, given that the three reference ports exist.
2. **The Pixel ABL boot path** (R, possibly small). Header-v3 vendor_boot DTB, dtbo overlay handling and model/ID matching have never been documented for a mainline redfin boot. There is also no UART. This is the first gate: until a mainline kernel prints to pstore, nothing else matters.
3. **The display panel** (P): S6E3HC2 in DSI command mode with DSC, at 60 and 90 Hz. A new panel driver is needed on top of the not-yet-merged DPU 6.1 series. avicii proves that command mode + DSC works on SM7250 DPU. Until then, simpledrm on the bootloader framebuffer (with an interconnect vote, as on nairo) is a workable stopgap for a desktop.
4. **Touch** (P/S): Samsung S6SY79x over SPI with an AP/SSC mux GPIO. The mainline s6sy761 driver is I2C only and needs an SPI transport plus probable protocol differences. Without touch, a phone UI is unusable. USB keyboard and SSH remain possible.
5. **Modem, audio and the ADSP stack** (P with R parts):
   - the Pixel-specific SMEM socinfo requirement for the modem;
   - the ADSP firmware variant;
   - the ADSP `sensor_process` watchdog restarts, which need hexagonrpcd plus the sensor registry;
   - the CS35L41 TDM and RT5514 wiring and tuning;
   - q6voice for calls, which is out of tree.

   Wi-Fi depends on the modem being up, so this blocks Wi-Fi too. LTE data, calls and SMS are proven on nairo; 5G NR and VoLTE are unproven.

Not blockers for a usable Ubuntu device, but effectively unsolved: cameras (no SM7250 CAMSS, no IMX363/IMX481 drivers), rear fingerprint (TEE), CDSP and Venus (TZ refuses), wireless charging (P9382).

### Rough difficulty summary

| Works / DT only | Small patch / apply existing | Port (moderate) | Research |
|---|---|---|---|
| PMIC regulators, PAC1934, flash LED (probably), Ubuntu Mesa A620 | UFS, USB2 gadget, GPU A620, interconnect, Wi-Fi, BT, cpufreq/thermal, charger, suspend | Board DTS, S6E3HC2 panel, S6SY79x SPI touch, DRV2624 haptics, audio wiring (CS35L41/RT5514), modem bring-up incl. IPA, q6voice, QGauge, USB3 SS PHY, SSC sensors | ABL boot path (first gate), Pixel modem SMEM quirk under PAS, 5G NR / VoLTE, cameras, fingerprint, CDSP/Venus, wireless charging |

---

## 5. What I could not verify

- Whether **any** mainline kernel has ever booted on a redfin or bramble. I found no evidence that one has.
- Pixel 5 ABL behaviour with a mainline DTB: how vendor_boot and dtbo are handled, and whether `fastboot boot` works with a mainline image.
- Exact camera sensor models. These are from public specs, not from the DT, because the downstream DT does not name sensors.
- Whether `st-nci` supports redfin's ST21NFC part.
- Whether the Heidelberg SMEM socinfo quirk applies to redfin's modem when loaded through `qcom_q6v5_pas`.
- Exact firmware file names and partitions on a redfin image.
- Whether 5G NR registers under ModemManager on any SM7250 mainline port. nairo reports LTE only.
- The postmarketOS → "Nura" rename. I only observed that `gitlab.postmarketos.org` and `wiki.postmarketos.org` redirect to `*.nura.eco`, where the project is titled "Nura". I did not research the context.
- lore.kernel.org blocked automated fetches (Anubis), so mailing-list data came from patchwork's API and the ratatoskr.run mirror. Upstream status ("pending", "in-next") reflects patchwork state as of 2026-11-18.

## Sources

- linux-next next-20261118, checked out at `(local scratch checkout, not kept) next`, and torvalds/linux master (7.4-rc3) via the GitHub API.
- Downstream DT: [LineageOS/android_kernel_google_redbull](https://github.com/LineageOS/android_kernel_google_redbull), checked out at `(local scratch checkout, not kept) redbull` (`arch/arm64/boot/dts/google/`).
- [Patchwork linux-arm-msm "SM7250"](https://patchwork.kernel.org/project/linux-arm-msm/list/?q=SM7250); [SM7250 base v15 (ratatoskr)](https://ratatoskr.run/linux-arm-msm/2026/11/17942053/t); [SM7250 base v9](https://ratatoskr.run/linux-devicetree/2026/09/17490576/t); [Ishu Brar DPU v2 cover](https://patch.msgid.link/20261112-dpu-sm7250-v2-0-8e925a3a8a7d@brar.si); [UBWC SM7250](https://lore.kernel.org/all/20261027-ubwc-sm7250-v1-1-e766b1e264cf@brar.si/); [Pixel modem socinfo patch](https://patchwork.kernel.org/project/linux-arm-msm/patch/20261116-modemsmem-v3-2-24ebc7ed6eb9@ixit.cz/)
- [effeffe/nairoArchLinuxArmTools](https://github.com/effeffe/nairoArchLinuxArmTools); [nairo blog post source](https://github.com/effeffe/effeffe.github.io/blob/HEAD/_posts/2026-10-04-mainline-linux-moto-g-5g-plus.md)
- [lazybrar/avicii-mainline](https://github.com/lazybrar/avicii-mainline)
- [sm7250-mainline/docs](https://github.com/sm7250-mainline/docs), [sm7250-mainline/linux_kernel](https://github.com/sm7250-mainline/linux_kernel)
- [yinnho/aginxos](https://github.com/yinnho/aginxos) (Pixel 5, downstream kernel)
- pmaports: [MR !9754 google-bramble (closed)](https://gitlab.nura.eco/nura/pmaports/-/merge_requests/9754); wiki [google-redfin](https://wiki.postmarketos.org/wiki/Google_Pixel_5_(google-redfin)), [google-bramble](https://wiki.postmarketos.org/wiki/Google_Pixel_4a_(5G)_(google-bramble)) (both stubs)
- Mesa [`freedreno_devices.py`](https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/src/freedreno/common/freedreno_devices.py) (`GPUId(620)` present in mesa-24.0.9 onward)
