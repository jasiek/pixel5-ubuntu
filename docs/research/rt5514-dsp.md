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

## Result (Tests 166-173): it works

- SE4 SPI needs GPI DMA (`gpi_dma0`, the SM6350 block; SE4's FIFO is off).
- On that path, **receive-only SPI transfers return zeros**; duplex and
  transmit-only work (Test 171). rt5514-spi reads full-duplex: one
  transfer of command, address, 4 dummy bytes and the data (patch 0009).
  Root cause in spi-geni-qcom not investigated: a candidate upstream bug.
- The handshake (Test 168) and the rails (Test 169) were never the cause;
  downstream reads the chip with the same hardware (Test 170).
- In DSP mode the firmware owns the interface: it sets PLL2 from BCLK
  and the DMIC clock in CLK_CTRL1. The codec must not apply the machine
  driver's fmt/sysclk/pll/tdm calls, and must not write registers from
  its cache (DAPM update_bits restored the default DMIC divider and the
  mics gave LSB noise). Patch 0010 (Test 172).
- At boot the first load fails about every second time and leaves the
  chip reading zeros on I2C; a reset (TLMM 91) recovers it. The driver
  resets and retries (Test 173). Cause unknown; it may be the ADSP sensor
  stack starting at the same time.

Open: the capture is mono duplicated to two channels (DSP buffer
0x18002fcc = 1); the second microphone, gain controls and wake-word
features are not explored.
