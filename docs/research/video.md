<!-- SPDX-License-Identifier: MIT -->
# Video codec (Venus) on SM7250 / redfin

Research for hardware video encoding, 2026-11-21. Sources: downstream
`lito-vidc.dtsi`, `lito.dtsi` (`qcom,venus@aae0000`), `lito-gdsc.dtsi`,
`drivers/clk/qcom/videocc-lito.c`, `techpack/video/msm/vidc`; mainline
next-20261021 (`videocc-sm8150.c`, `venus/`, `iris/`); the phone's
`/vendor/firmware/venus.*`.

## Hardware

- Codec core: **IRIS1, 2 VPP pipes** (`lito_data`: `VPU_VERSION_IRIS1`,
  `num_vpp_pipes = 2`), the SM8150 generation. Not IRIS2 (SM8250) or
  IRIS2_1 (SC7280).
- Firmware: `venus.mdt` + `.b00-.b04` in vendor, `QC_IMAGE_VERSION_STRING=
  VIDEO.IR.1.2-00068-PROD-2`, loaded by TZ as PAS id 9 into `video_mem`
  (`0x86a00000`, 5 MB, already reserved in nairo's `sm7250.dtsi`).
- Registers `0xaa00000`, IRQ SPI 174. IRIS1 uses the old register layout
  (`CPU_BASE` 0xc0000, wrapper 0xe0000), the same as mainline's AR50 path
  (sdm845-v2, sc7180), not the V6 layout of IRIS2.
- Power: GDSCs `mvsc` (0xab00814, control), `mvs0` (0xab00874, codec,
  HW-trigger), `mvs1` (0xab008b4, CVP, HW-trigger); videocc on CX.
- Clocks used by the vidc node: `mvsc_core` (core), `venus_ahb` (iface),
  `mvsc_ctl_axi`, `mvs0_core`, `mvs0_axi`, plus `mvs1_*` for CVP. Core
  rates 240/338/365 MHz on SKU 0 (the `iris-bin` fuse can cap a part at
  365 MHz, or at 200 MHz with one pipe); CX corners from `rate_max`: 240
  low-SVS, 338 SVS, 365 SVS-L1, 444 nominal, 533 turbo.
- IOMMU, non-secure context bank: SIDs `0x1380` mask `0x60` and `0x1360`.
  Content protection: `cp_size` = non-secure pool start `0x25800000`,
  non-pixel `0x1000000` + `0x24800000`.
- Firmware start (downstream PIL): TZ is asked to authenticate and reset
  only while `mvsc_gdsc` is on, `video_cc_xo` and `mvsc_core` run at
  240 MHz and a DDR vote VIDEO_P0 -> EBI of 304 MB/s is held. The other
  SM7250 ports report TZ refusing Venus (`-EINVAL`), as it refused the CDSP
  until we added its bus vote (Test 184).

## Clock controller

Mainline has no SM7250 videocc. **SM8150's (`videocc-sm8150.c`) has the
same register layout**: PLL0 at 0x42c, `iris_clk_src` 0x7f0, `mvs0/mvs1/
mvsc_core` 0x890/0x8d0/0x850, GDSCs 0x814/0x874/0x8b4, max register 0xb94.
Lito differs: Lucid PLL (mainline drives it with the Trion code) with
other config values (L 0x19, config_ctl_hi 0x2261, hi1 0x329a699c,
user_ctl 0x1, test_ctl_hi1 0x01800000), a 240-533 MHz table, extra
branches (`mvs0/mvs1_axi` 0x9ec/0xa0c, `mvsc_ctl_axi` 0x9cc, `venus_ahb`
0xa6c, `apb` 0xa4c, `xo` 0x980 critical, `sleep` 0x9a4), no `iris_ahb`, and
the interface BCR at 0x9ac. SM8150's "keep XO on" write to 0x984 would hit
lito's sleep clock RCG instead, so a separate driver is needed.

## Drivers

- `venus`: supports AR50 (HFI 4xx) and IRIS2/IRIS2_1 (HFI 6xx); the
  `VPU_VERSION_IRIS1` enum exists but no platform uses it. Its non-IRIS2
  branches (register bases, ARM9 reset, `CGC_DIS`/`CLOCK_CONFIG` writes)
  match downstream's IRIS1 "common" ops.
- `iris`: sm8250 and sc7280 (VPU2, HFI Gen1), qcm2290 (AR50-lite), newer
  Gen2 parts; no IRIS1.

Plan: a `videocc-sm7250` driver; a `qcom,sm7250-venus` entry in `venus`
modelled on sc7180 (AR50 register path, HFI 4xx first; HFI 6xx with an
IRIS1 entry if the firmware disagrees); DT nodes in the board DTS. All of
it builds as modules, so most iterations are a module copy.
