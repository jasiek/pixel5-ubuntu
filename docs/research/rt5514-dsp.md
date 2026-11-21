<!-- SPDX-License-Identifier: MIT -->
# RT5514 microphones: what a mainline port needs (scoping, 2026-11-21)

Status: not started. Plain capture (mainline path) gives exact zeros
(docs/log.md Tests 149-153); this note lists what downstream does instead.

## Downstream facts

- Google's driver (`external/kernel-redbull/sound/soc/codecs/rt5514.c`,
  about 2500 lines, not the upstream driver) forces the RT5514 DSP on for
  every recording in `rt5514_hw_params()`: `dsp_enabled = 3`,
  `dsp_adc_enabled = 1`, then writes `RT5514_DSP_FUNC` (0x18002fb0) =
  `RT5514_DSP_FUNC_WOV_I2S_SENSOR` (3). Its plain-ADC branch is never reached.
- DSP firmware: `rt5514_dsp_fw1.bin` / `rt5514_dsp_fw2.bin` in
  /vendor/firmware, loaded over SPI.
- SPI: QUP0 SE4 (`qupv3_se4_spi`, spi@890000), chip select 0, 10 MHz
  (20 MHz on the RT5514P variant), cpol + cpha. Node `mnh-spi@0`,
  compatible `realtek,rt5514`.
- GPIOs: IRQ TLMM 65, handshake TLMM 66 (out), handshake-ack TLMM 11 (in,
  IRQ). The driver toggles the handshake around SPI transfers
  (`rt5514_spi_request_switch`), shared with the sensor hub (CHRE).
- `rt5514_enable_dsp_prepare()` has two register sequences, for the
  RT5514P (`v_p`) and the plain RT5514; which one this phone has is not
  known yet (read the variant register before choosing).

## Mainline facts

- `rt5514.c` already loads fw1/fw2 over SPI (`rt5514_spi_burst_write` to
  0x4ff60000 / 0x4ffc0000) when the "DSP Voice Wake Up" control is set,
  for hotword buffering on Chromebooks. It never selects an I2S DSP
  function.
- `rt5514-spi.c` (`realtek,rt5514` on SPI) reads the hotword buffer; no
  handshake GPIOs.

## Likely shape of a port (unproven)

1. DT: QUP0 SE4 SPI node with the RT5514 SPI device and the IRQ pin.
2. Local driver patch: on capture hw_params, load the DSP firmware (as
   "DSP Voice Wake Up" does), then write `RT5514_DSP_FUNC` = 3 (or 5,
   `DSP_FUNC_I2S`) as downstream does.
3. Find out whether the handshake GPIOs matter without the sensor hub
   using the same SPI link.
4. One step per test image; first check whether fw load over SPI works at all.

## Results so far (Tests 166-167)

- DT for SE4 and its GPI DMA works at the bus level (`gpi_dma0` is the
  SM6350 block; SE4's FIFO is off, so DMA is required).
- The RT5514 never answers over SPI: reads give zeros, even for the ID
  register, in every SPI mode and with GPIO5 low, high or untouched.
- WIP driver code: `kernel/mainline/patches/wip/0009-...` (not in the
  series; module parameters `rt5514 spi_switch=`, `rt5514-spi mode= hz=`).

## Next leads

1. The handshake: drive TLMM 66 low, then high, and watch TLMM 11 (the
   CHRE's ack, falling edge). If the ADSP never answers, the sensor
   firmware may own the switch or the RT5514 SPI port.
2. Whether the ADSP sensor stack (`pixel5-see`) opens the RT5514 SPI link
   itself (downstream CHRE "SPI_SWITCH_MASK_CHRE_QMI").
3. Scope or logic probe on the SE4 lines, if the owner has one: shows
   whether CS and SCLK toggle and whether MISO ever moves.

