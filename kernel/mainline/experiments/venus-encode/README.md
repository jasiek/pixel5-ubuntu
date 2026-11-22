<!-- SPDX-License-Identifier: MIT -->
# Venus H.264 encoding on SM7250: proof of concept (Tests 235-248)

Not a patch. It shows why the IRIS1 encoder stalled or reset the SoC
(Tests 214-234) and that hardware encoding works once that is handled.

## Cause

The encoder's CVP core reads its register-program table from the session's
`HFI_BUFFER_INTERNAL_PERSIST` buffer through the *secure non-pixel* SMMU stream
(0x1384, in downstream's `venus_sec_non_pixel` bank `<0x1304 0xe0>`, VMID 0xB),
even in a non-secure session. Mainline has no stream match for it: the SoC
freezes at the first frame and resets about 6 s later. Downstream allocates
encoder PERSIST buffers as `ION_FLAG_SECURE | ION_FLAG_CP_NON_PIXEL`
(`msm_smem.c` `alloc_dma_mem()`). Decoding never uses the CVP core.

## Parts

- `enc-base.py`, `sec.py`, `enc-sec.py`: edits to the venus sources (run inside
  `drivers/media/platform/qcom/venus`, `EXP=<this dir>`). `enc-sec.py` is the
  working combination: encoder on, vcodec1 powered with vcodec0 under hardware
  control (mainline flow), and encoder PERSIST pages handed to VMID 0xB alone
  (`qcom_scm_assign_mem`), mapped in the `venus-sec-np` domain from IOVA
  0x10000000, with that domain's page-table pages shared {HLOS RW, 0xB R}.
- `sec-nodes.dtsi`: the three nodes added to the encoder test DTB (plus the
  pre-0045 venus node: MVS1 domain and clocks, `video-encoder` child).
- `seccb/`: module binding those nodes and sharing each domain's top-level
  page table with its VMID (its S2CR rewrite is redundant).
- `paniccast/`: on panic, broadcasts the kernel log tail as UDP over `usb0`
  (`pcrecv.py` receives it on the Mac). Proved these resets are not panics.
- `encbench.sh`: the benchmark (runs on the phone).

## Result (Test 248, reproduced from Test 247)

300 frames of NV12 from a file, start-up included: 720p in 1.37-1.51 s
(198-219 fps, CPU 1.1-1.3 s; x264 veryfast 107-113 fps, CPU 8.6-8.9 s),
1080p in 1.94-1.98 s (151-154 fps, CPU 1.2-1.4 s; x264 63 fps, CPU 17.4 s).
The 1080p stream decodes with libavcodec (Y PSNR 68-89 dB on the test
pattern) and with the Venus decoder.

## Left for a real implementation

A secure non-pixel context bank in the Venus binding and driver, PERSIST
allocated from it for IRIS1 encoder sessions, patch 0015 and the DT back to
encoder + vcodec1, and no `DBG` prints or fixed IOVA allocator.
